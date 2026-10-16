#Update-*OS functions of AllFunctions.ps1: updates applied to the mounted install.wim ($MountDirectory)
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}

    $SessionsXmlFixture = Join-Path (Join-Path $FixturesPath 'AllFunctionsUpdate') 'Sessions.xml'

    function New-UpdateItem {
        param ($Group, $Title, $KB, $FileKB, $Date = '2026-10-14', $Extension = 'msu', $Os = 'windows10.0')
        $FileName = if ($FileKB) {$FileKB} else {$KB}
        [PSCustomObject]@{
            UpdateGroup     = $Group
            Title           = $Title
            KBNumber        = $KB
            FileKBNumber    = $FileKB
            CreationDate    = $Date
            OriginUri       = "https://catalog.invalid/$Os-kb$($FileName)-x64_0123456789abcdef.$Extension"
        }
    }

    #Creates the downloaded file of each update in $Path
    function New-UpdateFile ($Path, $Update) {
        foreach ($Item in $Update) {New-TestFile -Path (Join-Path $Path (Split-Path $Item.OriginUri -Leaf)) | Out-Null}
    }

    #Copies the Sessions.xml fixture to <Mount>\Windows\Servicing\Sessions
    function Copy-SessionsXml ($Mount) {
        $Destination = Join-Path (Join-Path (Join-Path (Join-Path $Mount 'Windows') 'Servicing') 'Sessions') 'Sessions.xml'
        New-Item -Path (Split-Path $Destination -Parent) -ItemType Directory -Force | Out-Null
        Copy-Item -Path $SessionsXmlFixture -Destination $Destination -Force
        $Destination
    }
}

Describe 'Update-AdobeOS' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'Adobe'
        $MountDirectory = 'C:\Mount'; $Info = 'C:\Info'; $OSMajorVersion = 10
        $SkipUpdates = $false; $SkipUpdatesOS = $false
        $OSDUpdateAdobeSU = @(
            New-UpdateItem 'AdobeSU' 'Security Update for Adobe Flash Player (KB4580325)' '4580325' '4580325'
            New-UpdateItem 'AdobeSU' 'Security Update for Adobe Flash Player (KB4561600)' '4561600' '4561600'
        )
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateAdobeSU
        $script:Installed = New-Object System.Collections.Generic.List[string]
        Mock Show-ActionTime {}
        Mock Get-SessionsXml {}
        Mock Get-WindowsPackage {}
        Mock Add-WindowsPackage {$script:Installed.Add((Split-Path $PackagePath -Leaf))}
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'SkipUpdatesOS'; Value = $true}
        @{Variable = 'OSMajorVersion'; Value = 6}
        @{Variable = 'OSDUpdateAdobeSU'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Update-AdobeOS 6>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'installs every Adobe update in list order to the mounted image with a KB log' {
        $Output = (Update-AdobeOS 6>&1) -join "`n"
        $script:Installed.Count | Should -Be 2
        $script:Installed[0] | Should -BeLike '*kb4580325*'
        $script:Installed[1] | Should -BeLike '*kb4561600*'
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {
            ($Path -eq 'C:\Mount') -and ($PackagePath -eq (Join-Path $SetOSDBuilderPathUpdates 'windows10.0-kb4580325-x64_0123456789abcdef.msu')) -and ($LogPath -like 'C:\Info\logs\*-Update-AdobeOS-KB4580325.log')
        }
        $Output | Should -BeLike '*OS: (ASU) Adobe Flash Player Security Update*'
        $Output | Should -Not -BeLike '*(Forced)*'
    }

    It 'skips an update that Sessions.xml lists as installed' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}} -ParameterFilter {$KBNumber -eq '4580325'}
        Update-AdobeOS 6>$null
        $script:Installed | Should -Be @('windows10.0-kb4561600-x64_0123456789abcdef.msu')
        Should -Invoke Get-SessionsXml -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and ($KBNumber -eq '4580325')}
    }

    It 'does not skip an update that Sessions.xml lists with another TargetState' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Absent'}}
        Update-AdobeOS 6>$null
        $script:Installed.Count | Should -Be 2
    }

    It 'skips an update that Get-WindowsPackage returns' {
        Mock Get-WindowsPackage {[PSCustomObject]@{PackageName = 'Package_for_KB4561600~31bf3856ad364e35~amd64~~10.0.1.0'}}
        Update-AdobeOS 6>$null
        $script:Installed | Should -Be @('windows10.0-kb4580325-x64_0123456789abcdef.msu')
    }

    It 'reinstalls installed updates without checking with -Force' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}}
        $Output = (Update-AdobeOS -Force 6>&1) -join "`n"
        $script:Installed.Count | Should -Be 2
        Should -Invoke Get-SessionsXml -Times 0 -Exactly
        Should -Invoke Get-WindowsPackage -Times 0 -Exactly
        $Output | Should -BeLike '*Adobe Flash Player Security Update (Forced)*'
    }

    It 'warns and continues when the update file was not downloaded' {
        Remove-Item -Path (Join-Path $SetOSDBuilderPathUpdates 'windows10.0-kb4580325-x64_0123456789abcdef.msu')
        $Warnings = (Update-AdobeOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Update-AdobeOS is Null*'
        $script:Installed | Should -Be @('windows10.0-kb4561600-x64_0123456789abcdef.msu')
    }

    It 'warns and continues when the update file cannot be found' {
        Mock Test-Path {$false} -ParameterFilter {$Path -like '*kb4580325*'}
        $Warnings = (Update-AdobeOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Update-AdobeOS was not found*'
        $script:Installed | Should -Be @('windows10.0-kb4561600-x64_0123456789abcdef.msu')
    }

    It 'reports 0x800f081e as not applicable and continues with the next update' {
        Mock Add-WindowsPackage {throw 'Add-WindowsPackage failed. Error code = 0x800f081e'}
        $Verbose = (Update-AdobeOS 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*Review the log for more information*'
        $Verbose | Should -BeLike '*-Update-AdobeOS-KB4561600.log*'
        Should -Invoke Add-WindowsPackage -Times 2 -Exactly
    }

    It 'reports other errors with the log only' {
        Mock Add-WindowsPackage {throw 'Add-WindowsPackage failed. Error code = 0x80070005'}
        $Verbose = (Update-AdobeOS 6>$null 4>&1) -join "`n"
        $Verbose | Should -Not -BeLike '*0x800f081e*'
        $Verbose | Should -BeLike '*Review the log for more information*'
    }
}

Describe 'Update-ComponentOS' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'Component'
        $MountDirectory = 'C:\Mount'; $Info = 'C:\Info'
        $SkipUpdates = $false; $SkipUpdatesDUC = $false; $SkipUpdatesOS = $false
        $OSDUpdateComponentDU = @(
            New-UpdateItem 'ComponentDU Critical' '2026-10 Dynamic Update for Windows 10 Version 22H2 (KB5000001)' '5000001' '5000001' -Extension 'cab'
            New-UpdateItem 'ComponentDU SafeOS' '2026-10 Safe OS Dynamic Update for Windows 10 Version 22H2 (KB5000002)' '5000002' '5000002' -Extension 'cab'
            New-UpdateItem 'ComponentDU Critical' '2026-09 Dynamic Update for Windows 10 Version 22H2 (KB5000003)' '5000003' '5000003' -Extension 'cab'
        )
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateComponentDU
        $script:Installed = New-Object System.Collections.Generic.List[string]
        Mock Show-ActionTime {}
        Mock Get-SessionsXml {}
        Mock Get-WindowsPackage {}
        Mock Add-WindowsPackage {$script:Installed.Add((Split-Path $PackagePath -Leaf))}
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'SkipUpdatesDUC'; Value = $true}
        @{Variable = 'SkipUpdatesOS'; Value = $true}
        @{Variable = 'OSDUpdateComponentDU'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Update-ComponentOS 6>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'installs the Component Dynamic Updates except Safe OS in list order with a KB log' {
        $Output = (Update-ComponentOS 6>&1) -join "`n"
        $script:Installed | Should -Be @('windows10.0-kb5000001-x64_0123456789abcdef.cab', 'windows10.0-kb5000003-x64_0123456789abcdef.cab')
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and ($LogPath -like 'C:\Info\logs\*-Update-ComponentOS-KB5000003.log')}
        $Output | Should -BeLike '*OS: Component Update*'
        $Output | Should -Not -BeLike '*(Forced)*'
    }

    It 'skips updates that Sessions.xml or Get-WindowsPackage report as installed' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}} -ParameterFilter {$KBNumber -eq '5000001'}
        Mock Get-WindowsPackage {[PSCustomObject]@{PackageName = 'Package_for_KB5000003~31bf3856ad364e35~amd64~~19041.1.1.0'}}
        $Output = (Update-ComponentOS 6>&1) -join "`n"
        $script:Installed.Count | Should -Be 0
        $Output | Should -BeLike '*INSTALLED*KB5000001*'
        $Output | Should -BeLike '*INSTALLED*KB5000003*'
    }

    It 'reinstalls with -Force without checking the image' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}}
        $Output = (Update-ComponentOS -Force 6>&1) -join "`n"
        $script:Installed.Count | Should -Be 2
        Should -Invoke Get-SessionsXml -Times 0 -Exactly
        $Output | Should -BeLike '*OS: Component Update (Forced)*'
    }

    It 'warns when the update file is missing or cannot be found' {
        Remove-Item -Path (Join-Path $SetOSDBuilderPathUpdates 'windows10.0-kb5000001-x64_0123456789abcdef.cab')
        Mock Test-Path {$false} -ParameterFilter {$Path -like '*kb5000003*'}
        $Warnings = (Update-ComponentOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Update-ComponentOS is Null*'
        $Warnings | Should -BeLike '*Update-ComponentOS was not found*'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'reports 0x800f081e as not applicable with the log' {
        Mock Add-WindowsPackage {throw 'Add-WindowsPackage failed. Error code = 0x800f081e'}
        $Verbose = (Update-ComponentOS 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*Review the log for more information*'
        $Verbose | Should -BeLike '*-Update-ComponentOS-KB5000001.log*'
    }
}

Describe 'Update-CumulativeOS' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'LCU'
        $MountDirectory = 'C:\Mount'; $Info = 'C:\Info'; $OSMajorVersion = 10
        $OSImageName = 'Windows 10 Enterprise'; $ReleaseID = '22H2'
        $SkipUpdates = $false; $SkipUpdatesOS = $false; $SkipUpdatesOSLCU = $false
        $OSDUpdateLCU = @(New-UpdateItem 'LCU' '2026-10 Cumulative Update for Windows 10 Version 22H2 (KB5066791)' '5066791' '5066791')
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateLCU
        $script:Installed = New-Object System.Collections.Generic.List[string]
        Mock Show-ActionTime {}
        Mock Get-SessionsXml {}
        Mock Test-WindowsPackageCAB {'MSU'}
        Mock Add-WindowsPackage {$script:Installed.Add($PackagePath)}
        Mock Add-WindowsPackageSSU {}
        Mock Get-WindowsImage {
            [PSCustomObject]@{Path = 'C:\Other'; ImagePath = 'C:\Other\install.wim'; ImageIndex = 1}
            [PSCustomObject]@{Path = 'C:\Mount'; ImagePath = 'C:\OSMedia\OS\sources\install.wim'; ImageIndex = 3}
        }
        Mock Dismount-WindowsImage {}
        Mock Mount-WindowsImage {}
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'SkipUpdatesOS'; Value = $true}
        @{Variable = 'SkipUpdatesOSLCU'; Value = $true}
        @{Variable = 'OSMajorVersion'; Value = 6}
        @{Variable = 'OSDUpdateLCU'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Update-CumulativeOS 6>$null 4>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'installs the LCU with the type returned by Test-WindowsPackageCAB and a KB log' {
        $Output = (Update-CumulativeOS 6>&1 4>$null) -join "`n"
        $script:Installed | Should -Be @(Join-Path $SetOSDBuilderPathUpdates 'windows10.0-kb5066791-x64_0123456789abcdef.msu')
        Should -Invoke Test-WindowsPackageCAB -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and ($PackagePath -like '*kb5066791*')}
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and ($LogPath -like 'C:\Info\logs\*-Update-CumulativeOS-KB5066791.log')}
        Should -Invoke Add-WindowsPackageSSU -Times 0 -Exactly
        $Output | Should -BeLike '*OS: (LCU) Latest Cumulative Update*'
        $Output | Should -Not -BeLike '*(Forced)*'
    }

    It 'installs the LCUs sorted by date and KB number' {
        $OSDUpdateLCU = @(
            New-UpdateItem 'LCU' '2026-10 LCU' '5066791' '5066791' '2026-10-14'
            New-UpdateItem 'LCU' '2026-09 LCU' '5065429' '5065429' '2026-09-09'
            New-UpdateItem 'LCU' '2026-10 LCU - Checkpoint' '5066791' '5043080' '2026-10-14'
        )
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateLCU
        Update-CumulativeOS 6>$null 4>$null
        ($script:Installed | ForEach-Object {Split-Path $_ -Leaf}) | Should -Be @(
            'windows10.0-kb5065429-x64_0123456789abcdef.msu'
            'windows10.0-kb5043080-x64_0123456789abcdef.msu'
            'windows10.0-kb5066791-x64_0123456789abcdef.msu'
        )
    }

    It 'skips an LCU that Sessions.xml lists as installed' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}} -ParameterFilter {($Path -eq 'C:\Mount') -and ($KBNumber -eq '5066791')}
        $Output = (Update-CumulativeOS 6>&1 4>$null) -join "`n"
        $script:Installed.Count | Should -Be 0
        $Output | Should -BeLike '*INSTALLED*2026-10 Cumulative Update*kb5066791*'
    }

    It 'reapplies an installed LCU with -Force' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}}
        $Output = (Update-CumulativeOS -Force 6>&1 4>$null) -join "`n"
        $script:Installed.Count | Should -Be 1
        Should -Invoke Get-SessionsXml -Times 0 -Exactly
        $Output | Should -BeLike '*Latest Cumulative Update (Forced)*'
    }

    It 'warns when the LCU file is missing or cannot be found' {
        $OSDUpdateLCU = @($OSDUpdateLCU) + @(New-UpdateItem 'LCU' 'Missing LCU' '5000009' '5000009')
        Mock Test-Path {$false} -ParameterFilter {$Path -like '*kb5066791*'}
        $Warnings = (Update-CumulativeOS 6>$null 4>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Update-CumulativeOS is Null*'
        $Warnings | Should -BeLike '*Update-CumulativeOS was not found*'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    Context 'Windows 11 22H2 (RPC/DISM workaround)' {
        BeforeEach {
            $OSImageName = 'Windows 11 Enterprise'; $ReleaseID = '22H2'
            $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'LCU22H2'
            $OSDUpdateLCU = @(New-UpdateItem 'LCU' '2026-10 Cumulative Update for Windows 11 Version 22H2 (KB5066793)' '5066793' '5066793' -Extension 'cab' -Os 'windows11.0')
            if (Test-Path $SetOSDBuilderPathUpdates) {Remove-Item -Path $SetOSDBuilderPathUpdates -Recurse -Force}
            New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateLCU
            $Cab = Join-Path $SetOSDBuilderPathUpdates 'windows11.0-kb5066793-x64_0123456789abcdef.cab'
            $Msu = Join-Path $SetOSDBuilderPathUpdates 'windows11.0-kb5066793-x64_0123456789abcdef.msu'
        }

        It 'copies the combined LCU to an .msu and installs the .msu without Test-WindowsPackageCAB' {
            $Verbose = (Update-CumulativeOS 6>$null 4>&1) -join "`n"
            Test-Path $Msu | Should -BeTrue
            $script:Installed | Should -Be @($Msu)
            Should -Invoke Test-WindowsPackageCAB -Times 0 -Exactly
            $Verbose | Should -BeLike '*Applying Combined LCU as an MSU Package*'
        }

        It 'uses an existing .msu without copying' {
            Set-Content -Path $Msu -Value 'existing'
            Mock Copy-Item {}
            Update-CumulativeOS 6>$null 4>$null
            Should -Invoke Copy-Item -Times 0 -Exactly
            Get-Content -Path $Msu | Should -Be 'existing'
            $script:Installed | Should -Be @($Msu)
        }

        It 'installs the .cab when the .msu cannot be created' {
            Mock Copy-Item {}
            $Verbose = (Update-CumulativeOS 6>$null 4>&1) -join "`n"
            $script:Installed | Should -Be @($Cab)
            $Verbose | Should -Not -BeLike '*Applying Combined LCU as an MSU Package*'
        }
    }

    It 'splits a CombinedLCU: installs the SSU, saves and remounts the image, then installs the LCU' {
        Mock Test-WindowsPackageCAB {'CombinedLCU'}
        $script:Order = New-Object System.Collections.Generic.List[string]
        Mock Add-WindowsPackageSSU {$script:Order.Add('SSU')}
        Mock Dismount-WindowsImage {$script:Order.Add('Dismount')}
        Mock Mount-WindowsImage {$script:Order.Add('Mount')}
        Mock Add-WindowsPackage {$script:Order.Add('LCU')}
        Update-CumulativeOS 6>$null 4>$null
        $script:Order | Should -Be @('SSU', 'Dismount', 'Mount', 'LCU')
        Should -Invoke Add-WindowsPackageSSU -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and ($PackagePath -like '*kb5066791*') -and ($LogPath -like 'C:\Info\logs\*-Add-WindowsPackageSSU-KB5066791.log')}
        Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {$Mounted}
        Should -Invoke Dismount-WindowsImage -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and $Save}
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and ($ImagePath -eq 'C:\OSMedia\OS\sources\install.wim') -and ($Index -eq 3)}
    }

    It 'reports <Code> with "<Message>"' -ForEach @(
        @{Code = '0x800f081e'; Message = '0x800f081e The package is not applicable to this image'}
        @{Code = '0x800f0998'; Message = '0x800f0998 The package may require an SSU installed first'}
        @{Code = '0x8007007b'; Message = '0x8007007b This is a bug that Manel Rodero first spotted'}
        @{Code = '0x80070005'; Message = 'Review the log for more information'}
    ) {
        Mock Add-WindowsPackage {throw "Add-WindowsPackage failed. Error code = $Code"}
        $Verbose = (Update-CumulativeOS 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike "*OSDBuilder: $Message*"
        $Verbose | Should -BeLike '*-Update-CumulativeOS-KB5066791.log*'
    }
}

Describe 'Update-DotNetOS' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'DotNet'
        $MountDirectory = 'C:\Mount'; $Info = 'C:\Info'; $OSMajorVersion = 10
        $SkipUpdates = $false; $SkipUpdatesOS = $false
        $OSDUpdateDotNet = @(
            New-UpdateItem 'DotNetCU' '2026-10 Cumulative Update for .NET Framework 3.5 and 4.8.1 (KB5066999)' '5066999' '5066999'
            New-UpdateItem 'DotNet' '.NET Framework 4.8.1 (KB5011048)' '5011048' '5011048'
            New-UpdateItem 'DotNet' '.NET Framework 4.8 (KB4486153)' '4486153' '4486153'
            New-UpdateItem 'LCU' '2026-10 Cumulative Update (KB5066791)' '5066791' '5066791'
        )
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateDotNet
        $script:Installed = New-Object System.Collections.Generic.List[string]
        Mock Show-ActionTime {}
        Mock Get-SessionsXml {}
        Mock Get-WindowsPackage {}
        Mock Add-WindowsPackage {$script:Installed.Add((Split-Path $PackagePath -Leaf))}
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'SkipUpdatesOS'; Value = $true}
        @{Variable = 'OSMajorVersion'; Value = 6}
        @{Variable = 'OSDUpdateDotNet'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Update-DotNetOS 6>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'installs the .NET Framework updates sorted by KB number before the .NET CU and ignores other groups' {
        $Output = (Update-DotNetOS 6>&1) -join "`n"
        $script:Installed | Should -Be @(
            'windows10.0-kb4486153-x64_0123456789abcdef.msu'
            'windows10.0-kb5011048-x64_0123456789abcdef.msu'
            'windows10.0-kb5066999-x64_0123456789abcdef.msu'
        )
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and ($LogPath -like 'C:\Info\logs\*-Update-DotNetOS-KB5066999.log')}
        $Output | Should -BeLike '*OS: (NetCU) DotNet Framework Cumulative Update*'
        $Output | Should -Not -BeLike '*(Forced)*'
    }

    It 'reinstalls with -Force without checking the image' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}}
        $Output = (Update-DotNetOS -Force 6>&1) -join "`n"
        $script:Installed.Count | Should -Be 3
        Should -Invoke Get-SessionsXml -Times 0 -Exactly
        Should -Invoke Get-WindowsPackage -Times 0 -Exactly
        $Output | Should -BeLike '*DotNet Framework Cumulative Update (Forced)*'
    }

    Context '<Group> updates' -ForEach @(
        @{Group = 'DotNet'; KB = '5011048'}
        @{Group = 'DotNetCU'; KB = '5066999'}
    ) {
        It 'skips the update when Sessions.xml lists it as installed' {
            Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}} -ParameterFilter {$KBNumber -eq $KB}
            Update-DotNetOS 6>$null
            $script:Installed.Count | Should -Be 2
            $script:Installed | Should -Not -Contain "windows10.0-kb$KB-x64_0123456789abcdef.msu"
        }

        It 'skips the update when Get-WindowsPackage returns it' {
            Mock Get-WindowsPackage {[PSCustomObject]@{PackageName = "Package_for_KB$KB~31bf3856ad364e35~amd64~~10.0.1.0"}}
            Update-DotNetOS 6>$null
            $script:Installed.Count | Should -Be 2
            $script:Installed | Should -Not -Contain "windows10.0-kb$KB-x64_0123456789abcdef.msu"
        }

        It 'warns when the update file is missing' {
            Remove-Item -Path (Join-Path $SetOSDBuilderPathUpdates "windows10.0-kb$KB-x64_0123456789abcdef.msu")
            $Warnings = (Update-DotNetOS 6>$null 3>&1) -join "`n"
            $Warnings | Should -BeLike '*Update-DotNetOS is Null*'
            $script:Installed.Count | Should -Be 2
        }

        It 'warns when the update file cannot be found' {
            Mock Test-Path {$false} -ParameterFilter {$Path -like "*kb$KB*"}
            $Warnings = (Update-DotNetOS 6>$null 3>&1) -join "`n"
            $Warnings | Should -BeLike '*Update-DotNetOS was not found*'
            $script:Installed.Count | Should -Be 2
        }

        It 'explains 0x8007371b and 0x800f081e' {
            Mock Add-WindowsPackage {throw 'Error code = 0x800f081e'} -ParameterFilter {$PackagePath -notlike "*kb$KB*"}
            Mock Add-WindowsPackage {throw 'Error code = 0x8007371b'} -ParameterFilter {$PackagePath -like "*kb$KB*"}
            $Verbose = (Update-DotNetOS 6>$null 4>&1) -join "`n"
            $Verbose | Should -BeLike '*0x8007371b ERROR_SXS_TRANSACTION_CLOSURE_INCOMPLETE*One or more required members*enable a DotNet Feature like NetFX 3.5*'
            $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
            $Verbose | Should -BeLike "*Review the log for more information*-Update-DotNetOS-KB$KB.log*"
        }
    }
}

Describe 'Update-OptionalOS' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'Optional'
        $MountDirectory = 'C:\Mount'; $Info = 'C:\Info'; $OSMajorVersion = 10; $ScriptName = 'New-OSBuild'
        $SkipUpdates = $false; $SkipUpdatesOS = $false
        $OSDUpdateOptional = @(
            New-UpdateItem 'Optional' 'Update for Windows 10 Version 22H2 (KB5005716)' '5005716' '5005716'
            New-UpdateItem 'Optional' 'Update for Windows 10 Version 22H2 (KB4589212)' '4589212' '4589212'
        )
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateOptional
        $script:Installed = New-Object System.Collections.Generic.List[string]
        Mock Show-ActionTime {}
        Mock Get-SessionsXml {}
        Mock Get-WindowsPackage {}
        Mock Add-WindowsPackage {$script:Installed.Add((Split-Path $PackagePath -Leaf))}
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'ScriptName'; Value = 'Update-OSMedia'}
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'SkipUpdatesOS'; Value = $true}
        @{Variable = 'OSMajorVersion'; Value = 6}
        @{Variable = 'OSDUpdateOptional'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Update-OptionalOS 6>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'installs the optional updates in New-OSBuild in list order with a KB log' {
        $Output = (Update-OptionalOS 6>&1) -join "`n"
        $script:Installed | Should -Be @('windows10.0-kb5005716-x64_0123456789abcdef.msu', 'windows10.0-kb4589212-x64_0123456789abcdef.msu')
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and ($LogPath -like 'C:\Info\logs\*-Update-OptionalOS-KB4589212.log')}
        $Output | Should -BeLike '*OS: Optional Updates*'
    }

    It 'skips updates that Sessions.xml or Get-WindowsPackage report as installed' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}} -ParameterFilter {$KBNumber -eq '5005716'}
        Mock Get-WindowsPackage {[PSCustomObject]@{PackageName = 'Package_for_KB4589212~31bf3856ad364e35~amd64~~19041.1.1.0'}}
        $Output = (Update-OptionalOS 6>&1) -join "`n"
        $script:Installed.Count | Should -Be 0
        $Output | Should -BeLike '*INSTALLED*KB5005716*'
        $Output | Should -BeLike '*INSTALLED*KB4589212*'
    }

    It 'warns when the update file is missing or cannot be found' {
        Remove-Item -Path (Join-Path $SetOSDBuilderPathUpdates 'windows10.0-kb5005716-x64_0123456789abcdef.msu')
        Mock Test-Path {$false} -ParameterFilter {$Path -like '*kb4589212*'}
        $Warnings = (Update-OptionalOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Update-OptionalOS is Null*'
        $Warnings | Should -BeLike '*Update-OptionalOS was not found*'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'reports 0x800f081e as not applicable with the log' {
        Mock Add-WindowsPackage {throw 'Add-WindowsPackage failed. Error code = 0x800f081e'}
        $Verbose = (Update-OptionalOS 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*-Update-OptionalOS-KB5005716.log*'
        Should -Invoke Add-WindowsPackage -Times 2 -Exactly
    }
}

Describe 'Update-ServicingStackOS' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'SSU'
        $MountDirectory = 'C:\Mount'; $Info = 'C:\Info'; $OSMajorVersion = 10
        $SkipUpdates = $false; $SkipUpdatesOS = $false; $SkipUpdatesOSSSU = $false
        $OSDUpdateSSU = @(
            New-UpdateItem 'SSU' '2022-10 Servicing Stack Update for Windows 10 Version 1809 (KB5018506)' '5018506' '5018506'
            New-UpdateItem 'SSU' '2021-01 Servicing Stack Update for Windows 10 Version 1809 (KB4598480)' '4598480' '4598480'
        )
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateSSU
        $script:Installed = New-Object System.Collections.Generic.List[string]
        Mock Show-ActionTime {}
        Mock Get-SessionsXml {}
        Mock Get-WindowsPackage {}
        Mock Add-WindowsPackage {$script:Installed.Add((Split-Path $PackagePath -Leaf))}
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'SkipUpdatesOS'; Value = $true}
        @{Variable = 'SkipUpdatesOSSSU'; Value = $true}
        @{Variable = 'OSMajorVersion'; Value = 6}
        @{Variable = 'OSDUpdateSSU'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Update-ServicingStackOS 6>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'installs the SSUs in list order with a KB log' {
        $Output = (Update-ServicingStackOS 6>&1) -join "`n"
        $script:Installed | Should -Be @('windows10.0-kb5018506-x64_0123456789abcdef.msu', 'windows10.0-kb4598480-x64_0123456789abcdef.msu')
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and ($LogPath -like 'C:\Info\logs\*-Update-ServicingStackOS-KB5018506.log')}
        $Output | Should -BeLike '*OS: (SSU) Servicing Stack Update*'
        $Output | Should -Not -BeLike '*(Forced)*'
    }

    It 'skips SSUs that Sessions.xml or Get-WindowsPackage report as installed' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}} -ParameterFilter {$KBNumber -eq '5018506'}
        Mock Get-WindowsPackage {[PSCustomObject]@{PackageName = 'Package_for_ServicingStack_KB4598480~31bf3856ad364e35~amd64~~17763.1690.1.0'}}
        Update-ServicingStackOS 6>$null
        $script:Installed.Count | Should -Be 0
    }

    It 'reinstalls with -Force without checking the image' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}}
        $Output = (Update-ServicingStackOS -Force 6>&1) -join "`n"
        $script:Installed.Count | Should -Be 2
        Should -Invoke Get-SessionsXml -Times 0 -Exactly
        $Output | Should -BeLike '*Servicing Stack Update (Forced)*'
    }

    It 'warns when the update file is missing or cannot be found' {
        Remove-Item -Path (Join-Path $SetOSDBuilderPathUpdates 'windows10.0-kb5018506-x64_0123456789abcdef.msu')
        Mock Test-Path {$false} -ParameterFilter {$Path -like '*kb4598480*'}
        $Warnings = (Update-ServicingStackOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Update-ServicingStackOS is Null*'
        $Warnings | Should -BeLike '*Update-ServicingStackOS was not found*'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'reports 0x800f081e as not applicable with the log' {
        Mock Add-WindowsPackage {throw 'Add-WindowsPackage failed. Error code = 0x800f081e'}
        $Verbose = (Update-ServicingStackOS 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*Review the log for more information*'
        $Verbose | Should -BeLike '*-Update-ServicingStackOS-KB5018506.log*'
    }
}

Describe 'Update-WindowsServer2012R2OS' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'TwelveR2'
        $MountDirectory = Join-Path $TestDrive 'Mount2012R2'
        $Info = 'C:\Info'; $OSMajorVersion = 6; $ScriptName = 'Update-OSMedia'; $SkipUpdates = $false
        #FileKBNumber $null: the update is checked by KBNumber
        $OSDUpdateWinTwelveR2 = @(
            New-UpdateItem 'Windows Server 2012 R2' 'Servicing stack update for Windows Server 2012 R2 (KB3172729)' '3172729' $null -Os 'windows8.1'
            New-UpdateItem 'Windows Server 2012 R2' '2021-01 Security Monthly Quality Rollup (KB4598285)' '4598285' '4598285' -Os 'windows8.1'
            New-UpdateItem 'Windows Server 2012 R2' '2020-07 Servicing Stack Update (KB4566425)' '4566425' $null -Os 'windows8.1'
            New-UpdateItem 'Windows Server 2012 R2' '2020-08 Security Update (KB4571703)' '4571703' '4571703' -Os 'windows8.1'
        )
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateWinTwelveR2
        if (Test-Path $MountDirectory) {Remove-Item -Path $MountDirectory -Recurse -Force}
        New-Item -Path $MountDirectory -ItemType Directory -Force | Out-Null
        $script:Installed = New-Object System.Collections.Generic.List[string]
        Mock Show-ActionTime {}
        Mock Get-WindowsPackage {}
        Mock Add-WindowsPackage {$script:Installed.Add((Split-Path $PackagePath -Leaf))}
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'ScriptName'; Value = 'New-OSBuild'}
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'OSMajorVersion'; Value = 10}
        @{Variable = 'OSDUpdateWinTwelveR2'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Update-WindowsServer2012R2OS 6>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'skips the updates that Sessions.xml lists as Installed by KBNumber or FileKBNumber' {
        Copy-SessionsXml $MountDirectory | Out-Null
        $Output = (Update-WindowsServer2012R2OS 6>&1) -join "`n"
        $script:Installed | Should -Be @('windows8.1-kb4566425-x64_0123456789abcdef.msu', 'windows8.1-kb4571703-x64_0123456789abcdef.msu')
        $Output | Should -BeLike '*INSTALLED*(KB3172729)*'
        $Output | Should -BeLike '*INSTALLED*(KB4598285)*'
        $Output | Should -BeLike '*OS: Windows Server 2012 R2 Updates*'
    }

    It 'checks the Sessions.xml again by <Check> after reading it for each update' -ForEach @(
        @{Check = 'KBNumber'; Index = 0}
        @{Check = 'FileKBNumber'; Index = 1}
    ) {
        $SessionsXml = Copy-SessionsXml $MountDirectory
        $script:SessionsXmlReads = 0
        $script:FullXml = Get-Content -Path $SessionsXml -Raw
        $script:EmptyXml = '<?xml version="1.0" encoding="utf-8"?><Sessions version="1.0"><Session><Tasks><Phase seq="1"><package name="Package_for_KB1" targetState="Installed" /></Phase></Tasks></Session></Sessions>'
        #1: header (does not list the update yet), 2: reread for the update lists it as Installed
        Mock Get-Content {$script:SessionsXmlReads++; if ($script:SessionsXmlReads -ge 2) {$script:FullXml} else {$script:EmptyXml}} -ParameterFilter {$Path -like '*Sessions.xml'}
        $OSDUpdateWinTwelveR2 = @($OSDUpdateWinTwelveR2[$Index])
        Update-WindowsServer2012R2OS 6>$null
        $script:Installed.Count | Should -Be 0
        Should -Invoke Get-Content -Times 2 -Exactly -ParameterFilter {$Path -like '*Sessions.xml'}
        Should -Invoke Get-WindowsPackage -Times 0 -Exactly
    }

    It 'skips the updates that Get-WindowsPackage returns by KBNumber or FileKBNumber without Sessions.xml' {
        Mock Get-WindowsPackage {
            [PSCustomObject]@{PackageName = 'Package_for_KB3172729~31bf3856ad364e35~amd64~~6.3.1.1'}
            [PSCustomObject]@{PackageName = 'Package_for_KB4571703~31bf3856ad364e35~amd64~~6.3.1.0'}
        }
        Update-WindowsServer2012R2OS 6>$null
        $script:Installed | Should -Be @('windows8.1-kb4598285-x64_0123456789abcdef.msu', 'windows8.1-kb4566425-x64_0123456789abcdef.msu')
        Should -Invoke Get-WindowsPackage -Times 4 -Exactly -ParameterFilter {$Path -eq $MountDirectory}
    }

    It 'installs with a log named after FileKBNumber or KBNumber' {
        Update-WindowsServer2012R2OS 6>$null
        $script:Installed.Count | Should -Be 4
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {($Path -eq $MountDirectory) -and ($PackagePath -like '*kb3172729*') -and ($LogPath -like 'C:\Info\logs\*-Update-WindowsServer2012R2OS-KB3172729.log')}
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {($PackagePath -like '*kb4598285*') -and ($LogPath -like '*-Update-WindowsServer2012R2OS-KB4598285.log')}
    }

    It 'skips missing update files silently and warns when a file cannot be found' {
        Remove-Item -Path (Join-Path $SetOSDBuilderPathUpdates 'windows8.1-kb3172729-x64_0123456789abcdef.msu')
        Mock Test-Path {$false} -ParameterFilter {$Path -like '*kb4598285*'}
        $Warnings = @(Update-WindowsServer2012R2OS 6>$null 3>&1)
        $Warnings.Count | Should -Be 1
        "$($Warnings[0])" | Should -BeLike 'Not Found: *kb4598285*'
        $script:Installed.Count | Should -Be 2
    }

    It 'reports 0x800f081e as not applicable with the log' {
        Mock Add-WindowsPackage {throw 'Add-WindowsPackage failed. Error code = 0x800f081e'}
        $Verbose = (Update-WindowsServer2012R2OS 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*Review the log for more information*-Update-WindowsServer2012R2OS-KB3172729.log*'
        Should -Invoke Add-WindowsPackage -Times 4 -Exactly
    }
}

Describe 'Update-WindowsSevenOS' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'Seven'
        $MountDirectory = Join-Path $TestDrive 'MountSeven'
        $Info = 'C:\Info'; $OSMajorVersion = 6; $ScriptName = 'Update-OSMedia'; $SkipUpdates = $false
        $OSDUpdateWinSeven = @(
            New-UpdateItem 'Windows 7' 'Update for Windows 7 (KB3172729)' '3172729' $null -Os 'windows6.1'
            New-UpdateItem 'Windows 7' '2020-01 Security Monthly Quality Rollup for Windows 7 (KB4598285)' '4598285' '4598285' -Os 'windows6.1'
            New-UpdateItem 'Windows 7' 'Servicing Stack Update for Windows 7 (KB4566425)' '4566425' $null -Os 'windows6.1'
            New-UpdateItem 'Windows 7' 'Security Update for Windows 7 (KB4571703)' '4571703' '4571703' -Os 'windows6.1'
        )
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateWinSeven
        if (Test-Path $MountDirectory) {Remove-Item -Path $MountDirectory -Recurse -Force}
        New-Item -Path $MountDirectory -ItemType Directory -Force | Out-Null
        $script:Installed = New-Object System.Collections.Generic.List[string]
        Mock Show-ActionTime {}
        Mock Get-WindowsPackage {}
        Mock Add-WindowsPackage {$script:Installed.Add((Split-Path $PackagePath -Leaf))}
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'ScriptName'; Value = 'New-OSBuild'}
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'OSMajorVersion'; Value = 10}
        @{Variable = 'OSDUpdateWinSeven'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Update-WindowsSevenOS 6>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'skips the updates that Sessions.xml lists as Installed by KBNumber or FileKBNumber' {
        Copy-SessionsXml $MountDirectory | Out-Null
        $Output = (Update-WindowsSevenOS 6>&1) -join "`n"
        #KB4566425 is Absent in Sessions.xml
        $script:Installed | Should -Be @('windows6.1-kb4566425-x64_0123456789abcdef.msu', 'windows6.1-kb4571703-x64_0123456789abcdef.msu')
        $Output | Should -BeLike '*INSTALLED*(KB3172729)*'
        $Output | Should -BeLike '*INSTALLED*(KB4598285)*'
        $Output | Should -BeLike '*OS: Windows 7 Updates*'
    }

    It 'checks the Sessions.xml again by <Check> after reading it for each update' -ForEach @(
        @{Check = 'KBNumber'; Index = 0}
        @{Check = 'FileKBNumber'; Index = 1}
    ) {
        $SessionsXml = Copy-SessionsXml $MountDirectory
        $script:SessionsXmlReads = 0
        $script:FullXml = Get-Content -Path $SessionsXml -Raw
        $script:EmptyXml = '<?xml version="1.0" encoding="utf-8"?><Sessions version="1.0"><Session><Tasks><Phase seq="1"><package name="Package_for_KB1" targetState="Installed" /></Phase></Tasks></Session></Sessions>'
        #1: header (empty), 2: reread for the update finds it
        Mock Get-Content {$script:SessionsXmlReads++; if ($script:SessionsXmlReads -ge 2) {$script:FullXml} else {$script:EmptyXml}} -ParameterFilter {$Path -like '*Sessions.xml'}
        $OSDUpdateWinSeven = @($OSDUpdateWinSeven[$Index])
        Update-WindowsSevenOS 6>$null
        $script:Installed.Count | Should -Be 0
        Should -Invoke Get-WindowsPackage -Times 0 -Exactly
    }

    It 'skips the updates that Get-WindowsPackage returns by KBNumber or FileKBNumber without Sessions.xml' {
        Mock Get-WindowsPackage {
            [PSCustomObject]@{PackageName = 'Package_for_KB3172729~31bf3856ad364e35~amd64~~6.1.1.1'}
            [PSCustomObject]@{PackageName = 'Package_for_KB4571703~31bf3856ad364e35~amd64~~6.1.1.0'}
        }
        Update-WindowsSevenOS 6>$null
        $script:Installed | Should -Be @('windows6.1-kb4598285-x64_0123456789abcdef.msu', 'windows6.1-kb4566425-x64_0123456789abcdef.msu')
    }

    It 'installs with a log named after FileKBNumber or KBNumber' {
        Update-WindowsSevenOS 6>$null
        $script:Installed.Count | Should -Be 4
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {($Path -eq $MountDirectory) -and ($PackagePath -like '*kb4566425*') -and ($LogPath -like 'C:\Info\logs\*-Update-WindowsSevenOS-KB4566425.log')}
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {($PackagePath -like '*kb4571703*') -and ($LogPath -like '*-Update-WindowsSevenOS-KB4571703.log')}
    }

    It 'skips missing update files silently and warns when a file cannot be found' {
        Remove-Item -Path (Join-Path $SetOSDBuilderPathUpdates 'windows6.1-kb3172729-x64_0123456789abcdef.msu')
        Mock Test-Path {$false} -ParameterFilter {$Path -like '*kb4598285*'}
        $Warnings = @(Update-WindowsSevenOS 6>$null 3>&1)
        $Warnings.Count | Should -Be 1
        "$($Warnings[0])" | Should -BeLike 'Not Found: *kb4598285*'
        $script:Installed.Count | Should -Be 2
    }

    It 'reports 0x800f081e as not applicable with the log' {
        Mock Add-WindowsPackage {throw 'Add-WindowsPackage failed. Error code = 0x800f081e'}
        $Verbose = (Update-WindowsSevenOS 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*Review the log for more information*-Update-WindowsSevenOS-KB3172729.log*'
    }
}
