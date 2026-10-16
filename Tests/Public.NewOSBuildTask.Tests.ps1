BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    foreach ($Name in 'Get-OSDBuilder', 'Get-OSMedia', 'New-OSBuildTask') {. (Join-Path (Join-Path $RepoRoot 'Public') "$Name.ps1")}

    $PEBuildTaskFixtures = Join-Path $FixturesPath 'PEBuildTask'

    $global:SetOSDBuilder = @{}
    $global:GetOSDBuilder = @{VersionOSDBuilder = [version]'26.10.16.1'}
    $global:SetOSDBuilderPathTasks = Join-Path $TestDrive 'Tasks'
    $global:SetOSDBuilderPathTemplates = Join-Path $TestDrive 'Templates'
    $global:SetOSDBuilderPathOSMedia = Join-Path $TestDrive 'OSMedia'
    $global:SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
    $global:GetOSDBuilderPathContentIsoExtract = Join-Path $global:SetOSDBuilderPathContent 'IsoExtract'

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
            [string]$InstallationType = 'Client',
            [string]$MediaType = 'OSMedia',
            #Writes info\xml\CurrentVersion.xml with these properties
            [hashtable]$CurrentVersion,
            [switch]$NoCapabilityInventory
        )
        $FullName = Join-Path $global:SetOSDBuilderPathOSMedia $Name
        $Xml = Join-Path (Join-Path $FullName 'info') 'xml'
        New-Item -Path $Xml -ItemType Directory -Force | Out-Null
        New-TestFile -Path (Join-Path (Join-Path (Join-Path $FullName 'OS') 'sources') 'install.wim') | Out-Null
        [PSCustomObject]@{ImageName = 'Windows 11 Enterprise'; Version = "10.0.$Build.6899"; Architecture = 9} | Export-Clixml -Path (Join-Path $Xml 'Get-WindowsImage.xml')
        if (-not $NoCapabilityInventory) {
            @([PSCustomObject]@{Name = 'Language.Basic~~~de-DE~0.0.1.0'; State = 'NotPresent'}) | Export-Clixml -Path (Join-Path $Xml 'Get-WindowsCapability.xml')
        }
        if ($CurrentVersion) {[PSCustomObject]$CurrentVersion | Export-Clixml -Path (Join-Path $Xml 'CurrentVersion.xml')}
        [PSCustomObject]@{
            MediaType           = $MediaType
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
            InstallationType    = $InstallationType
            MajorVersion        = $MajorVersion
            Build               = $Build
            CreatedTime         = [datetime]'2026-10-01T10:00:00'
            ModifiedTime        = [datetime]'2026-10-02T10:00:00'
        }
    }

    function Get-TestTask ([string]$Name = 'Contoso', [string]$Folder = $global:SetOSDBuilderPathTasks) {
        Get-Content -Path (Join-Path $Folder "OSBuild $Name.json") -Raw | ConvertFrom-Json
    }

    function Copy-ExistingTask ([string]$Name = 'Contoso', [scriptblock]$Change) {
        $Task = Get-Content -Path (Join-Path $PEBuildTaskFixtures 'OSBuild Existing.json') -Raw | ConvertFrom-Json
        if ($Change) {. $Change}
        $Task | ConvertTo-Json | Set-Content -Path (Join-Path $global:SetOSDBuilderPathTasks "OSBuild $Name.json")
    }

    function Item ([string]$Property, [string[]]$Value) {
        foreach ($Item in $Value) {[PSCustomObject]@{$Property = $Item}}
    }
}

AfterAll {
    Remove-Variable -Name SetOSDBuilder, GetOSDBuilder, SetOSDBuilderPathTasks, SetOSDBuilderPathTemplates, SetOSDBuilderPathOSMedia, SetOSDBuilderPathContent, GetOSDBuilderPathContentIsoExtract -Scope Global -ErrorAction SilentlyContinue
}

Describe 'New-OSBuildTask' {
    BeforeEach {
        foreach ($Path in $global:SetOSDBuilderPathTasks, $global:SetOSDBuilderPathTemplates, $global:SetOSDBuilderPathOSMedia) {
            if (Test-Path $Path) {Remove-Item -Path $Path -Recurse -Force}
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
        $script:GridInput = @()
        Mock Get-OSDBuilder {}
        Mock Block-StandardUser {}
        Mock Get-OSMedia {}
        Mock Out-GridView {$script:GridInput += $InputObject; if ($script:GridInput.Count -eq 1) {$InputObject}}
        Mock Get-WindowsImage {[PSCustomObject]@{Version = '10.0.26200.6899'; MinorVersion = 0; SPBuild = 6899; SPLevel = 0; ImageBootable = $false; WIMBoot = $false}}
        Mock Get-IsContentPacksEnabled {$true}
        Mock Get-TaskContentIsoExtract {}
        Mock Get-OSDBuilderCapabilitySource {'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LanguagesAndOptionalFeatures'}
        foreach ($Command in 'Get-TaskContentPacks', 'Get-TaskRemoveAppxProvisionedPackage', 'Get-TaskRemoveWindowsCapability', 'Get-TaskRemoveWindowsPackage',
            'Get-TaskDisableWindowsOptionalFeature', 'Get-TaskEnableWindowsOptionalFeature', 'Get-TaskContentDrivers', 'Get-TaskContentExtraFiles',
            'Get-TaskContentScripts', 'Get-TaskContentStartLayoutXML', 'Get-TaskContentUnattendXML', 'Get-TaskContentAddWindowsPackage',
            'Get-TaskContentAddFeatureOnDemand', 'Get-TaskContentAddWindowsCapability', 'Get-TaskContentLanguagePack', 'Get-TaskContentLanguageFeature',
            'Get-TaskContentLanguageInterfacePack', 'Get-TaskContentLocalExperiencePacks', 'Get-TaskContentLanguageCopySources', 'Get-TaskWinPEDaRT',
            'Get-TaskWinPEADKPE', 'Get-TaskWinPEADKRE', 'Get-TaskWinPEADKSE', 'Get-TaskWinPEDrivers', 'Get-TaskWinPEExtraFilesPE', 'Get-TaskWinPEExtraFilesRE',
            'Get-TaskWinPEExtraFilesSE', 'Get-TaskWinPEScriptsPE', 'Get-TaskWinPEScriptsRE', 'Get-TaskWinPEScriptsSE') {
            Mock $Command {}
        }
        $OSMedia = New-TestOSMedia
    }

    Context 'Parameters' {
        It 'requires a TaskName' {
            $Parameter = (Get-Command New-OSBuildTask).Parameters['TaskName']
            ($Parameter.Attributes | Where-Object {$_ -is [System.Management.Automation.ParameterAttribute]}).Mandatory | Should -BeTrue
        }

        It 'puts the content selections and the language settings in the All parameter set' {
            $Command = Get-Command New-OSBuildTask
            foreach ($Name in 'ContentDrivers', 'ContentLanguagePackages', 'ContentFeaturesOnDemand', 'ContentWinPEADK', 'SetAllIntl', 'SetUILang', 'SourcesLanguageCopy') {
                $Command.Parameters[$Name].ParameterSets.Keys | Should -Be @('All')
            }
            $Command.DefaultParameterSet | Should -Be 'Basic'
        }

        It 'rejects an unknown language in <Name>' -ForEach @(@{Name = 'SetAllIntl'}, @{Name = 'SetUILang'}, @{Name = 'SetUILangFallback'}, @{Name = 'SetSKUIntlDefaults'}, @{Name = 'SetSetupUILang'}) {
            $Splat = @{TaskName = 'Contoso'; OSMedia = $OSMedia; $Name = 'xx-XX'}
            {New-OSBuildTask @Splat 6>$null} | Should -Throw '*xx-XX*'
        }

        It 'rejects an invalid -SaveAs' {
            {New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -SaveAs 'Global' 6>$null} | Should -Throw
        }

        It 'reads the switch defaults from $global:SetOSDBuilder' {
            $global:SetOSDBuilder = @{NewOSBuildTaskEnableNetFX3 = $true; NewOSBuildTaskCustomName = 'Default Name'}
            try {New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia 6>$null 3>$null | Out-Null}
            finally {$global:SetOSDBuilder = @{}}
            $Task = Get-TestTask
            $Task.EnableNetFX3 | Should -Be 'True'
            $Task.CustomName | Should -Be 'Default Name'
        }
    }

    Context 'New Task' {
        It 'writes the OSMedia and the switches to the Task JSON' {
            $Result = New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -CustomName 'Contoso 25H2' -EnableNetFX3 -WinPEAutoExtraFiles -WinPEOSDCloud -WinREWiFi -PSModulesOS 'OSD', 'PSWindowsUpdate' -PSModulesWinPE 'OSD' 6>$null

            $Task = Get-TestTask
            $Task.TaskType | Should -Be 'OSBuild'
            $Task.TaskVersion | Should -Be '26.10.16.1'
            {[guid]$Task.TaskGuid} | Should -Not -Throw
            $Task.TaskName | Should -Be 'Contoso'
            $Task.CustomName | Should -Be 'Contoso 25H2'
            $Task.OSMFamily | Should -Be 'Enterprise x64 26200 en-US'
            $Task.OSMGuid | Should -Be $OSMedia.OSMGuid
            $Task.Name | Should -Be 'Windows 11 Enterprise x64 25H2 26200.6899'
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
            $Task.EnableNetFX3 | Should -Be 'True'
            $Task.WinPEAutoExtraFiles | Should -Be 'True'
            $Task.WinPEOSDCloud | Should -Be 'True'
            $Task.WinREWiFi | Should -Be 'True'
            $Task.PSModulesOS | Should -Be @('OSD', 'PSWindowsUpdate')
            $Task.PSModulesWinPE | Should -Be @('OSD')

            $Result.TaskName | Should -Be 'Contoso'
            $Result.TaskGuid | Should -Be $Task.TaskGuid
        }

        It 'writes empty selections and language settings without switches' {
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia 6>$null 3>$null | Out-Null

            $Task = Get-TestTask
            $Task.EnableNetFX3 | Should -Be 'False'
            $Task.WinPEAutoExtraFiles | Should -Be 'False'
            $Task.WinPEOSDCloud | Should -Be 'False'
            $Task.WinREWiFi | Should -Be 'False'
            $Task.CustomName | Should -BeNullOrEmpty
            foreach ($Property in 'ContentPacks', 'RemoveAppxProvisionedPackage', 'RemoveWindowsCapability', 'RemoveWindowsPackage', 'DisableWindowsOptionalFeature',
                'EnableWindowsOptionalFeature', 'Drivers', 'ExtraFiles', 'PSModulesOS', 'PSModulesWinPE', 'Scripts', 'StartLayoutXML', 'UnattendXML',
                'AddWindowsPackage', 'AddFeatureOnDemand', 'AddWindowsCapability', 'WinPEADKPE', 'WinPEADKRE', 'WinPEADKSE', 'WinPEDaRT', 'WinPEDrivers',
                'WinPEExtraFilesPE', 'WinPEExtraFilesRE', 'WinPEExtraFilesSE', 'WinPEScriptsPE', 'WinPEScriptsRE', 'WinPEScriptsSE',
                'LangSetAllIntl', 'LangSetInputLocale', 'LangSetSKUIntlDefaults', 'LangSetSetupUILang', 'LangSetSysLocale', 'LangSetUILang',
                'LangSetUILangFallback', 'LangSetUserLocale', 'LanguagePack', 'LanguageInterfacePack', 'LocalExperiencePacks', 'LanguageFeature', 'LanguageCopySources') {
                $Task.PSObject.Properties.Name | Should -Contain $Property
                $Task.$Property | Should -BeNullOrEmpty -Because $Property
            }
            Should -Invoke Get-OSMedia -Times 0 -Exactly
            Should -Invoke Out-GridView -Times 0 -Exactly
            Should -Invoke Get-TaskContentLanguagePack -Times 0 -Exactly
            Should -Invoke Get-TaskContentAddWindowsCapability -Times 0 -Exactly
        }

        It 'saves a Template in the Templates directory' {
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -SaveAs Template 6>$null 3>$null | Out-Null
            (Get-TestTask -Folder $global:SetOSDBuilderPathTemplates).TaskName | Should -Be 'Contoso'
            Join-Path $global:SetOSDBuilderPathTasks 'OSBuild Contoso.json' | Should -Not -Exist
        }

        It 'accepts the OSMedia from the pipeline' {
            $OSMedia | New-OSBuildTask -TaskName 'Contoso' 6>$null 3>$null | Out-Null
            (Get-TestTask).OSMGuid | Should -Be $OSMedia.OSMGuid
        }

        It 'accepts an OSImport as OSMedia' {
            $OSImport = New-TestOSMedia -Name 'Windows 11 Enterprise x64 25H2 26200.6584' -MediaType 'OSImport'
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSImport 6>$null 3>$null | Out-Null
            (Get-TestTask).Name | Should -Be 'Windows 11 Enterprise x64 25H2 26200.6584'
        }

        It 'reads the Windows Image of the OSMedia install.wim' {
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia 6>$null 3>$null | Out-Null
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq "$($OSMedia.FullName)\OS\sources\install.wim") -and ($Index -eq 1)}
        }

        It 'initializes OSDBuilder and blocks standard users' {
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia 6>$null 3>$null | Out-Null
            Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
            Should -Invoke Block-StandardUser -Times 1 -Exactly
        }

        It 'exits with a warning when the media type is not OSMedia or OSImport' {
            $OSBuild = New-TestOSMedia -MediaType 'OSBuild'
            $Warnings = foreach ($Once in 1) {New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSBuild 6>$null 3>&1}
            ($Warnings -join "`n") | Should -BeLike '*media type is not correct*'
            Join-Path $global:SetOSDBuilderPathTasks 'OSBuild Contoso.json' | Should -Not -Exist
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }
    }

    Context 'OSMedia selection' {
        BeforeEach {
            $script:AllOSMedia = @(
                New-TestOSMedia -Name 'x64 25H2' -Arch 'x64' -ReleaseId '25H2'
                New-TestOSMedia -Name 'x86 22H2' -Arch 'x86' -ReleaseId '22H2' -Build '19045'
                New-TestOSMedia -Name 'x64 20H2' -Arch 'x64' -ReleaseId '20H2' -Build '19042'
            )
            foreach ($ReleaseId in '1511', '1607', '1703', '1709', '1803', '1809', '1903', '1909', '2004', '21H1', '21H2', '23H2', '24H2', '26H2') {
                $script:AllOSMedia += New-TestOSMedia -Name "x64 $ReleaseId" -ReleaseId $ReleaseId
            }
            Mock Get-OSMedia {$script:AllOSMedia}
        }

        It 'selects the OSMedia in Out-GridView from Get-OSMedia' {
            New-OSBuildTask -TaskName 'Contoso' 6>$null 3>$null | Out-Null
            Should -Invoke Get-OSMedia -Times 1 -Exactly -ParameterFilter {($Revision -eq 'OK') -and ($OSMajorVersion -eq 10)}
            Should -Invoke Out-GridView -ParameterFilter {$OutputMode -eq 'Single'}
            $script:GridInput.Count | Should -Be $script:AllOSMedia.Count
        }

        It 'offers only the OSMedia matching <TaskName>' -ForEach @(
            @{TaskName = 'Contoso x86'; Expected = @('x86 22H2')}
            @{TaskName = 'Contoso x64 25H2'; Expected = @('x64 25H2')}
            @{TaskName = 'Contoso 2009'; Expected = @('x64 20H2')}
            @{TaskName = 'Contoso 20H2'; Expected = @('x64 20H2')}
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
            New-OSBuildTask -TaskName $TaskName 6>$null 3>$null | Out-Null
            @($script:GridInput.Name) | Should -Be $Expected
            (Get-TestTask -Name $TaskName).Name | Should -Be $Expected[0]
        }

        It 'exits with a warning when Out-GridView fails' {
            Mock Out-GridView {throw 'Out-GridView is not available'}
            $Warnings = foreach ($Once in 1) {New-OSBuildTask -TaskName 'Contoso' 6>$null 3>&1}
            ($Warnings -join "`n") | Should -BeLike '*Source OSMedia was not selected*'
            Join-Path $global:SetOSDBuilderPathTasks 'OSBuild Contoso.json' | Should -Not -Exist
        }

        #$OSMedia has [ValidateNotNullOrEmpty()], assigning the empty selection throws into the Catch block
        It 'exits with a warning and writes no Task when the OSMedia selection is cancelled' {
            Mock Out-GridView {}
            $Warnings = foreach ($Once in 1) {New-OSBuildTask -TaskName 'Contoso' 6>$null 3>&1}
            ($Warnings -join "`n") | Should -BeLike '*Source OSMedia was not selected*'
            Join-Path $global:SetOSDBuilderPathTasks 'OSBuild Contoso.json' | Should -Not -Exist
        }
    }

    Context 'ReleaseId' {
        It 'reads the DisplayVersion from CurrentVersion.xml when the OSMedia has no ReleaseId' {
            $OSMedia = New-TestOSMedia -ReleaseId $null -CurrentVersion @{ReleaseId = '2009'; DisplayVersion = '22H2'}
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia 6>$null 3>$null | Out-Null
            (Get-TestTask).ReleaseId | Should -Be '22H2'
        }

        It 'reads the ReleaseId from CurrentVersion.xml without DisplayVersion' {
            $OSMedia = New-TestOSMedia -ReleaseId $null -CurrentVersion @{ReleaseId = '1809'}
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia 6>$null 3>$null | Out-Null
            (Get-TestTask).ReleaseId | Should -Be '1809'
        }

        It 'sets the ReleaseId <ReleaseId> of Build <Build> without CurrentVersion.xml' -ForEach @(
            @{Build = '7600'; ReleaseId = '7600'}, @{Build = '7601'; ReleaseId = '7601'}, @{Build = '9600'; ReleaseId = '9600'}
            @{Build = '10240'; ReleaseId = '1507'}, @{Build = '14393'; ReleaseId = '1607'}, @{Build = '15063'; ReleaseId = '1703'}
            @{Build = '16299'; ReleaseId = '1709'}, @{Build = '17134'; ReleaseId = '1803'}, @{Build = '17763'; ReleaseId = '1809'}
        ) {
            $OSMedia = New-TestOSMedia -ReleaseId $null -Build $Build
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia 6>$null 3>$null | Out-Null
            (Get-TestTask).ReleaseId | Should -Be $ReleaseId
        }
    }

    Context 'Selections' {
        BeforeEach {
            Mock Get-TaskContentPacks {Item Name 'Contoso', '_Global'}
            Mock Get-TaskRemoveAppxProvisionedPackage {Item PackageName 'Microsoft.ZuneMusic_8wekyb3d8bbwe', 'Microsoft.BingWeather_8wekyb3d8bbwe'}
            Mock Get-TaskRemoveWindowsCapability {Item Name 'App.StepsRecorder~~~~0.0.1.0'}
            Mock Get-TaskRemoveWindowsPackage {Item PackageName 'Microsoft-Windows-Hello-Face-Package~31bf3856ad364e35~amd64~~10.0.26100.1'}
            Mock Get-TaskDisableWindowsOptionalFeature {Item FeatureName 'WindowsMediaPlayer'}
            Mock Get-TaskEnableWindowsOptionalFeature {Item FeatureName 'TelnetClient', 'TFTP'}
            Mock Get-TaskContentDrivers {Item FullName 'Drivers\Dell'}
            Mock Get-TaskContentExtraFiles {Item FullName 'ExtraFiles\Wallpaper'}
            Mock Get-TaskContentScripts {Item FullName 'Scripts\Config.ps1'}
            Mock Get-TaskContentStartLayoutXML {Item FullName 'StartLayout\Start.xml'}
            Mock Get-TaskContentUnattendXML {Item FullName 'Unattend\Unattend.xml'}
            Mock Get-TaskContentAddWindowsPackage {Item FullName 'Packages\Package.cab'}
            Mock Get-TaskContentAddFeatureOnDemand {Item FullName 'IsoExtract\FOD\Microsoft-Windows-NetFx3-OnDemand-Package.cab'}
            Mock Get-TaskContentAddWindowsCapability {Item Name 'Language.Basic~~~de-DE~0.0.1.0', $null, 'Language.Handwriting~~~de-DE~0.0.1.0'}
            Mock Get-TaskContentLanguagePack {Item FullName 'IsoExtract\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab'}
            Mock Get-TaskContentLanguageFeature {Item FullName 'IsoExtract\Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab'}
            Mock Get-TaskContentLanguageInterfacePack {Item FullName 'IsoExtract\Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab'}
            Mock Get-TaskContentLocalExperiencePacks {Item FullName 'IsoExtract\LocalExperiencePack\de-de\LanguageExperiencePack.de-DE.Neutral.appx'}
            Mock Get-TaskContentLanguageCopySources {Item OSMFamily 'Enterprise x64 26200 de-DE'}
            Mock Get-TaskWinPEDaRT {Item FullName 'DaRT\10\Toolsx64.cab'}
            Mock Get-TaskWinPEADKPE {Item FullName 'ADK\x64\WinPE_OCs\WinPE-PowerShell.cab', 'ADK\x64\WinPE_OCs\WinPE-WMI.cab'}
            Mock Get-TaskWinPEADKRE {Item FullName 'ADK\x64\WinPE_OCs\WinPE-NetFx.cab'}
            Mock Get-TaskWinPEADKSE {Item FullName 'ADK\x64\WinPE_OCs\WinPE-SecureStartup.cab'}
            Mock Get-TaskWinPEDrivers {Item FullName 'Drivers\WinPE\Intel'}
            Mock Get-TaskWinPEExtraFilesPE {Item FullName 'ExtraFiles\WinPE\Tools'}
            Mock Get-TaskWinPEExtraFilesRE {Item FullName 'ExtraFiles\WinRE\Tools'}
            Mock Get-TaskWinPEExtraFilesSE {Item FullName 'ExtraFiles\WinSE\Tools'}
            Mock Get-TaskWinPEScriptsPE {Item FullName 'Scripts\WinPE\Config.ps1'}
            Mock Get-TaskWinPEScriptsRE {Item FullName 'Scripts\WinRE\Config.ps1'}
            Mock Get-TaskWinPEScriptsSE {Item FullName 'Scripts\WinSE\Config.ps1'}
            $script:All = @{
                AddContentPacks = $true; RemoveAppx = $true; RemoveCapability = $true; RemovePackage = $true; DisableFeature = $true; EnableFeature = $true
                ContentDrivers = $true; ContentExtraFiles = $true; ContentScripts = $true; ContentStartLayout = $true; ContentUnattend = $true
                ContentPackages = $true; ContentFeaturesOnDemand = $true; ContentLanguagePackages = $true; SourcesLanguageCopy = $true
                ContentWinPEDart = $true; ContentWinPEADK = $true; ContentWinPEDrivers = $true; ContentWinPEExtraFiles = $true; ContentWinPEScripts = $true
            }
        }

        It 'writes every selection to the Task JSON' {
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia @script:All 6>$null 3>$null | Out-Null

            $Task = Get-TestTask
            $Task.ContentPacks | Should -Be @('_Global', 'Contoso')
            $Task.RemoveAppxProvisionedPackage | Should -Be @('Microsoft.BingWeather_8wekyb3d8bbwe', 'Microsoft.ZuneMusic_8wekyb3d8bbwe')
            $Task.RemoveWindowsCapability | Should -Be @('App.StepsRecorder~~~~0.0.1.0')
            $Task.RemoveWindowsPackage | Should -Be @('Microsoft-Windows-Hello-Face-Package~31bf3856ad364e35~amd64~~10.0.26100.1')
            $Task.DisableWindowsOptionalFeature | Should -Be @('WindowsMediaPlayer')
            $Task.EnableWindowsOptionalFeature | Should -Be @('TelnetClient', 'TFTP')
            $Task.Drivers | Should -Be @('Drivers\Dell')
            $Task.ExtraFiles | Should -Be @('ExtraFiles\Wallpaper')
            $Task.Scripts | Should -Be @('Scripts\Config.ps1')
            $Task.StartLayoutXML | Should -Be 'StartLayout\Start.xml'
            $Task.UnattendXML | Should -Be 'Unattend\Unattend.xml'
            $Task.AddWindowsPackage | Should -Be @('Packages\Package.cab')
            $Task.AddWindowsCapability | Should -Be @('Language.Basic~~~de-DE~0.0.1.0', 'Language.Handwriting~~~de-DE~0.0.1.0')
            $Task.AddFeatureOnDemand | Should -BeNullOrEmpty
            $Task.LanguagePack | Should -Be @('IsoExtract\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab')
            $Task.LanguageFeature | Should -Be @('IsoExtract\Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab')
            $Task.LanguageInterfacePack | Should -Be @('IsoExtract\Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab')
            $Task.LocalExperiencePacks | Should -Be @('IsoExtract\LocalExperiencePack\de-de\LanguageExperiencePack.de-DE.Neutral.appx')
            $Task.LanguageCopySources | Should -Be @('Enterprise x64 26200 de-DE')
            $Task.WinPEDaRT | Should -Be 'DaRT\10\Toolsx64.cab'
            $Task.WinPEADKPE | Should -Be @('ADK\x64\WinPE_OCs\WinPE-WMI.cab', 'ADK\x64\WinPE_OCs\WinPE-PowerShell.cab')
            $Task.WinPEADKRE | Should -Be @('ADK\x64\WinPE_OCs\WinPE-NetFx.cab')
            $Task.WinPEADKSE | Should -Be @('ADK\x64\WinPE_OCs\WinPE-SecureStartup.cab')
            $Task.WinPEDrivers | Should -Be @('Drivers\WinPE\Intel')
            $Task.WinPEExtraFilesPE | Should -Be @('ExtraFiles\WinPE\Tools')
            $Task.WinPEExtraFilesRE | Should -Be @('ExtraFiles\WinRE\Tools')
            $Task.WinPEExtraFilesSE | Should -Be @('ExtraFiles\WinSE\Tools')
            $Task.WinPEScriptsPE | Should -Be @('Scripts\WinPE\Config.ps1')
            $Task.WinPEScriptsRE | Should -Be @('Scripts\WinRE\Config.ps1')
            $Task.WinPEScriptsSE | Should -Be @('Scripts\WinSE\Config.ps1')
        }

        It 'writes the language settings to the Lang properties' {
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -SetAllIntl 'de-DE' -SetInputLocale '0407:00000407' -SetSKUIntlDefaults 'de-DE' -SetSetupUILang 'de-DE' `
                -SetSysLocale 'de-DE' -SetUILang 'de-DE' -SetUILangFallback 'en-US' -SetUserLocale 'de-AT' 6>$null 3>$null | Out-Null

            $Task = Get-TestTask
            $Task.LangSetAllIntl | Should -Be 'de-DE'
            $Task.LangSetInputLocale | Should -Be '0407:00000407'
            $Task.LangSetSKUIntlDefaults | Should -Be 'de-DE'
            $Task.LangSetSetupUILang | Should -Be 'de-DE'
            $Task.LangSetSysLocale | Should -Be 'de-DE'
            $Task.LangSetUILang | Should -Be 'de-DE'
            $Task.LangSetUILangFallback | Should -Be 'en-US'
            $Task.LangSetUserLocale | Should -Be 'de-AT'
        }

        It 'generates the IsoExtract content and filters the WinPE and Windows Server content for a Client OSMedia' {
            Mock Get-TaskContentIsoExtract {Item FullName 'IsoExtract\Windows 11 Client\lp.cab', 'IsoExtract\Windows Server 2025\lp.cab', 'IsoExtract\Windows Preinstallation Environment\lp.cab'}
            Mock Get-TaskContentLanguagePack {$script:SeenIsoExtract = @($ContentIsoExtract.FullName); $script:SeenIsoExtractWinPE = @($ContentIsoExtractWinPE.FullName)}
            $Warnings = New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -ContentLanguagePackages 6>$null 3>&1
            ($Warnings -join "`n") | Should -BeLike '*Generating IsoExtract Content*'
            $script:SeenIsoExtract | Should -Be @('IsoExtract\Windows 11 Client\lp.cab')
            $script:SeenIsoExtractWinPE | Should -Be @('IsoExtract\Windows Preinstallation Environment\lp.cab')
        }

        It 'keeps only the Windows Server IsoExtract content for a Server OSMedia' {
            $OSMedia = New-TestOSMedia -Name 'Windows Server 2025' -InstallationType 'Server' -Build '26100'
            Mock Get-TaskContentIsoExtract {Item FullName 'IsoExtract\Windows 11 Client\lp.cab', 'IsoExtract\Windows Server 2025\lp.cab'}
            Mock Get-TaskContentLanguagePack {$script:SeenIsoExtract = @($ContentIsoExtract.FullName)}
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -ContentLanguagePackages 6>$null 3>$null | Out-Null
            $script:SeenIsoExtract | Should -Be @('IsoExtract\Windows Server 2025\lp.cab')
        }

        It 'uses Windows Capabilities for Features on Demand with a capability inventory and a repository' {
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -ContentFeaturesOnDemand 6>$null 3>$null | Out-Null
            Should -Invoke Get-OSDBuilderCapabilitySource -Times 1 -Exactly -ParameterFilter {$OSMedia.Name -eq 'Windows 11 Enterprise x64 25H2 26200.6899'}
            Should -Invoke Get-TaskContentAddWindowsCapability -Times 1 -Exactly
            Should -Invoke Get-TaskContentAddFeatureOnDemand -Times 0 -Exactly
            (Get-TestTask).AddWindowsCapability | Should -Be @('Language.Basic~~~de-DE~0.0.1.0', 'Language.Handwriting~~~de-DE~0.0.1.0')
        }

        It 'uses the Features on Demand packages without a capability inventory' {
            $OSMedia = New-TestOSMedia -Name 'No Inventory' -NoCapabilityInventory
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -ContentFeaturesOnDemand 6>$null 3>$null | Out-Null
            Should -Invoke Get-TaskContentAddWindowsCapability -Times 0 -Exactly
            $Task = Get-TestTask
            $Task.AddFeatureOnDemand | Should -Be @('IsoExtract\FOD\Microsoft-Windows-NetFx3-OnDemand-Package.cab')
            $Task.AddWindowsCapability | Should -BeNullOrEmpty
        }

        It 'uses the Features on Demand packages without a Features on Demand repository' {
            Mock Get-OSDBuilderCapabilitySource {}
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -ContentFeaturesOnDemand 6>$null 3>$null | Out-Null
            Should -Invoke Get-TaskContentAddWindowsCapability -Times 0 -Exactly
            (Get-TestTask).AddFeatureOnDemand | Should -Be @('IsoExtract\FOD\Microsoft-Windows-NetFx3-OnDemand-Package.cab')
        }

        It 'warns and writes no ContentPacks when ContentPacks are not enabled' {
            Mock Get-IsContentPacksEnabled {$false}
            $Warnings = New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -AddContentPacks 6>$null 3>&1
            ($Warnings -join "`n") | Should -BeLike '*ContentPacks are not enabled*'
            Should -Invoke Get-TaskContentPacks -Times 0 -Exactly
            (Get-TestTask).ContentPacks | Should -BeNullOrEmpty
        }

        It 'does not select Windows 10 content and disables NetFX3 for a Windows 7 OSMedia' {
            $OSMedia = New-TestOSMedia -Name 'Windows 7' -MajorVersion '6' -Build '7601' -ReleaseId '7601'
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia @script:All -EnableNetFX3 6>$null 3>$null | Out-Null
            Should -Invoke Get-TaskContentIsoExtract -Times 0 -Exactly
            Should -Invoke Get-TaskContentLanguagePack -Times 0 -Exactly
            Should -Invoke Get-TaskContentStartLayoutXML -Times 0 -Exactly
            Should -Invoke Get-TaskContentUnattendXML -Times 0 -Exactly
            Should -Invoke Get-TaskWinPEDaRT -Times 0 -Exactly
            $Task = Get-TestTask
            $Task.EnableNetFX3 | Should -Be 'False'
            $Task.StartLayoutXML | Should -BeNullOrEmpty
            $Task.LanguagePack | Should -BeNullOrEmpty
            $Task.Drivers | Should -Be @('Drivers\Dell')
        }
    }

    Context 'Existing Task' {
        It 'warns that the existing Task is updated' {
            Copy-ExistingTask
            $Warnings = New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia 6>$null 3>&1
            ($Warnings -join "`n") | Should -BeLike '*Task already exists at*OSBuild Contoso.json*'
            ($Warnings -join "`n") | Should -BeLike '*Content will be updated!*'
        }

        It 'keeps the selections of the existing Task without switches' {
            Copy-ExistingTask
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia 6>$null 3>$null | Out-Null

            $Existing = Get-Content -Path (Join-Path $PEBuildTaskFixtures 'OSBuild Existing.json') -Raw | ConvertFrom-Json
            $Task = Get-TestTask
            foreach ($Property in 'ContentPacks', 'RemoveAppxProvisionedPackage', 'RemoveWindowsCapability', 'RemoveWindowsPackage', 'DisableWindowsOptionalFeature',
                'EnableWindowsOptionalFeature', 'Drivers', 'ExtraFiles', 'Scripts', 'StartLayoutXML', 'UnattendXML', 'AddWindowsPackage', 'AddFeatureOnDemand',
                'AddWindowsCapability', 'LanguagePack', 'LanguageFeature', 'LanguageInterfacePack', 'LocalExperiencePacks', 'LanguageCopySources',
                'WinPEDaRT', 'WinPEADKRE', 'WinPEADKSE', 'WinPEDrivers', 'WinPEExtraFilesPE', 'WinPEExtraFilesRE', 'WinPEExtraFilesSE', 'WinPEScriptsPE', 'WinPEScriptsSE') {
                $Task.$Property | Should -Be $Existing.$Property -Because $Property
            }
            $Task.WinPEADKPE | Should -Be @('ADK\x64\WinPE_OCs\WinPE-WMI.cab', 'ADK\x64\WinPE_OCs\WinPE-PowerShell.cab')
            $Task.CustomName | Should -Be 'Existing Custom'
            $Task.EnableNetFX3 | Should -Be 'True'
            $Task.WinPEAutoExtraFiles | Should -Be 'True'
            $Task.WinPEOSDCloud | Should -Be 'True'
            $Task.WinREWiFi | Should -Be 'True'
            $Task.TaskGuid | Should -Not -Be $Existing.TaskGuid
            $Task.OSMGuid | Should -Be $OSMedia.OSMGuid
        }

        It 'keeps the CustomName given as parameter' {
            Copy-ExistingTask
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -CustomName 'New Custom' 6>$null 3>$null | Out-Null
            (Get-TestTask).CustomName | Should -Be 'New Custom'
        }

        It 'merges the new selections with the existing Task' {
            Copy-ExistingTask
            Mock Get-TaskContentPacks {Item Name 'Contoso', 'Fabrikam'}
            Mock Get-TaskRemoveAppxProvisionedPackage {Item PackageName 'Microsoft.BingNews_8wekyb3d8bbwe', 'Microsoft.ZuneMusic_8wekyb3d8bbwe'}
            Mock Get-TaskRemoveWindowsCapability {Item Name 'Browser.InternetExplorer~~~~0.0.11.0'}
            Mock Get-TaskRemoveWindowsPackage {Item PackageName 'Package_B'}
            Mock Get-TaskDisableWindowsOptionalFeature {Item FeatureName 'SMB1Protocol'}
            Mock Get-TaskEnableWindowsOptionalFeature {Item FeatureName 'TelnetClient', 'TFTP'}
            Mock Get-TaskContentDrivers {Item FullName 'Drivers\New'}
            Mock Get-TaskContentExtraFiles {Item FullName 'ExtraFiles\New'}
            Mock Get-TaskContentScripts {Item FullName 'Scripts\New.ps1'}
            Mock Get-TaskContentAddWindowsPackage {Item FullName 'Packages\New.cab'}
            Mock Get-TaskContentAddWindowsCapability {Item Name 'Language.Speech~~~de-DE~0.0.1.0'}
            Mock Get-TaskContentLanguagePack {Item FullName 'IsoExtract\Microsoft-Windows-Client-Language-Pack_x64_fr-fr.cab'}
            Mock Get-TaskContentLanguageFeature {Item FullName 'IsoExtract\Microsoft-Windows-LanguageFeatures-Basic-fr-fr-Package~31bf3856ad364e35~amd64~~.cab'}
            Mock Get-TaskContentLanguageInterfacePack {}
            Mock Get-TaskContentLocalExperiencePacks {Item FullName 'IsoExtract\LocalExperiencePack\fr-fr\LanguageExperiencePack.fr-FR.Neutral.appx'}
            Mock Get-TaskContentLanguageCopySources {Item OSMFamily 'Enterprise x64 26200 fr-FR'}
            Mock Get-TaskWinPEADKPE {Item FullName 'ADK\x64\WinPE_OCs\WinPE-Scripting.cab'}
            Mock Get-TaskWinPEADKRE {Item FullName 'ADK\x64\WinPE_OCs\WinPE-WMI.cab'}
            Mock Get-TaskWinPEADKSE {}
            Mock Get-TaskWinPEDrivers {Item FullName 'Drivers\WinPE\New'}
            Mock Get-TaskWinPEExtraFilesPE {Item FullName 'ExtraFiles\WinPE\New'}
            Mock Get-TaskWinPEExtraFilesRE {Item FullName 'ExtraFiles\WinRE\New'}
            Mock Get-TaskWinPEExtraFilesSE {Item FullName 'ExtraFiles\WinSE\New'}
            Mock Get-TaskWinPEScriptsPE {Item FullName 'Scripts\WinPE\New.ps1'}
            Mock Get-TaskWinPEScriptsRE {Item FullName 'Scripts\WinRE\New.ps1'}
            Mock Get-TaskWinPEScriptsSE {Item FullName 'Scripts\WinSE\New.ps1'}

            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -AddContentPacks -RemoveAppx -RemoveCapability -RemovePackage -DisableFeature -EnableFeature `
                -ContentDrivers -ContentExtraFiles -ContentScripts -ContentPackages -ContentFeaturesOnDemand -ContentLanguagePackages -SourcesLanguageCopy `
                -ContentWinPEADK -ContentWinPEDrivers -ContentWinPEExtraFiles -ContentWinPEScripts 6>$null 3>$null | Out-Null

            $Task = Get-TestTask
            $Task.ContentPacks | Should -Be @('_Global', 'Contoso', 'Fabrikam')
            $Task.RemoveAppxProvisionedPackage | Should -Be @('Microsoft.BingNews_8wekyb3d8bbwe', 'Microsoft.ZuneMusic_8wekyb3d8bbwe')
            $Task.RemoveWindowsCapability | Should -Be @('App.StepsRecorder~~~~0.0.1.0', 'Browser.InternetExplorer~~~~0.0.11.0')
            $Task.RemoveWindowsPackage | Should -Be @('Microsoft-Windows-Hello-Face-Package~31bf3856ad364e35~amd64~~10.0.26100.1', 'Package_B')
            $Task.DisableWindowsOptionalFeature | Should -Be @('SMB1Protocol', 'WindowsMediaPlayer')
            $Task.EnableWindowsOptionalFeature | Should -Be @('TelnetClient', 'TFTP')
            $Task.Drivers | Should -Be @('Drivers\Existing', 'Drivers\New')
            $Task.ExtraFiles | Should -Be @('ExtraFiles\Existing', 'ExtraFiles\New')
            $Task.Scripts | Should -Be @('Scripts\Existing.ps1', 'Scripts\New.ps1')
            $Task.AddWindowsPackage | Should -Be @('Packages\Existing.cab', 'Packages\New.cab')
            $Task.AddWindowsCapability | Should -Be @('Language.Basic~~~de-DE~0.0.1.0', 'Language.Speech~~~de-DE~0.0.1.0')
            $Task.AddFeatureOnDemand | Should -Be @('IsoExtract\FOD\Existing.cab')
            $Task.LanguagePack | Should -Be @('IsoExtract\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab', 'IsoExtract\Microsoft-Windows-Client-Language-Pack_x64_fr-fr.cab')
            $Task.LanguageFeature | Should -Be @('IsoExtract\Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab', 'IsoExtract\Microsoft-Windows-LanguageFeatures-Basic-fr-fr-Package~31bf3856ad364e35~amd64~~.cab')
            $Task.LanguageInterfacePack | Should -Be @('IsoExtract\Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab')
            $Task.LocalExperiencePacks | Should -Be @('IsoExtract\LocalExperiencePack\de-de\LanguageExperiencePack.de-DE.Neutral.appx', 'IsoExtract\LocalExperiencePack\fr-fr\LanguageExperiencePack.fr-FR.Neutral.appx')
            $Task.LanguageCopySources | Should -Be @('Enterprise x64 26200 de-DE', 'Enterprise x64 26200 fr-FR')
            $Task.WinPEADKPE | Should -Be @('ADK\x64\WinPE_OCs\WinPE-WMI.cab', 'ADK\x64\WinPE_OCs\WinPE-Scripting.cab', 'ADK\x64\WinPE_OCs\WinPE-PowerShell.cab')
            $Task.WinPEADKRE | Should -Be @('ADK\x64\WinPE_OCs\WinPE-WMI.cab')
            $Task.WinPEADKSE | Should -Be @('ADK\x64\WinPE_OCs\WinPE-SecureStartup.cab')
            $Task.WinPEDrivers | Should -Be @('Drivers\WinPE\Existing', 'Drivers\WinPE\New')
            $Task.WinPEExtraFilesPE | Should -Be @('ExtraFiles\WinPE\Existing', 'ExtraFiles\WinPE\New')
            $Task.WinPEExtraFilesRE | Should -Be @('ExtraFiles\WinRE\Existing', 'ExtraFiles\WinRE\New')
            $Task.WinPEExtraFilesSE | Should -Be @('ExtraFiles\WinSE\Existing', 'ExtraFiles\WinSE\New')
            $Task.WinPEScriptsPE | Should -Be @('Scripts\WinPE\Existing.ps1', 'Scripts\WinPE\New.ps1')
            $Task.WinPEScriptsRE | Should -Be @('Scripts\WinRE\Existing.ps1', 'Scripts\WinRE\New.ps1')
            $Task.WinPEScriptsSE | Should -Be @('Scripts\WinSE\Existing.ps1', 'Scripts\WinSE\New.ps1')
        }

        It 'replaces StartLayout, Unattend and DaRT with the new selection' {
            Copy-ExistingTask
            Mock Get-TaskContentStartLayoutXML {Item FullName 'StartLayout\New.xml'}
            Mock Get-TaskContentUnattendXML {Item FullName 'Unattend\New.xml'}
            Mock Get-TaskWinPEDaRT {Item FullName 'DaRT\10\New.cab'}
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -ContentStartLayout -ContentUnattend -ContentWinPEDart 6>$null 3>$null | Out-Null
            $Task = Get-TestTask
            $Task.StartLayoutXML | Should -Be 'StartLayout\New.xml'
            $Task.UnattendXML | Should -Be 'Unattend\New.xml'
            $Task.WinPEDaRT | Should -Be 'DaRT\10\New.cab'
        }

        It 'keeps StartLayout and Unattend of the existing Task when nothing is selected' {
            Copy-ExistingTask
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -ContentStartLayout -ContentUnattend 6>$null 3>$null | Out-Null
            Should -Invoke Get-TaskContentStartLayoutXML -Times 1 -Exactly
            $Task = Get-TestTask
            $Task.StartLayoutXML | Should -Be 'StartLayout\Existing.xml'
            $Task.UnattendXML | Should -Be 'Unattend\Existing.xml'
        }

        It 'keeps the switches False when the existing Task has them False' {
            Copy-ExistingTask -Change {$Task.EnableNetFX3 = 'False'; $Task.WinPEAutoExtraFiles = 'False'; $Task.WinPEOSDCloud = 'False'; $Task.WinREWiFi = 'False'; $Task.CustomName = ''}
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia 6>$null 3>$null | Out-Null
            $Task = Get-TestTask
            $Task.EnableNetFX3 | Should -Be 'False'
            $Task.WinPEAutoExtraFiles | Should -Be 'False'
            $Task.WinPEOSDCloud | Should -Be 'False'
            $Task.WinREWiFi | Should -Be 'False'
            $Task.CustomName | Should -BeNullOrEmpty
        }

        It 'keeps the language settings of the existing Task when they are not given' {
            Copy-ExistingTask
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -SetUserLocale 'de-CH' 6>$null 3>$null | Out-Null
            $Task = Get-TestTask
            $Task.LangSetUserLocale | Should -Be 'de-CH'
        }

        # KnownBug: New-OSBuildTask.ps1:910-917 compare the [string] parameters with $null (always '' when not given) and read SetAllIntl instead of LangSetAllIntl, the existing language settings are lost
        It 'keeps the Lang settings of the existing Task when the parameters are not given' -Skip {
            Copy-ExistingTask
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia 6>$null 3>$null | Out-Null
            $Task = Get-TestTask
            $Task.LangSetAllIntl | Should -Be 'de-DE'
            $Task.LangSetInputLocale | Should -Be '0407:00000407'
            $Task.LangSetSKUIntlDefaults | Should -Be 'de-DE'
            $Task.LangSetSetupUILang | Should -Be 'de-DE'
            $Task.LangSetSysLocale | Should -Be 'de-DE'
            $Task.LangSetUILang | Should -Be 'de-DE'
            $Task.LangSetUILangFallback | Should -Be 'en-US'
            $Task.LangSetUserLocale | Should -Be 'de-AT'
        }

        # KnownBug: New-OSBuildTask.ps1:916 assigns the existing SetUILangFallback to $SetUILang instead of $SetUILangFallback (masked by the $null check of 910-917, the fallback is lost)
        It 'does not overwrite -SetUILang with the existing SetUILangFallback' -Skip {
            Copy-ExistingTask
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia -SetUILang 'fr-FR' 6>$null 3>$null | Out-Null
            $Task = Get-TestTask
            $Task.LangSetUILang | Should -Be 'fr-FR'
            $Task.LangSetUILangFallback | Should -Be 'en-US'
        }

        # KnownBug: New-OSBuildTask.ps1:878 reads $ExistingTask.$WinPEScriptsRE (dynamic property name $null) instead of $ExistingTask.WinPEScriptsRE
        It 'keeps the WinPEScriptsRE of the existing Task without -ContentWinPEScripts' -Skip {
            Copy-ExistingTask
            New-OSBuildTask -TaskName 'Contoso' -OSMedia $OSMedia 6>$null 3>$null | Out-Null
            (Get-TestTask).WinPEScriptsRE | Should -Be @('Scripts\WinRE\Existing.ps1')
        }
    }
}
