function Get-OSDBuilderLanguageFromPackage {
    <#
    .SYNOPSIS
    Returns the language of a Windows Language Pack or Language Interface Pack .cab, or $null
    Microsoft-Windows-Client-Language-Pack_x64_de-de.cab -> de-de
    Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab -> ca-es
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    $Leaf = ($Name -split '[\\/]')[-1]
    if ($Leaf -match 'Language-(Interface-)?Pack_(x64|x86|amd64|arm64)_(?<Lang>[a-z]{2,3}(-[a-z0-9]{2,4}){1,2})\.cab$') {
        Return $Matches['Lang'].ToLower()
    }
    Return $null
}
function Get-OSDBuilderWinPELanguageSource {
    <#
    .SYNOPSIS
    Returns the WinPE_OCs directories of the Languages and Optional Features ISOs in Content\IsoExtract that match the OSMedia
    Microsoft: WinRE language packs are distributed on the Languages and Optional Features ISO,
    don't use the WinPE language packs that ship with the ADK
    https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/languages-overview
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $OSMedia,

        [string]$Architecture = 'x64'
    )
    if (-not $GetOSDBuilderPathContentIsoExtract) {Return}
    if (!(Test-Path $GetOSDBuilderPathContentIsoExtract)) {Return}

    $ArchFolders = @($Architecture)
    if ($Architecture -eq 'x64') {$ArchFolders += 'amd64'}

    Get-ChildItem -Path $GetOSDBuilderPathContentIsoExtract -Directory -Recurse -Filter 'WinPE_OCs' -ErrorAction SilentlyContinue | `
        Where-Object {$_.Parent.Parent.Name -eq 'Windows Preinstallation Environment'} | `
        Where-Object {$_.Parent.Name -in $ArchFolders} | `
        Where-Object {$_.FullName -match (Get-OSDBuilderLanguageReleasePattern -OSMedia $OSMedia)} | `
        Where-Object {$_.FullName -notmatch (Get-OSDBuilderLanguageExcludePattern -OSMedia $OSMedia)} | `
        Select-Object -ExpandProperty FullName
}
function Get-OSDBuilderContentPackLanguages {
    <#
    .SYNOPSIS
    Returns the languages of the Language Packs in the OSLanguagePacks ContentPacks of the Task
    #>
    [CmdletBinding()]
    param ()
    if (Get-IsTemplatesEnabled) {Return}
    if ($SkipContentPacks -eq $true) {Return}
    foreach ($ContentPack in $ContentPacks) {
        $ContentPackPath = Join-Path $SetOSDBuilderPathContentPacks "$ContentPack\OSLanguagePacks"
        $ContentPackContent = Resolve-OSDBuilderContentPackReleasePath -Path $ContentPackPath
        Get-ChildItem -Path "$ContentPackContent\*" -Include *.cab -File -ErrorAction SilentlyContinue | ForEach-Object {Get-OSDBuilderLanguageFromPackage -Name $_.Name}
    }
}
function Add-OSDBuilderWinPELanguagePacks {
    <#
    .SYNOPSIS
    Adds languages to a mounted WinPE based image (WinRE, WinSE)
    lp.cab first, then the language pack of each optional component in the image, then the font support
    The language content is read from the first Source that contains <language>\lp.cab
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$MountPath,

        [Parameter(Mandatory = $true)]
        [string[]]$Languages,

        [Parameter(Mandatory = $true)]
        [string[]]$Sources,

        #Name used in the output and the log file names
        [Parameter(Mandatory = $true)]
        [string]$ImageName,

        #Optional components that are not language specific
        [string[]]$ExcludeOptionalComponents = @('WinPE-WiFi'),

        #Optional components whose language pack is always added
        [string[]]$RequiredOptionalComponents = @(),

        #Microsoft: add WinPE-FontSupport-WinRE for Thai to Windows Setup
        [switch]$ThaiFontSupport
    )
    foreach ($Language in ($Languages | ForEach-Object {$_.ToLower()} | Sort-Object -Unique)) {
        $Source = $Sources | Where-Object {Test-Path (Join-Path (Join-Path $_ $Language) 'lp.cab')} | Select-Object -First 1
        if (-not $Source) {
            Write-Warning "$($ImageName): $Language is not available in $($Sources -join ', ')"; Continue
        }
        $LanguageSource = Join-Path $Source $Language
        $Installed = @(Get-WindowsPackage -Path "$MountPath" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PackageName)
        #The Languages and Optional Features ISO uses lowercase file names, the lookup ignores the case
        $LanguageFiles = @{}
        Get-ChildItem -Path $LanguageSource -File -Filter *.cab -ErrorAction SilentlyContinue | ForEach-Object {$LanguageFiles[$_.Name.ToLower()] = $_.FullName}
        $SourceFiles = @{}
        foreach ($Item in $Sources) {
            Get-ChildItem -Path $Item -File -Filter *.cab -ErrorAction SilentlyContinue | ForEach-Object {
                if (-not $SourceFiles.ContainsKey($_.Name.ToLower())) {$SourceFiles[$_.Name.ToLower()] = $_.FullName}
            }
        }

        #Base language pack first, then the language pack of each optional component
        $Cabs = @()
        if (-not ($Installed | Where-Object {$_ -match "LanguagePack-Package~31bf3856ad364e35~[^~]+~$([regex]::Escape($Language))~"})) {
            $Cabs += $LanguageFiles['lp.cab']
        }
        $OptionalComponents = @($Installed | ForEach-Object {
            if ($_ -match '^(?<Name>WinPE-[^~]+)-Package~31bf3856ad364e35~[^~]+~~') {$Matches['Name']}
        }) + @($RequiredOptionalComponents)
        $OptionalComponents = $OptionalComponents | Where-Object {$_ -and ($_ -notin $ExcludeOptionalComponents)} | Sort-Object -Unique
        foreach ($Name in $OptionalComponents) {
            if ($Installed | Where-Object {$_ -match "^$([regex]::Escape($Name))-Package~31bf3856ad364e35~[^~]+~$([regex]::Escape($Language))~"}) {Continue}
            $Cab = $LanguageFiles["$($Name)_$($Language).cab".ToLower()]
            if ($Cab) {$Cabs += $Cab}
            elseif ($Name -in $RequiredOptionalComponents) {Write-Warning "$($ImageName): $($Name)_$($Language).cab was not found in $LanguageSource"}
        }
        #Font support for Japan, Korea and China
        $FontSupport = $SourceFiles["winpe-fontsupport-$($Language).cab"]
        if ($FontSupport -and (-not ($Installed | Where-Object {$_ -match "^WinPE-FontSupport-$([regex]::Escape($Language))-Package"}))) {$Cabs += $FontSupport}
        #Font support for Thai
        if ($ThaiFontSupport.IsPresent -and ($Language -eq 'th-th') -and (-not ($Installed | Where-Object {$_ -match '^WinPE-FontSupport-WinRE-Package'}))) {
            if ($SourceFiles['winpe-fontsupport-winre.cab']) {$Cabs += $SourceFiles['winpe-fontsupport-winre.cab']}
            else {Write-Warning "$($ImageName): WinPE-FontSupport-WinRE.cab for th-TH was not found, it is part of the ADK WinPE_OCs"}
        }

        if ($Cabs.Count -eq 0) {
            Write-Host -ForegroundColor Gray "INSTALLED         $Language"; Continue
        }
        foreach ($Cab in $Cabs) {
            Write-Host -ForegroundColor Cyan "INSTALLING        " -NoNewline
            Write-Host -ForegroundColor Gray "$Language $(Split-Path $Cab -Leaf)"
            $CurrentLog = "$PEInfo\logs\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Add-LanguagePacks$($ImageName)-$Language.log"
            Try {Add-WindowsPackage -Path "$MountPath" -PackagePath "$Cab" -LogPath "$CurrentLog" | Out-Null}
            Catch {
                if ($_.Exception.Message -match '0x800f081e') {Write-Verbose "OSDBuilder: 0x800f081e The package is not applicable to this image" -Verbose}
                Write-Verbose "OSDBuilder: Review the log for more information" -Verbose
                Write-Verbose "$CurrentLog" -Verbose
            }
        }
    }
}
function Add-LanguagePacksWinRE {
    <#
    .SYNOPSIS
    Adds the Languages of the Windows image to WinRE from the Languages and Optional Features ISO

    .DESCRIPTION
    Microsoft: add the base language pack (lp.cab) and the language pack of each Windows PE optional component
    in the WinRE image, not including WinPE-WiFi. Add the font packages for Japan, Korea and China.
    Add the same set of languages to WinRE that you add to the Windows image.
    https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/customize-windows-re
    #>
    [CmdletBinding()]
    param ()
    #=================================================
    #   Abort
    #=================================================
    if ($ScriptName -ne 'New-OSBuild') {Return}
    if ($OSMajorVersion -ne 10) {Return}
    if ($UpdateOS -ne 'Windows 11') {Return}
    if ($null -eq $MountWinRE) {Return}
    if (!(Test-Path "$MountWinRE\Windows")) {Return}

    #Languages added to the Windows image by the Task and the OSLanguagePacks ContentPacks
    $TaskLanguages = @(@($LanguagePacks) + @($LanguageInterfacePacks) | Where-Object {$_} | ForEach-Object {Get-OSDBuilderLanguageFromPackage -Name $_})
    $TaskLanguages = @(@($TaskLanguages) + @(Get-OSDBuilderContentPackLanguages) | Where-Object {$_} | Sort-Object -Unique)

    $Source = Get-OSDBuilderWinPELanguageSource -OSMedia ([PSCustomObject]@{OperatingSystem = $UpdateOS; ReleaseId = $ReleaseId; InstallationType = $OSInstallationType}) -Architecture $OSArchitecture | Select-Object -First 1
    if (-not $Source) {
        if ($TaskLanguages.Count -gt 0) {
            Show-ActionTime; Write-Host -ForegroundColor Green "WinRE: Language Packs from the Languages and Optional Features ISO"
            Write-Warning "WinRE: No Languages and Optional Features ISO for $UpdateOS $ReleaseId was found in $GetOSDBuilderPathContentIsoExtract"
            Write-Warning "WinRE: $($TaskLanguages -join ', ') will not be available in the Windows Recovery Environment"
            Write-Warning "Use Save-OSDBuilderDownload -ContentDownload to download the Languages and Optional Features ISO"
        }
        Return
    }
    #Languages already in WinRE need the language packs of optional components that were added by the Task
    $WinRELanguages = @(Get-WindowsPackage -Path "$MountWinRE" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.PackageName -match 'WinPE-LanguagePack-Package~31bf3856ad364e35~[^~]+~(?<Lang>[A-Za-z0-9-]+)~') {$Matches['Lang'].ToLower()}
    })
    $Languages = @(@($TaskLanguages) + @($WinRELanguages) | Where-Object {$_} | Sort-Object -Unique)
    if ($Languages.Count -eq 0) {Return}
    #=================================================
    #   Execute
    #=================================================
    Show-ActionTime; Write-Host -ForegroundColor Green "WinRE: Language Packs from the Languages and Optional Features ISO"
    Write-Host "    Source: $Source" -ForegroundColor DarkGray
    Add-OSDBuilderWinPELanguagePacks -MountPath $MountWinRE -Languages $Languages -Sources @($Source) -ImageName 'WinRE'
    #=================================================
    #   Default language of WinRE matches the Windows image
    #=================================================
    if ($SetAllIntl -and ($SetAllIntl.ToLower() -in $TaskLanguages)) {
        Write-Host -ForegroundColor Gray "    Set-AllIntl $SetAllIntl"
        Dism /Image:"$MountWinRE" /Set-AllIntl:"$SetAllIntl" /LogPath:"$PEInfo\logs\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Dism-SetAllIntl-WinRE.log" | Out-Null
    }
}
function Get-OSDBuilderADKWinPELanguageSource {
    <#
    .SYNOPSIS
    Returns the WinPE_OCs directories of the ADK content (Content\ADK) that match the OSMedia
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $OSMedia,

        [string]$Architecture = 'x64'
    )
    $ArchFolders = @($Architecture)
    if ($Architecture -eq 'x64') {$ArchFolders += 'amd64'}
    $Paths = @()
    if ($GetOSDBuilderPathContentADK -and (Test-Path $GetOSDBuilderPathContentADK)) {
        $Paths = Get-ChildItem -Path $GetOSDBuilderPathContentADK -Directory -Recurse -Filter 'WinPE_OCs' -ErrorAction SilentlyContinue | `
            Where-Object {$_.Parent.Name -in $ArchFolders} | `
            Where-Object {$_.FullName -match (Get-OSDBuilderLanguageReleasePattern -OSMedia $OSMedia)} | `
            Where-Object {$_.FullName -notmatch (Get-OSDBuilderLanguageExcludePattern -OSMedia $OSMedia)} | `
            Select-Object -ExpandProperty FullName
    }
    $Paths
}
function Add-LanguagePacksWinSE {
    <#
    .SYNOPSIS
    Adds the languages of the LanguageCopySources to Windows Setup (boot.wim index 2, WinSE)

    .DESCRIPTION
    Microsoft: add lp.cab, WinPE-Setup_<language>.cab and WinPE-Setup-Client_<language>.cab (Windows Server: WinPE-Setup-Server)
    to the Windows Setup image for each language, the font support for Japanese, Korean and Chinese and
    WinPE-FontSupport-WinRE for Thai. The localized Setup resources (sources\<language>) are copied from the
    LanguageCopySources by Copy-MediaLanguageSources, Lang.ini is created by Set-LanguageSettingsOS.
    Language Interface Packs are not supported by Windows Setup.
    https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-multilingual-support-to-windows-setup
    #>
    [CmdletBinding()]
    param ()
    #=================================================
    #   Abort
    #=================================================
    if ($ScriptName -ne 'New-OSBuild') {Return}
    if ($OSMajorVersion -ne 10) {Return}
    if ([string]::IsNullOrWhiteSpace($LanguageCopySources)) {Return}
    if ($null -eq $MountWinSE) {Return}
    if (!(Test-Path "$MountWinSE\Windows")) {Return}
    #=================================================
    #   Languages of the LanguageCopySources
    #=================================================
    $CopySources = @(Get-OSMedia -Revision OK | Where-Object {$_.OSMFamily -in $LanguageCopySources})
    foreach ($Item in ($LanguageCopySources | Where-Object {$_ -notin $CopySources.OSMFamily})) {
        Write-Warning "WinSE: LanguageCopySources $Item was not found, import the OSMedia of this language with Import-OSMedia"
    }
    $Languages = @($CopySources | ForEach-Object {$_.Languages} | Where-Object {$_} | ForEach-Object {"$_".ToLower()} | Sort-Object -Unique)
    if ($Languages.Count -eq 0) {Return}
    #=================================================
    #   Sources: Languages and Optional Features ISO, then ADK
    #=================================================
    $OSMediaInfo = [PSCustomObject]@{OperatingSystem = $UpdateOS; ReleaseId = $ReleaseId; InstallationType = $OSInstallationType}
    $Sources = @(@(Get-OSDBuilderWinPELanguageSource -OSMedia $OSMediaInfo -Architecture $OSArchitecture) + @(Get-OSDBuilderADKWinPELanguageSource -OSMedia $OSMediaInfo -Architecture $OSArchitecture) | Where-Object {$_})

    Show-ActionTime; Write-Host -ForegroundColor Green "WinSE: Windows Setup Language Packs for $($Languages -join ', ')"
    if ($Sources.Count -eq 0) {
        Write-Warning "WinSE: No Languages and Optional Features ISO or ADK WinPE_OCs for $UpdateOS $ReleaseId was found"
        Write-Warning "Use Save-OSDBuilderDownload -ContentDownload to download the Languages and Optional Features ISO"
        Return
    }
    foreach ($Item in $Sources) {Write-Host "    Source: $Item" -ForegroundColor DarkGray}

    $SetupOptionalComponents = @('WinPE-Setup')
    if ($OSInstallationType -match 'Server') {$SetupOptionalComponents += 'WinPE-Setup-Server'}
    else {$SetupOptionalComponents += 'WinPE-Setup-Client'}

    Add-OSDBuilderWinPELanguagePacks -MountPath $MountWinSE -Languages $Languages -Sources $Sources -ImageName 'WinSE' -RequiredOptionalComponents $SetupOptionalComponents -ThaiFontSupport
}
