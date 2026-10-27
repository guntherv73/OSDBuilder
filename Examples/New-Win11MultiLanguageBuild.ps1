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

With -SetupLanguages the ISOs of these languages are imported (-SetupLanguageIso) and used as
LanguageCopySources: Windows Setup shows these display languages and the language selection of the image.

New-OSBuild then:
- adds the Language Packs, Language Interface Packs and Language Features, reapplies the LCU once
- adds the Local Experience Packs of the languages from Content\IsoExtract, the Local Experience Pack of a language
  without a .cab is downloaded from the Microsoft Store with winget (see README)
- adds the same languages to WinRE from the Languages and Optional Features ISO
- enables .NET Framework 3.5 (NetFx3) from the Languages and Optional Features ISO and applies the .NET CU (-SkipNetFX3 to skip)
- reinstalls the inbox apps from the Inbox Apps ISO so they include the language resources

Run in an elevated Windows PowerShell 5.1 session on Windows 10/11.
About 60 GB of free space are required on the OSDBuilder drive.

.EXAMPLE
.\New-Win11MultiLanguageBuild.ps1 -CustomerName 'Contoso' -SourceIso 'D:\ISO\Win11_25H2_x64.iso' -CreateISO

.EXAMPLE
.\New-Win11MultiLanguageBuild.ps1 -CustomerName 'Contoso' -SourceIso 'D:\ISO\Win11_25H2_English_x64.iso' -SetupLanguages 'de-DE','fr-FR' -SetupLanguageIso 'D:\ISO\Win11_25H2_German_x64.iso','D:\ISO\Win11_25H2_French_x64.iso' -SetupUILanguage 'de-DE'

.EXAMPLE
.\New-Win11MultiLanguageBuild.ps1 -CustomerName 'Contoso' -Languages 'en-US','de-DE' -DefaultLanguage 'de-DE' -RegionalFormat 'de-AT'
German display language with the Austrian regional format, system locale and keyboard

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
    [string[]]$Languages = @('en-US','de-DE','fr-FR','sv-SE','sk-SK','th-TH'),

    #Default language of Windows and WinRE (Dism /Set-AllIntl)
    [string]$DefaultLanguage = 'en-US',

    #Regional format, system locale and keyboard of the image (Dism /Set-UserLocale, /Set-SysLocale, /Set-InputLocale)
    #For regions without an own display language, for example 'de-AT' with -DefaultLanguage 'de-DE'
    #The individual settings take precedence over Set-AllIntl, the display language stays -DefaultLanguage
    [string]$RegionalFormat,

    #Language Features on Demand of each language, Fonts are added automatically when the language requires them
    [ValidateSet('Basic','Handwriting','OCR','TextToSpeech','Speech')]
    [string[]]$LanguageFeatures = @('Basic','Handwriting','OCR','TextToSpeech','Speech'),

    #Windows Capabilities (Features on Demand), for example 'Rsat.Dns.Tools~~~~0.0.1.0'
    [string[]]$AddWindowsCapability = @(),

    #ContentPacks of the Task, for example 'Contoso-Defaults', ContentPacks of an existing Task are replaced
    [string[]]$ContentPacks = @(),

    #Provisioned apps to remove, by DisplayName, for example 'Microsoft.BingNews','Microsoft.GamingApp'
    [string[]]$RemoveAppxDisplayName = @(),

    #.NET Framework 3.5 is enabled by default, -EnableNetFX3 is kept for compatibility
    [switch]$EnableNetFX3,

    #Do not enable .NET Framework 3.5
    [switch]$SkipNetFX3,

    [switch]$CreateISO,

    #Skip the download of the Languages and Optional Features and Inbox Apps ISOs
    [switch]$SkipContentDownload,

    #Language of -SourceIso (the language of the install.wim)
    [string]$MediaLanguage = 'en-US',

    #Additional Windows Setup display languages, for example 'de-DE','fr-FR'
    #Each language requires the Windows 11 ISO of that language (-SetupLanguageIso) for the localized Setup resources
    [string[]]$SetupLanguages = @(),

    #Windows 11 ISOs of the -SetupLanguages (same release and build), imported as OSMedia for LanguageCopySources
    [string[]]$SetupLanguageIso = @(),

    #Default Windows Setup display language (Dism /Set-SetupUILang)
    [string]$SetupUILanguage
)
$ErrorActionPreference = 'Stop'
if ($DefaultLanguage -notin $Languages) {throw "-DefaultLanguage $DefaultLanguage must be one of -Languages $($Languages -join ', ')"}
if ($EnableNetFX3 -and $SkipNetFX3) {throw "-EnableNetFX3 and -SkipNetFX3 cannot be used together, .NET Framework 3.5 is enabled by default"}
if ($RegionalFormat) {
    try {$RegionalFormat = ([System.Globalization.CultureInfo]::GetCultureInfo($RegionalFormat)).Name}
    catch {throw "-RegionalFormat $RegionalFormat is not a valid locale name"}
}
if (-not $SetupUILanguage) {$SetupUILanguage = $MediaLanguage}
if ($SetupUILanguage -notin (@($MediaLanguage) + $SetupLanguages)) {throw "-SetupUILanguage $SetupUILanguage must be -MediaLanguage $MediaLanguage or one of -SetupLanguages"}
#Microsoft: Language Interface Packs are not supported on Windows Setup
foreach ($Item in $SetupLanguages | Where-Object {$_ -in 'ca-ES','eu-ES','gl-ES','id-ID','vi-VN'}) {throw "-SetupLanguages $Item is a Language Interface Pack, LIPs are not supported by Windows Setup"}
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
function Get-ReleaseOSMedia ([string]$Language) {
    Get-OSMedia -OSMajorVersion 10 -Revision OK | `
        Where-Object {($_.OperatingSystem -eq 'Windows 11') -and ($_.ReleaseId -eq $ReleaseId) -and ($_.EditionId -eq $EditionId) -and ($_.Arch -eq 'x64')} | `
        Where-Object {(@($_.Languages).Count -eq 1) -and ("$($_.Languages)" -eq $Language)} | `
        Sort-Object -Property ModifiedTime -Descending | Select-Object -First 1
}
function Get-BuildOSMedia {Get-ReleaseOSMedia -Language $MediaLanguage}
function Import-IsoOSMedia ([string]$Iso) {
    $DiskImage = Mount-DiskImage -ImagePath $Iso -StorageType ISO -PassThru
    try {
        Start-Sleep -Seconds 2
        $DriveLetter = ($DiskImage | Get-Volume).DriveLetter
        Import-OSMedia -Path "$($DriveLetter):\" -EditionId $EditionId -SkipGrid -SkipFeatureUpdates
    }
    finally {
        Dismount-DiskImage -ImagePath $Iso | Out-Null
    }
}
$OSMedia = Get-BuildOSMedia
if (-not $OSMedia) {
    if (-not $SourceIso) {throw "No OSMedia for Windows 11 $EditionId x64 $ReleaseId $MediaLanguage was found, use -SourceIso to import it"}
    Import-IsoOSMedia -Iso $SourceIso
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
#=================================================
#   Windows Setup languages (LanguageCopySources)
#   The localized Setup resources are copied from an OSMedia of each language with the same build
#=================================================
$LanguageCopySources = @()
if ($SetupLanguages) {
    Write-Step "Windows Setup languages $($SetupLanguages -join ', ')"
    $MissingSetup = @($SetupLanguages | Where-Object {-not (Get-ReleaseOSMedia -Language $_)})
    if ($MissingSetup) {
        foreach ($Iso in $SetupLanguageIso) {Import-IsoOSMedia -Iso $Iso}
    }
    foreach ($Language in $SetupLanguages) {
        $SetupMedia = Get-ReleaseOSMedia -Language $Language
        if (-not $SetupMedia) {throw "No OSMedia for Windows 11 $EditionId x64 $ReleaseId $Language was found, add the $Language ISO to -SetupLanguageIso"}
        if ($SetupMedia.Build -ne $OSMedia.Build) {throw "$($SetupMedia.Name) has build $($SetupMedia.Build), $($OSMedia.Name) has build $($OSMedia.Build)"}
        Write-Host "$Language Setup resources from $($SetupMedia.Name)"
        $LanguageCopySources += $SetupMedia.OSMFamily
    }
}
Write-Step "5. Task content for $($Languages -join ', ')"
$ImageLanguages = @($OSMedia.Languages | ForEach-Object {"$_".ToLower()})
$LanguagePack = @(); $LanguageInterfacePack = @(); $LanguageFeature = @(); $LocalExperiencePack = @(); $Missing = @()

#Windows 11 publishes 43 languages as .cab on the Languages and Optional Features ISO, the other languages only as
#Local Experience Packs (.appx). LXPs are used from Content\IsoExtract\<directory with the ReleaseId>\LocalExperiencePack\<lang>
$ReleaseIds = if ($ReleaseGroup -eq '22H2-23H2') {@('22H2','23H2')} else {@('24H2','25H2','26H2')}
$IsoExtractPath = Join-Path $SetOSDBuilderPathContent 'IsoExtract'

#Languages without a .cab are downloaded from the Microsoft Store with winget (Microsoft Entra ID License Administrator)
$LxpLanguages = @($Languages | ForEach-Object {$_.ToLower()} | Sort-Object -Unique | Where-Object {
    ($_ -notin $ImageLanguages) -and
    !(Test-Path (Join-Path $LofPath "Microsoft-Windows-Client-Language-Pack_x64_$_.cab")) -and
    !(Test-Path (Join-Path $LofPath "Microsoft-Windows-Lip-Language-Pack_x64_$_.cab"))
})
if ($LxpLanguages -and -not $SkipContentDownload) {
    Write-Host "Local Experience Packs from the Microsoft Store: $($LxpLanguages -join ', ')" -ForegroundColor Cyan
    Save-OSDBuilderDownload -LocalExperiencePack $LxpLanguages -LocalExperiencePackRelease "Windows 11 $ReleaseGroup"
}
$LxpFiles = @(Get-ChildItem -Path $IsoExtractPath -Filter 'LanguageExperiencePack.*.appx' -File -Recurse -ErrorAction SilentlyContinue | `
    Where-Object {$_.Directory.Parent.Name -eq 'LocalExperiencePack'} | `
    Where-Object {$_.FullName -match "Windows 11 .*($($ReleaseIds -join '|'))"} | `
    Where-Object {Test-Path (Join-Path $_.DirectoryName 'License.xml')})

foreach ($Language in ($Languages | ForEach-Object {$_.ToLower()} | Sort-Object -Unique)) {
    #The Local Experience Pack in IsoExtract is added for every language, also for the language of the OSMedia and languages with a .cab
    $Lxp = $LxpFiles | Where-Object {$_.Name -eq "LanguageExperiencePack.$Language.Neutral.appx"} | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    #New-OSBuild expects the path relative to the Content directory
    if ($Lxp) {$LocalExperiencePack += $Lxp.FullName.Substring($SetOSDBuilderPathContent.TrimEnd('\', '/').Length + 1)}
    if ($Language -in $ImageLanguages) {
        Write-Host "$Language is the language of the OSMedia" -ForegroundColor DarkGray; Continue
    }
    $ClientLp = "Microsoft-Windows-Client-Language-Pack_x64_$Language.cab"
    $LipLp = "Microsoft-Windows-Lip-Language-Pack_x64_$Language.cab"
    if (Test-Path (Join-Path $LofPath $ClientLp)) {$LanguagePack += "$LofRelative\$ClientLp"}
    elseif (Test-Path (Join-Path $LofPath $LipLp)) {$LanguageInterfacePack += "$LofRelative\$LipLp"}
    elseif (-not $Lxp) {$Missing += $Language; Continue}

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
if ($Missing) {
    #Regions like de-AT, de-CH or fr-BE use the display language of de-DE or fr-FR and are set with -RegionalFormat
    $Hint = @($Missing | ForEach-Object {
        $Parent = $_.Split('-')[0]
        $ParentLp = @(Get-ChildItem -Path $LofPath -Filter "Microsoft-Windows-Client-Language-Pack_x64_$Parent-*.cab" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        if ($ParentLp) {"$_ is not a display language, use the display language $(($ParentLp | ForEach-Object {($_ -replace '^.*_x64_' -replace '\.cab$')}) -join ' or ') in -Languages and -RegionalFormat $_"}
    })
    throw "No Language Pack was found in $LofPath and no Local Experience Pack in $IsoExtractPath for: $($Missing -join ', '). $($Hint -join '. ')"
}
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
foreach ($Item in $LocalExperiencePack)     {Write-Host "LocalExperiencePack   $Item"}
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
if (-not $SkipNetFX3) {$TaskParams.EnableNetFX3 = $true}
if ($RegionalFormat) {
    $TaskParams.SetUserLocale   = $RegionalFormat
    $TaskParams.SetSysLocale    = $RegionalFormat
    #A locale name sets the default keyboard of the locale, de-AT: 0C07:00000407 (German keyboard)
    $TaskParams.SetInputLocale  = $RegionalFormat
}
New-OSBuildTask @TaskParams

$TaskPath = Join-Path $SetOSDBuilderPathTasks "OSBuild $MediaName.json"
if (!(Test-Path $TaskPath)) {throw "The Task $TaskPath was not created"}
$Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
$Task.CustomName                    = $ExportName
#New-OSBuildTask keeps the ContentPacks of an existing Task, the Task only uses the -ContentPacks of this script
$Task | Add-Member -NotePropertyName ContentPacks -NotePropertyValue ([string[]]$ContentPacks) -Force
$Task.LanguagePack                  = [string[]]$LanguagePack
$Task.LanguageInterfacePack         = [string[]]$LanguageInterfacePack
$Task | Add-Member -NotePropertyName LocalExperiencePacks -NotePropertyValue ([string[]]$LocalExperiencePack) -Force
$Task.LanguageFeature               = [string[]]$LanguageFeature
$Task.AddWindowsCapability          = [string[]]$AddWindowsCapability
$Task.RemoveAppxProvisionedPackage  = [string[]]$RemoveAppxPackageName
$Task.LanguageCopySources           = [string[]]$LanguageCopySources
if ($LanguageCopySources) {$Task.LangSetSetupUILang = $SetupUILanguage}
$Task.EnableNetFX3                  = [string](-not $SkipNetFX3)
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
