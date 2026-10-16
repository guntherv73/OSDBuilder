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
