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

    It 'queries all supported releases by default' {
        $Result = @(Get-OSDBuilderCatalogManifests 3>$null)
        Should -Invoke Search-OSDBuilderCatalog -Times 20 -Exactly
        foreach ($Release in '22H2', '23H2', '24H2', '25H2', '26H2') {
            Should -Invoke Search-OSDBuilderCatalog -Times 1 -Exactly -ParameterFilter {$Search -eq "Cumulative Update for Windows 11 $Release x64"}
        }
        #The mocked catalog has 25H2 updates only
        $Result.Count | Should -Be 4
    }

    It 'warns and uses the OSD Module archive when no update matches' {
        $Warnings = (Get-OSDBuilderCatalogManifests -ReleaseId '24H2' -Verbose 3>&1 4>$null) -join "`n"
        $Warnings | Should -BeLike '*Unable to get the latest updates for Windows 11 24H2 x64*'
        $Warnings | Should -BeLike '*No updates were returned for Windows 11 24H2 x64*'
        $Warnings | Should -BeLike '*Using the OSD Module archive for Windows 11 24H2 x64*'
        $Verbose = (Get-OSDBuilderCatalogManifests -ReleaseId '24H2' -Force -Verbose 3>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*Microsoft Update Catalog: No result for Cumulative Update for Windows 11 24H2 x64*'
    }

    It 'does not query the catalog again in the session after a failure' {
        Mock Search-OSDBuilderCatalog {throw 'The remote name could not be resolved'}
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' 3>$null | Should -BeNullOrEmpty
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' 3>$null | Should -BeNullOrEmpty
        Should -Invoke Search-OSDBuilderCatalog -Times 1 -Exactly
    }

    It 'warns when the catalog returns no download links' {
        Mock Get-OSDBuilderCatalogDownloadLinks {}
        $Warnings = (Get-OSDBuilderCatalogManifests -ReleaseId '25H2' 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Unable to get the download links for 2026-10 Cumulative Update for Windows 11, version 25H2*'
        Join-Path (Join-Path $global:SetOSDBuilderPathUpdates '_Catalog') 'Windows 11 25H2 x64.json' | Should -Not -Exist
    }

    It 'queries the catalog again for a corrupt disk cache' {
        $CacheFile = New-TestFile -Path (Join-Path (Join-Path $global:SetOSDBuilderPathUpdates '_Catalog') 'Windows 11 25H2 x64.json') -Value '{not json'
        $Verbose = (Get-OSDBuilderCatalogManifests -ReleaseId '25H2' -Verbose 4>&1) | Where-Object {$_ -is [System.Management.Automation.VerboseRecord]} | ForEach-Object {"$_"}
        ($Verbose -join "`n") | Should -BeLike "*Unable to read $($CacheFile.FullName)*"
        Should -Invoke Search-OSDBuilderCatalog -Times 4 -Exactly
        @(Get-Content -Path $CacheFile.FullName -Raw | ConvertFrom-Json | ForEach-Object {$_}).Count | Should -Be 4
    }

    It 'ignores the memory and disk cache with -Force' {
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' | Out-Null
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' -Force | Out-Null
        Should -Invoke Search-OSDBuilderCatalog -Times 8 -Exactly
    }

    It 'queries the catalog again when the caches are expired' {
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' | Out-Null
        $CacheFile = Join-Path (Join-Path $global:SetOSDBuilderPathUpdates '_Catalog') 'Windows 11 25H2 x64.json'
        (Get-Item $CacheFile).LastWriteTime = (Get-Date).AddDays(-2)
        $script:OSDBuilderCatalogCache['Windows 11 25H2 x64'].Timestamp = (Get-Date).AddDays(-2)
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' | Out-Null
        Should -Invoke Search-OSDBuilderCatalog -Times 8 -Exactly
    }

    It 'uses the cached result of the catalog when the catalog fails later' {
        Get-OSDBuilderCatalogManifests -ReleaseId '25H2' | Out-Null
        Mock Search-OSDBuilderCatalog {throw 'The remote name could not be resolved'}
        $Output = @(Get-OSDBuilderCatalogManifests -ReleaseId '25H2' -Force 3>&1)
        ($Output | Where-Object {$_ -is [System.Management.Automation.WarningRecord]} | ForEach-Object {"$_"}) -join "`n" | Should -BeLike '*Using cached results from*'
        @($Output | Where-Object {$_ -isnot [System.Management.Automation.WarningRecord]}).Count | Should -Be 4
    }

    It 'uses the TEMP directory for the disk cache without OSDBuilder path' {
        $Temp = $env:TEMP
        try {
            $global:SetOSDBuilderPathUpdates = $null
            $env:TEMP = Join-Path $TestDrive 'Temp'
            Get-OSDBuilderCatalogManifests -ReleaseId '25H2' | Out-Null
            Join-Path (Join-Path (Join-Path $env:TEMP 'OSDBuilder') 'Catalog') 'Windows 11 25H2 x64.json' | Should -Exist
        }
        finally {
            $env:TEMP = $Temp
        }
    }
}

Describe 'Search-OSDBuilderCatalog edge cases' {
    It 'skips a row with an invalid date' {
        $Html = "<a id='3b5e9c1a-0000-4000-8000-000000000001_link' href='#'>2026-10 Update (KB1)</a>" +
            '<td id="x_C2_R1">Windows 11</td><td id="x_C3_R1">Updates</td><td id="x_C4_R1">not a date</td><span id="x_size">1 MB</span>' +
            "<a id='3b5e9c1a-0000-4000-8000-000000000002_link' href='#'>2026-10 Update &amp; more</a>" +
            '<td id="x_C2_R2">Windows 11, Windows 10</td><td id="x_C3_R2">Updates</td><td id="x_C4_R2">10/14/2026</td><span id="x_size">2 MB</span>'
        Mock Invoke-WebRequest {[PSCustomObject]@{Content = $Html}}
        $Output = @(Search-OSDBuilderCatalog -Search 'Update' -Verbose 4>&1)
        ($Output | Where-Object {$_ -is [System.Management.Automation.VerboseRecord]} | ForEach-Object {"$_"}) -join "`n" | Should -BeLike '*Unable to parse the date of 2026-10 Update (KB1)*'
        $Result = @($Output | Where-Object {$_ -isnot [System.Management.Automation.VerboseRecord]})
        $Result.Count | Should -Be 1
        $Result[0].Title | Should -Be '2026-10 Update & more'
        $Result[0].Id | Should -BeNullOrEmpty
        $Result[0].SupportedProducts | Should -Be @('Windows 11', 'Windows 10')
        $Result[0].LastModified | Should -Be ([datetime]'2026-10-14')
        $Result[0].Size | Should -Be '2 MB'
    }
}
