function Get-OSDBuilderCatalogManifests {
    <#
    .SYNOPSIS
    Returns the latest Windows 11 Updates from the Microsoft Update Catalog

    .DESCRIPTION
    The update manifests shipped with the OSD Module are an archive and are no longer updated.
    This function queries the Microsoft Update Catalog directly for the latest LCU, .NET CU,
    Safe OS Dynamic Update and Setup Dynamic Update of each supported Windows 11 release.
    Results are returned in the same format as Get-WindowsUpdateManifests (OSD Module).
    Results are cached in memory and on disk. If the Microsoft Update Catalog cannot be reached,
    the last cached result is used.

    .EXAMPLE
    Get-OSDBuilderCatalogManifests -ReleaseId '25H2'
    #>
    [CmdletBinding()]
    param (
        [ValidateSet('22H2','23H2','24H2','25H2','26H2')]
        [string[]]$ReleaseId = @('22H2','23H2','24H2','25H2','26H2'),

        [ValidateSet('x64')]
        [string]$Architecture = 'x64',

        #Number of hours the cached result is used before the Microsoft Update Catalog is queried again
        [int]$CacheHours = 12,

        #Ignore the cache and query the Microsoft Update Catalog
        [switch]$Force
    )
    #=================================================
    #   Catalog Groups
    #   {0} = ReleaseId, {1} = Architecture
    #   Patterns exclude Preview, Hotpatch and Dynamic Cumulative Updates
    #=================================================
    $CatalogGroups = @(
        [PSCustomObject]@{
            Name    = 'LCU'
            Search  = 'Cumulative Update for Windows 11 {0} {1}'
            Pattern = '^\d{{4}}-\d{{2}} Cumulative Update for Windows 11,? [Vv]ersion {0} for {1}-based Systems'
        }
        [PSCustomObject]@{
            Name    = 'DotNetCU'
            Search  = 'Cumulative Update for .NET Framework Windows 11 {0} {1}'
            Pattern = '^\d{{4}}-\d{{2}} Cumulative Update for \.NET Framework .+ for Windows 11,? [Vv]ersion {0} for {1}\b'
        }
        [PSCustomObject]@{
            Name    = 'SafeOS'
            Search  = 'Safe OS Dynamic Update Windows 11 {0} {1}'
            Pattern = '^\d{{4}}-\d{{2}} Safe OS Dynamic Update for Windows 11,? [Vv]ersion {0} for {1}-based Systems'
        }
        [PSCustomObject]@{
            Name    = 'SetupDU'
            Search  = 'Setup Dynamic Update Windows 11 {0} {1}'
            Pattern = '^\d{{4}}-\d{{2}} Setup Dynamic Update for Windows 11,? [Vv]ersion {0} for {1}-based Systems'
        }
    )
    #=================================================
    #   Cache
    #=================================================
    if ($null -eq $script:OSDBuilderCatalogCache) {$script:OSDBuilderCatalogCache = @{}}

    $CachePath = $null
    if ($global:SetOSDBuilderPathUpdates) {
        $CachePath = Join-Path $global:SetOSDBuilderPathUpdates '_Catalog'
    }
    else {
        $CachePath = Join-Path $env:TEMP 'OSDBuilder\Catalog'
    }
    #=================================================
    #   TLS 1.2 is required by the Microsoft Update Catalog
    #=================================================
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    #=================================================
    #   Execute
    #=================================================
    $Results = foreach ($Release in $ReleaseId) {
        $CacheKey = "Windows 11 $Release $Architecture"
        $CacheFile = Join-Path $CachePath "$CacheKey.json"
        #=================================================
        #   Memory Cache
        #=================================================
        if (-not $Force.IsPresent -and $script:OSDBuilderCatalogCache.ContainsKey($CacheKey)) {
            $MemoryCache = $script:OSDBuilderCatalogCache[$CacheKey]
            if ($MemoryCache.Timestamp -gt (Get-Date).AddHours(-$CacheHours)) {
                $MemoryCache.Items
                Continue
            }
        }
        #=================================================
        #   Disk Cache
        #=================================================
        $DiskCache = $null
        if (Test-Path $CacheFile) {
            try {
                #Windows PowerShell 5.1 returns a JSON array as a single object, assign before enumerating
                $DiskCacheJson = Get-Content -Path $CacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $DiskCache = @($DiskCacheJson | ForEach-Object {$_})
            }
            catch {
                Write-Verbose "Unable to read $CacheFile"
                $DiskCache = $null
            }
            if ($DiskCache -and -not $Force.IsPresent -and ((Get-Item $CacheFile).LastWriteTime -gt (Get-Date).AddHours(-$CacheHours))) {
                $script:OSDBuilderCatalogCache[$CacheKey] = @{Timestamp = (Get-Item $CacheFile).LastWriteTime; Items = $DiskCache}
                $DiskCache
                Continue
            }
        }
        #=================================================
        #   Microsoft Update Catalog
        #=================================================
        try {
            Write-Verbose "Microsoft Update Catalog: $CacheKey"
            $Items = foreach ($Group in $CatalogGroups) {
                $Search = $Group.Search -f $Release, $Architecture
                $Pattern = $Group.Pattern -f $Release, $Architecture

                $Latest = Search-OSDBuilderCatalog -Search $Search -ErrorAction Stop | `
                    Where-Object {$_.Title -match $Pattern} | `
                    Sort-Object -Property @{Expression = {$_.LastModified}; Descending = $true}, @{Expression = {[int64]$_.Id}; Descending = $true} | `
                    Select-Object -First 1

                if ($null -eq $Latest) {
                    Write-Verbose "Microsoft Update Catalog: No result for $Search"
                    Continue
                }

                $Links = @(Get-OSDBuilderCatalogDownloadLinks -UpdateId $Latest.UpdateId -ErrorAction Stop)
                if ($Links.Count -eq 0) {
                    Throw "Unable to get the download links for $($Latest.Title)"
                }

                [PSCustomObject]@{
                    Title             = $Latest.Title
                    Id                = $Latest.Id
                    Architecture      = $Architecture
                    Language          = ''
                    Description       = $null
                    LastModified      = $Latest.LastModified.ToString('yyyy-MM-dd')
                    Size              = $Latest.Size
                    Classification    = $Latest.Classification
                    SupportedProducts = $Latest.SupportedProducts
                    UpdateId          = $Latest.UpdateId
                    Link              = $Links
                    ReleaseId         = $Release
                    Source            = 'Microsoft Update Catalog'
                }
            }
            $Items = @($Items)

            if ($Items.Count -eq 0) {
                Throw "No updates were returned for $CacheKey"
            }

            if (!(Test-Path $CachePath)) {New-Item -Path $CachePath -ItemType Directory -Force | Out-Null}
            ConvertTo-Json -InputObject $Items -Depth 5 | Out-File -FilePath $CacheFile -Encoding utf8 -Force
            $script:OSDBuilderCatalogCache[$CacheKey] = @{Timestamp = Get-Date; Items = $Items}
            $Items
        }
        catch {
            Write-Warning "Microsoft Update Catalog: Unable to get the latest updates for $CacheKey"
            Write-Warning "$($_.Exception.Message)"
            if ($DiskCache) {
                Write-Warning "Microsoft Update Catalog: Using cached results from $((Get-Item $CacheFile).LastWriteTime)"
                $script:OSDBuilderCatalogCache[$CacheKey] = @{Timestamp = Get-Date; Items = $DiskCache}
                $DiskCache
            }
            else {
                #Do not query the Microsoft Update Catalog again in this session, the OSD Module archive is used
                Write-Warning "Microsoft Update Catalog: Using the OSD Module archive for $CacheKey"
                $script:OSDBuilderCatalogCache[$CacheKey] = @{Timestamp = Get-Date; Items = @()}
            }
        }
    }
    Return $Results
}
function Search-OSDBuilderCatalog {
    <#
    .SYNOPSIS
    Searches the Microsoft Update Catalog and returns the first page of results
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Search
    )
    $Uri = "https://www.catalog.update.microsoft.com/Search.aspx?q=$([uri]::EscapeDataString($Search))"
    $Response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 60 -Headers @{'Accept-Language' = 'en-US'} -ErrorAction Stop

    $RowPattern = "<a id='(?<UpdateId>[0-9a-fA-F-]{36})_link'[^>]*>\s*(?<Title>.*?)\s*</a>" + `
        '.*?_C2_R\d+">\s*(?<Products>.*?)\s*</td>' + `
        '.*?_C3_R\d+">\s*(?<Classification>.*?)\s*</td>' + `
        '.*?_C4_R\d+">\s*(?<LastModified>.*?)\s*</td>' + `
        '.*?_size">\s*(?<Size>.*?)\s*</span>'

    foreach ($Match in [regex]::Matches($Response.Content, $RowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $Title = [System.Net.WebUtility]::HtmlDecode($Match.Groups['Title'].Value).Trim()

        $LastModified = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($Match.Groups['LastModified'].Value.Trim(), 'M/d/yyyy', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$LastModified)) {
            Write-Verbose "Unable to parse the date of $Title"
            Continue
        }

        $Id = $null
        if ($Title -match '\(KB(?<KB>\d+)\)') {$Id = $Matches['KB']}

        [PSCustomObject]@{
            Title             = $Title
            Id                = $Id
            UpdateId          = $Match.Groups['UpdateId'].Value
            Classification    = [System.Net.WebUtility]::HtmlDecode($Match.Groups['Classification'].Value).Trim()
            SupportedProducts = @(([System.Net.WebUtility]::HtmlDecode($Match.Groups['Products'].Value) -split ',') | ForEach-Object {$_.Trim()} | Where-Object {$_})
            LastModified      = $LastModified
            Size              = $Match.Groups['Size'].Value.Trim()
        }
    }
}
function Get-OSDBuilderCatalogDownloadLinks {
    <#
    .SYNOPSIS
    Returns the download links of a Microsoft Update Catalog UpdateId
    Windows 11 24H2 and newer LCUs return multiple links (checkpoint cumulative updates)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$UpdateId
    )
    $Body = @{updateIDs = "[{`"size`":0,`"languages`":`"`",`"uidInfo`":`"$UpdateId`",`"updateID`":`"$UpdateId`"}]"}
    $Response = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $Body -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop

    [regex]::Matches($Response.Content, "files\[\d+\]\.url\s*=\s*'(?<Url>https?://[^']+)'") | `
        ForEach-Object {$_.Groups['Url'].Value} | `
        Select-Object -Unique
}
