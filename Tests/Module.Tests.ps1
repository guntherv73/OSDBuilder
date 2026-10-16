BeforeDiscovery {
    $RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $ScriptFiles = Get-ChildItem -Path $RepoRoot -Include '*.ps1','*.psm1','*.psd1' -File -Recurse |
        Where-Object {$_.FullName -notmatch '[\\/]\.git[\\/]'} |
        ForEach-Object {@{Name = $_.FullName.Substring($RepoRoot.Length + 1); FullName = $_.FullName}}
    $Manifest = Import-PowerShellDataFile -Path (Join-Path $RepoRoot 'OSDBuilder.psd1')
    $ExportedFunctions = $Manifest.FunctionsToExport | ForEach-Object {@{Name = $_}}
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $Manifest = Import-PowerShellDataFile -Path (Join-Path $RepoRoot 'OSDBuilder.psd1')
}

Describe 'PowerShell files' {
    It '<Name> has no syntax errors' -ForEach $ScriptFiles {
        $Tokens = $null
        $Errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($FullName, [ref]$Tokens, [ref]$Errors) | Out-Null
        $Errors | ForEach-Object {"$($_.Extent.StartLineNumber): $($_.Message)"} | Should -BeNullOrEmpty
    }
}

Describe 'Module manifest' {
    It 'has a valid ModuleVersion' {
        {[version]$Manifest.ModuleVersion} | Should -Not -Throw
    }

    It 'supports Windows PowerShell 5.1 and PowerShell 7' {
        $Manifest.PowerShellVersion | Should -Be '5.1'
        $Manifest.CompatiblePSEditions | Should -Contain 'Desktop'
        $Manifest.CompatiblePSEditions | Should -Contain 'Core'
    }

    It 'requires the OSD module 24.10.8.1' {
        $Osd = $Manifest.RequiredModules | Where-Object {$_.ModuleName -eq 'OSD'}
        $Osd.ModuleVersion | Should -Be '24.10.8.1'
    }

    It 'exports <Name> from Public\<Name>.ps1' -ForEach $ExportedFunctions {
        $File = Join-Path (Join-Path $RepoRoot 'Public') "$Name.ps1"
        $File | Should -Exist
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$null, [ref]$null)
        $Functions = $Ast.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $false).Name
        $Functions | Should -Contain $Name
    }
}

Describe 'Module import' {
    It 'refuses to import on macOS and Linux' -Skip:($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) {
        {Import-Module (Join-Path $RepoRoot 'OSDBuilder.psm1') -Force -ErrorAction Stop} | Should -Throw '*requires Windows*'
    }
}

Describe 'Private functions' {
    It 'have unique names' {
        $Names = foreach ($Script in (Get-OSDBuilderPrivateScript)) {
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$null)
            $Ast.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $false).Name
        }
        $Duplicates = $Names | Group-Object | Where-Object {$_.Count -gt 1} | Select-Object -ExpandProperty Name
        $Duplicates | Should -BeNullOrEmpty
    }
}
