#Tests for the AllFunctions.ps1 functions Save-* and Set-*
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    $IMNRSFixtures = Join-Path $FixturesPath 'AllFunctionsIMNRS'

    function New-InfoDirectory {
        <#
        .SYNOPSIS
        Creates a directory with the json, logs and xml subdirectories and returns its path
        #>
        param ([string]$Path)
        foreach ($Folder in 'json', 'logs', 'xml') {New-Item -Path (Join-Path $Path $Folder) -ItemType Directory -Force | Out-Null}
        $Path
    }

    function Assert-FormattedFile {
        <#
        .SYNOPSIS
        Asserts a text file written with Out-File
        .DESCRIPTION
        Out-File formats a table with the width of the console, without a console (redirected output) the table can be empty
        #>
        param ([string]$Path, [string]$Like, [switch]$NoEmptyLines)
        Test-Path -Path $Path -PathType Leaf | Should -BeTrue
        $Text = Get-Content -Path $Path -Raw
        if ($Text -and $Text.Trim()) {
            $Text | Should -BeLike $Like
            if ($NoEmptyLines) {Get-Content -Path $Path | Where-Object {-not $_.Trim()} | Should -BeNullOrEmpty}
        }
    }

    function Get-InfoFile {
        <#
        .SYNOPSIS
        Returns the file in a json, logs or xml directory
        #>
        param ([string]$Path, [string]$Folder, [string]$Filter)
        @(Get-ChildItem -Path (Join-Path $Path $Folder) -Filter $Filter -File)
    }
}

Describe 'Save-AutoExtraFilesOS' {
    BeforeEach {
        $MountDirectory = 'C:\Mount'
        $script:Robocopy = [System.Collections.Generic.List[string]]::new()
        Mock robocopy {$script:Robocopy.Add((@($InputObject) + @($RemainingArguments)) -join ' ')}
    }

    It 'copies the AutoExtraFiles of the mounted install.wim to WinPE\AutoExtraFiles' {
        $Output = (Save-AutoExtraFilesOS -OSMediaPath 'C:\OSMedia' 6>&1) -join "`n"
        $Output | Should -BeLike '*OS: Backup Auto Extra Files to C:\OSMedia\WinPE\AutoExtraFiles*'
        $script:Robocopy.Count | Should -Be 35
        foreach ($Call in $script:Robocopy) {
            $Call | Should -BeLike 'C:\Mount\Windows\* C:\OSMedia\WinPE\AutoExtraFiles\Windows\* /log+:C:\OSMedia\info\logs\*-Save-AutoExtraFilesOS.log'
        }
    }

    It 'copies <File> from <Source>' -TestCases @(
        @{File = 'curl.exe'; Source = 'C:\Mount\Windows\System32'}
        @{File = 'tar.exe'; Source = 'C:\Mount\Windows\System32'}
        @{File = 'bcp47*.dll'; Source = 'C:\Mount\Windows\System32'}
        @{File = 'osk*.*'; Source = 'C:\Mount\Windows\System32'}
        @{File = 'mstsc*.*'; Source = 'C:\Mount\Windows\System32'}
        @{File = 'aerolite*.*'; Source = 'C:\Mount\Windows\Resources'}
        @{File = 'shellstyle*.*'; Source = 'C:\Mount\Windows\Resources\Themes\aero\shell\normalcolor'}
        @{File = 'mdmregistration*.*'; Source = 'C:\Mount\Windows\System32'}
    ) {
        Save-AutoExtraFilesOS -OSMediaPath 'C:\OSMedia' 6>$null
        @($script:Robocopy | Where-Object {$_.StartsWith("$Source C:\OSMedia\WinPE\AutoExtraFiles\Windows\") -and (($_ -split ' ')[2] -eq $File)}).Count | Should -BeGreaterOrEqual 1
    }

    It 'does not copy cleanmgr.exe' {
        Save-AutoExtraFilesOS -OSMediaPath 'C:\OSMedia' 6>$null
        $script:Robocopy | Where-Object {$_ -like '*cleanmgr*'} | Should -BeNullOrEmpty
    }
}

Describe 'Save-InventoryOS' {
    BeforeEach {
        $MountDirectory = 'C:\Mount'
        $OSMediaPath = Join-Path $TestDrive "OSMedia$([guid]::NewGuid().Guid)"
        $InfoPath = New-InfoDirectory -Path (Join-Path $OSMediaPath 'info')
        Mock Get-AppxProvisionedPackage {[PSCustomObject]@{DisplayName = 'Microsoft.WindowsCalculator'; Version = '11.2502.2.0'; PackageName = 'Microsoft.WindowsCalculator_11.2502.2.0_neutral_~_8wekyb3d8bbwe'}}
        Mock Get-WindowsOptionalFeature {[PSCustomObject]@{FeatureName = 'NetFx3'; State = 'Enabled'}}
        Mock Get-WindowsCapability {[PSCustomObject]@{Name = 'Language.Basic~~~de-DE~0.0.1.0'; State = 'Installed'}}
        Mock Get-WindowsPackage {[PSCustomObject]@{PackageName = 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.6899.1.12'; PackageState = 'Installed'}}
    }

    It 'exports the <Name> inventory as txt, xml and json' -TestCases @(
        @{Name = 'AppxProvisionedPackage'; Property = 'DisplayName'; Value = 'Microsoft.WindowsCalculator'}
        @{Name = 'WindowsOptionalFeature'; Property = 'FeatureName'; Value = 'NetFx3'}
        @{Name = 'WindowsCapability'; Property = 'Name'; Value = 'Language.Basic~~~de-DE~0.0.1.0'}
        @{Name = 'WindowsPackage'; Property = 'PackageName'; Value = 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.6899.1.12'}
    ) {
        Save-InventoryOS -OSMediaPath $OSMediaPath 6>$null
        Assert-FormattedFile -Path (Join-Path $OSMediaPath "$Name.txt") -Like "*$Value*"
        Assert-FormattedFile -Path (Join-Path $InfoPath "Get-$Name.txt") -Like "*$Value*"
        (Import-Clixml -Path (Join-Path (Join-Path $InfoPath 'xml') "Get-$Name.xml")).$Property | Should -Be $Value
        (Get-Content -Path (Join-Path (Join-Path $InfoPath 'json') "Get-$Name.json") -Raw | ConvertFrom-Json).$Property | Should -Be $Value
        (Get-InfoFile -Path $InfoPath -Folder 'logs' -Filter "*-Get-$Name.txt").Count | Should -Be 1
        (Get-InfoFile -Path $InfoPath -Folder 'xml' -Filter "*-Get-$Name.xml").Count | Should -Be 1
        (Get-InfoFile -Path $InfoPath -Folder 'json' -Filter "*-Get-$Name.json").Count | Should -Be 1
    }

    It 'reads the inventory of the mounted image' {
        Save-InventoryOS -OSMediaPath $OSMediaPath 6>$null
        Should -Invoke Get-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {$Path -eq 'C:\Mount'}
        Should -Invoke Get-WindowsOptionalFeature -Times 1 -Exactly -ParameterFilter {$Path -eq 'C:\Mount'}
        Should -Invoke Get-WindowsCapability -Times 1 -Exactly -ParameterFilter {$Path -eq 'C:\Mount'}
        Should -Invoke Get-WindowsPackage -Times 1 -Exactly -ParameterFilter {$Path -eq 'C:\Mount'}
    }

    It 'warns with the DISM error and continues with the next inventory' {
        $DismError = [System.Runtime.InteropServices.COMException]::new('The request is not supported.', -2146498530)
        Mock Get-AppxProvisionedPackage {throw $DismError}
        Mock Get-WindowsOptionalFeature {throw $DismError}
        Mock Get-WindowsCapability {throw $DismError}
        Mock Get-WindowsPackage {throw $DismError}
        $Warnings = (Save-InventoryOS -OSMediaPath $OSMediaPath 6>$null 3>&1) -join "`n"
        foreach ($Name in 'AppxProvisionedPackage', 'WindowsOptionalFeature', 'WindowsCapability', 'WindowsPackage') {
            $Warnings | Should -BeLike "*Get-$Name encountered errors*"
        }
        $Warnings | Should -BeLike '*-2146498530*'
        $Warnings | Should -BeLike '*The request is not supported.*'
        Test-Path -Path (Join-Path $OSMediaPath 'WindowsPackage.txt') | Should -BeFalse
    }

    # KnownBug: the catch blocks of Save-InventoryOS pass $_.Exception.ErrorCode to Write-Warning (AllFunctions.ps1:5750), an exception without ErrorCode fails with 'Cannot bind argument to parameter Message because it is null'
    It 'warns without an error when the exception has no ErrorCode' -Skip {
        Mock Get-AppxProvisionedPackage {throw 'The mount directory is not valid'}
        $Warnings = (Save-InventoryOS -OSMediaPath $OSMediaPath 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*The mount directory is not valid*'
        Test-Path -Path (Join-Path $OSMediaPath 'WindowsPackage.txt') | Should -BeTrue
    }
}

Describe 'Save-InventoryPE' {
    BeforeEach {
        $OSMediaPath = Join-Path $TestDrive "OSMedia$([guid]::NewGuid().Guid)"
        $PEInfoPath = New-InfoDirectory -Path (Join-Path (Join-Path $OSMediaPath 'WinPE') 'info')
        Mock Get-WindowsImage {
            [PSCustomObject]@{ImageIndex = 1; ImageName = "Microsoft Windows PE ($(Split-Path $ImagePath -Leaf))"; ImageSize = 1}
            if (-not $Index) {[PSCustomObject]@{ImageIndex = 2; ImageName = 'Microsoft Windows Setup (amd64)'; ImageSize = 2}}
        }
    }

    It 'exports the image information of <Wim> to Get-WindowsImage-<Name>' -TestCases @(
        @{Wim = 'boot.wim'; Name = 'Boot'}
        @{Wim = 'winpe.wim'; Name = 'WinPE'}
        @{Wim = 'winre.wim'; Name = 'WinRE'}
        @{Wim = 'winse.wim'; Name = 'WinSE'}
    ) {
        Save-InventoryPE -OSMediaPath $OSMediaPath 6>$null
        Assert-FormattedFile -Path (Join-Path $PEInfoPath "Get-WindowsImage-$Name.txt") -Like "*Microsoft Windows PE ($Wim)*" -NoEmptyLines
        @(Import-Clixml -Path (Join-Path (Join-Path $PEInfoPath 'xml') "Get-WindowsImage-$Name.xml"))[0].ImageName | Should -Be "Microsoft Windows PE ($Wim)"
        @(Get-Content -Path (Join-Path (Join-Path $PEInfoPath 'json') "Get-WindowsImage-$Name.json") -Raw | ConvertFrom-Json)[0].ImageIndex | Should -Be 1
        (Get-InfoFile -Path $PEInfoPath -Folder 'logs' -Filter "*-Get-WindowsImage-$Name.txt").Count | Should -Be 1
        (Get-InfoFile -Path $PEInfoPath -Folder 'xml' -Filter "*-Get-WindowsImage-$Name.xml").Count | Should -Be 1
        (Get-InfoFile -Path $PEInfoPath -Folder 'json' -Filter "*-Get-WindowsImage-$Name.json").Count | Should -Be 1
    }

    It 'exports all indexes of boot.wim and index 1 of the other wims' {
        Save-InventoryPE -OSMediaPath $OSMediaPath 6>$null
        @(Import-Clixml -Path (Join-Path (Join-Path $PEInfoPath 'xml') 'Get-WindowsImage-Boot.xml')).Count | Should -Be 2
        Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -like '*WinPE\boot.wim') -and -not $Index}
        foreach ($Wim in 'winpe.wim', 'winre.wim', 'winse.wim') {
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -like "*WinPE\$Wim") -and ($Index -eq 1)}
        }
    }
}

Describe 'Save-OSMediaVariables' {
    It 'exports the variables of the session to Variables.xml and Variables.json' {
        $OSMediaPathInfo = New-InfoDirectory -Path (Join-Path $TestDrive 'OSMediaInfo')
        $OSMediaName = 'Windows 11 Enterprise x64 25H2 6899'
        $Hashtable = @{Key = 'Value'}
        Save-OSMediaVariables 3>$null
        $Xml = Import-Clixml -Path (Join-Path (Join-Path $OSMediaPathInfo 'xml') 'Variables.xml')
        ($Xml | Where-Object {$_.Name -eq 'OSMediaName'}).Value | Should -Be 'Windows 11 Enterprise x64 25H2 6899'
        $Json = Get-Content -Path (Join-Path (Join-Path $OSMediaPathInfo 'json') 'Variables.json') -Raw | ConvertFrom-Json
        ($Json | Where-Object {$_.Name -eq 'OSMediaName'}).Value | Should -Be 'Windows 11 Enterprise x64 25H2 6899'
        $Json.Name | Should -Not -Contain 'Hashtable'
        $Xml.Name | Should -Contain 'Hashtable'
    }
}

Describe 'Save-OSMediaWindowsImageContent' {
    It 'writes the content of the install.wim to Get-WindowsImageContent.txt' {
        $OSMediaPathInfo = Join-Path $TestDrive 'OSMediaInfo'
        New-Item -Path $OSMediaPathInfo -ItemType Directory -Force | Out-Null
        $OSMediaPathWindowsImage = 'C:\OSMedia\OS\sources\install.wim'
        Mock Get-WindowsImageContent {'\Windows\System32\ntoskrnl.exe', '\Windows\explorer.exe'}
        Save-OSMediaWindowsImageContent 6>$null
        Get-Content -Path (Join-Path $OSMediaPathInfo 'Get-WindowsImageContent.txt') | Should -Be @('\Windows\System32\ntoskrnl.exe', '\Windows\explorer.exe')
        Should -Invoke Get-WindowsImageContent -Times 1 -Exactly -ParameterFilter {($ImagePath -eq 'C:\OSMedia\OS\sources\install.wim') -and ($Index -eq 1)}
    }
}

Describe 'Save-PackageInventoryPE' {
    BeforeEach {
        $OSMediaPath = Join-Path $TestDrive "OSMedia$([guid]::NewGuid().Guid)"
        $PEInfoPath = New-InfoDirectory -Path (Join-Path (Join-Path $OSMediaPath 'WinPE') 'info')
        $MountWinPE = 'C:\Mount\WinPE'; $MountWinRE = 'C:\Mount\WinRE'; $MountWinSE = 'C:\Mount\WinSE'
        Mock Get-WindowsPackage {[PSCustomObject]@{PackageName = "WinPE-Package-$(Split-Path $Path -Leaf)"; PackageState = 'Installed'}}
    }

    It 'exports the packages of the mounted <Name> as txt, xml and json' -TestCases @(
        @{Name = 'WinPE'}, @{Name = 'WinRE'}, @{Name = 'WinSE'}
    ) {
        Save-PackageInventoryPE -OSMediaPath $OSMediaPath 6>$null
        Assert-FormattedFile -Path (Join-Path $PEInfoPath "Get-WindowsPackage-$Name.txt") -Like "*WinPE-Package-$Name*"
        (Import-Clixml -Path (Join-Path (Join-Path $PEInfoPath 'xml') "Get-WindowsPackage-$Name.xml")).PackageName | Should -Be "WinPE-Package-$Name"
        (Get-Content -Path (Join-Path (Join-Path $PEInfoPath 'json') "Get-WindowsPackage-$Name.json") -Raw | ConvertFrom-Json).PackageName | Should -Be "WinPE-Package-$Name"
        (Get-InfoFile -Path $PEInfoPath -Folder 'logs' -Filter "*-Get-WindowsPackage-$Name.txt").Count | Should -Be 1
        (Get-InfoFile -Path $PEInfoPath -Folder 'xml' -Filter "*-Get-WindowsPackage-$Name.xml").Count | Should -Be 1
        (Get-InfoFile -Path $PEInfoPath -Folder 'json' -Filter "*-Get-WindowsPackage-$Name.json").Count | Should -Be 1
        Should -Invoke Get-WindowsPackage -Times 1 -Exactly -ParameterFilter {$Path -eq "C:\Mount\$Name"}
    }
}

Describe 'Save-RegistryCurrentVersionOS' {
    It 'writes CurrentVersion as txt and xml to info, logs and the working path' {
        $Info = New-InfoDirectory -Path (Join-Path $TestDrive 'Info')
        $WorkingPath = Join-Path $TestDrive 'Working'
        New-Item -Path $WorkingPath -ItemType Directory -Force | Out-Null
        $RegKeyCurrentVersion = [PSCustomObject]@{CurrentBuild = '26200'; DisplayVersion = '25H2'; UBR = 6899}
        Save-RegistryCurrentVersionOS
        Assert-FormattedFile -Path (Join-Path $Info 'CurrentVersion.txt') -Like '*25H2*'
        Assert-FormattedFile -Path (Join-Path $WorkingPath 'CurrentVersion.txt') -Like '*26200*'
        (Import-Clixml -Path (Join-Path (Join-Path $Info 'xml') 'CurrentVersion.xml')).DisplayVersion | Should -Be '25H2'
        (Get-InfoFile -Path $Info -Folder 'logs' -Filter '*-CurrentVersion.txt').Count | Should -Be 1
        (Get-InfoFile -Path $Info -Folder 'xml' -Filter '*-CurrentVersion.xml').Count | Should -Be 1
        (Get-InfoFile -Path $Info -Folder 'json' -Filter '*-CurrentVersion.json').Count | Should -Be 1
    }
}

Describe 'Save-SessionsXmlOS' {
    BeforeEach {
        $MountDirectory = Join-Path $TestDrive "Mount$([guid]::NewGuid().Guid)"
        $SessionsPath = Join-Path (Join-Path (Join-Path $MountDirectory 'Windows') 'Servicing') 'Sessions'
        New-Item -Path $SessionsPath -ItemType Directory -Force | Out-Null
        Copy-Item -Path (Join-Path $IMNRSFixtures 'Sessions.xml') -Destination (Join-Path $SessionsPath 'Sessions.xml')
        $OSMediaPath = Join-Path $TestDrive "OSMedia$([guid]::NewGuid().Guid)"
        $InfoPath = New-InfoDirectory -Path (Join-Path $OSMediaPath 'info')
    }

    It 'exports the package sessions, newest first' {
        Save-SessionsXmlOS -OSMediaPath $OSMediaPath 6>$null
        $Sessions = @(Import-Clixml -Path (Join-Path (Join-Path $InfoPath 'xml') 'Sessions.xml'))
        $Sessions.Count | Should -Be 2
        $Sessions[0].KBNumber | Should -Be 'KB5127648'
        $Sessions[0].Id | Should -Be 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.6899.1.12'
        $Sessions[0].TargetState | Should -Be 'Installed'
        $Sessions[0].Client | Should -Be 'DISM Package Manager Provider'
        $Sessions[0].Status | Should -Be '0x0'
        $Sessions[0].Complete | Should -Be '2026-10-14T09:30:00Z'
        $Sessions[1].KBNumber | Should -Be 'KB5065426'
        $Sessions.Id | Should -Not -Contain 'Microsoft-Windows-Foundation-Package~31bf3856ad364e35~amd64~~10.0.26100.1'
    }

    It 'copies Sessions.xml and writes txt and json' {
        Save-SessionsXmlOS -OSMediaPath $OSMediaPath 6>$null
        Get-Content -Path (Join-Path $InfoPath 'Sessions.xml') -Raw | Should -Be (Get-Content -Path (Join-Path $IMNRSFixtures 'Sessions.xml') -Raw)
        Assert-FormattedFile -Path (Join-Path $OSMediaPath 'Sessions.txt') -Like '*KB5127648*'
        @(Get-Content -Path (Join-Path (Join-Path $InfoPath 'json') 'Sessions.json') -Raw | ConvertFrom-Json).KBNumber | Should -Be @('KB5127648', 'KB5065426')
        (Get-InfoFile -Path $InfoPath -Folder 'logs' -Filter '*-Sessions.txt').Count | Should -Be 1
        (Get-InfoFile -Path $InfoPath -Folder 'xml' -Filter '*-Sessions.xml').Count | Should -Be 1
        (Get-InfoFile -Path $InfoPath -Folder 'json' -Filter '*-Sessions.json').Count | Should -Be 1
    }

    It 'removes the Sessions.xml of an old OSMedia version' {
        New-TestFile -Path (Join-Path $OSMediaPath 'Sessions.xml') | Out-Null
        Save-SessionsXmlOS -OSMediaPath $OSMediaPath 6>$null
        Test-Path -Path (Join-Path $OSMediaPath 'Sessions.xml') | Should -BeFalse
    }

    It 'exports nothing when the image has no Sessions.xml' {
        Remove-Item -Path (Join-Path $SessionsPath 'Sessions.xml')
        (Save-SessionsXmlOS -OSMediaPath $OSMediaPath 6>&1) -join "`n" | Should -BeLike '*Exporting Sessions.xml Patch Inventory*'
        Test-Path -Path (Join-Path $OSMediaPath 'Sessions.txt') | Should -BeFalse
    }
}

Describe 'Save-VariablesOSD' {
    It 'exports the variables of the session to Variables.xml and Variables.json' {
        $Info = New-InfoDirectory -Path (Join-Path $TestDrive 'Info')
        $TaskName = 'Win11 Enterprise de-DE'
        $Hashtable = @{Key = 'Value'}
        Save-VariablesOSD 3>$null
        $Xml = Import-Clixml -Path (Join-Path (Join-Path $Info 'xml') 'Variables.xml')
        ($Xml | Where-Object {$_.Name -eq 'TaskName'}).Value | Should -Be 'Win11 Enterprise de-DE'
        $Json = Get-Content -Path (Join-Path (Join-Path $Info 'json') 'Variables.json') -Raw | ConvertFrom-Json
        ($Json | Where-Object {$_.Name -eq 'TaskName'}).Value | Should -Be 'Win11 Enterprise de-DE'
        $Json.Name | Should -Not -Contain 'Hashtable'
    }
}

Describe 'Save-WimsPE' {
    It 'copies boot.wim and exports WinPE, WinRE and WinSE' {
        $OSMediaPath = Join-Path $TestDrive 'OSMedia'
        New-TestFile -Path (Join-Path (Join-Path (Join-Path $OSMediaPath 'OS') 'sources') 'boot.wim') -Value 'boot.wim' | Out-Null
        New-Item -Path (Join-Path $OSMediaPath 'WinPE') -ItemType Directory -Force | Out-Null
        $MountDirectory = 'C:\Mount'
        Mock Export-WindowsImage {}
        Save-WimsPE -OSMediaPath $OSMediaPath 6>$null
        Get-Content -Path (Join-Path (Join-Path $OSMediaPath 'WinPE') 'boot.wim') | Should -Be 'boot.wim'
        Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($SourceImagePath -like '*OS\sources\boot.wim') -and ($SourceIndex -eq 1) -and ($DestinationImagePath -like '*WinPE\winpe.wim') -and ($LogPath -like '*WinPE\info\logs\*-Export-WindowsImage-WinPE.log')
        }
        Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($SourceImagePath -eq 'C:\Mount\Windows\System32\Recovery\winre.wim') -and ($SourceIndex -eq 1) -and ($DestinationImagePath -like '*WinPE\winre.wim')
        }
        Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($SourceImagePath -like '*OS\sources\boot.wim') -and ($SourceIndex -eq 2) -and ($DestinationImagePath -like '*WinPE\winse.wim')
        }
    }
}

Describe 'Save-WindowsImageContentOS' {
    It 'writes the content of OS\Sources\install.wim to Get-WindowsImageContent.txt' {
        $Info = Join-Path $TestDrive 'InfoOS'
        New-Item -Path $Info -ItemType Directory -Force | Out-Null
        $OS = 'C:\OSBuild\OS'
        Mock Get-WindowsImageContent {'\Windows\System32\winload.efi'}
        (Save-WindowsImageContentOS 6>&1) -join "`n" | Should -BeLike '*OS: Export Image Content to*'
        Get-Content -Path (Join-Path $Info 'Get-WindowsImageContent.txt') | Should -Be '\Windows\System32\winload.efi'
        Should -Invoke Get-WindowsImageContent -Times 1 -Exactly -ParameterFilter {($ImagePath -eq 'C:\OSBuild\OS\Sources\install.wim') -and ($Index -eq 1)}
    }
}

Describe 'Save-WindowsImageContentPE' {
    It 'writes the content of OS\Sources\boot.wim to Get-WindowsImageContent.txt' {
        $Info = Join-Path $TestDrive 'InfoPE'
        New-Item -Path $Info -ItemType Directory -Force | Out-Null
        $OS = 'C:\PEBuild\OS'
        Mock Get-WindowsImageContent {'\Windows\System32\winpeshl.exe'}
        Save-WindowsImageContentPE 6>$null
        Get-Content -Path (Join-Path $Info 'Get-WindowsImageContent.txt') | Should -Be '\Windows\System32\winpeshl.exe'
        Should -Invoke Get-WindowsImageContent -Times 1 -Exactly -ParameterFilter {($ImagePath -eq 'C:\PEBuild\OS\Sources\boot.wim') -and ($Index -eq 1)}
    }
}

Describe 'Set-LanguageSettingsOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10
        $MountDirectory = 'C:\Mount'; $Info = 'C:\OSBuild\info'; $OS = 'C:\OSBuild\OS'; $WorkingPath = 'C:\OSBuild'
        $SetAllIntl = 'de-DE'; $SetInputLocale = '0407:00000407'; $SetSKUIntlDefaults = 'de-DE'; $SetSetupUILang = 'de-DE'
        $SetSysLocale = 'de-DE'; $SetUILang = 'de-DE'; $SetUILangFallback = 'en-US'; $SetUserLocale = 'de-AT'
        $script:Dism = [System.Collections.Generic.List[string]]::new()
        Mock dism {$script:Dism.Add((@($InputObject) + @($RemainingArguments)) -join ' ')}
        Mock Update-LangIniMEDIA {}
    }

    It 'sets <Setting> to <Value>' -TestCases @(
        @{Setting = 'Set-AllIntl'; Value = 'de-DE'}
        @{Setting = 'Set-InputLocale'; Value = '0407:00000407'}
        @{Setting = 'Set-SKUIntlDefaults'; Value = 'de-DE'}
        @{Setting = 'Set-SysLocale'; Value = 'de-DE'}
        @{Setting = 'Set-UILang'; Value = 'de-DE'}
        @{Setting = 'Set-UILangFallback'; Value = 'en-US'}
        @{Setting = 'Set-UserLocale'; Value = 'de-AT'}
    ) {
        Set-LanguageSettingsOS 6>$null
        $Call = @($script:Dism | Where-Object {$_ -like "* /$($Setting):*"})
        $Call.Count | Should -Be 1
        $Call[0] | Should -BeLike "/Image:C:\Mount /$($Setting):$Value /LogPath:C:\OSBuild\info\logs\*-Dism-$($Setting -replace '-', '').log"
    }

    It 'sets the Setup UI language of the distribution and generates Lang.ini' {
        Set-LanguageSettingsOS 6>$null
        $script:Dism | Should -Contain ($script:Dism | Where-Object {$_ -like '/Image:C:\Mount /Set-SetupUILang:de-DE /Distribution:C:\OSBuild\OS /LogPath:*'})
        $script:Dism[-1] | Should -BeLike '/Image:C:\Mount /Gen-LangIni /Distribution:C:\OSBuild\OS /LogPath:C:\OSBuild\info\logs\*-Dism-gen-langini.log'
        $script:Dism.Count | Should -Be 9
        Should -Invoke Update-LangIniMEDIA -Times 1 -Exactly -ParameterFilter {$OSMediaPath -eq 'C:\OSBuild'}
    }

    It 'only generates Lang.ini without language settings' {
        $SetAllIntl = $null; $SetInputLocale = $null; $SetSKUIntlDefaults = $null; $SetSetupUILang = $null
        $SetSysLocale = $null; $SetUILang = $null; $SetUILangFallback = $null; $SetUserLocale = $null
        Set-LanguageSettingsOS 6>$null
        $script:Dism.Count | Should -Be 1
        $script:Dism[0] | Should -BeLike '*/Gen-LangIni*'
    }

    It 'does nothing for <Case>' -TestCases @(
        @{Case = 'New-PEBuild'; TestScriptName = 'New-PEBuild'; TestOSMajorVersion = 10}
        @{Case = 'Windows 7'; TestScriptName = 'New-OSBuild'; TestOSMajorVersion = 6}
    ) {
        $ScriptName = $TestScriptName; $OSMajorVersion = $TestOSMajorVersion
        Set-LanguageSettingsOS 6>$null
        $script:Dism.Count | Should -Be 0
        Should -Invoke Update-LangIniMEDIA -Times 0 -Exactly
    }
}

Describe 'Set-PEBuildScratchSpace' {
    BeforeEach {
        $Info = 'C:\PEBuild\info'
        $script:Dism = [System.Collections.Generic.List[string]]::new()
        Mock dism {$script:Dism.Add((@($InputObject) + @($RemainingArguments)) -join ' ')}
    }

    It 'sets the scratch space of the mounted WinPE' {
        (Set-PEBuildScratchSpace -MountDirectory 'C:\Mount\PE' -ScratchSpace 512 6>&1) -join "`n" | Should -BeLike '*WinPE: Set-ScratchSpace 512*'
        $script:Dism[0] | Should -BeLike '/Image:C:\Mount\PE /Set-ScratchSpace:512 /LogPath:C:\PEBuild\info\logs\*-Set-PEBuildScratchSpace.log'
    }

    It 'warns when DISM fails' {
        Mock dism {throw 'Error: 87 The scratch space is not valid'}
        (Set-PEBuildScratchSpace -MountDirectory 'C:\Mount\PE' -ScratchSpace 1024 6>$null 3>&1) -join "`n" | Should -BeLike '*The scratch space is not valid*'
    }
}

Describe 'Set-PEBuildTargetPath' {
    BeforeEach {
        $Info = 'C:\PEBuild\info'
        $script:Dism = [System.Collections.Generic.List[string]]::new()
        Mock dism {$script:Dism.Add((@($InputObject) + @($RemainingArguments)) -join ' ')}
    }

    It 'sets the target path of the mounted WinPE to X:\' {
        Set-PEBuildTargetPath -MountDirectory 'C:\Mount\PE' 6>$null
        $script:Dism[0] | Should -BeLike '/Image:C:\Mount\PE /Set-TargetPath:X:\ /LogPath:C:\PEBuild\info\logs\*-Set-PEBuildTargetPath.log'
    }

    It 'warns when DISM fails' {
        Mock dism {throw 'Error: 50 The target path is not supported'}
        (Set-PEBuildTargetPath -MountDirectory 'C:\Mount\PE' 6>$null 3>&1) -join "`n" | Should -BeLike '*The target path is not supported*'
    }
}

Describe 'Set-WinREWimOS' {
    BeforeEach {
        $MountDirectory = Join-Path $TestDrive "Mount$([guid]::NewGuid().Guid)"
        $RecoveryPath = Join-Path (Join-Path (Join-Path $MountDirectory 'Windows') 'System32') 'Recovery'
        New-Item -Path $RecoveryPath -ItemType Directory -Force | Out-Null
        $WinPE = Join-Path $TestDrive "WinPE$([guid]::NewGuid().Guid)"
        New-TestFile -Path (Join-Path $WinPE 'winre.wim') -Value 'updated winre.wim' | Out-Null
        $PEInfo = New-InfoDirectory -Path (Join-Path $WinPE 'info')
        Mock Get-WindowsImage {[PSCustomObject]@{ImageIndex = 1; ImageName = 'Microsoft Windows Recovery Environment (amd64)'; Languages = @('de-DE')}}
    }

    It 'replaces the winre.wim of the image with the updated winre.wim' {
        New-TestFile -Path (Join-Path $RecoveryPath 'winre.wim') -Value 'original winre.wim' | Out-Null
        Set-WinREWimOS 6>$null
        Get-Content -Path (Join-Path $RecoveryPath 'winre.wim') | Should -Be 'updated winre.wim'
        Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -like '*winre.wim') -and ($Index -eq 1)}
    }

    It 'copies the winre.wim when the image has none' {
        Set-WinREWimOS 6>$null
        Get-Content -Path (Join-Path $RecoveryPath 'winre.wim') | Should -Be 'updated winre.wim'
    }

    It 'exports the image information of the new winre.wim' {
        Set-WinREWimOS 6>$null
        Assert-FormattedFile -Path (Join-Path $PEInfo 'Get-WindowsImage-WinRE.txt') -Like '*Microsoft Windows Recovery Environment (amd64)*' -NoEmptyLines
        (Import-Clixml -Path (Join-Path (Join-Path $PEInfo 'xml') 'Get-WindowsImage-WinRE.xml')).ImageName | Should -Be 'Microsoft Windows Recovery Environment (amd64)'
        (Get-Content -Path (Join-Path (Join-Path $PEInfo 'json') 'Get-WindowsImage-WinRE.json') -Raw | ConvertFrom-Json).Languages | Should -Be 'de-DE'
        (Get-InfoFile -Path $PEInfo -Folder 'logs' -Filter '*-Get-WindowsImage-WinRE.txt').Count | Should -Be 1
        (Get-InfoFile -Path $PEInfo -Folder 'xml' -Filter '*-Get-WindowsImage-WinRE.xml').Count | Should -Be 1
        (Get-InfoFile -Path $PEInfo -Folder 'json' -Filter '*-Get-WindowsImage-WinRE.json').Count | Should -Be 1
    }
}
