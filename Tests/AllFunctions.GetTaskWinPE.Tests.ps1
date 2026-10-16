BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}

    #Get-ChildItem is mocked with the objects of a Windows file system below $ContentRoot
    #$ContentRoot exists, so Pester can resolve the dynamic parameters of the FileSystem provider (-Directory) on every platform
    $ContentRoot = Join-Path $TestDrive 'Content'
    New-Item -Path $ContentRoot -ItemType Directory -Force | Out-Null
    function New-ContentItem {
        param ([string]$FullName, [int]$Length = 1024)
        [PSCustomObject]@{
            Name         = ($FullName -split '\\')[-1]
            FullName     = $FullName
            Length       = $Length
            CreationTime = [datetime]'2026-10-14'
        }
    }
    #Out-GridView passes everything through, the offered items are collected in $script:GridView
    function Initialize-GridView {
        $script:GridView = New-Object System.Collections.ArrayList
        Mock Out-GridView {[void]$script:GridView.Add($InputObject); $InputObject}
    }

    #ADK and WinPE content of Windows 11 24H2 (x64, x86, language) and Windows 10 2004
    function Initialize-AdkContent {
        $SetOSDBuilderPathContent = $ContentRoot
        $GetOSDBuilderPathContentADK = "$ContentRoot\ADK"
        $GetOSDBuilderPathContentIsoExtract = "$ContentRoot\IsoExtract"
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 11'; InstallationType = 'Client'; Arch = 'x64'; ReleaseId = '25H2'}
        $ExistingTask = $null
        $ContentIsoExtractWinPE = $null
        $Adk11 = "$ContentRoot\ADK\Windows 11 24H2\Windows Preinstallation Environment"
        Mock Get-ChildItem {
            New-ContentItem "$Adk11\amd64\WinPE_OCs\WinPE-WMI.cab"
            New-ContentItem "$Adk11\amd64\WinPE_OCs\WinPE-PowerShell.cab"
            New-ContentItem "$Adk11\amd64\WinPE_OCs\de-de\lp.cab"
            New-ContentItem "$Adk11\amd64\WinPE_OCs\de-de\WinPE-WMI_de-de.cab"
            New-ContentItem "$Adk11\x86\WinPE_OCs\WinPE-WMI.cab"
            New-ContentItem "$ContentRoot\ADK\Windows 10 2004\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-WMI.cab"
            New-ContentItem "$ContentRoot\ADK\Windows 10 2004\Windows Preinstallation Environment\x86\WinPE_OCs\WinPE-WMI.cab"
        } -ParameterFilter {($Filter -eq '*.cab') -and $Recurse}
    }
    function Get-RelativeAdk ($Path) {$Path.Replace("$ContentRoot\", '')}

    #Directories of Content\ExtraFiles and Content\WinPE\ExtraFiles, Empty has no files
    function Initialize-ExtraFilesContent {
        $SetOSDBuilderPathContent = $ContentRoot
        $GetOSDBuilderPathContentExtraFiles = "$ContentRoot\ExtraFiles"
        $ExistingTask = $null
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\ExtraFiles\Wallpaper"
            New-ContentItem "$ContentRoot\ExtraFiles\Empty"
            New-ContentItem "$ContentRoot\WinPE\ExtraFiles\Tools"
        } -ParameterFilter {$Directory}
        Mock Get-ChildItem {if ("$Path" -notlike '*\Empty') {New-ContentItem "$Path\file.txt"}}
    }

    #Scripts of Content\Scripts and Content\WinPE\Scripts
    function Initialize-ScriptsContent {
        $SetOSDBuilderPathContent = $ContentRoot
        $GetOSDBuilderPathContentScripts = "$ContentRoot\Scripts"
        $ExistingTask = $null
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\WinPE\Scripts\Set-WinPE.ps1"
            New-ContentItem "$ContentRoot\Scripts\Set-Wallpaper.ps1"
        } -ParameterFilter {$Filter -eq '*.ps1'}
    }
}

Describe 'Get-TaskWinPEADK' {
    BeforeEach {
        . Initialize-AdkContent
        Initialize-GridView
    }

    It 'offers the x64 ADK packages of the release relative to the Content directory' {
        $Result = Get-TaskWinPEADK 6>$null
        Should -Invoke Get-ChildItem -Times 1 -Exactly -ParameterFilter {($Path -contains "$ContentRoot\WinPE\ADK\*") -and ($Path -contains "$ContentRoot\ADK\*\Windows Preinstallation Environment\*\WinPE_OCs")}
        $script:GridView.FullName | Should -Be @(
            (Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\WinPE-WMI.cab")
            (Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\WinPE-PowerShell.cab")
            (Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\de-de\lp.cab")
            (Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\de-de\WinPE-WMI_de-de.cab")
        )
        Should -Invoke Out-GridView -Times 4 -Exactly -ParameterFilter {($null -ne $InputObject) -and $PassThru -and ($Title -like 'WinPE.wim ADK Packages:*')}
        @($Result | Where-Object {$_}).Count | Should -Be 4
    }

    It 'offers the x86 ADK packages to an x86 OSMedia and adds the WinPE content of the IsoExtract' {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 10'; InstallationType = 'Client'; Arch = 'x86'; ReleaseId = '22H2'}
        $ContentIsoExtractWinPE = @(New-ContentItem 'IsoExtract\Windows 10 2004 x86 WinPE\WinPE-Fonts-Legacy.cab')
        Get-TaskWinPEADK 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('ADK\Windows 10 2004\Windows Preinstallation Environment\x86\WinPE_OCs\WinPE-WMI.cab', 'IsoExtract\Windows 10 2004 x86 WinPE\WinPE-Fonts-Legacy.cab')
    }

    It 'does not offer the ADK packages of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEADK = @((Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\WinPE-WMI.cab"))}
        Get-TaskWinPEADK 6>$null | Out-Null
        $script:GridView.FullName | Should -Not -Contain (Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\WinPE-WMI.cab")
        @($script:GridView | Where-Object {$_}).Count | Should -Be 3
    }

    # KnownBug: Private/AllFunctions.ps1:4214 (and 4245, 4285, 4318 in ADKPE, ADKRE, ADKSE) [array] + $null appends $null, the GridView shows an empty item without WinPE content in the IsoExtract
    It 'does not offer an empty item when the IsoExtract has no WinPE content' -Skip {
        Get-TaskWinPEADK 6>$null | Out-Null
        $script:GridView | Should -Not -Contain $null
        Should -Invoke Out-GridView -Times 0 -Exactly -ParameterFilter {$null -eq $InputObject}
    }

    It 'warns when there are no ADK packages' {
        Mock Get-ChildItem {} -ParameterFilter {$Filter -eq '*.cab'}
        $Warnings = (Get-TaskWinPEADK 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinPE.wim ADK Packages: Add Content to $ContentRoot\ADK*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEADKPE' {
    BeforeEach {
        . Initialize-AdkContent
        Initialize-GridView
    }

    It 'offers the x64 ADK packages of the release for WinPE' {
        $Result = Get-TaskWinPEADKPE 6>$null
        @($script:GridView | Where-Object {$_}).Count | Should -Be 4
        $script:GridView.FullName | Should -Contain (Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\de-de\lp.cab")
        Should -Invoke Out-GridView -Times 4 -Exactly -ParameterFilter {($null -ne $InputObject) -and $PassThru -and ($Title -like 'WinPE.wim ADK Packages:*')}
        @($Result | Where-Object {$_}).Count | Should -Be 4
    }

    It 'offers the x86 ADK packages to an x86 OSMedia and adds the WinPE content of the IsoExtract' {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 10'; InstallationType = 'Client'; Arch = 'x86'; ReleaseId = '22H2'}
        $ContentIsoExtractWinPE = @(New-ContentItem 'IsoExtract\Windows 10 2004 x86 WinPE\WinPE-Fonts-Legacy.cab')
        Get-TaskWinPEADKPE 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('ADK\Windows 10 2004\Windows Preinstallation Environment\x86\WinPE_OCs\WinPE-WMI.cab', 'IsoExtract\Windows 10 2004 x86 WinPE\WinPE-Fonts-Legacy.cab')
    }

    It 'does not offer the ADK packages of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEADKPE = @((Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\WinPE-PowerShell.cab"))}
        Get-TaskWinPEADKPE 6>$null | Out-Null
        $script:GridView.FullName | Should -Not -Contain (Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\WinPE-PowerShell.cab")
        @($script:GridView | Where-Object {$_}).Count | Should -Be 3
    }

    It 'warns when there are no ADK packages' {
        Mock Get-ChildItem {} -ParameterFilter {$Filter -eq '*.cab'}
        $Warnings = (Get-TaskWinPEADKPE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinPE.wim ADK Packages: Add Content to $ContentRoot\ADK*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEADKRE' {
    BeforeEach {
        . Initialize-AdkContent
        Mock Get-OSDBuilderWinPELanguageSource {}
        Initialize-GridView
    }

    It 'offers the x64 ADK packages of the release with the language packs when there is no Languages and Optional Features ISO' {
        $Result = Get-TaskWinPEADKRE 6>$null 3>$null
        @($script:GridView | Where-Object {$_}).Count | Should -Be 4
        Should -Invoke Out-GridView -Times 4 -Exactly -ParameterFilter {($null -ne $InputObject) -and $PassThru -and ($Title -like 'WinRE.wim ADK Packages:*')}
        @($Result | Where-Object {$_}).Count | Should -Be 4
    }

    It 'does not offer the ADK language packs of Windows 11 when the Languages and Optional Features ISO has WinPE languages' {
        Mock Get-OSDBuilderWinPELanguageSource {"$ContentRoot\IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\Windows Preinstallation Environment\x64\WinPE_OCs"}
        Get-TaskWinPEADKRE 6>$null 3>$null | Out-Null
        Should -Invoke Get-OSDBuilderWinPELanguageSource -Times 1 -Exactly -ParameterFilter {$Architecture -eq 'x64'}
        $script:GridView.FullName | Should -Be @(
            (Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\WinPE-WMI.cab")
            (Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\WinPE-PowerShell.cab")
        )
    }

    It 'warns about the size of WinRE' {
        $Warnings = (Get-TaskWinPEADKRE 6>$null 3>&1 | Where-Object {$_ -is [System.Management.Automation.WarningRecord]}) -join "`n"
        $Warnings | Should -BeLike '*If you add too many ADK Packages to WinRE*'
        $Warnings | Should -BeLike '*your WinRE.wim should not be more than 400MB (100MB Free)*'
    }

    It 'offers the x86 ADK packages to an x86 OSMedia and adds the WinPE content of the IsoExtract' {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 10'; InstallationType = 'Client'; Arch = 'x86'; ReleaseId = '22H2'}
        $ContentIsoExtractWinPE = @(New-ContentItem 'IsoExtract\Windows 10 2004 x86 WinPE\WinPE-Fonts-Legacy.cab')
        Get-TaskWinPEADKRE 6>$null 3>$null | Out-Null
        Should -Invoke Get-OSDBuilderWinPELanguageSource -Times 0 -Exactly
        $script:GridView.FullName | Should -Be @('ADK\Windows 10 2004\Windows Preinstallation Environment\x86\WinPE_OCs\WinPE-WMI.cab', 'IsoExtract\Windows 10 2004 x86 WinPE\WinPE-Fonts-Legacy.cab')
    }

    It 'does not offer the ADK packages of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEADKRE = @((Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\WinPE-PowerShell.cab"))}
        Get-TaskWinPEADKRE 6>$null 3>$null | Out-Null
        $script:GridView.FullName | Should -Not -Contain (Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\WinPE-PowerShell.cab")
        @($script:GridView | Where-Object {$_}).Count | Should -Be 3
    }

    It 'warns when there are no ADK packages' {
        Mock Get-ChildItem {} -ParameterFilter {$Filter -eq '*.cab'}
        $Warnings = (Get-TaskWinPEADKRE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinRE.wim ADK Packages: Add Content to $ContentRoot\ADK*"
        $Warnings | Should -Not -BeLike '*too many ADK Packages*'
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEADKSE' {
    BeforeEach {
        . Initialize-AdkContent
        Initialize-GridView
    }

    It 'offers the x64 ADK packages of the release for WinSE' {
        $Result = Get-TaskWinPEADKSE 6>$null
        @($script:GridView | Where-Object {$_}).Count | Should -Be 4
        Should -Invoke Out-GridView -Times 4 -Exactly -ParameterFilter {($null -ne $InputObject) -and $PassThru -and ($Title -like 'WinSE.wim ADK Packages:*')}
        @($Result | Where-Object {$_}).Count | Should -Be 4
    }

    It 'offers the x86 ADK packages to an x86 OSMedia and adds the WinPE content of the IsoExtract' {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 10'; InstallationType = 'Client'; Arch = 'x86'; ReleaseId = '22H2'}
        $ContentIsoExtractWinPE = @(New-ContentItem 'IsoExtract\Windows 10 2004 x86 WinPE\WinPE-Fonts-Legacy.cab')
        Get-TaskWinPEADKSE 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('ADK\Windows 10 2004\Windows Preinstallation Environment\x86\WinPE_OCs\WinPE-WMI.cab', 'IsoExtract\Windows 10 2004 x86 WinPE\WinPE-Fonts-Legacy.cab')
    }

    It 'does not offer the ADK packages of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEADKSE = @((Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\de-de\lp.cab"))}
        Get-TaskWinPEADKSE 6>$null | Out-Null
        $script:GridView.FullName | Should -Not -Contain (Get-RelativeAdk "$Adk11\amd64\WinPE_OCs\de-de\lp.cab")
        @($script:GridView | Where-Object {$_}).Count | Should -Be 3
    }

    It 'warns when there are no ADK packages' {
        Mock Get-ChildItem {} -ParameterFilter {$Filter -eq '*.cab'}
        $Warnings = (Get-TaskWinPEADKSE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinSE.wim ADK Packages: Add Content to $ContentRoot\ADK*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEDaRT' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $GetOSDBuilderPathContentDaRT = "$ContentRoot\DaRT"
        $OSMedia = [PSCustomObject]@{Arch = 'x64'}
        $ExistingTask = $null
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\DaRT\DaRT 10\Toolsx64.cab"
            New-ContentItem "$ContentRoot\DaRT\DaRT 10\Toolsx86.cab"
            New-ContentItem "$ContentRoot\WinPE\DaRT\DaRT 8.1\Toolsx64.cab"
        } -ParameterFilter {($Path -contains "$ContentRoot\DaRT") -and ($Path -contains "$ContentRoot\WinPE\DaRT") -and ($Filter -eq '*.cab')}
        Initialize-GridView
    }

    It 'offers the DaRT packages of the architecture for a single selection' {
        $Result = Get-TaskWinPEDaRT 6>$null
        $script:GridView.FullName | Should -Be @('DaRT\DaRT 10\Toolsx64.cab', 'WinPE\DaRT\DaRT 8.1\Toolsx64.cab')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {($OutputMode -eq 'Single') -and ($Title -like 'WinPEDaRT:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the DaRT package of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEDaRT = 'DaRT\DaRT 10\Toolsx64.cab'}
        Get-TaskWinPEDaRT 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('WinPE\DaRT\DaRT 8.1\Toolsx64.cab')
    }

    It 'warns when there is no DaRT package for the architecture' {
        $OSMedia = [PSCustomObject]@{Arch = 'arm64'}
        $Warnings = (Get-TaskWinPEDaRT 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinPEDaRT: Add Content to $ContentRoot\DaRT*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEDrivers' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $GetOSDBuilderPathContentDrivers = "$ContentRoot\Drivers"
        $ExistingTask = $null
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\Drivers\Dell WinPE"
            New-ContentItem "$ContentRoot\WinPE\Drivers\Intel Network"
        } -ParameterFilter {($Path -contains "$ContentRoot\Drivers") -and ($Path -contains "$ContentRoot\WinPE\Drivers") -and $Directory}
        Initialize-GridView
    }

    It 'offers the driver directories of Content\Drivers and Content\WinPE\Drivers' {
        $Result = Get-TaskWinPEDrivers 6>$null
        $script:GridView.FullName | Should -Be @('Drivers\Dell WinPE', 'WinPE\Drivers\Intel Network')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'WinPEDrivers:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the drivers of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEDrivers = @('Drivers\Dell WinPE')}
        Get-TaskWinPEDrivers 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('WinPE\Drivers\Intel Network')
    }

    It 'warns when there are no drivers' {
        Mock Get-ChildItem {} -ParameterFilter {$Directory}
        $Warnings = (Get-TaskWinPEDrivers 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinPEDrivers: To select WinPE Drivers, add Content to $ContentRoot\Drivers*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEExtraFiles' {
    BeforeEach {
        . Initialize-ExtraFilesContent
        Initialize-GridView
    }

    It 'offers the directories with files of Content\ExtraFiles and Content\WinPE\ExtraFiles' {
        $Result = Get-TaskWinPEExtraFiles 6>$null
        Should -Invoke Get-ChildItem -Times 1 -Exactly -ParameterFilter {$Directory -and ($Path -contains "$ContentRoot\ExtraFiles") -and ($Path -contains "$ContentRoot\WinPE\ExtraFiles")}
        $script:GridView.FullName | Should -Be @('ExtraFiles\Wallpaper', 'WinPE\ExtraFiles\Tools')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'WinPEExtraFiles:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the directories of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEExtraFiles = @('ExtraFiles\Wallpaper')}
        Get-TaskWinPEExtraFiles 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('WinPE\ExtraFiles\Tools')
    }

    It 'warns when there are no directories with files' {
        Mock Get-ChildItem {New-ContentItem "$ContentRoot\ExtraFiles\Empty"} -ParameterFilter {$Directory}
        $Warnings = (Get-TaskWinPEExtraFiles 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinPEExtraFiles: To select WinPE Extra Files, add Content to $ContentRoot\ExtraFiles*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEExtraFilesPE' {
    BeforeEach {
        . Initialize-ExtraFilesContent
        Initialize-GridView
    }

    It 'offers the directories with files for WinPE' {
        $Result = Get-TaskWinPEExtraFilesPE 6>$null
        $script:GridView.FullName | Should -Be @('ExtraFiles\Wallpaper', 'WinPE\ExtraFiles\Tools')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'WinPEExtraFilesPE:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the directories of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEExtraFilesPE = @('WinPE\ExtraFiles\Tools')}
        Get-TaskWinPEExtraFilesPE 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('ExtraFiles\Wallpaper')
    }

    It 'warns when there are no directories with files' {
        Mock Get-ChildItem {} -ParameterFilter {$Directory}
        $Warnings = (Get-TaskWinPEExtraFilesPE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinPEExtraFilesPE: To select WinPE Extra Files, add Content to $ContentRoot\ExtraFiles*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEExtraFilesRE' {
    BeforeEach {
        . Initialize-ExtraFilesContent
        Initialize-GridView
    }

    It 'offers the directories with files for WinRE' {
        $Result = Get-TaskWinPEExtraFilesRE 6>$null
        $script:GridView.FullName | Should -Be @('ExtraFiles\Wallpaper', 'WinPE\ExtraFiles\Tools')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'WinPEExtraFilesRE:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the directories of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEExtraFilesRE = @('ExtraFiles\Wallpaper')}
        Get-TaskWinPEExtraFilesRE 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('WinPE\ExtraFiles\Tools')
    }

    It 'warns when there are no directories with files' {
        Mock Get-ChildItem {} -ParameterFilter {$Directory}
        $Warnings = (Get-TaskWinPEExtraFilesRE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinPEExtraFilesRE: To select WinRE Extra Files, add Content to $ContentRoot\ExtraFiles*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEExtraFilesSE' {
    BeforeEach {
        . Initialize-ExtraFilesContent
        Initialize-GridView
    }

    It 'offers the directories with files for WinSE' {
        $Result = Get-TaskWinPEExtraFilesSE 6>$null
        $script:GridView.FullName | Should -Be @('ExtraFiles\Wallpaper', 'WinPE\ExtraFiles\Tools')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'WinPEExtraFilesSE:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the directories of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEExtraFilesSE = @('ExtraFiles\Wallpaper', 'WinPE\ExtraFiles\Tools')}
        Get-TaskWinPEExtraFilesSE 6>$null | Should -BeNullOrEmpty
        Should -Invoke Out-GridView -Times 0 -Exactly
    }

    It 'warns when there are no directories with files' {
        Mock Get-ChildItem {} -ParameterFilter {$Directory}
        $Warnings = (Get-TaskWinPEExtraFilesSE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinPEExtraFilesSE: To select WinSE Extra Files, add Content to $ContentRoot\ExtraFiles*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEScripts' {
    BeforeEach {
        . Initialize-ScriptsContent
        Initialize-GridView
    }

    It 'offers the scripts of Content\Scripts and Content\WinPE\Scripts sorted by path' {
        $Result = Get-TaskWinPEScripts 6>$null
        Should -Invoke Get-ChildItem -Times 1 -Exactly -ParameterFilter {($Path -contains "$ContentRoot\Scripts") -and ($Path -contains "$ContentRoot\WinPE\Scripts")}
        $script:GridView.FullName | Should -Be @('Scripts\Set-Wallpaper.ps1', 'WinPE\Scripts\Set-WinPE.ps1')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'WinPE PowerShell Scripts:*')}
        $Result[0].Length | Should -Be 1024
    }

    It 'does not offer the scripts of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEScripts = @('Scripts\Set-Wallpaper.ps1')}
        Get-TaskWinPEScripts 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('WinPE\Scripts\Set-WinPE.ps1')
    }

    It 'warns when there are no scripts' {
        Mock Get-ChildItem {} -ParameterFilter {$Filter -eq '*.ps1'}
        $Warnings = (Get-TaskWinPEScripts 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinPE PowerShell Scripts: To select PowerShell Scripts add Content to $ContentRoot\Scripts*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEScriptsPE' {
    BeforeEach {
        . Initialize-ScriptsContent
        Initialize-GridView
    }

    It 'offers the scripts for WinPE sorted by path' {
        $Result = Get-TaskWinPEScriptsPE 6>$null
        $script:GridView.FullName | Should -Be @('Scripts\Set-Wallpaper.ps1', 'WinPE\Scripts\Set-WinPE.ps1')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'WinPE PowerShell Scripts:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the scripts of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEScriptsPE = @('WinPE\Scripts\Set-WinPE.ps1')}
        Get-TaskWinPEScriptsPE 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('Scripts\Set-Wallpaper.ps1')
    }

    It 'warns when there are no scripts' {
        Mock Get-ChildItem {} -ParameterFilter {$Filter -eq '*.ps1'}
        $Warnings = (Get-TaskWinPEScriptsPE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinPE PowerShell Scripts: To select PowerShell Scripts add Content to $ContentRoot\Scripts*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEScriptsRE' {
    BeforeEach {
        . Initialize-ScriptsContent
        Initialize-GridView
    }

    It 'offers the scripts for WinRE sorted by path' {
        $Result = Get-TaskWinPEScriptsRE 6>$null
        $script:GridView.FullName | Should -Be @('Scripts\Set-Wallpaper.ps1', 'WinPE\Scripts\Set-WinPE.ps1')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'WinRE PowerShell Scripts:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the scripts of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEScriptsRE = @('Scripts\Set-Wallpaper.ps1')}
        Get-TaskWinPEScriptsRE 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('WinPE\Scripts\Set-WinPE.ps1')
    }

    It 'warns when there are no scripts' {
        Mock Get-ChildItem {} -ParameterFilter {$Filter -eq '*.ps1'}
        $Warnings = (Get-TaskWinPEScriptsRE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinRE PowerShell Scripts: To select PowerShell Scripts add Content to $ContentRoot\Scripts*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskWinPEScriptsSE' {
    BeforeEach {
        . Initialize-ScriptsContent
        Initialize-GridView
    }

    It 'offers the scripts for WinSE sorted by path' {
        $Result = Get-TaskWinPEScriptsSE 6>$null
        $script:GridView.FullName | Should -Be @('Scripts\Set-Wallpaper.ps1', 'WinPE\Scripts\Set-WinPE.ps1')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'WinSE PowerShell Scripts:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the scripts of the existing Task' {
        $ExistingTask = [PSCustomObject]@{WinPEScriptsSE = @('WinPE\Scripts\Set-WinPE.ps1')}
        Get-TaskWinPEScriptsSE 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('Scripts\Set-Wallpaper.ps1')
    }

    It 'warns when there are no scripts' {
        Mock Get-ChildItem {} -ParameterFilter {$Filter -eq '*.ps1'}
        $Warnings = (Get-TaskWinPEScriptsSE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*WinSE PowerShell Scripts: To select PowerShell Scripts add Content to $ContentRoot\Scripts*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}
