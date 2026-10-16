#Tests for the AllFunctions.ps1 functions Import-*, Invoke-*, Mount-*, New-*, Remove-*, Rename-* and Repair-*
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    $IMNRSFixtures = Join-Path $FixturesPath 'AllFunctionsIMNRS'

    #Public functions that are not dot-sourced with the Private scripts
    function Get-OSDBuilder {
        [CmdletBinding()]
        param ([switch]$CreatePaths, [switch]$HideDetails)
    }
    function Get-OSMedia {
        [CmdletBinding()]
        param ($Revision)
    }
    #Remove-ItemProperty -Name is mandatory, Import-RegistryXmlOS calls it without -Name to remove a key
    #a mock of the cmdlet would prompt for the Name, the placeholder has no mandatory parameter
    function Remove-ItemProperty {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Test placeholder without the mandatory Name')]
        [CmdletBinding()]
        param ($LiteralPath, $Name, [switch]$Force)
    }

    function New-MountedHives {
        <#
        .SYNOPSIS
        Creates the offline registry hive files of a mounted install.wim
        #>
        param ([string]$MountDirectory, [string[]]$Hive = @('NTUser.dat', 'DEFAULT', 'SOFTWARE', 'SYSTEM'))
        foreach ($Item in $Hive) {
            if ($Item -eq 'NTUser.dat') {
                New-TestFile -Path (Join-Path (Join-Path (Join-Path $MountDirectory 'Users') 'Default') 'NTUser.dat') | Out-Null
            }
            else {
                New-TestFile -Path (Join-Path (Join-Path (Join-Path (Join-Path $MountDirectory 'Windows') 'System32') 'Config') $Item) | Out-Null
            }
        }
    }

    function Register-RegMock {
        <#
        .SYNOPSIS
        Mocks reg.exe LOAD / IMPORT / UNLOAD through Start-Process and simulates the loaded hives in HKLM:
        #>
        param ([switch]$StuckHives)
        $script:RegCalls = [System.Collections.Generic.List[string]]::new()
        $script:LoadedHives = @{}
        $script:StuckHives = [bool]$StuckHives
        Mock Start-Process {
            $Arguments = @($ArgumentList) -join ' '
            $script:RegCalls.Add($Arguments)
            if ($Arguments -match '^load HKLM\\(\S+)') {$script:LoadedHives[$Matches[1]] = $true}
            if (($Arguments -match '^unload HKLM\\(\S+)') -and -not $script:StuckHives) {$script:LoadedHives.Remove($Matches[1])}
        } -ParameterFilter {$FilePath -eq 'reg'}
        Mock Test-Path {$script:LoadedHives.ContainsKey(("$Path" -replace '^HKLM:\\', ''))} -ParameterFilter {"$Path" -like 'HKLM:\*'}
        Mock Pause {}
    }

    function New-OSMediaFixture {
        <#
        .SYNOPSIS
        Creates an OSMedia directory with info\xml\Get-WindowsImage.xml and optional CurrentVersion.xml
        #>
        param (
            [string]$Root, [string]$Name, [string]$ImageName, $Architecture = 9, $Build = 26200, $UBR = 6899,
            [string[]]$Languages = @('en-US'), [string]$InstallationType = 'Client', $MajorVersion = 10,
            [string]$EditionId = 'Enterprise', [string]$ReleaseId, [string]$OSMGuid = [guid]::NewGuid().Guid
        )
        $Path = Join-Path $Root $Name
        foreach ($Folder in 'xml', 'logs', 'json') {New-Item -Path (Join-Path (Join-Path $Path 'info') $Folder) -ItemType Directory -Force | Out-Null}
        $Image = [PSCustomObject]@{
            ImageName = $ImageName; Version = "$MajorVersion.0.$Build.$UBR"; Architecture = $Architecture; EditionId = $EditionId
            InstallationType = $InstallationType; MajorVersion = $MajorVersion; MinorVersion = 0; Build = $Build; UBR = $UBR
            Languages = $Languages; CreatedTime = [datetime]'2026-10-14 10:00:00'
        }
        if ($OSMGuid) {$Image | Add-Member -NotePropertyName OSMGuid -NotePropertyValue $OSMGuid}
        $Image | Export-Clixml -Path (Join-Path (Join-Path (Join-Path $Path 'info') 'xml') 'Get-WindowsImage.xml')
        if ($ReleaseId) {
            [PSCustomObject]@{ReleaseId = $ReleaseId} | Export-Clixml -Path (Join-Path (Join-Path (Join-Path $Path 'info') 'xml') 'CurrentVersion.xml')
        }
        Get-Item -Path $Path
    }

    function New-RepairMedia ($Arch, $ReleaseId) {
        [PSCustomObject]@{
            Name = "Windows 10 Enterprise $Arch $ReleaseId"; Arch = $Arch; ReleaseId = $ReleaseId; OSMGuid = [guid]::NewGuid().Guid
            OSMFamily = "Client Enterprise $Arch 17763 en-US"; ImageName = 'Windows 10 Enterprise'; UBR = '6893'; EditionId = 'Enterprise'
            InstallationType = 'Client'; MajorVersion = '10'; Build = '17763'
            CreatedTime = [datetime]'2026-10-14 10:00:00'; ModifiedTime = [datetime]'2026-10-14 11:00:00'
        }
    }
}

Describe 'Import-AutoExtraFilesPE' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $WinPEAutoExtraFiles = $true
        $WinPE = 'C:\OSMedia\WinPE'; $PEInfo = 'C:\OSMedia\WinPE\info'
        $MountWinPE = 'C:\Mount\WinPE'; $MountWinRE = 'C:\Mount\WinRE'; $MountWinSE = 'C:\Mount\WinSE'
        $script:Robocopy = [System.Collections.Generic.List[string]]::new()
        Mock robocopy {$script:Robocopy.Add((@($InputObject) + @($RemainingArguments)) -join ' ')}
    }

    It 'copies the AutoExtraFiles into WinPE, WinRE and WinSE without the bcp47 dlls' {
        Import-AutoExtraFilesPE 6>$null
        $script:Robocopy.Count | Should -Be 3
        $script:Robocopy[0] | Should -BeLike 'C:\OSMedia\WinPE\AutoExtraFiles C:\Mount\WinPE `*.`* /s *'
        $script:Robocopy[1] | Should -BeLike 'C:\OSMedia\WinPE\AutoExtraFiles C:\Mount\WinRE *'
        $script:Robocopy[2] | Should -BeLike 'C:\OSMedia\WinPE\AutoExtraFiles C:\Mount\WinSE *'
        foreach ($Call in $script:Robocopy) {
            $Call | Should -BeLike '*/xf bcp47`*.dll*'
            $Call | Should -BeLike '*/Log+:C:\OSMedia\WinPE\info\logs\*-Import-AutoExtraFilesPE.log'
        }
    }

    It 'runs for New-OSDCloudOSMedia and writes the header' {
        $ScriptName = 'New-OSDCloudOSMedia'
        $Output = (Import-AutoExtraFilesPE 6>&1) -join "`n"
        $Output | Should -BeLike '*WinPE: Import AutoExtraFiles*'
        $Output | Should -BeLike '*C:\OSMedia\WinPE\AutoExtraFiles*'
        $script:Robocopy.Count | Should -Be 3
    }

    It 'does nothing for <TestScriptName> with WinPEAutoExtraFiles <TestAutoExtraFiles>' -TestCases @(
        @{TestScriptName = 'New-PEBuild'; TestAutoExtraFiles = $true}
        @{TestScriptName = 'New-OSBuild'; TestAutoExtraFiles = $false}
    ) {
        $ScriptName = $TestScriptName; $WinPEAutoExtraFiles = $TestAutoExtraFiles
        Import-AutoExtraFilesPE 6>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Import-RegistryRegOS' {
    BeforeEach {
        $MountDirectory = Join-Path $TestDrive "Mount$([guid]::NewGuid().Guid)"
        New-MountedHives -MountDirectory $MountDirectory
        $RegistryTemplatesReg = @(Get-Item -Path (Join-Path $IMNRSFixtures 'Template.reg'))
        Register-RegMock
    }

    It 'loads the offline hives, imports the .reg and unloads the hives' {
        Import-RegistryRegOS 6>$null
        $script:RegCalls[0] | Should -BeLike 'load HKLM\OfflineDefaultUser *Users\Default\NTUser.dat'
        $script:RegCalls[1] | Should -BeLike 'load HKLM\OfflineDefault *Windows\System32\Config\DEFAULT'
        $script:RegCalls[2] | Should -BeLike 'load HKLM\OfflineSoftware *Windows\System32\Config\SOFTWARE'
        $script:RegCalls[3] | Should -BeLike 'load HKLM\OfflineSystem *Windows\System32\Config\SYSTEM'
        $script:RegCalls[4] | Should -Be "import `"$($RegistryTemplatesReg[0].FullName)`""
        $script:RegCalls[5..8] | Should -Be @('unload HKLM\OfflineDefaultUser', 'unload HKLM\OfflineDefault', 'unload HKLM\OfflineSoftware', 'unload HKLM\OfflineSystem')
        $script:RegCalls.Count | Should -Be 9
        $script:LoadedHives.Count | Should -Be 0
        Should -Invoke Pause -Times 0 -Exactly
    }

    It 'shows the content of every .reg file' {
        $Second = New-TestFile -Path (Join-Path $TestDrive 'Second.reg') -Value "Windows Registry Editor Version 5.00`r`n[HKEY_LOCAL_MACHINE\OfflineSystem\Setup]"
        $RegistryTemplatesReg = @($RegistryTemplatesReg[0], $Second)
        $Output = (Import-RegistryRegOS 6>&1) -join "`n"
        $Output | Should -BeLike '*OS: Template Registry REG*'
        $Output | Should -BeLike "*Processing $($Second.FullName)*"
        $Output | Should -BeLike '*"DisableWindowsConsumerFeatures"=dword:00000001*'
        $Output | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineSystem\Setup`]*'
        @($script:RegCalls | Where-Object {$_ -like 'import *'}).Count | Should -Be 2
    }

    It 'loads only the hives that exist in the mounted image' {
        $MountDirectory = Join-Path $TestDrive "Mount$([guid]::NewGuid().Guid)"
        New-MountedHives -MountDirectory $MountDirectory -Hive 'SOFTWARE'
        Import-RegistryRegOS 6>$null
        @($script:RegCalls | Where-Object {$_ -like 'load *'}) | Should -BeLike 'load HKLM\OfflineSoftware *'
        @($script:RegCalls | Where-Object {$_ -like 'unload *'}) | Should -Be 'unload HKLM\OfflineSoftware'
    }

    It 'unloads twice and warns when a hive cannot be unloaded' {
        Register-RegMock -StuckHives
        $Warnings = (Import-RegistryRegOS 6>$null 3>&1) -join "`n"
        @($script:RegCalls | Where-Object {$_ -like 'unload *'}).Count | Should -Be 8
        foreach ($Hive in 'OfflineDefaultUser', 'OfflineDefault', 'OfflineSoftware', 'OfflineSystem') {
            $Warnings | Should -BeLike "*HKLM:\$Hive could not be dismounted*"
        }
        Should -Invoke Pause -Times 4 -Exactly
    }

    It 'does nothing without .reg templates' {
        $RegistryTemplatesReg = @()
        Import-RegistryRegOS 6>$null
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

Describe 'Import-RegistryXmlOS' {
    BeforeEach {
        $MountDirectory = Join-Path $TestDrive "Mount$([guid]::NewGuid().Guid)"
        New-MountedHives -MountDirectory $MountDirectory
        $RegistryTemplatesXml = @(Get-Item -Path (Join-Path $IMNRSFixtures 'Registry.xml'))
        Register-RegMock
        $script:RegistryKeys = @{}
        Mock Test-Path {$script:RegistryKeys.ContainsKey("$LiteralPath")} -ParameterFilter {"$LiteralPath" -like 'Registry::*'}
        Mock New-Item {$script:RegistryKeys["$Path"] = $true} -ParameterFilter {"$Path" -like 'Registry::*'}
        Mock New-ItemProperty {}
        Mock Remove-ItemProperty {}
        Mock Remove-Item {} -ParameterFilter {"$LiteralPath$Path" -like 'Registry::*'}
    }

    It 'maps the hives of the XML to the loaded offline hives' {
        Import-RegistryXmlOS 6>$null
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\Policies\Microsoft\Windows\CloudContent') -and ($Name -eq 'DisableWindowsConsumerFeatures') -and ($PropertyType -eq 'DWord') -and ($Value -eq '00000001') -and $Force
        }
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineDefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced') -and ($Name -eq 'TaskbarAl')
        }
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineDefault\Control Panel\Colors') -and ($Name -eq 'Background') -and ($PropertyType -eq 'String') -and ($Value -eq '0 0 0')
        }
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSystem\CurrentControlSet\Control\TimeZoneInformation') -and ($PropertyType -eq 'QWord')
        }
    }

    It 'converts the registry types and the binary value' {
        Import-RegistryXmlOS 6>$null
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($Name -eq 'Settings') -and ($PropertyType -eq 'Binary') -and ((@($Value) -join ',') -eq '0x0a,0x0b,0x0c')
        }
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {($Name -eq 'Languages') -and ($PropertyType -eq 'MultiString')}
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($Name -eq '(Default)') -and ($PropertyType -eq 'ExpandString') -and ($Value -eq '%SystemRoot%\OSDBuilder')
        }
    }

    It 'creates every missing key once and no value for an entry without a type' {
        Import-RegistryXmlOS 6>$null
        Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {"$Path" -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\OSDBuilder\Empty'}
        Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {"$Path" -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\OSDBuilder'}
        Should -Invoke New-Item -Times 6 -Exactly -ParameterFilter {"$Path" -like 'Registry::*'}
        Should -Invoke New-ItemProperty -Times 7 -Exactly
    }

    It 'loads and unloads the offline hives and shows the commands' {
        $Output = (Import-RegistryXmlOS 6>&1) -join "`n"
        @($script:RegCalls | Where-Object {$_ -like 'load *'}).Count | Should -Be 4
        @($script:RegCalls | Where-Object {$_ -like 'unload *'}).Count | Should -Be 4
        $script:LoadedHives.Count | Should -Be 0
        $Output | Should -BeLike '*OS: Template Registry XML*'
        $Output | Should -BeLike "*Processing $($RegistryTemplatesXml[0].FullName)*"
        $Output | Should -BeLike '*-Name DisableWindowsConsumerFeatures -PropertyType DWord -Value 00000001*'
    }

    It 'removes the values of entries with the action D' {
        $RegistryTemplatesXml = @(Get-Item -Path (Join-Path $IMNRSFixtures 'RegistryDelete.xml'))
        Import-RegistryXmlOS 6>$null
        Should -Invoke Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\Microsoft\Windows\CurrentVersion\Run') -and ($Name -eq 'SecurityHealth')
        }
        Should -Invoke Remove-ItemProperty -Times 1 -Exactly -ParameterFilter {
            ($LiteralPath -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\OSDBuilder') -and ($Name -eq '(Default)')
        }
        Should -Invoke New-ItemProperty -Times 0 -Exactly
    }

    It 'does not create a key that the XML removes' {
        $RegistryTemplatesXml = @(Get-Item -Path (Join-Path $IMNRSFixtures 'RegistryDeleteKey.xml'))
        Import-RegistryXmlOS 6>$null
        Should -Invoke New-Item -Times 0 -Exactly -ParameterFilter {"$Path" -like 'Registry::*'}
        Should -Invoke New-ItemProperty -Times 0 -Exactly
    }

    # KnownBug: Import-RegistryXmlOS calls Remove-ItemProperty without the mandatory -Name to remove a key (AllFunctions.ps1:4772), it prompts for a Name and does not remove the key
    It 'removes the key of an entry with the action D without a name' -Skip {
        $RegistryTemplatesXml = @(Get-Item -Path (Join-Path $IMNRSFixtures 'RegistryDeleteKey.xml'))
        Import-RegistryXmlOS 6>$null
        Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter {"$LiteralPath$Path" -eq 'Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\OSDBuilder\Obsolete'}
    }

    # KnownBug: the REG_DWORD value of a Group Policy Preferences XML is hexadecimal, Import-RegistryXmlOS passes '0000001e' unchanged to New-ItemProperty (AllFunctions.ps1:4789)
    It 'converts the hexadecimal REG_DWORD value to a number' -Skip {
        $Xml = (Get-Content -Path (Join-Path $IMNRSFixtures 'Registry.xml') -Raw) -replace 'value="00000001"', 'value="0000001e"'
        $RegistryTemplatesXml = @(New-TestFile -Path (Join-Path $TestDrive 'RegistryHex.xml') -Value $Xml)
        Import-RegistryXmlOS 6>$null
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {($Name -eq 'DisableWindowsConsumerFeatures') -and (($Value -as [long]) -eq 30)}
    }

    It 'skips an existing key' {
        $script:RegistryKeys['Registry::HKEY_LOCAL_MACHINE\OfflineSoftware\Policies\Microsoft\Windows\CloudContent'] = $true
        Import-RegistryXmlOS 6>$null
        Should -Invoke New-Item -Times 0 -Exactly -ParameterFilter {"$Path" -like '*CloudContent'}
    }

    It 'unloads twice and warns when a hive cannot be unloaded' {
        Register-RegMock -StuckHives
        $Warnings = (Import-RegistryXmlOS 6>$null 3>&1) -join "`n"
        @($script:RegCalls | Where-Object {$_ -like 'unload *'}).Count | Should -Be 8
        foreach ($Hive in 'OfflineDefaultUser', 'OfflineDefault', 'OfflineSoftware', 'OfflineSystem') {
            $Warnings | Should -BeLike "*HKLM:\$Hive could not be dismounted*"
        }
        Should -Invoke Pause -Times 4 -Exactly
    }

    It 'does nothing without XML templates' {
        $RegistryTemplatesXml = $null
        (Import-RegistryXmlOS 6>&1) | Should -BeNullOrEmpty
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

Describe 'Invoke-DismCleanupImage' {
    BeforeEach {
        $SkipUpdates = $false; $SkipComponentCleanup = $false; $OSVersion = '10.0.26100.6899'; $OSMajorVersion = 10
        $MountDirectory = 'C:\Mount'; $Info = 'C:\OSBuild\info'
        $script:Dism = [System.Collections.Generic.List[string]]::new()
        Mock dism {$script:Dism.Add((@($InputObject) + @($RemainingArguments)) -join ' '); 'Deployment Image Servicing and Management tool'}
        Mock Get-WindowsCapability {[PSCustomObject]@{Name = 'Language.Basic~~~de-DE~0.0.1.0'; State = 'Installed'}}
    }

    It 'runs StartComponentCleanup ResetBase and returns the DISM output' {
        $Output = Invoke-DismCleanupImage 6>$null
        $Output | Should -Be 'Deployment Image Servicing and Management tool'
        $script:Dism[0] | Should -BeLike '/Image:C:\Mount /Cleanup-Image /StartComponentCleanup /ResetBase /LogPath:C:\OSBuild\info\logs\*-Invoke-DismCleanupImage.log'
        Should -Invoke Get-WindowsCapability -Times 1 -Exactly -ParameterFilter {$Path -eq 'C:\Mount'}
    }

    It 'hides the DISM output and warns about the duration with -HideCleanupProgress' {
        $Result = Invoke-DismCleanupImage -HideCleanupProgress 6>$null 3>&1
        ($Result -join "`n") | Should -BeLike '*This process will take between 5 - 200 minutes*'
        $Result | Should -Not -Contain 'Deployment Image Servicing and Management tool'
        $script:Dism.Count | Should -Be 1
    }

    It 'does not check pending capabilities on Windows 8.1' {
        $OSMajorVersion = 6; $OSVersion = '6.3.9600'
        Invoke-DismCleanupImage 6>$null | Out-Null
        Should -Invoke Get-WindowsCapability -Times 0 -Exactly
        $script:Dism.Count | Should -Be 1
    }

    # KnownBug: the pending check compares the State with -eq "*pending*" instead of -like (AllFunctions.ps1:4871), it never finds a pending capability
    It 'does not clean up an image with pending capabilities' -Skip {
        Mock Get-WindowsCapability {[PSCustomObject]@{Name = 'Language.Basic~~~de-DE~0.0.1.0'; State = 'InstallPending'}}
        $Warnings = (Invoke-DismCleanupImage 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Cannot run WindowsImage Cleanup on a WIM with Pending Installations*'
        $script:Dism.Count | Should -Be 0
    }

    It 'does nothing with <Case>' -TestCases @(
        @{Case = 'SkipUpdates'; TestSkipUpdates = $true; TestSkipComponentCleanup = $false; TestOSVersion = '10.0.26100.1'}
        @{Case = 'SkipComponentCleanup'; TestSkipUpdates = $false; TestSkipComponentCleanup = $true; TestOSVersion = '10.0.26100.1'}
        @{Case = 'Windows 7'; TestSkipUpdates = $false; TestSkipComponentCleanup = $false; TestOSVersion = '6.1.7601'}
    ) {
        $SkipUpdates = $TestSkipUpdates; $SkipComponentCleanup = $TestSkipComponentCleanup; $OSVersion = $TestOSVersion
        Invoke-DismCleanupImage 6>$null | Out-Null
        $script:Dism.Count | Should -Be 0
    }
}

Describe 'Mount-ImportOSMediaWim' {
    BeforeEach {
        $MountDirectory = Join-Path $TestDrive "Mount$([guid]::NewGuid().Guid)"
        $SourceImagePath = 'D:\sources\install.wim'; $SourceImageIndex = 6; $SourceTempWim = 'C:\Temp\install.wim'
        Mock Mount-WindowsImage {}
    }

    It 'creates the mount directory and mounts the index of the install.wim read only' {
        $OSMediaGetItem = [PSCustomObject]@{Extension = '.wim'}
        $Output = (Mount-ImportOSMediaWim 6>&1) -join "`n"
        Test-Path $MountDirectory | Should -BeTrue
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq 'D:\sources\install.wim') -and ($Index -eq 6) -and ($Path -eq $MountDirectory) -and $ReadOnly}
        $Output | Should -BeLike '*Index: 6*'
    }

    It 'mounts index 1 of the temporary wim for an install.esd' {
        $OSMediaGetItem = [PSCustomObject]@{Extension = '.esd'}
        New-Item -Path $MountDirectory -ItemType Directory -Force | Out-Null
        Mount-ImportOSMediaWim 6>$null
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq 'C:\Temp\install.wim') -and ($Index -eq '1') -and $ReadOnly}
    }
}

Describe 'Mount-InstallwimOS' {
    It 'mounts index 1 of WimTemp\install.wim with a log' {
        $MountDirectory = 'C:\Mount'; $Info = 'C:\OSBuild\info'; $WimTemp = 'C:\OSBuild\WimTemp'
        Mock Mount-WindowsImage {}
        (Mount-InstallwimOS 6>&1) -join "`n" | Should -BeLike '*OS: Mount to C:\Mount*'
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($ImagePath -eq 'C:\OSBuild\WimTemp\install.wim') -and ($Index -eq 1) -and ($Path -eq 'C:\Mount') -and ($LogPath -like 'C:\OSBuild\info\logs\*-Mount-WindowsImage.log')
        }
    }
}

Describe 'Mount-OSDOfflineRegistryPE' {
    BeforeEach {
        Register-RegMock
        $MountPath = Join-Path $TestDrive "WinPE$([guid]::NewGuid().Guid)"
    }

    It 'loads the system profile, DEFAULT, SOFTWARE and SYSTEM hives of WinPE' {
        New-TestFile -Path (Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $MountPath 'Windows') 'ServiceProfiles') 'LocalService') '.') 'NTUser.dat') | Out-Null
        New-MountedHives -MountDirectory $MountPath -Hive 'DEFAULT', 'SOFTWARE', 'SYSTEM'
        Mount-OSDOfflineRegistryPE -MountPath $MountPath
        $script:RegCalls[0] | Should -BeLike 'load HKLM\OfflineDefaultUser *Windows\ServiceProfiles\LocalService\NTUser.dat'
        $script:RegCalls[1] | Should -BeLike 'load HKLM\OfflineDefault *Windows\System32\Config\DEFAULT'
        $script:RegCalls[2] | Should -BeLike 'load HKLM\OfflineSoftware *Windows\System32\Config\SOFTWARE'
        $script:RegCalls[3] | Should -BeLike 'load HKLM\OfflineSystem *Windows\System32\Config\SYSTEM'
    }

    It 'loads only the hives that exist' {
        New-MountedHives -MountDirectory $MountPath -Hive 'SYSTEM'
        Mount-OSDOfflineRegistryPE -MountPath $MountPath
        $script:RegCalls | Should -BeLike 'load HKLM\OfflineSystem *'
    }

    It 'does nothing when the mount path does not exist' {
        Mount-OSDOfflineRegistryPE -MountPath (Join-Path $TestDrive 'Missing')
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

Describe 'Mount-PEBuild' {
    It 'mounts index 1 of the working wim' {
        $Info = 'C:\PEBuild\info'
        Mock Mount-WindowsImage {}
        Mount-PEBuild -MountDirectory 'C:\Mount\PE' -WorkingWim 'C:\PEBuild\WinPE.wim' 6>$null
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($ImagePath -eq 'C:\PEBuild\WinPE.wim') -and ($Index -eq 1) -and ($Path -eq 'C:\Mount\PE') -and ($LogPath -like 'C:\PEBuild\info\logs\*-Mount-PEBuild.log')
        }
    }
}

Describe 'Mount-WinPEwim' {
    It 'mounts WimTemp\winpe.wim to MountWinPE' {
        $MountWinPE = 'C:\Mount\WinPE'
        Mock Mount-WindowsImage {}
        (Mount-WinPEwim -OSMediaPath 'C:\OSMedia' 6>&1) -join "`n" | Should -BeLike '*Mount WinPE.wim to C:\Mount\WinPE*'
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($ImagePath -eq 'C:\OSMedia\WimTemp\winpe.wim') -and ($Path -eq 'C:\Mount\WinPE') -and ($LogPath -like 'C:\OSMedia\WinPE\info\logs\*-Mount-WindowsImage-WinPE.log')
        }
    }
}

Describe 'Mount-WinREwim' {
    It 'mounts WimTemp\winre.wim to MountWinRE' {
        $MountWinRE = 'C:\Mount\WinRE'
        Mock Mount-WindowsImage {}
        (Mount-WinREwim -OSMediaPath 'C:\OSMedia' 6>&1) -join "`n" | Should -BeLike '*Mount WinRE.wim to C:\Mount\WinRE*'
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($ImagePath -eq 'C:\OSMedia\WimTemp\winre.wim') -and ($Path -eq 'C:\Mount\WinRE') -and ($LogPath -like 'C:\OSMedia\WinPE\info\logs\*-Mount-WindowsImage-WinRE.log')
        }
    }
}

Describe 'Mount-WinSEwim' {
    It 'mounts WimTemp\winse.wim to MountWinSE' {
        $MountWinSE = 'C:\Mount\WinSE'
        Mock Mount-WindowsImage {}
        (Mount-WinSEwim -OSMediaPath 'C:\OSMedia' 6>&1) -join "`n" | Should -BeLike '*Mount WinSE.wim to C:\Mount\WinSE*'
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($ImagePath -eq 'C:\OSMedia\WimTemp\winse.wim') -and ($Path -eq 'C:\Mount\WinSE') -and ($LogPath -like 'C:\OSMedia\WinPE\info\logs\*-Mount-WindowsImage-WinSE.log')
        }
    }
}

Describe 'New-DirectoriesOSMedia' {
    It 'creates the OSMedia, info, WinPE and mount directories' {
        $Root = Join-Path $TestDrive 'OSMedia'
        $Info = Join-Path $Root 'info'; $OS = Join-Path $Root 'OS'; $WinPE = Join-Path $Root 'WinPE'; $PEInfo = Join-Path $WinPE 'info'
        $WimTemp = Join-Path $Root 'WimTemp'; $MountDirectory = Join-Path $Root 'Mount'
        $MountWinPE = Join-Path $Root 'MountWinPE'; $MountWinSE = Join-Path $Root 'MountWinSE'; $MountWinRE = Join-Path $Root 'MountWinRE'
        New-DirectoriesOSMedia
        foreach ($Path in @($Info, $OS, $WinPE, $PEInfo, $WimTemp, $MountDirectory, $MountWinPE, $MountWinSE, $MountWinRE)) {
            Test-Path -Path $Path -PathType Container | Should -BeTrue
        }
        foreach ($Folder in 'json', 'logs', 'xml') {
            Test-Path -Path (Join-Path $Info $Folder) -PathType Container | Should -BeTrue
            Test-Path -Path (Join-Path $PEInfo $Folder) -PathType Container | Should -BeTrue
        }
    }

    It 'keeps existing directories and their content' {
        $Root = Join-Path $TestDrive 'OSMediaExisting'
        $Info = Join-Path $Root 'info'; $OS = Join-Path $Root 'OS'; $WinPE = Join-Path $Root 'WinPE'; $PEInfo = Join-Path $WinPE 'info'
        $WimTemp = Join-Path $Root 'WimTemp'; $MountDirectory = Join-Path $Root 'Mount'
        $MountWinPE = Join-Path $Root 'MountWinPE'; $MountWinSE = Join-Path $Root 'MountWinSE'; $MountWinRE = Join-Path $Root 'MountWinRE'
        $Existing = New-TestFile -Path (Join-Path (Join-Path $Info 'logs') 'Import-OSMedia.log') -Value 'existing log'
        New-DirectoriesOSMedia
        Get-Content -Path $Existing.FullName | Should -Be 'existing log'
        Test-Path -Path (Join-Path $Info 'json') -PathType Container | Should -BeTrue
    }
}

Describe 'New-ItemDirectoryGetOSDBuilderHome' {
    It 'creates the missing OSDBuilder home directories' {
        $GetOSDBuilderHome = Join-Path $TestDrive 'OSDBuilder'
        $Names = 'Content', 'ContentPacks', 'FeatureUpdates', 'OSBuilds', 'OSImport', 'OSMedia', 'PEBuilds', 'Tasks', 'Templates', 'Mount', 'Updates'
        foreach ($Name in $Names) {Set-Variable -Name "SetOSDBuilderPath$Name" -Value (Join-Path $GetOSDBuilderHome $Name)}
        New-Item -Path $SetOSDBuilderPathOSMedia -ItemType Directory -Force | Out-Null
        New-TestFile -Path (Join-Path $SetOSDBuilderPathOSMedia 'keep.txt') | Out-Null
        New-ItemDirectoryGetOSDBuilderHome
        foreach ($Name in $Names) {Test-Path -Path (Join-Path $GetOSDBuilderHome $Name) -PathType Container | Should -BeTrue}
        Test-Path -Path (Join-Path $SetOSDBuilderPathOSMedia 'keep.txt') | Should -BeTrue
    }
}

Describe 'New-ItemDirectorySetOSDBuilderPathContent' {
    It 'creates the Content directories with the ADK, DaRT and IsoExtract folders' {
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
        $GetOSDBuilderPathContentADK = Join-Path $SetOSDBuilderPathContent 'ADK'
        $GetOSDBuilderPathContentDaRT = Join-Path $SetOSDBuilderPathContent 'DaRT'
        $GetOSDBuilderPathContentDrivers = Join-Path $SetOSDBuilderPathContent 'Drivers'
        $GetOSDBuilderPathContentIsoExtract = Join-Path $SetOSDBuilderPathContent 'IsoExtract'
        $SetOSDBuilderPathMount = Join-Path $TestDrive 'Mount'
        $GetOSDBuilderPathContentOneDrive = Join-Path $SetOSDBuilderPathContent 'OneDrive'
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'Updates'
        $GetOSDBuilderPathContentPackages = Join-Path $SetOSDBuilderPathContent 'Packages'
        $GetOSDBuilderPathContentScripts = Join-Path $SetOSDBuilderPathContent 'Scripts'
        $GetOSDBuilderPathContentStartLayout = Join-Path $SetOSDBuilderPathContent 'StartLayout'
        $GetOSDBuilderPathContentUnattend = Join-Path $SetOSDBuilderPathContent 'Unattend'
        New-Item -Path $SetOSDBuilderPathMount -ItemType Directory -Force | Out-Null
        New-ItemDirectorySetOSDBuilderPathContent
        foreach ($Path in @($GetOSDBuilderPathContentDrivers, $SetOSDBuilderPathMount, $GetOSDBuilderPathContentOneDrive, $SetOSDBuilderPathUpdates,
            $GetOSDBuilderPathContentPackages, $GetOSDBuilderPathContentScripts, $GetOSDBuilderPathContentStartLayout, $GetOSDBuilderPathContentUnattend,
            (Join-Path $SetOSDBuilderPathContent 'ExtraFiles'), (Join-Path $GetOSDBuilderPathContentDaRT 'DaRT 10'),
            (Join-Path (Join-Path $GetOSDBuilderPathContentADK 'Windows 10 2004') 'Windows Preinstallation Environment'),
            (Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows 10 2004 FOD x64'),
            (Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows Server 2019 1809 Language'))) {
            Test-Path -Path $Path -PathType Container | Should -BeTrue
        }
    }
}

Describe 'Remove-AppxProvisionedPackageOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10; $MountDirectory = 'C:\Mount'; $Info = 'C:\OSBuild\info'
        $RemoveAppx = @('Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe', 'Microsoft.GetHelp_10.2409.22951.0_neutral_~_8wekyb3d8bbwe')
        Mock Remove-AppxProvisionedPackage {}
    }

    It 'removes every Appx package of the task' {
        Remove-AppxProvisionedPackageOS 6>$null
        foreach ($Item in $RemoveAppx) {
            Should -Invoke Remove-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {
                ($Path -eq 'C:\Mount') -and ($PackageName -eq $Item) -and ($LogPath -like 'C:\OSBuild\info\logs\*-Remove-AppxProvisionedPackage.log')
            }
        }
    }

    It 'warns and continues when a package cannot be removed' {
        Mock Remove-AppxProvisionedPackage {throw 'The package is not provisioned'} -ParameterFilter {$PackageName -like 'Microsoft.BingNews*'}
        $Warnings = (Remove-AppxProvisionedPackageOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*The package is not provisioned*'
        Should -Invoke Remove-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {$PackageName -like 'Microsoft.GetHelp*'}
    }

    It 'does nothing for <Case>' -TestCases @(
        @{Case = 'New-PEBuild'; TestScriptName = 'New-PEBuild'; TestOSMajorVersion = 10; TestRemove = @('Microsoft.BingNews')}
        @{Case = 'Windows 7'; TestScriptName = 'New-OSBuild'; TestOSMajorVersion = 6; TestRemove = @('Microsoft.BingNews')}
        @{Case = 'no packages'; TestScriptName = 'New-OSBuild'; TestOSMajorVersion = 10; TestRemove = @()}
    ) {
        $ScriptName = $TestScriptName; $OSMajorVersion = $TestOSMajorVersion; $RemoveAppx = $TestRemove
        Remove-AppxProvisionedPackageOS 6>$null
        Should -Invoke Remove-AppxProvisionedPackage -Times 0 -Exactly
    }
}

Describe 'Remove-WindowsCapabilityOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $MountDirectory = 'C:\Mount'; $Info = 'C:\OSBuild\info'
        $RemoveCapability = @('App.StepsRecorder~~~~0.0.1.0', 'Browser.InternetExplorer~~~~0.0.11.0')
        Mock Remove-WindowsCapability {}
    }

    It 'removes every capability of the task' {
        Remove-WindowsCapabilityOS 6>$null
        Should -Invoke Remove-WindowsCapability -Times 2 -Exactly
        Should -Invoke Remove-WindowsCapability -Times 1 -Exactly -ParameterFilter {
            ($Path -eq 'C:\Mount') -and ($Name -eq 'App.StepsRecorder~~~~0.0.1.0') -and ($LogPath -like 'C:\OSBuild\info\logs\*-Remove-WindowsCapability.log')
        }
    }

    It 'warns and continues when a capability cannot be removed' {
        Mock Remove-WindowsCapability {throw 'Capability not present'} -ParameterFilter {$Name -like 'App.*'}
        $Warnings = (Remove-WindowsCapabilityOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Capability not present*'
        Should -Invoke Remove-WindowsCapability -Times 1 -Exactly -ParameterFilter {$Name -like 'Browser.*'}
    }

    It 'does nothing for <Case>' -TestCases @(
        @{Case = 'New-PEBuild'; TestScriptName = 'New-PEBuild'; TestRemove = @('App.StepsRecorder~~~~0.0.1.0')}
        @{Case = 'no capabilities'; TestScriptName = 'New-OSBuild'; TestRemove = $null}
    ) {
        $ScriptName = $TestScriptName; $RemoveCapability = $TestRemove
        Remove-WindowsCapabilityOS 6>$null
        Should -Invoke Remove-WindowsCapability -Times 0 -Exactly
    }
}

Describe 'Remove-WindowsPackageOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $MountDirectory = 'C:\Mount'; $Info = 'C:\OSBuild\info'
        $RemovePackage = @('Microsoft-Windows-Hello-Face-Package~31bf3856ad364e35~amd64~~10.0.26100.1', 'Microsoft-Windows-QuickAssist-Package~31bf3856ad364e35~amd64~~10.0.26100.1')
        Mock Remove-WindowsPackage {}
    }

    It 'removes every package of the task' {
        Remove-WindowsPackageOS 6>$null
        Should -Invoke Remove-WindowsPackage -Times 2 -Exactly
        Should -Invoke Remove-WindowsPackage -Times 1 -Exactly -ParameterFilter {
            ($Path -eq 'C:\Mount') -and ($PackageName -like 'Microsoft-Windows-Hello-Face*') -and ($LogPath -like 'C:\OSBuild\info\logs\*-Remove-WindowsPackage.log')
        }
    }

    It 'warns and continues when a package cannot be removed' {
        Mock Remove-WindowsPackage {throw 'The specified package is not valid'} -ParameterFilter {$PackageName -like '*Hello-Face*'}
        $Warnings = (Remove-WindowsPackageOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*The specified package is not valid*'
        Should -Invoke Remove-WindowsPackage -Times 1 -Exactly -ParameterFilter {$PackageName -like '*QuickAssist*'}
    }

    It 'does nothing for <Case>' -TestCases @(
        @{Case = 'New-PEBuild'; TestScriptName = 'New-PEBuild'; TestRemove = @('Package')}
        @{Case = 'no packages'; TestScriptName = 'New-OSBuild'; TestRemove = ''}
    ) {
        $ScriptName = $TestScriptName; $RemovePackage = $TestRemove
        Remove-WindowsPackageOS 6>$null
        Should -Invoke Remove-WindowsPackage -Times 0 -Exactly
    }
}

Describe 'Rename-OSMedia' {
    BeforeEach {
        $SetOSDBuilderPathOSMedia = Join-Path $TestDrive "OSMedia$([guid]::NewGuid().Guid)"
        New-Item -Path $SetOSDBuilderPathOSMedia -ItemType Directory -Force | Out-Null
        $script:GridItems = [System.Collections.Generic.List[object]]::new()
        Mock Get-OSDBuilder {}
        Mock Out-GridView {if ($InputObject) {$script:GridItems.Add($InputObject); $InputObject}}
    }

    It 'renames <ImageName> build <Build> to <Expected>' -TestCases @(
        @{ImageName = 'Windows 11 Enterprise'; Architecture = 9; Build = 26200; UBR = 6899; Languages = @('en-US'); InstallationType = 'Client'; MajorVersion = 10; ReleaseId = '25H2'; Expected = 'Windows 11 Enterprise x64 25H2 6899'}
        @{ImageName = 'Windows 10 Enterprise'; Architecture = 0; Build = 17763; UBR = 6893; Languages = @('en-US', 'de-DE'); InstallationType = 'Client'; MajorVersion = 10; ReleaseId = $null; Expected = 'Windows 10 Enterprise x86 1809 6893 en-US de-DE'}
        @{ImageName = 'Windows 7 Professional'; Architecture = 9; Build = 7601; UBR = 24544; Languages = @('de-DE'); InstallationType = 'Client'; MajorVersion = 6; ReleaseId = $null; Expected = 'Windows 7 Professional x64 SP1 24544 de-DE'}
        @{ImageName = 'Windows 7 Starter'; Architecture = 0; Build = 7600; UBR = 16385; Languages = @('en-US'); InstallationType = 'Client'; MajorVersion = 6; ReleaseId = $null; Expected = 'Windows 7 Starter x86 7600 16385'}
        @{ImageName = 'Windows Server 2012 R2 SERVERSTANDARD'; Architecture = 6; Build = 9600; UBR = 21620; Languages = @('en-US'); InstallationType = 'Server'; MajorVersion = 6; ReleaseId = $null; Expected = 'Windows Server 2012 R2 SERVERSTANDARD ia64 9600 21620'}
        @{ImageName = 'Windows 10 Enterprise 2015 LTSB'; Architecture = 9; Build = 10240; UBR = 20796; Languages = @('en-US'); InstallationType = 'Client'; MajorVersion = 10; ReleaseId = $null; Expected = 'Windows 10 Enterprise 2015 LTSB x64 1507 20796'}
        @{ImageName = 'Windows Server 2016 SERVERDATACENTER (Desktop Experience)'; Architecture = 9; Build = 14393; UBR = 7428; Languages = @('en-US'); InstallationType = 'Server'; MajorVersion = 10; ReleaseId = $null; Expected = 'Windows Server 2016 SERVERDATACENTER Desktop Experience x64 1607 7428'}
        @{ImageName = 'Windows 10 Pro'; Architecture = 12; Build = 15063; UBR = 2679; Languages = @('en-US'); InstallationType = 'Client'; MajorVersion = 10; ReleaseId = $null; Expected = 'Windows 10 Pro x64 ARM 1703 2679'}
        @{ImageName = 'Windows 10 Education'; Architecture = 9; Build = 16299; UBR = 2166; Languages = @('en-US'); InstallationType = 'Client'; MajorVersion = 10; ReleaseId = $null; Expected = 'Windows 10 Education x64 1709 2166'}
        @{ImageName = 'Windows Server 2019 SERVERSTANDARD'; Architecture = 9; Build = 17134; UBR = 2208; Languages = @('en-US'); InstallationType = 'Server'; MajorVersion = 10; ReleaseId = $null; Expected = 'Windows Server 2019 SERVERSTANDARD x64 1803 2208'}
        @{ImageName = 'Windows Server 2022 SERVERSTANDARD'; Architecture = 9; Build = 20348; UBR = 4171; Languages = @('en-US'); InstallationType = 'Server'; MajorVersion = 10; ReleaseId = '2009'; Expected = 'Windows Server 2022 SERVERSTANDARD x64 2009 4171'}
    ) {
        $Media = New-OSMediaFixture -Root $SetOSDBuilderPathOSMedia -Name 'Imported OSMedia' -ImageName $ImageName -Architecture $Architecture -Build $Build -UBR $UBR -Languages $Languages -InstallationType $InstallationType -MajorVersion $MajorVersion -ReleaseId $ReleaseId
        Rename-OSMedia 3>$null
        Test-Path -Path (Join-Path $SetOSDBuilderPathOSMedia $Expected) -PathType Container | Should -BeTrue
        Test-Path -Path $Media.FullName | Should -BeFalse
        $script:GridItems[0].FullNameFormat | Should -Be $Expected
        $script:GridItems[0].Name | Should -Be 'Imported OSMedia'
        Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
    }

    It 'warns about every rename' {
        New-OSMediaFixture -Root $SetOSDBuilderPathOSMedia -Name 'Old' -ImageName 'Windows 11 Pro' -ReleaseId '25H2' | Out-Null
        $Warnings = (Rename-OSMedia 3>&1) -join "`n"
        $Warnings | Should -BeLike "*Renaming *Old to Windows 11 Pro x64 25H2 6899*"
    }

    It 'adds an OSMGuid and writes the WindowsImage files when the OSMedia has none' {
        $Media = New-OSMediaFixture -Root $SetOSDBuilderPathOSMedia -Name 'Windows 11 Pro x64 25H2 6899' -ImageName 'Windows 11 Pro' -ReleaseId '25H2' -OSMGuid ''
        Rename-OSMedia 3>$null
        $Image = Import-Clixml -Path (Join-Path (Join-Path (Join-Path $Media.FullName 'info') 'xml') 'Get-WindowsImage.xml')
        {[guid]$Image.OSMGuid} | Should -Not -Throw
        Get-Content -Path (Join-Path (Join-Path (Join-Path $Media.FullName 'info') 'json') 'Get-WindowsImage.json') -Raw | Should -BeLike "*$($Image.OSMGuid)*"
        $Text = Get-Content -Path (Join-Path $Media.FullName 'WindowsImage.txt')
        $Text | Where-Object {-not $_.Trim()} | Should -BeNullOrEmpty
        ($Text -join "`n") | Should -BeLike '*OSMGuid*'
        @(Get-ChildItem -Path (Join-Path (Join-Path $Media.FullName 'info') 'logs') -Filter '*-Get-WindowsImage.txt').Count | Should -Be 1
    }

    It 'does not offer OSMedia that already have the right name and ignores directories without Get-WindowsImage.xml' {
        New-OSMediaFixture -Root $SetOSDBuilderPathOSMedia -Name 'Windows 11 Pro x64 25H2 6899' -ImageName 'Windows 11 Pro' -ReleaseId '25H2' | Out-Null
        New-Item -Path (Join-Path $SetOSDBuilderPathOSMedia 'Not an OSMedia') -ItemType Directory | Out-Null
        Rename-OSMedia 3>$null
        $script:GridItems.Count | Should -Be 0
        Test-Path -Path (Join-Path $SetOSDBuilderPathOSMedia 'Not an OSMedia') | Should -BeTrue
    }

    It 'renames nothing when no OSMedia is selected' {
        Mock Out-GridView {}
        $Media = New-OSMediaFixture -Root $SetOSDBuilderPathOSMedia -Name 'Old' -ImageName 'Windows 11 Pro' -ReleaseId '25H2'
        Rename-OSMedia 3>$null
        Test-Path -Path $Media.FullName | Should -BeTrue
    }
}

Describe 'Repair-OSBuildTask' {
    BeforeAll {
        $SavedGetOSDBuilder = $global:GetOSDBuilder
        $global:GetOSDBuilder = [PSCustomObject]@{VersionOSDBuilder = '26.10.14.1'}
    }
    AfterAll {
        $global:GetOSDBuilder = $SavedGetOSDBuilder
    }
    BeforeEach {
        $TaskDirectory = Join-Path $TestDrive "Tasks$([guid]::NewGuid().Guid)"
        New-Item -Path $TaskDirectory -ItemType Directory -Force | Out-Null
        $TaskPath = Join-Path $TaskDirectory 'OSBuild Win10 x64 1809.json'
        $TaskJson = [ordered]@{
            TaskName = 'Win10 x64 1809'; TaskVersion = '19.1.1.0'; MediaName = 'Windows 10 Enterprise x64 1809 17763.253'; BuildName = 'Win10 Custom'
            EnableNetFX3 = 'True'; ImportStartLayout = 'StartLayout\Layout.xml'; UseWindowsUnattend = 'Unattend\Unattend.xml'; WinPEAddDaRT = 'DaRT\DaRT 10'
            RobocopyExtraFiles = @('ExtraFiles\Wallpaper'); InvokeScript = @('Scripts\Cleanup.ps1'); AddWindowsDriver = @('Drivers\Dell')
            RemoveAppxProvisionedPackage = @('Microsoft.BingNews'); RemoveWindowsCapability = @('App.StepsRecorder~~~~0.0.1.0')
            WinPEInvokeScriptSetup = @('WinPE\Scripts\Setup.ps1'); LangSetUILang = 'de-DE'; AddLanguagePack = @('LanguagePacks\de-DE.cab')
        } | ConvertTo-Json
        Set-Content -Path $TaskPath -Value $TaskJson
        $script:Media = @(
            New-RepairMedia 'x64' '1511'; New-RepairMedia 'x64' '1607'; New-RepairMedia 'x64' '1703'; New-RepairMedia 'x64' '1709'
            New-RepairMedia 'x64' '1803'; New-RepairMedia 'x64' '1809'; New-RepairMedia 'x86' '1809'
        )
        $script:Select = 'Windows 10 Enterprise x64 1809'
        $script:GridItems = [System.Collections.Generic.List[string]]::new()
        Mock Get-OSDBuilder {}
        Mock Get-OSBuildTask {
            [PSCustomObject]@{FullName = $TaskPath; OSMGuid = $null}
            [PSCustomObject]@{FullName = (Join-Path $TaskDirectory 'Repaired.json'); OSMGuid = [guid]::NewGuid().Guid}
        }
        Mock Get-OSMedia {$script:Media}
        Mock Out-GridView {if ($InputObject) {$script:GridItems.Add($InputObject.Name); if ($InputObject.Name -eq $script:Select) {$InputObject}}}
    }

    It 'rewrites the task with the selected OSMedia and the renamed properties' {
        Repair-OSBuildTask 6>$null 3>$null
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Selected = $script:Media | Where-Object {$_.Name -eq $script:Select}
        $Task.TaskType | Should -Be 'OSBuild'
        $Task.TaskName | Should -Be 'Win10 x64 1809'
        $Task.TaskVersion | Should -Be '26.10.14.1'
        $Task.CustomName | Should -Be 'Win10 Custom'
        $Task.OSMGuid | Should -Be $Selected.OSMGuid
        $Task.OSMFamily | Should -Be $Selected.OSMFamily
        $Task.ReleaseId | Should -Be '1809'
        $Task.StartLayoutXML | Should -Be 'StartLayout\Layout.xml'
        $Task.UnattendXML | Should -Be 'Unattend\Unattend.xml'
        $Task.WinPEAutoExtraFiles | Should -Be 'False'
        $Task.WinPEDaRT | Should -Be 'DaRT\DaRT 10'
        $Task.ExtraFiles | Should -Be 'ExtraFiles\Wallpaper'
        $Task.Scripts | Should -Be 'Scripts\Cleanup.ps1'
        $Task.Drivers | Should -Be 'Drivers\Dell'
        $Task.RemoveAppxProvisionedPackage | Should -Be 'Microsoft.BingNews'
        $Task.WinPEScriptsSE | Should -Be 'WinPE\Scripts\Setup.ps1'
        $Task.LangSetUILang | Should -Be 'de-DE'
        $Task.LanguagePack | Should -Be 'LanguagePacks\de-DE.cab'
        {[guid]$Task.TaskGuid} | Should -Not -Throw
        Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
    }

    It 'saves a backup of the original task in Repair' {
        $Original = Get-Content -Path $TaskPath -Raw
        $Warnings = (Repair-OSBuildTask 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*Repair Required: $TaskPath*"
        Get-Content -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) -Raw | Should -Be $Original
    }

    It 'keeps an existing backup' {
        New-TestFile -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) -Value 'first backup' | Out-Null
        Repair-OSBuildTask 6>$null 3>$null
        Get-Content -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) | Should -Be 'first backup'
        (Get-Content -Path $TaskPath -Raw | ConvertFrom-Json).TaskType | Should -Be 'OSBuild'
    }

    It 'offers only the OSMedia that match <MediaName>' -TestCases @(
        @{MediaName = 'Windows 10 Enterprise x64 1511'; Expected = @('Windows 10 Enterprise x64 1511')}
        @{MediaName = 'Windows 10 Enterprise x64 1607'; Expected = @('Windows 10 Enterprise x64 1607')}
        @{MediaName = 'Windows 10 Enterprise x64 1703'; Expected = @('Windows 10 Enterprise x64 1703')}
        @{MediaName = 'Windows 10 Enterprise x64 1709'; Expected = @('Windows 10 Enterprise x64 1709')}
        @{MediaName = 'Windows 10 Enterprise x64 1803'; Expected = @('Windows 10 Enterprise x64 1803')}
        @{MediaName = 'Windows 10 Enterprise x86 1809'; Expected = @('Windows 10 Enterprise x86 1809')}
        @{MediaName = 'Windows 10 Enterprise 1809'; Expected = @('Windows 10 Enterprise x64 1809', 'Windows 10 Enterprise x86 1809')}
    ) {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.MediaName = $MediaName
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath
        $script:Select = $Expected[0]
        Repair-OSBuildTask 6>$null 3>$null
        @($script:GridItems) | Should -Be $Expected
        (Get-Content -Path $TaskPath -Raw | ConvertFrom-Json).Name | Should -Be $Expected[0]
    }

    It 'does not change a task that is newer than 19.1.3' {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.TaskVersion = '19.1.4.0'
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath
        $Before = Get-Content -Path $TaskPath -Raw
        $Warnings = (Repair-OSBuildTask 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*OSBuild Task does not need a Repair*'
        Get-Content -Path $TaskPath -Raw | Should -Be $Before
        Should -Invoke Get-OSMedia -Times 0 -Exactly
    }

    It 'does not change the task when no OSMedia is selected' {
        $script:Select = 'None'
        $Before = Get-Content -Path $TaskPath -Raw
        $Warnings = (Repair-OSBuildTask 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*OSMedia was not selected*'
        Get-Content -Path $TaskPath -Raw | Should -Be $Before
        Test-Path -Path (Join-Path $TaskDirectory 'Repair') | Should -BeFalse
    }
}

Describe 'Repair-PEBuildTask' {
    BeforeAll {
        $SavedGetOSDBuilder = $global:GetOSDBuilder
        $global:GetOSDBuilder = [PSCustomObject]@{VersionOSDBuilder = '26.10.14.1'}
    }
    AfterAll {
        $global:GetOSDBuilder = $SavedGetOSDBuilder
    }
    BeforeEach {
        $TaskDirectory = Join-Path $TestDrive "PETasks$([guid]::NewGuid().Guid)"
        New-Item -Path (Join-Path $TaskDirectory 'Repair') -ItemType Directory -Force | Out-Null
        $TaskPath = Join-Path $TaskDirectory 'PEBuild WinPE x64 1809.json'
        $TaskJson = [ordered]@{
            TaskName = 'WinPE x64 1809'; TaskVersion = '19.1.1.0'; MediaName = 'Windows 10 Enterprise x64 1809 17763.253'
            PEOutput = 'MDT'; DeploymentShare = '\\server\DeploymentShare$'; ScratchSpace = '512'; SourceWim = 'WinPE'; AutoExtraFiles = 'True'
            WinPEAddDaRT = 'DaRT\DaRT 10'; WinPEAddWindowsDriver = @('WinPE\Drivers\Intel'); WinPERobocopyExtraFiles = @('WinPE\ExtraFiles\Tools')
            WinPEInvokeScript = @('WinPE\Scripts\Start.ps1'); WinPEAddADK = @('ADK\WinPE-PowerShell.cab', 'ADK\WinPE-WMI.cab')
        } | ConvertTo-Json
        Set-Content -Path $TaskPath -Value $TaskJson
        $script:Media = @(
            New-RepairMedia 'x64' '1511'; New-RepairMedia 'x64' '1607'; New-RepairMedia 'x64' '1703'; New-RepairMedia 'x64' '1709'
            New-RepairMedia 'x64' '1803'; New-RepairMedia 'x64' '1809'; New-RepairMedia 'x86' '1809'
        )
        $script:Select = 'Windows 10 Enterprise x64 1809'
        $script:GridItems = [System.Collections.Generic.List[string]]::new()
        Mock Get-OSDBuilder {}
        Mock Get-PEBuildTask {[PSCustomObject]@{FullName = $TaskPath; OSMGuid = $null}}
        Mock Get-OSMedia {$script:Media}
        Mock Out-GridView {if ($InputObject) {$script:GridItems.Add($InputObject.Name); if ($InputObject.Name -eq $script:Select) {$InputObject}}}
    }

    It 'rewrites the task with the selected OSMedia and the renamed properties' {
        $Original = Get-Content -Path $TaskPath -Raw
        $Output = (Repair-PEBuildTask 6>&1 3>$null) -join "`n"
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Selected = $script:Media | Where-Object {$_.Name -eq $script:Select}
        $Task.TaskType | Should -Be 'PEBuild'
        $Task.TaskVersion | Should -Be '26.10.14.1'
        $Task.OSMGuid | Should -Be $Selected.OSMGuid
        $Task.Arch | Should -Be 'x64'
        $Task.WinPEOutput | Should -Be 'MDT'
        $Task.MDTDeploymentShare | Should -Be '\\server\DeploymentShare$'
        $Task.ScratchSpace | Should -Be '512'
        $Task.SourceWim | Should -Be 'WinPE'
        $Task.WinPEAutoExtraFiles | Should -Be 'True'
        $Task.WinPEDrivers | Should -Be 'WinPE\Drivers\Intel'
        $Task.WinPEExtraFiles | Should -Be 'WinPE\ExtraFiles\Tools'
        $Task.WinPEScripts | Should -Be 'WinPE\Scripts\Start.ps1'
        $Task.WinPEADK | Should -Be @('ADK\WinPE-PowerShell.cab', 'ADK\WinPE-WMI.cab')
        $Task.CustomName | Should -Be ''
        Get-Content -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) -Raw | Should -Be $Original
        $Output | Should -BeLike '*Update Complete: WinPE x64 1809*'
    }

    It 'offers only the OSMedia that match <MediaName>' -TestCases @(
        @{MediaName = 'Windows 10 Enterprise x64 1511'; Expected = @('Windows 10 Enterprise x64 1511')}
        @{MediaName = 'Windows 10 Enterprise x64 1607'; Expected = @('Windows 10 Enterprise x64 1607')}
        @{MediaName = 'Windows 10 Enterprise x64 1703'; Expected = @('Windows 10 Enterprise x64 1703')}
        @{MediaName = 'Windows 10 Enterprise x64 1709'; Expected = @('Windows 10 Enterprise x64 1709')}
        @{MediaName = 'Windows 10 Enterprise x64 1803'; Expected = @('Windows 10 Enterprise x64 1803')}
        @{MediaName = 'Windows 10 Enterprise x86 1809'; Expected = @('Windows 10 Enterprise x86 1809')}
    ) {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.MediaName = $MediaName
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath
        $script:Select = $Expected[0]
        Repair-PEBuildTask 6>$null 3>$null
        @($script:GridItems) | Should -Be $Expected
        (Get-Content -Path $TaskPath -Raw | ConvertFrom-Json).Name | Should -Be $Expected[0]
    }

    It 'creates the Repair directory for the backup' {
        Remove-Item -Path (Join-Path $TaskDirectory 'Repair') -Recurse -Force
        Repair-PEBuildTask 6>$null 3>$null
        Test-Path -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) -PathType Leaf | Should -BeTrue
    }

    It 'keeps an existing backup' {
        New-TestFile -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) -Value 'first backup' | Out-Null
        Repair-PEBuildTask 6>$null 3>$null
        Get-Content -Path (Join-Path (Join-Path $TaskDirectory 'Repair') (Split-Path $TaskPath -Leaf)) | Should -Be 'first backup'
        (Get-Content -Path $TaskPath -Raw | ConvertFrom-Json).TaskType | Should -Be 'PEBuild'
    }

    It 'does not change a task that is newer than 19.1.3' {
        $Task = Get-Content -Path $TaskPath -Raw | ConvertFrom-Json
        $Task.TaskVersion = '20.1.1.0'
        $Task | ConvertTo-Json | Set-Content -Path $TaskPath
        $Before = Get-Content -Path $TaskPath -Raw
        $Warnings = (Repair-PEBuildTask 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*PEBuild Task does not need a Repair*'
        Get-Content -Path $TaskPath -Raw | Should -Be $Before
    }

    It 'does not change the task when no OSMedia is selected' {
        $script:Select = 'None'
        $Before = Get-Content -Path $TaskPath -Raw
        $Warnings = (Repair-PEBuildTask 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*OSMedia was not selected*'
        Get-Content -Path $TaskPath -Raw | Should -Be $Before
    }
}
