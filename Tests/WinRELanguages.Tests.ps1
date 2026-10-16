BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript -Name 'ReleaseSupport','WinRELanguages')) {. $Script}

    #Directory layout and lowercase file names of the Languages and Optional Features ISO
    function New-WinPEOCs ($Root) {
        $OCs = Join-Path (Join-Path (Join-Path $Root 'Windows Preinstallation Environment') 'x64') 'WinPE_OCs'
        foreach ($File in @(
            'winpe-fontsupport-ja-jp.cab'
            'winpe-wifi.cab'
            'de-de\lp.cab'
            'de-de\winpe-wmi_de-de.cab'
            'de-de\winpe-wifi_de-de.cab'
            'de-de\winpe-setup_de-de.cab'
            'ja-jp\lp.cab'
            'ja-jp\winpe-wmi_ja-jp.cab'
            'th-th\lp.cab'
        )) {
            New-TestFile -Path (Join-Path $OCs ($File -replace '\\', [System.IO.Path]::DirectorySeparatorChar)) | Out-Null
        }
        $OCs
    }
}

Describe 'Get-OSDBuilderLanguageFromPackage' {
    It '<Name> -> <Expected>' -ForEach @(
        @{Name = 'IsoExtract\LanguagesAndOptionalFeatures\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab'; Expected = 'de-de'}
        @{Name = 'Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab'; Expected = 'ca-es'}
        @{Name = 'Microsoft-Windows-Server-Language-Pack_x64_sr-latn-rs.cab'; Expected = 'sr-latn-rs'}
        @{Name = 'Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab'; Expected = $null}
    ) {
        Get-OSDBuilderLanguageFromPackage -Name $Name | Should -Be $Expected
    }
}

Describe 'Get-OSDBuilderWinPELanguageSource' {
    BeforeAll {
        $GetOSDBuilderPathContentIsoExtract = Join-Path $TestDrive 'IsoExtract'
        New-WinPEOCs (Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows 11 24H2-26H2 x64 Languages and Optional Features') | Out-Null
        New-WinPEOCs (Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows 11 22H2-23H2 x64 Languages and Optional Features') | Out-Null
    }

    It 'returns the WinPE_OCs of the matching Languages and Optional Features ISO' {
        $Result = @(Get-OSDBuilderWinPELanguageSource -OSMedia ([PSCustomObject]@{OperatingSystem = 'Windows 11'; ReleaseId = '25H2'}))
        $Result.Count | Should -Be 1
        $Result[0] | Should -BeLike '*24H2-26H2*WinPE_OCs'
    }
}

Describe 'Add-OSDBuilderWinPELanguagePacks' {
    BeforeAll {
        $Source = New-WinPEOCs (Join-Path $TestDrive 'LOF')
        $PEInfo = $TestDrive
    }

    BeforeEach {
        $script:Added = [System.Collections.Generic.List[string]]::new()
        Mock Add-WindowsPackage {$script:Added.Add((Split-Path $PackagePath -Leaf).ToLower())}
        Mock Get-WindowsPackage {
            [PSCustomObject]@{PackageName = 'WinPE-WMI-Package~31bf3856ad364e35~amd64~~10.0.26100.1'}
            [PSCustomObject]@{PackageName = 'WinPE-WiFi-Package~31bf3856ad364e35~amd64~~10.0.26100.1'}
        }
    }

    It 'adds lp.cab first, then the language pack of each optional component' {
        Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'de-DE' -Sources $Source -ImageName 'WinRE' 6>$null
        $script:Added -join ',' | Should -Be 'lp.cab,winpe-wmi_de-de.cab'
    }

    It 'does not add the WinPE-WiFi language pack' {
        Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'de-DE' -Sources $Source -ImageName 'WinRE' 6>$null
        $script:Added | Should -Not -Contain 'winpe-wifi_de-de.cab'
    }

    It 'adds the font support for Japanese' {
        Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'ja-JP' -Sources $Source -ImageName 'WinRE' 6>$null
        $script:Added -join ',' | Should -Be 'lp.cab,winpe-wmi_ja-jp.cab,winpe-fontsupport-ja-jp.cab'
    }

    It 'adds the required Setup optional component for WinSE' {
        Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'de-DE' -Sources $Source -ImageName 'WinSE' -RequiredOptionalComponents 'WinPE-Setup' 6>$null
        $script:Added | Should -Contain 'winpe-setup_de-de.cab'
    }

    It 'warns when the Thai font support is missing for Windows Setup' {
        $Warnings = (Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'th-TH' -Sources $Source -ImageName 'WinSE' -ThaiFontSupport 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*WinPE-FontSupport-WinRE.cab for th-TH was not found*'
        $script:Added | Should -Contain 'lp.cab'
    }

    It 'installs nothing when the language is already in the image' {
        Mock Get-WindowsPackage {
            [PSCustomObject]@{PackageName = 'Microsoft-Windows-WinPE-LanguagePack-Package~31bf3856ad364e35~amd64~de-DE~10.0.26100.1'}
            [PSCustomObject]@{PackageName = 'WinPE-WMI-Package~31bf3856ad364e35~amd64~~10.0.26100.1'}
            [PSCustomObject]@{PackageName = 'WinPE-WMI-Package~31bf3856ad364e35~amd64~de-DE~10.0.26100.1'}
        }
        Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'de-DE' -Sources $Source -ImageName 'WinRE' 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'warns when a language is not available' {
        $Warnings = (Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'xx-XX' -Sources $Source -ImageName 'WinRE' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*xx-xx is not available*'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }
}

Describe 'Add-OSDBuilderWinPELanguagePacks edge cases' {
    BeforeAll {
        $Source = New-WinPEOCs (Join-Path $TestDrive 'LOFEdge')
        New-TestFile -Path (Join-Path $Source 'winpe-fontsupport-winre.cab') | Out-Null
        $PEInfo = $TestDrive
    }

    BeforeEach {
        $script:Added = [System.Collections.Generic.List[string]]::new()
        Mock Add-WindowsPackage {$script:Added.Add((Split-Path $PackagePath -Leaf).ToLower())}
        Mock Get-WindowsPackage {}
    }

    It 'adds WinPE-FontSupport-WinRE for Thai when it is in the source' {
        Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'th-TH' -Sources $Source -ImageName 'WinSE' -ThaiFontSupport 6>$null
        $script:Added -join ',' | Should -Be 'lp.cab,winpe-fontsupport-winre.cab'
    }

    It 'does not add WinPE-FontSupport-WinRE without -ThaiFontSupport' {
        Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'th-TH' -Sources $Source -ImageName 'WinRE' 6>$null
        $script:Added -join ',' | Should -Be 'lp.cab'
    }

    It 'warns when the language pack of a required optional component is missing' {
        $Warnings = (Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'ja-JP' -Sources $Source -ImageName 'WinSE' -RequiredOptionalComponents 'WinPE-Setup' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*WinSE: WinPE-Setup_ja-jp.cab was not found in*'
        $script:Added | Should -Not -Contain 'winpe-setup_ja-jp.cab'
    }

    It 'only adds the missing optional component language pack when the base language is installed' {
        Mock Get-WindowsPackage {
            [PSCustomObject]@{PackageName = 'WinPE-LanguagePack-Package~31bf3856ad364e35~amd64~de-DE~10.0.26100.1'}
            [PSCustomObject]@{PackageName = 'WinPE-WMI-Package~31bf3856ad364e35~amd64~~10.0.26100.1'}
        }
        Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'de-DE' -Sources $Source -ImageName 'WinRE' 6>$null
        $script:Added -join ',' | Should -Be 'winpe-wmi_de-de.cab'
    }

    It 'does not add the font support twice' {
        Mock Get-WindowsPackage {
            [PSCustomObject]@{PackageName = 'WinPE-FontSupport-JA-JP-Package~31bf3856ad364e35~amd64~~10.0.26100.1'}
        }
        Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'ja-JP' -Sources $Source -ImageName 'WinRE' 6>$null
        $script:Added -join ',' | Should -Be 'lp.cab'
    }

    It 'uses the first source that contains the language and font support of all sources' {
        $Second = New-WinPEOCs (Join-Path $TestDrive 'ADKEdge')
        New-TestFile -Path (Join-Path (Join-Path $Second 'fr-fr') 'lp.cab') | Out-Null
        Mock Add-WindowsPackage {$script:Added.Add($PackagePath)}
        Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'fr-FR', 'FR-fr' -Sources (Join-Path $TestDrive 'Missing'), $Second -ImageName 'WinRE' 6>$null
        $script:Added.Count | Should -Be 1
        $script:Added[0] | Should -Be (Join-Path (Join-Path $Second 'fr-fr') 'lp.cab')
    }

    It 'continues with the next package and reports the log when Add-WindowsPackage fails with <Message>' -ForEach @(
        @{Message = 'Error 0x800f081e'; Expected = '*0x800f081e The package is not applicable*'}
        @{Message = 'Access denied'; Expected = '*Review the log for more information*'}
    ) {
        Mock Get-WindowsPackage {[PSCustomObject]@{PackageName = 'WinPE-WMI-Package~31bf3856ad364e35~amd64~~10.0.26100.1'}}
        Mock Add-WindowsPackage {$script:Added.Add((Split-Path $PackagePath -Leaf).ToLower()); throw $Message}
        $Verbose = (Add-OSDBuilderWinPELanguagePacks -MountPath 'C:\Mount' -Languages 'de-DE' -Sources $Source -ImageName 'WinRE' 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike $Expected
        $Verbose | Should -BeLike '*Add-LanguagePacksWinRE-de-de.log*'
        $script:Added -join ',' | Should -Be 'lp.cab,winpe-wmi_de-de.cab'
    }
}

Describe 'Get-OSDBuilderWinPELanguageSource' {
    It 'returns nothing when Content\IsoExtract is not set' {
        $GetOSDBuilderPathContentIsoExtract = $null
        Get-OSDBuilderWinPELanguageSource -OSMedia ([PSCustomObject]@{OperatingSystem = 'Windows 11'; ReleaseId = '24H2'}) | Should -BeNullOrEmpty
    }

    It 'returns nothing when Content\IsoExtract does not exist' {
        $GetOSDBuilderPathContentIsoExtract = Join-Path $TestDrive 'MissingIsoExtract'
        Get-OSDBuilderWinPELanguageSource -OSMedia ([PSCustomObject]@{OperatingSystem = 'Windows 11'; ReleaseId = '24H2'}) | Should -BeNullOrEmpty
    }

    It 'returns the WinPE_OCs of the architecture and not of Windows 10' {
        $GetOSDBuilderPathContentIsoExtract = Join-Path $TestDrive 'IsoExtractArch'
        New-WinPEOCs (Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows 11 24H2 Languages') | Out-Null
        New-WinPEOCs (Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows 10 24H2 Languages') | Out-Null
        $Arm64 = Join-Path (Join-Path (Join-Path (Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows 11 24H2 Languages') 'Windows Preinstallation Environment') 'arm64') 'WinPE_OCs'
        New-Item -Path $Arm64 -ItemType Directory -Force | Out-Null
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 11'; ReleaseId = '24H2'}
        @(Get-OSDBuilderWinPELanguageSource -OSMedia $OSMedia) | Should -HaveCount 1
        @(Get-OSDBuilderWinPELanguageSource -OSMedia $OSMedia)[0] | Should -BeLike '*Windows 11 24H2*x64*WinPE_OCs'
        @(Get-OSDBuilderWinPELanguageSource -OSMedia $OSMedia -Architecture 'arm64') | Should -Be @($Arm64)
    }
}

Describe 'Get-OSDBuilderContentPackLanguages' {
    BeforeAll {
        if (-not (Get-Command -Name Get-IsTemplatesEnabled -ErrorAction SilentlyContinue)) {function Get-IsTemplatesEnabled {}}
        $SetOSDBuilderPathContentPacks = Join-Path $TestDrive 'ContentPacks'
        $UpdateOS = 'Windows 11'
        $OSArchitecture = 'x64'
        $ReleaseID = '24H2'
        $Release = Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContentPacks 'MultiLang') 'OSLanguagePacks') 'Windows 11 24H2 x64'
        New-TestFile -Path (Join-Path $Release 'Microsoft-Windows-Client-Language-Pack_x64_de-de.cab') | Out-Null
        New-TestFile -Path (Join-Path $Release 'Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab') | Out-Null
        New-TestFile -Path (Join-Path $Release 'Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab') | Out-Null
        New-TestFile -Path (Join-Path $Release 'Microsoft-Windows-Client-Language-Pack_x64_fr-fr.txt') | Out-Null
        $Other = Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContentPacks 'French') 'OSLanguagePacks') 'Windows 11 24H2 x64'
        New-TestFile -Path (Join-Path $Other 'Microsoft-Windows-Client-Language-Pack_x64_fr-fr.cab') | Out-Null
    }

    BeforeEach {
        Mock Get-IsTemplatesEnabled {$false}
        $SkipContentPacks = $false
    }

    It 'returns the languages of the Language Packs in the OSLanguagePacks of all ContentPacks' {
        $ContentPacks = @('MultiLang', 'French', 'Missing')
        $Result = @(Get-OSDBuilderContentPackLanguages 6>$null)
        ($Result | Sort-Object) -join ',' | Should -Be 'ca-es,de-de,fr-fr'
    }

    It 'uses the compatible release of the ContentPack for Windows 11 25H2' {
        $ReleaseID = '25H2'
        $ContentPacks = @('French')
        Get-OSDBuilderContentPackLanguages 6>$null | Should -Be 'fr-fr'
    }

    It 'returns nothing when templates are enabled' {
        Mock Get-IsTemplatesEnabled {$true}
        $ContentPacks = @('MultiLang')
        Get-OSDBuilderContentPackLanguages | Should -BeNullOrEmpty
    }

    It 'returns nothing with SkipContentPacks' {
        $SkipContentPacks = $true
        $ContentPacks = @('MultiLang')
        Get-OSDBuilderContentPackLanguages | Should -BeNullOrEmpty
    }

    It 'returns nothing without ContentPacks' {
        $ContentPacks = @()
        Get-OSDBuilderContentPackLanguages | Should -BeNullOrEmpty
    }
}

Describe 'Add-LanguagePacksWinRE' {
    BeforeAll {
        if (-not (Get-Command -Name Get-IsTemplatesEnabled -ErrorAction SilentlyContinue)) {function Get-IsTemplatesEnabled {}}
        $PEInfo = $TestDrive
        $GetOSDBuilderPathContentIsoExtract = Join-Path $TestDrive 'IsoExtractWinRE'
        $WinRESource = Join-Path (Join-Path (Join-Path (Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows 11 24H2-26H2 x64 Languages and Optional Features') 'Windows Preinstallation Environment') 'x64') 'WinPE_OCs'
        $MountWinRERoot = Join-Path $TestDrive 'MountWinRE'
        New-Item -Path (Join-Path $MountWinRERoot 'Windows') -ItemType Directory -Force | Out-Null
    }

    BeforeEach {
        $ScriptName = 'New-OSBuild'
        $OSMajorVersion = 10
        $UpdateOS = 'Windows 11'
        $ReleaseId = '25H2'
        $OSArchitecture = 'x64'
        $OSInstallationType = 'Client'
        $MountWinRE = $MountWinRERoot
        $LanguagePacks = @('IsoExtract\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab')
        $LanguageInterfacePacks = @('IsoExtract\Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab')
        $SetAllIntl = $null
        Mock Get-OSDBuilderContentPackLanguages {'fr-fr'}
        Mock Get-OSDBuilderWinPELanguageSource {$WinRESource, 'second'}
        Mock Get-WindowsPackage {
            [PSCustomObject]@{PackageName = 'WinPE-LanguagePack-Package~31bf3856ad364e35~amd64~en-US~10.0.26100.1'}
            [PSCustomObject]@{PackageName = 'WinPE-WMI-Package~31bf3856ad364e35~amd64~~10.0.26100.1'}
        }
        Mock Add-OSDBuilderWinPELanguagePacks {}
        Mock Show-ActionTime {}
        Mock dism {}
    }

    It 'adds the Task, ContentPack and WinRE languages from the first source' {
        Add-LanguagePacksWinRE 6>$null
        Should -Invoke Add-OSDBuilderWinPELanguagePacks -Times 1 -Exactly -ParameterFilter {
            ($Languages -join ',') -eq 'ca-es,de-de,en-us,fr-fr' -and ($Sources -join ',') -eq $WinRESource -and
            $ImageName -eq 'WinRE' -and $MountPath -eq $MountWinRERoot
        }
        Should -Invoke Get-OSDBuilderWinPELanguageSource -Times 1 -Exactly -ParameterFilter {
            $OSMedia.OperatingSystem -eq 'Windows 11' -and $OSMedia.ReleaseId -eq '25H2' -and $OSMedia.InstallationType -eq 'Client' -and $Architecture -eq 'x64'
        }
        Should -Invoke dism -Times 0 -Exactly
    }

    It 'sets the default language of WinRE when SetAllIntl is a Task language' {
        $SetAllIntl = 'de-DE'
        Add-LanguagePacksWinRE 6>$null
        Should -Invoke dism -Times 1 -Exactly -ParameterFilter {
            $script:DismArgs = $RemainingArguments -join ' '; $true
        }
    }

    It 'does not set the default language when SetAllIntl is not a Task language' {
        $SetAllIntl = 'en-US'
        Add-LanguagePacksWinRE 6>$null
        Should -Invoke dism -Times 0 -Exactly
    }

    It 'adds the optional component language packs of the WinRE languages without Task languages' {
        $LanguagePacks = @()
        $LanguageInterfacePacks = @()
        Mock Get-OSDBuilderContentPackLanguages {}
        Add-LanguagePacksWinRE 6>$null
        Should -Invoke Add-OSDBuilderWinPELanguagePacks -Times 1 -Exactly -ParameterFilter {($Languages -join ',') -eq 'en-us'}
    }

    It 'does nothing without languages' {
        $LanguagePacks = @()
        $LanguageInterfacePacks = @()
        Mock Get-OSDBuilderContentPackLanguages {}
        Mock Get-WindowsPackage {}
        Add-LanguagePacksWinRE 6>$null
        Should -Invoke Add-OSDBuilderWinPELanguagePacks -Times 0 -Exactly
    }

    It 'warns when no Languages and Optional Features ISO was found' {
        Mock Get-OSDBuilderWinPELanguageSource {}
        $Warnings = (Add-LanguagePacksWinRE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinRE: No Languages and Optional Features ISO for Windows 11 25H2 was found in $GetOSDBuilderPathContentIsoExtract*"
        $Warnings | Should -BeLike '*WinRE: ca-es, de-de, fr-fr will not be available*'
        $Warnings | Should -BeLike '*Save-OSDBuilderDownload -ContentDownload*'
        Should -Invoke Add-OSDBuilderWinPELanguagePacks -Times 0 -Exactly
    }

    It 'does not warn without a source when there are no Task languages' {
        Mock Get-OSDBuilderWinPELanguageSource {}
        $LanguagePacks = @()
        $LanguageInterfacePacks = @()
        Mock Get-OSDBuilderContentPackLanguages {}
        (Add-LanguagePacksWinRE 6>$null 3>&1) | Should -BeNullOrEmpty
        Should -Invoke Show-ActionTime -Times 0 -Exactly
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'the script is not New-OSBuild'; Variable = 'ScriptName'; Value = 'New-OSMedia'}
        @{Case = 'the OS is not Windows 10 or 11'; Variable = 'OSMajorVersion'; Value = 6}
        @{Case = 'the OS is Windows 10'; Variable = 'UpdateOS'; Value = 'Windows 10'}
        @{Case = 'WinRE is not mounted'; Variable = 'MountWinRE'; Value = $null}
        @{Case = 'the WinRE mount has no Windows directory'; Variable = 'MountWinRE'; Value = 'TestDrive:\NoWinRE'}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Add-LanguagePacksWinRE 6>$null 3>$null
        Should -Invoke Get-OSDBuilderWinPELanguageSource -Times 0 -Exactly
        Should -Invoke Add-OSDBuilderWinPELanguagePacks -Times 0 -Exactly
    }
}

Describe 'Get-OSDBuilderADKWinPELanguageSource' {
    BeforeAll {
        $ADK = Join-Path $TestDrive 'ADK'
        $Win11 = Join-Path $ADK 'Windows 11 24H2'
        foreach ($Arch in 'amd64', 'x86', 'arm64') {
            New-Item -Path (Join-Path (Join-Path $Win11 $Arch) 'WinPE_OCs') -ItemType Directory -Force | Out-Null
        }
        New-Item -Path (Join-Path (Join-Path (Join-Path $ADK 'Windows 10 24H2') 'amd64') 'WinPE_OCs') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path (Join-Path (Join-Path $ADK 'Windows 11 22H2') 'amd64') 'WinPE_OCs') -ItemType Directory -Force | Out-Null
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 11'; ReleaseId = '25H2'}
    }

    It 'returns the amd64 WinPE_OCs of a compatible release for x64' {
        $GetOSDBuilderPathContentADK = $ADK
        $Result = @(Get-OSDBuilderADKWinPELanguageSource -OSMedia $OSMedia)
        $Result | Should -Be @(Join-Path (Join-Path $Win11 'amd64') 'WinPE_OCs')
    }

    It 'returns the WinPE_OCs of <Architecture>' -ForEach @(@{Architecture = 'arm64'}, @{Architecture = 'x86'}) {
        $GetOSDBuilderPathContentADK = $ADK
        @(Get-OSDBuilderADKWinPELanguageSource -OSMedia $OSMedia -Architecture $Architecture) | Should -Be @(Join-Path (Join-Path $Win11 $Architecture) 'WinPE_OCs')
    }

    It 'returns nothing when Content\ADK is <Case>' -ForEach @(
        @{Case = 'not set'; Value = $null}
        @{Case = 'missing'; Value = 'TestDrive:\MissingADK'}
    ) {
        $GetOSDBuilderPathContentADK = $Value
        Get-OSDBuilderADKWinPELanguageSource -OSMedia $OSMedia | Should -BeNullOrEmpty
    }
}

Describe 'Add-LanguagePacksWinSE' {
    BeforeAll {
        if (-not (Get-Command -Name Get-OSMedia -ErrorAction SilentlyContinue)) {function Get-OSMedia {param ($Revision)}}
        $MountWinSERoot = Join-Path $TestDrive 'MountWinSE'
        New-Item -Path (Join-Path $MountWinSERoot 'Windows') -ItemType Directory -Force | Out-Null
    }

    BeforeEach {
        $ScriptName = 'New-OSBuild'
        $OSMajorVersion = 10
        $UpdateOS = 'Windows 11'
        $ReleaseId = '24H2'
        $OSArchitecture = 'x64'
        $OSInstallationType = 'Client'
        $MountWinSE = $MountWinSERoot
        $LanguageCopySources = @('Windows 11 Enterprise x64 24H2 de-DE', 'Windows 11 Enterprise x64 24H2 ja-JP')
        Mock Get-OSMedia {
            [PSCustomObject]@{OSMFamily = 'Windows 11 Enterprise x64 24H2 de-DE'; Languages = @('de-DE')}
            [PSCustomObject]@{OSMFamily = 'Windows 11 Enterprise x64 24H2 ja-JP'; Languages = @('ja-JP', 'de-de')}
            [PSCustomObject]@{OSMFamily = 'Windows 11 Enterprise x64 24H2 fr-FR'; Languages = @('fr-FR')}
        }
        Mock Get-OSDBuilderWinPELanguageSource {'LOF'}
        Mock Get-OSDBuilderADKWinPELanguageSource {'ADK'}
        Mock Add-OSDBuilderWinPELanguagePacks {}
        Mock Show-ActionTime {}
    }

    It 'adds the languages of the LanguageCopySources with the Windows Setup client components' {
        Add-LanguagePacksWinSE 6>$null
        Should -Invoke Get-OSMedia -Times 1 -Exactly -ParameterFilter {$Revision -eq 'OK'}
        Should -Invoke Add-OSDBuilderWinPELanguagePacks -Times 1 -Exactly -ParameterFilter {
            ($Languages -join ',') -eq 'de-de,ja-jp' -and ($Sources -join ',') -eq 'LOF,ADK' -and $ImageName -eq 'WinSE' -and
            ($RequiredOptionalComponents -join ',') -eq 'WinPE-Setup,WinPE-Setup-Client' -and $ThaiFontSupport.IsPresent -and $MountPath -eq $MountWinSERoot
        }
        Should -Invoke Get-OSDBuilderADKWinPELanguageSource -Times 1 -Exactly -ParameterFilter {
            $OSMedia.OperatingSystem -eq 'Windows 11' -and $OSMedia.ReleaseId -eq '24H2' -and $Architecture -eq 'x64'
        }
    }

    It 'uses the Windows Setup server component for Windows Server' {
        $OSInstallationType = 'Server Core'
        Add-LanguagePacksWinSE 6>$null
        Should -Invoke Add-OSDBuilderWinPELanguagePacks -Times 1 -Exactly -ParameterFilter {
            ($RequiredOptionalComponents -join ',') -eq 'WinPE-Setup,WinPE-Setup-Server'
        }
    }

    It 'uses the ADK when there is no Languages and Optional Features ISO' {
        Mock Get-OSDBuilderWinPELanguageSource {}
        Add-LanguagePacksWinSE 6>$null
        Should -Invoke Add-OSDBuilderWinPELanguagePacks -Times 1 -Exactly -ParameterFilter {($Sources -join ',') -eq 'ADK'}
    }

    It 'warns about LanguageCopySources that are not imported' {
        $LanguageCopySources = @('Windows 11 Enterprise x64 24H2 de-DE', 'Windows 11 Enterprise x64 24H2 it-IT')
        $Warnings = (Add-LanguagePacksWinSE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*WinSE: LanguageCopySources Windows 11 Enterprise x64 24H2 it-IT was not found*'
        Should -Invoke Add-OSDBuilderWinPELanguagePacks -Times 1 -Exactly -ParameterFilter {($Languages -join ',') -eq 'de-de'}
    }

    It 'warns and adds nothing without a source' {
        Mock Get-OSDBuilderWinPELanguageSource {}
        Mock Get-OSDBuilderADKWinPELanguageSource {}
        $Warnings = (Add-LanguagePacksWinSE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*WinSE: No Languages and Optional Features ISO or ADK WinPE_OCs for Windows 11 24H2 was found*'
        $Warnings | Should -BeLike '*Save-OSDBuilderDownload -ContentDownload*'
        Should -Invoke Add-OSDBuilderWinPELanguagePacks -Times 0 -Exactly
    }

    It 'does nothing when the LanguageCopySources have no languages' {
        Mock Get-OSMedia {[PSCustomObject]@{OSMFamily = 'Windows 11 Enterprise x64 24H2 de-DE'; Languages = @()}}
        $LanguageCopySources = @('Windows 11 Enterprise x64 24H2 de-DE')
        Add-LanguagePacksWinSE 6>$null 3>$null
        Should -Invoke Get-OSDBuilderWinPELanguageSource -Times 0 -Exactly
        Should -Invoke Add-OSDBuilderWinPELanguagePacks -Times 0 -Exactly
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'the script is not New-OSBuild'; Variable = 'ScriptName'; Value = 'New-PEBuild'}
        @{Case = 'the OS is not Windows 10 or 11'; Variable = 'OSMajorVersion'; Value = 6}
        @{Case = 'there are no LanguageCopySources'; Variable = 'LanguageCopySources'; Value = $null}
        @{Case = 'WinSE is not mounted'; Variable = 'MountWinSE'; Value = $null}
        @{Case = 'the WinSE mount has no Windows directory'; Variable = 'MountWinSE'; Value = 'TestDrive:\NoWinSE'}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Add-LanguagePacksWinSE 6>$null 3>$null
        Should -Invoke Get-OSMedia -Times 0 -Exactly
        Should -Invoke Add-OSDBuilderWinPELanguagePacks -Times 0 -Exactly
    }
}
