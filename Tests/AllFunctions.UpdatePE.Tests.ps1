#Update-* functions of AllFunctions.ps1 for WinPE, WinRE, WinSE, the media and the module itself
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}

    #PowerShellGet is not installed on every platform, placeholders so Pester can mock it
    $ModuleCommands = [ordered]@{
        'Install-Module'    = '$Name, $Scope, [switch]$Force'
        'Uninstall-Module'  = '$Name, [switch]$AllVersions, [switch]$Force'
    }
    foreach ($Name in $ModuleCommands.Keys) {
        if (Get-Command -Name $Name -ErrorAction SilentlyContinue) {Continue}
        $Body = "[CmdletBinding()] param ($($ModuleCommands[$Name]), [Parameter(ValueFromRemainingArguments = `$true)]`$RemainingArguments) process {throw '$Name is not available on this platform, mock it in the test'}"
        Set-Item -Path "function:global:$Name" -Value ([scriptblock]::Create($Body))
    }

    function New-UpdateItem {
        param ($Group, $Title, $KB, $FileKB, $Date = '2026-10-14', $Extension = 'cab', [switch]$OSDWinPE)
        [PSCustomObject]@{
            UpdateGroup     = $Group
            Title           = $Title
            KBNumber        = $KB
            FileKBNumber    = $FileKB
            CreationDate    = $Date
            OSDWinPE        = [bool]$OSDWinPE
            OriginUri       = "https://catalog.invalid/windows11.0-kb$($FileKB)-x64_0123456789abcdef.$Extension"
        }
    }

    function New-UpdateFile ($Path, $Update) {
        foreach ($Item in $Update) {New-TestFile -Path (Join-Path $Path (Split-Path $Item.OriginUri -Leaf)) | Out-Null}
    }

    #Arguments of a mocked Windows program
    function Join-ProgramArgument ($InputObject, $RemainingArguments) {
        (@($InputObject) + @($RemainingArguments)) -join ' '
    }
}

Describe 'Update-CumulativePE' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'LCU'
        $MountWinPE = 'C:\WinPE'; $MountWinRE = 'C:\WinRE'; $MountWinSE = 'C:\WinSE'; $PEInfo = 'C:\PEInfo'; $OSMajorVersion = 10
        $SkipUpdates = $false; $SkipUpdatesPE = $false; $SkipUpdatesPELCU = $false
        $OSDUpdateLCU = @(New-UpdateItem 'LCU' '2026-10 Cumulative Update (KB5066791)' '5066791' '5066791' -Extension 'msu')
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateLCU
        Mock Show-ActionTime {}
        Mock Get-SessionsXml {}
        Mock Get-WindowsPackage {}
        Mock Add-WindowsPackage {}
        Mock Add-WindowsPackageSSU {}
        Mock dism {}
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'SkipUpdatesPE'; Value = $true}
        @{Variable = 'SkipUpdatesPELCU'; Value = $true}
        @{Variable = 'OSDUpdateLCU'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        $Warnings = @(Update-CumulativePE 6>$null 3>&1)
        $Warnings.Count | Should -Be 0
        Should -Invoke Show-ActionTime -Times 0 -Exactly
    }

    It 'does nothing with -Force on an operating system older than Windows 10' {
        $OSMajorVersion = 6
        Update-CumulativePE -Force 6>$null 3>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
    }

    It 'skips the WinPE LCU with a warning on <Name> and does not change WinPE, WinRE or WinSE' -ForEach @(
        @{Name = 'Windows 10 and newer'; Major = 10}
        @{Name = 'older operating systems'; Major = 6}
    ) {
        $OSMajorVersion = $Major
        $Output = (Update-CumulativePE 6>&1 3>&1) -join "`n"
        $Output | Should -BeLike '*WinPE: (LCU) Latest Cumulative Update*'
        $Output | Should -BeLike '*Skipping WinPE LCU Update for this version of Windows*'
        $Output | Should -Not -BeLike '*WinRE: (LCU)*'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        Should -Invoke Add-WindowsPackageSSU -Times 0 -Exactly
        Should -Invoke dism -Times 0 -Exactly
    }
}

Describe 'Update-ServicingStackPE' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'SSU'
        $MountWinPE = 'C:\WinPE'; $MountWinRE = 'C:\WinRE'; $MountWinSE = 'C:\WinSE'; $PEInfo = 'C:\PEInfo'; $OSMajorVersion = 10
        $SkipUpdates = $false; $SkipUpdatesPE = $false; $SkipUpdatesPESSU = $false
        $OSDUpdateSSU = @(New-UpdateItem 'SSU' '2022-10 Servicing Stack Update (KB5018506)' '5018506' '5018506' -Extension 'msu')
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateSSU
        Mock Show-ActionTime {}
        Mock Get-SessionsXml {}
        Mock Get-WindowsPackage {}
        Mock Add-WindowsPackage {}
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'SkipUpdatesPE'; Value = $true}
        @{Variable = 'SkipUpdatesPESSU'; Value = $true}
        @{Variable = 'OSDUpdateSSU'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        $Warnings = @(Update-ServicingStackPE 6>$null 3>&1)
        $Warnings.Count | Should -Be 0
        Should -Invoke Show-ActionTime -Times 0 -Exactly
    }

    It 'does nothing with -Force on an operating system older than Windows 10' {
        $OSMajorVersion = 6
        Update-ServicingStackPE -Force 6>$null 3>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
    }

    It 'skips the WinPE SSU with a warning on <Name> and does not change WinPE, WinRE or WinSE' -ForEach @(
        @{Name = 'Windows 10 and newer'; Major = 10}
        @{Name = 'older operating systems'; Major = 6}
    ) {
        $OSMajorVersion = $Major
        $Output = (Update-ServicingStackPE 6>&1 3>&1) -join "`n"
        $Output | Should -BeLike '*WinPE: (SSU) Servicing Stack Update*'
        $Output | Should -BeLike '*Skipping WinPE SSU Update for this version of Windows*'
        $Output | Should -Not -BeLike '*WinRE: (SSU)*'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }
}

Describe 'Update-SafeOSPE' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'SafeOS'
        $MountWinRE = Join-Path $TestDrive 'WinRE'
        New-Item -Path (Join-Path $MountWinRE 'Windows') -ItemType Directory -Force | Out-Null
        $PEInfo = 'C:\PEInfo'; $OSMajorVersion = 10; $UpdateOS = 'Windows 11'
        $SkipUpdates = $false; $SkipUpdatesPE = $false; $SkipComponentCleanup = $false
        $OSDUpdateComponentDU = @(
            New-UpdateItem 'ComponentDU SafeOS' '2026-10 Safe OS Dynamic Update (KB5127654)' '5127654' '5127654' '2026-10-14'
            New-UpdateItem 'ComponentDU Critical' '2026-10 Dynamic Update (KB5000001)' '5000001' '5000001' '2026-10-20'
            New-UpdateItem 'ComponentDU SafeOS' '2026-09 Safe OS Dynamic Update (KB5065400)' '5065400' '5065400' '2026-09-09'
        )
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateComponentDU
        $script:Installed = New-Object System.Collections.Generic.List[string]
        Mock Show-ActionTime {}
        Mock Get-WindowsPackage {}
        Mock Add-WindowsPackage {$script:Installed.Add((Split-Path $PackagePath -Leaf))}
        Mock dism {}
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'SkipUpdatesPE'; Value = $true}
        @{Variable = 'OSMajorVersion'; Value = 6}
        @{Variable = 'UpdateOS'; Value = 'Windows 10'}
        @{Variable = 'MountWinRE'; Value = $null}
        @{Variable = 'OSDUpdateComponentDU'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Update-SafeOSPE 6>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'does nothing when WinRE is not mounted' {
        $MountWinRE = Join-Path $TestDrive 'NotMounted'
        Update-SafeOSPE 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'does nothing without a Safe OS Dynamic Update' {
        $OSDUpdateComponentDU = @($OSDUpdateComponentDU[1])
        Update-SafeOSPE 6>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'installs only the newest Safe OS Dynamic Update to WinRE and cleans up WinRE' {
        $Output = (Update-SafeOSPE 6>&1) -join "`n"
        $script:Installed | Should -Be @('windows11.0-kb5127654-x64_0123456789abcdef.cab')
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {($Path -eq $MountWinRE) -and ($LogPath -like 'C:\PEInfo\logs\*-Update-SafeOSPE-KB5127654-WinRE.log')}
        Should -Invoke dism -Times 1 -Exactly -ParameterFilter {
            $Arguments = Join-ProgramArgument $InputObject $RemainingArguments
            ($Arguments -like "/Image:$MountWinRE /Cleanup-Image /StartComponentCleanup /ResetBase /LogPath:C:\PEInfo\logs\*-DismCleanupImage-WinRE.log")
        }
        $Output | Should -BeLike '*WinRE: Safe OS Dynamic Update*'
    }

    It 'does not clean up WinRE with -SkipComponentCleanup' {
        $SkipComponentCleanup = $true
        $Warnings = (Update-SafeOSPE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Skip: -SkipComponentCleanup Parameter was used*'
        $script:Installed.Count | Should -Be 1
        Should -Invoke dism -Times 0 -Exactly
    }

    It 'skips the update and the cleanup when WinRE already contains it' {
        Mock Get-WindowsPackage {[PSCustomObject]@{PackageName = 'Package_for_SafeOSDU~31bf3856ad364e35~amd64~~26100.5127654.1.0'}} -ParameterFilter {$Path -eq $MountWinRE}
        $Output = (Update-SafeOSPE 6>&1) -join "`n"
        $Output | Should -BeLike '*INSTALLED*KB5127654*'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        Should -Invoke dism -Times 0 -Exactly
    }

    It 'warns when the update file is missing' {
        Remove-Item -Path (Join-Path $SetOSDBuilderPathUpdates 'windows11.0-kb5127654-x64_0123456789abcdef.cab')
        $Warnings = (Update-SafeOSPE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Update-SafeOSPE is Null*'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'warns when the update file cannot be found' {
        Mock Test-Path {$false} -ParameterFilter {$Path -like '*kb5127654*'}
        $Warnings = (Update-SafeOSPE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Update-SafeOSPE was not found*'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'reports 0x800f081e as not applicable with the log and still cleans up' {
        Mock Add-WindowsPackage {throw 'Add-WindowsPackage failed. Error code = 0x800f081e'}
        $Verbose = (Update-SafeOSPE 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*Review the log for more information*-Update-SafeOSPE-KB5127654-WinRE.log*'
        Should -Invoke dism -Times 1 -Exactly
    }
}

Describe 'Update-SetupDUMEDIA' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'SetupDU'
        $OS = 'C:\OSBuild\OS'; $MountWinSE = 'C:\Mount\WinSE'; $Logs = 'C:\OSBuild\info\logs'
        $SkipUpdates = $false; $SkipSetupDU = $false
        $OSDUpdateSetupDU = @(
            New-UpdateItem 'SetupDU' '2026-10 Setup Dynamic Update (KB5127650)' '5127650' '5127650'
            New-UpdateItem 'SetupDU' '2026-09 Setup Dynamic Update (KB5065410)' '5065410' '5065410'
        )
        New-UpdateFile $SetOSDBuilderPathUpdates $OSDUpdateSetupDU
        $script:TempBefore = $env:TEMP
        $env:TEMP = Join-Path $TestDrive 'Temp'
        if (Test-Path $env:TEMP) {Remove-Item -Path $env:TEMP -Recurse -Force}
        New-Item -Path $env:TEMP -ItemType Directory -Force | Out-Null
        $script:Random = 4711
        Mock Get-Random {$script:Random++; $script:Random}
        Mock Show-ActionTime {}
        Mock expand.exe {}
        Mock robocopy {}
    }

    AfterEach {
        $env:TEMP = $script:TempBefore
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'SkipSetupDU'; Value = $true}
        @{Variable = 'OSDUpdateSetupDU'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Update-SetupDUMEDIA 6>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
        Should -Invoke expand.exe -Times 0 -Exactly
    }

    It 'expands each Setup Dynamic Update to its own temporary folder' {
        $Output = (Update-SetupDUMEDIA 6>&1) -join "`n"
        $Output | Should -BeLike '*MEDIA: (SetupDU) Windows Setup Dynamic Update*'
        Should -Invoke expand.exe -Times 1 -Exactly -ParameterFilter {
            (Join-ProgramArgument $InputObject $RemainingArguments) -eq "$(Join-Path $SetOSDBuilderPathUpdates 'windows11.0-kb5127650-x64_0123456789abcdef.cab') -F: *.* $env:TEMP\4712"
        }
        Should -Invoke expand.exe -Times 1 -Exactly -ParameterFilter {
            (Join-ProgramArgument $InputObject $RemainingArguments) -like "*kb5065410* -F: *.* $env:TEMP\4713"
        }
        Test-Path (Join-Path $env:TEMP '4712') | Should -BeTrue
    }

    It 'copies the expanded files to the media sources and to WinSE sources with a log' {
        Update-SetupDUMEDIA 6>$null
        Should -Invoke robocopy -Times 4 -Exactly
        Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {
            (Join-ProgramArgument $InputObject $RemainingArguments) -like "$env:TEMP\4712 C:\OSBuild\OS\Sources *.* /s /ndl /xo /xx /xl /b /np /ts /tee /r:0 /w:0 /Log+:C:\OSBuild\info\logs\*-Robocopy-Media-SetupDU.log"
        }
        Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {
            (Join-ProgramArgument $InputObject $RemainingArguments) -like "$env:TEMP\4712 C:\Mount\WinSE\Sources *.* /s * /Log+:C:\OSBuild\info\logs\*-Robocopy-WinSE-SetupDU.log"
        }
    }

    It 'skips an update that was not downloaded without a warning' {
        Remove-Item -Path (Join-Path $SetOSDBuilderPathUpdates 'windows11.0-kb5127650-x64_0123456789abcdef.cab')
        $Warnings = @(Update-SetupDUMEDIA 6>$null 3>&1)
        $Warnings.Count | Should -Be 0
        Should -Invoke expand.exe -Times 1 -Exactly
        Should -Invoke expand.exe -Times 1 -Exactly -ParameterFilter {"$InputObject" -like '*kb5065410*'}
    }

    It 'warns when an update file cannot be found' {
        Mock Test-Path {$false} -ParameterFilter {$Path -like '*kb5127650*'}
        $Warnings = (Update-SetupDUMEDIA 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Not Found: *kb5127650*'
        Should -Invoke expand.exe -Times 1 -Exactly
    }

    It 'uses an existing temporary folder' {
        New-Item -Path (Join-Path $env:TEMP '4712') -ItemType Directory -Force | Out-Null
        Mock New-Item {}
        Update-SetupDUMEDIA 6>$null
        Should -Invoke New-Item -Times 0 -Exactly -ParameterFilter {$Path -like '*4712'}
        Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {$Path -like '*4713'}
    }

    # KnownBug: Update-SetupDUMEDIA never removes the temporary folder in $env:TEMP that expand.exe extracts the Setup Dynamic Update to
    It 'removes the temporary folder after applying the update' -Skip {
        Update-SetupDUMEDIA 6>$null
        Test-Path (Join-Path $env:TEMP '4712') | Should -BeFalse
        Test-Path (Join-Path $env:TEMP '4713') | Should -BeFalse
    }
}

Describe 'Update-SourcesPE' {
    BeforeEach {
        $OSMediaPath = 'C:\OSMedia\Windows 10 1809'; $MountWinSE = 'C:\Mount\WinSE'
        $ReleaseId = '1809'; $OSBuild = 17763
        $SkipUpdates = $false; $SkipUpdatesPE = $false; $SkipUpdatesOS = $false
        Mock Show-ActionTime {}
        Mock robocopy {}
    }

    It 'does nothing when <Variable> is <Value>' -ForEach @(
        @{Variable = 'SkipUpdates'; Value = $true}
        @{Variable = 'SkipUpdatesPE'; Value = $true}
        @{Variable = 'SkipUpdatesOS'; Value = $true}
        @{Variable = 'ReleaseId'; Value = '1903'}
        @{Variable = 'ReleaseId'; Value = '21H2'}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Update-SourcesPE -OSMediaPath $OSMediaPath 6>$null
        Should -Invoke Show-ActionTime -Times 0 -Exactly
        Should -Invoke robocopy -Times 0 -Exactly
    }

    It 'copies setup.exe and setuphost.exe from WinSE to the media sources' {
        $Output = (Update-SourcesPE -OSMediaPath $OSMediaPath 6>&1) -join "`n"
        $Output | Should -BeLike '*MEDIA: Update Media Sources with WinSE.wim*'
        Should -Invoke robocopy -Times 2 -Exactly
        foreach ($File in 'setup.exe', 'setuphost.exe') {
            Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {
                (Join-ProgramArgument $InputObject $RemainingArguments) -like "C:\Mount\WinSE\sources C:\OSMedia\Windows 10 1809\OS\sources $File /ndl /xo /xx /xl /b /np /ts /tee /r:0 /w:0 /Log+:C:\OSMedia\Windows 10 1809\info\logs\*-Robocopy-WinSE-MediaSources.log"
            }
        }
    }

    It 'skips with a warning for build 18362 and newer' {
        $OSBuild = 18362
        $Warnings = (Update-SourcesPE -OSMediaPath $OSMediaPath 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Skipping WinPE Update for this version of Windows*'
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Update-LangIniMEDIA' {
    BeforeEach {
        $SetOSDBuilderPathMount = Join-Path $TestDrive 'Mount'
        if (Test-Path $SetOSDBuilderPathMount) {Remove-Item -Path $SetOSDBuilderPathMount -Recurse -Force}
        New-Item -Path $SetOSDBuilderPathMount -ItemType Directory -Force | Out-Null
        $OSMediaPath = 'C:\OSMedia\Windows 10 22H2'; $OS = 'C:\OSMedia\Windows 10 22H2\OS'
        $script:Steps = New-Object System.Collections.Generic.List[string]
        Mock Show-ActionTime {}
        Mock Start-Sleep {}
        Mock Mount-WindowsImage {$script:Steps.Add("Mount $(Split-Path $ImagePath -Leaf) $Index")}
        Mock Copy-Item {$script:Steps.Add("Copy $(Split-Path (Split-Path $Destination -Parent) -Leaf)")} -ParameterFilter {$Path -eq 'C:\OSMedia\Windows 10 22H2\OS\Sources\lang.ini'}
        Mock Dismount-WindowsImage {$script:Steps.Add("Dismount $(Split-Path $Path -Leaf)")}
    }

    It 'mounts WinSE.wim and Boot.wim index 2, copies lang.ini and saves both images' {
        $Output = (Update-LangIniMEDIA -OSMediaPath $OSMediaPath 6>&1) -join "`n"
        $Output | Should -BeLike '*WinSE: Updating WinSE.wim with updated Lang.ini*'
        $Output | Should -BeLike '*Boot: Updating Boot.wim (Index 2 - Windows Setup Environment) with updated Lang.ini*'
        $script:Steps.Count | Should -Be 6
        $script:Steps[0] | Should -Be 'Mount winse.wim 1'
        $script:Steps[1] | Should -BeLike 'Copy winselangini*'
        $script:Steps[2] | Should -BeLike 'Dismount winselangini*'
        $script:Steps[3] | Should -Be 'Mount boot.wim 2'
        $script:Steps[4] | Should -BeLike 'Copy bootlangini*'
        $script:Steps[5] | Should -BeLike 'Dismount bootlangini*'
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($ImagePath -eq 'C:\OSMedia\Windows 10 22H2\WinPE\winse.wim') -and ($Path -like (Join-Path $SetOSDBuilderPathMount 'winselangini*')) -and ($LogPath -like 'C:\OSMedia\Windows 10 22H2\WinPE\info\logs\*-Mount-WinSELangIni.log')
        }
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq 'C:\OSMedia\Windows 10 22H2\OS\Sources\boot.wim') -and ($LogPath -like '*-Mount-BootLangIni.log')}
        Should -Invoke Copy-Item -Times 2 -Exactly -ParameterFilter {$Destination -like '*langini*\Sources'}
        Should -Invoke Dismount-WindowsImage -Times 2 -Exactly -ParameterFilter {$Save}
        Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter {$Seconds -eq 10}
    }

    It 'removes the temporary mount directories' {
        Update-LangIniMEDIA -OSMediaPath $OSMediaPath 6>$null
        @(Get-ChildItem -Path $SetOSDBuilderPathMount).Count | Should -Be 0
    }

    It 'waits 30 seconds and retries when <Image> cannot be dismounted' -ForEach @(
        @{Image = 'WinSE.wim'; Folder = 'winselangini'}
        @{Image = 'Boot.wim'; Folder = 'bootlangini'}
    ) {
        $script:FailFolder = $Folder
        $script:Failed = $false
        Mock Dismount-WindowsImage {
            if ((-not $script:Failed) -and ((Split-Path $Path -Leaf) -like "$($script:FailFolder)*")) {$script:Failed = $true; throw 'The process cannot access the file'}
            $script:Steps.Add("Dismount $(Split-Path $Path -Leaf)")
        }
        $Warnings = (Update-LangIniMEDIA -OSMediaPath $OSMediaPath 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*Could not dismount $Image ... Waiting 30 seconds ...*"
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {$Seconds -eq 30}
        Should -Invoke Dismount-WindowsImage -Times 3 -Exactly
        @($script:Steps | Where-Object {$_ -like "Dismount $Folder*"}).Count | Should -Be 1
    }
}

Describe 'Update-ModuleOSDBuilder' {
    BeforeEach {
        $script:Calls = New-Object System.Collections.Generic.List[string]
        Mock Uninstall-Module {$script:Calls.Add("Uninstall $Name")}
        Mock Remove-Module {$script:Calls.Add("Remove $Name")} -ParameterFilter {$Name -eq 'OSDBuilder'}
        Mock Install-Module {$script:Calls.Add("Install $Name $Scope")}
        Mock Import-Module {$script:Calls.Add("Import $Name")} -ParameterFilter {$Name -eq 'OSDBuilder'}
    }

    It 'reinstalls OSD and OSDBuilder for all users in order' {
        $Warnings = (Update-ModuleOSDBuilder 3>&1) -join "`n"
        $script:Calls | Should -Be @('Uninstall OSDBuilder', 'Remove OSDBuilder', 'Install OSD ', 'Install OSDBuilder ', 'Import OSDBuilder')
        Should -Invoke Uninstall-Module -Times 1 -Exactly -ParameterFilter {$AllVersions -and $Force}
        Should -Invoke Install-Module -Times 2 -Exactly -ParameterFilter {$Force -and (-not $Scope)}
        $Warnings | Should -BeLike '*Install-Module -Name OSD -Force*Install-Module -Name OSDBuilder -Force*Close all open PowerShell sessions before using OSDBuilder*'
    }

    It 'installs for the current user with -CurrentUser' {
        $Warnings = (Update-ModuleOSDBuilder -CurrentUser 3>&1) -join "`n"
        $script:Calls | Should -Be @('Uninstall OSDBuilder', 'Remove OSDBuilder', 'Install OSD CurrentUser', 'Install OSDBuilder CurrentUser', 'Import OSDBuilder')
        $Warnings | Should -BeLike '*Install-Module -Name OSD -Scope CurrentUser -Force*Install-Module -Name OSDBuilder -Scope CurrentUser -Force*'
    }

    It 'continues and finishes when <Switch> every module command fails' -ForEach @(
        @{Switch = 'without -CurrentUser'; CurrentUser = $false}
        @{Switch = 'with -CurrentUser'; CurrentUser = $true}
    ) {
        Mock Uninstall-Module {throw 'No match was found'}
        Mock Remove-Module {throw 'No modules were removed'} -ParameterFilter {$Name -eq 'OSDBuilder'}
        Mock Install-Module {throw 'Unable to resolve package source'}
        Mock Import-Module {throw 'module was not loaded'} -ParameterFilter {$Name -eq 'OSDBuilder'}
        $Warnings = (Update-ModuleOSDBuilder -CurrentUser:$CurrentUser 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Close all open PowerShell sessions before using OSDBuilder*'
        Should -Invoke Install-Module -Times 2 -Exactly
        Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter {$Name -eq 'OSDBuilder'}
    }
}
