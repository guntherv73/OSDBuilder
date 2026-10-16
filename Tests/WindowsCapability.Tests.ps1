BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript -Name 'ReleaseSupport','WindowsCapability')) {. $Script}
}

Describe 'ConvertTo-OSDBuilderLanguageTag' {
    It '<Tag> -> <Expected>' -ForEach @(
        @{Tag = 'de-de'; Expected = 'de-DE'}
        @{Tag = 'sr-latn-rs'; Expected = 'sr-Latn-RS'}
        @{Tag = 'chr-cher-us'; Expected = 'chr-Cher-US'}
        @{Tag = 'es-419'; Expected = 'es-419'}
        @{Tag = 'ca-es-valencia'; Expected = 'ca-ES-valencia'}
    ) {
        ConvertTo-OSDBuilderLanguageTag -Tag $Tag | Should -BeExactly $Expected
    }
}

Describe 'Get-OSDBuilderLanguageCapabilityName' {
    It '<Name> -> <Expected>' -ForEach @(
        @{Name = 'Microsoft-Windows-LanguageFeatures-Basic-fr-fr-Package~31bf3856ad364e35~amd64~~.cab'; Expected = 'Language.Basic~~~fr-FR~0.0.1.0'}
        @{Name = 'Microsoft-Windows-LanguageFeatures-TextToSpeech-de-de-Package~31bf3856ad364e35~amd64~~.cab'; Expected = 'Language.TextToSpeech~~~de-DE~0.0.1.0'}
        @{Name = 'Microsoft-Windows-LanguageFeatures-Fonts-Thai-Package~31bf3856ad364e35~amd64~~.cab'; Expected = 'Language.Fonts.Thai~~~und-THAI~0.0.1.0'}
        @{Name = 'C:\IsoExtract\LanguagesAndOptionalFeatures\Microsoft-Windows-LanguageFeatures-OCR-sr-latn-rs-Package~31bf3856ad364e35~amd64~~.cab'; Expected = 'Language.OCR~~~sr-Latn-RS~0.0.1.0'}
        @{Name = 'Microsoft-Windows-RetailDemo-OfflineContent-Content-fr-fr-Package~31bf3856ad364e35~amd64~~.cab'; Expected = 'Language.RetailDemo~~~fr-FR~0.0.1.0'}
    ) {
        Get-OSDBuilderLanguageCapabilityName -Name $Name | Should -BeExactly $Expected
    }

    It 'returns $null for a Language Pack' {
        Get-OSDBuilderLanguageCapabilityName -Name 'Microsoft-Windows-Client-Language-Pack_x64_de-de.cab' | Should -BeNullOrEmpty
    }
}

Describe 'Get-OSDBuilderCapabilitySource' {
    BeforeAll {
        $GetOSDBuilderPathContentIsoExtract = Join-Path $TestDrive 'IsoExtract'
        foreach ($Directory in @(
            'Windows 11 24H2-26H2 x64 Languages and Optional Features\LanguagesAndOptionalFeatures\metadata'
            'Windows 11 22H2-23H2 x64 Languages and Optional Features\LanguagesAndOptionalFeatures\metadata'
            'Windows 10 2004 FOD\metadata'
            'Windows Server 2025 24H2 FOD\metadata'
        )) {
            New-Item -Path (Join-Path $GetOSDBuilderPathContentIsoExtract ($Directory -replace '\\', [System.IO.Path]::DirectorySeparatorChar)) -ItemType Directory -Force | Out-Null
        }
    }

    It 'returns the 26100 repository for Windows 11 25H2' {
        $Result = @(Get-OSDBuilderCapabilitySource -OSMedia ([PSCustomObject]@{OperatingSystem = 'Windows 11'; ReleaseId = '25H2'; InstallationType = 'Client'}))
        $Result.Count | Should -Be 1
        $Result[0] | Should -BeLike '*Windows 11 24H2-26H2*LanguagesAndOptionalFeatures'
    }

    It 'returns the 22621 repository for Windows 11 23H2' {
        $Result = @(Get-OSDBuilderCapabilitySource -OSMedia ([PSCustomObject]@{OperatingSystem = 'Windows 11'; ReleaseId = '23H2'; InstallationType = 'Client'}))
        $Result.Count | Should -Be 1
        $Result[0] | Should -BeLike '*Windows 11 22H2-23H2*'
    }

    It 'returns only Windows Server repositories for Windows Server' {
        $Result = @(Get-OSDBuilderCapabilitySource -OSMedia ([PSCustomObject]@{OperatingSystem = 'Windows Server'; ReleaseId = '24H2'; InstallationType = 'Server'}))
        $Result.Count | Should -Be 1
        $Result[0] | Should -BeLike '*Windows Server 2025*'
    }

    It 'returns nothing when IsoExtract does not exist' {
        $GetOSDBuilderPathContentIsoExtract = Join-Path $TestDrive 'Missing'
        Get-OSDBuilderCapabilitySource -OSMedia ([PSCustomObject]@{OperatingSystem = 'Windows 11'; ReleaseId = '25H2'; InstallationType = 'Client'}) | Should -BeNullOrEmpty
    }
}

Describe 'Add-OSDBuilderWindowsCapability' {
    BeforeAll {
        $Repository = Join-Path $TestDrive 'Repository'
        New-Item -Path $Repository -ItemType Directory -Force | Out-Null
    }

    It 'adds the capability from the local repository with LimitAccess' {
        Mock Add-WindowsCapability {}
        Add-OSDBuilderWindowsCapability -Path 'C:\Mount' -Name 'Language.Basic~~~de-DE~0.0.1.0' -Source $Repository | Should -BeTrue
        Should -Invoke Add-WindowsCapability -Times 1 -Exactly -ParameterFilter {
            ($Name -eq 'Language.Basic~~~de-DE~0.0.1.0') -and ($Source -contains $Repository) -and $LimitAccess
        }
    }

    It 'returns $false when Add-WindowsCapability fails' {
        Mock Add-WindowsCapability {throw 'Add-WindowsCapability failed. Error code = 0x800f081f'}
        Add-OSDBuilderWindowsCapability -Path 'C:\Mount' -Name 'Language.OCR~~~de-DE~0.0.1.0' -Source $Repository 4>$null | Should -BeFalse
    }

    It 'writes <Expected> when Add-WindowsCapability fails with <Message>' -ForEach @(
        @{Message = 'Add-WindowsCapability failed. Error code = 0x800f081f'; Expected = '*0x800f081f The source files could not be found for Language.OCR~~~de-DE~0.0.1.0*'}
        @{Message = 'Add-WindowsCapability failed. Error code = 0x800f081e'; Expected = '*0x800f081e Language.OCR~~~de-DE~0.0.1.0 is not applicable to this image*'}
        @{Message = 'Access is denied'; Expected = '*OSDBuilder: Access is denied*'}
    ) {
        Mock Add-WindowsCapability {throw $Message}
        $LogPath = Join-Path $TestDrive 'capability.log'
        $Output = @(Add-OSDBuilderWindowsCapability -Path 'C:\Mount' -Name 'Language.OCR~~~de-DE~0.0.1.0' -Source $Repository -LogPath $LogPath 4>&1)
        $Output[-1] | Should -BeFalse
        ($Output -join "`n") | Should -BeLike $Expected
        ($Output -join "`n") | Should -BeLike "*$LogPath*"
        Should -Invoke Add-WindowsCapability -Times 1 -Exactly -ParameterFilter {$LogPath -eq (Join-Path $TestDrive 'capability.log')}
    }

    It 'does not write the log path without -LogPath' {
        Mock Add-WindowsCapability {throw 'Access is denied'}
        $Output = @(Add-OSDBuilderWindowsCapability -Path 'C:\Mount' -Name 'NetFX3~~~~' -Source $Repository 4>&1)
        $Output.Count | Should -Be 2
        Should -Invoke Add-WindowsCapability -Times 1 -Exactly -ParameterFilter {-not $LogPath}
    }

    It 'does not use LimitAccess when Add-WindowsCapability does not support it' {
        Mock Get-Command {[PSCustomObject]@{Parameters = @{Path = $null; Name = $null; Source = $null}}} -ParameterFilter {$Name -eq 'Add-WindowsCapability'}
        Mock Add-WindowsCapability {}
        Add-OSDBuilderWindowsCapability -Path 'C:\Mount' -Name 'NetFX3~~~~' -Source $Repository, $Repository, '' | Should -BeTrue
        Should -Invoke Add-WindowsCapability -Times 1 -Exactly -ParameterFilter {(-not $LimitAccess) -and (@($Source).Count -eq 1)}
    }

    It 'warns without a repository' {
        Mock Add-WindowsCapability {}
        $Warnings = (Add-OSDBuilderWindowsCapability -Path 'C:\Mount' -Name 'NetFX3~~~~' 3>&1) -join "`n"
        $Warnings | Should -BeLike '*No Features on Demand repository for NetFX3~~~~*'
    }

    It 'returns $false without a repository and does not call DISM' {
        Mock Add-WindowsCapability {}
        Add-OSDBuilderWindowsCapability -Path 'C:\Mount' -Name 'NetFX3~~~~' -Source (Join-Path $TestDrive 'Missing') 3>$null | Should -BeFalse
        Should -Invoke Add-WindowsCapability -Times 0 -Exactly
    }
}
