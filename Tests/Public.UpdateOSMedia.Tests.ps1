<#
Update-OSMedia is the orchestrator that updates an imported OSMedia: it selects the OSMedia, filters the Microsoft Updates,
downloads the missing ones and calls the Private worker functions in a fixed order on a working copy
(OSMedia\buildyyMMddhhmm) that is renamed to the new OSMedia name at the end.
The Private worker functions are mocked (they have their own tests), the tests assert the orchestration.

The Process block of Public\Update-OSMedia.ps1 is shared with New-OSBuild (the bodies are identical except for some
messages). The New-OSBuild branches are covered by invoking the same function body under the name New-OSBuild,
see the Context 'shared New-OSBuild code path'.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    foreach ($PublicName in 'Update-OSMedia', 'Get-OSDBuilder', 'Get-OSMedia', 'New-OSDBuilderISO', 'New-OSDBuilderVHD', 'Show-OSDBuilderInfo') {
        . (Join-Path (Join-Path $RepoRoot 'Public') "$PublicName.ps1")
    }

    $UpdateOSMediaFixtures = Join-Path $FixturesPath 'UpdateOSMedia'
    $script:FixtureImages = Get-Content -Path (Join-Path $UpdateOSMediaFixtures 'WindowsImages.json') -Raw | ConvertFrom-Json
    $script:FixtureRegistry = Get-Content -Path (Join-Path $UpdateOSMediaFixtures 'CurrentVersion.json') -Raw | ConvertFrom-Json
    $script:FixtureUpdates = Get-Content -Path (Join-Path $UpdateOSMediaFixtures 'OSDUpdates.json') -Raw | ConvertFrom-Json
    $script:FixtureTask = Join-Path $UpdateOSMediaFixtures 'OSBuildTask.json'

    #Global variables set by Get-OSDBuilder, restored in AfterAll
    $script:SavedGlobals = @{}
    foreach ($VariableName in 'SetOSDBuilder', 'SetOSDBuilderPathOSImport', 'SetOSDBuilderPathOSMedia', 'SetOSDBuilderPathOSBuilds',
        'SetOSDBuilderPathMount', 'SetOSDBuilderPathTemplates', 'GetOSDBuilderPathContentOneDrive', 'ReapplyLCU', 'UpdateLanguageContent') {
        $script:SavedGlobals[$VariableName] = Get-Variable -Name $VariableName -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    }
    $global:SetOSDBuilder = $null

    #Private worker functions called by Update-OSMedia, every call is recorded in $global:UpdateOSMediaSteps
    $script:WorkerCommands = @(
        'Add-ContentADKWinPE', 'Add-ContentADKWinRE', 'Add-ContentADKWinSE', 'Add-ContentDriversOS', 'Add-ContentDriversPE',
        'Add-ContentExtraFilesOS', 'Add-ContentExtraFilesPE', 'Add-ContentScriptsOS', 'Add-ContentScriptsPE', 'Add-ContentStartLayout',
        'Add-ContentUnattend', 'Add-FeaturesOnDemandOS', 'Add-LanguageFeaturesOnDemandOS', 'Add-LanguageInterfacePacksOS',
        'Add-LanguagePacksOS', 'Add-LanguagePacksWinRE', 'Add-LanguagePacksWinSE', 'Add-LocalExperiencePacksOS', 'Add-WindowsCapabilityOS',
        'Add-WindowsPackageOS', 'Copy-MediaLanguageSources', 'Copy-MediaOperatingSystem', 'Disable-WindowsOptionalFeatureOS',
        'Dismount-InstallwimOS', 'Dismount-WimsPE', 'Enable-NetFXOS', 'Enable-WindowsOptionalFeatureOS', 'Enable-WinPEOSDCloud',
        'Enable-WinREWiFi', 'Expand-DaRTPE', 'Export-InstallwimOS', 'Export-PEBootWim', 'Export-PEWims', 'Get-OSDUpdateDownloads',
        'Import-AutoExtraFilesPE', 'Import-RegistryRegOS', 'Import-RegistryXmlOS', 'Invoke-DismCleanupImage', 'Mount-InstallwimOS',
        'Mount-WinPEwim', 'Mount-WinREwim', 'Mount-WinSEwim', 'Remove-AppxProvisionedPackageOS', 'Remove-WindowsCapabilityOS',
        'Remove-WindowsPackageOS', 'Save-AutoExtraFilesOS', 'Save-InventoryOS', 'Save-InventoryPE', 'Save-PackageInventoryPE',
        'Save-SessionsXmlOS', 'Save-VariablesOSD', 'Save-WindowsImageContentOS', 'Set-LanguageSettingsOS', 'Set-WinREWimOS',
        'Show-MediaImageInfoOS', 'Show-TaskInfo', 'Show-WorkingInfoOS', 'Update-AdobeOS', 'Update-ComponentOS', 'Update-CumulativeOS',
        'Update-CumulativePE', 'Update-DotNetOS', 'Update-InboxAppsOS', 'Update-OptionalOS', 'Update-SafeOSPE', 'Update-ServicingStackOS',
        'Update-ServicingStackPE', 'Update-SetupDUMEDIA', 'Update-SourcesPE', 'Update-WindowsServer2012R2OS', 'Update-WindowsSevenOS',
        'New-OSDBuilderISO', 'New-OSDBuilderVHD', 'Show-OSDBuilderInfo',
        'Get-OSTemplateDrivers', 'Get-OSTemplateExtraFiles', 'Get-OSTemplateRegistryReg', 'Get-OSTemplateRegistryXml', 'Get-OSTemplateScripts'
    )

    function New-TestWindowsImage {
        <#
        .SYNOPSIS
        Get-WindowsImage -Index result from Fixtures\UpdateOSMedia\WindowsImages.json
        #>
        param (
            [string]$Key,
            [string]$ImagePath,
            [hashtable]$Property = @{}
        )
        $Image = $script:FixtureImages.$Key | Select-Object -Property *
        $Image | Add-Member -MemberType NoteProperty -Name ImagePath -Value $ImagePath -Force
        foreach ($Item in $Property.GetEnumerator()) {$Image | Add-Member -MemberType NoteProperty -Name $Item.Key -Value $Item.Value -Force}
        $Image
    }

    function New-TestRegistry {
        <#
        .SYNOPSIS
        Get-RegCurrentVersion result from Fixtures\UpdateOSMedia\CurrentVersion.json
        #>
        param ([string]$Key)
        $script:FixtureRegistry.$Key | Select-Object -Property *
    }

    function New-TestOSMedia {
        <#
        .SYNOPSIS
        Builds an OSMedia directory like Import-OSMedia creates it and registers its Windows Image for the Get-WindowsImage mock
        #>
        param (
            [string]$Parent = $global:SetOSDBuilderPathOSImport,
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$Image,
            [hashtable]$ImageProperty = @{},
            #Key in CurrentVersion.json, no info\xml\CurrentVersion.xml when empty
            [string]$Registry,
            [switch]$NoWindowsImageTxt,
            [switch]$NoInstallWim
        )
        $Path = Join-Path $Parent $Name
        $Info = Join-Path $Path 'info'
        foreach ($Directory in (Join-Path (Join-Path $Path 'OS') 'sources'), (Join-Path $Info 'xml'), (Join-Path $Info 'json'), (Join-Path $Info 'logs'), (Join-Path (Join-Path $Path 'WinPE') 'info')) {
            New-Item -Path $Directory -ItemType Directory -Force | Out-Null
        }
        $InstallWim = Join-Path (Join-Path (Join-Path $Path 'OS') 'sources') 'install.wim'
        $WindowsImage = New-TestWindowsImage -Key $Image -ImagePath $InstallWim -Property $ImageProperty
        if (-not $NoInstallWim) {New-TestFile -Path $InstallWim -Value 'MSWIM' | Out-Null}
        if (-not $NoWindowsImageTxt) {$WindowsImage | Out-File -FilePath (Join-Path $Path 'WindowsImage.txt')}
        $WindowsImage | Export-Clixml -Path (Join-Path (Join-Path $Info 'xml') 'Get-WindowsImage.xml')
        $WindowsImage | ConvertTo-Json | Out-File -FilePath (Join-Path (Join-Path $Info 'json') 'Get-WindowsImage.json')
        if ($Registry) {
            $RegKey = New-TestRegistry -Key $Registry
            $RegKey | Export-Clixml -Path (Join-Path (Join-Path $Info 'xml') 'CurrentVersion.xml')
            $RegKey | ConvertTo-Json | Out-File -FilePath (Join-Path (Join-Path $Info 'json') 'CurrentVersion.json')
        }
        $script:SourceImages[$Name] = $WindowsImage
        Get-Item -Path $Path
    }

    function New-TestUpdate {
        <#
        .SYNOPSIS
        Get-OSDUpdates result item
        #>
        param ($UpdateOS = 'Windows 10', $UpdateBuild, $UpdateGroup = 'LCU', $KBNumber, $OSDStatus = '', $UpdateArch = 'x64')
        [PSCustomObject]@{
            UpdateOS     = $UpdateOS
            UpdateBuild  = $UpdateBuild
            UpdateArch   = $UpdateArch
            UpdateGroup  = $UpdateGroup
            KBNumber     = $KBNumber
            CreationDate = '2026-10-14T10:00:00'
            OSDStatus    = $OSDStatus
            Title        = "Cumulative Update for $UpdateOS Version $UpdateBuild for x64-based Systems (KB$KBNumber)"
            FileName     = "windows10.0-kb$KBNumber-x64_0123456789abcdef0123456789abcdef01234567.msu"
        }
    }

    function Get-TestUpdate {
        <#
        .SYNOPSIS
        Updates of OSDUpdates.json for one Operating System and release
        #>
        param ($UpdateOS, $UpdateBuild)
        $script:FixtureUpdates | Where-Object {($_.UpdateOS -eq $UpdateOS) -and ($_.UpdateBuild -eq $UpdateBuild) -and ($_.UpdateArch -eq 'x64')}
    }

    function Assert-StepOrder {
        <#
        .SYNOPSIS
        Asserts that the steps were called in this order (other steps may be called in between)
        #>
        param ([string[]]$Expected)
        $Steps = @($global:UpdateOSMediaSteps)
        $Position = -1
        foreach ($Step in $Expected) {
            $Found = -1
            for ($i = $Position + 1; $i -lt $Steps.Count; $i++) {
                if ($Steps[$i] -eq $Step) {$Found = $i; break}
            }
            $Found | Should -BeGreaterThan $Position -Because "'$Step' should be called after step $Position of: $($Steps -join ', ')"
            $Position = $Found
        }
    }

    function Invoke-UpdateOSMedia {
        <#
        .SYNOPSIS
        Runs Update-OSMedia (or the shared body as New-OSBuild), returns the warnings
        Break in the production code leaves the nearest loop, the foreach keeps it inside this function
        #>
        param (
            [hashtable]$Parameters = @{},
            [string]$Command = 'Update-OSMedia',
            $InputObject
        )
        foreach ($Guard in 1) {
            if ($null -ne $InputObject) {
                $Output = $InputObject | & $Command @Parameters 3>&1 6>$null
            } else {
                $Output = & $Command @Parameters 3>&1 6>$null
            }
        }
        @($Output | Where-Object {$_ -is [System.Management.Automation.WarningRecord]} | ForEach-Object {$_.Message})
    }

    function Get-RenamedOSMedia {
        <#
        .SYNOPSIS
        Names of the directories in OSMedia, without the source OSMedia
        #>
        param ([string]$Path = $global:SetOSDBuilderPathOSMedia)
        @(Get-ChildItem -Path $Path -Directory | Select-Object -ExpandProperty Name)
    }
}

AfterAll {
    foreach ($Item in $script:SavedGlobals.GetEnumerator()) {
        Set-Variable -Name $Item.Key -Value $Item.Value -Scope Global
    }
    Remove-Variable -Name UpdateOSMediaSteps -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Update-OSMedia' {
    BeforeEach {
        $Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $global:SetOSDBuilderPathOSImport = Join-Path $Root 'OSImport'
        $global:SetOSDBuilderPathOSMedia = Join-Path $Root 'OSMedia'
        $global:SetOSDBuilderPathOSBuilds = Join-Path $Root 'OSBuilds'
        $global:SetOSDBuilderPathMount = Join-Path $Root 'Mount'
        $global:SetOSDBuilderPathTemplates = Join-Path $Root 'Templates'
        $global:GetOSDBuilderPathContentOneDrive = Join-Path (Join-Path $Root 'Content') 'OneDrive'
        foreach ($Directory in $global:SetOSDBuilderPathOSImport, $global:SetOSDBuilderPathOSMedia, $global:SetOSDBuilderPathOSBuilds, $global:SetOSDBuilderPathMount) {
            New-Item -Path $Directory -ItemType Directory -Force | Out-Null
        }

        $script:SourceImages = @{}
        $script:TestUpdates = @($script:FixtureUpdates)
        $script:PostImage = $null
        $script:RegistryPre = New-TestRegistry -Key 'Win11-24H2-1742'
        $script:RegistryPost = New-TestRegistry -Key 'Win11-24H2-6899'
        $script:RegistryCalls = 0
        $script:Seen = @{}
        $global:UpdateOSMediaSteps = New-Object System.Collections.Generic.List[string]

        foreach ($Worker in $script:WorkerCommands) {
            Mock -CommandName $Worker -MockWith ([scriptblock]::Create("`$global:UpdateOSMediaSteps.Add('$Worker')"))
        }
        Mock Add-ContentPack {$global:UpdateOSMediaSteps.Add("Add-ContentPack $PackType")}
        Mock Get-OSDBuilder {}
        Mock Block-StandardUser {}
        Mock Get-OSDUpdates {$script:TestUpdates}
        Mock Get-OSMedia {}
        Mock Out-GridView {$InputObject}
        Mock Get-IsTemplatesEnabled {$false}
        Mock Get-IsContentPacksEnabled {$false}
        Mock Start-Transcript {}
        Mock Stop-Transcript {}
        Mock Start-Sleep {}
        Mock Read-Host {}
        Mock robocopy {}
        Mock Get-RegCurrentVersion {
            $script:RegistryCalls++
            if ($script:RegistryCalls -eq 1) {$script:RegistryPre} else {$script:RegistryPost}
        }
        #Writes info\xml\CurrentVersion.xml of the working directory like the real function
        Mock Save-RegistryCurrentVersionOS {
            $global:UpdateOSMediaSteps.Add('Save-RegistryCurrentVersionOS')
            $RegKeyCurrentVersion | Export-Clixml -Path (Join-Path (Join-Path $Info 'xml') 'CurrentVersion.xml')
        }
        Mock Get-WindowsImage {
            if (($ImagePath -match 'build\d{10}') -and $script:PostImage) {return $script:PostImage}
            foreach ($Key in $script:SourceImages.Keys) {
                if ($ImagePath -like "*$Key*") {return $script:SourceImages[$Key]}
            }
        }

        $Win11Name = 'Windows 11 Enterprise x64 24H2 26100.1742'
        $Win11NewName = 'Windows 11 Enterprise x64 24H2 26100.6899'
    }

    Context 'OSMedia selection' {
        BeforeEach {
            New-TestOSMedia -Name $Win11Name -Image 'Win11Enterprise24H2' -Registry 'Win11-24H2-1742' | Out-Null
        }

        It 'uses the OSMedia of -Name without Get-OSMedia and Out-GridView' {
            Invoke-UpdateOSMedia -Parameters @{Name = $Win11Name} | Out-Null
            Should -Invoke Get-OSMedia -Times 0 -Exactly
            Should -Invoke Out-GridView -Times 0 -Exactly
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -like "*$Win11Name*install.wim") -and ($Index -eq 1)}
            Should -Invoke Show-MediaImageInfoOS -Times 1 -Exactly
        }

        It 'updates every OSMedia of -Name' {
            New-TestOSMedia -Name 'Windows 10 Enterprise x64 22H2 19045.2965' -Image 'Win10Enterprise22H2' -Registry 'Win10-22H2-2965' | Out-Null
            Invoke-UpdateOSMedia -Parameters @{Name = $Win11Name, 'Windows 10 Enterprise x64 22H2 19045.2965'} | Out-Null
            Should -Invoke Show-MediaImageInfoOS -Times 2 -Exactly
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {$ImagePath -like '*19045.2965*'}
        }

        It 'accepts the OSMedia from the pipeline by property name' {
            Invoke-UpdateOSMedia -InputObject ([PSCustomObject]@{Name = $Win11Name}) | Out-Null
            Should -Invoke Show-MediaImageInfoOS -Times 1 -Exactly
            Should -Invoke Out-GridView -Times 0 -Exactly
        }

        It 'shows the OSMedia that needs updates in Out-GridView without legacy Operating Systems' {
            Mock Get-OSMedia {
                [PSCustomObject]@{Name = $Win11Name; MajorVersion = 10; InstallationType = 'Client'; Version = '10.0.26100.1742'}
                [PSCustomObject]@{Name = 'Windows 7 Enterprise x64 7601.17514'; MajorVersion = 6; InstallationType = 'Client'; Version = '6.1.7601.17514'}
                [PSCustomObject]@{Name = 'Windows Server 2012 R2 x64 9600.17031'; MajorVersion = 6; InstallationType = 'Server'; Version = '6.3.9600.17031'}
                [PSCustomObject]@{Name = 'Windows 8.1 Enterprise x64 9600.17031'; MajorVersion = 6; InstallationType = 'Client'; Version = '6.3.9600.17031'}
            } -ParameterFilter {($Revision -eq 'OK') -and ($Updates -eq 'Update')}
            Mock Out-GridView {
                $script:Seen['Grid'] = @($script:Seen['Grid']) + @($InputObject.Name) | Where-Object {$_}
                $script:Seen['GridTitle'] = $Title
                if ($InputObject.Name -eq $Win11Name) {$InputObject}
            }
            Invoke-UpdateOSMedia | Out-Null
            $script:Seen['Grid'] | Should -Be @($Win11Name, 'Windows 7 Enterprise x64 7601.17514', 'Windows Server 2012 R2 x64 9600.17031')
            $script:Seen['GridTitle'] | Should -BeLike 'Select one or more OSMedia to Update*'
            Should -Invoke Show-MediaImageInfoOS -Times 1 -Exactly
        }

        It 'shows all OSMedia with -ShowHiddenOSMedia' {
            Mock Get-OSMedia {[PSCustomObject]@{Name = $Win11Name; MajorVersion = 10}}
            Invoke-UpdateOSMedia -Parameters @{ShowHiddenOSMedia = $true} | Out-Null
            Should -Invoke Get-OSMedia -Times 1 -Exactly -ParameterFilter {(-not $Revision) -and (-not $Updates)}
            Should -Invoke Show-MediaImageInfoOS -Times 1 -Exactly
        }

        It 'does nothing when the selection in Out-GridView is cancelled' {
            Mock Get-OSMedia {[PSCustomObject]@{Name = $Win11Name; MajorVersion = 10}}
            Mock Out-GridView {}
            $Warnings = Invoke-UpdateOSMedia -Parameters @{Execute = $true}
            $Warnings | Should -BeNullOrEmpty
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
            Should -Invoke Mount-InstallwimOS -Times 0 -Exactly
        }

        It 'removes legacy and updated OSMedia when $UpdateNeeded is set by the caller' {
            #UpdateNeeded is not a parameter of Update-OSMedia (any more), the variable is read from the calling scope
            $UpdateNeeded = [switch]$true
            Mock Get-OSMedia {
                [PSCustomObject]@{Name = $Win11Name; MajorVersion = 10; Servicing = ''; Cumulative = 'KB5066835'; Adobe = 'KB4580325'}
                [PSCustomObject]@{Name = 'Windows 10 Enterprise x64 22H2 19045.6456'; MajorVersion = 10; Servicing = 'KB5031539'; Cumulative = 'KB5066791'; Adobe = 'KB4580325'}
                [PSCustomObject]@{Name = 'Windows 7 Enterprise x64 7601.17514'; MajorVersion = 6; InstallationType = 'Client'; Version = '6.1.7601.17514'; Servicing = ''}
            }
            Mock Out-GridView {$script:Seen['Grid'] = @($script:Seen['Grid']) + @($InputObject.Name) | Where-Object {$_}; $InputObject}
            $Warnings = Invoke-UpdateOSMedia
            $Warnings | Should -Contain 'UpdateNeeded does not support Legacy Operating Systems'
            $script:Seen['Grid'] | Should -Be @($Win11Name)
        }

        It 'has an -UpdateNeeded parameter for the UpdateNeeded filter' -Skip {
            # KnownBug: Update-OSMedia.ps1:201 filters on $UpdateNeeded, but Update-OSMedia has no UpdateNeeded parameter (dead code, the value leaks from the caller scope)
            (Get-Command Update-OSMedia).Parameters.Keys | Should -Contain 'UpdateNeeded'
        }
    }

    Context 'OSMedia validation' {
        It 'warns when the OSMedia of -Name does not exist' {
            $Warnings = Invoke-UpdateOSMedia -Parameters @{Name = 'Windows 11 Enterprise x64 24H2 26100.9999'; Execute = $true}
            $Warnings | Should -Contain 'Unable to find an OSMedia to use'
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'warns when the directory has no WindowsImage.txt' {
            New-TestOSMedia -Name $Win11Name -Image 'Win11Enterprise24H2' -NoWindowsImageTxt | Out-Null
            $Warnings = Invoke-UpdateOSMedia -Parameters @{Name = $Win11Name; Execute = $true}
            ($Warnings -like '*is not a valid OSMedia Directory') | Should -HaveCount 1
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'warns when OS\sources\install.wim is missing' {
            New-TestOSMedia -Name $Win11Name -Image 'Win11Enterprise24H2' -NoInstallWim | Out-Null
            $Warnings = Invoke-UpdateOSMedia -Parameters @{Name = $Win11Name; Execute = $true}
            ($Warnings -like '*install.wim is not a valid Windows Image') | Should -HaveCount 1
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'prefers the OSMedia directory over the OSImport directory with the same name' {
            New-TestOSMedia -Name $Win11Name -Image 'Win11Enterprise24H2' -Registry 'Win11-24H2-1742' | Out-Null
            New-TestOSMedia -Parent $global:SetOSDBuilderPathOSMedia -Name $Win11Name -Image 'Win11Enterprise24H2' -Registry 'Win11-24H2-1742' | Out-Null
            Invoke-UpdateOSMedia -Parameters @{Name = $Win11Name} | Out-Null
            $OSMediaLeaf = Split-Path $global:SetOSDBuilderPathOSMedia -Leaf
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {$ImagePath -like "*$OSMediaLeaf*$Win11Name*"}
        }

        It 'does not update <Name> (not supported)' -ForEach @(
            @{Name = 'Windows 7 ENTERPRISE x64 7601.17514'; Image = 'Win7Enterprise'; Property = @{}}
            @{Name = 'Windows 7 ENTERPRISE x64 7600.16385'; Image = 'Win7Enterprise'; Property = @{Build = 7600; SPBuild = 16385; Version = '6.1.7600.16385'}}
            @{Name = 'Windows Server 2012 R2 SERVERSTANDARD x64 9600.17031'; Image = 'Server2012R2Standard'; Property = @{}}
        ) {
            New-TestOSMedia -Name $Name -Image $Image -ImageProperty $Property | Out-Null
            $Warnings = Invoke-UpdateOSMedia -Parameters @{Name = $Name; Download = $true; Execute = $true}
            ($Warnings -like '*is not supported') | Should -HaveCount 1
            Should -Invoke Get-OSDUpdateDownloads -Times 0 -Exactly
            Should -Invoke Mount-InstallwimOS -Times 0 -Exactly
        }

        It 'continues with the next OSMedia after an unsupported OSMedia' -Skip {
            # KnownBug: Update-OSMedia.ps1:543 uses Break for an unsupported OSMedia, which also skips the remaining OSMedia of -Name (Continue is expected)
            New-TestOSMedia -Name 'Windows 7 ENTERPRISE x64 7601.17514' -Image 'Win7Enterprise' | Out-Null
            New-TestOSMedia -Name $Win11Name -Image 'Win11Enterprise24H2' -Registry 'Win11-24H2-1742' | Out-Null
            Invoke-UpdateOSMedia -Parameters @{Name = 'Windows 7 ENTERPRISE x64 7601.17514', $Win11Name} | Out-Null
            Should -Invoke Show-MediaImageInfoOS -Times 2 -Exactly
        }
    }

    Context 'Microsoft Updates (without -Execute)' {
        BeforeEach {
            New-TestOSMedia -Name $Win11Name -Image 'Win11Enterprise24H2' -Registry 'Win11-24H2-1742' | Out-Null
        }

        It 'asks for -Execute and does not change the OSMedia' {
            $Warnings = Invoke-UpdateOSMedia -Parameters @{Name = $Win11Name; Download = $true}
            $Warnings | Should -Contain 'Use the -Execute parameter to complete this task'
            Should -Invoke Mount-InstallwimOS -Times 0 -Exactly
            Get-RenamedOSMedia | Should -BeNullOrEmpty
        }

        It 'disables -Execute when updates are missing and -Download is not used' {
            $Warnings = Invoke-UpdateOSMedia -Parameters @{Name = $Win11Name; Execute = $true}
            $Warnings | Should -Contain 'Execute is currently disabled as all Updates have not been downloaded'
            $Warnings | Should -Contain 'You can automatically download required Updates by adding the -Download parameter'
            Should -Invoke Get-OSDUpdateDownloads -Times 0 -Exactly
            Should -Invoke Mount-InstallwimOS -Times 0 -Exactly
        }

        It 'downloads only the missing required updates of Windows 11 24H2 x64 with -Download' {
            $HostOutput = (Update-OSMedia -Name $Win11Name -Download 3>$null 6>&1) -join ' '
            Should -Invoke Get-OSDUpdateDownloads -Times 1 -Exactly
            Should -Invoke Get-OSDUpdateDownloads -Times 1 -Exactly -ParameterFilter {$FileName -like 'windows11.0-kb5066131-x64-ndp481*'}
            #Optional updates are listed with the download command but not downloaded
            $HostOutput | Should -BeLike "*Save-OSDBuilderDownload -UpdateOS 'Windows 11' -UpdateBuild 24H2 -UpdateArch x64 -UpdateGroup Optional -Download*"
            $HostOutput | Should -BeLike '*Microsoft Update Manifests Downloaded*KB5066835*'
        }

        It 'applies no updates with -SkipUpdates' {
            $Warnings = Invoke-UpdateOSMedia -Parameters @{Name = $Win11Name; SkipUpdates = $true}
            Should -Invoke Get-OSDUpdateDownloads -Times 0 -Exactly
            $Warnings | Should -Not -Contain 'Execute is currently disabled as all Updates have not been downloaded'
        }

        It 'downloads only the update groups of -Include' {
            $script:TestUpdates = @($script:FixtureUpdates | Select-Object -Property * | ForEach-Object {$_.OSDStatus = ''; $_})
            Invoke-UpdateOSMedia -Parameters @{Name = $Win11Name; Download = $true; Include = 'LCU'} | Out-Null
            Should -Invoke Get-OSDUpdateDownloads -Times 1 -Exactly
            Should -Invoke Get-OSDUpdateDownloads -Times 1 -Exactly -ParameterFilter {$FileName -like 'windows11.0-kb5066835*'}
        }

        It 'does not download the update groups of -Exclude' {
            $script:TestUpdates = @($script:FixtureUpdates | Select-Object -Property * | ForEach-Object {$_.OSDStatus = ''; $_})
            Invoke-UpdateOSMedia -Parameters @{Name = $Win11Name; Download = $true; Exclude = 'LCU', 'DotNetCU'} | Out-Null
            Should -Invoke Get-OSDUpdateDownloads -Times 2 -Exactly
            Should -Invoke Get-OSDUpdateDownloads -Times 0 -Exactly -ParameterFilter {$FileName -like 'windows11.0-kb5066835*'}
        }

        It 'downloads only the updates selected in Out-GridView with -SelectUpdates' {
            Mock Out-GridView {
                $script:Seen['GridTitle'] = $Title
                if ($InputObject.UpdateGroup -eq 'LCU') {$InputObject}
            }
            $Warnings = Invoke-UpdateOSMedia -Parameters @{Name = $Win11Name; SelectUpdates = $true}
            $script:Seen['GridTitle'] | Should -Be 'Select Updates to Apply and press OK'
            #the not downloaded .NET CU is not selected, so nothing is missing
            $Warnings | Should -Contain 'Use the -Execute parameter to complete this task'
            Should -Invoke Get-OSDUpdateDownloads -Times 0 -Exactly
        }

        It 'uses the DisplayVersion of CurrentVersion.xml as ReleaseId (22H2 and not 2009)' {
            New-TestOSMedia -Name 'Windows 10 Enterprise x64 22H2 19045.2965' -Image 'Win10Enterprise22H2' -Registry 'Win10-22H2-2965' | Out-Null
            $script:TestUpdates = @($script:FixtureUpdates | Select-Object -Property * | ForEach-Object {$_.OSDStatus = ''; $_})
            Invoke-UpdateOSMedia -Parameters @{Name = 'Windows 10 Enterprise x64 22H2 19045.2965'; Download = $true} | Out-Null
            Should -Invoke Get-OSDUpdateDownloads -Times 1 -Exactly -ParameterFilter {$FileName -like 'windows10.0-kb5066791-x64*'}
            Should -Invoke Get-OSDUpdateDownloads -Times 0 -Exactly -ParameterFilter {$FileName -like 'windows10.0-kb4598242*'}
            Should -Invoke Get-OSDUpdateDownloads -Times 0 -Exactly -ParameterFilter {$FileName -like '*-x86_*'}
        }
    }

    Context 'Execute' {
        BeforeEach {
            New-TestOSMedia -Name $Win11Name -Image 'Win11Enterprise24H2' -Registry 'Win11-24H2-1742' | Out-Null
            $script:PostImage = New-TestWindowsImage -Key 'Win11Enterprise24H2' -ImagePath 'build' -Property @{Version = '10.0.26100.6899'; SPBuild = 6899}
            $Parameters = @{Name = $Win11Name; Download = $true; Execute = $true}
        }

        It 'calls the worker functions in the servicing order' {
            Invoke-UpdateOSMedia -Parameters $Parameters | Out-Null
            Assert-StepOrder -Expected @(
                'Show-MediaImageInfoOS', 'Get-OSDUpdateDownloads', 'Show-WorkingInfoOS', 'Copy-MediaOperatingSystem',
                'Mount-WinPEwim', 'Mount-WinREwim', 'Mount-WinSEwim', 'Update-SetupDUMEDIA',
                'Add-ContentADKWinPE', 'Add-ContentADKWinRE', 'Add-ContentADKWinSE', 'Add-ContentPack PEADK', 'Add-ContentPack PEADKLang',
                'Add-LanguagePacksWinRE', 'Add-LanguagePacksWinSE', 'Expand-DaRTPE', 'Add-ContentPack PEDaRT',
                'Update-ServicingStackPE', 'Update-SafeOSPE', 'Update-CumulativePE',
                'Import-AutoExtraFilesPE', 'Enable-WinPEOSDCloud', 'Enable-WinREWiFi', 'Add-ContentExtraFilesPE', 'Add-ContentDriversPE', 'Add-ContentScriptsPE',
                'Add-ContentPack PEDrivers', 'Add-ContentPack PEExtraFiles', 'Add-ContentPack PEPoshMods', 'Add-ContentPack PERegistry', 'Add-ContentPack PEScripts',
                'Update-SourcesPE', 'Save-PackageInventoryPE', 'Dismount-WimsPE', 'Export-PEWims', 'Export-PEBootWim', 'Save-InventoryPE',
                'Mount-InstallwimOS', 'Set-WinREWimOS', 'Save-RegistryCurrentVersionOS',
                'Add-LanguagePacksOS', 'Add-ContentPack OSLanguagePacks', 'Add-LanguageInterfacePacksOS', 'Add-LanguageFeaturesOnDemandOS',
                'Add-ContentPack OSLanguageFeatures', 'Add-LocalExperiencePacksOS', 'Add-ContentPack OSLocalExperiencePacks', 'Copy-MediaLanguageSources', 'Add-ContentPack MEDIA',
                'Add-ContentPack OSCapability', 'Add-ContentPack OSPackages', 'Add-WindowsPackageOS', 'Add-FeaturesOnDemandOS', 'Add-WindowsCapabilityOS',
                'Update-ComponentOS', 'Update-ServicingStackOS', 'Update-CumulativeOS', 'Update-WindowsSevenOS', 'Update-WindowsServer2012R2OS',
                'Save-RegistryCurrentVersionOS', 'Update-AdobeOS', 'Update-DotNetOS', 'Update-OptionalOS', 'Invoke-DismCleanupImage',
                'Enable-WindowsOptionalFeatureOS', 'Enable-NetFXOS', 'Update-InboxAppsOS', 'Remove-AppxProvisionedPackageOS', 'Remove-WindowsPackageOS',
                'Remove-WindowsCapabilityOS', 'Disable-WindowsOptionalFeatureOS', 'Add-ContentDriversOS', 'Add-ContentExtraFilesOS', 'Add-ContentStartLayout',
                'Add-ContentUnattend', 'Add-ContentScriptsOS', 'Import-RegistryRegOS', 'Import-RegistryXmlOS',
                'Add-ContentPack OSDrivers', 'Add-ContentPack OSExtraFiles', 'Add-ContentPack OSPoshMods', 'Add-ContentPack OSRegistry', 'Add-ContentPack OSScripts', 'Add-ContentPack OSStartLayout',
                'Save-AutoExtraFilesOS', 'Save-SessionsXmlOS', 'Save-InventoryOS', 'Dismount-InstallwimOS', 'Export-InstallwimOS',
                'Save-WindowsImageContentOS', 'Save-VariablesOSD'
            )
            Should -Invoke Set-LanguageSettingsOS -Times 0 -Exactly
            Should -Invoke New-OSDBuilderISO -Times 0 -Exactly
            Should -Invoke Read-Host -Times 0 -Exactly
            Should -Invoke Update-CumulativeOS -Times 1 -Exactly -ParameterFilter {-not $Force}
        }

        It 'services a working copy in OSMedia\buildyyMMddhhmm' {
            Invoke-UpdateOSMedia -Parameters $Parameters | Out-Null
            Should -Invoke Mount-WinPEwim -Times 1 -Exactly -ParameterFilter {$OSMediaPath -match 'OSMedia.build\d{10}$'}
            Should -Invoke Save-InventoryOS -Times 1 -Exactly -ParameterFilter {$OSMediaPath -match 'OSMedia.build\d{10}$'}
            Should -Invoke Start-Transcript -Times 1 -Exactly -ParameterFilter {$Path -like '*Update-OSMedia.log'}
            Should -Invoke Stop-Transcript -Times 1 -Exactly
        }

        It 'passes the updates of each update group to the worker functions' {
            Mock Update-CumulativeOS {$script:Seen['LCU'] = @($OSDUpdateLCU.KBNumber)}
            Mock Update-SetupDUMEDIA {$script:Seen['SetupDU'] = @($OSDUpdateSetupDU.KBNumber); $script:Seen['ComponentDU'] = @($OSDUpdateComponentDU.KBNumber)}
            Mock Update-DotNetOS {$script:Seen['DotNet'] = @($OSDUpdateDotNet.KBNumber)}
            Mock Update-OptionalOS {$script:Seen['Optional'] = @($OSDUpdateOptional | Where-Object {$_})}
            Invoke-UpdateOSMedia -Parameters $Parameters | Out-Null
            $script:Seen['LCU'] | Should -Be @('5066835')
            $script:Seen['SetupDU'] | Should -Be @('5066699')
            $script:Seen['ComponentDU'] | Should -Be @('5066700')
            $script:Seen['DotNet'] | Should -Be @('5066131')
            #Update-OSMedia never applies Optional updates
            $script:Seen['Optional'] | Should -BeNullOrEmpty
        }

        It 'passes no updates to the worker functions with -SkipUpdates' {
            Mock Update-CumulativeOS {$script:Seen['LCU'] = @($OSDUpdateLCU | Where-Object {$_})}
            Invoke-UpdateOSMedia -Parameters @{Name = $Win11Name; Execute = $true; SkipUpdates = $true} | Out-Null
            Should -Invoke Update-CumulativeOS -Times 1 -Exactly
            $script:Seen['LCU'] | Should -BeNullOrEmpty
        }

        It 'renames the working copy to the new OSMedia name and writes the Windows Image information' {
            Invoke-UpdateOSMedia -Parameters $Parameters | Out-Null
            Get-RenamedOSMedia | Should -Be @($Win11NewName)
            $NewOSMedia = Join-Path $global:SetOSDBuilderPathOSMedia $Win11NewName
            Get-Content -Path (Join-Path $NewOSMedia 'WindowsImage.txt') | Where-Object {-not $_.Trim()} | Should -BeNullOrEmpty
            (Get-Content -Path (Join-Path $NewOSMedia 'WindowsImage.txt')) -join "`n" | Should -BeLike '*26100.6899*'
            (Get-Content -Path (Join-Path (Join-Path (Join-Path $NewOSMedia 'info') 'json') 'Get-WindowsImage.json') -Raw | ConvertFrom-Json).UBR | Should -Be '26100.6899'
            Import-Clixml -Path (Join-Path (Join-Path (Join-Path $NewOSMedia 'info') 'xml') 'Get-WindowsImage.xml') | Select-Object -ExpandProperty ImageName | Should -Be 'Windows 11 Enterprise'
            #the source OSMedia is not changed
            Test-Path (Join-Path $global:SetOSDBuilderPathOSImport $Win11Name) | Should -BeTrue
        }

        It 'keeps the languages in the name of a multi language OSMedia' {
            $script:PostImage = New-TestWindowsImage -Key 'Win11Enterprise24H2DeDE' -ImagePath 'build' -Property @{SPBuild = 6899}
            Invoke-UpdateOSMedia -Parameters $Parameters | Out-Null
            Get-RenamedOSMedia | Should -Be @("$Win11NewName en-US de-DE")
        }

        It 'removes the temporary and the mount directories' {
            Invoke-UpdateOSMedia -Parameters $Parameters | Out-Null
            @(Get-ChildItem -Path $global:SetOSDBuilderPathMount) | Should -BeNullOrEmpty
            Test-Path (Join-Path (Join-Path $global:SetOSDBuilderPathOSMedia $Win11NewName) 'WimTemp') | Should -BeFalse
        }

        It 'warns when the Update Build Revision did not change' {
            $script:RegistryPost = $script:RegistryPre
            $script:PostImage = New-TestWindowsImage -Key 'Win11Enterprise24H2' -ImagePath 'build'
            $Warnings = Invoke-UpdateOSMedia -Parameters $Parameters
            $Warnings | Should -Contain 'The Update Build Revision did not change after Windows Updates'
            Get-RenamedOSMedia | Should -Be @($Win11Name)
        }

        It 'uses the SPBuild of the Windows Image when the registry has no CurrentBuild and UBR' {
            $script:RegistryPre = [PSCustomObject]@{DisplayVersion = '24H2'}
            $script:RegistryPost = [PSCustomObject]@{DisplayVersion = '24H2'}
            $Warnings = Invoke-UpdateOSMedia -Parameters $Parameters
            $Warnings | Should -Contain 'The Update Build Revision did not change after Windows Updates'
            Get-RenamedOSMedia | Should -Be @('Windows 11 Enterprise x64 24H2 1742.1742')
        }

        It 'reapplies the LCU after language content and runs Set-LanguageSettingsOS' {
            Mock Add-LanguagePacksOS {$global:ReapplyLCU = $true; $global:UpdateLanguageContent = $true}
            Invoke-UpdateOSMedia -Parameters $Parameters | Out-Null
            Should -Invoke Update-CumulativeOS -Times 1 -Exactly -ParameterFilter {$Force}
            Should -Invoke Update-CumulativeOS -Times 0 -Exactly -ParameterFilter {-not $Force}
            Should -Invoke Set-LanguageSettingsOS -Times 1 -Exactly
        }

        It 'reapplies the LCU before the cleanup when a later update requires it' {
            Mock Update-AdobeOS {$global:ReapplyLCU = $true}
            Invoke-UpdateOSMedia -Parameters $Parameters | Out-Null
            Should -Invoke Update-CumulativeOS -Times 1 -Exactly -ParameterFilter {-not $Force}
            Should -Invoke Update-CumulativeOS -Times 1 -Exactly -ParameterFilter {$Force}
        }

        It 'hides the cleanup progress with -HideCleanupProgress' {
            Invoke-UpdateOSMedia -Parameters ($Parameters + @{HideCleanupProgress = $true}) | Out-Null
            Should -Invoke Invoke-DismCleanupImage -Times 1 -Exactly -ParameterFilter {$HideCleanupProgress}
        }

        It 'shows the cleanup progress without -HideCleanupProgress' {
            Invoke-UpdateOSMedia -Parameters $Parameters | Out-Null
            Should -Invoke Invoke-DismCleanupImage -Times 1 -Exactly -ParameterFilter {-not $HideCleanupProgress}
        }

        It 'makes -SkipComponentCleanup available to Invoke-DismCleanupImage' {
            Mock Invoke-DismCleanupImage {$script:Seen['SkipComponentCleanup'] = [bool]$SkipComponentCleanup}
            Invoke-UpdateOSMedia -Parameters ($Parameters + @{SkipComponentCleanup = $true}) | Out-Null
            $script:Seen['SkipComponentCleanup'] | Should -BeTrue
        }

        It 'creates an ISO of the working copy with -CreateISO' {
            Invoke-UpdateOSMedia -Parameters ($Parameters + @{CreateISO = $true}) | Out-Null
            Should -Invoke New-OSDBuilderISO -Times 1 -Exactly -ParameterFilter {$FullName -match 'build\d{10}$'}
            Assert-StepOrder -Expected 'Save-VariablesOSD', 'New-OSDBuilderISO'
        }

        It 'pauses before the dismount with -PauseDismountPE and -PauseDismountOS' {
            Mock Read-Host {$global:UpdateOSMediaSteps.Add('Read-Host')}
            Invoke-UpdateOSMedia -Parameters ($Parameters + @{PauseDismountPE = $true; PauseDismountOS = $true}) | Out-Null
            Should -Invoke Read-Host -Times 2 -Exactly
            Assert-StepOrder -Expected 'Save-PackageInventoryPE', 'Read-Host', 'Dismount-WimsPE', 'Save-InventoryOS', 'Read-Host', 'Dismount-InstallwimOS'
        }

        It 'replaces an existing working directory' {
            $Now = Get-Date
            foreach ($Time in $Now, $Now.AddMinutes(1)) {
                New-TestFile -Path (Join-Path (Join-Path $global:SetOSDBuilderPathOSMedia "build$($Time.ToString('yyMMddhhmm'))") 'old.txt') | Out-Null
            }
            $Warnings = Invoke-UpdateOSMedia -Parameters $Parameters
            ($Warnings -like '*build* will be replaced!') | Should -HaveCount 1
            Test-Path (Join-Path (Join-Path $global:SetOSDBuilderPathOSMedia $Win11NewName) 'old.txt') | Should -BeFalse
        }

        It 'appends yyMMddhhmm to the name when the new OSMedia already exists' {
            New-Item -Path (Join-Path $global:SetOSDBuilderPathOSMedia $Win11NewName) -ItemType Directory | Out-Null
            $Warnings = Invoke-UpdateOSMedia -Parameters $Parameters
            $Warnings | Should -Contain 'Trying to rename the Build directory, but it already exists'
            Get-RenamedOSMedia | Where-Object {$_ -match "^$([regex]::Escape($Win11NewName)) \d{10}$"} | Should -HaveCount 1
        }

        It 'retries the rename after 30 seconds and warns when it fails again' {
            Mock Rename-Item {throw 'The process cannot access the file because it is being used by another process'}
            $Warnings = Invoke-UpdateOSMedia -Parameters $Parameters
            $Warnings | Should -Contain 'Could not rename the the Build directory ... Waiting 30 seconds ...'
            $Warnings | Should -Contain 'Could not rename the the Build directory ...'
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {$Seconds -eq 30}
            Should -Invoke Rename-Item -Times 2 -Exactly -ParameterFilter {$NewName -eq $Win11NewName}
        }

        It 'renames on the second try when the first rename fails' {
            $script:RenameCalls = 0
            Mock Rename-Item {
                $script:RenameCalls++
                if ($script:RenameCalls -eq 1) {throw 'locked'}
                Microsoft.PowerShell.Management\Rename-Item -Path $Path -NewName $NewName
            }
            $Warnings = Invoke-UpdateOSMedia -Parameters $Parameters
            $Warnings | Should -Not -Contain 'Could not rename the the Build directory ...'
            Get-RenamedOSMedia | Should -Be @($Win11NewName)
        }

        Context 'OneDriveSetup.exe' {
            BeforeEach {
                $script:OneDriveFolder = 'SysWOW64'
                Mock Mount-InstallwimOS {
                    New-TestFile -Path (Join-Path (Join-Path (Join-Path $MountDirectory 'Windows') $script:OneDriveFolder) 'OneDriveSetup.exe') | Out-Null
                }
                New-TestFile -Path (Join-Path $global:GetOSDBuilderPathContentOneDrive 'OneDriveSetup.exe') | Out-Null
            }

            It 'copies the downloaded OneDriveSetup.exe to SysWOW64 of x64 Windows' {
                (Get-Item (Join-Path $global:GetOSDBuilderPathContentOneDrive 'OneDriveSetup.exe')).LastWriteTime = (Get-Date).AddDays(-7)
                Invoke-UpdateOSMedia -Parameters $Parameters | Out-Null
                Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {((@($InputObject) + @($RemainingArguments)) -join ' ') -like '*OneDrive *SysWOW64 OneDriveSetup.exe /ndl*'}
            }

            It 'copies the downloaded OneDriveSetup.exe to System32 of x86 Windows' {
                $script:OneDriveFolder = 'System32'
                $script:SourceImages[$Win11Name].Architecture = 0
                Invoke-UpdateOSMedia -Parameters $Parameters | Out-Null
                Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {((@($InputObject) + @($RemainingArguments)) -join ' ') -like '*OneDrive *System32 OneDriveSetup.exe /ndl*'}
            }

            It 'keeps OneDriveSetup.exe of the image when it was not downloaded' {
                Remove-Item -Path (Join-Path $global:GetOSDBuilderPathContentOneDrive 'OneDriveSetup.exe')
                Invoke-UpdateOSMedia -Parameters $Parameters | Out-Null
                Should -Invoke robocopy -Times 0 -Exactly
            }

            It 'does not update OneDriveSetup.exe on Windows Server' {
                $ServerName = 'Windows Server 2022 Datacenter Desktop Experience x64 21H2 20348.587'
                New-TestOSMedia -Name $ServerName -Image 'Server2022Datacenter' -Registry 'Server2022-587' | Out-Null
                $script:RegistryPre = New-TestRegistry -Key 'Server2022-587'
                $script:RegistryPost = New-TestRegistry -Key 'Server2022-4294'
                $script:PostImage = New-TestWindowsImage -Key 'Server2022Datacenter' -ImagePath 'build' -Property @{SPBuild = 4294}
                Invoke-UpdateOSMedia -Parameters @{Name = $ServerName; Download = $true; Execute = $true} | Out-Null
                Should -Invoke robocopy -Times 0 -Exactly
                Get-RenamedOSMedia | Should -Be @('Windows Server 2022 Datacenter Desktop Experience x64 21H2 20348.4294')
            }
        }
    }

    Context 'Windows 10 and Windows Server' {
        It 'applies SSU, LCU, ComponentDU, AdobeSU and .NET to Windows 10 22H2' {
            $Name = 'Windows 10 Enterprise x64 22H2 19045.2965'
            New-TestOSMedia -Name $Name -Image 'Win10Enterprise22H2' -Registry 'Win10-22H2-2965' | Out-Null
            $script:RegistryPre = New-TestRegistry -Key 'Win10-22H2-2965'
            $script:RegistryPost = New-TestRegistry -Key 'Win10-22H2-6456'
            $script:PostImage = New-TestWindowsImage -Key 'Win10Enterprise22H2' -ImagePath 'build' -Property @{SPBuild = 6456}
            Mock Update-ServicingStackOS {$script:Seen['SSU'] = @($OSDUpdateSSU.KBNumber)}
            Mock Update-ComponentOS {$script:Seen['ComponentDU'] = @($OSDUpdateComponentDU.KBNumber)}
            Mock Update-AdobeOS {$script:Seen['AdobeSU'] = @($OSDUpdateAdobeSU.KBNumber)}
            Mock Update-DotNetOS {$script:Seen['DotNet'] = @($OSDUpdateDotNet.KBNumber)}
            Mock Update-CumulativeOS {$script:Seen['LCU'] = @($OSDUpdateLCU.KBNumber)}
            Invoke-UpdateOSMedia -Parameters @{Name = $Name; Execute = $true} | Out-Null
            $script:Seen['SSU'] | Should -Be @('5031539')
            $script:Seen['ComponentDU'] | Should -Be @('5066792')
            $script:Seen['AdobeSU'] | Should -Be @('4580325')
            $script:Seen['DotNet'] | Should -Be @('5011048')
            $script:Seen['LCU'] | Should -Be @('5066791')
            Get-RenamedOSMedia | Should -Be @('Windows 10 Enterprise x64 22H2 19045.6456')
        }

        It 'does not apply AdobeSU to Windows Server Core' {
            $Name = 'Windows Server 2022 Datacenter x64 21H2 20348.587'
            New-TestOSMedia -Name $Name -Image 'Server2022DatacenterCore' -Registry 'Server2022-587' | Out-Null
            $script:RegistryPre = New-TestRegistry -Key 'Server2022-587'
            $script:RegistryPost = New-TestRegistry -Key 'Server2022-4294'
            $script:PostImage = New-TestWindowsImage -Key 'Server2022DatacenterCore' -ImagePath 'build' -Property @{SPBuild = 4294}
            Mock Update-AdobeOS {$script:Seen['AdobeSU'] = @($OSDUpdateAdobeSU | Where-Object {$_})}
            Mock Update-CumulativeOS {$script:Seen['LCU'] = @($OSDUpdateLCU.KBNumber)}
            Invoke-UpdateOSMedia -Parameters @{Name = $Name; Execute = $true} | Out-Null
            $script:Seen['AdobeSU'] | Should -BeNullOrEmpty
            $script:Seen['LCU'] | Should -Be @('5066782')
            Get-RenamedOSMedia | Should -Be @('Windows Server 2022 Datacenter x64 21H2 20348.4294')
        }

        It 'applies AdobeSU to Windows Server with Desktop Experience' {
            $Name = 'Windows Server 2022 Datacenter Desktop Experience x64 21H2 20348.587'
            New-TestOSMedia -Name $Name -Image 'Server2022Datacenter' -Registry 'Server2022-587' | Out-Null
            $script:RegistryPre = New-TestRegistry -Key 'Server2022-587'
            $script:RegistryPost = New-TestRegistry -Key 'Server2022-4294'
            $script:PostImage = New-TestWindowsImage -Key 'Server2022Datacenter' -ImagePath 'build' -Property @{SPBuild = 4294}
            Mock Update-AdobeOS {$script:Seen['AdobeSU'] = @($OSDUpdateAdobeSU.KBNumber)}
            Mock Update-WindowsServer2012R2OS {$script:Seen['TwelveR2'] = @($OSDUpdateWinTwelveR2 | Where-Object {$_})}
            Invoke-UpdateOSMedia -Parameters @{Name = $Name; Execute = $true} | Out-Null
            $script:Seen['AdobeSU'] | Should -Be @('4580325')
            $script:Seen['TwelveR2'] | Should -BeNullOrEmpty
        }

        It 'maps build <Build> without CurrentVersion.xml to ReleaseId <ExpectedReleaseId>' -ForEach @(
            @{Build = 10240; ExpectedReleaseId = '1507'}
            @{Build = 14393; ExpectedReleaseId = '1607'}
            @{Build = 15063; ExpectedReleaseId = '1703'}
            @{Build = 16299; ExpectedReleaseId = '1709'}
            @{Build = 17134; ExpectedReleaseId = '1803'}
            @{Build = 17763; ExpectedReleaseId = '1809'}
        ) {
            $Name = "Windows 10 Enterprise x64 $ExpectedReleaseId $Build.1"
            New-TestOSMedia -Name $Name -Image 'Win10Enterprise1809' -ImageProperty @{Build = $Build; Version = "10.0.$Build.1"} | Out-Null
            $script:TestUpdates = @(
                New-TestUpdate -UpdateBuild $ExpectedReleaseId -KBNumber '1000001'
                New-TestUpdate -UpdateBuild '1909' -KBNumber '1000002'
            )
            #Get-RegCurrentVersion of an old image without CurrentBuild, UBR and DisplayVersion
            $script:RegistryPre = [PSCustomObject]@{ReleaseId = $ExpectedReleaseId}
            $script:RegistryPost = [PSCustomObject]@{ReleaseId = $ExpectedReleaseId; CurrentBuild = "$Build"; UBR = 5000}
            $script:PostImage = New-TestWindowsImage -Key 'Win10Enterprise1809' -ImagePath 'build' -Property @{Build = $Build; SPBuild = 5000}
            Invoke-UpdateOSMedia -Parameters @{Name = $Name; Download = $true; Execute = $true} | Out-Null
            Should -Invoke Get-OSDUpdateDownloads -Times 1 -Exactly
            Should -Invoke Get-OSDUpdateDownloads -Times 1 -Exactly -ParameterFilter {$FileName -like '*kb1000001*'}
            Get-RenamedOSMedia | Should -Be @("Windows 10 Enterprise x64 $ExpectedReleaseId $Build.5000")
        }
    }

    Context 'shared New-OSBuild code path' {
        BeforeAll {
            #The Process block of Update-OSMedia.ps1 contains the New-OSBuild branches, run the same body as New-OSBuild
            Set-Item -Path function:script:New-OSBuild -Value (Get-Command -Name Update-OSMedia -CommandType Function).ScriptBlock
        }
        AfterAll {
            Remove-Item -Path function:script:New-OSBuild -ErrorAction SilentlyContinue
        }

        BeforeEach {
            #New-OSBuild parameters that Update-OSMedia does not have, read from the calling scope
            $ByTaskName = $null; $SkipTemplates = $null; $EnableNetFX = $null; $SelectContentPacks = $null; $SkipContentPacks = $null
            $DontUseNewestMedia = $null; $IncludeKB = $null; $ExcludeKB = $null; $OSDVHD = $null; $OSDInfo = $null

            $SourceOSMedia = New-TestOSMedia -Parent $global:SetOSDBuilderPathOSMedia -Name $Win11Name -Image 'Win11Enterprise24H2' -Registry 'Win11-24H2-1742'
            $script:PostImage = New-TestWindowsImage -Key 'Win11Enterprise24H2' -ImagePath 'build' -Property @{SPBuild = 6899}

            $global:SetOSDBuilderPathTasks = Join-Path $Root 'Tasks'
            $TaskFile = Join-Path $global:SetOSDBuilderPathTasks 'OSBuild Win11 Enterprise x64 24H2.json'
            New-Item -Path $global:SetOSDBuilderPathTasks -ItemType Directory -Force | Out-Null
            Copy-Item -Path $script:FixtureTask -Destination $TaskFile
            $script:TaskItem = [PSCustomObject]@{TaskName = 'Win11 Enterprise x64 24H2'; FullName = $TaskFile}
            Mock Get-OSBuildTask {$script:TaskItem}

            $script:LatestOSMedia = [PSCustomObject]@{
                Name = $Win11Name; FullName = $SourceOSMedia.FullName; Revision = 'OK'; Updates = 'OK'
                OSMFamily = '26100 Enterprise x64 Client en-US'; OSMGuid = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0'
            }
            Mock Get-OSMedia {$script:LatestOSMedia}
            Mock Get-TaskContentPacks {[PSCustomObject]@{Name = 'Selected'}}
            $BuildParameters = @{Download = $true; Execute = $true}
        }

        It 'builds the OSBuild of the task selected in Out-GridView with its CustomName' {
            Mock Out-GridView {$script:Seen['GridTitle'] = $Title; $InputObject}
            Invoke-UpdateOSMedia -Command 'New-OSBuild' -Parameters $BuildParameters | Out-Null
            $script:Seen['GridTitle'] | Should -BeLike 'OSBuild Tasks: Select one or more Tasks*'
            Should -Invoke Show-TaskInfo -Times 2 -Exactly
            Get-RenamedOSMedia -Path $global:SetOSDBuilderPathOSBuilds | Should -Be @('Win11 Ent 24H2 Corp 26100.6899')
            Should -Invoke Start-Transcript -Times 1 -Exactly -ParameterFilter {$Path -like '*OSBuilds*New-OSBuild.log'}
        }

        It 'warns when no task is selected' {
            Mock Out-GridView {}
            $Warnings = Invoke-UpdateOSMedia -Command 'New-OSBuild' -Parameters $BuildParameters
            $Warnings | Should -Contain 'OSBuild Task was not selected or found . . . Exiting!'
            Should -Invoke Show-TaskInfo -Times 0 -Exactly
        }

        It 'uses the task of $ByTaskName without Out-GridView' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'
            Invoke-UpdateOSMedia -Command 'New-OSBuild' -Parameters $BuildParameters | Out-Null
            Should -Invoke Out-GridView -Times 0 -Exactly
            Get-RenamedOSMedia -Path $global:SetOSDBuilderPathOSBuilds | Should -Be @('Win11 Ent 24H2 Corp 26100.6899')
        }

        It 'renames WinPEAddDaRT to WinPEDaRT in the task file' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'
            Invoke-UpdateOSMedia -Command 'New-OSBuild' | Out-Null
            $TaskText = Get-Content -Path $script:TaskItem.FullName -Raw
            $TaskText | Should -Not -BeLike '*WinPEAddDaRT*'
            $TaskText | Should -BeLike '*"WinPEDaRT"*'
        }

        It 'adds the _Global and the task ContentPacks when ContentPacks are enabled' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'
            Mock Get-IsContentPacksEnabled {$true}
            Mock Show-TaskInfo {$script:Seen['ContentPacks'] = @($ContentPacks)}
            Invoke-UpdateOSMedia -Command 'New-OSBuild' | Out-Null
            $script:Seen['ContentPacks'] | Should -Be @('_Global', 'Corp')
        }

        It 'uses only the _Global ContentPack when the task has no ContentPacks' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'
            $Task = Get-Content -Path $script:TaskItem.FullName -Raw | ConvertFrom-Json
            $Task.ContentPacks = $null
            $Task | ConvertTo-Json | Set-Content -Path $script:TaskItem.FullName
            Mock Get-IsContentPacksEnabled {$true}
            Mock Show-TaskInfo {$script:Seen['ContentPacks'] = @($ContentPacks)}
            Invoke-UpdateOSMedia -Command 'New-OSBuild' | Out-Null
            $script:Seen['ContentPacks'] | Should -Be @('_Global')
        }

        It 'selects the ContentPacks with $SelectContentPacks' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'; $SelectContentPacks = [switch]$true
            Mock Get-IsContentPacksEnabled {$true}
            Mock Show-TaskInfo {$script:Seen['ContentPacks'] = @($ContentPacks)}
            Invoke-UpdateOSMedia -Command 'New-OSBuild' | Out-Null
            Should -Invoke Get-TaskContentPacks -Times 1 -Exactly -ParameterFilter {$Select}
            $script:Seen['ContentPacks'] | Should -Be @('Selected')
        }

        It 'stops with a task older than 19.1.4.0' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'
            (Get-Content -Path $script:TaskItem.FullName -Raw).Replace('23.10.24.1', '19.1.3.0') | Set-Content -Path $script:TaskItem.FullName
            $Warnings = Invoke-UpdateOSMedia -Command 'New-OSBuild' -Parameters $BuildParameters
            $Warnings | Should -Contain 'OSDBuilder Tasks need to be version 19.1.4.0 or newer'
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'stops when there is no OSMedia of the task OSMFamily' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'
            Mock Get-OSMedia {} -ParameterFilter {$Revision -eq 'OK'}
            $Warnings = Invoke-UpdateOSMedia -Command 'New-OSBuild' -Parameters $BuildParameters
            $Warnings | Should -Contain 'Unable to find a matching OSMFamily 26100 Enterprise x64 Client en-US'
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'finds the OSMedia of a Taskless task by name' {
            $ByTaskName = 'Taskless'
            $script:TaskItem.TaskName = 'Taskless'
            (Get-Content -Path $script:TaskItem.FullName -Raw).Replace('"Win11 Enterprise x64 24H2"', '"Taskless"').Replace('23.10.24.1', '1.0') | Set-Content -Path $script:TaskItem.FullName
            Invoke-UpdateOSMedia -Command 'New-OSBuild' | Out-Null
            Should -Invoke Show-TaskInfo -Times 1 -Exactly
            Should -Invoke Show-MediaImageInfoOS -Times 1 -Exactly
        }

        It 'warns when the newest OSMedia does not have the latest updates' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'
            $script:LatestOSMedia.Updates = 'Update'
            $Warnings = Invoke-UpdateOSMedia -Command 'New-OSBuild'
            $Warnings | Should -Contain "Update-OSMedia -Name '$Win11Name' -Download -Execute"
        }

        It 'merges the Global and the OSMFamily templates and skips other templates' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'
            New-Item -Path $global:SetOSDBuilderPathTemplates -ItemType Directory -Force | Out-Null
            $TemplateBase = Get-Content -Path $script:FixtureTask -Raw | ConvertFrom-Json
            $GlobalTemplate = $TemplateBase | Select-Object -Property *
            $GlobalTemplate.TaskName = 'Global Corp'; $GlobalTemplate.Drivers = @('Global\Drivers'); $GlobalTemplate.EnableNetFX3 = $true; $GlobalTemplate.ContentPacks = @('GlobalPack')
            $GlobalTemplate | Add-Member -NotePropertyName SetAllIntl -NotePropertyValue 'de-DE'
            foreach ($Property in 'StartLayoutXML', 'UnattendXML', 'LangSetInputLocale', 'LangSetSKUIntlDefaults', 'LangSetSetupUILang', 'LangSetSysLocale', 'LangSetUILang', 'LangSetUILangFallback', 'LangSetUserLocale') {
                $GlobalTemplate.$Property = "$Property-Global"
            }
            $GlobalTemplate.WinPEAutoExtraFiles = $true; $GlobalTemplate.WinPEOSDCloud = $true; $GlobalTemplate.WinREWiFi = $true; $GlobalTemplate.WinPEAddDaRT = 'DaRT10'
            $GlobalTemplate | ConvertTo-Json | Set-Content -Path (Join-Path $global:SetOSDBuilderPathTemplates 'OSBuild Global Corp.json')
            $Family = $TemplateBase | Select-Object -Property *
            $Family.TaskName = 'Win11 Family'; $Family.Drivers = @('Family\Drivers')
            $Family | ConvertTo-Json | Set-Content -Path (Join-Path $global:SetOSDBuilderPathTemplates 'OSBuild Win11 Family.json')
            $Other = $TemplateBase | Select-Object -Property *
            $Other.TaskName = 'Win10 Other'; $Other.OSMFamily = '19041 Enterprise x64 Client en-US'; $Other.Drivers = @('Other\Drivers')
            $Other | ConvertTo-Json | Set-Content -Path (Join-Path $global:SetOSDBuilderPathTemplates 'OSBuild Win10 Other.json')

            Mock Add-ContentDriversOS {$script:Seen['Drivers'] = @($Drivers); $script:Seen['EnableNetFX3'] = $EnableNetFX3; $script:Seen['WinPEDaRT'] = $WinPEDaRT; $script:Seen['SetUILang'] = $SetUILang}
            Invoke-UpdateOSMedia -Command 'New-OSBuild' -Parameters $BuildParameters | Out-Null
            $script:Seen['Drivers'] | Should -Be @('Corp\Drivers', 'Global\Drivers', 'Family\Drivers')
            $script:Seen['EnableNetFX3'] | Should -BeTrue
            $script:Seen['WinPEDaRT'] | Should -Be 'DaRT10'
            $script:Seen['SetUILang'] | Should -Be 'LangSetUILang-Global'
        }

        It 'ignores the templates with $SkipTemplates' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'; $SkipTemplates = [switch]$true
            New-Item -Path $global:SetOSDBuilderPathTemplates -ItemType Directory -Force | Out-Null
            Copy-Item -Path $script:FixtureTask -Destination (Join-Path $global:SetOSDBuilderPathTemplates 'OSBuild Global.json')
            Mock Get-IsTemplatesEnabled {$true}
            Mock Add-ContentDriversOS {$script:Seen['Drivers'] = @($Drivers)}
            Invoke-UpdateOSMedia -Command 'New-OSBuild' -Parameters $BuildParameters | Out-Null
            $script:Seen['Drivers'] | Should -Be @('Corp\Drivers')
            Should -Invoke Get-OSTemplateDrivers -Times 0 -Exactly
        }

        It 'lists the template content when templates are enabled' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'
            New-Item -Path $global:SetOSDBuilderPathTemplates -ItemType Directory -Force | Out-Null
            Mock Get-IsTemplatesEnabled {$true}
            foreach ($Template in 'Get-OSTemplateDrivers', 'Get-OSTemplateExtraFiles', 'Get-OSTemplateRegistryReg', 'Get-OSTemplateRegistryXml', 'Get-OSTemplateScripts') {
                Mock -CommandName $Template -MockWith {[PSCustomObject]@{FullName = 'Templates\Global\Item'}}
            }
            Invoke-UpdateOSMedia -Command 'New-OSBuild' | Out-Null
            foreach ($Template in 'Get-OSTemplateDrivers', 'Get-OSTemplateExtraFiles', 'Get-OSTemplateRegistryReg', 'Get-OSTemplateRegistryXml', 'Get-OSTemplateScripts') {
                Should -Invoke -CommandName $Template -Times 1 -Exactly
            }
        }

        It 'enables NetFX 3.5 with $EnableNetFX' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'; $EnableNetFX = [switch]$true
            Mock Enable-NetFXOS {$script:Seen['EnableNetFX3'] = $EnableNetFX3}
            Invoke-UpdateOSMedia -Command 'New-OSBuild' -Parameters $BuildParameters | Out-Null
            $script:Seen['EnableNetFX3'] | Should -BeTrue
        }

        It 'applies the Optional updates and filters $IncludeKB and $ExcludeKB' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'
            $IncludeKB = '5066835', '5067036', '890830', '5066699'; $ExcludeKB = '5066699'
            Mock Update-OptionalOS {$script:Seen['Optional'] = @($OSDUpdateOptional.KBNumber); $script:Seen['SetupDU'] = @($OSDUpdateSetupDU | Where-Object {$_})}
            Invoke-UpdateOSMedia -Command 'New-OSBuild' -Parameters $BuildParameters | Out-Null
            $script:Seen['Optional'] | Should -Be @('890830', '5067036')
            $script:Seen['SetupDU'] | Should -BeNullOrEmpty
            Should -Invoke Get-OSDUpdateDownloads -Times 0 -Exactly
        }

        It 'creates a VHD and shows the info with $OSDVHD and $OSDInfo' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'; $OSDVHD = [switch]$true; $OSDInfo = [switch]$true
            Invoke-UpdateOSMedia -Command 'New-OSBuild' -Parameters $BuildParameters | Out-Null
            Should -Invoke New-OSDBuilderVHD -Times 1 -Exactly -ParameterFilter {$FullName -match 'OSBuilds.build\d{10}$'}
            Should -Invoke Show-OSDBuilderInfo -Times 1 -Exactly -ParameterFilter {$FullName -match 'OSBuilds.build\d{10}$'}
        }

        It 'appends yyMMddhhmm when the OSBuild already exists' {
            $ByTaskName = 'Win11 Enterprise x64 24H2'
            New-Item -Path (Join-Path $global:SetOSDBuilderPathOSBuilds 'Win11 Ent 24H2 Corp 26100.6899') -ItemType Directory | Out-Null
            $Warnings = Invoke-UpdateOSMedia -Command 'New-OSBuild' -Parameters $BuildParameters
            $Warnings | Should -Contain 'Trying to rename the Build directory, but it already exists'
            Get-RenamedOSMedia -Path $global:SetOSDBuilderPathOSBuilds | Where-Object {$_ -match '^Win11 Ent 24H2 Corp 26100\.6899 \d{10}$'} | Should -HaveCount 1
        }
    }
}
