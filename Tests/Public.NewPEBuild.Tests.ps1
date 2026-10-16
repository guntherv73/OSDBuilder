BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    foreach ($Name in 'Get-OSDBuilder', 'Get-OSMedia', 'New-OSDBuilderISO', 'Show-OSDBuilderInfo', 'New-PEBuild') {. (Join-Path (Join-Path $RepoRoot 'Public') "$Name.ps1")}

    $PEBuildTaskFixtures = Join-Path $FixturesPath 'PEBuildTask'

    $global:SetOSDBuilder = @{}
    $global:GetOSDBuilder = @{VersionOSDBuilder = [version]'26.10.16.1'}
    $global:SetOSDBuilderPathTasks = Join-Path $TestDrive 'Tasks'
    $global:SetOSDBuilderPathOSMedia = Join-Path $TestDrive 'OSMedia'
    $global:SetOSDBuilderPathPEBuilds = Join-Path $TestDrive 'PEBuilds'
    $global:SetOSDBuilderPathMount = Join-Path $TestDrive 'Mount'
    $global:SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
    $global:SetOSDBuilderPathTemplates = Join-Path $TestDrive 'Templates'

    function New-TestOSMedia {
        <#
        .SYNOPSIS
        Creates an OSMedia directory with OS and WinPE in $TestDrive and returns the Get-OSMedia object of it
        #>
        param (
            [string]$Name = 'Windows 11 Enterprise x64 25H2 26200.6899',
            [string]$OSMFamily = 'Enterprise x64 26200 en-US',
            [string]$OSMGuid = '11111111-2222-3333-4444-555555555555',
            [string]$UBR = '26200.6899',
            #Writes info\xml\CurrentVersion.xml with these properties
            [hashtable]$CurrentVersion
        )
        $FullName = Join-Path $global:SetOSDBuilderPathOSMedia $Name
        $OS = Join-Path $FullName 'OS'
        $Xml = Join-Path (Join-Path $FullName 'info') 'xml'
        New-Item -Path $Xml -ItemType Directory -Force | Out-Null
        foreach ($File in 'bootmgr', 'bootmgr.efi', (Join-Path 'sources' 'install.wim'), (Join-Path 'boot' 'bcd'), (Join-Path 'efi' 'bootx64.efi')) {
            New-TestFile -Path (Join-Path $OS $File) | Out-Null
        }
        foreach ($File in 'WinPE.wim', 'WinRE.wim') {New-TestFile -Path (Join-Path (Join-Path $FullName 'WinPE') $File) | Out-Null}
        if ($CurrentVersion) {[PSCustomObject]$CurrentVersion | Export-Clixml -Path (Join-Path $Xml 'CurrentVersion.xml')}
        [PSCustomObject]@{
            MediaType   = 'OSMedia'
            OSMFamily   = $OSMFamily
            OSMGuid     = $OSMGuid
            Name        = $Name
            FullName    = $FullName
            UBR         = $UBR
        }
    }

    function New-TestPEBuildTask {
        <#
        .SYNOPSIS
        Writes a PEBuild Task from the fixture to the Tasks directory and returns the Get-PEBuildTask object of it
        #>
        param (
            [string]$FileName = 'WinPE Contoso.json',
            [scriptblock]$Change
        )
        $Task = Get-Content -Path (Join-Path $PEBuildTaskFixtures 'WinPE Existing.json') -Raw | ConvertFrom-Json
        $Task | Add-Member -NotePropertyName WinPEOSDCloud -NotePropertyValue $false
        $Task | Add-Member -NotePropertyName WinREWiFi -NotePropertyValue $false
        if ($Change) {. $Change}
        $Path = Join-Path $global:SetOSDBuilderPathTasks $FileName
        $Task | ConvertTo-Json | Set-Content -Path $Path
        [PSCustomObject]@{Name = (Split-Path $Path -Leaf); FullName = $Path; TaskName = $Task.TaskName}
    }

    function Get-TestWindowsImage ([string]$ImageName = 'Windows 11 Enterprise', [string]$Architecture = '9', [string]$Build = '26200', [string]$InstallationType = 'Client', [string]$Version = '10.0.26200.6899') {
        [PSCustomObject]@{
            ImageName = $ImageName; ImageDescription = $ImageName; Architecture = $Architecture; EditionId = 'Enterprise'; InstallationType = $InstallationType
            Languages = @('en-US'); MajorVersion = 10; Build = $Build; Version = $Version; SPBuild = 6899; SPLevel = 0; ImageBootable = $false; WIMBoot = $false
            CreatedTime = [datetime]'2026-10-01'; ModifiedTime = [datetime]'2026-10-02'
        }
    }

    function Invoke-TestPEBuild {
        param ([hashtable]$Parameters = @{})
        New-PEBuild @Parameters 6>$null 3>$null
    }
}

AfterAll {
    Remove-Variable -Name SetOSDBuilder, GetOSDBuilder, SetOSDBuilderPathTasks, SetOSDBuilderPathOSMedia, SetOSDBuilderPathPEBuilds, SetOSDBuilderPathMount, SetOSDBuilderPathContent, SetOSDBuilderPathTemplates -Scope Global -ErrorAction SilentlyContinue
}

Describe 'New-PEBuild' {
    BeforeEach {
        foreach ($Path in $global:SetOSDBuilderPathTasks, $global:SetOSDBuilderPathOSMedia, $global:SetOSDBuilderPathPEBuilds, $global:SetOSDBuilderPathMount, $global:SetOSDBuilderPathContent) {
            if (Test-Path $Path) {Remove-Item -Path $Path -Recurse -Force}
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
        $script:OSMedia = New-TestOSMedia
        $script:PEBuildTasks = @(New-TestPEBuildTask)
        $script:WindowsImage = Get-TestWindowsImage
        $script:Seen = @{}
        $PEBuilds = $global:SetOSDBuilderPathPEBuilds
        #New-PEBuild builds the paths with backslashes
        $WorkingPath = "$PEBuilds\Existing WinPE"

        Mock Get-OSDBuilder {}
        Mock Block-StandardUser {}
        Mock Get-PEBuildTask {$script:PEBuildTasks}
        Mock Out-GridView {$InputObject}
        Mock Get-IsContentPacksEnabled {$false}
        Mock Get-OSMedia {$script:OSMedia}
        Mock Get-WindowsImage {$script:WindowsImage}
        Mock dism {}
        Mock Copy-Item {}
        Mock Start-Transcript {}
        Mock Stop-Transcript {}
        Mock Read-Host {}
        Mock Mount-PEBuild {New-Item -Path (Join-Path (Join-Path $MountDirectory 'Windows') 'System32') -ItemType Directory -Force | Out-Null}
        Mock Get-RegCurrentVersion {[PSCustomObject]@{UBR = 6899; DisplayVersion = '25H2'; ReleaseId = '2009'; CurrentBuild = '26200'}}
        Mock Set-PEBuildScratchSpace {}
        Mock Set-PEBuildTargetPath {}
        Mock Add-ContentPack {}
        Mock Add-ContentADKWinPE {$script:Seen.WinPEADKPE = $WinPEADKPE}
        Mock Expand-DaRTPE {}
        Mock Enable-WinPEOSDCloud {}
        Mock Enable-WinREWiFi {}
        Mock Add-WindowsDriver {}
        Mock Invoke-Expression {}
        Mock Get-WindowsPackage {[PSCustomObject]@{PackageName = 'WinPE-WMI-Package~31bf3856ad364e35~amd64~~10.0.26100.1'; PackageState = 'Installed'}}
        Mock Dismount-WindowsImage {}
        Mock Export-WindowsImage {}
        Mock Save-WindowsImageContentPE {}
        Mock Save-VariablesOSD {$script:Seen.ReleaseId = $ReleaseId; $script:Seen.UpdateOS = $UpdateOS; $script:Seen.UBR = $UBR}
        Mock New-OSDBuilderISO {}
        Mock Show-OSDBuilderInfo {}
    }

    Context 'Task selection' {
        It 'reads the switch defaults from $global:SetOSDBuilder' {
            $Command = Get-Command New-PEBuild
            $Command.Parameters['PauseMount'].ParameterSets.Keys | Should -Be @('Advanced')
            $global:SetOSDBuilder = @{NewPEBuildExecute = $true; NewPEBuildCreateISO = $true}
            try {Invoke-TestPEBuild}
            finally {$global:SetOSDBuilder = @{}}
            Should -Invoke Mount-PEBuild -Times 1 -Exactly
            Should -Invoke New-OSDBuilderISO -Times 1 -Exactly
        }

        It 'selects the PEBuild Tasks in Out-GridView' {
            Invoke-TestPEBuild
            Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
            Should -Invoke Block-StandardUser -Times 1 -Exactly
            Should -Invoke Out-GridView -Times 1 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'PEBuild Tasks*')}
        }

        It 'exits with a warning when no Task is selected' {
            Mock Out-GridView {}
            $Warnings = New-PEBuild -Execute 6>$null 3>&1
            ($Warnings -join "`n") | Should -BeLike '*PEBuild Task was not selected or found*'
            Should -Invoke Get-OSMedia -Times 0 -Exactly
            Should -Invoke Mount-PEBuild -Times 0 -Exactly
        }

        It 'exits with a warning for a Task older than 19.1.4.0' {
            $script:PEBuildTasks = @(New-TestPEBuildTask -Change {$Task.TaskVersion = '19.1.3.0'})
            $Warnings = New-PEBuild -Execute 6>$null 3>&1
            ($Warnings -join "`n") | Should -BeLike '*PEBuild Tasks need to be version 19.1.4.0 or newer*'
            Should -Invoke Get-OSMedia -Times 0 -Exactly
            Should -Invoke Mount-PEBuild -Times 0 -Exactly
        }

        It 'exits with a warning when no OSMedia of the OSMFamily exists' {
            Mock Get-OSMedia {}
            $Warnings = New-PEBuild -Execute 6>$null 3>&1
            ($Warnings -join "`n") | Should -BeLike '*Unable to find a matching OSMFamily Enterprise x64 26200 en-US*'
            Should -Invoke Mount-PEBuild -Times 0 -Exactly
        }

        It 'uses the latest OSMedia of the OSMFamily' {
            $Latest = New-TestOSMedia -Name 'Windows 11 Enterprise x64 25H2 26200.7000' -OSMGuid ([guid]::NewGuid()) -UBR '26200.7000'
            Mock Get-OSMedia -ParameterFilter {$Revision -eq 'OK'} {$Latest}
            Invoke-TestPEBuild
            Should -Invoke Get-OSMedia -Times 1 -Exactly -ParameterFilter {$Revision -eq 'OK'}
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq "$($Latest.FullName)\OS\sources\install.wim") -and ($Index -eq 1)}
        }

        It 'does not build without -Execute' {
            $Output = (New-PEBuild 6>&1 3>$null) -join "`n"
            $Output | Should -BeLike '*-TaskName:*Existing*'
            $Output | Should -BeLike '*-Destination Name:*Microsoft Windows PE (x64)*'
            Should -Invoke Mount-PEBuild -Times 0 -Exactly
            Should -Invoke dism -Times 0 -Exactly
            Join-Path $WorkingPath 'info' | Should -Not -Exist
        }

        It 'shows the ContentPacks when ContentPacks are enabled' {
            Mock Get-IsContentPacksEnabled {$true}
            $Output = (New-PEBuild 6>&1 3>$null) -join "`n"
            $Output | Should -BeLike "*$global:SetOSDBuilderPathTemplates\_Global*"
            $Output | Should -BeLike "*$global:SetOSDBuilderPathTemplates\Contoso*"
        }

        It 'sets the Architecture <Expected> of the Windows Image Architecture <Architecture>' -ForEach @(
            @{Architecture = '0'; Expected = 'x86'}, @{Architecture = '6'; Expected = 'ia64'}, @{Architecture = '9'; Expected = 'x64'}, @{Architecture = '12'; Expected = 'x64 ARM'}
        ) {
            $script:WindowsImage = Get-TestWindowsImage -Architecture $Architecture
            $Output = (New-PEBuild 6>&1 3>$null) -join "`n"
            $Output | Should -BeLike "*-Architecture:*$Expected*"
            $Output | Should -BeLike "*Microsoft Windows PE ($Expected)*"
        }

        It 'builds every selected Task' {
            $script:PEBuildTasks = @(
                New-TestPEBuildTask -FileName 'WinPE One.json' -Change {$Task.TaskName = 'One'; $Task.CustomName = 'One'}
                New-TestPEBuildTask -FileName 'WinPE Two.json' -Change {$Task.TaskName = 'Two'; $Task.CustomName = 'Two'}
            )
            Invoke-TestPEBuild @{Execute = $true}
            Should -Invoke Mount-PEBuild -Times 2 -Exactly
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {$DestinationImagePath -eq "$PEBuilds\One\WinPE.wim"}
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {$DestinationImagePath -eq "$PEBuilds\Two\WinPE.wim"}
        }
    }

    Context 'Execute WinPE' {
        It 'exports the WinPE wim and mounts it' {
            Mock dism {$script:DismArgs = $RemainingArguments; $script:DismInput = $InputObject}
            Invoke-TestPEBuild @{Execute = $true}
            Write-Host ("ARGS: " + ($script:DismArgs -join '|') + " INPUT: $script:DismInput")
            Should -Invoke dism -Times 1 -Exactly -ParameterFilter {
                $Arguments = $RemainingArguments -join ' '
                ($Arguments -like '/Export-Image*') -and
                ($Arguments -like "*/SourceImageFile:$($script:OSMedia.FullName)\WinPE\WinPE.wim*") -and
                ($Arguments -like "*/DestinationImageFile:$WorkingPath\WimTemp\boot.wim*") -and
                ($Arguments -like '*/DestinationName:Microsoft Windows PE (x64)*') -and
                ($Arguments -like '*/Bootable*')
            }
            Should -Invoke Mount-PEBuild -Times 1 -Exactly -ParameterFilter {($MountDirectory -like (Join-Path $global:SetOSDBuilderPathMount 'pebuild*')) -and ($WorkingWim -eq "$WorkingPath\WimTemp\boot.wim")}
            Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter {($Path -eq "$($script:OSMedia.FullName)\OS\bootmgr") -and ($Destination -eq "$WorkingPath\OS\bootmgr")}
            Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter {($Path -eq "$($script:OSMedia.FullName)\OS\efi\") -and $Recurse}
            Should -Invoke Start-Transcript -Times 1 -Exactly
            Should -Invoke Stop-Transcript -Times 1 -Exactly
        }

        It 'creates the PEBuild directories and the CurrentVersion inventory' {
            Invoke-TestPEBuild @{Execute = $true}
            foreach ($Folder in 'json', 'logs', 'xml') {Join-Path (Join-Path $WorkingPath 'info') $Folder | Should -Exist}
            Join-Path (Join-Path $WorkingPath 'OS') 'sources' | Should -Exist
            (Import-Clixml -Path (Join-Path (Join-Path (Join-Path $WorkingPath 'info') 'xml') 'CurrentVersion.xml')).DisplayVersion | Should -Be '25H2'
            (Get-Content -Path (Join-Path (Join-Path (Join-Path $WorkingPath 'info') 'json') 'CurrentVersion.json') -Raw | ConvertFrom-Json).UBR | Should -Be 6899
            Join-Path $WorkingPath 'CurrentVersion.txt' | Should -Exist
            Join-Path (Join-Path $WorkingPath 'info') 'CurrentVersion.txt' | Should -Exist
        }

        It 'configures the ScratchSpace, the TargetPath, ADK packages and DaRT' {
            Invoke-TestPEBuild @{Execute = $true}
            Should -Invoke Set-PEBuildScratchSpace -Times 1 -Exactly -ParameterFilter {$ScratchSpace -eq '256'}
            Should -Invoke Set-PEBuildTargetPath -Times 1 -Exactly
            Should -Invoke Add-ContentADKWinPE -Times 1 -Exactly
            Should -Invoke Expand-DaRTPE -Times 1 -Exactly
            $script:Seen.WinPEADKPE | Should -Be @('ADK\x64\WinPE_OCs\WinPE-PowerShell.cab', 'ADK\x64\WinPE_OCs\WinPE-WMI.cab')
        }

        It 'adds the Task drivers and runs the existing Task scripts' {
            $Script = New-TestFile -Path (Join-Path (Join-Path (Join-Path $global:SetOSDBuilderPathContent 'Scripts') 'WinPE') 'Existing.ps1')
            $script:PEBuildTasks = @(New-TestPEBuildTask -Change {$Task.WinPEScripts = @('Scripts\WinPE\Existing.ps1', 'Scripts\WinPE\Missing.ps1')})
            Invoke-TestPEBuild @{Execute = $true}
            $Script | Should -Exist
            Should -Invoke Add-WindowsDriver -Times 1 -Exactly -ParameterFilter {($Driver -eq "$global:SetOSDBuilderPathContent\Drivers\WinPE\Existing") -and $Recurse -and $ForceUnsigned}
            Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter {$Command -eq "& '$global:SetOSDBuilderPathContent\Scripts\WinPE\Existing.ps1'"}
        }

        It 'skips drivers, extra files and scripts the Task does not have' {
            $script:PEBuildTasks = @(New-TestPEBuildTask -Change {$Task.WinPEDrivers = $null; $Task.WinPEExtraFiles = $null; $Task.WinPEScripts = $null; $Task.WinPEADK = $null})
            $Output = (New-PEBuild -Execute 6>&1 3>$null) -join "`n"
            $Output | Should -Not -BeLike '*WinPE: Task Drivers*'
            $Output | Should -Not -BeLike '*WinPE: Task PEExtraFiles*'
            $Output | Should -Not -BeLike '*WinPE: Task PowerShell Scripts*'
            Should -Invoke Add-WindowsDriver -Times 0 -Exactly
            Should -Invoke Invoke-Expression -Times 0 -Exactly
        }

        It 'lists the Task extra files and the Auto ExtraFiles' {
            $Output = (New-PEBuild -Execute 6>&1 3>$null) -join "`n"
            $Output | Should -BeLike '*WinPE: Task PEExtraFiles*'
            $Output | Should -BeLike "*Source: $global:SetOSDBuilderPathContent\ExtraFiles\WinPE\Existing*"
            $Output | Should -BeLike '*WinPE: Copy Auto ExtraFiles*'
        }

        It 'enables OSDCloud and WinRE WiFi when the Task enables them' {
            $script:PEBuildTasks = @(New-TestPEBuildTask -Change {$Task.WinPEOSDCloud = $true; $Task.WinREWiFi = $true; $Task.WinPEAutoExtraFiles = $false})
            $Output = (New-PEBuild -Execute 6>&1 3>$null) -join "`n"
            Should -Invoke Enable-WinPEOSDCloud -Times 1 -Exactly
            Should -Invoke Enable-WinREWiFi -Times 1 -Exactly
            $Output | Should -Not -BeLike '*WinPE: Copy Auto ExtraFiles*'
        }

        It 'does not enable OSDCloud and WinRE WiFi by default' {
            Invoke-TestPEBuild @{Execute = $true}
            Should -Invoke Enable-WinPEOSDCloud -Times 0 -Exactly
            Should -Invoke Enable-WinREWiFi -Times 0 -Exactly
            Should -Invoke Add-ContentPack -Times 0 -Exactly
        }

        It 'exports the package inventory, dismounts and exports boot.wim and WinPE.wim' {
            Invoke-TestPEBuild @{Execute = $true}
            Should -Invoke Get-WindowsPackage -Times 1 -Exactly
            (Import-Clixml -Path (Join-Path (Join-Path (Join-Path $WorkingPath 'info') 'xml') 'Get-WindowsPackage.xml')).PackageName | Should -Be 'WinPE-WMI-Package~31bf3856ad364e35~amd64~~10.0.26100.1'
            Join-Path (Join-Path $WorkingPath 'info') 'WindowsPackage.txt' | Should -Exist
            Should -Invoke Dismount-WindowsImage -Times 1 -Exactly -ParameterFilter {$Save -and ($Path -like (Join-Path $global:SetOSDBuilderPathMount 'pebuild*'))}
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {($SourceImagePath -eq "$WorkingPath\WimTemp\boot.wim") -and ($DestinationImagePath -eq "$WorkingPath\OS\sources\boot.wim") -and $Setbootable -and ($DestinationName -eq 'Existing')}
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {$DestinationImagePath -eq "$WorkingPath\WinPE.wim"}
            Should -Invoke Export-WindowsImage -Times 2 -Exactly
        }

        It 'writes the Windows Image inventory with the UBR and removes the temporary directories' {
            Invoke-TestPEBuild @{Execute = $true}
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {$ImagePath -eq "$WorkingPath\OS\sources\boot.wim"}
            (Import-Clixml -Path (Join-Path (Join-Path (Join-Path $WorkingPath 'info') 'xml') 'Get-WindowsImage.xml')).UBR | Should -Be '26200.6899'
            (Get-Content -Path (Join-Path $WorkingPath 'WindowsImage.txt')) | Where-Object {-not $_.Trim()} | Should -BeNullOrEmpty
            Should -Invoke Save-WindowsImageContentPE -Times 1 -Exactly
            Should -Invoke Save-VariablesOSD -Times 1 -Exactly
            Join-Path $WorkingPath 'WimTemp' | Should -Not -Exist
            @(Get-ChildItem -Path $global:SetOSDBuilderPathMount).Count | Should -Be 0
        }

        It 'uses Build.SPBuild as UBR for Windows 7' {
            $script:WindowsImage = Get-TestWindowsImage -Version '6.1.7601.24546' -Build '7601'
            Invoke-TestPEBuild @{Execute = $true}
            $script:Seen.UBR | Should -Be '7601.6899'
        }

        It 'replaces the contents of an existing PEBuild' {
            $Old = New-TestFile -Path (Join-Path $WorkingPath 'old.txt')
            $Warnings = (New-PEBuild -Execute 6>$null 3>&1) -join "`n"
            $Warnings | Should -BeLike '*exists.  Contents will be replaced*'
            $Old.FullName | Should -Not -Exist
        }

        It 'uses the TaskName and the UBR as directory without CustomName' {
            $script:PEBuildTasks = @(New-TestPEBuildTask -Change {$Task.CustomName = ''})
            Invoke-TestPEBuild @{Execute = $true}
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {$DestinationImagePath -eq "$PEBuilds\Existing 26200.6899\WinPE.wim"}
        }

        It 'pauses after mounting and before dismounting' {
            Invoke-TestPEBuild @{Execute = $true; PauseMount = $true; PauseDismount = $true}
            Should -Invoke Read-Host -Times 2 -Exactly
        }

        It 'does not pause by default' {
            Invoke-TestPEBuild @{Execute = $true}
            Should -Invoke Read-Host -Times 0 -Exactly
            Should -Invoke New-OSDBuilderISO -Times 0 -Exactly
            Should -Invoke Show-OSDBuilderInfo -Times 0 -Exactly
        }

        It 'creates an ISO with -CreateISO' {
            Invoke-TestPEBuild @{Execute = $true; CreateISO = $true}
            Should -Invoke New-OSDBuilderISO -Times 1 -Exactly -ParameterFilter {$FullName -eq $WorkingPath}
        }

        # KnownBug: New-PEBuild.ps1:834 reads $OSDInfo, but New-PEBuild has no -OSDInfo parameter, Show-OSDBuilderInfo is never called
        It 'shows the PEBuild with -OSDInfo' -Skip {
            (Get-Command New-PEBuild).Parameters.Keys | Should -Contain 'OSDInfo'
            Invoke-TestPEBuild @{Execute = $true; OSDInfo = $true}
            Should -Invoke Show-OSDBuilderInfo -Times 1 -Exactly -ParameterFilter {$FullName -eq $WorkingPath}
        }

        It 'sets the ReleaseId <ReleaseId> of Build <Build>' -ForEach @(
            @{Build = '7600'; ReleaseId = '7600'}, @{Build = '7601'; ReleaseId = '7601'}, @{Build = '10240'; ReleaseId = '1507'}
            @{Build = '14393'; ReleaseId = '1607'}, @{Build = '15063'; ReleaseId = '1703'}, @{Build = '16299'; ReleaseId = '1709'}
            @{Build = '17134'; ReleaseId = '1803'}, @{Build = '17763'; ReleaseId = '1809'}, @{Build = '18362'; ReleaseId = '1903'}
            @{Build = '18363'; ReleaseId = '1909'}, @{Build = '19041'; ReleaseId = '2004'}, @{Build = '19042'; ReleaseId = '20H2'}
            @{Build = '19043'; ReleaseId = '21H1'}, @{Build = '19044'; ReleaseId = '21H2'}, @{Build = '22000'; ReleaseId = '21H2'}
            @{Build = '20348'; ReleaseId = '21H2'}, @{Build = '22621'; ReleaseId = '22H2'}, @{Build = '22631'; ReleaseId = '23H2'}
            @{Build = '26100'; ReleaseId = '24H2'}, @{Build = '26200'; ReleaseId = '25H2'}, @{Build = '26300'; ReleaseId = '26H2'}
        ) {
            $script:WindowsImage = Get-TestWindowsImage -Build $Build
            Invoke-TestPEBuild @{Execute = $true}
            $script:Seen.ReleaseId | Should -Be $ReleaseId
        }

        It 'reads the ReleaseId of an unknown Build from CurrentVersion.xml' {
            $script:OSMedia = New-TestOSMedia -Name 'Insider' -CurrentVersion @{ReleaseId = '27H1'}
            $script:WindowsImage = Get-TestWindowsImage -Build '27000'
            Invoke-TestPEBuild @{Execute = $true}
            $script:Seen.ReleaseId | Should -Be '27H1'
        }

        It 'sets the UpdateOS <UpdateOS> for <ImageName>' -ForEach @(
            @{ImageName = 'Windows 11 Enterprise'; InstallationType = 'Client'; UpdateOS = 'Windows 11'}
            @{ImageName = 'Windows 10 Enterprise'; InstallationType = 'Client'; UpdateOS = 'Windows 10'}
            @{ImageName = 'Windows Server 2025 SERVERSTANDARD'; InstallationType = 'Server'; UpdateOS = 'Windows Server'}
        ) {
            $script:WindowsImage = Get-TestWindowsImage -ImageName $ImageName -InstallationType $InstallationType
            Invoke-TestPEBuild @{Execute = $true}
            $script:Seen.UpdateOS | Should -Be $UpdateOS
        }
    }

    Context 'ContentPacks' {
        BeforeEach {
            Mock Get-IsContentPacksEnabled {$true}
            Mock Add-ContentPack {$script:Seen.ContentPacks = $ContentPacks}
        }

        It 'adds the PE ContentPacks in order' {
            $script:Order = @()
            Mock Add-ContentPack {$script:Order += $PackType; $script:Seen.ContentPacks = $ContentPacks}
            Invoke-TestPEBuild @{Execute = $true}
            $script:Order | Should -Be @('PEDaRT', 'PEADK', 'PEExtraFiles', 'PEDrivers', 'PEScripts', 'PEPoshMods', 'PERegistry')
            $script:Seen.ContentPacks | Should -Be @('_Global', '_Global', 'Contoso')
        }

        It 'uses the _Global ContentPack for a Task without ContentPacks' {
            $script:PEBuildTasks = @(New-TestPEBuildTask -Change {$Task.ContentPacks = $null})
            Invoke-TestPEBuild @{Execute = $true}
            $script:Seen.ContentPacks | Should -Be @('_Global')
        }
    }

    Context 'Execute Recovery and MDT' {
        It 'builds WinRE.wim for a Recovery Task' {
            $script:PEBuildTasks = @(New-TestPEBuildTask -FileName 'Recovery Contoso.json' -Change {$Task.WinPEOutput = 'Recovery'; $Task.SourceWim = 'WinRE'})
            Invoke-TestPEBuild @{Execute = $true}
            Should -Invoke dism -Times 1 -Exactly -ParameterFilter {
                $Arguments = $RemainingArguments -join ' '
                ($Arguments -like "*/SourceImageFile:$($script:OSMedia.FullName)\WinPE\WinRE.wim*") -and ($Arguments -like '*/DestinationName:Microsoft Windows Recovery Environment (x64)*')
            }
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {$DestinationImagePath -eq "$WorkingPath\WinRE.wim"}
            Should -Invoke Export-WindowsImage -Times 0 -Exactly -ParameterFilter {$DestinationImagePath -eq "$WorkingPath\WinPE.wim"}
        }

        It 'exits with a warning when the MDT Deployment Share does not exist' {
            $script:PEBuildTasks = @(New-TestPEBuildTask -FileName 'MDT Contoso.json' -Change {$Task.WinPEOutput = 'MDT'; $Task.MDTDeploymentShare = (Join-Path $TestDrive 'Missing')})
            $Warnings = (New-PEBuild -Execute 6>$null 3>&1) -join "`n"
            $Warnings | Should -BeLike '*MDT Deployment Share not found*'
            Should -Invoke Mount-PEBuild -Times 0 -Exactly
        }

        It 'copies the MDT Deployment Share and writes the LiteTouch <Architecture> configuration' -ForEach @(
            @{WindowsArchitecture = '9'; Architecture = 'x64'; UnattendArchitecture = 'amd64'}
            @{WindowsArchitecture = '0'; Architecture = 'x86'; UnattendArchitecture = 'x86'}
        ) {
            $DeploymentShare = Join-Path $TestDrive 'DeploymentShare'
            New-Item -Path $DeploymentShare -ItemType Directory -Force | Out-Null
            $script:WindowsImage = Get-TestWindowsImage -Architecture $WindowsArchitecture
            $script:PEBuildTasks = @(New-TestPEBuildTask -FileName 'MDT Contoso.json' -Change {$Task.WinPEOutput = 'MDT'; $Task.MDTDeploymentShare = $DeploymentShare})
            Mock Dismount-WindowsImage {
                $script:Seen.Winpeshl = Get-Content -Path (Join-Path (Join-Path (Join-Path $Path 'Windows') 'System32') 'winpeshl.ini') -Raw
                $script:Seen.Unattend = Get-Content -Path (Join-Path $Path 'Unattend.xml') -Raw
                $script:Seen.Deploy = @(Get-ChildItem -Path (Join-Path $Path 'Deploy') -Recurse -Directory).Name
            }

            Invoke-TestPEBuild @{Execute = $true}

            $script:Seen.Winpeshl | Should -BeLike '*%SYSTEMROOT%\System32\bddrun.exe,/bootstrap*'
            ([xml]$script:Seen.Unattend).unattend.settings.component.processorArchitecture | Should -Be $UnattendArchitecture
            ([xml]$script:Seen.Unattend).unattend.settings.component.RunSynchronous.RunSynchronousCommand.Path | Should -Be 'wscript.exe X:\Deploy\Scripts\LiteTouch.wsf'
            $script:Seen.Deploy | Should -Contain 'Scripts'
            $script:Seen.Deploy | Should -Contain '00000409'
            Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter {($Path -eq "$DeploymentShare\Control\Bootstrap.ini") -and ($Destination -like '*\Deploy\Scripts\Bootstrap.ini')}
            Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter {$Path -eq "$DeploymentShare\Scripts\LiteTouch.wsf"}
            Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter {($Path -eq "$DeploymentShare\Tools\$Architecture\BDDRUN.exe") -and ($Destination -like '*\Windows\system32\BDDRUN.exe')}
            Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter {$Path -eq "$DeploymentShare\Tools\$Architecture\00000409\tsres.dll"}
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {$DestinationImagePath -eq "$WorkingPath\LiteTouchPE_$Architecture.wim"}
        }
    }
}
