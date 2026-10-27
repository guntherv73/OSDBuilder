<#
Stub of the OSDBuilder module for Examples.Tests.ps1
Records every call in $global:OSDBuilderStubLog, nothing is downloaded or serviced
$global:OSDBuilderStubOSMedia   OSMedia returned by Get-OSMedia
$global:OSDBuilderStubImport    OSMedia added by Import-OSMedia, keyed by the ISO path
#>
function Add-StubLog ([string]$Message) {$global:OSDBuilderStubLog.Add($Message)}

function Get-OSDBuilder {
    param ([string]$SetHome, [switch]$CreatePaths, [switch]$HideDetails)
    $global:SetOSDBuilderPathContent = Join-Path $SetHome 'Content'
    $global:SetOSDBuilderPathTasks = Join-Path $SetHome 'Tasks'
    $global:GetOSDBuilderPathContentIsoExtract = Join-Path $global:SetOSDBuilderPathContent 'IsoExtract'
    foreach ($Path in @($global:SetOSDBuilderPathTasks, $global:GetOSDBuilderPathContentIsoExtract)) {
        if (!(Test-Path $Path)) {New-Item -Path $Path -ItemType Directory -Force | Out-Null}
    }
    Add-StubLog "Get-OSDBuilder -SetHome $SetHome"
}

function Save-OSDBuilderDownload {
    param ([string]$ContentDownload, [string[]]$LocalExperiencePack, [string]$LocalExperiencePackRelease)
    if ($LocalExperiencePack) {Add-StubLog "Save-OSDBuilderDownload -LocalExperiencePack $($LocalExperiencePack -join ',') -LocalExperiencePackRelease $LocalExperiencePackRelease"}
    else {Add-StubLog "Save-OSDBuilderDownload -ContentDownload $ContentDownload"}
}

function Get-OSMedia {
    param ($OSMajorVersion, $Revision)
    $global:OSDBuilderStubOSMedia
}

function Import-OSMedia {
    param ($Path, $EditionId, [switch]$SkipGrid, [switch]$SkipFeatureUpdates)
    Add-StubLog "Import-OSMedia -EditionId $EditionId"
}

function Mount-DiskImage {
    #The stub replaces the Storage cmdlet for the example script
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '')]
    param ($ImagePath, $StorageType, [switch]$PassThru)
    Add-StubLog "Mount-DiskImage $ImagePath"
    if ($global:OSDBuilderStubImport -and $global:OSDBuilderStubImport.ContainsKey($ImagePath)) {
        $global:OSDBuilderStubOSMedia = @($global:OSDBuilderStubOSMedia) + @($global:OSDBuilderStubImport[$ImagePath])
    }
    [PSCustomObject]@{ImagePath = $ImagePath}
}

function Get-Volume {
    #The stub replaces the Storage cmdlet for the example script
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '')]
    param ([Parameter(ValueFromPipeline = $true)]$DiskImage)
    process {[PSCustomObject]@{DriveLetter = 'E'}}
}

function Dismount-DiskImage {
    #The stub replaces the Storage cmdlet for the example script
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '')]
    param ($ImagePath)
}

function Update-OSMedia {
    param ([string[]]$Name, [switch]$Download, [switch]$Execute, [switch]$HideCleanupProgress)
    Add-StubLog "Update-OSMedia -Name $Name -Download:$Download -Execute:$Execute"
}

function New-OSBuildTask {
    param ($TaskName, $CustomName, $OSMedia, $SetAllIntl, $SetUserLocale, $SetSysLocale, $SetInputLocale, [switch]$EnableNetFX3)
    Add-StubLog "New-OSBuildTask -TaskName $TaskName -SetAllIntl $SetAllIntl -SetUserLocale $SetUserLocale -SetSysLocale $SetSysLocale -SetInputLocale $SetInputLocale -EnableNetFX3:$EnableNetFX3"
    #New-OSBuildTask keeps the ContentPacks of an existing Task
    $TaskPath = Join-Path $global:SetOSDBuilderPathTasks "OSBuild $TaskName.json"
    $ContentPacks = @()
    if (Test-Path $TaskPath) {$ContentPacks = @((Get-Content -Path $TaskPath -Raw | ConvertFrom-Json).ContentPacks | Where-Object {$_})}
    #The fields of the Task JSON written by New-OSBuildTask that the example script changes
    [ordered]@{
        TaskName                        = $TaskName
        ContentPacks                    = [string[]]$ContentPacks
        CustomName                      = $CustomName
        LangSetAllIntl                  = [string]$SetAllIntl
        LangSetUserLocale               = [string]$SetUserLocale
        LangSetSysLocale                = [string]$SetSysLocale
        LangSetInputLocale              = [string]$SetInputLocale
        LangSetSetupUILang              = ''
        EnableNetFX3                    = [string]$EnableNetFX3
        LanguagePack                    = @()
        LanguageInterfacePack           = @()
        LanguageFeature                 = @()
        LocalExperiencePacks            = @()
        AddWindowsCapability            = @()
        RemoveAppxProvisionedPackage    = @()
        LanguageCopySources             = @()
    } | ConvertTo-Json | Out-File -FilePath $TaskPath
}

function New-OSBuild {
    param ($ByTaskName, [switch]$Download, [switch]$Execute, [switch]$HideCleanupProgress, [switch]$CreateISO)
    Add-StubLog "New-OSBuild -ByTaskName $ByTaskName -Download:$Download -Execute:$Execute -CreateISO:$CreateISO"
}

function Get-OSBuilds {}

Export-ModuleMember -Function *
