function Invoke-OSDBuilderWinget {
    <#
    .SYNOPSIS
    Runs winget.exe and returns the ExitCode, and the Output with -CaptureOutput

    .DESCRIPTION
    Without -CaptureOutput the winget output (progress, Microsoft Entra ID authentication) is written to the console
    Throws when winget.exe is not installed
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$CaptureOutput
    )
    $Winget = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $Winget) {
        throw 'winget.exe was not found, install the App Installer from the Microsoft Store'
    }
    $Output = $null
    if ($CaptureOutput) {$Output = & $Winget.Source @Arguments 2>&1 | Out-String}
    else {& $Winget.Source @Arguments | Out-Host}
    [PSCustomObject]@{
        ExitCode    = $LASTEXITCODE
        Output      = $Output
    }
}
function Get-OSDBuilderLocalExperiencePackRelease {
    <#
    .SYNOPSIS
    Returns the servicing branch of a Local Experience Pack release group

    .DESCRIPTION
    Directory is the Content\IsoExtract directory, it contains the ReleaseIds so New-OSBuildTask offers the LXPs for these releases
    OSVersion is passed to winget download --os-version, winget then selects the newest LXP whose Windows.Desktop MinVersion
    is not newer than the build of the servicing branch
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Windows 11 24H2-26H2','Windows 11 22H2-23H2','Windows 10 2004-22H2')]
        [string]$Release
    )
    switch ($Release) {
        'Windows 11 24H2-26H2'  {$Build = 26100}
        'Windows 11 22H2-23H2'  {$Build = 22621}
        'Windows 10 2004-22H2'  {$Build = 19041}
    }
    [PSCustomObject]@{
        Release     = $Release
        Build       = $Build
        OSVersion   = "10.0.$Build.0"
        Directory   = "$Release x64 Local Experience Packs"
    }
}
function Get-OSDBuilderLocalExperiencePackProduct {
    <#
    .SYNOPSIS
    Returns the Microsoft Store product of the Local Experience Pack of a language

    .DESCRIPTION
    The Microsoft Store display catalog is queried by the PackageFamilyName Microsoft.LanguageExperiencePack<lang>_8wekyb3d8bbwe
    Packages lists every published LXP version with its Windows.Desktop MinVersion
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Language
    )
    $PackageFamilyName = "Microsoft.LanguageExperiencePack$($Language)_8wekyb3d8bbwe"
    $Uri = "https://displaycatalog.mp.microsoft.com/v7.0/products/lookup?alternateId=PackageFamilyName&value=$([uri]::EscapeDataString($PackageFamilyName))&market=US&languages=en-US&fieldsTemplate=details"

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $Response = Invoke-RestMethod -Uri $Uri -Method Get -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    $Product = @($Response.Products) | Where-Object {$_} | Select-Object -First 1
    if ($null -eq $Product) {Return}

    #PlatformDependencies versions are UInt64, 16 bits per part
    $Packages = foreach ($Sku in @($Product.DisplaySkuAvailabilities)) {
        foreach ($Package in @($Sku.Sku.Properties.Packages)) {
            if ($null -eq $Package) {Continue}
            $Desktop = @($Package.PlatformDependencies) | Where-Object {$_.PlatformName -eq 'Windows.Desktop'} | Select-Object -First 1
            if ($null -eq $Desktop) {Continue}
            $MinVersion = [uint64]$Desktop.MinVersion
            [PSCustomObject]@{
                PackageFullName = $Package.PackageFullName
                Version         = [version](($Package.PackageFullName -split '_')[1])
                MinVersion      = [version]('{0}.{1}.{2}.{3}' -f (($MinVersion -shr 48) -band 0xFFFF), (($MinVersion -shr 32) -band 0xFFFF), (($MinVersion -shr 16) -band 0xFFFF), ($MinVersion -band 0xFFFF))
            }
        }
    }
    [PSCustomObject]@{
        Language            = $Language
        ProductId           = $Product.ProductId
        Title               = @($Product.LocalizedProperties)[0].ProductTitle
        PackageFamilyName   = $PackageFamilyName
        Packages            = @($Packages | Sort-Object -Property PackageFullName -Unique | Sort-Object -Property Version)
    }
}
function Save-OSDBuilderLocalExperiencePack {
    <#
    .SYNOPSIS
    Downloads Local Experience Packs from the Microsoft Store with winget and saves them for New-OSBuildTask

    .DESCRIPTION
    Microsoft does not publish a Local Experience Pack ISO for Windows 11, the LXPs are Microsoft Store apps
    winget download (App Installer 1.8 or newer with --os-version) downloads the package and the offline license
    The Microsoft Entra ID account must be a Global Administrator, User Administrator or License Administrator
    https://learn.microsoft.com/en-us/windows/package-manager/winget/download

    The LXP is saved in the layout of the Local Experience Pack ISO
    Content\IsoExtract\<Release> x64 Local Experience Packs\LocalExperiencePack\<lang>\LanguageExperiencePack.<lang>.Neutral.appx
    Content\IsoExtract\<Release> x64 Local Experience Packs\LocalExperiencePack\<lang>\License.xml
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Language,

        [ValidateSet('Windows 11 24H2-26H2','Windows 11 22H2-23H2','Windows 10 2004-22H2')]
        [string]$Release = 'Windows 11 24H2-26H2',

        #Microsoft Entra ID account for the Microsoft Store license
        [string]$AuthenticationAccount
    )
    $Target = Get-OSDBuilderLocalExperiencePackRelease -Release $Release
    $TargetPath = Join-Path (Join-Path $GetOSDBuilderPathContentIsoExtract $Target.Directory) 'LocalExperiencePack'
    Write-Host -ForegroundColor Green "Local Experience Packs: $Release (Windows build $($Target.Build))"
    Write-Host -ForegroundColor DarkGray "Destination: $TargetPath"
    #=================================================
    #   winget
    #=================================================
    try {$WingetHelp = Invoke-OSDBuilderWinget -Arguments @('download', '--help') -CaptureOutput}
    catch {
        Write-Warning "Local Experience Packs: $($_.Exception.Message)"
        Return
    }
    if ([string]$WingetHelp.Output -notmatch '--os-version') {
        Write-Warning "Local Experience Packs: winget download does not support --os-version, update the App Installer"
        Write-Warning "Without --os-version winget downloads the LXP of the newest Windows build, which does not match $Release"
        Return
    }
    #=================================================
    #   Languages
    #=================================================
    foreach ($Item in ($Language | Where-Object {$_} | Sort-Object -Unique)) {
        try {$Tag = ([System.Globalization.CultureInfo]::GetCultureInfo($Item)).Name}
        catch {Write-Warning "Local Experience Packs: $Item is not a valid language"; Continue}
        $Folder = $Tag.ToLower()
        $AppxDestination = Join-Path (Join-Path $TargetPath $Folder) "LanguageExperiencePack.$Folder.Neutral.appx"
        $LicenseDestination = Join-Path (Join-Path $TargetPath $Folder) 'License.xml'
        Write-Host -ForegroundColor Cyan "$Tag"
        #=================================================
        #   Microsoft Store product
        #=================================================
        $Product = $null
        try {$Product = Get-OSDBuilderLocalExperiencePackProduct -Language $Tag}
        catch {Write-Warning "Local Experience Packs: Unable to query the Microsoft Store for $Tag, $($_.Exception.Message)"; Continue}
        if ($null -eq $Product) {
            Write-Warning "Local Experience Packs: The Microsoft Store has no Local Experience Pack for $Tag"
            Continue
        }
        #The newest LXP of the servicing branch that winget selects for --os-version
        $Expected = $Product.Packages | Where-Object {($_.Version.Major -eq $Target.Build) -and ($_.MinVersion.Build -le $Target.Build)} | Select-Object -Last 1
        if ($null -eq $Expected) {
            Write-Warning "Local Experience Packs: $($Product.Title) [$($Product.ProductId)] has no package for Windows build $($Target.Build)"
            Continue
        }
        Write-Host -ForegroundColor DarkGray "    $($Product.Title) [$($Product.ProductId)] $($Expected.Version)"
        #=================================================
        #   Installed
        #=================================================
        if ((Test-Path $AppxDestination) -and (Test-Path $LicenseDestination)) {
            $Existing = $null
            try {$Existing = Get-OSDBuilderAppxManifest -Path $AppxDestination -ErrorAction Stop}
            catch {Write-Verbose "Unable to read $AppxDestination, it is downloaded again"}
            if ($Existing -and ([version]$Existing.Version -ge $Expected.Version)) {
                Write-Host -ForegroundColor DarkGray "    $($Existing.Version) is already downloaded"
                Continue
            }
        }
        #=================================================
        #   winget download
        #=================================================
        $DownloadPath = Join-Path $SetOSDBuilderPathContent "ISO\LocalExperiencePack\$($Product.ProductId)"
        if (Test-Path $DownloadPath) {Remove-Item -Path $DownloadPath -Recurse -Force -ErrorAction SilentlyContinue}
        New-Item -Path $DownloadPath -ItemType Directory -Force | Out-Null

        $Arguments = @(
            'download', '--id', $Product.ProductId, '--source', 'msstore', '--exact',
            '--platform', 'Windows.Desktop', '--os-version', $Target.OSVersion,
            '--download-directory', $DownloadPath,
            '--accept-package-agreements', '--accept-source-agreements'
        )
        if ($AuthenticationAccount) {$Arguments += @('--authentication-account', $AuthenticationAccount)}
        $WingetDownload = Invoke-OSDBuilderWinget -Arguments $Arguments
        if ($WingetDownload.ExitCode -ne 0) {
            Write-Warning "Local Experience Packs: winget download failed for $Tag with exit code $($WingetDownload.ExitCode)"
            Continue
        }
        #=================================================
        #   Validate
        #=================================================
        $Appx = Get-ChildItem -Path $DownloadPath -File -Recurse -Include '*.appx','*.msix' -ErrorAction SilentlyContinue | `
            Where-Object {$_.Name -like "Microsoft.LanguageExperiencePack*"} | Sort-Object -Property Name | Select-Object -Last 1
        $License = Get-ChildItem -Path $DownloadPath -File -Recurse -Filter '*License.xml' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $Appx) {Write-Warning "Local Experience Packs: winget did not download a Local Experience Pack for $Tag"; Continue}
        if ($null -eq $License) {Write-Warning "Local Experience Packs: winget did not download the license for $Tag, the Entra ID account needs the License Administrator role"; Continue}

        $Manifest = $null
        try {$Manifest = Get-OSDBuilderAppxManifest -Path $Appx.FullName -ErrorAction Stop}
        catch {Write-Verbose "Unable to read the AppxManifest of $($Appx.FullName)"}
        if (($null -eq $Manifest) -or ($Manifest.Name -ne "Microsoft.LanguageExperiencePack$Tag")) {
            Write-Warning "Local Experience Packs: $($Appx.Name) is not the Local Experience Pack of $Tag"
            Continue
        }
        if (-not (Test-OSDBuilderLocalExperiencePackBuild -Manifest $Manifest -Build $Target.Build)) {
            Write-Warning "Local Experience Packs: winget downloaded $($Manifest.Version) (MinVersion $($Manifest.MinOSVersion)), this is not the LXP for Windows build $($Target.Build)"
            Continue
        }
        #=================================================
        #   Save
        #=================================================
        New-Item -Path (Split-Path $AppxDestination -Parent) -ItemType Directory -Force | Out-Null
        Copy-Item -Path $Appx.FullName -Destination $AppxDestination -Force
        Copy-Item -Path $License.FullName -Destination $LicenseDestination -Force
        Remove-Item -Path $DownloadPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host -ForegroundColor Green "    Saved $($Manifest.Version) to $AppxDestination"
    }
}
