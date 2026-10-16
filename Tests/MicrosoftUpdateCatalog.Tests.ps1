BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript -Name 'MicrosoftUpdateCatalog')) {. $Script}

    $SearchHtml = Get-Content -Path (Join-Path $FixturesPath 'CatalogSearch-25H2.html') -Raw
    $DownloadHtml = Get-Content -Path (Join-Path $FixturesPath 'CatalogDownloadDialog-KB5127648.html') -Raw

    function New-CatalogItem ($Title, $Date, $UpdateId = ([guid]::NewGuid().Guid)) {
        $Id = $null
        if ($Title -match '\(KB(?<KB>\d+)\)') {$Id = $Matches['KB']}
        [PSCustomObject]@{Title = $Title; Id = $Id; UpdateId = $UpdateId; Classification = 'Security Updates'; SupportedProducts = @('Windows 11'); LastModified = [datetime]$Date; Size = '1 MB'}
    }
}

Describe 'Search-OSDBuilderCatalog' {
    BeforeAll {
        Mock Invoke-WebRequest {[PSCustomObject]@{Content = $SearchHtml}}
        $Results = @(Search-OSDBuilderCatalog -Search 'Windows 11 25H2 x64')
    }

    It 'parses every row of the Microsoft Update Catalog search result' {
        $Results.Count | Should -Be 25
    }

    It 'parses title, KB, UpdateId, date and products' {
        $Lcu = $Results | Where-Object {$_.Id -eq '5127648'}
        $Lcu.Title | Should -Be '2026-10 Cumulative Update for Windows 11, version 25H2 for x64-based Systems (KB5127648) (26200.9711)'
        $Lcu.UpdateId | Should -Match '^[0-9a-f-]{36}$'
        $Lcu.LastModified | Should -BeOfType [datetime]
        $Lcu.LastModified.Year | Should -Be 2026
        $Lcu.SupportedProducts | Should -Not -BeNullOrEmpty
    }

    It 'queries the catalog with the URL encoded search' {
        Should -Invoke Invoke-WebRequest -Scope Describe -Times 1 -Exactly -ParameterFilter {([uri]$Uri).AbsoluteUri -eq 'https://www.catalog.update.microsoft.com/Search.aspx?q=Windows%2011%2025H2%20x64'}
    }
}

Describe 'Get-OSDBuilderCatalogDownloadLinks' {
    It 'returns the LCU and the checkpoint cumulative update' {
        Mock Invoke-WebRequest {[PSCustomObject]@{Content = $DownloadHtml}}
        $Links = @(Get-OSDBuilderCatalogDownloadLinks -UpdateId '00000000-0000-0000-0000-000000000000')
        $Links.Count | Should -Be 2
        $Links | Where-Object {$_ -like '*kb5127648*'} | Should -Not -BeNullOrEmpty
        $Links | Where-Object {$_ -like '*kb5043080*'} | Should -Not -BeNullOrEmpty
        $Links | ForEach-Object {$_ | Should -Match '^https://'}
    }
}

Describe 'Get-OSDBuilderCatalogManifests' {
    BeforeEach {
        $script:OSDBuilderCatalogCache = $null
        $global:SetOSDBuilderPathUpdates = Join-Path $TestDrive ([guid]::NewGuid())
        Mock Get-OSDBuilderCatalogDownloadLinks {"https://example.invalid/$UpdateId.msu"}
        Mock Search-OSDBuilderCatalog {
            @(
                New-CatalogItem '2026-10 Cumulative Update for Windows 11, version 25H2 for x64-based Systems (KB5127648) (26200.9711)' '2026-10-14'
                New-CatalogItem '2026-09 Cumulative Update for Windows 11, version 25H2 for x64-based Systems (KB5129195) (26200.9457)' '2026-09-09'
                New-CatalogItem '2026-10 Cumulative Update Preview for Windows 11, version 25H2 for x64-based Systems (KB5130000) (26200.9800)' '2026-10-28'
                New-CatalogItem '2026-10 Safe OS Dynamic Update for Windows 11, version 25H2 for x64-based Systems (KB5127654)' '2026-10-14'
                New-CatalogItem '2026-10 Setup Dynamic Update for Windows 11, version 25H2 for x64-based Systems (KB5127650)' '2026-10-14'
                New-CatalogItem '2026-10 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2 for x64 (KB5127690)' '2026-10-14'
            )
        }
    }
    AfterAll {
        Remove-Variable -Name SetOSDBuilderPathUpdates -Scope Global -ErrorAction SilentlyContinue
    }

    It 'returns the latest LCU, .NET CU, Safe OS DU and Setup DU without previews' {
        $Result = @(Get-OSDBuilderCatalogManifests -ReleaseId '25H2')
        $Result.Id | Sort-Object | Should -Be @('5127648','5127650','5127654','5127690')
        $Result | ForEach-Object {$_.Source | Should -Be 'Microsoft Update Catalog'}
        $Result | ForEach-Object {$_.ReleaseId | Should -Be '25H2'}
    }

    It 'writes the result to the disk cache' {
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' | Out-Null
        Join-Path (Join-Path $global:SetOSDBuilderPathUpdates '_Catalog') 'Windows 11 25H2 x64.json' | Should -Exist
    }

    It 'uses the memory cache for the second call' {
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' | Out-Null
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' | Out-Null
        Should -Invoke Search-OSDBuilderCatalog -Times 4 -Exactly
    }

    It 'uses the disk cache in a new session' {
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' | Out-Null
        $script:OSDBuilderCatalogCache = $null
        $Result = @(Get-OSDBuilderCatalogManifests -ReleaseId '25H2')
        $Result.Count | Should -Be 4
        Should -Invoke Search-OSDBuilderCatalog -Times 4 -Exactly
    }

    It 'uses an expired disk cache when the catalog cannot be reached' {
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' | Out-Null
        $script:OSDBuilderCatalogCache = $null
        $CacheFile = Join-Path (Join-Path $global:SetOSDBuilderPathUpdates '_Catalog') 'Windows 11 25H2 x64.json'
        (Get-Item $CacheFile).LastWriteTime = (Get-Date).AddDays(-2)
        Mock Search-OSDBuilderCatalog {throw 'The remote name could not be resolved'}
        $Result = @(Get-OSDBuilderCatalogManifests -ReleaseId '25H2' 3>$null)
        $Result.Count | Should -Be 4
    }

    It 'returns nothing without cache when the catalog cannot be reached' {
        Mock Search-OSDBuilderCatalog {throw 'The remote name could not be resolved'}
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' 3>$null | Should -BeNullOrEmpty
    }
}
