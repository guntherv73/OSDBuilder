<#
.SYNOPSIS
Shows the code coverage of OSDBuilder functions

.DESCRIPTION
Runs the given tests with code coverage of Private and Public and lists the coverage of each function,
lowest first, and the missed lines of the functions below -Threshold

.EXAMPLE
.\Tests\Measure-OSDBuilderCoverage.ps1 -Path .\Tests\LocalExperiencePacks.Tests.ps1 -Function Add-OSDBuilderLocalExperiencePack, Add-LocalExperiencePacksOS

.EXAMPLE
.\Tests\Measure-OSDBuilderCoverage.ps1 -Path .\Tests\NewOSBuild.Tests.ps1 -File New-OSBuild.ps1 -ShowMissed
#>
[CmdletBinding()]
param (
    #Test files
    [Parameter(Mandatory = $true)]
    [string[]]$Path,

    #Only these functions, all functions of -File when empty
    [string[]]$Function,

    #Only functions of these files (file names in Private or Public), all files when empty
    [string[]]$File,

    #Lists the missed lines of functions below this coverage in percent
    [int]$Threshold = 90,

    [switch]$ShowMissed
)
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name Pester -RequiredVersion '5.7.1' -Force

$CoverageFiles = Get-ChildItem -Path (Join-Path $RepoRoot 'Private'), (Join-Path $RepoRoot 'Public') -Filter '*.ps1' -File
if ($File) {$CoverageFiles = $CoverageFiles | Where-Object {$_.Name -in $File}}

$Configuration = New-PesterConfiguration
$Configuration.Run.Path = $Path
$Configuration.Run.PassThru = $true
$Configuration.Output.Verbosity = 'None'
$Configuration.CodeCoverage.Enabled = $true
$Configuration.CodeCoverage.Path = @($CoverageFiles.FullName)
$Configuration.CodeCoverage.OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) 'OSDBuilderCoverage.xml'

$Result = Invoke-Pester -Configuration $Configuration
Write-Host "Tests: $($Result.PassedCount) passed, $($Result.FailedCount) failed" -ForegroundColor $(if ($Result.FailedCount) {'Red'} else {'Green'})
foreach ($Failed in $Result.Failed) {Write-Host "  FAILED $($Failed.ExpandedPath): $($Failed.ErrorRecord.Exception.Message)" -ForegroundColor Red}

$Commands = @($Result.CodeCoverage.CommandsExecuted | Select-Object *, @{Name = 'Hit'; Expression = {$true}}) +
    @($Result.CodeCoverage.CommandsMissed | Select-Object *, @{Name = 'Hit'; Expression = {$false}})
#Commands outside of a function belong to the script file
$Commands = $Commands | ForEach-Object {if (-not $_.Function) {$_.Function = "<script> $(Split-Path $_.File -Leaf)"}; $_}
if ($Function) {$Commands = $Commands | Where-Object {$_.Function -in $Function}}

$Report = $Commands | Group-Object -Property Function | ForEach-Object {
    $Hit = @($_.Group | Where-Object {$_.Hit}).Count
    [PSCustomObject]@{
        Function    = $_.Name
        File        = Split-Path ($_.Group[0].File) -Leaf
        Commands    = $_.Count
        Missed      = $_.Count - $Hit
        Coverage    = [math]::Round(100 * $Hit / $_.Count, 1)
    }
} | Sort-Object -Property Coverage, Function

$Report | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
$Total = ($Report | Measure-Object -Property Commands -Sum).Sum
$Missed = ($Report | Measure-Object -Property Missed -Sum).Sum
if ($Total) {Write-Host ("Total: {0:N1}% of {1} commands, {2} missed" -f (100 * ($Total - $Missed) / $Total), $Total, $Missed) -ForegroundColor Cyan}

if ($ShowMissed) {
    foreach ($Item in ($Report | Where-Object {$_.Coverage -lt $Threshold})) {
        Write-Host "`n$($Item.Function) ($($Item.Coverage)%) missed lines:" -ForegroundColor Yellow
        $Commands | Where-Object {($_.Function -eq $Item.Function) -and -not $_.Hit} | Sort-Object Line -Unique | ForEach-Object {
            Write-Host ("  {0,5}: {1}" -f $_.Line, ($_.Command -replace '\s+', ' ').Substring(0, [math]::Min(140, ($_.Command -replace '\s+', ' ').Length)))
        }
    }
}
