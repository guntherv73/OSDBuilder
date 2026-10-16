function Get-OSDBuilderAppxManifest {
    <#
    .SYNOPSIS
    Reads the identity, dependencies and framework flag of an .appx, .msix, .appxbundle or .msixbundle

    .DESCRIPTION
    For a bundle the identity is read from AppxMetadata\AppxBundleManifest.xml
    With -Detailed the application package for the Architecture is read from the bundle,
    its version and dependencies are the values that DISM uses for provisioning
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        #Preferred application package architectures in a bundle, first match wins
        [string[]]$Architecture = @('x64','neutral','x86'),

        [switch]$Detailed
    )
    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    function Read-ZipEntryText ($Zip, [string]$EntryName) {
        $Entry = $Zip.Entries | Where-Object {($_.FullName -eq $EntryName) -or ([uri]::UnescapeDataString($_.FullName) -eq $EntryName)} | Select-Object -First 1
        if ($null -eq $Entry) {Return $null}
        $Reader = New-Object System.IO.StreamReader($Entry.Open())
        try {$Reader.ReadToEnd()} finally {$Reader.Dispose()}
    }
    function ConvertFrom-AppxManifest ([string]$Text) {
        [xml]$Xml = $Text
        $Dependencies = @($Xml.Package.Dependencies.PackageDependency | Where-Object {$_} | ForEach-Object {
            [PSCustomObject]@{Name = $_.Name; MinVersion = $_.MinVersion}
        })
        [PSCustomObject]@{
            Name            = $Xml.Package.Identity.Name
            Version         = $Xml.Package.Identity.Version
            Architecture    = if ($Xml.Package.Identity.ProcessorArchitecture) {$Xml.Package.Identity.ProcessorArchitecture} else {'neutral'}
            IsFramework     = ([string]$Xml.Package.Properties.Framework -eq 'true')
            Dependencies    = $Dependencies
        }
    }

    $Zip = $null
    try {
        $Zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $BundleText = Read-ZipEntryText $Zip 'AppxMetadata/AppxBundleManifest.xml'

        if (-not $BundleText) {
            $Manifest = ConvertFrom-AppxManifest (Read-ZipEntryText $Zip 'AppxManifest.xml')
            $Manifest | Add-Member -NotePropertyName Path -NotePropertyValue $Path
            $Manifest | Add-Member -NotePropertyName IsBundle -NotePropertyValue $false
            Return $Manifest
        }

        [xml]$BundleXml = $BundleText
        $Result = [PSCustomObject]@{
            Path            = $Path
            IsBundle        = $true
            Name            = $BundleXml.Bundle.Identity.Name
            Version         = $null
            Architecture    = $null
            IsFramework     = $false
            Dependencies    = @()
        }
        if (-not $Detailed.IsPresent) {Return $Result}

        $Applications = @($BundleXml.Bundle.Packages.Package | Where-Object {$_.Type -eq 'application'})
        $Application = $null
        foreach ($Arch in $Architecture) {
            $Application = $Applications | Where-Object {([string]$_.Architecture -eq $Arch) -or (($Arch -eq 'neutral') -and (-not $_.Architecture))} | Select-Object -First 1
            if ($Application) {Break}
        }
        if ($null -eq $Application) {Return $Result}

        $Entry = $Zip.Entries | Where-Object {($_.FullName -eq $Application.FileName) -or ([uri]::UnescapeDataString($_.FullName) -eq $Application.FileName)} | Select-Object -First 1
        if ($null -eq $Entry) {Return $Result}

        #A zip in a zip needs a seekable stream, the application package is copied to a temporary file
        $TempFile = [System.IO.Path]::GetTempFileName()
        try {
            $Source = $Entry.Open()
            $Target = [System.IO.File]::Create($TempFile)
            try {$Source.CopyTo($Target)} finally {$Target.Dispose(); $Source.Dispose()}

            $InnerZip = [System.IO.Compression.ZipFile]::OpenRead($TempFile)
            try {$Inner = ConvertFrom-AppxManifest (Read-ZipEntryText $InnerZip 'AppxManifest.xml')}
            finally {$InnerZip.Dispose()}
        }
        finally {
            Remove-Item -Path $TempFile -Force -ErrorAction SilentlyContinue
        }
        $Result.Version = $Inner.Version
        $Result.Architecture = $Inner.Architecture
        $Result.Dependencies = $Inner.Dependencies
        Return $Result
    }
    catch {
        Write-Verbose "Unable to read the manifest of $Path, $($_.Exception.Message)"
        Return $null
    }
    finally {
        if ($Zip) {$Zip.Dispose()}
    }
}
function Get-OSDBuilderInboxAppsSource {
    <#
    .SYNOPSIS
    Returns the Content\InboxApps\<Name>\packages directories that match the OSMedia
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $OSMedia
    )
    $InboxAppsPath = Join-Path $SetOSDBuilderPathContent 'InboxApps'
    if (!(Test-Path $InboxAppsPath)) {Return}
    Get-ChildItem -Path $InboxAppsPath -Directory -ErrorAction SilentlyContinue | `
        Where-Object {$_.FullName -match (Get-OSDBuilderLanguageReleasePattern -OSMedia $OSMedia)} | `
        Where-Object {$_.FullName -notmatch (Get-OSDBuilderLanguageExcludePattern -OSMedia $OSMedia)} | `
        ForEach-Object {Join-Path $_.FullName 'packages'} | `
        Where-Object {Test-Path $_}
}
function Update-InboxAppsOS {
    <#
    .SYNOPSIS
    Reinstalls the provisioned inbox apps from the Inbox Apps ISO after Languages were added

    .DESCRIPTION
    Microsoft: Reinstall the inbox apps after adding languages and updates, so the apps have the
    language resources. The apps are reinstalled without removing them first.
    https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-desktop-editions

    Only apps that are provisioned in the image are reinstalled, apps removed from the image are not added
    An app is skipped when the image contains a newer version
    The dependencies are read from the AppxManifest of each app, the license is the .xml with the same name
    #>
    [CmdletBinding()]
    param ()
    #=================================================
    #   Abort
    #=================================================
    if ($ScriptName -ne 'New-OSBuild') {Return}
    if ($OSMajorVersion -ne 10) {Return}
    if ($UpdateOS -ne 'Windows 11') {Return}
    if ($OSInstallationType -ne 'Client') {Return}
    if (-not ($LanguagePacks -or $LanguageInterfacePacks -or $LanguageFeatures -or $LocalExperiencePacks)) {Return}
    #=================================================
    #   Header
    #=================================================
    Show-ActionTime; Write-Host -ForegroundColor Green "OS: Reinstall Inbox Apps for the added Languages"
    $Sources = @(Get-OSDBuilderInboxAppsSource -OSMedia ([PSCustomObject]@{OperatingSystem = $UpdateOS; ReleaseId = $ReleaseId; InstallationType = $OSInstallationType}))
    if ($Sources.Count -eq 0) {
        Write-Warning "Inbox Apps: No Inbox Apps for $UpdateOS $ReleaseId were found in $(Join-Path $SetOSDBuilderPathContent 'InboxApps')"
        Write-Warning "Inbox Apps: The inbox apps will not include the resources of the added Languages"
        Write-Warning "Use Save-OSDBuilderDownload -ContentDownload to download the Inbox Apps ISO"
        Return
    }
    foreach ($Item in $Sources) {Write-Host "    Source: $Item" -ForegroundColor DarkGray}
    #=================================================
    #   Architectures
    #   An x64 image requires the x64 and x86 dependencies
    #=================================================
    $Architectures = @('neutral', $OSArchitecture)
    if ($OSArchitecture -eq 'x64') {$Architectures += 'x86'}
    #=================================================
    #   Index the Inbox Apps
    #=================================================
    $Files = @($Sources | ForEach-Object {Get-ChildItem -Path $_ -File -Include *.appx,*.msix,*.appxbundle,*.msixbundle -Recurse -ErrorAction SilentlyContinue})
    $Packages = @($Files | ForEach-Object {Get-OSDBuilderAppxManifest -Path $_.FullName} | Where-Object {$_})
    $Frameworks = @($Packages | Where-Object {$_.IsFramework} | Where-Object {$_.Architecture -in $Architectures})
    $Applications = @($Packages | Where-Object {-not $_.IsFramework} | Where-Object {$_.IsBundle -or ($_.Architecture -in @('neutral', $OSArchitecture))})
    #=================================================
    #   Provisioned Apps
    #=================================================
    $Provisioned = @(Get-AppxProvisionedPackage -Path "$MountDirectory" -ErrorAction SilentlyContinue)
    foreach ($App in ($Provisioned | Sort-Object DisplayName)) {
        #Prefer the package of the image architecture, then a bundle, then a neutral package
        $Source = $Applications | Where-Object {$_.Name -eq $App.DisplayName} | Sort-Object -Property @{Expression = {if ($_.Architecture -eq $OSArchitecture) {0} elseif ($_.IsBundle) {1} else {2}}} | Select-Object -First 1
        if ($null -eq $Source) {
            Write-Host -ForegroundColor DarkGray "NOT IN ISO        $($App.DisplayName)"; Continue
        }
        if ($Source.IsBundle) {
            $Source = Get-OSDBuilderAppxManifest -Path $Source.Path -Architecture @($OSArchitecture,'neutral','x86') -Detailed
            if ($null -eq $Source -or -not $Source.Version) {Write-Warning "Inbox Apps: Unable to read $($App.DisplayName)"; Continue}
        }
        if ([version]$Source.Version -lt [version]$App.Version) {
            Write-Host -ForegroundColor DarkGray "NEWER IN IMAGE    $($App.DisplayName) $($App.Version)"; Continue
        }
        #=================================================
        #   Dependencies: the newest framework of each name and architecture
        #=================================================
        $Dependencies = foreach ($Dependency in $Source.Dependencies) {
            $Frameworks | Where-Object {$_.Name -eq $Dependency.Name} | Group-Object -Property Architecture | ForEach-Object {
                $_.Group | Sort-Object -Property @{Expression = {[version]$_.Version}} -Descending | Select-Object -First 1 -ExpandProperty Path
            }
        }
        $Dependencies = @($Dependencies | Where-Object {$_} | Sort-Object -Unique)
        $Missing = @($Source.Dependencies | Where-Object {$_.Name -notin ($Frameworks.Name)})
        foreach ($Item in $Missing) {Write-Verbose "Inbox Apps: $($App.DisplayName) dependency $($Item.Name) is not in the Inbox Apps, DISM uses the framework in the image"}

        $Params = @{
            Path        = "$MountDirectory"
            PackagePath = $Source.Path
            LogPath     = "$Info\logs\$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Update-InboxAppsOS-$($App.DisplayName).log"
            ErrorAction = 'Stop'
        }
        if ($Dependencies.Count -gt 0) {$Params.DependencyPackagePath = $Dependencies}
        $License = [System.IO.Path]::ChangeExtension($Source.Path, '.xml')
        if (Test-Path $License) {$Params.LicensePath = $License} else {$Params.SkipLicense = $true}

        Write-Host -ForegroundColor Cyan "REINSTALLING      " -NoNewline
        Write-Host -ForegroundColor Gray "$($App.DisplayName) $($Source.Version)"
        try {Add-AppxProvisionedPackage @Params | Out-Null}
        catch {
            Write-Warning "Inbox Apps: $($App.DisplayName) could not be reinstalled, $($_.Exception.Message)"
            Write-Verbose "$($Params.LogPath)" -Verbose
        }
    }
}
