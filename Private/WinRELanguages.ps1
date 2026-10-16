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

    #Languages added to the Windows image by the Task
    $TaskLanguages = @(@($LanguagePacks) + @($LanguageInterfacePacks) | Where-Object {$_} | ForEach-Object {Get-OSDBuilderLanguageFromPackage -Name $_} | Where-Object {$_} | Sort-Object -Unique)

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
    #   Header
    #=================================================
    Show-ActionTime; Write-Host -ForegroundColor Green "WinRE: Language Packs from the Languages and Optional Features ISO"
    Write-Host "    Source: $Source" -ForegroundColor DarkGray
    #=================================================
    #   Execute
    #=================================================
    foreach ($Language in $Languages) {
        $LanguageSource = Join-Path $Source $Language
        if (!(Test-Path (Join-Path $LanguageSource 'lp.cab'))) {
            Write-Warning "WinRE: $Language is not available for the Windows Recovery Environment"; Continue
        }
        $Installed = @(Get-WindowsPackage -Path "$MountWinRE" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PackageName)
        #The Languages and Optional Features ISO uses lowercase file names, the lookup ignores the case
        $LanguageFiles = @{}
        Get-ChildItem -Path $LanguageSource -File -Filter *.cab -ErrorAction SilentlyContinue | ForEach-Object {$LanguageFiles[$_.Name.ToLower()] = $_.FullName}
        $SourceFiles = @{}
        Get-ChildItem -Path $Source -File -Filter *.cab -ErrorAction SilentlyContinue | ForEach-Object {$SourceFiles[$_.Name.ToLower()] = $_.FullName}

        #Base language pack first, then the language pack of each optional component in WinRE
        $Cabs = @()
        if (-not ($Installed | Where-Object {$_ -match "LanguagePack-Package~31bf3856ad364e35~[^~]+~$([regex]::Escape($Language))~"})) {
            $Cabs += $LanguageFiles['lp.cab']
        }
        $OptionalComponents = $Installed | ForEach-Object {
            if ($_ -match '^(?<Name>WinPE-[^~]+)-Package~31bf3856ad364e35~[^~]+~~') {$Matches['Name']}
        } | Where-Object {$_ -ne 'WinPE-WiFi'} | Sort-Object -Unique
        foreach ($Name in $OptionalComponents) {
            if ($Installed | Where-Object {$_ -match "^$([regex]::Escape($Name))-Package~31bf3856ad364e35~[^~]+~$([regex]::Escape($Language))~"}) {Continue}
            $Cab = $LanguageFiles["$($Name)_$($Language).cab".ToLower()]
            if ($Cab) {$Cabs += $Cab}
        }
        #Font support for Japan, Korea and China
        $FontSupport = $SourceFiles["winpe-fontsupport-$($Language).cab"]
        if ($FontSupport -and (-not ($Installed | Where-Object {$_ -match "^WinPE-FontSupport-$([regex]::Escape($Language))-Package"}))) {$Cabs += $FontSupport}

        if ($Cabs.Count -eq 0) {
            Write-Host -ForegroundColor Gray "INSTALLED         $Language"; Continue
        }
        foreach ($Cab in $Cabs) {
            Write-Host -ForegroundColor Cyan "INSTALLING        " -NoNewline
            Write-Host -ForegroundColor Gray "$Language $(Split-Path $Cab -Leaf)"
            $CurrentLog = "$PEInfo\logs\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Add-LanguagePacksWinRE-$Language.log"
            Try {Add-WindowsPackage -Path "$MountWinRE" -PackagePath "$Cab" -LogPath "$CurrentLog" | Out-Null}
            Catch {
                if ($_.Exception.Message -match '0x800f081e') {Write-Verbose "OSDBuilder: 0x800f081e The package is not applicable to this image" -Verbose}
                Write-Verbose "OSDBuilder: Review the log for more information" -Verbose
                Write-Verbose "$CurrentLog" -Verbose
            }
        }
    }
    #=================================================
    #   Default language of WinRE matches the Windows image
    #=================================================
    if ($SetAllIntl -and ($SetAllIntl.ToLower() -in $TaskLanguages)) {
        Write-Host -ForegroundColor Gray "    Set-AllIntl $SetAllIntl"
        Dism /Image:"$MountWinRE" /Set-AllIntl:"$SetAllIntl" /LogPath:"$PEInfo\logs\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Dism-SetAllIntl-WinRE.log" | Out-Null
    }
}
