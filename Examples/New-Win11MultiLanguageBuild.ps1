<#
.SYNOPSIS
Creates a fully patched multi-language Windows 11 image with OSDBuilder

.DESCRIPTION
Unattended end-to-end build:
1. Downloads the Windows 11 Languages and Optional Features ISO and the Inbox Apps ISO
2. Imports the Windows 11 edition from an ISO (only when no OSMedia of this release exists)
3. Updates the OSMedia with the latest LCU, .NET CU, Safe OS DU and Setup DU
4. Creates the OSBuild Task with the Language Packs, Language Features and Windows Capabilities
   of the selected languages (no Out-GridView)
5. Runs New-OSBuild

New-OSBuild then:
- adds the Language Packs, Language Interface Packs and Language Features, reapplies the LCU once
- adds the same languages to WinRE from the Languages and Optional Features ISO
- reinstalls the inbox apps from the Inbox Apps ISO so they include the language resources

Run in an elevated Windows PowerShell 5.1 session on Windows 10/11.
About 60 GB of free space are required on the OSDBuilder drive.

.EXAMPLE
.\New-Win11MultiLanguageBuild.ps1 -CustomerName 'Contoso' -SourceIso 'D:\ISO\Win11_25H2_x64.iso' -EnableNetFX3 -CreateISO

.EXAMPLE
.\New-Win11MultiLanguageBuild.ps1 -CustomerName 'Contoso' -Languages 'en-US','de-DE','fr-FR' -DefaultLanguage 'de-DE' -AddWindowsCapability 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param (
    #Prefix of the Task and OSBuild name
    [Parameter(Mandatory = $true)]
    [string]$CustomerName,

    #OSDBuilder module manifest of this repository
    [string]$OSDBuilderModule = (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDBuilder.psd1'),

    #OSDBuilder home directory
    [string]$OSDBuilderHome = 'G:\OSDBuilder',

    #Windows 11 ISO, only required when no OSMedia of the release and edition exists yet
    [string]$SourceIso,

    [ValidateSet('22H2','23H2','24H2','25H2','26H2')]
    [string]$ReleaseId = '25H2',

    [string]$EditionId = 'Enterprise',

    #Languages of the image, the first language of the OSMedia (usually en-US) is already installed
    #Englisch, Deutsch, Franzoesisch, Schwedisch, Russisch, Slowakisch, Thailaendisch
    [string[]]$Languages = @('en-US','de-DE','fr-FR','sv-SE','ru-RU','sk-SK','th-TH'),

    #Default language of Windows and WinRE (Dism /Set-AllIntl)
    [string]$DefaultLanguage = 'en-US',

    #Language Features on Demand of each language, Fonts are added automatically when the language requires them
    [ValidateSet('Basic','Handwriting','OCR','TextToSpeech','Speech')]
    [string[]]$LanguageFeatures = @('Basic','Handwriting','OCR','TextToSpeech','Speech'),

    #Windows Capabilities (Features on Demand), for example 'Rsat.Dns.Tools~~~~0.0.1.0'
    [string[]]$AddWindowsCapability = @(),

    #Provisioned apps to remove, by DisplayName, for example 'Microsoft.BingNews','Microsoft.GamingApp'
    [string[]]$RemoveAppxDisplayName = @(),

    [switch]$EnableNetFX3,

    [switch]$CreateISO,

    #Skip the download of the Languages and Optional Features and Inbox Apps ISOs
    [switch]$SkipContentDownload
)
$ErrorActionPreference = 'Stop'
if ($DefaultLanguage -notin $Languages) {throw "-DefaultLanguage $DefaultLanguage must be one of -Languages $($Languages -join ', ')"}
#=================================================
#   Names
#=================================================
$BaseName       = "Windows 11 $($EditionId.Substring(0,[math]::Min(3,$EditionId.Length))) x64 $ReleaseId"
$BuildDate      = (Get-Date).ToString('yyyy-MM')
$MediaName      = "$CustomerName-$BaseName - MUI"
$ExportName     = "$CustomerName-$BaseName - MUI - $BuildDate"
$ReleaseGroup   = if ($ReleaseId -in '22H2','23H2') {'22H2-23H2'} else {'24H2-26H2'}
$LofName        = "Windows 11 $ReleaseGroup x64 Languages and Optional Features"
$InboxAppsName  = "Windows 11 $ReleaseGroup Inbox Apps"

#Language Font Features on Demand required by a language
#https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-language-fod
$FontScript = @{
    'am-et' = 'Ethi'; 'ar-sa' = 'Arab'; 'as-in' = 'Beng'; 'bn-bd' = 'Beng'; 'bn-in' = 'Beng'; 'chr-cher-us' = 'Cher'
    'fa-ir' = 'Arab'; 'gu-in' = 'Gujr'; 'he-il' = 'Hebr'; 'hi-in' = 'Deva'; 'ja-jp' = 'Jpan'; 'km-kh' = 'Khmr'
    'kn-in' = 'Knda'; 'kok-in' = 'Deva'; 'ko-kr' = 'Kore'; 'ku-arab-iq' = 'Arab'; 'lo-la' = 'Laoo'; 'ml-in' = 'Mlym'
    'mr-in' = 'Deva'; 'ne-np' = 'Deva'; 'or-in' = 'Orya'; 'pa-arab-pk' = 'Arab'; 'pa-in' = 'Guru'; 'prs-af' = 'Arab'
    'sd-arab-pk' = 'Arab'; 'si-lk' = 'Sinh'; 'ta-in' = 'Taml'; 'te-in' = 'Telu'; 'th-th' = 'Thai'; 'ti-et' = 'Ethi'
    'ug-cn' = 'Arab'; 'ur-pk' = 'Arab'; 'zh-cn' = 'Hans'; 'zh-tw' = 'Hant'
}

function Write-Step ([string]$Message) {
    Write-Host '========================================================================================' -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor Green
}
#=================================================
#   1. OSDBuilder
#=================================================
Write-Step "1. Import OSDBuilder $OSDBuilderModule"
Import-Module $OSDBuilderModule -Force
Get-OSDBuilder -SetHome $OSDBuilderHome -CreatePaths -HideDetails
$ErrorActionPreference = 'Continue'
#=================================================
#   2. Languages and Optional Features, Inbox Apps
#=================================================
if (-not $SkipContentDownload) {
    Write-Step "2. Download $LofName and $InboxAppsName"
    Save-OSDBuilderDownload -ContentDownload $LofName
    Save-OSDBuilderDownload -ContentDownload $InboxAppsName
}
$LofRelative = "IsoExtract\$LofName\LanguagesAndOptionalFeatures"
$LofPath = Join-Path $SetOSDBuilderPathContent $LofRelative
if (!(Test-Path $LofPath)) {
    throw "The Languages and Optional Features ISO was not found in $LofPath, run the script without -SkipContentDownload"
}
#=================================================
#   3. OSMedia
#=================================================
Write-Step "3. OSMedia Windows 11 $EditionId x64 $ReleaseId"
function Get-BuildOSMedia {
    Get-OSMedia -OSMajorVersion 10 -Revision OK | `
        Where-Object {($_.OperatingSystem -eq 'Windows 11') -and ($_.ReleaseId -eq $ReleaseId) -and ($_.EditionId -eq $EditionId) -and ($_.Arch -eq 'x64')} | `
        Sort-Object -Property ModifiedTime -Descending | Select-Object -First 1
}
$OSMedia = Get-BuildOSMedia
if (-not $OSMedia) {
    if (-not $SourceIso) {throw "No OSMedia for Windows 11 $EditionId x64 $ReleaseId was found, use -SourceIso to import it"}
    $DiskImage = Mount-DiskImage -ImagePath $SourceIso -StorageType ISO -PassThru
    try {
        Start-Sleep -Seconds 2
        $DriveLetter = ($DiskImage | Get-Volume).DriveLetter
        Import-OSMedia -Path "$($DriveLetter):\" -EditionId $EditionId -SkipGrid -SkipFeatureUpdates
    }
    finally {
        Dismount-DiskImage -ImagePath $SourceIso | Out-Null
    }
    $OSMedia = Get-BuildOSMedia
    if (-not $OSMedia) {throw "Import-OSMedia did not create an OSMedia for Windows 11 $EditionId x64 $ReleaseId"}
}
Write-Host "OSMedia: $($OSMedia.Name)"
#=================================================
#   4. Update OSMedia
#=================================================
Write-Step "4. Update-OSMedia $($OSMedia.Name)"
Update-OSMedia -Name $OSMedia.Name -Download -Execute -HideCleanupProgress
$OSMedia = Get-BuildOSMedia
Write-Host "OSMedia: $($OSMedia.Name)"
#=================================================
#   5. Task content
#=================================================
Write-Step "5. Task content for $($Languages -join ', ')"
$ImageLanguages = @($OSMedia.Languages | ForEach-Object {"$_".ToLower()})
$LanguagePack = @(); $LanguageInterfacePack = @(); $LanguageFeature = @(); $Missing = @()

foreach ($Language in ($Languages | ForEach-Object {$_.ToLower()} | Sort-Object -Unique)) {
    if ($Language -in $ImageLanguages) {
        Write-Host "$Language is the language of the OSMedia" -ForegroundColor DarkGray; Continue
    }
    $ClientLp = "Microsoft-Windows-Client-Language-Pack_x64_$Language.cab"
    $LipLp = "Microsoft-Windows-Lip-Language-Pack_x64_$Language.cab"
    if (Test-Path (Join-Path $LofPath $ClientLp)) {$LanguagePack += "$LofRelative\$ClientLp"}
    elseif (Test-Path (Join-Path $LofPath $LipLp)) {$LanguageInterfacePack += "$LofRelative\$LipLp"}
    else {$Missing += $Language; Continue}

    $Types = @($LanguageFeatures)
    foreach ($Type in $Types) {
        $Cab = "Microsoft-Windows-LanguageFeatures-$Type-$Language-Package~31bf3856ad364e35~amd64~~.cab"
        if (Test-Path (Join-Path $LofPath $Cab)) {$LanguageFeature += "$LofRelative\$Cab"}
        else {Write-Host "$Language does not have the $Type Language Feature" -ForegroundColor DarkGray}
    }
    #Basic is required by all other Language Features
    if (($LanguageFeatures.Count -gt 0) -and ('Basic' -notin $LanguageFeatures)) {
        $Cab = "Microsoft-Windows-LanguageFeatures-Basic-$Language-Package~31bf3856ad364e35~amd64~~.cab"
        if (Test-Path (Join-Path $LofPath $Cab)) {$LanguageFeature += "$LofRelative\$Cab"}
    }
    if ($FontScript.ContainsKey($Language)) {
        $Cab = "Microsoft-Windows-LanguageFeatures-Fonts-$($FontScript[$Language])-Package~31bf3856ad364e35~amd64~~.cab"
        if (Test-Path (Join-Path $LofPath $Cab)) {$LanguageFeature += "$LofRelative\$Cab"}
    }
}
if ($Missing) {throw "No Language Pack was found in $LofPath for: $($Missing -join ', ')"}
$LanguageFeature = @($LanguageFeature | Sort-Object -Unique)

$RemoveAppxPackageName = @()
if ($RemoveAppxDisplayName) {
    $AppxXml = Join-Path $OSMedia.FullName 'info\xml\Get-AppxProvisionedPackage.xml'
    $RemoveAppxPackageName = @(Import-Clixml $AppxXml | Where-Object {$_.DisplayName -in $RemoveAppxDisplayName} | Select-Object -ExpandProperty PackageName)
    $NotFound = @($RemoveAppxDisplayName | Where-Object {$_ -notin (Import-Clixml $AppxXml).DisplayName})
    foreach ($Item in $NotFound) {Write-Warning "$Item is not provisioned in $($OSMedia.Name)"}
}

foreach ($Item in $LanguagePack)            {Write-Host "LanguagePack          $Item"}
foreach ($Item in $LanguageInterfacePack)   {Write-Host "LanguageInterfacePack $Item"}
foreach ($Item in $LanguageFeature)         {Write-Host "LanguageFeature       $Item"}
foreach ($Item in $AddWindowsCapability)    {Write-Host "WindowsCapability     $Item"}
foreach ($Item in $RemoveAppxPackageName)   {Write-Host "RemoveAppx            $Item"}
#=================================================
#   6. OSBuild Task
#=================================================
Write-Step "6. New-OSBuildTask $MediaName"
$TaskParams = @{
    TaskName    = $MediaName
    CustomName  = $ExportName
    OSMedia     = $OSMedia
    SetAllIntl  = $DefaultLanguage
}
if ($EnableNetFX3) {$TaskParams.EnableNetFX3 = $true}
New-OSBuildTask @TaskParams

$TaskPath = Join-Path $SetOSDBuilderPathTasks "OSBuild $MediaName.json"
if (!(Test-Path $TaskPath)) {throw "The Task $TaskPath was not created"}
$Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
$Task.CustomName                    = $ExportName
$Task.LanguagePack                  = [string[]]$LanguagePack
$Task.LanguageInterfacePack         = [string[]]$LanguageInterfacePack
$Task.LanguageFeature               = [string[]]$LanguageFeature
$Task.AddWindowsCapability          = [string[]]$AddWindowsCapability
$Task.RemoveAppxProvisionedPackage  = [string[]]$RemoveAppxPackageName
$Task | ConvertTo-Json | Out-File -FilePath $TaskPath
Write-Host "Task: $TaskPath"
#=================================================
#   7. OSBuild
#=================================================
Write-Step "7. New-OSBuild $MediaName"
$BuildParams = @{
    ByTaskName          = $MediaName
    Download            = $true
    Execute             = $true
    HideCleanupProgress = $true
}
if ($CreateISO) {$BuildParams.CreateISO = $true}
New-OSBuild @BuildParams
#=================================================
#   Result
#=================================================
Write-Step "Complete"
Get-OSBuilds | Where-Object {$_.Name -like "$ExportName*"} | Sort-Object ModifiedTime -Descending | Select-Object -First 1 | Format-List Name, ReleaseId, UBR, Languages, FullName
