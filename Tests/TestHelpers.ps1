<#
.SYNOPSIS
Shared test setup, dot-source it in the BeforeAll block of every *.Tests.ps1 file

.DESCRIPTION
- $RepoRoot and $FixturesPath
- Placeholder commands for the Windows only DISM, Appx and Storage cmdlets and the OSD module, so Pester can mock them on every platform
  (on Windows the real cmdlets exist and are mocked directly)
- Import-OSDBuilderPrivate returns the Private scripts, dot-source them in the test scope:
  foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
- New-TestAppx creates an .appx (zip with an AppxManifest.xml) for the Appx manifest tests
#>
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$FixturesPath = Join-Path $PSScriptRoot 'Fixtures'

#=================================================
#   Windows only commands
#   Defined only when the command does not exist, the parameters are the ones the module uses
#=================================================
$WindowsOnlyCommands = [ordered]@{
    'Add-WindowsPackage'                = 'param($Path, $PackagePath, $LogPath, [switch]$IgnoreCheck, [switch]$PreventPending)'
    'Get-WindowsPackage'                = 'param($Path, $PackageName, $PackagePath, $LogPath)'
    'Add-WindowsCapability'             = 'param($Path, $Name, [string[]]$Source, $LogPath, [switch]$LimitAccess)'
    'Get-WindowsCapability'             = 'param($Path, $Name, $LogPath, [switch]$LimitAccess)'
    'Enable-WindowsOptionalFeature'     = 'param($Path, $FeatureName, [switch]$All, [switch]$LimitAccess, [string[]]$Source, $LogPath)'
    'Get-WindowsOptionalFeature'        = 'param($Path, $FeatureName, $LogPath)'
    'Add-AppxProvisionedPackage'        = 'param($Path, $PackagePath, $LicensePath, [string[]]$DependencyPackagePath, [switch]$SkipLicense, $LogPath, $Regions)'
    'Get-AppxProvisionedPackage'        = 'param($Path, $LogPath)'
    'Remove-AppxProvisionedPackage'     = 'param($Path, $PackageName, $LogPath)'
    'Mount-DiskImage'                   = 'param($ImagePath, $StorageType, [switch]$PassThru)'
    'Dismount-DiskImage'                = 'param($ImagePath)'
    'Get-Volume'                        = 'param([Parameter(ValueFromPipeline = $true)]$DiskImage)'
    'Start-BitsTransfer'                = 'param($Source, $Destination, $DisplayName)'
    #OSD module (RequiredModules), not installed for the tests
    'Get-SessionsXml'                   = 'param($Path, $KBNumber)'
    'Test-WindowsPackageCAB'            = 'param($Path, $PackagePath)'
    'Get-RegCurrentVersion'             = 'param($Path, $Property)'
    'Get-WindowsUpdateManifests'        = 'param()'
}
foreach ($Name in $WindowsOnlyCommands.Keys) {
    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        $Body = "$($WindowsOnlyCommands[$Name]) throw '$Name is not available on this platform, mock it in the test'"
        Set-Item -Path "function:global:$Name" -Value ([scriptblock]::Create($Body))
    }
}

#OSDBuilder functions that only write the output header
if (-not (Get-Command -Name Show-ActionTime -ErrorAction SilentlyContinue)) {
    function global:Show-ActionTime {}
}

function Get-OSDBuilderPrivateScript {
    <#
    .SYNOPSIS
    Returns the Private scripts of the module, dot-source them in the test scope
    #>
    [CmdletBinding()]
    param (
        #File names without extension, all Private scripts when empty
        [string[]]$Name
    )
    $Scripts = Get-ChildItem -Path (Join-Path $RepoRoot 'Private') -Filter '*.ps1' -File | Sort-Object Name
    if ($Name) {$Scripts = $Scripts | Where-Object {$_.BaseName -in $Name}}
    $Scripts.FullName
}

function New-TestAppx {
    <#
    .SYNOPSIS
    Creates an .appx with an AppxManifest.xml for tests
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [string]$Architecture = 'neutral',

        #Windows.Desktop MinVersion, no TargetDeviceFamily when empty
        [string]$MinVersion,

        [string[]]$Dependency = @(),

        [switch]$Framework
    )
    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $DependencyXml = ''
    if ($MinVersion) {$DependencyXml += "<TargetDeviceFamily Name=`"Windows.Desktop`" MinVersion=`"$MinVersion`" MaxVersionTested=`"$MinVersion`" />"}
    foreach ($Item in $Dependency) {$DependencyXml += "<PackageDependency Name=`"$Item`" MinVersion=`"1.0.0.0`" />"}
    $FrameworkXml = if ($Framework) {'<Properties><Framework>true</Framework></Properties>'} else {'<Properties />'}
    $Manifest = '<?xml version="1.0" encoding="utf-8"?>' +
        '<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">' +
        "<Identity Name=`"$Name`" Publisher=`"CN=Microsoft Corporation`" Version=`"$Version`" ProcessorArchitecture=`"$Architecture`" />" +
        $FrameworkXml +
        "<Dependencies>$DependencyXml</Dependencies>" +
        '</Package>'

    $Parent = Split-Path -Path $Path -Parent
    if ($Parent -and !(Test-Path $Parent)) {New-Item -Path $Parent -ItemType Directory -Force | Out-Null}
    if (Test-Path $Path) {Remove-Item -Path $Path -Force}
    $Zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $Entry = $Zip.CreateEntry('AppxManifest.xml')
        $Writer = New-Object System.IO.StreamWriter($Entry.Open())
        try {$Writer.Write($Manifest)} finally {$Writer.Dispose()}
    }
    finally {
        $Zip.Dispose()
    }
    Get-Item -Path $Path
}

function New-TestFile {
    <#
    .SYNOPSIS
    Creates a file and its parent directories
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$Value = 'test'
    )
    $Parent = Split-Path -Path $Path -Parent
    if ($Parent -and !(Test-Path $Parent)) {New-Item -Path $Parent -ItemType Directory -Force | Out-Null}
    Set-Content -Path $Path -Value $Value
    Get-Item -Path $Path
}
