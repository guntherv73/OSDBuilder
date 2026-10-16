BeforeDiscovery {
    $RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $ScriptFiles = Get-ChildItem -Path $RepoRoot -Include '*.ps1','*.psm1','*.psd1' -File -Recurse |
        Where-Object {$_.FullName -notmatch '[\\/]\.git[\\/]'} |
        ForEach-Object {@{Name = $_.FullName.Substring($RepoRoot.Length + 1); FullName = $_.FullName}}
    $Manifest = Import-PowerShellDataFile -Path (Join-Path $RepoRoot 'OSDBuilder.psd1')
    $ExportedFunctions = $Manifest.FunctionsToExport | ForEach-Object {@{Name = $_}}

    #Every function of the module and the Describe blocks of the tests
    $ModuleFunctions = foreach ($Script in (Get-ChildItem -Path (Join-Path $RepoRoot 'Private'), (Join-Path $RepoRoot 'Public') -Filter '*.ps1' -File)) {
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Script.FullName, [ref]$null, [ref]$null)
        $Ast.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $false) | ForEach-Object {@{Name = $_.Name; File = $Script.Name}}
    }
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

Describe 'Test coverage of the functions' {
    BeforeAll {
        $DescribedNames = foreach ($TestFile in (Get-ChildItem -Path $PSScriptRoot -Filter '*.Tests.ps1' -File)) {
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($TestFile.FullName, [ref]$null, [ref]$null)
            $Ast.FindAll({($args[0] -is [System.Management.Automation.Language.CommandAst]) -and ($args[0].GetCommandName() -eq 'Describe')}, $true) | ForEach-Object {
                $_.CommandElements[1].Extent.Text.Trim("'", '"')
            }
        }
    }

    It '<Name> (<File>) has a Describe block' -ForEach $ModuleFunctions {
        $DescribedNames | Should -Contain $Name
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
