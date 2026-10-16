function Get-OSDBuilderServicingBuild {
    <#
    .SYNOPSIS
    Returns the build of the servicing branch that language content is published for
    Windows 10 2004-22H2 (19041-19045) -> 19041
    Windows 11 22H2-23H2 (22621-22631) -> 22621
    Windows 11 24H2-26H2 (26100-26300) -> 26100
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int]$Build
    )
    if (($Build -ge 19041) -and ($Build -le 19045)) {Return 19041}
    if (($Build -eq 22621) -or ($Build -eq 22631)) {Return 22621}
    if (($Build -ge 26100) -and ($Build -le 26300)) {Return 26100}
    Return $Build
}
function Test-OSDBuilderLocalExperiencePackBuild {
    <#
    .SYNOPSIS
    Returns $true when a Local Experience Pack can be added to an image of the Build

    .DESCRIPTION
    The version of an LXP starts with the build of its servicing branch, for example
    19041.29.88.0 (Windows 10 2004-22H2), 22000.8.13.0 (Windows 11 21H2) or 26100.x (Windows 11 24H2-26H2)
    The Windows.Desktop MinVersion is lower than the branch (10.0.18823.0 for 19041), it must not be newer than the image
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [int]$Build
    )
    $MinVersion = $null
    if ([version]::TryParse([string]$Manifest.MinOSVersion, [ref]$MinVersion) -and ($MinVersion.Build -gt $Build)) {Return $false}

    $PackageVersion = $null
    if (-not [version]::TryParse([string]$Manifest.Version, [ref]$PackageVersion)) {Return $true}
    Return ((Get-OSDBuilderServicingBuild -Build $PackageVersion.Major) -eq (Get-OSDBuilderServicingBuild -Build $Build))
}
function Add-OSDBuilderLocalExperiencePack {
    <#
    .SYNOPSIS
    Adds a Local Experience Pack (LanguageExperiencePack.<lang>.Neutral.appx) to the mounted Windows image
    Returns Added, Installed (the same or a newer version is already provisioned) or Failed

    .DESCRIPTION
    The license is License.xml in the directory of the .appx, as on the Local Experience Pack ISO
    The LXP is skipped when it was published for another servicing branch or the image contains the same or a newer version
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [int]$Build,

        [string]$LogPath
    )
    if (!(Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        Write-Warning "Local Experience Pack: Not Found $PackagePath"
        Return 'Failed'
    }
    #Full provider path for System.IO.Compression and DISM
    $PackagePath = Convert-Path -LiteralPath $PackagePath
    #=================================================
    #   Manifest
    #=================================================
    $Manifest = $null
    try {$Manifest = Get-OSDBuilderAppxManifest -Path $PackagePath -ErrorAction Stop}
    catch {Write-Verbose "Unable to read the AppxManifest of $PackagePath"}
    if (($null -eq $Manifest) -or [string]::IsNullOrWhiteSpace($Manifest.Name)) {
        Write-Warning "Local Experience Pack: $PackagePath is not a valid .appx"
        Return 'Failed'
    }
    if ($Manifest.Name -notlike 'Microsoft.LanguageExperiencePack*') {
        Write-Warning "Local Experience Pack: $($Manifest.Name) is not a Language Experience Pack"
        Return 'Failed'
    }
    if ($Build -and -not (Test-OSDBuilderLocalExperiencePackBuild -Manifest $Manifest -Build $Build)) {
        Write-Warning "Local Experience Pack: $($Manifest.Name) $($Manifest.Version) (MinVersion $($Manifest.MinOSVersion)) is not published for build $Build"
        Return 'Failed'
    }
    #=================================================
    #   License
    #=================================================
    $Directory = Split-Path -Path $PackagePath -Parent
    $LicensePath = Get-ChildItem -LiteralPath $Directory -File -Filter '*.xml' -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq 'License.xml'} | Select-Object -First 1 -ExpandProperty FullName
    if (-not $LicensePath) {
        Write-Warning "Local Experience Pack: Unable to find the License.xml for $($Manifest.Name) in $Directory"
        Return 'Failed'
    }
    #=================================================
    #   Installed
    #=================================================
    $Provisioned = @(Get-AppxProvisionedPackage -Path $Path -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -eq $Manifest.Name})
    $NewVersion = $null
    [void][version]::TryParse([string]$Manifest.Version, [ref]$NewVersion)
    foreach ($Item in $Provisioned) {
        $InstalledVersion = $null
        if ($NewVersion -and [version]::TryParse([string]$Item.Version, [ref]$InstalledVersion) -and ($InstalledVersion -ge $NewVersion)) {
            Write-Host -ForegroundColor Gray "INSTALLED         $($Manifest.Name) $($Item.Version)"
            Return 'Installed'
        }
    }
    #=================================================
    #   Execute
    #=================================================
    Write-Host -ForegroundColor Cyan "INSTALLING        " -NoNewline
    Write-Host -ForegroundColor Gray "$($Manifest.Name) $($Manifest.Version)"
    $Params = @{
        Path        = $Path
        PackagePath = $PackagePath
        LicensePath = $LicensePath
        ErrorAction = 'Stop'
    }
    if ($LogPath) {$Params.LogPath = $LogPath}
    try {
        Add-AppxProvisionedPackage @Params | Out-Null
    }
    catch {
        Write-Warning "Local Experience Pack: $($Manifest.Name) $($_.Exception.Message)"
        if ($LogPath) {Write-Warning "Review $LogPath"}
        Return 'Failed'
    }
    #=================================================
    #   Verify
    #=================================================
    $Provisioned = @(Get-AppxProvisionedPackage -Path $Path -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -eq $Manifest.Name})
    if ($Provisioned.Count -eq 0) {
        Write-Warning "Local Experience Pack: $($Manifest.Name) is not provisioned in the image"
        if ($LogPath) {Write-Warning "Review $LogPath"}
        Return 'Failed'
    }
    Return 'Added'
}
