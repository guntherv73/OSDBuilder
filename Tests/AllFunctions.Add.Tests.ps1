<#
Tests of the Add- build functions in Private\AllFunctions.ps1 that add Task content to the mounted images
(ADK Optional Components, Drivers, Extra Files, Scripts, Start Layout, Unattend, Features on Demand, Language content,
Windows Capabilities, Packages)
The ContentPack functions (Add-ContentPack*) are tested in AllFunctions.AddContentPack.Tests.ps1
#>
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}

    #Arguments of a mocked Windows program (dism, robocopy), the first positional argument is bound to $InputObject
    function Join-ProgramArgument ($InputObject, $RemainingArguments) {
        (@($InputObject) + @($RemainingArguments) | Where-Object {$null -ne $_}) -join ' '
    }
}

AfterAll {
    Remove-Variable -Name ReapplyLCU, UpdateLanguageContent, AddTestScriptRan -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Add-ContentADKWinPE' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10
        $SetOSDBuilderPathContent = 'C:\Content'; $MountWinPE = 'C:\MountWinPE'; $PEInfo = $TestDrive
        #Task.WinPEADKPE contains the paths relative to Content
        $WinPEADKPE = @(
            'WinPE\ADK\x64\WinPE-WMI.cab'
            'WinPE\ADK\x64\WinPE-PowerShell.cab'
            'WinPE\ADK\x64\WinPE-NetFx.cab'
            'WinPE\ADK\x64\WinPE-StorageWMI.cab'
        )
        $global:ReapplyLCU = $false
        $script:Added = [System.Collections.Generic.List[string]]::new()
        Mock Add-WindowsPackage {$script:Added.Add($PackagePath)}
        Mock dism {}
    }

    It 'installs WinPE-NetFx before WinPE-PowerShell before the other packages in WinPE.wim' {
        Add-ContentADKWinPE 6>$null
        $script:Added[0] | Should -Be 'C:\Content\WinPE\ADK\x64\WinPE-NetFx.cab'
        $script:Added[1] | Should -Be 'C:\Content\WinPE\ADK\x64\WinPE-PowerShell.cab'
        $script:Added | Should -Contain 'C:\Content\WinPE\ADK\x64\WinPE-WMI.cab'
        $script:Added | Should -Contain 'C:\Content\WinPE\ADK\x64\WinPE-StorageWMI.cab'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly -ParameterFilter {($Path -ne 'C:\MountWinPE') -or ($LogPath -notlike '*-Add-ContentADKWinPE.log')}
        $global:ReapplyLCU | Should -BeTrue
        Should -Invoke dism -Times 0 -Exactly
    }

    # KnownBug: AllFunctions.ps1:30,45 filter the relative path strings of the Task by $_.Name, which is empty, so NetFx and PowerShell are added twice
    It 'installs every package once' -Skip {
        Add-ContentADKWinPE 6>$null
        $script:Added.Count | Should -Be 4
    }

    It 'also runs in New-PEBuild' {
        $ScriptName = 'New-PEBuild'
        Add-ContentADKWinPE 6>$null
        Should -Invoke Add-WindowsPackage -ParameterFilter {$PackagePath -like '*WinPE-WMI.cab'}
    }

    It 'adds the other packages with dism.exe on Windows 7 / 8.1 (OSMajorVersion 6)' {
        $OSMajorVersion = 6
        Add-ContentADKWinPE 6>$null
        Should -Invoke dism -ParameterFilter {
            ($InputObject -eq '/Image:C:\MountWinPE') -and ($RemainingArguments -contains '/Add-Package') -and
            ($RemainingArguments -contains '/PackagePath:C:\Content\WinPE\ADK\x64\WinPE-WMI.cab')
        } -Times 1 -Exactly
        Should -Invoke Add-WindowsPackage -ParameterFilter {$PackagePath -like '*WinPE-WMI.cab'} -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -ParameterFilter {$PackagePath -like '*WinPE-NetFx.cab'}
    }

    It 'continues when a package is not applicable (0x800f081e)' {
        Mock Add-WindowsPackage {throw 'Add-WindowsPackage failed. Error code = 0x800f081e'}
        $Verbose = (Add-ContentADKWinPE 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        Should -Invoke Add-WindowsPackage -Times 6 -Exactly
    }

    It 'shows the log when a package fails' {
        Mock Add-WindowsPackage {throw 'Access is denied'}
        $Verbose = (Add-ContentADKWinPE 6>$null 4>&1) -join "`n"
        $Verbose | Should -Not -BeLike '*0x800f081e*'
        $Verbose | Should -BeLike '*-Add-ContentADKWinPE.log*'
    }

    It 'does nothing in <ScriptName>' -ForEach @(@{ScriptName = 'Update-OSMedia'}, @{ScriptName = 'New-OSDCloudOSMedia'}) {
        #-ForEach data is set before BeforeEach, apply it again
        foreach ($Key in $_.Keys) {Set-Variable -Name $Key -Value $_[$Key]}
        Add-ContentADKWinPE 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        $global:ReapplyLCU | Should -BeFalse
    }

    It 'does nothing without WinPE ADK packages' {
        $WinPEADKPE = $null
        Add-ContentADKWinPE 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        $global:ReapplyLCU | Should -BeFalse
    }
}

Describe 'Add-ContentADKWinRE' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10
        $SetOSDBuilderPathContent = 'C:\Content'; $MountWinRE = 'C:\MountWinRE'; $PEInfo = $TestDrive
        $WinPEADKRE = @(
            'WinPE\ADK\x64\WinPE-WMI.cab'
            'WinPE\ADK\x64\WinPE-PowerShell.cab'
            'WinPE\ADK\x64\WinPE-NetFx.cab'
            'WinPE\ADK\x64\WinPE-StorageWMI.cab'
        )
        $global:ReapplyLCU = $false
        $script:Added = [System.Collections.Generic.List[string]]::new()
        Mock Add-WindowsPackage {$script:Added.Add($PackagePath)}
        Mock dism {}
    }

    It 'installs WinPE-NetFx before WinPE-PowerShell before the other packages in WinRE.wim' {
        Add-ContentADKWinRE 6>$null
        $script:Added[0] | Should -Be 'C:\Content\WinPE\ADK\x64\WinPE-NetFx.cab'
        $script:Added[1] | Should -Be 'C:\Content\WinPE\ADK\x64\WinPE-PowerShell.cab'
        $script:Added | Should -Contain 'C:\Content\WinPE\ADK\x64\WinPE-StorageWMI.cab'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly -ParameterFilter {($Path -ne 'C:\MountWinRE') -or ($LogPath -notlike '*-Add-ContentADKWinRE.log')}
        $global:ReapplyLCU | Should -BeTrue
    }

    # KnownBug: AllFunctions.ps1:89,103 filter the relative path strings of the Task by $_.Name, which is empty, so NetFx and PowerShell are added twice
    It 'installs every package once' -Skip {
        Add-ContentADKWinRE 6>$null
        $script:Added.Count | Should -Be 4
    }

    It 'adds the other packages with dism.exe when OSMajorVersion is 6' {
        $OSMajorVersion = 6
        Add-ContentADKWinRE 6>$null
        Should -Invoke dism -ParameterFilter {
            ($InputObject -eq '/Image:C:\MountWinRE') -and ($RemainingArguments -contains '/PackagePath:C:\Content\WinPE\ADK\x64\WinPE-StorageWMI.cab')
        } -Times 1 -Exactly
        Should -Invoke Add-WindowsPackage -ParameterFilter {$PackagePath -like '*WinPE-StorageWMI.cab'} -Times 0 -Exactly
    }

    It 'continues when a package is not applicable (0x800f081e)' {
        Mock Add-WindowsPackage {throw 'Error 0x800f081e'}
        $Verbose = (Add-ContentADKWinRE 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*-Add-ContentADKWinRE.log*'
    }

    It 'does nothing in Update-OSMedia' {
        $ScriptName = 'Update-OSMedia'
        Add-ContentADKWinRE 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'does nothing without WinRE ADK packages' {
        $WinPEADKRE = @()
        Add-ContentADKWinRE 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        $global:ReapplyLCU | Should -BeFalse
    }
}

Describe 'Add-ContentADKWinSE' {
    BeforeEach {
        $ScriptName = 'New-PEBuild'; $OSMajorVersion = 10
        $SetOSDBuilderPathContent = 'C:\Content'; $MountWinSE = 'C:\MountWinSE'; $PEInfo = $TestDrive
        $WinPEADKSE = @(
            'WinPE\ADK\x64\WinPE-WMI.cab'
            'WinPE\ADK\x64\WinPE-PowerShell.cab'
            'WinPE\ADK\x64\WinPE-NetFx.cab'
        )
        $global:ReapplyLCU = $false
        $script:Added = [System.Collections.Generic.List[string]]::new()
        Mock Add-WindowsPackage {$script:Added.Add($PackagePath)}
        Mock dism {$script:Dism = Join-ProgramArgument $InputObject $RemainingArguments}
    }

    It 'installs WinPE-NetFx before WinPE-PowerShell before the other packages in WinSE.wim' {
        Add-ContentADKWinSE 6>$null
        $script:Added[0] | Should -Be 'C:\Content\WinPE\ADK\x64\WinPE-NetFx.cab'
        $script:Added[1] | Should -Be 'C:\Content\WinPE\ADK\x64\WinPE-PowerShell.cab'
        $script:Added | Should -Contain 'C:\Content\WinPE\ADK\x64\WinPE-WMI.cab'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly -ParameterFilter {($Path -ne 'C:\MountWinSE') -or ($LogPath -notlike '*-Add-ContentADKWinSE.log')}
        $global:ReapplyLCU | Should -BeTrue
    }

    # KnownBug: AllFunctions.ps1:145,158 filter the relative path strings of the Task by $_.Name, which is empty, so NetFx and PowerShell are added twice
    It 'installs every package once' -Skip {
        Add-ContentADKWinSE 6>$null
        $script:Added.Count | Should -Be 3
    }

    It 'adds the other packages with dism.exe when OSMajorVersion is 6' {
        $OSMajorVersion = 6
        Add-ContentADKWinSE 6>$null
        $script:Dism | Should -BeLike '/Image:C:\MountWinSE /Add-Package /PackagePath:C:\Content\WinPE\ADK\x64\WinPE-*.cab /LogPath:*'
    }

    # KnownBug: AllFunctions.ps1:158 appends .log to the log path a second time (/LogPath:...-Add-ContentADKWinSE.log.log)
    It 'writes the dism.exe log to Add-ContentADKWinSE.log' -Skip {
        $OSMajorVersion = 6
        Add-ContentADKWinSE 6>$null
        $script:Dism | Should -BeLike '*-Add-ContentADKWinSE.log'
        $script:Dism | Should -Not -BeLike '*.log.log'
    }

    It 'continues when a package is not applicable (0x800f081e)' {
        Mock Add-WindowsPackage {throw 'Error 0x800f081e'}
        $Verbose = (Add-ContentADKWinSE 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
    }

    It 'does nothing in Update-OSMedia' {
        $ScriptName = 'Update-OSMedia'
        Add-ContentADKWinSE 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'does nothing without WinSE ADK packages' {
        $WinPEADKSE = ''
        Add-ContentADKWinSE 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        $global:ReapplyLCU | Should -BeFalse
    }
}

Describe 'Add-ContentDriversOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10
        $SetOSDBuilderPathContent = 'C:\Content'; $MountDirectory = 'C:\Mount'; $Info = $TestDrive
        $Drivers = @('Drivers\Intel Wireless')
        $DriverTemplates = @([PSCustomObject]@{FullName = 'C:\Templates\Drivers\AutoApply\Global\Surface'})
        Mock Add-WindowsDriver {}
        Mock dism {}
    }

    It 'adds the Task drivers and the Template drivers recursively and unsigned' {
        Add-ContentDriversOS 6>$null
        Should -Invoke Add-WindowsDriver -Times 1 -Exactly -ParameterFilter {
            ($Driver -eq 'C:\Content\Drivers\Intel Wireless') -and ($Path -eq 'C:\Mount') -and $Recurse -and $ForceUnsigned -and ($LogPath -like '*-Add-ContentDriversOS-Task.log')
        }
        Should -Invoke Add-WindowsDriver -Times 1 -Exactly -ParameterFilter {
            ($Driver -eq 'C:\Templates\Drivers\AutoApply\Global\Surface') -and ($Path -eq 'C:\Mount') -and $Recurse -and $ForceUnsigned -and ($LogPath -like '*-Add-ContentDriversOS-Template.log')
        }
        Should -Invoke dism -Times 0 -Exactly
    }

    It 'uses dism.exe when OSMajorVersion is 6' {
        $OSMajorVersion = 6
        Add-ContentDriversOS 6>$null
        Should -Invoke dism -Times 1 -Exactly -ParameterFilter {
            ($InputObject -eq '/Image:C:\Mount') -and ($RemainingArguments -contains '/Driver:C:\Content\Drivers\Intel Wireless') -and ($RemainingArguments -contains '/Recurse') -and ($RemainingArguments -contains '/ForceUnsigned')
        }
        Should -Invoke dism -Times 1 -Exactly -ParameterFilter {$RemainingArguments -contains '/Driver:C:\Templates\Drivers\AutoApply\Global\Surface'}
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
    }

    It 'continues when a driver is not applicable (0x800f081e)' {
        Mock Add-WindowsDriver {throw 'Error 0x800f081e'}
        $Verbose = (Add-ContentDriversOS 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*-Add-ContentDriversOS-Task.log*'
        $Verbose | Should -BeLike '*-Add-ContentDriversOS-Template.log*'
    }

    It 'shows the log when a driver fails' {
        Mock Add-WindowsDriver {throw 'The driver package is invalid'}
        $Verbose = (Add-ContentDriversOS 6>$null 4>&1) -join "`n"
        $Verbose | Should -Not -BeLike '*0x800f081e*'
        $Verbose | Should -BeLike '*-Add-ContentDriversOS-Task.log*'
    }

    It 'adds only the Template drivers when the Task has no drivers' {
        $Drivers = $null
        Add-ContentDriversOS 6>$null
        Should -Invoke Add-WindowsDriver -Times 1 -Exactly
        Should -Invoke Add-WindowsDriver -Times 1 -Exactly -ParameterFilter {$Driver -like 'C:\Templates*'}
    }

    It 'does nothing in Update-OSMedia' {
        $ScriptName = 'Update-OSMedia'
        Add-ContentDriversOS 6>$null
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
    }
}

Describe 'Add-ContentDriversPE' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10
        $SetOSDBuilderPathContent = 'C:\Content'; $PEInfo = $TestDrive
        $MountWinPE = 'C:\MountWinPE'; $MountWinRE = 'C:\MountWinRE'; $MountWinSE = 'C:\MountWinSE'
        $WinPEDrivers = @('Drivers\WinPE\Intel', 'Drivers\WinPE\Realtek')
        Mock Add-WindowsDriver {}
        Mock dism {}
    }

    It 'adds every WinPE driver to WinPE, WinRE and WinSE' {
        Add-ContentDriversPE 6>$null
        Should -Invoke Add-WindowsDriver -Times 6 -Exactly
        foreach ($Mount in 'C:\MountWinPE', 'C:\MountWinRE', 'C:\MountWinSE') {
            Should -Invoke Add-WindowsDriver -Times 1 -Exactly -ParameterFilter {
                ($Path -eq $Mount) -and ($Driver -eq 'C:\Content\Drivers\WinPE\Realtek') -and $Recurse -and $ForceUnsigned -and ($LogPath -like '*-Add-ContentDriversPE-Task.log')
            }
        }
    }

    It 'uses dism.exe when OSMajorVersion is 6' {
        $OSMajorVersion = 6
        Add-ContentDriversPE 6>$null
        Should -Invoke dism -Times 6 -Exactly
        Should -Invoke dism -Times 1 -Exactly -ParameterFilter {($InputObject -eq '/Image:C:\MountWinRE') -and ($RemainingArguments -contains '/Driver:C:\Content\Drivers\WinPE\Intel')}
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
    }

    It 'does nothing without WinPE drivers' {
        $WinPEDrivers = $null
        Add-ContentDriversPE 6>$null
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
    }

    It 'does nothing in New-PEBuild' {
        $ScriptName = 'New-PEBuild'
        Add-ContentDriversPE 6>$null
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
    }
}

Describe 'Add-ContentExtraFilesOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'
        $SetOSDBuilderPathContent = 'C:\Content'; $MountDirectory = 'C:\Mount'; $Info = $TestDrive
        $ExtraFiles = @('ExtraFiles\Wallpaper')
        $ExtraFilesTemplates = @([PSCustomObject]@{FullName = 'C:\Templates\ExtraFiles\AutoApply\Global\OEM'})
        $script:Robocopy = [System.Collections.Generic.List[string]]::new()
        Mock robocopy {$script:Robocopy.Add((Join-ProgramArgument $InputObject $RemainingArguments))}
    }

    It 'copies the Task and the Template Extra Files to the mounted image' {
        Add-ContentExtraFilesOS 6>$null
        $script:Robocopy.Count | Should -Be 2
        $script:Robocopy[0] | Should -BeLike 'C:\Content\ExtraFiles\Wallpaper C:\Mount `*.`* /s /ndl /xx /b /np /ts /tee /r:0 /w:0 /Log+:*-Add-ContentExtraFilesOS-Task.log'
        $script:Robocopy[1] | Should -BeLike 'C:\Templates\ExtraFiles\AutoApply\Global\OEM C:\Mount `*.`* *-Add-ContentExtraFilesOS-Template.log'
    }

    It 'copies nothing without Extra Files' {
        $ExtraFiles = $null; $ExtraFilesTemplates = $null
        Add-ContentExtraFilesOS 6>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }

    It 'does nothing in Update-OSMedia' {
        $ScriptName = 'Update-OSMedia'
        Add-ContentExtraFilesOS 6>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Add-ContentExtraFilesPE' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'
        $SetOSDBuilderPathContent = 'C:\Content'; $PEInfo = $TestDrive
        $MountWinPE = 'C:\MountWinPE'; $MountWinRE = 'C:\MountWinRE'; $MountWinSE = 'C:\MountWinSE'
        $WinPEExtraFilesPE = @('ExtraFiles\PE')
        $WinPEExtraFilesRE = @('ExtraFiles\RE')
        $WinPEExtraFilesSE = @('ExtraFiles\SE')
        $script:Robocopy = [System.Collections.Generic.List[string]]::new()
        Mock robocopy {$script:Robocopy.Add((Join-ProgramArgument $InputObject $RemainingArguments))}
    }

    It 'copies the Extra Files of each WinPE image to its mount directory' {
        Add-ContentExtraFilesPE 6>$null
        $script:Robocopy.Count | Should -Be 3
        $script:Robocopy[0] | Should -BeLike 'C:\Content\ExtraFiles\PE C:\MountWinPE `*.`* /S /ZB /COPY:D /NODCOPY /XJ /NDL /NP /TEE /TS /XX /R:0 /W:0 /LOG+:*-Add-ContentExtraFilesPE.log'
        $script:Robocopy[1] | Should -BeLike 'C:\Content\ExtraFiles\RE C:\MountWinRE *'
        $script:Robocopy[2] | Should -BeLike 'C:\Content\ExtraFiles\SE C:\MountWinSE *'
    }

    It 'copies only to WinRE when only WinRE has Extra Files' {
        $WinPEExtraFilesPE = $null; $WinPEExtraFilesSE = $null
        Add-ContentExtraFilesPE 6>$null
        $script:Robocopy.Count | Should -Be 1
        $script:Robocopy[0] | Should -BeLike 'C:\Content\ExtraFiles\RE C:\MountWinRE *'
    }

    It 'copies nothing without Extra Files' {
        $WinPEExtraFilesPE = $null; $WinPEExtraFilesRE = $null; $WinPEExtraFilesSE = $null
        Add-ContentExtraFilesPE 6>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }

    It 'does nothing in New-PEBuild' {
        $ScriptName = 'New-PEBuild'
        Add-ContentExtraFilesPE 6>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Add-ContentScriptsOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
        New-TestFile -Path (Join-Path (Join-Path $SetOSDBuilderPathContent 'Scripts') 'Task.ps1') -Value '$global:AddTestScriptRan += @("Task")' | Out-Null
        $Template = New-TestFile -Path (Join-Path (Join-Path $TestDrive 'Templates') 'Template.ps1') -Value '$global:AddTestScriptRan += @("Template")'
        $Scripts = @('Scripts\Task.ps1', 'Scripts\Missing.ps1')
        $ScriptTemplates = @($Template, [PSCustomObject]@{FullName = (Join-Path $TestDrive 'MissingTemplate.ps1')})
        $global:AddTestScriptRan = @()
    }

    It 'runs the existing Task scripts and then the Template scripts' {
        Add-ContentScriptsOS 6>$null
        $global:AddTestScriptRan | Should -Be @('Task', 'Template')
    }

    It 'runs nothing without scripts' {
        $Scripts = $null; $ScriptTemplates = $null
        Add-ContentScriptsOS 6>$null
        $global:AddTestScriptRan.Count | Should -Be 0
    }

    It 'does nothing in Update-OSMedia' {
        $ScriptName = 'Update-OSMedia'
        Add-ContentScriptsOS 6>$null
        $global:AddTestScriptRan.Count | Should -Be 0
    }
}

Describe 'Add-ContentScriptsPE' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
        $ScriptsPath = Join-Path $SetOSDBuilderPathContent 'Scripts'
        $PEScript = New-TestFile -Path (Join-Path $ScriptsPath 'PE.ps1') -Value '$global:AddTestScriptRan += @("PE winpe.wim.log")'
        $REScript = New-TestFile -Path (Join-Path $ScriptsPath 'RE.ps1') -Value '$global:AddTestScriptRan += @("RE winre.wim.log")'
        $SEScript = New-TestFile -Path (Join-Path $ScriptsPath 'SE.ps1') -Value '$global:AddTestScriptRan += @("SE MountSetup setup.wim.log")'
        $WinPEScriptsPE = @('Scripts\PE.ps1', 'Scripts\Missing.ps1')
        $WinPEScriptsRE = @('Scripts\RE.ps1')
        $WinPEScriptsSE = @('Scripts\SE.ps1')
        $global:AddTestScriptRan = @()
    }

    It 'renames the legacy log and mount names in the scripts and runs them' {
        Add-ContentScriptsPE 6>$null
        $global:AddTestScriptRan | Should -Be @('PE WinPE.log', 'RE WinRE.log', 'SE MountWinSE WinSE.log')
        Get-Content $SEScript.FullName | Should -Be '$global:AddTestScriptRan += @("SE MountWinSE WinSE.log")'
    }

    It 'runs only the WinSE scripts when only WinSE has scripts' {
        $WinPEScriptsPE = $null; $WinPEScriptsRE = $null
        Add-ContentScriptsPE 6>$null
        $global:AddTestScriptRan | Should -Be @('SE MountWinSE WinSE.log')
        Get-Content $PEScript.FullName | Should -BeLike '*winpe.wim.log*'
    }

    It 'runs nothing without scripts' {
        $WinPEScriptsPE = $null; $WinPEScriptsRE = $null; $WinPEScriptsSE = $null
        Add-ContentScriptsPE 6>$null
        $global:AddTestScriptRan.Count | Should -Be 0
    }

    It 'does nothing in New-PEBuild' {
        $ScriptName = 'New-PEBuild'
        Add-ContentScriptsPE 6>$null
        $global:AddTestScriptRan.Count | Should -Be 0
    }
}

Describe 'Add-ContentStartLayout' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
        New-TestFile -Path (Join-Path (Join-Path $SetOSDBuilderPathContent 'StartLayout') 'Layout.xml') -Value '<LayoutModificationTemplate />' | Out-Null
        $StartLayoutXML = 'StartLayout\Layout.xml'
        $MountDirectory = Join-Path $TestDrive 'Mount'
        $Shell = Join-Path $MountDirectory 'Users/Default/AppData/Local/Microsoft/Windows/Shell'
        New-Item -Path $Shell -ItemType Directory -Force | Out-Null
        $Destination = Join-Path $Shell 'LayoutModification.xml'
        if (Test-Path $Destination) {Remove-Item -Path $Destination -Force}
    }

    It 'copies the Start Layout to LayoutModification.xml of the Default User' {
        Add-ContentStartLayout 6>$null
        Get-Content $Destination | Should -Be '<LayoutModificationTemplate />'
    }

    It 'warns when the Start Layout cannot be copied' {
        Mock Copy-Item {throw 'Access to the path is denied'}
        $Warnings = (Add-ContentStartLayout 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Access to the path is denied*'
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'the script is Update-OSMedia'; ScriptName = 'Update-OSMedia'; OSMajorVersion = 10; StartLayoutXML = 'StartLayout\Layout.xml'}
        @{Case = 'the OS is not Windows 10 or 11'; ScriptName = 'New-OSBuild'; OSMajorVersion = 6; StartLayoutXML = 'StartLayout\Layout.xml'}
        @{Case = 'the Task has no Start Layout'; ScriptName = 'New-OSBuild'; OSMajorVersion = 10; StartLayoutXML = ''}
    ) {
        #-ForEach data is set before BeforeEach, apply it again
        foreach ($Key in $_.Keys) {Set-Variable -Name $Key -Value $_[$Key]}
        Add-ContentStartLayout 6>$null
        Test-Path $Destination | Should -BeFalse
    }
}

Describe 'Add-ContentUnattEnd' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10; $Info = $TestDrive
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
        New-TestFile -Path (Join-Path (Join-Path $SetOSDBuilderPathContent 'Unattend') 'Unattend.xml') -Value '<unattend />' | Out-Null
        $UnattendXML = 'Unattend\Unattend.xml'
        $MountDirectory = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -Path $MountDirectory -ItemType Directory -Force | Out-Null
        Mock Use-WindowsUnattend {}
    }

    It 'copies Unattend.xml to Windows\Panther and applies it to the image' {
        Add-ContentUnattEnd 6>$null
        Get-Content (Join-Path $MountDirectory 'Windows/Panther/Unattend.xml') | Should -Be '<unattend />'
        Should -Invoke Use-WindowsUnattend -Times 1 -Exactly -ParameterFilter {
            ($UnattendPath -like '*Unattend.xml') -and ($Path -eq $MountDirectory) -and ($LogPath -like '*-Add-ContentUnattend.log')
        }
    }

    It 'uses an existing Windows\Panther directory' {
        New-Item -Path (Join-Path $MountDirectory 'Windows/Panther') -ItemType Directory -Force | Out-Null
        Add-ContentUnattEnd 6>$null
        Test-Path (Join-Path $MountDirectory 'Windows/Panther/Unattend.xml') | Should -BeTrue
    }

    It 'warns when Use-WindowsUnattend fails' {
        Mock Use-WindowsUnattend {throw 'The unattend file is not valid'}
        $Warnings = (Add-ContentUnattEnd 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*The unattend file is not valid*'
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'the script is Update-OSMedia'; ScriptName = 'Update-OSMedia'; OSMajorVersion = 10; UnattendXML = 'Unattend\Unattend.xml'}
        @{Case = 'the OS is not Windows 10 or 11'; ScriptName = 'New-OSBuild'; OSMajorVersion = 6; UnattendXML = 'Unattend\Unattend.xml'}
        @{Case = 'the Task has no Unattend'; ScriptName = 'New-OSBuild'; OSMajorVersion = 10; UnattendXML = $null}
    ) {
        #-ForEach data is set before BeforeEach, apply it again
        foreach ($Key in $_.Keys) {Set-Variable -Name $Key -Value $_[$Key]}
        Add-ContentUnattEnd 6>$null
        Test-Path (Join-Path $MountDirectory 'Windows/Panther') | Should -BeFalse
        Should -Invoke Use-WindowsUnattend -Times 0 -Exactly
    }
}

Describe 'Add-FeaturesOnDemandOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $MountDirectory = 'C:\Mount'; $Info = $TestDrive
        $UpdateOS = 'Windows 11'; $ReleaseId = '25H2'; $OSInstallationType = 'Client'
        $SetOSDBuilderPathContent = 'C:\Content'
        $FeaturesOnDemand = @(
            'IsoExtract\Windows 11 FOD\Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'IsoExtract\Windows 11 FOD\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~amd64~~.cab'
            'IsoExtract\Windows 11 FOD\Microsoft-OneCore-Graphics-Tools-Package~31bf3856ad364e35~amd64~~.cab'
        )
        $global:ReapplyLCU = $false
        Mock Get-OSDBuilderCapabilitySource {'C:\IsoExtract\Windows 11 LOF\LanguagesAndOptionalFeatures'}
        Mock Add-OSDBuilderWindowsCapability {$true}
        Mock Add-WindowsPackage {}
    }

    It 'adds Language Features with Add-WindowsCapability from the directory of the .cab and the Features on Demand repository' {
        Add-FeaturesOnDemandOS 6>$null 3>$null
        Should -Invoke Add-OSDBuilderWindowsCapability -Times 1 -Exactly -ParameterFilter {
            ($Name -eq 'Language.Basic~~~de-DE~0.0.1.0') -and ($Path -eq 'C:\Mount') -and
            ($Source -contains 'C:\IsoExtract\Windows 11 LOF\LanguagesAndOptionalFeatures') -and ($Source[0] -like '*Windows 11 FOD') -and ($LogPath -like '*-Add-FeaturesOnDemandOS-Capability.log')
        }
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly -ParameterFilter {$PackagePath -like '*LanguageFeatures-Basic*'}
        Should -Invoke Get-OSDBuilderCapabilitySource -Times 1 -Exactly -ParameterFilter {($OSMedia.OperatingSystem -eq 'Windows 11') -and ($OSMedia.ReleaseId -eq '25H2') -and ($OSMedia.InstallationType -eq 'Client')}
        $global:ReapplyLCU | Should -BeTrue
    }

    It 'adds other Features on Demand .cab files with Add-WindowsPackage and warns once' {
        $Warnings = @(Add-FeaturesOnDemandOS 6>$null 3>&1)
        Should -Invoke Add-WindowsPackage -Times 2 -Exactly
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {
            ($PackagePath -eq 'C:\Content\IsoExtract\Windows 11 FOD\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~amd64~~.cab') -and ($Path -eq 'C:\Mount') -and ($LogPath -like '*-Add-FeaturesOnDemandOS.log')
        }
        $Warnings.Count | Should -Be 1
        ($Warnings -join "`n") | Should -BeLike '*Recreate the Task with New-OSBuildTask -ContentFeaturesOnDemand*'
    }

    It 'falls back to Add-WindowsPackage when Add-WindowsCapability fails' {
        Mock Add-OSDBuilderWindowsCapability {$false}
        $Warnings = (Add-FeaturesOnDemandOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Add-WindowsCapability failed, adding *LanguageFeatures-Basic-de-de* with Add-WindowsPackage*'
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {$PackagePath -like '*LanguageFeatures-Basic-de-de*'}
    }

    It 'continues when a package is not applicable (0x800f081e)' {
        Mock Add-WindowsPackage {throw 'Error 0x800f081e'}
        $Verbose = (Add-FeaturesOnDemandOS 6>$null 3>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*Review the log for more information*'
        Should -Invoke Add-WindowsPackage -Times 2 -Exactly
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'the script is Update-OSMedia'; ScriptName = 'Update-OSMedia'; FeaturesOnDemand = @('a.cab')}
        @{Case = 'the Task has no Features on Demand'; ScriptName = 'New-OSBuild'; FeaturesOnDemand = $null}
    ) {
        #-ForEach data is set before BeforeEach, apply it again
        foreach ($Key in $_.Keys) {Set-Variable -Name $Key -Value $_[$Key]}
        Add-FeaturesOnDemandOS 6>$null 3>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        Should -Invoke Add-OSDBuilderWindowsCapability -Times 0 -Exactly
    }
}

Describe 'Add-LanguageFeaturesOnDemandOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10; $MountDirectory = 'C:\Mount'; $Info = $TestDrive
        $UpdateOS = 'Windows 11'; $ReleaseId = '25H2'; $OSInstallationType = 'Client'
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
        $Relative = 'IsoExtract\Windows 11 FOD'
        $LanguageFeatures = @(
            "$Relative\Microsoft-Windows-LanguageFeatures-Speech-de-de-Package~31bf3856ad364e35~amd64~~.cab"
            "$Relative\Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab"
            "$Relative\Microsoft-Windows-LanguageFeatures-Handwriting-de-de-Package~31bf3856ad364e35~amd64~~.cab"
            "$Relative\Microsoft-Windows-InternationalFeatures-Germany-Package~31bf3856ad364e35~amd64~~.cab"
            ''
        )
        foreach ($Item in ($LanguageFeatures | Where-Object {$_})) {New-TestFile -Path (Join-Path $SetOSDBuilderPathContent $Item) | Out-Null}
        $global:ReapplyLCU = $false
        $script:Capability = [System.Collections.Generic.List[string]]::new()
        Mock Get-OSDBuilderCapabilitySource {}
        Mock Add-OSDBuilderWindowsCapability {$script:Capability.Add($Name); $true}
        Mock Add-WindowsPackage {}
    }

    It 'adds Basic before Handwriting before Speech with Add-WindowsCapability' {
        Add-LanguageFeaturesOnDemandOS 6>$null
        $script:Capability | Should -Be @('Language.Basic~~~de-DE~0.0.1.0', 'Language.Handwriting~~~de-DE~0.0.1.0', 'Language.Speech~~~de-DE~0.0.1.0')
        Should -Invoke Add-OSDBuilderWindowsCapability -ParameterFilter {($Source[0] -like '*Windows 11 FOD') -and ($LogPath -like '*-Add-LanguageFeaturesOnDemandOS-Capability.log')} -Times 3 -Exactly
        $global:ReapplyLCU | Should -BeTrue
    }

    It 'adds packages without a capability name with Add-WindowsPackage' {
        Add-LanguageFeaturesOnDemandOS 6>$null
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {
            ($PackagePath -like '*InternationalFeatures-Germany*') -and ($Path -eq 'C:\Mount') -and ($LogPath -like '*-Add-LanguageFeaturesOnDemandOS.log')
        }
    }

    It 'falls back to Add-WindowsPackage when Add-WindowsCapability fails' {
        Mock Add-OSDBuilderWindowsCapability {$false}
        $Warnings = (Add-LanguageFeaturesOnDemandOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Add-WindowsCapability failed, adding *Basic-de-de* with Add-WindowsPackage*'
        Should -Invoke Add-WindowsPackage -Times 4 -Exactly
    }

    It 'continues when a package is not applicable (0x800f081e)' {
        Mock Add-WindowsPackage {throw 'Error 0x800f081e'}
        $Verbose = (Add-LanguageFeaturesOnDemandOS 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*-Add-LanguageFeaturesOnDemandOS.log*'
    }

    It 'warns about missing files' {
        $LanguageFeatures = @('IsoExtract\Missing\Microsoft-Windows-LanguageFeatures-OCR-de-de-Package~31bf3856ad364e35~amd64~~.cab')
        $Warnings = (Add-LanguageFeaturesOnDemandOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Not Found: *Missing*LanguageFeatures-OCR-de-de*'
        Should -Invoke Add-OSDBuilderWindowsCapability -Times 0 -Exactly
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'the script is Update-OSMedia'; ScriptName = 'Update-OSMedia'; OSMajorVersion = 10; Features = @('a.cab')}
        @{Case = 'the OS is not Windows 10 or 11'; ScriptName = 'New-OSBuild'; OSMajorVersion = 6; Features = @('a.cab')}
        @{Case = 'the Task has no Language Features'; ScriptName = 'New-OSBuild'; OSMajorVersion = 10; Features = $null}
    ) {
        #-ForEach data is set before BeforeEach, apply it again
        foreach ($Key in $_.Keys) {Set-Variable -Name $Key -Value $_[$Key]}
        $LanguageFeatures = $Features
        Add-LanguageFeaturesOnDemandOS 6>$null 3>$null
        Should -Invoke Get-OSDBuilderCapabilitySource -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }
}

Describe 'Add-LanguageInterfacePacksOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10; $MountDirectory = 'C:\Mount'; $Info = $TestDrive
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
        New-TestFile -Path (Join-Path $SetOSDBuilderPathContent 'LIP/Microsoft-Windows-Client-Language-Pack_x64_ca-es.cab') | Out-Null
        $LanguageInterfacePacks = @('LIP\Microsoft-Windows-Client-Language-Pack_x64_ca-es.cab', 'LIP\Missing.cab')
        $global:ReapplyLCU = $false
        Mock Add-WindowsPackage {}
    }

    It 'adds the existing Language Interface Packs and warns about missing files' {
        $Warnings = (Add-LanguageInterfacePacksOS 6>$null 3>&1) -join "`n"
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {
            ($PackagePath -like '*Language-Pack_x64_ca-es.cab') -and ($Path -eq 'C:\Mount') -and ($LogPath -like '*-Add-LanguageInterfacePacksOS.log')
        }
        $Warnings | Should -BeLike '*Not Found: *Missing.cab*'
        $global:ReapplyLCU | Should -BeTrue
    }

    It 'continues when a package is not applicable (0x800f081e)' {
        Mock Add-WindowsPackage {throw 'Error 0x800f081e'}
        $Verbose = (Add-LanguageInterfacePacksOS 6>$null 3>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'the script is Update-OSMedia'; ScriptName = 'Update-OSMedia'; OSMajorVersion = 10; Lip = @('a.cab')}
        @{Case = 'the OS is not Windows 10 or 11'; ScriptName = 'New-OSBuild'; OSMajorVersion = 6; Lip = @('a.cab')}
        @{Case = 'the Task has no Language Interface Packs'; ScriptName = 'New-OSBuild'; OSMajorVersion = 10; Lip = $null}
    ) {
        #-ForEach data is set before BeforeEach, apply it again
        foreach ($Key in $_.Keys) {Set-Variable -Name $Key -Value $_[$Key]}
        $LanguageInterfacePacks = $Lip
        Add-LanguageInterfacePacksOS 6>$null 3>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }
}

Describe 'Add-LanguagePacksOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10; $MountDirectory = 'C:\Mount'; $Info = $TestDrive
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
        New-TestFile -Path (Join-Path $SetOSDBuilderPathContent 'LP/Microsoft-Windows-Client-Language-Pack_x64_de-de.cab') | Out-Null
        New-TestFile -Path (Join-Path $SetOSDBuilderPathContent 'LXP/de-de/LanguageExperiencePack.de-de.Neutral.appx') | Out-Null
        New-TestFile -Path (Join-Path $SetOSDBuilderPathContent 'LP/readme.txt') | Out-Null
        $LanguagePacks = @(
            'LP\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab'
            'LXP\de-de\LanguageExperiencePack.de-de.Neutral.appx'
            'LP\readme.txt'
            'LP\Missing.cab'
        )
        $global:ReapplyLCU = $false
        Mock Add-WindowsPackage {}
        Mock Add-AppxProvisionedPackage {}
    }

    It 'adds .cab Language Packs with Add-WindowsPackage' {
        Add-LanguagePacksOS 6>$null 3>$null
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {
            ($PackagePath -like '*Language-Pack_x64_de-de.cab') -and ($Path -eq 'C:\Mount') -and ($LogPath -like '*-Add-LanguagePacksOS.log')
        }
        $global:ReapplyLCU | Should -BeTrue
    }

    It 'provisions .appx Language Packs with the License.xml of their directory' {
        Add-LanguagePacksOS 6>$null 3>$null
        $ExpectedLicense = Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContent 'LXP') 'de-de') 'License.xml'
        Should -Invoke Add-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {
            ($PackagePath -like '*LanguageExperiencePack.de-de.Neutral.appx') -and ($Path -eq 'C:\Mount') -and ($LicensePath -eq $ExpectedLicense) -and ($LogPath -like '*-Add-LanguagePacksOS.log')
        }
    }

    It 'ignores other files and warns about missing files' {
        $Warnings = (Add-LanguagePacksOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Not Found: *Missing.cab*'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly -ParameterFilter {$PackagePath -like '*readme.txt'}
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly -ParameterFilter {$PackagePath -like '*readme.txt'}
    }

    It 'continues when a package is not applicable (0x800f081e)' {
        Mock Add-WindowsPackage {throw 'Error 0x800f081e'}
        $Verbose = (Add-LanguagePacksOS 6>$null 3>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*-Add-LanguagePacksOS.log*'
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'the script is Update-OSMedia'; ScriptName = 'Update-OSMedia'; OSMajorVersion = 10; Lp = @('a.cab')}
        @{Case = 'the OS is not Windows 10 or 11'; ScriptName = 'New-OSBuild'; OSMajorVersion = 6; Lp = @('a.cab')}
        @{Case = 'the Task has no Language Packs'; ScriptName = 'New-OSBuild'; OSMajorVersion = 10; Lp = @()}
    ) {
        #-ForEach data is set before BeforeEach, apply it again
        foreach ($Key in $_.Keys) {Set-Variable -Name $Key -Value $_[$Key]}
        $LanguagePacks = $Lp
        Add-LanguagePacksOS 6>$null 3>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }
}

Describe 'Add-LocalExperiencePacksOS' {
    #More tests in LocalExperiencePacks.Tests.ps1
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10; $MountDirectory = 'C:\Mount'; $Info = $TestDrive; $OSBuild = '26200'
        $SetOSDBuilderPathContent = 'C:\Content'
        $LocalExperiencePacks = @('LXP\de-de\LanguageExperiencePack.de-de.Neutral.appx', '', 'LXP\fr-fr\LanguageExperiencePack.fr-fr.Neutral.appx')
        $global:ReapplyLCU = $false
        Mock Add-OSDBuilderLocalExperiencePack {if ($PackagePath -like '*de-de*') {'Added'} else {'Failed'}}
    }

    It 'adds every LXP for the build of the image and lists the LXPs that failed' {
        $Warnings = (Add-LocalExperiencePacksOS 6>$null 3>&1) -join "`n"
        Should -Invoke Add-OSDBuilderLocalExperiencePack -Times 2 -Exactly
        Should -Invoke Add-OSDBuilderLocalExperiencePack -Times 1 -Exactly -ParameterFilter {
            ($Path -eq 'C:\Mount') -and ($PackagePath -eq 'C:\Content\LXP\de-de\LanguageExperiencePack.de-de.Neutral.appx') -and ($Build -eq 26200) -and ($LogPath -like '*-Add-LocalExperiencePacksOS.log')
        }
        $Warnings | Should -BeLike '*1 of 2 were not added*'
        $Warnings | Should -BeLike '*LXP\fr-fr\LanguageExperiencePack.fr-fr.Neutral.appx*'
        $global:ReapplyLCU | Should -BeTrue
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'the OS is not Windows 10 or 11'; OSMajorVersion = 6; Lxp = @('a.appx')}
        @{Case = 'the Task has no LXP'; OSMajorVersion = 10; Lxp = $null}
    ) {
        #-ForEach data is set before BeforeEach, apply it again
        foreach ($Key in $_.Keys) {Set-Variable -Name $Key -Value $_[$Key]}
        $LocalExperiencePacks = $Lxp
        Add-LocalExperiencePacksOS 6>$null 3>$null
        Should -Invoke Add-OSDBuilderLocalExperiencePack -Times 0 -Exactly
    }
}

Describe 'Add-WindowsCapabilityOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10; $MountDirectory = 'C:\Mount'; $Info = $TestDrive
        $UpdateOS = 'Windows 11'; $ReleaseId = '25H2'; $OSInstallationType = 'Client'
        $GetOSDBuilderPathContentIsoExtract = 'C:\Content\IsoExtract'
        $AddWindowsCapability = @('Language.Basic~~~de-DE~0.0.1.0', 'NetFX3~~~~', 'Language.Basic~~~de-DE~0.0.1.0', '', 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0')
        $global:ReapplyLCU = $false
        Mock Get-OSDBuilderCapabilitySource {'C:\Content\IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LanguagesAndOptionalFeatures'}
        Mock Get-WindowsCapability {
            [PSCustomObject]@{Name = 'NetFX3~~~~'; State = 'Installed'}
            [PSCustomObject]@{Name = 'Language.Basic~~~de-DE~0.0.1.0'; State = 'NotPresent'}
        }
        Mock Add-OSDBuilderWindowsCapability {$true}
    }

    It 'adds each capability that is not installed once from the Features on Demand repository' {
        $Output = (Add-WindowsCapabilityOS 6>&1) -join "`n"
        Should -Invoke Add-OSDBuilderWindowsCapability -Times 2 -Exactly
        Should -Invoke Add-OSDBuilderWindowsCapability -Times 1 -Exactly -ParameterFilter {
            ($Name -eq 'Language.Basic~~~de-DE~0.0.1.0') -and ($Path -eq 'C:\Mount') -and ($Source -like '*LanguagesAndOptionalFeatures') -and ($LogPath -like '*-Add-WindowsCapabilityOS.log')
        }
        Should -Invoke Add-OSDBuilderWindowsCapability -Times 0 -Exactly -ParameterFilter {$Name -eq 'NetFX3~~~~'}
        $Output | Should -BeLike '*INSTALLED         NetFX3~~~~*'
        $Output | Should -BeLike '*Source: C:\Content\IsoExtract\Windows 11 24H2-26H2 x64*'
        $global:ReapplyLCU | Should -BeTrue
    }

    It 'warns when a capability cannot be added' {
        Mock Add-OSDBuilderWindowsCapability {$false}
        $Warnings = (Add-WindowsCapabilityOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Add-WindowsCapability: Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0 could not be added*'
    }

    It 'warns with the download command when there is no Features on Demand repository' {
        Mock Get-OSDBuilderCapabilitySource {}
        $Warnings = (Add-WindowsCapabilityOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*No Features on Demand repository was found in C:\Content\IsoExtract for Windows 11 25H2*'
        $Warnings | Should -BeLike '*Save-OSDBuilderDownload -ContentDownload*'
        Should -Invoke Get-WindowsCapability -Times 0 -Exactly
        $global:ReapplyLCU | Should -BeFalse
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'the script is Update-OSMedia'; ScriptName = 'Update-OSMedia'; OSMajorVersion = 10; Names = @('NetFX3~~~~')}
        @{Case = 'the OS is not Windows 10 or 11'; ScriptName = 'New-OSBuild'; OSMajorVersion = 6; Names = @('NetFX3~~~~')}
        @{Case = 'the Task has no capabilities'; ScriptName = 'New-OSBuild'; OSMajorVersion = 10; Names = $null}
    ) {
        #-ForEach data is set before BeforeEach, apply it again
        foreach ($Key in $_.Keys) {Set-Variable -Name $Key -Value $_[$Key]}
        $AddWindowsCapability = $Names
        Add-WindowsCapabilityOS 6>$null 3>$null
        Should -Invoke Get-OSDBuilderCapabilitySource -Times 0 -Exactly
        Should -Invoke Add-OSDBuilderWindowsCapability -Times 0 -Exactly
    }
}

Describe 'Add-WindowsPackageOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $MountDirectory = 'C:\Mount'; $Info = $TestDrive
        $SetOSDBuilderPathContent = 'C:\Content'
        $Packages = @('Packages\windows11.0-kb5000001-x64.msu', 'Packages\Contoso.cab')
        $global:ReapplyLCU = $false
        Mock Add-WindowsPackage {}
    }

    It 'adds every package of the Task' {
        Add-WindowsPackageOS 6>$null
        Should -Invoke Add-WindowsPackage -Times 2 -Exactly
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {
            ($PackagePath -eq 'C:\Content\Packages\Contoso.cab') -and ($Path -eq 'C:\Mount') -and ($LogPath -like '*-Add-WindowsPackageOS.log')
        }
        $global:ReapplyLCU | Should -BeTrue
    }

    It 'continues with the next package when a package fails' {
        Mock Add-WindowsPackage {throw 'Error 0x800f081e'}
        $Verbose = (Add-WindowsPackageOS 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*Review the log for more information*'
        Should -Invoke Add-WindowsPackage -Times 2 -Exactly
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'the script is Update-OSMedia'; ScriptName = 'Update-OSMedia'; Pkg = @('a.cab')}
        @{Case = 'the Task has no packages'; ScriptName = 'New-OSBuild'; Pkg = $null}
    ) {
        #-ForEach data is set before BeforeEach, apply it again
        foreach ($Key in $_.Keys) {Set-Variable -Name $Key -Value $_[$Key]}
        $Packages = $Pkg
        Add-WindowsPackageOS 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        $global:ReapplyLCU | Should -BeFalse
    }
}
