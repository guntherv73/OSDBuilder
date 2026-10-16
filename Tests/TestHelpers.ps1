<#
.SYNOPSIS
Shared test setup, dot-source it in the BeforeAll block of every *.Tests.ps1 file

.DESCRIPTION
- $RepoRoot and $FixturesPath
- Placeholder commands for the Windows only cmdlets, the OSD module commands and Windows programs, so Pester can mock them
  on every platform (on Windows the real cmdlets exist and are mocked directly)
- Import-OSDBuilderPrivate returns the Private scripts, dot-source them in the test scope:
  foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
- New-TestAppx creates an .appx (zip with an AppxManifest.xml) for the Appx manifest tests
#>
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$FixturesPath = Join-Path $PSScriptRoot 'Fixtures'

#=================================================
#   Commands that are not available on every platform
#   Windows only cmdlets (DISM, Appx, Storage, Hyper-V, BITS, Out-GridView), OSD module commands and Windows programs
#   A placeholder is defined only when the command does not exist, so Pester can mock it on Windows, macOS and Linux
#   The parameters are the ones the module uses, so -ParameterFilter works on every platform
#   Every placeholder accepts pipeline input ($InputObject) and positional arguments ($RemainingArguments)
#=================================================
$PlaceholderCommands = [ordered]@{
    'Add-AppxProvisionedPackage' = '$DependencyPackagePath, $LicensePath, $LogPath, $PackagePath, $Path, $Regions, [switch]$SkipLicense'
    'Add-PartitionAccessPath' = '[switch]$AssignDriveLetter, $DiskNumber, $PartitionNumber'
    'Add-WindowsCapability' = '[switch]$LimitAccess, $LogPath, $Name, $Path, $Source'
    'Add-WindowsDriver' = '$Driver, [switch]$ForceUnsigned, $LogPath, $Path, [switch]$Recurse'
    'Add-WindowsPackage' = '[switch]$IgnoreCheck, $LogPath, $PackagePath, $Path, [switch]$PreventPending'
    'Add-WindowsPackageSSU' = '$LogPath, $PackagePath, $Path'
    'Block-NoCurl' = ''
    'Block-PowerShellVersionLt5' = ''
    'Block-StandardUser' = ''
    'Block-WindowsVersionNe10' = ''
    'Block-WinPE' = ''
    'Clear-Disk' = '$Confirm, [switch]$PassThru, [switch]$RemoveData, [switch]$RemoveOEM'
    'Disable-WindowsOptionalFeature' = '$FeatureName, $LogPath, $Path'
    'Dismount-DiskImage' = '$ImagePath'
    'Dismount-WindowsImage' = '[switch]$Discard, $LogPath, $Path, [switch]$Save'
    'Enable-PEWindowsImagePSGallery' = '$Path'
    'Enable-WindowsOptionalFeature' = '[switch]$All, $FeatureName, [switch]$LimitAccess, $LogPath, $Path, $Source'
    'Expand-WindowsImage' = '$ApplyPath, $ImagePath, $Index'
    'Export-WindowsImage' = '[switch]$CheckIntegrity, $CompressionType, $DestinationImagePath, $DestinationName, $LogPath, [switch]$Setbootable, $SourceImagePath, $SourceIndex'
    'Format-Volume' = '$Confirm, $FileSystem, $NewFileSystemLabel'
    'Get-AdkPaths' = '$Arch'
    'Get-AppxProvisionedPackage' = '$Path'
    'Get-Disk' = ''
    'Get-DiskImage' = '$ImagePath'
    'Get-OSDCatalogIntelWirelessDriver' = ''
    'Get-OSDCloudOperatingSystems' = '$OSArch'
    'Get-Partition' = '$DiskNumber, $PartitionNumber'
    'Get-PartitionSupportedSize' = '$DiskNumber, $PartitionNumber'
    'Get-RegCurrentVersion' = '$Path, $Property'
    'Get-SessionsXml' = '$KBNumber, $Path'
    'Get-Volume' = ''
    'Get-WindowsCapability' = '[switch]$LimitAccess, $Name, $Path'
    'Get-WindowsImage' = '$ImagePath, $Index, [switch]$Mounted'
    'Get-WindowsImageContent' = '$ImagePath, $Index'
    'Get-WindowsOptionalFeature' = '$FeatureName, $Path'
    'Get-WindowsPackage' = '$PackageName, $PackagePath, $Path'
    'Get-WindowsUpdateManifests' = ''
    'Initialize-Disk' = '$Number, $PartitionStyle'
    'Mount-DiskImage' = '$ImagePath, [switch]$PassThru, $StorageType'
    'Mount-WindowsImage' = '$ImagePath, $Index, $LogPath, $Path, [switch]$ReadOnly'
    'New-Partition' = '[switch]$AssignDriveLetter, $DiskNumber, $GptType, [switch]$IsActive, $Size, [switch]$UseMaximumSize'
    'New-VHD' = '[switch]$Dynamic, $Path, $SizeBytes'
    'Out-GridView' = '$OutputMode, [switch]$PassThru, $Title'
    'Remove-AppxProvisionedPackage' = '$LogPath, $PackageName, $Path'
    'Remove-WindowsCapability' = '$LogPath, $Name, $Path'
    'Remove-WindowsPackage' = '$LogPath, $PackageName, $Path'
    'Resize-Partition' = '$DiskNumber, $PartitionNumber, $Size'
    'Save-WebFile' = '$SourceUrl'
    'Save-WindowsImage' = '$LogPath, $Path'
    'Set-WindowsImageExecutionPolicy' = '$ExecutionPolicy, $Path'
    'Start-BitsTransfer' = '$Destination, $DisplayName, $Source'
    'Test-WebConnection' = '$Uri'
    'Test-WindowsPackageCAB' = '$PackagePath, $Path'
    'Use-WindowsUnattend' = '$LogPath, $Path, $UnattendPath'
}
#Windows programs, called with positional arguments, always replaced in the tests
$PlaceholderPrograms = @(
    'bootsect.exe', 'cmd', 'curl.exe', 'dism', 'expand.exe', 'robocopy'
)
foreach ($Name in @($PlaceholderCommands.Keys) + $PlaceholderPrograms) {
    #Windows programs are always replaced, a test never starts robocopy or dism, functions are found before programs
    if (($Name -notin $PlaceholderPrograms) -and (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {Continue}
    $Parameters = @()
    if ($PlaceholderCommands.Contains($Name) -and $PlaceholderCommands[$Name]) {$Parameters += $PlaceholderCommands[$Name]}
    $Parameters += '[Parameter(ValueFromPipeline = $true)]$InputObject'
    $Parameters += '[Parameter(ValueFromRemainingArguments = $true)]$RemainingArguments'
    $Body = "[CmdletBinding()] param ($($Parameters -join ', ')) process {throw '$Name is not available on this platform, mock it in the test'}"
    Set-Item -Path "function:global:$Name" -Value ([scriptblock]::Create($Body))
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
