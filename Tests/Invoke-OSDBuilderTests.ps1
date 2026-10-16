<#
.SYNOPSIS
Runs the OSDBuilder Pester tests and PSScriptAnalyzer

.DESCRIPTION
Installs Pester 5.7.1 (and PSScriptAnalyzer 1.24.0 for -Lint) for the current user when missing and runs all Tests\*.Tests.ps1
Works with Windows PowerShell 5.1 and PowerShell 7 on Windows, macOS and Linux
The tests mock DISM, Appx, winget and the web requests, no Windows image, administrator rights or network are required

.EXAMPLE
.\Tests\Invoke-OSDBuilderTests.ps1

.EXAMPLE
.\Tests\Invoke-OSDBuilderTests.ps1 -Path .\Tests\LocalExperiencePacks.Tests.ps1 -Output Detailed

.EXAMPLE
.\Tests\Invoke-OSDBuilderTests.ps1 -CI
Runs PSScriptAnalyzer, the tests and the code coverage, writes Tests\TestResults.xml and Tests\Coverage.xml
and exits with 1 when a test fails, PSScriptAnalyzer reports a finding or the code coverage of Private and Public is below -MinimumCoverage (90 %)
#>
[CmdletBinding()]
param (
    #Test files or directories, all tests when empty
    [string[]]$Path = @($PSScriptRoot),

    [ValidateSet('None','Normal','Detailed','Diagnostic')]
    [string]$Output = 'Normal',

    #Filter the tests by tag
    [string[]]$Tag,

    #Measures the code coverage of Private and Public
    [switch]$CodeCoverage,

    #Runs PSScriptAnalyzer with PSScriptAnalyzerSettings.psd1
    [switch]$Lint,

    #Lint, code coverage, test result files and exit code
    [switch]$CI,

    #Installs Pester and PSScriptAnalyzer and exits, run it in its own process before the tests
    #Installing and importing Pester in the same process fails when another Pester version is loaded
    [switch]$InstallDependencies,

    #Minimum code coverage of Private and Public in percent for -CI
    [ValidateRange(0, 100)]
    [int]$MinimumCoverage = 90
)
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Import-RequiredModule ([string]$Name, [version]$Version) {
    if (-not (Get-Module -Name $Name -ListAvailable | Where-Object {$_.Version -eq $Version})) {
        Write-Host "Installing $Name $Version for the current user" -ForegroundColor Cyan
        #Windows PowerShell 5.1 needs the NuGet provider for the PowerShell Gallery
        if (($PSVersionTable.PSEdition -eq 'Desktop') -and -not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
        }
        $InstallParams = @{Name = $Name; RequiredVersion = $Version; Scope = 'CurrentUser'; Force = $true}
        #PowerShellGet 1.0 of Windows PowerShell 5.1 has no -SkipPublisherCheck and -AllowClobber
        $InstallModule = Get-Command -Name Install-Module
        if ($InstallModule.Parameters.ContainsKey('SkipPublisherCheck')) {$InstallParams.SkipPublisherCheck = $true}
        if ($InstallModule.Parameters.ContainsKey('AllowClobber')) {$InstallParams.AllowClobber = $true}
        Install-Module @InstallParams
    }
    Remove-Module -Name $Name -ErrorAction SilentlyContinue
    Import-Module -Name $Name -RequiredVersion $Version -Force
}

if ($InstallDependencies) {
    foreach ($Module in @(@{Name = 'Pester'; Version = '5.7.1'}, @{Name = 'PSScriptAnalyzer'; Version = '1.24.0'})) {
        if (-not (Get-Module -Name $Module.Name -ListAvailable | Where-Object {$_.Version -eq $Module.Version})) {
            Write-Host "Installing $($Module.Name) $($Module.Version) for the current user" -ForegroundColor Cyan
            if (($PSVersionTable.PSEdition -eq 'Desktop') -and -not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
            }
            $InstallParams = @{Name = $Module.Name; RequiredVersion = $Module.Version; Scope = 'CurrentUser'; Force = $true}
            $InstallModule = Get-Command -Name Install-Module
            if ($InstallModule.Parameters.ContainsKey('SkipPublisherCheck')) {$InstallParams.SkipPublisherCheck = $true}
            if ($InstallModule.Parameters.ContainsKey('AllowClobber')) {$InstallParams.AllowClobber = $true}
            Install-Module @InstallParams
        }
    }
    exit 0
}

$Failed = 0
#=================================================
#   PSScriptAnalyzer
#   Private scripts written with tests, the example and the tests
#   AllFunctions.ps1 and Public are linted when they are refactored with tests
#=================================================
if ($Lint -or $CI) {
    Import-RequiredModule -Name PSScriptAnalyzer -Version '1.24.0'
    $LintFiles = @(
        Get-ChildItem -Path (Join-Path $RepoRoot 'Private') -Filter '*.ps1' -File | Where-Object {$_.Name -ne 'AllFunctions.ps1'}
        Get-ChildItem -Path (Join-Path $RepoRoot 'Examples') -Filter '*.ps1' -File
        Get-ChildItem -Path $PSScriptRoot -Include '*.ps1','*.psm1' -File -Recurse
    )
    $Settings = Join-Path $RepoRoot 'PSScriptAnalyzerSettings.psd1'
    $Findings = @($LintFiles | ForEach-Object {Invoke-ScriptAnalyzer -Path $_.FullName -Settings $Settings})
    if ($Findings.Count -gt 0) {
        $Findings | Format-Table -AutoSize -Property Severity, RuleName, ScriptName, Line, Message | Out-String -Width 250 | Write-Host
        Write-Host "PSScriptAnalyzer: $($Findings.Count) finding(s)" -ForegroundColor Red
        $Failed++
    }
    else {
        Write-Host "PSScriptAnalyzer: no findings in $($LintFiles.Count) files" -ForegroundColor Green
    }
}
#=================================================
#   Pester
#=================================================
Import-RequiredModule -Name Pester -Version '5.7.1'

$Configuration = New-PesterConfiguration
$Configuration.Run.Path = $Path
$Configuration.Run.PassThru = $true
$Configuration.Output.Verbosity = $Output
if ($Tag) {$Configuration.Filter.Tag = $Tag}

if ($CI) {
    $Configuration.TestResult.Enabled = $true
    $Configuration.TestResult.OutputFormat = 'NUnitXml'
    $Configuration.TestResult.OutputPath = Join-Path $PSScriptRoot 'TestResults.xml'
}
if ($CodeCoverage -or $CI) {
    $Configuration.CodeCoverage.Enabled = $true
    $Configuration.CodeCoverage.Path = @(Get-ChildItem -Path (Join-Path $RepoRoot 'Private'), (Join-Path $RepoRoot 'Public') -Filter '*.ps1' -File | Select-Object -ExpandProperty FullName)
    $Configuration.CodeCoverage.OutputPath = Join-Path $PSScriptRoot 'Coverage.xml'
    $Configuration.CodeCoverage.CoveragePercentTarget = $MinimumCoverage
}

#The tests expect the default ErrorActionPreference Continue, the pwsh shell of GitHub Actions sets Stop in the global scope
$ErrorActionPreferenceCaller = $global:ErrorActionPreference
$global:ErrorActionPreference = 'Continue'
try {
    $Result = Invoke-Pester -Configuration $Configuration
}
finally {
    $global:ErrorActionPreference = $ErrorActionPreferenceCaller
}
if ($Result.FailedCount -gt 0) {
    Write-Host "Pester: $($Result.FailedCount) test(s) failed" -ForegroundColor Red
    $Failed++
}
if ($CI -and $Result.CodeCoverage -and ($Result.CodeCoverage.CoveragePercent -lt $MinimumCoverage)) {
    Write-Host ("Code coverage {0:N1}% is below {1}%" -f $Result.CodeCoverage.CoveragePercent, $MinimumCoverage) -ForegroundColor Red
    $Failed++
}
if ($CI) {exit [int]($Failed -gt 0)}
