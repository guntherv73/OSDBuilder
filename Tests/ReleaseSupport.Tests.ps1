BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript -Name 'ReleaseSupport')) {. $Script}

    function New-OSMediaInfo ($OperatingSystem, $ReleaseId) {
        [PSCustomObject]@{OperatingSystem = $OperatingSystem; ReleaseId = $ReleaseId}
    }
}

Describe 'Get-OSDBuilderLanguageReleasePattern' {
    It 'Windows 11 <ReleaseId> shares language content with <Expected>' -ForEach @(
        @{ReleaseId = '22H2'; Expected = '22H2|23H2'}
        @{ReleaseId = '23H2'; Expected = '22H2|23H2'}
        @{ReleaseId = '24H2'; Expected = '24H2|25H2|26H2'}
        @{ReleaseId = '25H2'; Expected = '24H2|25H2|26H2'}
        @{ReleaseId = '26H2'; Expected = '24H2|25H2|26H2'}
        @{ReleaseId = '21H2'; Expected = '21H2'}
    ) {
        Get-OSDBuilderLanguageReleasePattern -OSMedia (New-OSMediaInfo 'Windows 11' $ReleaseId) | Should -Be $Expected
    }

    It 'Windows 10 <ReleaseId> shares language content with <Expected>' -ForEach @(
        @{ReleaseId = '22H2'; Expected = '2004|2009|20H2|21H1|21H2|22H2'}
        @{ReleaseId = '20H2'; Expected = '2004|2009|20H2|21H1|21H2|22H2'}
        @{ReleaseId = '1909'; Expected = '1903|1909'}
        @{ReleaseId = '1809'; Expected = '1809'}
    ) {
        Get-OSDBuilderLanguageReleasePattern -OSMedia (New-OSMediaInfo 'Windows 10' $ReleaseId) | Should -Be $Expected
    }

    It 'matches the content directory <Directory> for Windows 11 25H2: <Match>' -ForEach @(
        @{Directory = 'Windows 11 24H2-26H2 x64 Languages and Optional Features'; Match = $true}
        @{Directory = 'Windows 11 24H2 Language'; Match = $true}
        @{Directory = 'Windows 11 22H2-23H2 x64 Languages and Optional Features'; Match = $false}
    ) {
        ($Directory -match (Get-OSDBuilderLanguageReleasePattern -OSMedia (New-OSMediaInfo 'Windows 11' '25H2'))) | Should -Be $Match
    }
}

Describe 'Get-OSDBuilderLanguageExcludePattern' {
    It 'excludes Windows 10 content for Windows 11' {
        'Windows 10 2004-22H2 x64 Local Experience Packs' | Should -Match (Get-OSDBuilderLanguageExcludePattern -OSMedia (New-OSMediaInfo 'Windows 11' '22H2'))
    }

    It 'excludes Windows 11 content for Windows 10' {
        'Windows 11 22H2-23H2 x64 Languages and Optional Features' | Should -Match (Get-OSDBuilderLanguageExcludePattern -OSMedia (New-OSMediaInfo 'Windows 10' '22H2'))
    }

    It 'excludes nothing for Windows Server' {
        'Windows 11 24H2' | Should -Not -Match (Get-OSDBuilderLanguageExcludePattern -OSMedia (New-OSMediaInfo 'Windows Server' '24H2'))
    }
}

Describe 'Get-OSDBuilderLanguageFeatureOrder' {
    It 'installs Basic first and Speech last' {
        $Names = @(
            'Microsoft-Windows-LanguageFeatures-Speech-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-OCR-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-TextToSpeech-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-Fonts-Thai-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-Handwriting-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab'
        )
        $Sorted = $Names | Sort-Object {Get-OSDBuilderLanguageFeatureOrder -Name $_}
        ($Sorted | ForEach-Object {($_ -split '-')[3]}) -join ',' | Should -Be 'Basic,Fonts,OCR,Handwriting,TextToSpeech,Speech'
    }
}

Describe 'Resolve-OSDBuilderContentPackReleasePath' {
    BeforeEach {
        $ContentPack = Join-Path $TestDrive ([guid]::NewGuid())
        $OSArchitecture = 'x64'
    }

    It 'uses the directory of the ReleaseId when it has files' {
        New-TestFile -Path (Join-Path (Join-Path $ContentPack 'Windows 11 25H2 x64') 'a.reg') | Out-Null
        New-TestFile -Path (Join-Path (Join-Path $ContentPack 'Windows 11 24H2 x64') 'b.reg') | Out-Null
        $UpdateOS = 'Windows 11'; $ReleaseID = '25H2'
        Resolve-OSDBuilderContentPackReleasePath -Path $ContentPack | Should -Be (Join-Path $ContentPack 'Windows 11 25H2 x64')
    }

    It 'uses Windows 11 24H2 for Windows 11 <ReleaseId>' -ForEach @(@{ReleaseId = '25H2'}, @{ReleaseId = '26H2'}) {
        New-Item -Path (Join-Path $ContentPack "Windows 11 $ReleaseId x64") -ItemType Directory -Force | Out-Null
        New-TestFile -Path (Join-Path (Join-Path $ContentPack 'Windows 11 24H2 x64') 'b.reg') | Out-Null
        $UpdateOS = 'Windows 11'; $ReleaseID = $ReleaseId
        Resolve-OSDBuilderContentPackReleasePath -Path $ContentPack 6>$null | Should -Be (Join-Path $ContentPack 'Windows 11 24H2 x64')
    }

    It 'does not use Windows 11 23H2 content for 24H2' {
        New-TestFile -Path (Join-Path (Join-Path $ContentPack 'Windows 11 23H2 x64') 'b.reg') | Out-Null
        $UpdateOS = 'Windows 11'; $ReleaseID = '24H2'
        Resolve-OSDBuilderContentPackReleasePath -Path $ContentPack | Should -Be (Join-Path $ContentPack 'Windows 11 24H2 x64')
    }

    It 'uses Windows 10 2004 for Windows 10 22H2' {
        New-TestFile -Path (Join-Path (Join-Path $ContentPack 'Windows 10 2004 x64') 'b.reg') | Out-Null
        $UpdateOS = 'Windows 10'; $ReleaseID = '22H2'
        Resolve-OSDBuilderContentPackReleasePath -Path $ContentPack 6>$null | Should -Be (Join-Path $ContentPack 'Windows 10 2004 x64')
    }

    It 'does not use Windows 10 content for Windows 11' {
        New-TestFile -Path (Join-Path (Join-Path $ContentPack 'Windows 10 22H2 x64') 'b.reg') | Out-Null
        $UpdateOS = 'Windows 11'; $ReleaseID = '22H2'
        Resolve-OSDBuilderContentPackReleasePath -Path $ContentPack | Should -Be (Join-Path $ContentPack 'Windows 11 22H2 x64')
    }

    It 'appends the suffix for RSAT' {
        New-TestFile -Path (Join-Path (Join-Path $ContentPack 'Windows 11 24H2 x64 RSAT') 'b.cab') | Out-Null
        $UpdateOS = 'Windows 11'; $ReleaseID = '25H2'
        Resolve-OSDBuilderContentPackReleasePath -Path $ContentPack -Suffix ' RSAT' 6>$null | Should -Be (Join-Path $ContentPack 'Windows 11 24H2 x64 RSAT')
    }

    It 'returns the directory of the ReleaseId when no directory has files' {
        $UpdateOS = 'Windows 11'; $ReleaseID = '25H2'
        Resolve-OSDBuilderContentPackReleasePath -Path $ContentPack | Should -Be (Join-Path $ContentPack 'Windows 11 25H2 x64')
    }
}
