BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    #The example requires an elevated session, the stub module does not
    $ExampleScript = Join-Path $TestDrive 'New-Win11MultiLanguageBuild.ps1'
    (Get-Content -Path (Join-Path (Join-Path $RepoRoot 'Examples') 'New-Win11MultiLanguageBuild.ps1') -Raw) -replace '(?m)^#Requires -RunAsAdministrator', '' |
        Set-Content -Path $ExampleScript
    $StubModule = Join-Path (Join-Path $FixturesPath 'StubOSDBuilder') 'OSDBuilder.psm1'

    function New-StubOSMedia ($Language, $Name = "Windows 11 Enterprise x64 25H2 26200.6899 $Language", $FullName = (Join-Path $TestDrive 'OSMedia')) {
        [PSCustomObject]@{
            Name = $Name; OperatingSystem = 'Windows 11'; ReleaseId = '25H2'; EditionId = 'Enterprise'; Arch = 'x64'
            Languages = @($Language); ModifiedTime = Get-Date; FullName = $FullName; Build = '26200'; OSMFamily = "Family $Language"
        }
    }

    function Invoke-Example {
        param ([hashtable]$Parameters = @{})
        $Defaults = @{
            CustomerName        = 'Contoso'
            OSDBuilderModule    = $StubModule
            OSDBuilderHome      = $OSDBuilderHome
            Languages           = @('en-US', 'de-DE')
        }
        foreach ($Key in $Parameters.Keys) {$Defaults[$Key] = $Parameters[$Key]}
        & $ExampleScript @Defaults 6>$null 3>$null
    }

    function Get-ExampleTask {
        Get-Content -Path (Get-ChildItem -Path (Join-Path $OSDBuilderHome 'Tasks') -Filter '*.json' | Select-Object -First 1).FullName -Raw | ConvertFrom-Json
    }
}

AfterAll {
    Remove-Module -Name OSDBuilder -Force -ErrorAction SilentlyContinue
    foreach ($Name in 'OSDBuilderStubLog','OSDBuilderStubOSMedia','OSDBuilderStubImport','SetOSDBuilderPathContent','SetOSDBuilderPathTasks','GetOSDBuilderPathContentIsoExtract') {
        Remove-Variable -Name $Name -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'New-Win11MultiLanguageBuild.ps1 parameter validation' {
    It 'requires -DefaultLanguage to be one of -Languages' {
        {& $ExampleScript -CustomerName 'Contoso' -Languages 'en-US' -DefaultLanguage 'de-DE'} | Should -Throw '*-DefaultLanguage de-DE must be one of -Languages*'
    }

    It 'rejects a Language Interface Pack as Windows Setup language' {
        {& $ExampleScript -CustomerName 'Contoso' -SetupLanguages 'ca-ES'} | Should -Throw '*LIPs are not supported by Windows Setup*'
    }

    It 'rejects an invalid -RegionalFormat' {
        {& $ExampleScript -CustomerName 'Contoso' -RegionalFormat 'not a locale!'} | Should -Throw '*is not a valid locale name*'
    }

    It 'rejects -EnableNetFX3 together with -SkipNetFX3' {
        {& $ExampleScript -CustomerName 'Contoso' -EnableNetFX3 -SkipNetFX3} | Should -Throw '*-EnableNetFX3 and -SkipNetFX3 cannot be used together*'
    }

    It 'requires a CustomerName without default' {
        $Parameter = (Get-Command $ExampleScript).Parameters['CustomerName']
        ($Parameter.Attributes | Where-Object {$_ -is [System.Management.Automation.ParameterAttribute]}).Mandatory | Should -BeTrue
    }
}

Describe 'New-Win11MultiLanguageBuild.ps1 with the stub module' {
    BeforeEach {
        $OSDBuilderHome = Join-Path $TestDrive ([guid]::NewGuid())
        $global:OSDBuilderStubLog = [System.Collections.Generic.List[string]]::new()
        $global:OSDBuilderStubOSMedia = @(New-StubOSMedia 'en-US')
        $global:OSDBuilderStubImport = @{}
        Mock Start-Sleep {}

        #Provisioned apps of the OSMedia
        $OSMediaInfo = Join-Path (Join-Path (Join-Path $TestDrive 'OSMedia') 'info') 'xml'
        New-Item -Path $OSMediaInfo -ItemType Directory -Force | Out-Null
        @(
            [PSCustomObject]@{DisplayName = 'Microsoft.BingNews'; PackageName = 'Microsoft.BingNews_4.55.1.0_neutral_~_8wekyb3d8bbwe'}
            [PSCustomObject]@{DisplayName = 'Microsoft.GamingApp'; PackageName = 'Microsoft.GamingApp_2509.1001.4.0_neutral_~_8wekyb3d8bbwe'}
        ) | Export-Clixml -Path (Join-Path $OSMediaInfo 'Get-AppxProvisionedPackage.xml')

        #Languages and Optional Features ISO with the file names of the 26100 ISO
        $Lof = Join-Path (Join-Path (Join-Path (Join-Path $OSDBuilderHome 'Content') 'IsoExtract') 'Windows 11 24H2-26H2 x64 Languages and Optional Features') 'LanguagesAndOptionalFeatures'
        foreach ($File in @(
            'Microsoft-Windows-Client-Language-Pack_x64_en-us.cab'
            'Microsoft-Windows-Client-Language-Pack_x64_de-de.cab'
            'Microsoft-Windows-Client-Language-Pack_x64_th-th.cab'
            'Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab'
            'Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-OCR-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-Speech-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-Basic-th-th-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-Fonts-Thai-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-Basic-ca-es-Package~31bf3856ad364e35~amd64~~.cab'
        )) {
            New-TestFile -Path (Join-Path $Lof $File) | Out-Null
        }
    }

    It 'downloads the content, updates the OSMedia, creates the Task and builds the image' {
        Invoke-Example -Parameters @{CreateISO = $true}
        $global:OSDBuilderStubLog | Should -Contain 'Save-OSDBuilderDownload -ContentDownload Windows 11 24H2-26H2 x64 Languages and Optional Features'
        $global:OSDBuilderStubLog | Should -Contain 'Save-OSDBuilderDownload -ContentDownload Windows 11 24H2-26H2 Inbox Apps'
        ($global:OSDBuilderStubLog -like 'Update-OSMedia -Name Windows 11 Enterprise x64 25H2*-Download:True -Execute:True').Count | Should -Be 1
        ($global:OSDBuilderStubLog -like 'New-OSBuild -ByTaskName Contoso-Windows 11 Ent x64 25H2 - MUI -Download:True -Execute:True -CreateISO:True').Count | Should -Be 1
    }

    It 'adds the Language Packs and Language Features, the Thai font and NetFX3' {
        Invoke-Example -Parameters @{Languages = @('en-US', 'de-DE', 'th-TH'); LanguageFeatures = @('Basic', 'OCR', 'Speech')}
        $Task = Get-ExampleTask
        $Task.LanguagePack | Should -HaveCount 2
        $Task.LanguagePack -like '*_x64_de-de.cab' | Should -HaveCount 1
        $Task.LanguageFeature -like '*Fonts-Thai*' | Should -HaveCount 1
        $Task.LanguageFeature -like '*Speech-de-de*' | Should -HaveCount 1
        $Task.LanguageFeature -like '*-en-us-*' | Should -HaveCount 0
        $Task.EnableNetFX3 | Should -Be 'True'
    }

    It 'adds a Language Interface Pack for ca-ES' {
        Invoke-Example -Parameters @{Languages = @('en-US', 'ca-ES')}
        (Get-ExampleTask).LanguageInterfacePack -like '*Lip-Language-Pack_x64_ca-es.cab' | Should -HaveCount 1
    }

    It 'resolves -RemoveAppxDisplayName to the PackageName of the OSMedia' {
        Invoke-Example -Parameters @{RemoveAppxDisplayName = @('Microsoft.BingNews')}
        (Get-ExampleTask).RemoveAppxProvisionedPackage | Should -Be 'Microsoft.BingNews_4.55.1.0_neutral_~_8wekyb3d8bbwe'
    }

    It 'sets the regional format, system locale and keyboard with -RegionalFormat' {
        Invoke-Example -Parameters @{DefaultLanguage = 'de-DE'; RegionalFormat = 'de-at'}
        ($global:OSDBuilderStubLog -like 'New-OSBuildTask*-SetAllIntl de-DE -SetUserLocale de-AT -SetSysLocale de-AT -SetInputLocale de-AT*').Count | Should -Be 1
    }

    It 'explains that de-AT is a regional format and not a display language' {
        {Invoke-Example -Parameters @{Languages = @('en-US', 'de-AT')}} | Should -Throw '*de-at is not a display language, use the display language de-de in -Languages and -RegionalFormat de-at*'
    }

    It 'downloads the Local Experience Pack of a language without a .cab' {
        $LxpDirectory = Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $OSDBuilderHome 'Content') 'IsoExtract') 'Windows 11 24H2-26H2 x64 Local Experience Packs') 'LocalExperiencePack') 'nn-no'
        New-TestFile -Path (Join-Path $LxpDirectory 'LanguageExperiencePack.nn-no.Neutral.appx') | Out-Null
        New-TestFile -Path (Join-Path $LxpDirectory 'License.xml') | Out-Null
        Invoke-Example -Parameters @{Languages = @('en-US', 'nn-NO')}
        $global:OSDBuilderStubLog | Should -Contain 'Save-OSDBuilderDownload -LocalExperiencePack nn-no -LocalExperiencePackRelease Windows 11 24H2-26H2'
        (Get-ExampleTask).LocalExperiencePacks | Should -BeLike '*LocalExperiencePack*nn-no*LanguageExperiencePack.nn-no.Neutral.appx'
    }

    It 'does not download content with -SkipContentDownload' {
        Invoke-Example -Parameters @{SkipContentDownload = $true}
        $global:OSDBuilderStubLog -like 'Save-OSDBuilderDownload*' | Should -HaveCount 0
    }

    It 'does not enable NetFX3 with -SkipNetFX3' {
        Invoke-Example -Parameters @{SkipNetFX3 = $true}
        (Get-ExampleTask).EnableNetFX3 | Should -Be 'False'
    }

    It 'imports the ISO of a Windows Setup language and sets LanguageCopySources' {
        $global:OSDBuilderStubImport = @{'D:\ISO\de.iso' = (New-StubOSMedia 'de-DE' -FullName 'D:\OSMedia\de')}
        Invoke-Example -Parameters @{SetupLanguages = @('de-DE'); SetupLanguageIso = @('D:\ISO\de.iso'); SetupUILanguage = 'de-DE'}
        $global:OSDBuilderStubLog | Should -Contain 'Mount-DiskImage D:\ISO\de.iso'
        $Task = Get-ExampleTask
        $Task.LanguageCopySources | Should -Be 'Family de-DE'
        $Task.LangSetSetupUILang | Should -Be 'de-DE'
    }

    It 'fails without OSMedia and without -SourceIso' {
        $global:OSDBuilderStubOSMedia = @()
        {Invoke-Example} | Should -Throw '*use -SourceIso to import it*'
    }
}
