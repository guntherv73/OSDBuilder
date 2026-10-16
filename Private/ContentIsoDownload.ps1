function Get-OSDBuilderContentIsoCatalog {
    <#
    .SYNOPSIS
    Returns the Windows 11 Languages and Optional Features and Inbox Apps ISOs published by Microsoft

    .DESCRIPTION
    https://learn.microsoft.com/en-us/azure/virtual-desktop/windows-11-language-packs

    Languages and Optional Features
    Language Packs, Language Features on Demand, Features on Demand and WinPE Optional Components
    The Name is used as the IsoExtract directory, it contains the ReleaseIds and the Architecture
    so the content is offered by New-OSBuildTask for all compatible OSMedia

    Inbox Apps
    The inbox app packages with their license files and framework dependencies
    The ISO is extracted to Content\InboxApps, it is not part of IsoExtract
    so the app packages are not offered as Language or Feature on Demand content
    #>
    [CmdletBinding()]
    param ()
    @(
        [PSCustomObject]@{
            Name            = 'Windows 11 22H2-23H2 x64 Languages and Optional Features'
            Type            = 'LanguagesAndOptionalFeatures'
            ReleaseId       = @('22H2','23H2')
            Build           = '22621'
            Url             = 'https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66749/22621.1.220506-1250.ni_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso'
            FileName        = '22621.1.220506-1250.ni_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso'
            Size            = [int64]7205206016
            ContentFolder   = 'LanguagesAndOptionalFeatures'
        }
        [PSCustomObject]@{
            #Microsoft publishes this ISO for 24H2 and 25H2, 26H2 is serviced with the same 26100 LCU
            Name            = 'Windows 11 24H2-26H2 x64 Languages and Optional Features'
            Type            = 'LanguagesAndOptionalFeatures'
            ReleaseId       = @('24H2','25H2','26H2')
            Build           = '26100'
            Url             = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1.240331-1435.ge_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso'
            FileName        = '26100.1.240331-1435.ge_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso'
            Size            = [int64]6251841536
            ContentFolder   = 'LanguagesAndOptionalFeatures'
        }
        [PSCustomObject]@{
            Name            = 'Windows 11 22H2-23H2 Inbox Apps'
            Type            = 'InboxApps'
            ReleaseId       = @('22H2','23H2')
            Build           = '22621'
            Url             = 'https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/22621.2501.231009-1937.ni_release_svc_prod3_amd64fre_InboxApps.iso'
            FileName        = '22621.2501.231009-1937.ni_release_svc_prod3_amd64fre_InboxApps.iso'
            Size            = [int64]4305571840
            ContentFolder   = 'packages'
        }
        [PSCustomObject]@{
            Name            = 'Windows 11 24H2-26H2 Inbox Apps'
            Type            = 'InboxApps'
            ReleaseId       = @('24H2','25H2','26H2')
            Build           = '26100'
            Url             = 'https://software-static.download.prss.microsoft.com/dbazure/26100.9457.260912-0409.ge_release_svc_im_amd64fre_InboxApps.iso'
            FileName        = '26100.9457.260912-0409.ge_release_svc_im_amd64fre_InboxApps.iso'
            Size            = [int64]5648132096
            ContentFolder   = 'packages'
        }
    )
}
function Save-OSDBuilderContentIso {
    <#
    .SYNOPSIS
    Downloads a Windows 11 Languages and Optional Features or Inbox Apps ISO and extracts it

    .DESCRIPTION
    The ISO is saved to Content\ISO and reused when it already exists with the expected size
    Languages and Optional Features are copied to Content\IsoExtract\<Name> where New-OSBuildTask finds the
    Language Packs, Language Features on Demand and Features on Demand
    Inbox Apps are copied to Content\InboxApps\<Name>
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    #=================================================
    #   Catalog
    #=================================================
    $Item = Get-OSDBuilderContentIsoCatalog | Where-Object {$_.Name -eq $Name} | Select-Object -First 1
    if ($null -eq $Item) {
        Write-Warning "Content ISO: $Name is not available"
        Return
    }
    $IsoPath = Join-Path $SetOSDBuilderPathContent 'ISO'
    $IsoFile = Join-Path $IsoPath $Item.FileName
    if ($Item.Type -eq 'InboxApps') {
        $ExtractPath = Join-Path (Join-Path $SetOSDBuilderPathContent 'InboxApps') $Item.Name
    }
    else {
        $ExtractPath = Join-Path $GetOSDBuilderPathContentIsoExtract $Item.Name
    }

    Write-Host -ForegroundColor Green "Content ISO: $($Item.Name)"
    Write-Host -ForegroundColor DarkGray "Url:     $($Item.Url)"
    Write-Host -ForegroundColor DarkGray "ISO:     $IsoFile"
    Write-Host -ForegroundColor DarkGray "Extract: $ExtractPath"
    #=================================================
    #   Expected Size
    #   Microsoft may republish the ISO, the published size wins over the catalog size
    #=================================================
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $ExpectedSize = $Item.Size
    try {
        $Head = Invoke-WebRequest -Uri $Item.Url -Method Head -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        $ContentLength = [int64]0
        if ([int64]::TryParse([string]($Head.Headers['Content-Length'] | Select-Object -First 1), [ref]$ContentLength) -and ($ContentLength -gt 0)) {
            $ExpectedSize = $ContentLength
        }
    }
    catch {
        Write-Verbose "Unable to read the published size, using $ExpectedSize bytes"
    }
    #=================================================
    #   Download
    #=================================================
    if (!(Test-Path $IsoPath)) {New-Item -Path $IsoPath -ItemType Directory -Force | Out-Null}

    if ((Test-Path $IsoFile) -and ((Get-Item $IsoFile).Length -eq $ExpectedSize)) {
        Write-Host -ForegroundColor DarkGray "ISO is already downloaded"
    }
    else {
        $FreeSpace = $null
        try {$FreeSpace = (Get-PSDrive -Name ((Get-Item $IsoPath).PSDrive.Name) -ErrorAction Stop).Free}
        catch {Write-Verbose "Unable to read the free space of $IsoPath"}
        if ($FreeSpace -and ($FreeSpace -lt ($ExpectedSize * 2))) {
            Write-Warning "Content ISO: $([math]::Round($ExpectedSize * 2 / 1GB, 1)) GB of free space is required to download and extract the ISO"
            Return
        }

        Write-Host -ForegroundColor Cyan "Downloading $([math]::Round($ExpectedSize / 1GB, 2)) GB, this will take some time ..."
        $Downloaded = $false
        #BITS resumes and handles proxies, curl.exe resumes a partial download
        if (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
            try {
                if (Test-Path $IsoFile) {Remove-Item -Path $IsoFile -Force -ErrorAction Stop}
                Start-BitsTransfer -Source $Item.Url -Destination $IsoFile -DisplayName $Item.Name -ErrorAction Stop
                $Downloaded = $true
            }
            catch {
                Write-Warning "Content ISO: BITS download failed, $($_.Exception.Message)"
            }
        }
        if (($Downloaded -eq $false) -and (Get-Command -Name 'curl.exe' -ErrorAction SilentlyContinue)) {
            & curl.exe --location --fail --retry 3 --continue-at - --output "$IsoFile" --url "$($Item.Url)"
            if ($LASTEXITCODE -eq 0) {$Downloaded = $true}
            else {Write-Warning "Content ISO: curl.exe download failed with exit code $LASTEXITCODE"}
        }
        if (!(Test-Path $IsoFile) -or ((Get-Item $IsoFile).Length -ne $ExpectedSize)) {
            Write-Warning "Content ISO: The download is incomplete, run the command again to resume"
            Return
        }
    }
    #=================================================
    #   Extract
    #   The marker is written after a complete extract, an interrupted extract is repeated
    #=================================================
    $ExtractComplete = Join-Path $ExtractPath "$($Item.FileName).extracted"
    if (Test-Path $ExtractComplete) {
        Write-Host -ForegroundColor DarkGray "ISO is already extracted"
        Return
    }

    Write-Host -ForegroundColor Cyan "Extracting to $ExtractPath ..."
    $DiskImage = $null
    try {
        $DiskImage = Mount-DiskImage -ImagePath $IsoFile -StorageType ISO -PassThru -ErrorAction Stop

        $DriveLetter = $null
        foreach ($Attempt in 1..10) {
            $DriveLetter = ($DiskImage | Get-Volume -ErrorAction SilentlyContinue).DriveLetter
            if ($DriveLetter) {Break}
            Start-Sleep -Seconds 1
        }
        if (-not $DriveLetter) {Throw "Unable to get the drive letter of $IsoFile"}

        if (!(Test-Path $ExtractPath)) {New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null}
        $CurrentLog = Join-Path $IsoPath "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Extract-$($Item.Build)-$($Item.Type).log"
        robocopy "$($DriveLetter):\" "$ExtractPath" *.* /e /ndl /nfl /np /r:0 /w:0 /xj /log:"$CurrentLog" | Out-Null
        #robocopy exit codes 8 and higher are failures
        if ($LASTEXITCODE -ge 8) {Throw "robocopy failed with exit code $LASTEXITCODE, review $CurrentLog"}
        if (!(Test-Path (Join-Path $ExtractPath $Item.ContentFolder))) {Throw "$IsoFile does not contain a $($Item.ContentFolder) directory"}
        Set-Content -Path $ExtractComplete -Value (Get-Date).ToString('s') -Force
    }
    catch {
        Write-Warning "Content ISO: $($_.Exception.Message)"
        Return
    }
    finally {
        if ($DiskImage) {Dismount-DiskImage -ImagePath $IsoFile -ErrorAction SilentlyContinue | Out-Null}
    }

    Write-Host -ForegroundColor Green "Content ISO: Complete"
    if ($Item.Type -eq 'InboxApps') {
        Write-Host -ForegroundColor Cyan "The Inbox Apps for Windows 11 $($Item.ReleaseId -join ', ') are in $(Join-Path $ExtractPath $Item.ContentFolder)"
    }
    else {
        Write-Host -ForegroundColor Cyan "Use New-OSBuildTask to select the Language Packs, Language Features and Features on Demand for Windows 11 $($Item.ReleaseId -join ', ')"
    }
}
