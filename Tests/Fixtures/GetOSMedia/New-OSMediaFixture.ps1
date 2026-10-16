<#
.SYNOPSIS
Fixture builders for the Get-OSMedia, Get-OSBuilds and Get-PEBuilds tests

.DESCRIPTION
New-OSMediaFixture creates an OSMedia, OSBuild or PEBuild directory like Import-OSMedia, New-OSBuild and New-PEBuild do:
info\xml\Get-WindowsImage.xml, info\xml\CurrentVersion.xml, info\xml\Get-WindowsPackage.xml, info\xml\Sessions.xml
and the info\logs and info\json directories. The values are the ones DISM and the offline registry return for the image.

New-OSDUpdateFixture creates an update object like Get-OSDUpdates returns.
#>
function New-OSMediaFixture {
    [CmdletBinding()]
    param (
        #Directory of the OSMedia, for example $SetOSDBuilderPathOSMedia\Windows 11 Enterprise x64 24H2 26100.4061 en-US
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$ImageName = 'Windows 11 Enterprise',

        #Get-WindowsImage Architecture: 0 x86, 6 ia64, 9 x64, 12 ARM64
        [int]$Architecture = 9,

        [string]$EditionId = 'Enterprise',

        [string]$InstallationType = 'Client',

        [int]$MajorVersion = 10,

        [int]$MinorVersion = 0,

        [int]$Build = 26100,

        #Build.UBR like Import-OSMedia writes it
        [string]$UBR = '26100.4061',

        #CurrentVersion registry values, a value is not written when empty
        [string]$CurrentBuild = '26100',
        [string]$DisplayVersion = '24H2',
        [string]$ReleaseId = '2009',

        [string[]]$Languages = @('en-US'),

        [datetime]$CreatedTime = '2026-01-10 10:00:00',

        [datetime]$ModifiedTime = '2026-01-10 12:00:00',

        #Empty for an OSMedia that has no OSMGuid yet
        [string]$OSMGuid = ([guid]::NewGuid().Guid),

        #KB numbers in Sessions.xml with targetState Installed
        [string[]]$InstalledKB = @(),

        #KB numbers in Sessions.xml with targetState Staged
        [string[]]$StagedKB = @(),

        [switch]$NoWindowsImage,
        [switch]$NoCurrentVersion,
        [switch]$NoWindowsPackage,
        [switch]$NoSessions
    )
    $Info = Join-Path $Path 'info'
    $Xml = Join-Path $Info 'xml'
    foreach ($Directory in @($Xml, (Join-Path $Info 'logs'), (Join-Path $Info 'json'))) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }

    if (-not $NoWindowsImage) {
        $WindowsImage = [ordered]@{
            ImageName           = $ImageName
            ImageIndex          = 1
            Architecture        = $Architecture
            EditionId           = $EditionId
            InstallationType    = $InstallationType
            Version             = "$MajorVersion.$MinorVersion.$Build.$(($UBR -split '\.')[-1])"
            MajorVersion        = $MajorVersion
            MinorVersion        = $MinorVersion
            Build               = $Build
            SPBuild             = [int](($UBR -split '\.')[-1])
            UBR                 = $UBR
            Languages           = $Languages
            CreatedTime         = $CreatedTime
            ModifiedTime        = $ModifiedTime
        }
        if ($OSMGuid) {$WindowsImage.OSMGuid = $OSMGuid}
        [PSCustomObject]$WindowsImage | Export-Clixml -Path (Join-Path $Xml 'Get-WindowsImage.xml')
    }

    if (-not $NoCurrentVersion) {
        $CurrentVersion = [ordered]@{
            ProductName     = $ImageName
            EditionID       = $EditionId
            UBR             = [int](($UBR -split '\.')[-1])
        }
        if ($CurrentBuild) {$CurrentVersion.CurrentBuild = $CurrentBuild}
        if ($DisplayVersion) {$CurrentVersion.DisplayVersion = $DisplayVersion}
        if ($ReleaseId) {$CurrentVersion.ReleaseId = $ReleaseId}
        [PSCustomObject]$CurrentVersion | Export-Clixml -Path (Join-Path $Xml 'CurrentVersion.xml')
    }

    if (-not $NoWindowsPackage) {
        @(
            [PSCustomObject]@{PackageName = "Package_for_RollupFix~31bf3856ad364e35~amd64~~$UBR"; PackageState = 'Installed'; targetState = 'Installed'; id = 1}
        ) | Export-Clixml -Path (Join-Path $Xml 'Get-WindowsPackage.xml')
    }

    if (-not $NoSessions) {
        $Id = 0
        $Sessions = @(
            [PSCustomObject]@{id = $Id; KBNumber = ''; targetState = 'Installed'; Status = 'Complete'}
            foreach ($KB in $InstalledKB) {$Id++; [PSCustomObject]@{id = $Id; KBNumber = "KB$KB"; targetState = 'Installed'; Status = 'Complete'}}
            foreach ($KB in $StagedKB) {$Id++; [PSCustomObject]@{id = $Id; KBNumber = "KB$KB"; targetState = 'Staged'; Status = 'Pending'}}
        )
        $Sessions | Export-Clixml -Path (Join-Path $Xml 'Sessions.xml')
    }
    Get-Item -Path $Path
}

function New-OSDUpdateFixture {
    [CmdletBinding()]
    param (
        [string]$UpdateOS = 'Windows 11',
        [string]$UpdateBuild = '24H2',
        [string]$UpdateArch = 'x64',
        [string]$UpdateGroup = 'LCU',
        [string]$FileKBNumber = '5050001',
        [string]$CreationDate = '2026-01-14'
    )
    [PSCustomObject]@{
        UpdateOS        = $UpdateOS
        UpdateBuild     = $UpdateBuild
        UpdateArch      = $UpdateArch
        UpdateGroup     = $UpdateGroup
        Title           = "$CreationDate Update for $UpdateOS $UpdateBuild $UpdateArch (KB$FileKBNumber)"
        FileKBNumber    = $FileKBNumber
        FileName        = "windows11.0-kb$FileKBNumber-$UpdateArch.msu"
        CreationDate    = [datetime]$CreationDate
    }
}
