BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    foreach ($Name in 'Get-OSDBuilder', 'Get-OSMedia', 'New-PEBuildTask') {. (Join-Path (Join-Path $RepoRoot 'Public') "$Name.ps1")}

    $PEBuildTaskFixtures = Join-Path $FixturesPath 'PEBuildTask'

    $global:SetOSDBuilder = @{}
    $global:GetOSDBuilder = @{VersionOSDBuilder = [version]'26.10.16.1'}
    $global:SetOSDBuilderPathTasks = Join-Path $TestDrive 'Tasks'
    $global:SetOSDBuilderPathOSMedia = Join-Path $TestDrive 'OSMedia'

    function New-TestOSMedia {
        <#
        .SYNOPSIS
        Creates an OSMedia directory in $TestDrive and returns the Get-OSMedia object of it
        #>
        param (
            [string]$Name = 'Windows 11 Enterprise x64 25H2 26200.6899',
            [string]$Arch = 'x64',
            $ReleaseId = '25H2',
            [string]$Build = '26200',
            [string]$MajorVersion = '10',
            #Writes info\xml\CurrentVersion.xml with these properties
            [hashtable]$CurrentVersion
        )
        $FullName = Join-Path $global:SetOSDBuilderPathOSMedia $Name
        $Xml = Join-Path (Join-Path $FullName 'info') 'xml'
        New-Item -Path $Xml -ItemType Directory -Force | Out-Null
        New-TestFile -Path (Join-Path (Join-Path (Join-Path $FullName 'OS') 'sources') 'install.wim') | Out-Null
        New-TestFile -Path (Join-Path (Join-Path $FullName 'WinPE') 'winpe.wim') | Out-Null
        [PSCustomObject]@{ImageName = 'Windows 11 Enterprise'; Version = "10.0.$Build.6899"; Architecture = 9} | Export-Clixml -Path (Join-Path $Xml 'Get-WindowsImage.xml')
        if ($CurrentVersion) {[PSCustomObject]$CurrentVersion | Export-Clixml -Path (Join-Path $Xml 'CurrentVersion.xml')}
        [PSCustomObject]@{
            MediaType           = 'OSMedia'
            OSMFamily           = "Enterprise $Arch $Build en-US"
            OSMGuid             = [string][guid]::NewGuid()
            Name                = $Name
            FullName            = $FullName
            ImageName           = 'Windows 11 Enterprise'
            Arch                = $Arch
            ReleaseId           = $ReleaseId
            UBR                 = "$Build.6899"
            Languages           = @('en-US')
            EditionId           = 'Enterprise'
            InstallationType    = 'Client'
            MajorVersion        = $MajorVersion
            Build               = $Build
            CreatedTime         = [datetime]'2026-10-01T10:00:00'
            ModifiedTime        = [datetime]'2026-10-02T10:00:00'
        }
    }

    function Get-TestTask ([string]$FileName = 'Recovery Contoso.json') {
        Get-Content -Path (Join-Path $global:SetOSDBuilderPathTasks $FileName) -Raw | ConvertFrom-Json
    }

    function Copy-ExistingTask ([string]$FileName = 'WinPE Contoso.json', [scriptblock]$Change) {
        $Task = Get-Content -Path (Join-Path $PEBuildTaskFixtures 'WinPE Existing.json') -Raw | ConvertFrom-Json
        if ($Change) {. $Change}
        $Task | ConvertTo-Json | Set-Content -Path (Join-Path $global:SetOSDBuilderPathTasks $FileName)
    }

    function Item ([string]$Property, [string[]]$Value) {
        foreach ($Item in $Value) {[PSCustomObject]@{$Property = $Item}}
    }
}

AfterAll {
    Remove-Variable -Name SetOSDBuilder, GetOSDBuilder, SetOSDBuilderPathTasks, SetOSDBuilderPathOSMedia -Scope Global -ErrorAction SilentlyContinue
}

Describe 'New-PEBuildTask' {
    BeforeEach {
        foreach ($Path in $global:SetOSDBuilderPathTasks, $global:SetOSDBuilderPathOSMedia) {
            if (Test-Path $Path) {Remove-Item -Path $Path -Recurse -Force}
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
        $script:GridInput = @()
        $script:OSMediaList = @(New-TestOSMedia)
        Mock Get-OSDBuilder {}
        Mock Block-StandardUser {}
        Mock Get-OSMedia {$script:OSMediaList}
        Mock Out-GridView {$script:GridInput += $InputObject; if ($script:GridInput.Count -eq 1) {$InputObject}}
        Mock Get-WindowsImage {[PSCustomObject]@{Version = '10.0.26200.6899'; MinorVersion = 0; SPBuild = 6899; SPLevel = 0; ImageBootable = $false; WIMBoot = $false}}
        Mock Get-IsContentPacksEnabled {$true}
        Mock Get-TaskContentIsoExtract {}
        foreach ($Command in 'Get-TaskContentPacks', 'Get-TaskWinPEDaRT', 'Get-TaskWinPEADK', 'Get-TaskWinPEDrivers', 'Get-TaskWinPEExtraFiles', 'Get-TaskWinPEScripts') {
            Mock $Command {}
        }
    }

    Context 'Parameters' {
        It 'uses the Recovery parameter set by default' {
            (Get-Command New-PEBuildTask).DefaultParameterSet | Should -Be 'Recovery'
        }

        It 'requires -SourceWim for WinPE and MDT' {
            $Parameter = (Get-Command New-PEBuildTask).Parameters['SourceWim']
            @($Parameter.ParameterSets.Keys | Sort-Object) | Should -Be @('MDT', 'WinPE')
            foreach ($Set in 'MDT', 'WinPE') {$Parameter.ParameterSets[$Set].IsMandatory | Should -BeTrue}
            (Get-Command New-PEBuildTask).Parameters['MDTDeploymentShare'].ParameterSets['MDT'].IsMandatory | Should -BeTrue
        }

        It 'rejects an invalid <Name>' -ForEach @(@{Name = 'ScratchSpace'; Value = '1024'}, @{Name = 'SourceWim'; Value = 'WinSE'}) {
            $Splat = @{TaskName = 'Contoso'; $Name = $Value}
            {New-PEBuildTask @Splat 6>$null 3>$null} | Should -Throw "*$Value*"
        }
    }

    Context 'New Task' {
        It 'writes a Recovery Task from WinRE with the OSMedia' {
            $Result = New-PEBuildTask -TaskName 'Contoso' -CustomName 'Contoso WinRE' -WinPEAutoExtraFiles 6>$null 3>$null

            $Task = Get-TestTask 'Recovery Contoso.json'
            $OSMedia = $script:OSMediaList[0]
            $Task.TaskType | Should -Be 'PEBuild'
            $Task.TaskVersion | Should -Be '26.10.16.1'
            {[guid]$Task.TaskGuid} | Should -Not -Throw
            $Task.TaskName | Should -Be 'Contoso'
            $Task.CustomName | Should -Be 'Contoso WinRE'
            $Task.WinPEOutput | Should -Be 'Recovery'
            $Task.SourceWim | Should -Be 'WinRE'
            $Task.ScratchSpace | Should -Be '512'
            $Task.MDTDeploymentShare | Should -BeNullOrEmpty
            $Task.WinPEAutoExtraFiles | Should -Be 'True'
            $Task.OSMFamily | Should -Be $OSMedia.OSMFamily
            $Task.OSMGuid | Should -Be $OSMedia.OSMGuid
            $Task.Name | Should -Be $OSMedia.Name
            $Task.ImageName | Should -Be 'Windows 11 Enterprise'
            $Task.Arch | Should -Be 'x64'
            $Task.ReleaseId | Should -Be '25H2'
            $Task.UBR | Should -Be '26200.6899'
            $Task.Languages | Should -Be @('en-US')
            $Task.EditionId | Should -Be 'Enterprise'
            $Task.InstallationType | Should -Be 'Client'
            $Task.MajorVersion | Should -Be '10'
            $Task.Build | Should -Be '26200'
            ([datetime]$Task.CreatedTime).Date | Should -Be ([datetime]'2026-10-01')
            ([datetime]$Task.ModifiedTime).Date | Should -Be ([datetime]'2026-10-02')
            foreach ($Property in 'ContentPacks', 'WinPEDaRT', 'WinPEADK', 'WinPEDrivers', 'WinPEExtraFiles', 'WinPEScripts') {
                $Task.PSObject.Properties.Name | Should -Contain $Property
                $Task.$Property | Should -BeNullOrEmpty -Because $Property
            }
            $Result.TaskGuid | Should -Be $Task.TaskGuid
            Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
            Should -Invoke Block-StandardUser -Times 1 -Exactly
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq "$($OSMedia.FullName)\OS\sources\install.wim") -and ($Index -eq 1)}
        }

        It 'writes a WinPE Task with -SourceWim <SourceWim> and the ScratchSpace' -ForEach @(@{SourceWim = 'WinPE'}, @{SourceWim = 'WinRE'}) {
            New-PEBuildTask -TaskName 'Contoso' -SourceWim $SourceWim -ScratchSpace 256 6>$null 3>$null | Out-Null
            $Task = Get-TestTask 'WinPE Contoso.json'
            $Task.WinPEOutput | Should -Be 'WinPE'
            $Task.SourceWim | Should -Be $SourceWim
            $Task.ScratchSpace | Should -Be '256'
            $Task.WinPEAutoExtraFiles | Should -Be 'False'
        }

        It 'writes an MDT Task with the Deployment Share' {
            New-PEBuildTask -TaskName 'Contoso' -SourceWim WinPE -MDTDeploymentShare 'D:\DeploymentShare' 6>$null 3>$null | Out-Null
            $Task = Get-TestTask 'MDT Contoso.json'
            $Task.WinPEOutput | Should -Be 'MDT'
            $Task.SourceWim | Should -Be 'WinPE'
            $Task.MDTDeploymentShare | Should -Be 'D:\DeploymentShare'
        }

        It 'writes every selection to the Task JSON' {
            Mock Get-TaskContentPacks {Item Name 'Contoso', '_Global'}
            Mock Get-TaskWinPEDaRT {Item FullName 'DaRT\10\Toolsx64.cab'}
            Mock Get-TaskWinPEDrivers {Item FullName 'Drivers\WinPE\Intel', 'Drivers\WinPE\Dell'}
            Mock Get-TaskWinPEExtraFiles {Item FullName 'ExtraFiles\WinPE\Tools'}
            Mock Get-TaskWinPEScripts {Item FullName 'Scripts\WinPE\Config.ps1'}
            Mock Get-TaskContentIsoExtract {Item FullName 'IsoExtract\Windows 11\lp.cab', 'IsoExtract\Windows Preinstallation Environment\WinPE-WMI.cab'}
            Mock Get-TaskWinPEADK {
                $script:SeenIsoExtractWinPE = @($ContentIsoExtractWinPE.FullName)
                Item FullName 'ADK\x64\WinPE_OCs\WinPE-PowerShell.cab', 'ADK\x64\WinPE_OCs\WinPE-WMI.cab'
            }

            $Warnings = New-PEBuildTask -TaskName 'Contoso' -SourceWim WinPE -AddContentPacks -ContentWinPEDart -ContentWinPEADK -ContentWinPEDrivers -ContentWinPEExtraFiles -ContentWinPEScripts 6>$null 3>&1 |
                Where-Object {$_ -is [System.Management.Automation.WarningRecord]}

            ($Warnings -join "`n") | Should -BeLike '*Generating IsoExtract Content*'
            $script:SeenIsoExtractWinPE | Should -Be @('IsoExtract\Windows Preinstallation Environment\WinPE-WMI.cab')
            $Task = Get-TestTask 'WinPE Contoso.json'
            $Task.ContentPacks | Should -Be @('_Global', 'Contoso')
            $Task.WinPEDaRT | Should -Be 'DaRT\10\Toolsx64.cab'
            $Task.WinPEADK | Should -Be @('ADK\x64\WinPE_OCs\WinPE-WMI.cab', 'ADK\x64\WinPE_OCs\WinPE-PowerShell.cab')
            $Task.WinPEDrivers | Should -Be @('Drivers\WinPE\Dell', 'Drivers\WinPE\Intel')
            $Task.WinPEExtraFiles | Should -Be @('ExtraFiles\WinPE\Tools')
            $Task.WinPEScripts | Should -Be @('Scripts\WinPE\Config.ps1')
        }

        It 'does not generate the IsoExtract content without -ContentWinPEADK' {
            New-PEBuildTask -TaskName 'Contoso' 6>$null 3>$null | Out-Null
            Should -Invoke Get-TaskContentIsoExtract -Times 0 -Exactly
            Should -Invoke Get-TaskWinPEADK -Times 0 -Exactly
        }

        It 'does not select DaRT for an OSMedia that is not Windows 10 or 11' {
            $script:OSMediaList = @(New-TestOSMedia -Name 'Windows 8.1' -MajorVersion '6' -Build '9600' -ReleaseId '9600')
            New-PEBuildTask -TaskName 'Contoso' -ContentWinPEDart 6>$null 3>$null | Out-Null
            Should -Invoke Get-TaskWinPEDaRT -Times 0 -Exactly
            (Get-TestTask).WinPEDaRT | Should -BeNullOrEmpty
        }

        It 'warns and writes no ContentPacks when ContentPacks are not enabled' {
            Mock Get-IsContentPacksEnabled {$false}
            $Warnings = New-PEBuildTask -TaskName 'Contoso' -AddContentPacks 6>$null 3>&1
            ($Warnings -join "`n") | Should -BeLike '*ContentPacks are not enabled*'
            Should -Invoke Get-TaskContentPacks -Times 0 -Exactly
            (Get-TestTask).ContentPacks | Should -BeNullOrEmpty
        }
    }

    Context 'OSMedia selection' {
        BeforeEach {
            $script:OSMediaList = @(
                New-TestOSMedia -Name 'x64 25H2' -Arch 'x64' -ReleaseId '25H2'
                New-TestOSMedia -Name 'x86 22H2' -Arch 'x86' -ReleaseId '22H2' -Build '19045'
                New-TestOSMedia -Name 'x64 20H2' -Arch 'x64' -ReleaseId '20H2' -Build '19042'
                New-TestOSMedia -Name 'x64 2009' -Arch 'x64' -ReleaseId '2009' -Build '19042'
            )
            foreach ($ReleaseId in '1511', '1607', '1703', '1709', '1803', '1809', '1903', '1909', '2004', '21H1', '21H2', '23H2', '24H2', '26H2') {
                $script:OSMediaList += New-TestOSMedia -Name "x64 $ReleaseId" -ReleaseId $ReleaseId
            }
        }

        It 'selects the OSMedia in Out-GridView from Get-OSMedia sorted by Name' {
            New-PEBuildTask -TaskName 'Contoso' 6>$null 3>$null | Out-Null
            Should -Invoke Get-OSMedia -Times 1 -Exactly -ParameterFilter {($Revision -eq 'OK') -and ($OSMajorVersion -eq 10)}
            Should -Invoke Out-GridView -ParameterFilter {$OutputMode -eq 'Single'}
            @($script:GridInput.Name) | Should -Be @($script:OSMediaList.Name | Sort-Object)
        }

        It 'offers only the OSMedia matching <TaskName>' -ForEach @(
            @{TaskName = 'Contoso x86'; Expected = @('x86 22H2')}
            @{TaskName = 'Contoso x64 25H2'; Expected = @('x64 25H2')}
            @{TaskName = 'Contoso 2009'; Expected = @('x64 2009', 'x64 20H2')}
            @{TaskName = 'Contoso 20H2'; Expected = @('x64 2009', 'x64 20H2')}
            @{TaskName = 'Contoso 22H2'; Expected = @('x86 22H2')}
            @{TaskName = 'Contoso 1511'; Expected = @('x64 1511')}
            @{TaskName = 'Contoso 1607'; Expected = @('x64 1607')}
            @{TaskName = 'Contoso 1703'; Expected = @('x64 1703')}
            @{TaskName = 'Contoso 1709'; Expected = @('x64 1709')}
            @{TaskName = 'Contoso 1803'; Expected = @('x64 1803')}
            @{TaskName = 'Contoso 1809'; Expected = @('x64 1809')}
            @{TaskName = 'Contoso 1903'; Expected = @('x64 1903')}
            @{TaskName = 'Contoso 1909'; Expected = @('x64 1909')}
            @{TaskName = 'Contoso 2004'; Expected = @('x64 2004')}
            @{TaskName = 'Contoso 21H1'; Expected = @('x64 21H1')}
            @{TaskName = 'Contoso 21H2'; Expected = @('x64 21H2')}
            @{TaskName = 'Contoso 23H2'; Expected = @('x64 23H2')}
            @{TaskName = 'Contoso 24H2'; Expected = @('x64 24H2')}
            @{TaskName = 'Contoso 26H2'; Expected = @('x64 26H2')}
        ) {
            New-PEBuildTask -TaskName $TaskName 6>$null 3>$null | Out-Null
            @($script:GridInput.Name) | Should -Be $Expected
            (Get-TestTask "Recovery $TaskName.json").Name | Should -Be $Expected[0]
        }

        It 'exits with a warning when the OSMedia selection is cancelled' {
            Mock Out-GridView {}
            $Warnings = New-PEBuildTask -TaskName 'Contoso' 6>$null 3>&1
            ($Warnings -join "`n") | Should -BeLike '*Source OSMedia was not selected*'
            Join-Path $global:SetOSDBuilderPathTasks 'Recovery Contoso.json' | Should -Not -Exist
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'exits with a warning when Out-GridView fails' {
            Mock Out-GridView {throw 'Out-GridView is not available'}
            $Warnings = foreach ($Once in 1) {New-PEBuildTask -TaskName 'Contoso' 6>$null 3>&1}
            ($Warnings -join "`n") | Should -BeLike '*Source OSMedia was not selected*'
            Join-Path $global:SetOSDBuilderPathTasks 'Recovery Contoso.json' | Should -Not -Exist
        }
    }

    Context 'ReleaseId' {
        It 'reads the ReleaseId from CurrentVersion.xml when the OSMedia has no ReleaseId' {
            $script:OSMediaList = @(New-TestOSMedia -ReleaseId $null -Build '17763' -CurrentVersion @{ReleaseId = '1809'})
            $Warnings = New-PEBuildTask -TaskName 'Contoso' 6>$null 3>&1
            ($Warnings -join "`n") | Should -Not -BeLike '*does not currently support*'
            (Get-TestTask).ReleaseId | Should -Be '1809'
        }

        It 'warns about a ReleaseId newer than 2009 in CurrentVersion.xml' {
            $script:OSMediaList = @(New-TestOSMedia -ReleaseId $null -CurrentVersion @{ReleaseId = '2100'})
            $Warnings = New-PEBuildTask -TaskName 'Contoso' 6>$null 3>&1
            ($Warnings -join "`n") | Should -BeLike '*does not currently support this version of Windows*'
            (Get-TestTask).ReleaseId | Should -Be '2100'
        }

        It 'sets the ReleaseId <ReleaseId> of Build <Build> without CurrentVersion.xml' -ForEach @(
            @{Build = '7601'; ReleaseId = '7601'}, @{Build = '10240'; ReleaseId = '1507'}, @{Build = '14393'; ReleaseId = '1607'}
            @{Build = '15063'; ReleaseId = '1703'}, @{Build = '16299'; ReleaseId = '1709'}, @{Build = '17134'; ReleaseId = '1803'}
            @{Build = '17763'; ReleaseId = '1809'}
        ) {
            $script:OSMediaList = @(New-TestOSMedia -ReleaseId $null -Build $Build)
            New-PEBuildTask -TaskName 'Contoso' 6>$null 3>$null | Out-Null
            (Get-TestTask).ReleaseId | Should -Be $ReleaseId
        }
    }

    Context 'Existing Task' {
        It 'warns that the existing Task is updated' {
            Copy-ExistingTask
            $Warnings = New-PEBuildTask -TaskName 'Contoso' -SourceWim WinPE 6>$null 3>&1
            ($Warnings -join "`n") | Should -BeLike '*Task already exists at*WinPE Contoso.json*'
            ($Warnings -join "`n") | Should -BeLike '*Content will be updated!*'
        }

        It 'keeps the selections of the existing Task without switches' {
            Copy-ExistingTask
            New-PEBuildTask -TaskName 'Contoso' -SourceWim WinPE 6>$null 3>$null | Out-Null
            $Task = Get-TestTask 'WinPE Contoso.json'
            $Task.CustomName | Should -Be 'Existing WinPE'
            $Task.ContentPacks | Should -Be @('_Global', 'Contoso')
            $Task.WinPEDaRT | Should -Be 'DaRT\10\Toolsx64.cab'
            $Task.WinPEADK | Should -Be @('ADK\x64\WinPE_OCs\WinPE-WMI.cab', 'ADK\x64\WinPE_OCs\WinPE-PowerShell.cab')
            $Task.WinPEDrivers | Should -Be @('Drivers\WinPE\Existing')
            $Task.WinPEExtraFiles | Should -Be @('ExtraFiles\WinPE\Existing')
            $Task.WinPEScripts | Should -Be @('Scripts\WinPE\Existing.ps1')
            $Task.WinPEAutoExtraFiles | Should -Be 'True'
            $Task.TaskGuid | Should -Not -Be '5d2d0c55-3a8e-4f0e-8a51-7ef1b0a1d222'
        }

        It 'keeps the MDT Deployment Share of the existing Task' {
            Copy-ExistingTask -Change {$Task.MDTDeploymentShare = 'D:\DeploymentShare'}
            New-PEBuildTask -TaskName 'Contoso' -SourceWim WinPE 6>$null 3>$null | Out-Null
            (Get-TestTask 'WinPE Contoso.json').MDTDeploymentShare | Should -Be 'D:\DeploymentShare'
        }

        It 'uses the given CustomName instead of the existing one' {
            Copy-ExistingTask
            New-PEBuildTask -TaskName 'Contoso' -SourceWim WinPE -CustomName 'New WinPE' 6>$null 3>$null | Out-Null
            (Get-TestTask 'WinPE Contoso.json').CustomName | Should -Be 'New WinPE'
        }

        It 'keeps WinPEAutoExtraFiles False when the existing Task has it False' {
            Copy-ExistingTask -Change {$Task.WinPEAutoExtraFiles = 'False'}
            New-PEBuildTask -TaskName 'Contoso' -SourceWim WinPE 6>$null 3>$null | Out-Null
            (Get-TestTask 'WinPE Contoso.json').WinPEAutoExtraFiles | Should -Be 'False'
        }

        It 'merges the new selections with the existing Task' {
            Copy-ExistingTask
            Mock Get-TaskContentPacks {Item Name 'Fabrikam', 'Contoso'}
            Mock Get-TaskWinPEDaRT {Item FullName 'DaRT\10\New.cab'}
            Mock Get-TaskWinPEADK {Item FullName 'ADK\x64\WinPE_OCs\WinPE-Scripting.cab', 'ADK\x64\WinPE_OCs\WinPE-WMI.cab'}
            Mock Get-TaskWinPEDrivers {Item FullName 'Drivers\WinPE\New'}
            Mock Get-TaskWinPEExtraFiles {Item FullName 'ExtraFiles\WinPE\New'}
            Mock Get-TaskWinPEScripts {Item FullName 'Scripts\WinPE\New.ps1'}
            New-PEBuildTask -TaskName 'Contoso' -SourceWim WinPE -AddContentPacks -ContentWinPEDart -ContentWinPEADK -ContentWinPEDrivers -ContentWinPEExtraFiles -ContentWinPEScripts 6>$null 3>$null | Out-Null

            $Task = Get-TestTask 'WinPE Contoso.json'
            $Task.ContentPacks | Should -Be @('_Global', 'Contoso', 'Fabrikam')
            $Task.WinPEDaRT | Should -Be 'DaRT\10\New.cab'
            $Task.WinPEADK | Should -Be @('ADK\x64\WinPE_OCs\WinPE-WMI.cab', 'ADK\x64\WinPE_OCs\WinPE-Scripting.cab', 'ADK\x64\WinPE_OCs\WinPE-PowerShell.cab')
            $Task.WinPEDrivers | Should -Be @('Drivers\WinPE\Existing', 'Drivers\WinPE\New')
            $Task.WinPEExtraFiles | Should -Be @('ExtraFiles\WinPE\Existing', 'ExtraFiles\WinPE\New')
            $Task.WinPEScripts | Should -Be @('Scripts\WinPE\Existing.ps1', 'Scripts\WinPE\New.ps1')
        }

        # KnownBug: New-PEBuildTask.ps1:340 never applies, -ScratchSpace defaults to '512' and an update resets the ScratchSpace of the existing Task
        It 'keeps the ScratchSpace of the existing Task when -ScratchSpace is not given' -Skip {
            Copy-ExistingTask
            New-PEBuildTask -TaskName 'Contoso' -SourceWim WinPE 6>$null 3>$null | Out-Null
            (Get-TestTask 'WinPE Contoso.json').ScratchSpace | Should -Be '256'
        }
    }
}
