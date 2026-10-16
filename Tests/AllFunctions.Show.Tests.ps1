#Tests for the AllFunctions.ps1 functions Show-*
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}

    #Public function that is not dot-sourced with the Private scripts
    function Get-OSMedia {
        [CmdletBinding()]
        param ($Revision)
    }
}

Describe 'Show-ActionTime' {
    BeforeAll {
        $SavedStartTime = $Global:OSDStartTime
    }
    AfterAll {
        $Global:OSDStartTime = $SavedStartTime
    }

    It 'writes the start time without a new line and saves it in OSDStartTime' {
        $Before = Get-Date
        $Output = @(Show-ActionTime 6>&1)
        $Output.Count | Should -Be 1
        $Global:OSDStartTime | Should -BeGreaterOrEqual $Before.AddSeconds(-1)
        "$($Output[0])" | Should -Be "$($Global:OSDStartTime.ToString('yyyy-MM-dd-HHmmss')) "
        $Output[0].MessageData.NoNewLine | Should -BeTrue
    }
}

Describe 'Show-GetWindowsImage' {
    It 'writes the header and returns the Windows image' {
        $GetWindowsImage = [PSCustomObject]@{ImageName = 'Windows 11 Enterprise'; ImageIndex = 3}
        $Output = Show-GetWindowsImage 6>$null
        $Output.ImageName | Should -Be 'Windows 11 Enterprise'
        (Show-GetWindowsImage 6>&1) -join "`n" | Should -BeLike '*Windows Image Information*'
    }
}

Describe 'Show-MediaImageInfoOS' {
    It 'shows the image information of the source OSMedia' {
        $OSMediaPath = 'C:\OSDBuilder\OSMedia\Windows 11 Enterprise x64 25H2 6899'; $OSImagePath = 'C:\OSMedia\OS\sources\install.wim'
        $OSImageName = 'Windows 11 Enterprise'; $OSImageDescription = 'Windows 11 Enterprise'; $OSArchitecture = 'x64'; $OSEditionID = 'Enterprise'
        $OSInstallationType = 'Client'; $OSLanguages = 'en-US'; $OSMajorVersion = 10; $OSBuild = 26200; $OSVersion = '10.0.26200.6899'
        $OSSPBuild = 6899; $OSSPLevel = 0; $OSCreatedTime = '10/14/2026 10:00:00'; $OSModifiedTime = '10/14/2026 11:00:00'
        $Output = (Show-MediaImageInfoOS 6>&1) -join "`n"
        $Output | Should -BeLike '*Source OSMedia Windows Image Information*'
        $Output | Should -BeLike "*-OSMedia Path:*$OSMediaPath*"
        $Output | Should -BeLike '*-Image File:*C:\OSMedia\OS\sources\install.wim*'
        $Output | Should -BeLike '*-Edition:*Enterprise*'
        $Output | Should -BeLike '*-Major Version:*10*'
        $Output | Should -BeLike '*-Version:*10.0.26200.6899*'
        $Output | Should -BeLike '*-SPBuild:*6899*'
        $Output | Should -BeLike '*-Modified Time:*10/14/2026 11:00:00*'
    }
}

Describe 'Show-MediaInfoOS' {
    It 'shows the OSMedia paths' {
        $OSMediaName = 'Windows 11 Enterprise x64 25H2 6899'; $OSMediaPath = 'C:\OSDBuilder\OSMedia\Windows 11 Enterprise x64 25H2 6899'
        $OS = "$OSMediaPath\OS"; $WinPE = "$OSMediaPath\WinPE"; $Info = "$OSMediaPath\info"
        $Output = (Show-MediaInfoOS 6>&1) -join "`n"
        $Output | Should -BeLike '*OSMedia Information*'
        $Output | Should -BeLike "*-OSMediaName:*$OSMediaName*"
        $Output | Should -BeLike "*-WinPE:*$OSMediaPath\WinPE*"
        $Output | Should -BeLike "*-Logs:*$OSMediaPath\info\logs*"
    }
}

Describe 'Show-OSDBuilderHomeMap' {
    BeforeEach {
        $GetOSDBuilderHome = Join-Path $TestDrive 'OSDBuilder'
        $SetOSDBuilderPathContentPacks = Join-Path $GetOSDBuilderHome 'ContentPacks'
        Mock Get-IsContentPacksEnabled {$true}
    }

    It 'shows the existing home and ContentPacks directories' {
        New-Item -Path $SetOSDBuilderPathContentPacks -ItemType Directory -Force | Out-Null
        $Output = @(Show-OSDBuilderHomeMap 6>&1) | ForEach-Object {"$_"}
        $Output | Should -Contain "OSDBuilder Home:                                    $GetOSDBuilderHome"
        $Output | Should -Contain "ContentPacks:                                         $SetOSDBuilderPathContentPacks"
    }

    It 'marks directories that do not exist' {
        $GetOSDBuilderHome = Join-Path $TestDrive 'Missing'
        $SetOSDBuilderPathContentPacks = Join-Path $GetOSDBuilderHome 'ContentPacks'
        $Output = (Show-OSDBuilderHomeMap 6>&1) -join "`n"
        $Output | Should -BeLike "*$GetOSDBuilderHome (does not exist)*"
        $Output | Should -BeLike "*$SetOSDBuilderPathContentPacks (does not exist)*"
    }

    It 'does not show ContentPacks when they are disabled' {
        Mock Get-IsContentPacksEnabled {$false}
        (Show-OSDBuilderHomeMap 6>&1) -join "`n" | Should -Not -BeLike '*ContentPacks*'
    }
}

Describe 'Show-OSDBuilderHomeTips' {
    It 'shows the shortcuts' {
        $Output = (Show-OSDBuilderHomeTips 6>&1) -join "`n"
        $Output | Should -BeLike '*Shortcuts:*'
        $Output | Should -BeLike '*OSDBuilder -SetHome D:\OSDBuilder*Change OSDBuilder Home Path*'
        $Output | Should -BeLike '*OSDBuilder -Download FeatureUpdates*Download Windows 10 and 11 Feature Updates for Import*'
        $Output | Should -BeLike '*Update-OSMedia -Download -Execute*Update an OS (Downloads Updates)*'
    }
}

Describe 'Show-OSMediaInfo' {
    It 'shows the OSMedia name and paths' {
        $OSMediaName = 'Windows 11 Enterprise x64 25H2 6899'; $OSMediaPath = 'C:\OSDBuilder\OSMedia\Windows 11 Enterprise x64 25H2 6899'
        $OSMediaPathOS = "$OSMediaPath\OS"; $OSMediaPathWinPE = "$OSMediaPath\WinPE"; $OSMediaPathInfo = "$OSMediaPath\info"
        $Output = (Show-OSMediaInfo 6>&1) -join "`n"
        $Output | Should -BeLike "*-OSMedia Name:*$OSMediaName*"
        $Output | Should -BeLike "*-OSMedia Path OS:*$OSMediaPath\OS*"
        $Output | Should -BeLike "*-OSMedia Path WinPE:*$OSMediaPath\WinPE*"
        $Output | Should -BeLike "*-OSMedia Path Info:*$OSMediaPath\info*"
    }
}

Describe 'Show-SkipUpdatesInfo' {
    It 'writes nothing' {
        @(Show-SkipUpdatesInfo 6>&1 3>&1) | Should -BeNullOrEmpty
    }
}

Describe 'Show-TaskInfo' {
    BeforeEach {
        $SetOSDBuilderPathContent = 'C:\OSDBuilder\Content'; $SetOSDBuilderPathContentPacks = 'C:\OSDBuilder\ContentPacks'
        $TaskName = 'Win11 Enterprise de-DE'; $TaskVersion = '26.10.14.1'; $TaskType = 'OSBuild'; $CustomName = 'Win11 Custom'
        $OSMediaName = 'Windows 11 Enterprise x64 25H2 6899'; $OSMediaPath = 'C:\OSDBuilder\OSMedia\Windows 11 Enterprise x64 25H2 6899'
        $TaskOSMFamily = 'Client Enterprise x64 26200 en-US'
        $ContentPacks = @('_Global', 'Win11 x64 25H2'); $EnableNetFX3 = $true; $WinPEAutoExtraFiles = $true; $WinPEOSDCloud = $true; $WinREWiFi = $true
        $DisableFeature = @('SMB1Protocol'); $EnableFeature = @('NetFx3'); $RemoveAppx = @('Microsoft.BingNews', 'Microsoft.BingNews')
        $RemoveCapability = @('App.StepsRecorder~~~~0.0.1.0'); $RemovePackage = @('Microsoft-Windows-Hello-Face-Package')
        $StartLayoutXML = 'StartLayout\Layout.xml'; $UnattendXML = 'Unattend\Unattend.xml'; $WinPEDaRT = 'DaRT\DaRT 10\MSDaRT100.wim'
        $Drivers = @('Drivers\Dell'); $ExtraFiles = @('ExtraFiles\Zeta', 'ExtraFiles\Alpha', 'ExtraFiles\Zeta'); $FeaturesOnDemand = @('FOD\Language.Basic.cab')
        $AddWindowsCapability = @('Language.Basic~~~de-DE~0.0.1.0'); $Packages = @('Packages\Package.cab'); $Scripts = @('Scripts\Cleanup.ps1')
        $WinPEDrivers = @('WinPE\Drivers\Intel'); $WinPEADKPE = @('ADK\WinPE-PowerShell.cab', 'ADK\WinPE-WMI.cab', 'ADK\WinPE-PowerShell.cab')
        $WinPEADKRE = @('ADK\WinPE-WMI.cab'); $WinPEADKSE = @('ADK\WinPE-Setup.cab')
        $WinPEExtraFilesPE = @('WinPE\ExtraFiles\PE'); $WinPEExtraFilesRE = @('WinPE\ExtraFiles\RE'); $WinPEExtraFilesSE = @('WinPE\ExtraFiles\SE')
        $WinPEScriptsPE = @('WinPE\Scripts\PE.ps1'); $WinPEScriptsRE = @('WinPE\Scripts\RE.ps1'); $WinPEScriptsSE = @('WinPE\Scripts\SE.ps1')
        $SetAllIntl = 'de-DE'; $SetInputLocale = '0407:00000407'; $SetSKUIntlDefaults = 'de-DE'; $SetSetupUILang = 'de-DE'
        $SetSysLocale = 'de-DE'; $SetUILang = 'de-DE'; $SetUILangFallback = 'en-US'; $SetUserLocale = 'de-AT'
        $LanguageFeatures = @('Language.Speech~~~de-DE~0.0.1.0'); $LanguageInterfacePacks = @('LIP\de-AT.cab'); $LanguagePacks = @('LanguagePacks\de-DE.cab')
        $LocalExperiencePacks = @('LXP\de-DE\LanguageExperiencePack.de-DE.Neutral.appx'); $LanguageCopySources = @('de-DE')

        $OSMediaDirectory = Join-Path $TestDrive "OSMedia$([guid]::NewGuid().Guid)"
        New-Item -Path $OSMediaDirectory -ItemType Directory -Force | Out-Null
        $script:OSMediaGuid = [guid]::NewGuid().Guid
        $script:OSMediaDirectory = $OSMediaDirectory
        Mock Get-IsContentPacksEnabled {$true}
        Mock Get-OSMedia {
            [PSCustomObject]@{
                OSMFamily = 'Client Enterprise x64 26200 en-US'; OSMGuid = $script:OSMediaGuid; FullName = $script:OSMediaDirectory
                ImageName = 'Windows 11 Enterprise'; Arch = 'x64'; ReleaseId = '25H2'; UBR = '6899'; Languages = @('en-US', 'de-DE')
                EditionId = 'Enterprise'; InstallationType = 'Client'; MajorVersion = '10'; Build = '26200'
                CreatedTime = [datetime]'2026-10-14 10:00:00'; ModifiedTime = [datetime]'2026-10-14 11:00:00'
            }
            [PSCustomObject]@{OSMFamily = 'Client Enterprise x64 19045 en-US'; OSMGuid = [guid]::NewGuid().Guid; FullName = (Join-Path $TestDrive 'Other')}
        }
    }

    It 'shows the task settings' {
        $Output = (Show-TaskInfo 6>&1) -join "`n"
        $Output | Should -BeLike '*OSBuild Task Information*'
        $Output | Should -BeLike '*-TaskName:*Win11 Enterprise de-DE*'
        $Output | Should -BeLike '*-Custom Name:*Win11 Custom*'
        $Output | Should -BeLike '*-ContentPacks:*C:\OSDBuilder\ContentPacks\_Global*C:\OSDBuilder\ContentPacks\Win11 x64 25H2*'
        $Output | Should -BeLike '*-Enable NetFx3:*True*'
        $Output | Should -BeLike '*-WinPE Auto ExtraFiles:*True*'
        $Output | Should -BeLike '*-WinPE OSDCloud:*True*'
        $Output | Should -BeLike '*-WinRE WiFi*True*'
        $Output | Should -BeLike '*-Disable Feature:*SMB1Protocol*'
        $Output | Should -BeLike '*-Enable Feature:*NetFx3*'
        $Output | Should -BeLike '*-Remove Appx:*Microsoft.BingNews*'
        $Output | Should -BeLike '*-Remove Capability:*App.StepsRecorder~~~~0.0.1.0*'
        $Output | Should -BeLike '*-Remove Packages:*Microsoft-Windows-Hello-Face-Package*'
        $Output | Should -BeLike '*-Start Layout:*C:\OSDBuilder\Content\StartLayout\Layout.xml*'
        $Output | Should -BeLike '*-Unattend:*C:\OSDBuilder\Content\Unattend\Unattend.xml*'
        $Output | Should -BeLike '*-WinPE DaRT:*C:\OSDBuilder\Content\DaRT\DaRT 10\MSDaRT100.wim*'
        $Output | Should -BeLike '*-Drivers:*C:\OSDBuilder\Content\Drivers\Dell*'
        $Output | Should -BeLike '*-Extra Files:*C:\OSDBuilder\Content\ExtraFiles\Zeta*'
        $Output | Should -BeLike '*-Features On Demand:*C:\OSDBuilder\Content\FOD\Language.Basic.cab*'
        $Output | Should -BeLike '*-Windows Capabilities:*Language.Basic~~~de-DE~0.0.1.0*'
        $Output | Should -BeLike '*-Packages:*C:\OSDBuilder\Content\Packages\Package.cab*'
        $Output | Should -BeLike '*-Scripts:*C:\OSDBuilder\Content\Scripts\Cleanup.ps1*'
        $Output | Should -BeLike '*-WinPE Drivers:*C:\OSDBuilder\Content\WinPE\Drivers\Intel*'
        $Output | Should -BeLike '*-WinPE ADK Packages:*ADK\WinPE-PowerShell.cab*'
        $Output | Should -BeLike '*-WinRE ADK Packages:*ADK\WinPE-WMI.cab*'
        $Output | Should -BeLike '*-WinSE ADK Packages:*ADK\WinPE-Setup.cab*'
        $Output | Should -BeLike '*-WinPE Extra Files:*WinPE\ExtraFiles\PE*'
        $Output | Should -BeLike '*-WinRE Extra Files:*WinPE\ExtraFiles\RE*'
        $Output | Should -BeLike '*-WinSE Extra Files:*WinPE\ExtraFiles\SE*'
        $Output | Should -BeLike '*-WinPE Scripts:*WinPE\Scripts\PE.ps1*'
        $Output | Should -BeLike '*-WinRE Scripts:*WinPE\Scripts\RE.ps1*'
        $Output | Should -BeLike '*-WinSE Scripts:*WinPE\Scripts\SE.ps1*'
        $Output | Should -BeLike '*-SetAllIntl (Language):*de-DE*'
        $Output | Should -BeLike '*-SetInputLocale (Language):*0407:00000407*'
        $Output | Should -BeLike '*-SetSKUIntlDefaults (Language):*de-DE*'
        $Output | Should -BeLike '*-SetSetupUILang (Language):*de-DE*'
        $Output | Should -BeLike '*-SetSysLocale (Language):*de-DE*'
        $Output | Should -BeLike '*-SetUILang (Language):*de-DE*'
        $Output | Should -BeLike '*-SetUILangFallback (Language):*en-US*'
        $Output | Should -BeLike '*-SetUserLocale (Language):*de-AT*'
        $Output | Should -BeLike '*-Language Features:*Language.Speech~~~de-DE~0.0.1.0*'
        $Output | Should -BeLike '*-Language Interface Packs:*LIP\de-AT.cab*'
        $Output | Should -BeLike '*-Language Packs:*LanguagePacks\de-DE.cab*'
        $Output | Should -BeLike '*-Local Experience Packs:*LanguageExperiencePack.de-DE.Neutral.appx*'
        $Output | Should -BeLike '*-Language Sources Copy:*de-DE*'
    }

    It 'writes the combined task to OSBuild.json of the OSMedia of the task' {
        Show-TaskInfo 6>$null
        $Task = Get-Content -Path (Join-Path $OSMediaDirectory 'OSBuild.json') -Raw | ConvertFrom-Json
        $Task.TaskType | Should -Be 'OSBuild'
        $Task.TaskName | Should -Be 'Win11 Enterprise de-DE'
        $Task.TaskVersion | Should -Be '26.10.14.1'
        $Task.CustomName | Should -Be 'Win11 Custom'
        $Task.OSMFamily | Should -Be 'Client Enterprise x64 26200 en-US'
        $Task.OSMGuid | Should -Be $script:OSMediaGuid
        $Task.Name | Should -Be 'Windows 11 Enterprise x64 25H2 6899'
        $Task.ReleaseId | Should -Be '25H2'
        $Task.Languages | Should -Be @('en-US', 'de-DE')
        $Task.EnableNetFX3 | Should -Be 'True'
        $Task.WinPEOSDCloud | Should -Be 'True'
        $Task.ContentPacks | Should -Be @('_Global', 'Win11 x64 25H2')
        $Task.ExtraFiles | Should -Be @('ExtraFiles\Alpha', 'ExtraFiles\Zeta')
        $Task.RemoveAppxProvisionedPackage | Should -Be 'Microsoft.BingNews'
        $Task.AddWindowsCapability | Should -Be 'Language.Basic~~~de-DE~0.0.1.0'
        $Task.WinPEADKPE | Should -Be @('ADK\WinPE-PowerShell.cab', 'ADK\WinPE-WMI.cab')
        $Task.LangSetUserLocale | Should -Be 'de-AT'
        $Task.LocalExperiencePacks | Should -Be 'LXP\de-DE\LanguageExperiencePack.de-DE.Neutral.appx'
        Should -Invoke Get-OSMedia -Times 1 -Exactly -ParameterFilter {$Revision -eq 'OK'}
        Test-Path -Path (Join-Path (Join-Path $TestDrive 'Other') 'OSBuild.json') | Should -BeFalse
    }

    It 'shows only the task name and OSMedia for an empty task' {
        $CustomName = $null; $ContentPacks = $null; $EnableNetFX3 = $false; $WinPEAutoExtraFiles = $false; $WinPEOSDCloud = $false; $WinREWiFi = $false
        $DisableFeature = $null; $EnableFeature = $null; $RemoveAppx = $null; $RemoveCapability = $null; $RemovePackage = $null
        $StartLayoutXML = $null; $UnattendXML = $null; $WinPEDaRT = $null; $Drivers = $null; $ExtraFiles = $null; $FeaturesOnDemand = $null
        $AddWindowsCapability = $null; $Packages = $null; $Scripts = $null; $WinPEDrivers = $null; $WinPEADKPE = $null; $WinPEADKRE = $null; $WinPEADKSE = $null
        $WinPEExtraFilesPE = $null; $WinPEExtraFilesRE = $null; $WinPEExtraFilesSE = $null; $WinPEScriptsPE = $null; $WinPEScriptsRE = $null; $WinPEScriptsSE = $null
        $SetAllIntl = $null; $SetInputLocale = $null; $SetSKUIntlDefaults = $null; $SetSetupUILang = $null
        $SetSysLocale = $null; $SetUILang = $null; $SetUILangFallback = $null; $SetUserLocale = $null
        $LanguageFeatures = $null; $LanguageInterfacePacks = $null; $LanguagePacks = $null; $LocalExperiencePacks = $null; $LanguageCopySources = $null
        Mock Get-IsContentPacksEnabled {$false}
        $Output = @(Show-TaskInfo 6>&1)
        $Output.Count | Should -Be 7
        ($Output -join "`n") | Should -BeLike '*-OSMedia Path:*Windows 11 Enterprise x64 25H2 6899'
        $Task = Get-Content -Path (Join-Path $OSMediaDirectory 'OSBuild.json') -Raw | ConvertFrom-Json
        $Task.EnableNetFX3 | Should -Be 'False'
        @($Task.ExtraFiles).Count | Should -Be 0
    }

    It 'does not show the ContentPacks with -SkipContentPacks' {
        $SkipContentPacks = [switch]$true
        (Show-TaskInfo 6>&1) -join "`n" | Should -Not -BeLike '*-ContentPacks:*'
    }
}

Describe 'Show-WorkingInfoOS' {
    It 'shows the working paths' {
        $WorkingName = 'build2026101410'; $WorkingPath = 'C:\OSDBuilder\OSBuilds\build2026101410'
        $OS = "$WorkingPath\OS"; $WinPE = "$WorkingPath\WinPE"; $Info = "$WorkingPath\info"
        $Output = (Show-WorkingInfoOS 6>&1) -join "`n"
        $Output | Should -BeLike '*Working Information*'
        $Output | Should -BeLike "*-WorkingName:*$WorkingName*"
        $Output | Should -BeLike "*-OS:*$WorkingPath\OS*"
        $Output | Should -BeLike "*-Logs:*$WorkingPath\info\logs*"
    }
}
