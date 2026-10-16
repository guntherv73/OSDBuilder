function ConvertTo-OSDBuilderLanguageTag {
    <#
    .SYNOPSIS
    Converts a lowercase language tag from a package file name to the casing used in capability names
    de-de -> de-DE, sr-latn-rs -> sr-Latn-RS, chr-cher-us -> chr-Cher-US
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Tag
    )
    $Parts = $Tag.ToLower() -split '-'
    $Result = for ($i = 0; $i -lt $Parts.Count; $i++) {
        $Part = $Parts[$i]
        if ($i -eq 0) {$Part}
        elseif ($Part.Length -eq 4) {$Part.Substring(0,1).ToUpper() + $Part.Substring(1)}
        elseif (($Part.Length -eq 2) -or ($Part -match '^\d{3}$')) {$Part.ToUpper()}
        else {$Part}
    }
    $Result -join '-'
}
function Get-OSDBuilderLanguageCapabilityName {
    <#
    .SYNOPSIS
    Returns the capability name of a Language Feature on Demand package, or $null
    https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-language-fod

    .EXAMPLE
    Microsoft-Windows-LanguageFeatures-Basic-fr-fr-Package~31bf3856ad364e35~amd64~~.cab -> Language.Basic~~~fr-FR~0.0.1.0
    Microsoft-Windows-LanguageFeatures-Fonts-Thai-Package~31bf3856ad364e35~amd64~~.cab -> Language.Fonts.Thai~~~und-THAI~0.0.1.0
    Microsoft-Windows-RetailDemo-OfflineContent-Content-fr-fr-Package~31bf3856ad364e35~amd64~~.cab -> Language.RetailDemo~~~fr-FR~0.0.1.0
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    $Leaf = ($Name -split '[\\/]')[-1]

    if ($Leaf -match '^Microsoft-Windows-LanguageFeatures-Fonts-(?<Script>[A-Za-z]+)-Package~') {
        $Script = $Matches['Script']
        Return "Language.Fonts.$Script~~~und-$($Script.ToUpper())~0.0.1.0"
    }
    if ($Leaf -match '^Microsoft-Windows-LanguageFeatures-(?<Type>Basic|Handwriting|OCR|Speech|TextToSpeech)-(?<Lang>[a-z]{2,3}(-[a-z0-9]{2,4}){1,2})-Package~') {
        Return "Language.$($Matches['Type'])~~~$(ConvertTo-OSDBuilderLanguageTag -Tag $Matches['Lang'])~0.0.1.0"
    }
    if ($Leaf -match '^Microsoft-Windows-RetailDemo-OfflineContent-Content-(?<Lang>[a-z]{2,3}(-[a-z0-9]{2,4}){1,2})-Package~') {
        Return "Language.RetailDemo~~~$(ConvertTo-OSDBuilderLanguageTag -Tag $Matches['Lang'])~0.0.1.0"
    }
    Return $null
}
function Get-OSDBuilderCapabilitySource {
    <#
    .SYNOPSIS
    Returns the Features on Demand repositories in Content\IsoExtract that match the OSMedia
    A repository is a directory with a metadata directory, like LanguagesAndOptionalFeatures on the
    Windows 11 Languages and Optional Features ISO or the root of the Windows 10 Features on Demand ISO
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $OSMedia
    )
    if (-not $GetOSDBuilderPathContentIsoExtract) {Return}
    if (!(Test-Path $GetOSDBuilderPathContentIsoExtract)) {Return}

    $Repositories = Get-ChildItem -Path $GetOSDBuilderPathContentIsoExtract -Directory -Recurse -Filter 'metadata' -ErrorAction SilentlyContinue | ForEach-Object {$_.Parent.FullName}
    $Repositories = $Repositories | Where-Object {$_ -match (Get-OSDBuilderLanguageReleasePattern -OSMedia $OSMedia)}
    $Repositories = $Repositories | Where-Object {$_ -notmatch (Get-OSDBuilderLanguageExcludePattern -OSMedia $OSMedia)}
    $Repositories = $Repositories | Where-Object {$_ -notlike '*\arm64\*' -and $_ -notlike '*\x86\*'}
    if ($OSMedia.InstallationType -eq 'Client') {$Repositories = $Repositories | Where-Object {$_ -notlike '*Windows Server*'}}
    if ($OSMedia.InstallationType -like '*Server*') {$Repositories = $Repositories | Where-Object {$_ -like '*Windows Server*'}}
    $Repositories | Sort-Object -Unique
}
function Add-OSDBuilderWindowsCapability {
    <#
    .SYNOPSIS
    Adds a capability to the mounted Windows image from local repositories only
    Returns $true when the capability is installed
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string[]]$Source,

        [string]$LogPath
    )
    $Source = @($Source | Where-Object {$_} | Where-Object {Test-Path $_} | Sort-Object -Unique)
    if ($Source.Count -eq 0) {
        Write-Warning "Add-WindowsCapability: No Features on Demand repository for $Name"
        Return $false
    }

    $Params = @{
        Path        = $Path
        Name        = $Name
        Source      = $Source
        ErrorAction = 'Stop'
    }
    if ($LogPath) {$Params.LogPath = $LogPath}
    #LimitAccess prevents DISM from contacting Windows Update for the source files
    if ((Get-Command -Name Add-WindowsCapability).Parameters.ContainsKey('LimitAccess')) {$Params.LimitAccess = $true}

    try {
        Add-WindowsCapability @Params | Out-Null
        Return $true
    }
    catch {
        if ($_.Exception.Message -match '0x800f081f') {Write-Verbose "OSDBuilder: 0x800f081f The source files could not be found for $Name" -Verbose}
        elseif ($_.Exception.Message -match '0x800f081e') {Write-Verbose "OSDBuilder: 0x800f081e $Name is not applicable to this image" -Verbose}
        else {Write-Verbose "OSDBuilder: $($_.Exception.Message)" -Verbose}
        if ($LogPath) {Write-Verbose "$LogPath" -Verbose}
        Return $false
    }
}
