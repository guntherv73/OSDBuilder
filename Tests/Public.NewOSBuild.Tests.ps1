BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    foreach ($Public in @('New-OSBuild', 'Get-OSDBuilder', 'Get-OSMedia', 'New-OSDBuilderISO', 'New-OSDBuilderVHD', 'Show-OSDBuilderInfo')) {
        . (Join-Path (Join-Path $RepoRoot 'Public') "$Public.ps1")
    }
    $NewOSBuildFixtures = Join-Path $FixturesPath 'NewOSBuild'

    #The default values of the parameters are read from $global:SetOSDBuilder, restored in AfterAll
    $SavedSetOSDBuilder = $global:SetOSDBuilder
    $global:SetOSDBuilder = $null

    #Private worker functions called by New-OSBuild, tested in their own test files
    #New-DirectoriesOSMedia and Save-RegistryCurrentVersionOS only write to $TestDrive and are not replaced
    $NewOSBuildWorkers = @(
        'Show-WorkingInfoOS', 'Copy-MediaOperatingSystem', 'Mount-WinPEwim', 'Mount-WinREwim', 'Mount-WinSEwim', 'Update-SetupDUMEDIA',
        'Add-ContentADKWinPE', 'Add-ContentADKWinRE', 'Add-ContentADKWinSE', 'Add-LanguagePacksWinRE', 'Add-LanguagePacksWinSE',
        'Expand-DaRTPE', 'Update-ServicingStackPE', 'Update-SafeOSPE', 'Update-CumulativePE',
        'Import-AutoExtraFilesPE', 'Enable-WinPEOSDCloud', 'Enable-WinREWiFi', 'Add-ContentExtraFilesPE', 'Add-ContentDriversPE', 'Add-ContentScriptsPE',
        'Update-SourcesPE', 'Save-PackageInventoryPE', 'Dismount-WimsPE', 'Export-PEWims', 'Export-PEBootWim', 'Save-InventoryPE',
        'Set-WinREWimOS', 'Add-LanguagePacksOS', 'Add-LanguageInterfacePacksOS', 'Add-LanguageFeaturesOnDemandOS',
        'Add-LocalExperiencePacksOS', 'Copy-MediaLanguageSources', 'Set-LanguageSettingsOS', 'Add-WindowsPackageOS', 'Add-FeaturesOnDemandOS',
        'Add-WindowsCapabilityOS', 'Update-ComponentOS', 'Update-ServicingStackOS', 'Update-WindowsSevenOS', 'Update-WindowsServer2012R2OS',
        'Update-AdobeOS', 'Update-DotNetOS', 'Update-OptionalOS', 'Enable-WindowsOptionalFeatureOS', 'Enable-NetFXOS', 'Update-InboxAppsOS',
        'Remove-AppxProvisionedPackageOS', 'Remove-WindowsPackageOS', 'Remove-WindowsCapabilityOS', 'Disable-WindowsOptionalFeatureOS',
        'Add-ContentDriversOS', 'Add-ContentExtraFilesOS', 'Add-ContentStartLayout', 'Add-ContentUnattend', 'Add-ContentScriptsOS',
        'Import-RegistryRegOS', 'Import-RegistryXmlOS', 'Save-AutoExtraFilesOS', 'Save-SessionsXmlOS', 'Save-InventoryOS',
        'Dismount-InstallwimOS', 'Export-InstallwimOS', 'Save-WindowsImageContentOS', 'Save-VariablesOSD',
        'New-OSDBuilderVHD', 'Show-OSDBuilderInfo'
    )

    #Variables of New-OSBuild that the worker functions read from the calling scope
    $NewOSBuildStateNames = @(
        'TaskName', 'TaskVersion', 'CustomName', 'ContentPacks', 'OSMediaName', 'OSMediaPath', 'EnableNetFX3', 'StartLayoutXML', 'UnattendXML',
        'WinPEAutoExtraFiles', 'WinPEOSDCloud', 'WinREWiFi', 'WinPEDaRT', 'ExtraFiles', 'Scripts', 'Drivers', 'AddWindowsCapability',
        'EnableFeature', 'DisableFeature', 'RemoveAppx', 'RemoveCapability', 'WinPEDrivers', 'SetAllIntl', 'SetInputLocale',
        'SetSKUIntlDefaults', 'SetSetupUILang', 'SetSysLocale', 'SetUILang', 'SetUILangFallback', 'SetUserLocale', 'LanguagePacks',
        'OSArchitecture', 'OSBuild', 'ReleaseId', 'UpdateOS', 'OSInstallationType', 'OSMajorVersion', 'WorkingPath', 'MountDirectory',
        'MountWinPE', 'MountWinRE', 'MountWinSE', 'Info', 'OS', 'ScriptName', 'UBR', 'OSDUpdates', 'OSDUpdateSetupDU', 'OSDUpdateComponentDU',
        'OSDUpdateSSU', 'OSDUpdateLCU', 'OSDUpdateAdobeSU', 'OSDUpdateDotNet', 'OSDUpdateOptional', 'OSDUpdateWinSeven'
    )

    function Save-NewOSBuildState ([string]$Key) {
        #Called from a mock, the variables of New-OSBuild are found in the calling scope
        $State = @{}
        foreach ($StateName in $NewOSBuildStateNames) {
            $State[$StateName] = Get-Variable -Name $StateName -ValueOnly -ErrorAction SilentlyContinue
        }
        $global:NewOSBuildState[$Key] = $State
    }

    function New-TestWindowsImage {
        #Get-WindowsImage of an install.wim
        param (
            [string]$ImageName = 'Windows 11 Enterprise',
            [string]$InstallationType = 'Client',
            [string]$EditionId = 'Enterprise',
            $Architecture = 9,
            [int]$MajorVersion = 10,
            [int]$Build = 26200,
            [int]$SPBuild = 6584,
            [string[]]$Languages = @('en-US')
        )
        [PSCustomObject]@{
            ImageName           = $ImageName
            ImageDescription    = $ImageName
            Architecture        = $Architecture
            EditionId           = $EditionId
            InstallationType    = $InstallationType
            Languages           = $Languages
            DefaultLanguageIndex = 0
            Version             = "$MajorVersion.0.$Build.$SPBuild"
            MajorVersion        = $MajorVersion
            MinorVersion        = 0
            Build               = $Build
            SPBuild             = $SPBuild
            SPLevel             = 0
            ImageBootable       = 'No'
            WIMBoot             = $false
            CreatedTime         = [datetime]'2025-09-24'
            ModifiedTime        = [datetime]'2025-09-25'
        }
    }

    function New-TestOSMedia {
        #Creates an OSMedia directory like Import-OSMedia and Update-OSMedia, returns the object of Get-OSMedia
        param (
            [string]$Name = 'Windows 11 Enterprise x64 25H2 26200.6584',
            [string]$Parent = $SetOSDBuilderPathOSMedia,
            [string]$OSMFamily = 'Client Enterprise x64 26200 en-US',
            [string]$OSMGuid = '0d6c3b52-8f0e-4f7a-9a43-41d8b6a0c3f1',
            [string]$Revision = 'OK',
            [string]$Updates = 'OK',
            $WindowsImage = (New-TestWindowsImage),
            #CurrentVersion registry key of the image, no CurrentVersion.xml when $null
            $CurrentVersion = [PSCustomObject]@{CurrentBuild = '26200'; DisplayVersion = '25H2'; ReleaseId = '2009'; UBR = '6584'},
            [switch]$NoWindowsImageTxt,
            [switch]$NoInstallWim
        )
        $FullName = Join-Path $Parent $Name
        $Xml = Join-Path (Join-Path $FullName 'info') 'xml'
        New-Item -Path $Xml -ItemType Directory -Force | Out-Null
        if (-not $NoWindowsImageTxt) {New-TestFile -Path (Join-Path $FullName 'WindowsImage.txt') -Value $WindowsImage.ImageName | Out-Null}
        if (-not $NoInstallWim) {New-TestFile -Path (Join-Path (Join-Path (Join-Path $FullName 'OS') 'sources') 'install.wim') | Out-Null}
        $WindowsImage | Export-Clixml -Path (Join-Path $Xml 'Get-WindowsImage.xml')
        if ($CurrentVersion) {$CurrentVersion | Export-Clixml -Path (Join-Path $Xml 'CurrentVersion.xml')}
        [PSCustomObject]@{
            Name            = $Name
            FullName        = $FullName
            OSMFamily       = $OSMFamily
            OSMGuid         = $OSMGuid
            Revision        = $Revision
            Updates         = $Updates
            ImageName       = $WindowsImage.ImageName
            MajorVersion    = $WindowsImage.MajorVersion
            ModifiedTime    = $WindowsImage.ModifiedTime
        }
    }

    function Copy-TestTask {
        #Copies a Task fixture to the Tasks directory, returns the object of Get-OSBuildTask
        param (
            [string]$Fixture = 'OSBuild Contoso Win11 Ent x64 25H2.json',
            #Properties to change in the Task
            [hashtable]$Change = @{}
        )
        $Destination = Join-Path $SetOSDBuilderPathTasks $Fixture
        Copy-Item -Path (Join-Path $NewOSBuildFixtures $Fixture) -Destination $Destination -Force
        $Json = Get-Content -Path $Destination -Raw | ConvertFrom-Json
        if ($Change.Count) {
            foreach ($Key in $Change.Keys) {$Json | Add-Member -MemberType NoteProperty -Name $Key -Value $Change[$Key] -Force}
            $Json | ConvertTo-Json -Depth 5 | Set-Content -Path $Destination
        }
        [PSCustomObject]@{
            TaskName    = $Json.TaskName
            TaskVersion = $Json.TaskVersion
            FullName    = $Destination
        }
    }

    function New-TestUpdate {
        #Microsoft Update manifest as returned by Get-OSDUpdates
        param (
            [string]$UpdateGroup,
            [string]$KBNumber,
            [string]$UpdateOS = 'Windows 11',
            [string]$UpdateBuild = '25H2',
            [string]$UpdateArch = 'x64',
            [string]$OSDStatus = 'Downloaded',
            [string]$CreationDate = '2025-10-14'
        )
        [PSCustomObject]@{
            UpdateGroup     = $UpdateGroup
            KBNumber        = $KBNumber
            UpdateOS        = $UpdateOS
            UpdateBuild     = $UpdateBuild
            UpdateArch      = $UpdateArch
            OSDStatus       = $OSDStatus
            CreationDate    = $CreationDate
            Title           = "$CreationDate $UpdateGroup $UpdateOS $UpdateBuild $UpdateArch KB$KBNumber"
            FileName        = "windows11.0-kb$KBNumber-$UpdateArch.msu"
        }
    }

    function Invoke-NewOSBuild {
        #Runs New-OSBuild without console output, returns the warnings as text
        param ([hashtable]$Parameters = @{})
        $Output = New-OSBuild @Parameters 6>$null 3>&1
        ($Output | ForEach-Object {"$_"}) -join "`n"
    }

    function Get-NewOSBuildCallIndex ([string]$Name) {
        #Position of the first call in the call log, -1 when not called
        $global:NewOSBuildCalls.IndexOf($Name)
    }
}

AfterAll {
    $global:SetOSDBuilder = $SavedSetOSDBuilder
    Remove-Variable -Name NewOSBuildCalls, NewOSBuildState, ReapplyLCU, UpdateLanguageContent -Scope Global -ErrorAction SilentlyContinue
}

Describe 'New-OSBuild' {
    BeforeEach {
        #Paths set by Get-OSDBuilder
        $BuildHome = Join-Path $TestDrive ([guid]::NewGuid().Guid.Substring(0, 8))
        $SetOSDBuilderPathOSMedia = Join-Path $BuildHome 'OSMedia'
        $SetOSDBuilderPathOSImport = Join-Path $BuildHome 'OSImport'
        $SetOSDBuilderPathOSBuilds = Join-Path $BuildHome 'OSBuilds'
        $SetOSDBuilderPathTasks = Join-Path $BuildHome 'Tasks'
        $SetOSDBuilderPathTemplates = Join-Path $BuildHome 'Templates'
        $SetOSDBuilderPathMount = Join-Path $BuildHome 'Mount'
        $SetOSDBuilderPathContent = Join-Path $BuildHome 'Content'
        $GetOSDBuilderPathContentOneDrive = Join-Path $SetOSDBuilderPathContent 'OneDrive'
        foreach ($Directory in @($SetOSDBuilderPathOSMedia, $SetOSDBuilderPathOSImport, $SetOSDBuilderPathOSBuilds, $SetOSDBuilderPathTasks, $SetOSDBuilderPathMount)) {
            New-Item -Path $Directory -ItemType Directory -Force | Out-Null
        }

        $global:NewOSBuildCalls = [System.Collections.Generic.List[string]]::new()
        $global:NewOSBuildState = @{}

        #Test data, changed in the tests
        $script:OSMediaList = @(New-TestOSMedia)
        $script:TaskList = @(Copy-TestTask)
        $script:Updates = @(
            New-TestUpdate -UpdateGroup 'SSU' -KBNumber '5065381' -CreationDate '2025-09-09'
            New-TestUpdate -UpdateGroup 'LCU' -KBNumber '5066835'
            New-TestUpdate -UpdateGroup 'DotNetCU' -KBNumber '5066128'
            New-TestUpdate -UpdateGroup 'ComponentDU SafeOS' -KBNumber '5067039'
            New-TestUpdate -UpdateGroup 'SetupDU' -KBNumber '5067040'
            New-TestUpdate -UpdateGroup 'LCU' -KBNumber '5066793' -UpdateBuild '24H2'
            New-TestUpdate -UpdateGroup 'LCU' -KBNumber '5066791' -UpdateOS 'Windows 10' -UpdateBuild '22H2'
            New-TestUpdate -UpdateGroup 'LCU' -KBNumber '5066837' -UpdateArch 'arm64'
        )
        $script:WindowsImage = New-TestWindowsImage
        $script:FinalWindowsImage = New-TestWindowsImage -SPBuild 6899
        $script:RegCurrentVersion = @(
            [PSCustomObject]@{CurrentBuild = '26200'; DisplayVersion = '25H2'; ReleaseId = '2009'; UBR = '6584'}
            [PSCustomObject]@{CurrentBuild = '26200'; DisplayVersion = '25H2'; ReleaseId = '2009'; UBR = '6899'}
        )
        $script:RegCurrentVersionCall = 0
        $script:OneDriveSetupPath = $null

        Mock Get-OSDBuilder {}
        Mock Block-StandardUser {}
        Mock Get-OSDUpdates {$script:Updates}
        Mock Get-OSBuildTask {$script:TaskList}
        Mock Get-OSMedia {
            $script:OSMediaList | Where-Object {(-not $Revision) -or ($_.Revision -eq $Revision)}
        }
        Mock Out-GridView {$input}
        Mock Get-IsContentPacksEnabled {$true}
        Mock Get-IsTemplatesEnabled {$false}
        Mock Get-TaskContentPacks {}
        Mock Show-TaskInfo {Save-NewOSBuildState 'Show-TaskInfo'}
        Mock Show-MediaImageInfoOS {}
        Mock Get-OSDUpdateDownloads {}
        Mock Get-WindowsImage {$script:WindowsImage}
        Mock Get-WindowsImage {$script:FinalWindowsImage} -ParameterFilter {$ImagePath -like "$SetOSDBuilderPathOSBuilds*"}
        Mock Get-RegCurrentVersion {
            $script:RegCurrentVersion[[math]::Min($script:RegCurrentVersionCall, $script:RegCurrentVersion.Count - 1)]
            $script:RegCurrentVersionCall++
        }
        Mock Start-Transcript {}
        Mock Stop-Transcript {}
        Mock Start-Sleep {}
        Mock Read-Host {}
        Mock robocopy {$global:NewOSBuildCalls.Add('robocopy')}
        Mock New-OSDBuilderISO {$global:NewOSBuildCalls.Add('New-OSDBuilderISO')}
        foreach ($Worker in $NewOSBuildWorkers) {
            Mock $Worker ([scriptblock]::Create("`$global:NewOSBuildCalls.Add('$Worker')"))
        }
        Mock Add-ContentPack {$global:NewOSBuildCalls.Add("Add-ContentPack $PackType")}
        Mock Update-CumulativeOS {$global:NewOSBuildCalls.Add("Update-CumulativeOS Force:$([bool]$Force)")}
        Mock Invoke-DismCleanupImage {$global:NewOSBuildCalls.Add("Invoke-DismCleanupImage HideCleanupProgress:$([bool]$HideCleanupProgress)")}
        Mock Mount-InstallwimOS {
            $global:NewOSBuildCalls.Add('Mount-InstallwimOS')
            Save-NewOSBuildState 'Mount-InstallwimOS'
            if ($script:OneDriveSetupPath) {New-TestFile -Path (Join-Path $MountDirectory $script:OneDriveSetupPath) | Out-Null}
        }
    }

    Context 'Task selection' {
        It 'reads the Task selected with -ByTaskName without Out-GridView' {
            $script:TaskList = @(Copy-TestTask -Fixture 'OSBuild Legacy DaRT.json'; Copy-TestTask)
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'} | Out-Null
            Should -Invoke Out-GridView -Times 0 -Exactly
            Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
            Should -Invoke Block-StandardUser -Times 1 -Exactly
            $State = $global:NewOSBuildState['Show-TaskInfo']
            $State.TaskName | Should -Be 'Contoso Win11 Ent x64 25H2'
            $State.TaskVersion | Should -Be '22.4.19.1'
            $State.StartLayoutXML | Should -Be 'StartLayout\Contoso.xml'
            $State.UnattendXML | Should -Be 'Unattend\Contoso.xml'
            $State.EnableNetFX3 | Should -Be 'True'
            $State.RemoveAppx | Should -Be 'Microsoft.BingNews_4.55.1.0_neutral_~_8wekyb3d8bbwe'
            $State.AddWindowsCapability | Should -Be 'OpenSSH.Server~~~~0.0.1.0'
            $State.EnableFeature | Should -Be 'TelnetClient'
            $State.DisableFeature | Should -Be 'SMB1Protocol'
            $State.Drivers | Should -Be 'Drivers\Contoso'
        }

        It 'adds the Task ContentPacks to _Global when ContentPacks are enabled' {
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'} | Out-Null
            $global:NewOSBuildState['Show-TaskInfo'].ContentPacks | Should -Be @('_Global', 'Contoso')
        }

        It 'uses only _Global when the Task has no ContentPacks' {
            $script:TaskList = @(Copy-TestTask -Fixture 'OSBuild Legacy DaRT.json')
            Invoke-NewOSBuild @{ByTaskName = 'Legacy DaRT'} | Out-Null
            $global:NewOSBuildState['Show-TaskInfo'].ContentPacks | Should -Be @('_Global')
        }

        It 'does not use ContentPacks with -SkipContentPacks' {
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; SkipContentPacks = $true} | Out-Null
            $global:NewOSBuildState['Show-TaskInfo'].ContentPacks | Should -BeNullOrEmpty
        }

        It 'takes the default Task name from $global:SetOSDBuilder' {
            $global:SetOSDBuilder = [PSCustomObject]@{NewOSBuildByTaskName = 'Contoso Win11 Ent x64 25H2'}
            try {Invoke-NewOSBuild | Out-Null}
            finally {$global:SetOSDBuilder = $null}
            Should -Invoke Out-GridView -Times 0 -Exactly
            $global:NewOSBuildState['Show-TaskInfo'].TaskName | Should -Be 'Contoso Win11 Ent x64 25H2'
        }

        It 'selects the Task in Out-GridView without -ByTaskName' {
            Invoke-NewOSBuild | Out-Null
            Should -Invoke Out-GridView -Times 1 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'OSBuild Tasks: Select one or more Tasks*')}
            $global:NewOSBuildState['Show-TaskInfo'].TaskName | Should -Be 'Contoso Win11 Ent x64 25H2'
        }

        It 'warns and exits when the Out-GridView is canceled' {
            Mock Out-GridView {}
            $Warnings = Invoke-NewOSBuild
            $Warnings | Should -BeLike '*OSBuild Task was not selected or found . . . Exiting!*'
            Should -Invoke Show-TaskInfo -Times 0 -Exactly
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'warns and exits when -ByTaskName does not match a Task' {
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Missing'}
            $Warnings | Should -BeLike '*OSBuild Task was not selected or found*'
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'renames WinPEAddDaRT of an old Task to WinPEDaRT in the Task file' {
            $script:TaskList = @(Copy-TestTask -Fixture 'OSBuild Legacy DaRT.json')
            Invoke-NewOSBuild @{ByTaskName = 'Legacy DaRT'} | Out-Null
            $Json = Get-Content -Path $script:TaskList[0].FullName -Raw
            $Json | Should -Not -BeLike '*WinPEAddDaRT*'
            ($Json | ConvertFrom-Json).WinPEDaRT | Should -Be 'DaRT\DaRT 10\Toolsx64.cab'
            $global:NewOSBuildState['Show-TaskInfo'].WinPEDaRT | Should -Be 'DaRT\DaRT 10\Toolsx64.cab'
        }

        It 'warns and exits when the Task is older than 19.1.4.0' {
            $script:TaskList = @(Copy-TestTask -Change @{TaskVersion = '19.1.3.0'})
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true}
            $Warnings | Should -BeLike '*OSDBuilder Tasks need to be version 19.1.4.0 or newer*'
            $Warnings | Should -BeLike '*Recreate this Task using New-OSBuildTask or Repair-OSBuildTask*'
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
            Should -Invoke Mount-InstallwimOS -Times 0 -Exactly
        }

        It 'builds every Task selected in Out-GridView' {
            $script:TaskList = @(Copy-TestTask; Copy-TestTask -Fixture 'OSBuild Legacy DaRT.json')
            Invoke-NewOSBuild @{Execute = $true} | Out-Null
            Should -Invoke Mount-InstallwimOS -Times 2 -Exactly
            @(Get-ChildItem -Path $SetOSDBuilderPathOSBuilds -Directory).Name | Should -Contain 'Legacy DaRT 26200.6899'
        }
    }

    Context 'Taskless OSBuild with -SkipTask' {
        It 'builds the OSMedia given with -Name without a Task' {
            Invoke-NewOSBuild @{SkipTask = $true; Name = 'Windows 11 Enterprise x64 25H2 26200.6584'; EnableNetFX = $true} | Out-Null
            Should -Invoke Out-GridView -Times 0 -Exactly
            Should -Invoke Get-OSBuildTask -Times 0 -Exactly
            #Show-TaskInfo is only called once, after the Templates
            Should -Invoke Show-TaskInfo -Times 1 -Exactly
            $State = $global:NewOSBuildState['Show-TaskInfo']
            $State.TaskName | Should -Be 'Taskless'
            $State.EnableNetFX3 | Should -BeTrue
            $State.OSMediaPath | Should -Be $script:OSMediaList[0].FullName
            $State.ContentPacks | Should -Be @('_Global')
        }

        It 'selects the OSMedia with Revision OK and OSMajorVersion 10 in Out-GridView' {
            Invoke-NewOSBuild @{SkipTask = $true} | Out-Null
            Should -Invoke Get-OSMedia -Times 1 -Exactly -ParameterFilter {($Revision -eq 'OK') -and ($OSMajorVersion -eq '10')}
            Should -Invoke Out-GridView -Times 1 -Exactly -ParameterFilter {$Title -like 'Select one or more OSMedia to Build*'}
            Should -Invoke Show-MediaImageInfoOS -Times 1 -Exactly
        }

        It 'shows all OSMedia with -ShowHiddenOSMedia' {
            Invoke-NewOSBuild @{SkipTask = $true; ShowHiddenOSMedia = $true} | Out-Null
            Should -Invoke Get-OSMedia -Times 0 -Exactly -ParameterFilter {$Revision -eq 'OK' -and $OSMajorVersion}
            Should -Invoke Out-GridView -Times 1 -Exactly
        }

        It 'warns and exits when no OSMedia is selected' {
            Mock Out-GridView {}
            $Warnings = Invoke-NewOSBuild @{SkipTask = $true}
            $Warnings | Should -BeLike '*Could not find a matching OSMedia . . . Exiting!*'
            Should -Invoke Show-TaskInfo -Times 0 -Exactly
        }

        It 'selects the ContentPacks with -SelectContentPacks' {
            Mock Get-TaskContentPacks {[PSCustomObject]@{Name = 'Contoso'}; [PSCustomObject]@{Name = 'Fabrikam'}} -ParameterFilter {$Select}
            Invoke-NewOSBuild @{SkipTask = $true; Name = 'Windows 11 Enterprise x64 25H2 26200.6584'; SelectContentPacks = $true} | Out-Null
            $global:NewOSBuildState['Show-TaskInfo'].ContentPacks | Should -Be @('Contoso', 'Fabrikam')
        }
    }

    Context 'Source OSMedia' {
        It 'uses the latest OSMedia with Revision OK of the Task OSMFamily' {
            $Superseded = New-TestOSMedia -Name 'Windows 11 Enterprise x64 25H2 26200.6584' -Revision 'Superseded'
            $Latest = New-TestOSMedia -Name 'Windows 11 Enterprise x64 25H2 26200.6899' -OSMGuid ([guid]::NewGuid().Guid)
            $script:OSMediaList = @($Superseded, $Latest)
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'} | Out-Null
            $State = $global:NewOSBuildState['Show-TaskInfo']
            $State.OSMediaName | Should -Be 'Windows 11 Enterprise x64 25H2 26200.6899'
            $State.OSMediaPath | Should -Be $Latest.FullName
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -like "$($Latest.FullName)*install.wim") -and ($Index -eq 1)}
        }

        It 'warns and exits when there is no OSMedia of the Task OSMFamily' {
            $script:OSMediaList = @(New-TestOSMedia -OSMFamily 'Client Professional x64 26200 en-US')
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true}
            $Warnings | Should -BeLike '*Unable to find a matching OSMFamily Client Enterprise x64 26200 en-US*'
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'uses the OSMedia of the Task with -DontUseNewestMedia' {
            $script:OSMediaList = @()
            $TaskOSMedia = New-TestOSMedia
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; DontUseNewestMedia = $true} | Out-Null
            $global:NewOSBuildState['Show-TaskInfo'].OSMediaPath | Should -Be "$SetOSDBuilderPathOSMedia\Windows 11 Enterprise x64 25H2 26200.6584"
            Should -Invoke Get-OSMedia -Times 0 -Exactly
            Should -Invoke Get-WindowsImage -Times 1 -Exactly
        }

        It 'prefers the OSImport directory with -DontUseNewestMedia' {
            New-TestOSMedia | Out-Null
            New-TestOSMedia -Parent $SetOSDBuilderPathOSImport | Out-Null
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; DontUseNewestMedia = $true} | Out-Null
            $global:NewOSBuildState['Show-TaskInfo'].OSMediaPath | Should -Be "$SetOSDBuilderPathOSImport\Windows 11 Enterprise x64 25H2 26200.6584"
        }

        It 'warns when the OSMedia of the Task does not exist with -DontUseNewestMedia' {
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; DontUseNewestMedia = $true; Execute = $true}
            $Warnings | Should -BeLike '*Unable to find an OSMedia to use*'
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'warns when the OSMedia has no WindowsImage.txt' {
            $script:OSMediaList = @(New-TestOSMedia -Name 'Broken' -NoWindowsImageTxt)
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true}
            $Warnings | Should -BeLike "*$($script:OSMediaList[0].FullName) is not a valid OSMedia Directory*"
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'warns when the OSMedia has no install.wim' {
            $script:OSMediaList = @(New-TestOSMedia -Name 'NoWim' -NoInstallWim)
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true}
            $Warnings | Should -BeLike '*install.wim is not a valid Windows Image*'
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'warns and stops for an OSMedia that is not Windows 10 or newer (build <Build>)' -TestCases @(
            @{Build = 7600}, @{Build = 7601}, @{Build = 9600}
        ) {
            $Image = New-TestWindowsImage -ImageName 'Windows 7 Enterprise' -MajorVersion 6 -Build $Build -SPBuild 24000
            $script:OSMediaList = @(New-TestOSMedia -Name 'Windows 7' -WindowsImage $Image -CurrentVersion $null)
            $script:WindowsImage = $Image
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true}
            $Warnings | Should -BeLike "*$($script:OSMediaList[0].FullName) is not supported*"
            Should -Invoke Mount-InstallwimOS -Times 0 -Exactly
        }
    }

    Context 'Operating System and ReleaseId' {
        It 'sets UpdateOS <UpdateOS> and applies only its updates' -TestCases @(
            @{ImageName = 'Windows 11 Enterprise'; InstallationType = 'Client'; UpdateOS = 'Windows 11'}
            @{ImageName = 'Windows 10 Enterprise'; InstallationType = 'Client'; UpdateOS = 'Windows 10'}
            @{ImageName = 'Windows Server 2025 SERVERDATACENTER'; InstallationType = 'Server'; UpdateOS = 'Windows Server'}
        ) {
            $script:WindowsImage = New-TestWindowsImage -ImageName $ImageName -InstallationType $InstallationType
            $script:Updates = @(
                New-TestUpdate -UpdateGroup 'LCU' -KBNumber '1' -UpdateOS 'Windows 11'
                New-TestUpdate -UpdateGroup 'LCU' -KBNumber '2' -UpdateOS 'Windows 10'
                New-TestUpdate -UpdateGroup 'LCU' -KBNumber '3' -UpdateOS 'Windows Server'
            )
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            $State = $global:NewOSBuildState['Mount-InstallwimOS']
            $State.UpdateOS | Should -Be $UpdateOS
            @($State.OSDUpdateLCU).Count | Should -Be 1
            $State.OSDUpdateLCU.UpdateOS | Should -Be $UpdateOS
        }

        It 'reads the ReleaseId <ReleaseId> from the DisplayVersion or ReleaseId of CurrentVersion.xml' -TestCases @(
            @{CurrentVersion = [PSCustomObject]@{CurrentBuild = '19045'; DisplayVersion = '22H2'; ReleaseId = '2009'}; ReleaseId = '22H2'}
            @{CurrentVersion = [PSCustomObject]@{CurrentBuild = '17763'; ReleaseId = '1809'}; ReleaseId = '1809'}
        ) {
            $script:OSMediaList = @(New-TestOSMedia -CurrentVersion $CurrentVersion)
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'} | Out-Null
            $global:NewOSBuildState['Show-TaskInfo'].ReleaseId | Should -Be $ReleaseId
        }

        It 'maps the build <Build> to the ReleaseId <ReleaseId> without CurrentVersion.xml' -TestCases @(
            @{Build = 10240; ReleaseId = '1507'}
            @{Build = 14393; ReleaseId = '1607'}
            @{Build = 15063; ReleaseId = '1703'}
            @{Build = 16299; ReleaseId = '1709'}
            @{Build = 17134; ReleaseId = '1803'}
            @{Build = 17763; ReleaseId = '1809'}
        ) {
            $script:WindowsImage = New-TestWindowsImage -ImageName 'Windows 10 Enterprise' -Build $Build -SPBuild 1
            $script:FinalWindowsImage = New-TestWindowsImage -ImageName 'Windows 10 Enterprise' -Build $Build -SPBuild 2
            $script:RegCurrentVersion = @([PSCustomObject]@{CurrentBuild = "$Build"; UBR = '2'})
            $script:OSMediaList = @(New-TestOSMedia -CurrentVersion $null)
            $script:Updates = @(
                New-TestUpdate -UpdateGroup 'LCU' -KBNumber '1' -UpdateOS 'Windows 10' -UpdateBuild $ReleaseId
                New-TestUpdate -UpdateGroup 'LCU' -KBNumber '2' -UpdateOS 'Windows 10' -UpdateBuild '22H2'
            )
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            $State = $global:NewOSBuildState['Mount-InstallwimOS']
            "$($State.ReleaseId)" | Should -Be $ReleaseId
            $State.OSDUpdateLCU.KBNumber | Should -Be '1'
            #The ReleaseId of the new OSBuild is mapped from the build of the exported install.wim
            (Get-ChildItem -Path $SetOSDBuilderPathOSBuilds -Directory).Name | Should -Be "Windows 10 Enterprise x64 $ReleaseId $Build.2"
        }

        It 'maps the Architecture <Architecture> to <OSArchitecture>' -TestCases @(
            @{Architecture = 0; OSArchitecture = 'x86'}
            @{Architecture = 6; OSArchitecture = 'ia64'}
            @{Architecture = 9; OSArchitecture = 'x64'}
            @{Architecture = 12; OSArchitecture = 'x64 ARM'}
        ) {
            $script:WindowsImage = New-TestWindowsImage -Architecture $Architecture
            $script:FinalWindowsImage = New-TestWindowsImage -Architecture $Architecture -SPBuild 6899
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true; SkipUpdates = $true} | Out-Null
            $global:NewOSBuildState['Mount-InstallwimOS'].OSArchitecture | Should -Be $OSArchitecture
            (Get-ChildItem -Path $SetOSDBuilderPathOSBuilds -Directory).Name | Should -Be "Windows 11 Enterprise $OSArchitecture 25H2 26200.6899"
        }
    }

    Context 'Templates' {
        BeforeEach {
            New-Item -Path $SetOSDBuilderPathTemplates -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path (Join-Path $NewOSBuildFixtures 'Templates') '*.json') -Destination $SetOSDBuilderPathTemplates
        }

        It 'merges the Global and the OSMFamily Templates into the Task and skips the other Templates' {
            $Output = New-OSBuild -ByTaskName 'Contoso Win11 Ent x64 25H2' 6>&1 3>$null | ForEach-Object {"$_"}
            $Output | Should -Contain 'Global: Global Contoso'
            $Output | Should -Contain 'OSMedia Family: Win11 Enterprise Family'
            $Output | Should -Contain 'Skipping: Server 2025 Family'
            $State = $global:NewOSBuildState['Show-TaskInfo']
            $State.ContentPacks | Should -Be @('_Global', 'Contoso', 'Contoso Global')
            $State.Drivers | Should -Be @('Drivers\Contoso', 'Drivers\Global')
            $State.ExtraFiles | Should -Be @('ExtraFiles\Contoso', 'ExtraFiles\Global')
            $State.Scripts | Should -Be @('Scripts\Contoso.ps1', 'Scripts\Global.ps1')
            $State.AddWindowsCapability | Should -Be @('OpenSSH.Server~~~~0.0.1.0', 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0')
            $State.RemoveAppx | Should -Be @('Microsoft.BingNews_4.55.1.0_neutral_~_8wekyb3d8bbwe', 'Microsoft.GamingApp_2509.1001.4.0_neutral_~_8wekyb3d8bbwe')
            $State.EnableFeature | Should -Be @('TelnetClient', 'Microsoft-Windows-Subsystem-Linux')
            $State.WinPEDrivers | Should -Be @('Drivers\WinPE')
            $State.StartLayoutXML | Should -Be 'StartLayout\Global.xml'
            $State.UnattendXML | Should -Be 'Unattend\Global.xml'
            $State.WinPEDaRT | Should -Be 'DaRT\DaRT 10\Toolsx64.cab'
            $State.LanguagePacks | Should -HaveCount 1
            $State.SetInputLocale | Should -Be '0407:00000407'
            $State.SetSKUIntlDefaults | Should -Be 'de-DE'
            $State.SetSetupUILang | Should -Be 'de-DE'
            $State.SetSysLocale | Should -Be 'de-AT'
            $State.SetUILang | Should -Be 'de-DE'
            $State.SetUILangFallback | Should -Be 'en-US'
            $State.SetUserLocale | Should -Be 'de-AT'
        }

        It 'keeps the switches of the Task when the Template value is False' {
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'} | Out-Null
            $State = $global:NewOSBuildState['Show-TaskInfo']
            $State.EnableNetFX3 | Should -Be 'True'
            $State.WinPEAutoExtraFiles | Should -Be 'True'
            $State.WinREWiFi | Should -Be 'True'
            #WinPEOSDCloud is False in the Task and True in the Global Template
            $State.WinPEOSDCloud | Should -Be 'True'
        }

        # KnownBug: New-OSBuild.ps1:429 reads $Task.SetAllIntl, the Templates store the value as LangSetAllIntl
        It 'applies LangSetAllIntl of a Template' -Skip {
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'} | Out-Null
            $global:NewOSBuildState['Show-TaskInfo'].SetAllIntl | Should -Be 'de-DE'
        }

        It 'renames WinPEAddDaRT to WinPEDaRT in the Template files' {
            Set-Content -Path (Join-Path $SetOSDBuilderPathTemplates 'OSBuild Old.json') -Value '{"TaskName": "Old Global", "WinPEAddDaRT": "DaRT\\Old.cab"}'
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'} | Out-Null
            Get-Content -Path (Join-Path $SetOSDBuilderPathTemplates 'OSBuild Old.json') -Raw | Should -BeLike '*"WinPEDaRT"*'
        }

        It 'ignores the Templates with -SkipTemplates' {
            Mock Get-IsTemplatesEnabled {$true}
            Mock Get-OSTemplateDrivers {}
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; SkipTemplates = $true} | Out-Null
            $State = $global:NewOSBuildState['Show-TaskInfo']
            $State.ContentPacks | Should -Be @('_Global', 'Contoso')
            $State.StartLayoutXML | Should -Be 'StartLayout\Contoso.xml'
            Should -Invoke Get-OSTemplateDrivers -Times 0 -Exactly
        }

        It 'lists the Template content when the Templates directories are enabled' {
            Mock Get-IsTemplatesEnabled {$true}
            $Template = Join-Path $SetOSDBuilderPathTemplates 'Drivers'
            Mock Get-OSTemplateDrivers {[PSCustomObject]@{FullName = "$Template\Global\Drivers"}}
            Mock Get-OSTemplateExtraFiles {[PSCustomObject]@{FullName = "$Template\Global\ExtraFiles.txt"}}
            Mock Get-OSTemplateRegistryReg {[PSCustomObject]@{FullName = "$Template\Global\Settings.reg"}}
            Mock Get-OSTemplateRegistryXml {[PSCustomObject]@{FullName = "$Template\Global\Settings.xml"}}
            Mock Get-OSTemplateScripts {[PSCustomObject]@{FullName = "$Template\Global\Script.ps1"}}
            $Output = New-OSBuild -ByTaskName 'Contoso Win11 Ent x64 25H2' 6>&1 3>$null | ForEach-Object {"$_"}
            $Output | Should -Contain 'OSBuild Template Driver Directories (Applied)'
            $Output | Should -Contain "$Template\Global\Drivers"
            $Output | Should -Contain "$Template\Global\ExtraFiles.txt"
            $Output | Should -Contain "$Template\Global\Settings.reg"
            $Output | Should -Contain "$Template\Global\Settings.xml"
            $Output | Should -Contain "$Template\Global\Script.ps1"
        }
    }

    Context 'Updates' {
        It 'applies the updates of the OS, ReleaseId and Architecture by UpdateGroup' {
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            $State = $global:NewOSBuildState['Mount-InstallwimOS']
            $State.OSDUpdateLCU.KBNumber | Should -Be '5066835'
            $State.OSDUpdateSSU.KBNumber | Should -Be '5065381'
            $State.OSDUpdateDotNet.KBNumber | Should -Be '5066128'
            $State.OSDUpdateComponentDU.KBNumber | Should -Be '5067039'
            $State.OSDUpdateSetupDU.KBNumber | Should -Be '5067040'
            $State.OSDUpdateAdobeSU | Should -BeNullOrEmpty
            $State.OSDUpdateWinSeven | Should -BeNullOrEmpty
            #Sorted by CreationDate
            @($State.OSDUpdates)[0].KBNumber | Should -Be '5065381'
        }

        It 'applies no updates with -SkipUpdates' {
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true; SkipUpdates = $true} | Out-Null
            $State = $global:NewOSBuildState['Mount-InstallwimOS']
            $State.OSDUpdates | Should -BeNullOrEmpty
            $State.OSDUpdateLCU | Should -BeNullOrEmpty
            Should -Invoke Update-CumulativeOS -Times 1 -Exactly
        }

        It 'filters the updates with -Include, -Exclude, -IncludeKB and -ExcludeKB' -TestCases @(
            @{Parameters = @{Include = @('LCU', 'SSU')}; KBNumber = @('5065381', '5066835')}
            @{Parameters = @{Exclude = @('LCU', 'SSU', 'DotNetCU')}; KBNumber = @('5067039', '5067040')}
            @{Parameters = @{IncludeKB = @('5066835')}; KBNumber = @('5066835')}
            @{Parameters = @{ExcludeKB = @('5066835', '5066128', '5067039', '5067040')}; KBNumber = @('5065381')}
        ) {
            Invoke-NewOSBuild (@{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} + $Parameters) | Out-Null
            @($global:NewOSBuildState['Mount-InstallwimOS'].OSDUpdates.KBNumber | Sort-Object) | Should -Be $KBNumber
        }

        It 'removes AdobeSU from Server Core and applies it to Desktop Experience' {
            $script:WindowsImage = New-TestWindowsImage -ImageName 'Windows Server 2025 SERVERDATACENTERCORE' -InstallationType 'Server Core'
            $script:Updates = @(
                New-TestUpdate -UpdateGroup 'AdobeSU' -KBNumber '1' -UpdateOS 'Windows Server'
                New-TestUpdate -UpdateGroup 'LCU' -KBNumber '2' -UpdateOS 'Windows Server'
            )
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            $global:NewOSBuildState['Mount-InstallwimOS'].OSDUpdates.KBNumber | Should -Be '2'

            $script:WindowsImage = New-TestWindowsImage -ImageName 'Windows Server 2025 SERVERDATACENTER' -InstallationType 'Server'
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            $global:NewOSBuildState['Mount-InstallwimOS'].OSDUpdateAdobeSU.KBNumber | Should -Be '1'
        }

        It 'applies downloaded Optional updates and updates without UpdateGroup' {
            $script:Updates = @(
                New-TestUpdate -UpdateGroup 'Optional' -KBNumber '1'
                New-TestUpdate -UpdateGroup '' -KBNumber '2' -UpdateBuild ''
                New-TestUpdate -UpdateGroup 'LCU' -KBNumber '3'
            )
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            @($global:NewOSBuildState['Mount-InstallwimOS'].OSDUpdateOptional.KBNumber | Sort-Object) | Should -Be @('1', '2')
        }

        It 'applies the updates selected in Out-GridView with -SelectUpdates' {
            Mock Out-GridView {$input | Where-Object {$_.UpdateGroup -eq 'LCU'}} -ParameterFilter {$Title -eq 'Select Updates to Apply and press OK'}
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true; SelectUpdates = $true} | Out-Null
            $global:NewOSBuildState['Mount-InstallwimOS'].OSDUpdates.KBNumber | Should -Be '5066835'
        }

        It 'disables -Execute and warns when updates are not downloaded' {
            $script:Updates += New-TestUpdate -UpdateGroup 'LCU' -KBNumber '5070000' -OSDStatus 'Not Downloaded' -CreationDate '2025-11-11'
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true}
            $Warnings | Should -BeLike '*Execute is currently disabled as all Updates have not been downloaded*'
            $Warnings | Should -BeLike '*-Download parameter*'
            Should -Invoke Get-OSDUpdateDownloads -Times 0 -Exactly
            Should -Invoke Mount-InstallwimOS -Times 0 -Exactly
        }

        It 'downloads the missing updates with -Download and builds' {
            $script:Updates += New-TestUpdate -UpdateGroup 'LCU' -KBNumber '5070000' -OSDStatus 'Not Downloaded' -CreationDate '2025-11-11'
            $script:Updates += New-TestUpdate -UpdateGroup 'Optional' -KBNumber '5070001' -OSDStatus 'Not Downloaded'
            $Output = New-OSBuild -ByTaskName 'Contoso Win11 Ent x64 25H2' -Execute -Download 6>&1 3>$null | ForEach-Object {"$_"}
            $Output | Should -Contain 'Microsoft Update Manifests Not Downloaded'
            $Output | Should -Contain "Save-OSDBuilderDownload -UpdateOS 'Windows 11' -UpdateBuild 25H2 -UpdateArch x64 -UpdateGroup Optional -Download"
            Should -Invoke Get-OSDUpdateDownloads -Times 1 -Exactly -ParameterFilter {$FileName -eq 'windows11.0-kb5070000-x64.msu'}
            Should -Invoke Mount-InstallwimOS -Times 1 -Exactly
        }

        It 'does not disable -Execute for a missing Optional update' {
            $script:Updates += New-TestUpdate -UpdateGroup 'Optional' -KBNumber '5070001' -OSDStatus 'Not Downloaded'
            $Output = New-OSBuild -ByTaskName 'Contoso Win11 Ent x64 25H2' -Execute 6>&1 3>$null | ForEach-Object {"$_"}
            $Output | Should -Contain 'Microsoft Update Manifests Not Downloaded'
            Should -Invoke Get-OSDUpdateDownloads -Times 0 -Exactly
            Should -Invoke Mount-InstallwimOS -Times 1 -Exactly
        }

        It 'warns when the OSMedia does not have the latest updates' {
            $script:OSMediaList = @(New-TestOSMedia -Updates 'Update')
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'}
            $Warnings | Should -BeLike '*This OSMedia does not have the latest WSUSXML (Microsoft Updates)*'
            $Warnings | Should -BeLike "*Update-OSMedia -Name 'Windows 11 Enterprise x64 25H2 26200.6584' -Download -Execute*"
        }
    }

    Context 'Sandbox mode without -Execute' {
        It 'warns and does not build without -Execute' {
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'}
            $Warnings | Should -BeLike '*Use the -Execute parameter to complete this task*'
            Should -Invoke Mount-InstallwimOS -Times 0 -Exactly
            Should -Invoke Start-Transcript -Times 0 -Exactly
            Get-ChildItem -Path $SetOSDBuilderPathOSBuilds | Should -BeNullOrEmpty
        }

        It 'takes -Execute from $global:SetOSDBuilder.NewOSBuildExecute' {
            $global:SetOSDBuilder = [PSCustomObject]@{NewOSBuildExecute = $true; NewOSBuildCreateISO = $true}
            try {Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'} | Out-Null}
            finally {$global:SetOSDBuilder = $null}
            Should -Invoke Mount-InstallwimOS -Times 1 -Exactly
            Should -Invoke New-OSDBuilderISO -Times 1 -Exactly
        }
    }

    Context 'Build with -Execute' {
        It 'services WinPE, then the install.wim and exports the image in this order' {
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            $Order = @(
                'Show-WorkingInfoOS', 'Copy-MediaOperatingSystem', 'Mount-WinPEwim', 'Mount-WinREwim', 'Mount-WinSEwim', 'Update-SetupDUMEDIA',
                'Add-ContentADKWinPE', 'Add-ContentPack PEADK', 'Add-ContentPack PEADKLang', 'Add-LanguagePacksWinRE', 'Expand-DaRTPE', 'Add-ContentPack PEDaRT',
                'Update-ServicingStackPE', 'Update-SafeOSPE', 'Update-CumulativePE', 'Import-AutoExtraFilesPE', 'Enable-WinPEOSDCloud', 'Enable-WinREWiFi',
                'Add-ContentDriversPE', 'Add-ContentPack PEScripts', 'Update-SourcesPE', 'Save-PackageInventoryPE', 'Dismount-WimsPE', 'Export-PEWims',
                'Export-PEBootWim', 'Save-InventoryPE', 'Mount-InstallwimOS', 'Set-WinREWimOS', 'Add-LanguagePacksOS', 'Add-ContentPack OSLanguagePacks',
                'Add-LocalExperiencePacksOS', 'Copy-MediaLanguageSources', 'Add-ContentPack MEDIA', 'Add-ContentPack OSCapability', 'Add-WindowsPackageOS',
                'Add-FeaturesOnDemandOS', 'Add-WindowsCapabilityOS', 'Update-ComponentOS', 'Update-ServicingStackOS', 'Update-CumulativeOS Force:False',
                'Update-WindowsSevenOS', 'Update-AdobeOS', 'Update-DotNetOS', 'Update-OptionalOS', 'Invoke-DismCleanupImage HideCleanupProgress:False',
                'Enable-WindowsOptionalFeatureOS', 'Enable-NetFXOS', 'Update-InboxAppsOS', 'Remove-AppxProvisionedPackageOS', 'Remove-WindowsPackageOS',
                'Remove-WindowsCapabilityOS', 'Disable-WindowsOptionalFeatureOS', 'Add-ContentDriversOS', 'Add-ContentExtraFilesOS', 'Add-ContentStartLayout',
                'Add-ContentUnattend', 'Add-ContentScriptsOS', 'Import-RegistryRegOS', 'Import-RegistryXmlOS', 'Add-ContentPack OSDrivers',
                'Add-ContentPack OSStartLayout', 'Save-AutoExtraFilesOS', 'Save-SessionsXmlOS', 'Save-InventoryOS', 'Dismount-InstallwimOS',
                'Export-InstallwimOS', 'Save-WindowsImageContentOS', 'Save-VariablesOSD'
            )
            foreach ($Name in $Order) {$global:NewOSBuildCalls | Should -Contain $Name}
            $Indexes = foreach ($Name in $Order) {Get-NewOSBuildCallIndex $Name}
            $Indexes | Should -Be @($Indexes | Sort-Object)
            #Language settings only with language content
            $global:NewOSBuildCalls | Should -Not -Contain 'Set-LanguageSettingsOS'
            $global:NewOSBuildCalls | Should -Not -Contain 'Update-CumulativeOS Force:True'
            $global:NewOSBuildCalls | Should -Not -Contain 'New-OSDBuilderISO'
            Should -Invoke Read-Host -Times 0 -Exactly
            Should -Invoke Start-Transcript -Times 1 -Exactly -ParameterFilter {$Path -like '*-New-OSBuild.log'}
            Should -Invoke Stop-Transcript -Times 1 -Exactly
        }

        It 'passes the working paths and mount directories to the worker functions' {
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            $State = $global:NewOSBuildState['Mount-InstallwimOS']
            $State.ScriptName | Should -Be 'New-OSBuild'
            $State.WorkingPath | Should -BeLike "$SetOSDBuilderPathOSBuilds\build??????????"
            $State.MountDirectory | Should -BeLike (Join-Path $SetOSDBuilderPathMount 'os??????????')
            $State.MountWinPE | Should -BeLike (Join-Path $SetOSDBuilderPathMount 'winpe??????????')
            $State.MountWinRE | Should -BeLike (Join-Path $SetOSDBuilderPathMount 'winre??????????')
            $State.MountWinSE | Should -BeLike (Join-Path $SetOSDBuilderPathMount 'setup??????????')
            $State.Info | Should -Be (Join-Path $State.WorkingPath 'info')
            $State.UBR | Should -BeNullOrEmpty
            Should -Invoke Mount-WinPEwim -Times 1 -Exactly -ParameterFilter {$OSMediaPath -eq $State.WorkingPath}
            Should -Invoke Get-RegCurrentVersion -Times 2 -Exactly -ParameterFilter {$Path -eq $State.MountDirectory}
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {$ImagePath -eq "$($State.OS)\sources\install.wim"}
        }

        It 'renames the build directory to ImageName, Architecture, ReleaseId and UBR and exports the image information' {
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            $Build = Get-ChildItem -Path $SetOSDBuilderPathOSBuilds -Directory
            $Build.Name | Should -Be 'Windows 11 Enterprise x64 25H2 26200.6899'
            $Info = Join-Path $Build.FullName 'info'
            $Xml = Import-Clixml -Path (Join-Path (Join-Path $Info 'xml') 'Get-WindowsImage.xml')
            $Xml.UBR | Should -Be '26200.6899'
            $Xml.ImageName | Should -Be 'Windows 11 Enterprise'
            (Get-Content -Path (Join-Path (Join-Path $Info 'json') 'Get-WindowsImage.json') -Raw | ConvertFrom-Json).SPBuild | Should -Be 6899
            $Text = Get-Content -Path (Join-Path $Build.FullName 'WindowsImage.txt')
            $Text | Should -Contain 'ImageName            : Windows 11 Enterprise'
            $Text | Where-Object {-not $_.Trim()} | Should -BeNullOrEmpty
            #CurrentVersion.xml of the install.wim after the LCU, written by Save-RegistryCurrentVersionOS
            (Import-Clixml -Path (Join-Path (Join-Path $Info 'xml') 'CurrentVersion.xml')).UBR | Should -Be '6899'
        }

        It 'keeps the language of a multi language image in the name' {
            $script:FinalWindowsImage = New-TestWindowsImage -SPBuild 6899 -Languages @('en-US', 'de-DE')
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            (Get-ChildItem -Path $SetOSDBuilderPathOSBuilds -Directory).Name | Should -Be 'Windows 11 Enterprise x64 25H2 26200.6899 en-US de-DE'
        }

        It 'uses the CustomName of the Task and the UBR' {
            $script:TaskList = @(Copy-TestTask -Change @{CustomName = 'Contoso Win11'})
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            (Get-ChildItem -Path $SetOSDBuilderPathOSBuilds -Directory).Name | Should -Be 'Contoso Win11 26200.6899'
        }

        It 'appends a timestamp when the OSBuild already exists' {
            New-Item -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Windows 11 Enterprise x64 25H2 26200.6899') -ItemType Directory | Out-Null
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true}
            $Warnings | Should -BeLike '*Trying to rename the Build directory, but it already exists*'
            (Get-ChildItem -Path $SetOSDBuilderPathOSBuilds -Directory).Name | Should -Contain 'Windows 11 Enterprise x64 25H2 26200.6899'
            @(Get-ChildItem -Path $SetOSDBuilderPathOSBuilds -Directory -Filter 'Windows 11 Enterprise x64 25H2 26200.6899 ??????????') | Should -HaveCount 1
        }

        It 'uses the SPBuild when the registry has no CurrentBuild and UBR' {
            $script:RegCurrentVersion = @([PSCustomObject]@{DisplayVersion = '25H2'})
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            #The SPBuild of the source OSMedia is used for both parts
            (Get-ChildItem -Path $SetOSDBuilderPathOSBuilds -Directory).Name | Should -Be 'Windows 11 Enterprise x64 25H2 6584.6584'
        }

        It 'removes the existing working directory and the temporary mount directories' {
            Mock Mount-InstallwimOS {
                Save-NewOSBuildState 'Mount-InstallwimOS'
                foreach ($Directory in @($MountDirectory, $MountWinPE, $MountWinRE, $MountWinSE)) {New-Item -Path $Directory -ItemType Directory -Force | Out-Null}
            }
            #New-OSBuild uses a working directory with the time in minutes, create it with the next minute too
            $Minute = Get-Date
            foreach ($Time in @($Minute, $Minute.AddMinutes(1))) {
                New-TestFile -Path (Join-Path (Join-Path $SetOSDBuilderPathOSBuilds "build$($Time.ToString('yyMMddhhmm'))") 'old.txt') | Out-Null
            }
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true}
            $Warnings | Should -BeLike '*will be replaced!*'
            Get-ChildItem -Path $SetOSDBuilderPathMount | Should -BeNullOrEmpty
            $Build = Get-ChildItem -Path $SetOSDBuilderPathOSBuilds -Directory -Filter 'Windows 11*'
            Join-Path $Build.FullName 'old.txt' | Should -Not -Exist
            Join-Path $Build.FullName 'WimTemp' | Should -Not -Exist
        }

        It 'sets the language settings and reapplies the LCU after language content' {
            Mock Add-LanguagePacksOS {$global:ReapplyLCU = $true; $global:UpdateLanguageContent = $true; $global:NewOSBuildCalls.Add('Add-LanguagePacksOS')}
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            (Get-NewOSBuildCallIndex 'Set-LanguageSettingsOS') | Should -BeGreaterThan (Get-NewOSBuildCallIndex 'Add-LanguagePacksOS')
            (Get-NewOSBuildCallIndex 'Update-CumulativeOS Force:True') | Should -BeGreaterThan (Get-NewOSBuildCallIndex 'Update-ServicingStackOS')
            @($global:NewOSBuildCalls -like 'Update-CumulativeOS*') | Should -Be @('Update-CumulativeOS Force:True')
        }

        It 'sets the language settings for the Language Packs of the Task' {
            $script:TaskList = @(Copy-TestTask -Fixture 'OSBuild Legacy DaRT.json')
            Invoke-NewOSBuild @{ByTaskName = 'Legacy DaRT'; Execute = $true} | Out-Null
            $global:NewOSBuildCalls | Should -Contain 'Set-LanguageSettingsOS'
        }

        It 'reapplies the LCU before the cleanup when the updates need it' {
            Mock Update-DotNetOS {$global:ReapplyLCU = $true}
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            @($global:NewOSBuildCalls -like 'Update-CumulativeOS*') | Should -Be @('Update-CumulativeOS Force:False', 'Update-CumulativeOS Force:True')
            (Get-NewOSBuildCallIndex 'Update-CumulativeOS Force:True') | Should -BeLessThan (Get-NewOSBuildCallIndex 'Invoke-DismCleanupImage HideCleanupProgress:False')
        }

        It 'hides the cleanup progress with -HideCleanupProgress' {
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true; HideCleanupProgress = $true} | Out-Null
            $global:NewOSBuildCalls | Should -Contain 'Invoke-DismCleanupImage HideCleanupProgress:True'
        }

        It 'creates an ISO of the working directory with -CreateISO' {
            Mock New-OSDBuilderISO {Save-NewOSBuildState 'New-OSDBuilderISO'}
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true; CreateISO = $true} | Out-Null
            $WorkingPath = $global:NewOSBuildState['New-OSDBuilderISO'].WorkingPath
            Should -Invoke New-OSDBuilderISO -Times 1 -Exactly -ParameterFilter {$FullName -eq $WorkingPath}
            Should -Invoke New-OSDBuilderVHD -Times 0 -Exactly
        }

        It 'creates a VHD and shows the info when $OSDVHD and $OSDInfo are set by the caller' {
            $OSDVHD = [switch]$true
            $OSDInfo = [switch]$true
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true} | Out-Null
            Should -Invoke New-OSDBuilderVHD -Times 1 -Exactly -ParameterFilter {$FullName -like "$SetOSDBuilderPathOSBuilds\build*"}
            Should -Invoke Show-OSDBuilderInfo -Times 1 -Exactly -ParameterFilter {$FullName -like "$SetOSDBuilderPathOSBuilds\build*"}
        }

        It 'pauses before WinPE and the install.wim are dismounted with -PauseDismountPE and -PauseDismountOS' {
            Mock Read-Host {$global:NewOSBuildCalls.Add('Read-Host')}
            Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true; PauseDismountPE = $true; PauseDismountOS = $true} | Out-Null
            Should -Invoke Read-Host -Times 2 -Exactly
            $First = $global:NewOSBuildCalls.IndexOf('Read-Host')
            $First | Should -BeLessThan (Get-NewOSBuildCallIndex 'Dismount-WimsPE')
            $First | Should -BeGreaterThan (Get-NewOSBuildCallIndex 'Save-PackageInventoryPE')
            $global:NewOSBuildCalls.LastIndexOf('Read-Host') | Should -Be ((Get-NewOSBuildCallIndex 'Dismount-InstallwimOS') - 1)
        }

        It 'warns and retries when the build directory cannot be renamed' {
            Mock Rename-Item {throw 'The process cannot access the file'}
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true}
            $Warnings | Should -BeLike '*Could not rename the the Build directory ... Waiting 30 seconds ...*'
            $Warnings | Should -BeLike '*Could not rename the the Build directory ...'
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {$Seconds -eq 30}
            Should -Invoke Rename-Item -Times 2 -Exactly
        }

        It 'renames the build directory in the second try' {
            $script:RenameCall = 0
            Mock Rename-Item {
                $script:RenameCall++
                if ($script:RenameCall -eq 1) {throw 'The process cannot access the file'}
                Microsoft.PowerShell.Management\Rename-Item -Path $Path -NewName $NewName
            }
            $Warnings = Invoke-NewOSBuild @{ByTaskName = 'Contoso Win11 Ent x64 25H2'; Execute = $true}
            $Warnings | Should -BeLike '*Waiting 30 seconds*'
            (Get-ChildItem -Path $SetOSDBuilderPathOSBuilds -Directory).Name | Should -Be 'Windows 11 Enterprise x64 25H2 26200.6899'
        }
    }

    Context 'OneDriveSetup.exe' {
        It 'updates <Image> OneDriveSetup.exe from the Content directory on a <Architecture> Client' -TestCases @(
            @{Architecture = 9; Image = 'Windows\SysWOW64\OneDriveSetup.exe'}
            @{Architecture = 0; Image = 'Windows\System32\OneDriveSetup.exe'}
        ) {
            $script:WindowsImage = New-TestWindowsImage -Architecture $Architecture
            $script:OneDriveSetupPath = $Image
            New-TestFile -Path (Join-Path $GetOSDBuilderPathContentOneDrive 'OneDriveSetup.exe') | Out-Null
            $Output = New-OSBuild -ByTaskName 'Contoso Win11 Ent x64 25H2' -Execute 6>&1 3>$null | ForEach-Object {"$_"}
            $Output | Should -Contain 'OS: Update OneDriveSetup.exe'
            $Output | Should -Contain "  Save-OSDBuilderDownload -ContentDownload 'OneDriveSetup Enterprise'"
            $Destination = Split-Path $Image -Parent
            Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {
                ($RemainingArguments[0] -eq $GetOSDBuilderPathContentOneDrive) -and ($RemainingArguments[1] -like "*$Destination") -and ($RemainingArguments[2] -eq 'OneDriveSetup.exe')
            }
        }

        It 'shows the download command and does not copy without OneDriveSetup.exe in the Content directory' {
            $script:OneDriveSetupPath = 'Windows\SysWOW64\OneDriveSetup.exe'
            $Output = New-OSBuild -ByTaskName 'Contoso Win11 Ent x64 25H2' -Execute 6>&1 3>$null | ForEach-Object {"$_"}
            $Output | Should -Contain "  Save-OSDBuilderDownload -ContentDownload 'OneDriveSetup Production'"
            Should -Invoke robocopy -Times 0 -Exactly
        }

        It 'updates an old OneDriveSetup.exe of the Content directory too' {
            $script:OneDriveSetupPath = 'Windows\SysWOW64\OneDriveSetup.exe'
            $Content = New-TestFile -Path (Join-Path $GetOSDBuilderPathContentOneDrive 'OneDriveSetup.exe')
            $Content.LastWriteTime = (Get-Date).AddDays(-10)
            New-OSBuild -ByTaskName 'Contoso Win11 Ent x64 25H2' -Execute 6>$null 3>$null
            Should -Invoke robocopy -Times 1 -Exactly
        }

        It 'does not update OneDriveSetup.exe on <ImageName>' -TestCases @(
            @{ImageName = 'Windows Server 2025 SERVERDATACENTER'; InstallationType = 'Server'; OneDriveSetupPath = 'Windows\SysWOW64\OneDriveSetup.exe'}
            @{ImageName = 'Windows 11 Enterprise'; InstallationType = 'Client'; OneDriveSetupPath = $null}
        ) {
            $script:WindowsImage = New-TestWindowsImage -ImageName $ImageName -InstallationType $InstallationType
            $script:OneDriveSetupPath = $OneDriveSetupPath
            New-TestFile -Path (Join-Path $GetOSDBuilderPathContentOneDrive 'OneDriveSetup.exe') | Out-Null
            $Output = New-OSBuild -ByTaskName 'Contoso Win11 Ent x64 25H2' -Execute 6>&1 3>$null | ForEach-Object {"$_"}
            $Output | Should -Not -Contain 'OS: Update OneDriveSetup.exe'
            Should -Invoke robocopy -Times 0 -Exactly
        }
    }
}
