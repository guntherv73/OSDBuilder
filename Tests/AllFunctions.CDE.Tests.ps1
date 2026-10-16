BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}

    #Public OSDBuilder functions used by the Private functions, placeholders so Pester can mock them
    if (-not (Get-Command -Name Get-OSMedia -ErrorAction SilentlyContinue)) {
        function Get-OSMedia {
            [CmdletBinding()]
            param ($OSArch, $OSInstallationType, $OSMajorVersion, $OSReleaseId, $Revision, [switch]$GridView, [switch]$Newest)
            throw 'Get-OSMedia is not loaded, mock it in the test'
        }
    }
}

Describe 'Convert-ByteArrayToHex' {
    It 'returns two lower case hex digits per byte' {
        Convert-ByteArrayToHex -Bytes ([byte[]](0, 15, 16, 171, 255)) | Should -BeExactly '000f10abff'
    }

    It 'converts the space separated decimal hash of an update like Save-OSDBuilderDownload' {
        Convert-ByteArrayToHex -Bytes ('18 52 86 120 154 188 222 240' -split ' ') | Should -BeExactly '123456789abcdef0'
    }
}

Describe 'Copy-MediaLanguageSources' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10
        $LanguageCopySources = @('Client Enterprise x64 26100 de-DE', 'Client Enterprise x64 26100 fr-FR')
        $OS = 'C:\OSBuilds\Build\OS'; $Info = 'C:\OSBuilds\Build\info'
        Mock Get-OSMedia {
            [PSCustomObject]@{OSMFamily = 'Client Enterprise x64 26100 de-DE'; FullName = 'C:\OSMedia\German'}
            [PSCustomObject]@{OSMFamily = 'Client Enterprise x64 26100 fr-FR'; FullName = 'C:\OSMedia\French'}
            [PSCustomObject]@{OSMFamily = 'Client Enterprise x64 26100 it-IT'; FullName = 'C:\OSMedia\Italian'}
        }
        Mock robocopy {}
    }

    It 'copies the OS directory of every Language Source OSMedia without the wim files' {
        Copy-MediaLanguageSources 6>$null
        Should -Invoke Get-OSMedia -Times 2 -Exactly -ParameterFilter {$Revision -eq 'OK'}
        Should -Invoke robocopy -Times 2 -Exactly
        Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {
            ($InputObject -eq 'C:\OSMedia\German\OS') -and ($RemainingArguments[0] -eq 'C:\OSBuilds\Build\OS') -and ($RemainingArguments -contains '*.wim') -and
            (@($RemainingArguments | Where-Object {$_ -like '/Log+:C:\OSBuilds\Build\info\logs\*-Copy-MediaLanguageSources.log'}).Count -eq 1)
        }
        Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {$InputObject -eq 'C:\OSMedia\French\OS'}
        Should -Invoke robocopy -Times 0 -Exactly -ParameterFilter {$InputObject -eq 'C:\OSMedia\Italian\OS'}
    }

    It 'does nothing for <Case>' -ForEach @(
        @{Case = 'New-OSDCloudOSMedia'; Variable = 'ScriptName'; Value = 'New-OSDCloudOSMedia'}
        @{Case = 'an Operating System other than 10'; Variable = 'OSMajorVersion'; Value = 6}
        @{Case = 'a Task without Language Sources'; Variable = 'LanguageCopySources'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Copy-MediaLanguageSources 6>$null
        Should -Invoke Get-OSMedia -Times 0 -Exactly
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Copy-MediaOperatingSystem' {
    BeforeEach {
        $OSMediaPath = 'C:\OSMedia\Windows 11 Enterprise x64 25H2'
        $WorkingPath = Join-Path $TestDrive 'Build'
        $WimTemp = Join-Path $WorkingPath 'WimTemp'
        Mock robocopy {}
    }

    It 'copies the media without images, install.wim and the WinPE wims except boot.wim' {
        Copy-MediaOperatingSystem 6>$null
        Should -Invoke robocopy -Times 3 -Exactly
        Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {
            ($InputObject -eq $OSMediaPath) -and ($RemainingArguments[0] -eq $WorkingPath) -and
            ($RemainingArguments -contains '*.wim') -and ($RemainingArguments -contains '*.iso') -and ($RemainingArguments -contains '*.vhdx')
        }
        Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {
            ($InputObject -eq "$OSMediaPath\OS\sources") -and ($RemainingArguments[0] -eq $WimTemp) -and ($RemainingArguments[1] -eq 'install.wim')
        }
        Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {
            ($InputObject -eq "$OSMediaPath\WinPE") -and ($RemainingArguments[0] -eq $WimTemp) -and ($RemainingArguments[1] -eq '*.wim') -and ($RemainingArguments[-1] -eq 'boot.wim')
        }
    }

    It 'removes the ISO and VHD directories copied from the OSMedia' {
        New-TestFile -Path (Join-Path (Join-Path $WorkingPath 'ISO') 'old.iso') | Out-Null
        New-TestFile -Path (Join-Path (Join-Path $WorkingPath 'VHD') 'old.vhdx') | Out-Null
        New-TestFile -Path (Join-Path (Join-Path $WorkingPath 'OS') 'setup.exe') | Out-Null
        Copy-MediaOperatingSystem 6>$null
        Join-Path $WorkingPath 'ISO' | Should -Not -Exist
        Join-Path $WorkingPath 'VHD' | Should -Not -Exist
        Join-Path (Join-Path $WorkingPath 'OS') 'setup.exe' | Should -Exist
    }
}

Describe 'Disable-WindowsOptionalFeatureOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $MountDirectory = 'C:\Mount'; $Info = 'C:\Build\info'
        $DisableFeature = @('SMB1Protocol', 'Printing-XPSServices-Features')
        Mock Disable-WindowsOptionalFeature {}
    }

    It 'disables every feature of the Task in the mounted image' {
        Disable-WindowsOptionalFeatureOS 6>$null
        Should -Invoke Disable-WindowsOptionalFeature -Times 2 -Exactly
        Should -Invoke Disable-WindowsOptionalFeature -Times 1 -Exactly -ParameterFilter {
            ($FeatureName -eq 'SMB1Protocol') -and ($Path -eq 'C:\Mount') -and ($LogPath -like 'C:\Build\info\logs\*-Disable-WindowsOptionalFeature.log')
        }
        Should -Invoke Disable-WindowsOptionalFeature -Times 1 -Exactly -ParameterFilter {$FeatureName -eq 'Printing-XPSServices-Features'}
    }

    It 'warns and continues when a feature cannot be disabled' {
        Mock Disable-WindowsOptionalFeature {throw 'Feature name SMB1Protocol is unknown'} -ParameterFilter {$FeatureName -eq 'SMB1Protocol'}
        $Warnings = (Disable-WindowsOptionalFeatureOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Feature name SMB1Protocol is unknown*'
        Should -Invoke Disable-WindowsOptionalFeature -Times 1 -Exactly -ParameterFilter {$FeatureName -eq 'Printing-XPSServices-Features'}
    }

    It 'does nothing for <Case>' -ForEach @(
        @{Case = 'New-OSDCloudOSMedia'; Variable = 'ScriptName'; Value = 'New-OSDCloudOSMedia'}
        @{Case = 'a Task without features'; Variable = 'DisableFeature'; Value = $null}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Disable-WindowsOptionalFeatureOS 6>$null
        Should -Invoke Disable-WindowsOptionalFeature -Times 0 -Exactly
    }
}

Describe 'Dismount-InstallwimOS' {
    BeforeEach {
        $MountDirectory = 'C:\Mount'; $Info = 'C:\Build\info'; $WaitDismount = [switch]$false
        Mock Start-Sleep {}
        Mock Read-Host {}
        Mock Dismount-WindowsImage {}
    }

    It 'saves and dismounts the install.wim' {
        Dismount-InstallwimOS 6>$null
        Should -Invoke Dismount-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($Path -eq 'C:\Mount') -and $Save -and ($LogPath -like 'C:\Build\info\logs\*-Dismount-WindowsImage.log')
        }
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {$Seconds -eq 10}
        Should -Invoke Read-Host -Times 0 -Exactly
    }

    It 'waits for Enter with -WaitDismount' {
        $WaitDismount = [switch]$true
        Dismount-InstallwimOS 6>$null
        Should -Invoke Read-Host -Times 1 -Exactly
        Should -Invoke Dismount-WindowsImage -Times 1 -Exactly
    }

    It 'waits 30 seconds and dismounts again when the first dismount fails' {
        $script:DismountCount = 0
        Mock Dismount-WindowsImage {$script:DismountCount++; if ($script:DismountCount -eq 1) {throw 'The process cannot access the file'}}
        $Warnings = (Dismount-InstallwimOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Could not dismount Install.wim ... Waiting 30 seconds*'
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {$Seconds -eq 30}
        Should -Invoke Dismount-WindowsImage -Times 2 -Exactly -ParameterFilter {$Save}
    }
}

Describe 'Dismount-OSDOfflineRegistry' {
    BeforeEach {
        $script:Hives = @{
            'HKLM:\OfflineDefaultUser' = $true
            'HKLM:\OfflineDefault'     = $true
            'HKLM:\OfflineSoftware'    = $true
            'HKLM:\OfflineSystem'      = $true
        }
        Mock Test-Path {[bool]$script:Hives["$Path"]} -ParameterFilter {"$Path" -like 'HKLM:\*'}
        Mock Start-Process {$script:Hives["HKLM:\$(("$ArgumentList" -replace '^unload HKLM\\', ''))"] = $false}
        Mock Pause {}
    }

    It 'unloads every loaded offline hive' {
        Dismount-OSDOfflineRegistry -MountPath $TestDrive
        Should -Invoke Start-Process -Times 4 -Exactly
        foreach ($Hive in 'OfflineDefaultUser', 'OfflineDefault', 'OfflineSoftware', 'OfflineSystem') {
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {($FilePath -eq 'reg') -and ("$ArgumentList" -eq "unload HKLM\$Hive") -and $Wait}
        }
        Should -Invoke Pause -Times 0 -Exactly
    }

    It 'unloads only the hives that are loaded' {
        $script:Hives['HKLM:\OfflineDefaultUser'] = $false
        $script:Hives['HKLM:\OfflineDefault'] = $false
        Dismount-OSDOfflineRegistry -MountPath $TestDrive
        Should -Invoke Start-Process -Times 2 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly -ParameterFilter {"$ArgumentList" -like '*OfflineDefault*'}
    }

    It 'tries a second time and warns for every hive that cannot be unloaded' {
        Mock Start-Process {}
        $Warnings = (Dismount-OSDOfflineRegistry -MountPath $TestDrive 3>&1) -join "`n"
        Should -Invoke Start-Process -Times 8 -Exactly
        Should -Invoke Pause -Times 4 -Exactly
        foreach ($Hive in 'OfflineDefaultUser', 'OfflineDefault', 'OfflineSoftware', 'OfflineSystem') {
            $Warnings | Should -BeLike "*HKLM:\$Hive could not be dismounted*"
        }
    }

    It 'does nothing when the mount path does not exist' {
        Dismount-OSDOfflineRegistry -MountPath (Join-Path $TestDrive 'Missing')
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Test-Path -Times 0 -Exactly -ParameterFilter {"$Path" -like 'HKLM:\*'}
    }
}

Describe 'Dismount-WimsPE' {
    BeforeEach {
        $MountWinPE = 'C:\Mount\WinPE'; $MountWinRE = 'C:\Mount\WinRE'; $MountWinSE = 'C:\Mount\WinSE'
        $OSMediaPath = 'C:\OSMedia\Build'
        Mock Start-Sleep {}
        Mock Dismount-WindowsImage {}
    }

    It 'saves and dismounts WinPE, WinRE and WinSE with a log for each' {
        Dismount-WimsPE -OSMediaPath $OSMediaPath 6>$null
        Should -Invoke Dismount-WindowsImage -Times 3 -Exactly -ParameterFilter {$Save}
        foreach ($Wim in 'WinPE', 'WinRE', 'WinSE') {
            Should -Invoke Dismount-WindowsImage -Times 1 -Exactly -ParameterFilter {
                ($Path -eq "C:\Mount\$Wim") -and ($LogPath -like "C:\OSMedia\Build\WinPE\info\logs\*-Dismount-WimsPE-$Wim.log")
            }
        }
        Should -Invoke Start-Sleep -Times 0 -Exactly -ParameterFilter {$Seconds -eq 30}
    }

    It 'waits 30 seconds and dismounts again when a dismount fails' {
        $script:Failed = @{}
        Mock Dismount-WindowsImage {if (-not $script:Failed["$Path"]) {$script:Failed["$Path"] = $true; throw 'busy'}}
        $Warnings = (Dismount-WimsPE -OSMediaPath $OSMediaPath 6>$null 3>&1) -join "`n"
        foreach ($Wim in 'WinPE', 'WinRE', 'WinSE') {
            $Warnings | Should -BeLike "*Could not dismount $Wim ... Waiting 30 seconds*"
            Should -Invoke Dismount-WindowsImage -Times 2 -Exactly -ParameterFilter {$Path -eq "C:\Mount\$Wim"}
        }
        Should -Invoke Start-Sleep -Times 3 -Exactly -ParameterFilter {$Seconds -eq 30}
    }
}

Describe 'Enable-NetFXOS' {
    #The main behavior is tested in OSServicing.Tests.ps1
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $EnableNetFX3 = 'True'; $OSMajorVersion = 10
        $UpdateOS = 'Windows 10'; $ReleaseId = '22H2'; $OSInstallationType = 'Client'
        $MountDirectory = 'C:\Mount'; $Info = $TestDrive
        $OS = Join-Path $TestDrive 'OS10'
        $GetOSDBuilderPathContentIsoExtract = Join-Path $TestDrive 'Missing'
        Mock Get-WindowsOptionalFeature {[PSCustomObject]@{FeatureName = 'NetFx3'; State = 'DisabledWithPayloadRemoved'}}
        Mock Add-WindowsCapability {}
        Mock Update-DotNetOS {}
    }

    It 'warns without the Windows 11 download command on Windows 10 when there is no source' {
        $Warnings = (Enable-NetFXOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*sources\sxs does not exist*'
        $Warnings | Should -Not -BeLike '*Save-OSDBuilderDownload*'
        Should -Invoke Add-WindowsCapability -Times 0 -Exactly
    }

    It 'does nothing for <Case>' -ForEach @(
        @{Case = 'Update-OSMedia'; Variable = 'ScriptName'; Value = 'Update-OSMedia'}
        @{Case = 'an Operating System other than 10'; Variable = 'OSMajorVersion'; Value = 6}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Enable-NetFXOS 6>$null
        Should -Invoke Get-WindowsOptionalFeature -Times 0 -Exactly
    }
}

Describe 'Enable-WindowsOptionalFeatureOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $MountDirectory = 'C:\Mount'; $Info = 'C:\Build\info'
        $EnableFeature = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')
        Mock Enable-WindowsOptionalFeature {}
        Mock Update-CumulativeOS {}
        Mock Invoke-DismCleanupImage {}
    }

    It 'enables every feature with -All, reapplies the LCU and cleans up the image' {
        Enable-WindowsOptionalFeatureOS 6>$null
        Should -Invoke Enable-WindowsOptionalFeature -Times 2 -Exactly -ParameterFilter {$All -and ($Path -eq 'C:\Mount')}
        Should -Invoke Enable-WindowsOptionalFeature -Times 1 -Exactly -ParameterFilter {
            ($FeatureName -eq 'Microsoft-Windows-Subsystem-Linux') -and ($LogPath -like 'C:\Build\info\logs\*-Enable-WindowsOptionalFeatureOS.log')
        }
        Should -Invoke Enable-WindowsOptionalFeature -Times 1 -Exactly -ParameterFilter {$FeatureName -eq 'VirtualMachinePlatform'}
        Should -Invoke Update-CumulativeOS -Times 1 -Exactly -ParameterFilter {$Force}
        Should -Invoke Invoke-DismCleanupImage -Times 1 -Exactly
    }

    It 'warns and continues when a feature cannot be enabled' {
        Mock Enable-WindowsOptionalFeature {throw '0x800f080c Feature name is unknown'} -ParameterFilter {$FeatureName -eq 'Microsoft-Windows-Subsystem-Linux'}
        $Warnings = (Enable-WindowsOptionalFeatureOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*0x800f080c Feature name is unknown*'
        Should -Invoke Enable-WindowsOptionalFeature -Times 1 -Exactly -ParameterFilter {$FeatureName -eq 'VirtualMachinePlatform'}
        Should -Invoke Update-CumulativeOS -Times 1 -Exactly
    }

    It 'does nothing for <Case>' -ForEach @(
        @{Case = 'Update-OSMedia'; Variable = 'ScriptName'; Value = 'Update-OSMedia'}
        @{Case = 'a Task without features'; Variable = 'EnableFeature'; Value = ''}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Enable-WindowsOptionalFeatureOS 6>$null
        Should -Invoke Enable-WindowsOptionalFeature -Times 0 -Exactly
        Should -Invoke Update-CumulativeOS -Times 0 -Exactly
        Should -Invoke Invoke-DismCleanupImage -Times 0 -Exactly
    }
}

Describe 'Enable-WinREWiFi' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $WinREWiFi = $true; $OSArchitecture = 'x64'; $MountWinRE = 'C:\Mount\WinRE'
        $DriverCab = New-TestFile -Path (Join-Path (Join-Path $TestDrive 'Downloads') 'WiFi-23.110.0-Driver64-Win10-Win11.cab')
        Mock Get-OSDCatalogIntelWirelessDriver {
            [PSCustomObject]@{OSVersion = '6.3'; OSArch = 'x64'; DriverUrl = 'https://downloadmirror.intel.com/win81-x64.zip'}
            [PSCustomObject]@{OSVersion = '10.0'; OSArch = 'x86'; DriverUrl = 'https://downloadmirror.intel.com/win10-x86.zip'}
            [PSCustomObject]@{OSVersion = '10.0'; OSArch = 'x64'; DriverUrl = 'https://downloadmirror.intel.com/win10-x64.zip'}
            [PSCustomObject]@{OSVersion = '10.0'; OSArch = 'x64'; DriverUrl = 'https://downloadmirror.intel.com/win10-x64-old.zip'}
        }
        Mock Test-WebConnection {$true}
        Mock Save-WebFile {$DriverCab}
        Mock Expand-Archive {}
        Mock Add-WindowsDriver {}
    }

    It 'expands the first Windows 10 x64 Intel Wireless driver and adds it to WinRE' {
        $ExpandPath = Join-Path $DriverCab.Directory $DriverCab.BaseName
        Enable-WinREWiFi 6>$null 4>$null
        Should -Invoke Save-WebFile -Times 1 -Exactly -ParameterFilter {$SourceUrl -eq 'https://downloadmirror.intel.com/win10-x64.zip'}
        Should -Invoke Expand-Archive -Times 1 -Exactly -ParameterFilter {("$Path" -like "*$($DriverCab.Name)") -and ($DestinationPath -eq $ExpandPath) -and $Force}
        Should -Invoke Add-WindowsDriver -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount\WinRE') -and ($Driver -eq $ExpandPath) -and $Recurse -and $ForceUnsigned}
    }

    It 'uses the x86 driver for an x86 Operating System' {
        $OSArchitecture = 'x86'
        Enable-WinREWiFi 6>$null 4>$null
        Should -Invoke Test-WebConnection -Times 1 -Exactly -ParameterFilter {$Uri -eq 'https://downloadmirror.intel.com/win10-x86.zip'}
        Should -Invoke Save-WebFile -Times 1 -Exactly -ParameterFilter {$SourceUrl -eq 'https://downloadmirror.intel.com/win10-x86.zip'}
    }

    It 'works for New-OSDCloudOSMedia' {
        $ScriptName = 'New-OSDCloudOSMedia'
        Enable-WinREWiFi 6>$null 4>$null
        Should -Invoke Add-WindowsDriver -Times 1 -Exactly
    }

    It 'does not add a driver when the download failed' {
        Mock Save-WebFile {[PSCustomObject]@{FullName = (Join-Path $TestDrive 'Missing.cab')}}
        Enable-WinREWiFi 6>$null 4>$null
        Should -Invoke Expand-Archive -Times 0 -Exactly
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
    }

    It 'warns when the driver cannot be downloaded' {
        Mock Test-WebConnection {$false}
        $Warnings = (Enable-WinREWiFi 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Unable to connect to https://downloadmirror.intel.com/win10-x64.zip*'
        Should -Invoke Save-WebFile -Times 0 -Exactly
    }

    It 'does nothing for <Case>' -ForEach @(
        @{Case = 'New-PEBuild'; Variable = 'ScriptName'; Value = 'New-PEBuild'}
        @{Case = 'a Task without WinREWiFi'; Variable = 'WinREWiFi'; Value = $false}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Enable-WinREWiFi 6>$null
        Should -Invoke Get-OSDCatalogIntelWirelessDriver -Times 0 -Exactly
    }
}

Describe 'Enable-WinPEOSDCloud' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $WinPEOSDCloud = $true
        $MountWinPE = 'C:\Mount\WinPE'; $MountWinRE = 'C:\Mount\WinRE'; $MountWinSE = 'C:\Mount\WinSE'; $MountDirectory = 'C:\Mount\PEBuild'
        $script:Temp = $env:TEMP
        $env:TEMP = Join-Path $TestDrive 'Temp'
        New-Item -Path $env:TEMP -ItemType Directory -Force | Out-Null
        Mock Set-WindowsImageExecutionPolicy {}
        Mock Enable-PEWindowsImagePSGallery {}
        Mock Start-Process {}
        Mock Save-Module {}
    }

    AfterEach {
        $env:TEMP = $script:Temp
    }

    It 'sets the ExecutionPolicy to Bypass and enables the PowerShell Gallery in WinPE, WinRE and WinSE' {
        Enable-WinPEOSDCloud 6>$null
        foreach ($MountPath in $MountWinPE, $MountWinRE, $MountWinSE) {
            Should -Invoke Set-WindowsImageExecutionPolicy -Times 1 -Exactly -ParameterFilter {($Path -eq $MountPath) -and ($ExecutionPolicy -eq 'Bypass')}
            Should -Invoke Enable-PEWindowsImagePSGallery -Times 1 -Exactly -ParameterFilter {$Path -eq $MountPath}
        }
    }

    It 'imports the console settings into the DEFAULT hive of every image' {
        Enable-WinPEOSDCloud 6>$null
        $RegFile = Join-Path $env:TEMP 'RegistryConsole.reg'
        $RegFile | Should -Exist
        $RegContent = Get-Content -Path $RegFile -Raw
        $RegContent.StartsWith('Windows Registry Editor Version 5.00') | Should -BeTrue
        $RegContent.Contains('[HKEY_LOCAL_MACHINE\Default\Console\%SystemRoot%_System32_WindowsPowerShell_v1.0_powershell.exe]') | Should -BeTrue
        $RegContent.Contains('"FaceName"="Consolas"') | Should -BeTrue
        Should -Invoke Start-Process -Times 9 -Exactly -ParameterFilter {($FilePath -eq 'reg') -and $Wait}
        foreach ($MountPath in $MountWinPE, $MountWinRE, $MountWinSE) {
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {"$ArgumentList" -eq "load HKLM\Default $MountPath\Windows\System32\Config\DEFAULT"}
        }
        Should -Invoke Start-Process -Times 3 -Exactly -ParameterFilter {"$ArgumentList" -eq "import $env:TEMP\RegistryConsole.reg"}
        Should -Invoke Start-Process -Times 3 -Exactly -ParameterFilter {"$ArgumentList" -eq 'unload HKLM\Default'}
    }

    It 'saves the OSD module to WinPE, WinRE and WinSE' {
        Enable-WinPEOSDCloud 6>$null
        Should -Invoke Save-Module -Times 3 -Exactly -ParameterFilter {($Name -eq 'OSD') -and $Force}
        foreach ($MountPath in $MountWinPE, $MountWinRE, $MountWinSE) {
            Should -Invoke Save-Module -Times 1 -Exactly -ParameterFilter {$Path -eq "$MountPath\Program Files\WindowsPowerShell\Modules"}
        }
    }

    It 'saves the OSD module to the mounted image of New-PEBuild' {
        $ScriptName = 'New-PEBuild'
        Enable-WinPEOSDCloud 6>$null
        Should -Invoke Save-Module -Times 1 -Exactly
        Should -Invoke Save-Module -Times 1 -Exactly -ParameterFilter {$Path -eq 'C:\Mount\PEBuild\Program Files\WindowsPowerShell\Modules'}
    }

    It 'saves the OSD module to WinPE, WinRE and WinSE for New-OSDCloudOSMedia' {
        $ScriptName = 'New-OSDCloudOSMedia'
        Enable-WinPEOSDCloud 6>$null
        Should -Invoke Save-Module -Times 3 -Exactly
    }

    It 'does nothing for <Case>' -ForEach @(
        @{Case = 'Update-OSMedia'; Variable = 'ScriptName'; Value = 'Update-OSMedia'}
        @{Case = 'a Task without WinPEOSDCloud'; Variable = 'WinPEOSDCloud'; Value = $false}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Enable-WinPEOSDCloud 6>$null
        Should -Invoke Set-WindowsImageExecutionPolicy -Times 0 -Exactly
        Should -Invoke Save-Module -Times 0 -Exactly
    }
}

Describe 'Expand-DaRTPE' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'
        $Root = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $SetOSDBuilderPathContent = Join-Path $Root 'Content'
        $WinPEDaRT = 'DaRT\DaRT 10\Toolsx64.cab'
        $DaRTPath = Join-Path (Join-Path $SetOSDBuilderPathContent 'DaRT') 'DaRT 10'
        New-TestFile -Path (Join-Path $DaRTPath 'Toolsx64.cab') | Out-Null
        $MountWinPE = Join-Path $Root 'WinPE'; $MountWinRE = Join-Path $Root 'WinRE'; $MountWinSE = Join-Path $Root 'WinSE'
        $MountDirectory = Join-Path $Root 'PEBuild'
        foreach ($MountPath in $MountWinPE, $MountWinRE, $MountWinSE, $MountDirectory) {
            New-TestFile -Path (Join-Path (Join-Path (Join-Path $MountPath 'Windows') 'System32') 'winpeshl.ini') -Value "[LaunchApps]`r`n%SYSTEMDRIVE%\sources\recovery\recenv.exe, -prompt" | Out-Null
        }
        function Get-DartConfig ($MountPath) {Join-Path (Join-Path (Join-Path $MountPath 'Windows') 'System32') 'DartConfig.dat'}
        function Get-Winpeshl ($MountPath) {Join-Path (Join-Path (Join-Path $MountPath 'Windows') 'System32') 'winpeshl.ini'}
        Mock expand.exe {}
    }

    It 'expands the DaRT cab into WinPE, WinRE and WinSE' {
        Expand-DaRTPE 6>$null
        Should -Invoke expand.exe -Times 3 -Exactly
        foreach ($MountPath in $MountWinPE, $MountWinRE, $MountWinSE) {
            Should -Invoke expand.exe -Times 1 -Exactly -ParameterFilter {($InputObject -eq "$SetOSDBuilderPathContent\$WinPEDaRT") -and ($RemainingArguments[-1] -eq $MountPath)}
        }
    }

    It 'expands only into the mounted images' {
        $MountWinSE = $null
        Expand-DaRTPE 6>$null
        Should -Invoke expand.exe -Times 2 -Exactly
    }

    It 'copies <Config> as DartConfig.dat to every image' -ForEach @(
        @{Config = 'DartConfig.dat'}
        @{Config = 'DartConfig8.dat'}
    ) {
        New-TestFile -Path (Join-Path $DaRTPath $Config) -Value $Config | Out-Null
        Expand-DaRTPE 6>$null
        foreach ($MountPath in $MountWinPE, $MountWinRE, $MountWinSE) {
            Get-DartConfig $MountPath | Should -FileContentMatchExactly $Config
        }
    }

    It 'copies DartConfig.dat to WinRE when there is no WinSE' {
        New-TestFile -Path (Join-Path $DaRTPath 'DartConfig.dat') | Out-Null
        $MountWinSE = $null
        Expand-DaRTPE 6>$null
        Get-DartConfig $MountWinRE | Should -Exist
    }

    It 'removes winpeshl.ini from WinPE and WinSE and starts DaRT with the network in WinRE for New-OSBuild' {
        Expand-DaRTPE 6>$null
        Get-Winpeshl $MountWinPE | Should -Not -Exist
        Get-Winpeshl $MountWinSE | Should -Not -Exist
        Get-Winpeshl $MountWinRE | Should -FileContentMatch 'recenv.exe, -network'
        Get-Winpeshl $MountWinRE | Should -Not -FileContentMatch '-prompt'
        Get-Winpeshl $MountDirectory | Should -FileContentMatch '-prompt'
    }

    It 'starts DaRT with the network in a Recovery PEBuild' {
        $ScriptName = 'New-PEBuild'; $WinPEOutput = 'Recovery'
        $MountWinPE = $null; $MountWinRE = $null; $MountWinSE = $null
        Expand-DaRTPE 6>$null
        Get-Winpeshl $MountDirectory | Should -FileContentMatch 'recenv.exe, -network'
    }

    It 'removes winpeshl.ini from a WinPE PEBuild' {
        $ScriptName = 'New-PEBuild'; $WinPEOutput = 'WinPE'
        Expand-DaRTPE 6>$null
        Get-Winpeshl $MountDirectory | Should -Not -Exist
        Get-Winpeshl $MountWinRE | Should -FileContentMatch '-prompt'
    }

    It 'warns when the DaRT cab does not exist' {
        $WinPEDaRT = 'DaRT\Missing.cab'
        $Warnings = (Expand-DaRTPE 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Microsoft DaRT do not exist in*Missing.cab*'
        Should -Invoke expand.exe -Times 0 -Exactly
    }

    It 'does nothing for <Case>' -ForEach @(
        @{Case = 'Update-OSMedia'; Variable = 'ScriptName'; Value = 'Update-OSMedia'}
        @{Case = 'a Task without DaRT'; Variable = 'WinPEDaRT'; Value = ''}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Expand-DaRTPE 6>$null
        Should -Invoke expand.exe -Times 0 -Exactly
        Get-Winpeshl $MountWinPE | Should -Exist
    }
}

Describe 'Export-InstallwimOS' {
    It 'exports index 1 of the temporary install.wim to the OS sources' {
        $OS = 'C:\Build\OS'; $WimTemp = 'C:\Build\WimTemp'; $Info = 'C:\Build\info'
        Mock Export-WindowsImage {}
        Export-InstallwimOS 6>$null
        Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($SourceImagePath -eq 'C:\Build\WimTemp\install.wim') -and ($SourceIndex -eq 1) -and
            ($DestinationImagePath -eq 'C:\Build\OS\sources\install.wim') -and ($LogPath -like 'C:\Build\info\logs\*-Export-WindowsImage.log')
        }
    }
}

Describe 'Export-PEBootWim' {
    It 'rebuilds boot.wim from WinPE and a bootable WinSE and copies it to the OS sources' {
        $OSMediaPath = Join-Path $TestDrive 'Build'
        New-Item -Path (Join-Path (Join-Path $OSMediaPath 'OS') 'sources') -ItemType Directory -Force | Out-Null
        $BootWim = New-TestFile -Path (Join-Path (Join-Path $OSMediaPath 'WinPE') 'boot.wim') -Value 'new boot.wim'
        Mock Export-WindowsImage {}
        Export-PEBootWim -OSMediaPath $OSMediaPath 6>$null
        Should -Invoke Export-WindowsImage -Times 2 -Exactly -ParameterFilter {($DestinationImagePath -eq "$OSMediaPath\WinPE\boot.wim") -and ($SourceIndex -eq 1)}
        Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($SourceImagePath -eq "$OSMediaPath\WimTemp\winpe.wim") -and -not $Setbootable -and ($LogPath -like '*-Export-WindowsImage-WinPE.log')
        }
        Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($SourceImagePath -eq "$OSMediaPath\WimTemp\winse.wim") -and $Setbootable -and ($LogPath -like '*-Export-WindowsImage-WinSE.log')
        }
        Join-Path (Join-Path (Join-Path $OSMediaPath 'OS') 'sources') 'boot.wim' | Should -FileContentMatchExactly 'new boot.wim'
    }
}

Describe 'Export-PEWims' {
    It 'exports WinPE, WinRE and WinSE from WimTemp to the WinPE directory' {
        $OSMediaPath = 'C:\Build'
        Mock Export-WindowsImage {}
        Export-PEWims -OSMediaPath $OSMediaPath 6>$null
        Should -Invoke Export-WindowsImage -Times 3 -Exactly -ParameterFilter {$SourceIndex -eq 1}
        foreach ($Wim in 'WinPE', 'WinRE', 'WinSE') {
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
                ($SourceImagePath -eq "C:\Build\WimTemp\$($Wim.ToLower()).wim") -and ($DestinationImagePath -eq "C:\Build\WinPE\$($Wim.ToLower()).wim") -and
                ($LogPath -like "C:\Build\WinPE\info\logs\*-Export-WindowsImage-$Wim.log")
            }
        }
    }
}

Describe 'Export-SessionsXmlOS' {
    BeforeAll {
        $OSMediaPath = Join-Path $TestDrive 'OSMedia'
        foreach ($Directory in 'logs', 'xml', 'json') {New-Item -Path (Join-Path (Join-Path $OSMediaPath 'info') $Directory) -ItemType Directory -Force | Out-Null}
        Copy-Item -Path (Join-Path (Join-Path (Join-Path $PSScriptRoot 'Fixtures') 'AllFunctionsCDEG') 'Sessions.xml') -Destination (Join-Path $OSMediaPath 'Sessions.xml')
        Export-SessionsXmlOS -OSMediaPath $OSMediaPath
        $InfoPath = Join-Path $OSMediaPath 'info'
    }

    It 'moves Sessions.xml to the info directory' {
        Join-Path $OSMediaPath 'Sessions.xml' | Should -Not -Exist
        Join-Path $InfoPath 'Sessions.xml' | Should -Exist
    }

    It 'exports the package sessions newest first to xml, json and txt' {
        $Sessions = @(Import-Clixml -Path (Join-Path (Join-Path $InfoPath 'xml') 'Sessions.xml'))
        $Sessions.Count | Should -Be 2
        $Sessions[0].KBNumber | Should -Be 'KB5066835'
        $Sessions[0].Id | Should -Be 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.6899.1.11'
        $Sessions[0].TargetState | Should -Be 'Installed'
        $Sessions[0].Client | Should -Be 'DISM Package Manager Provider'
        $Sessions[0].Status | Should -Be '0x0'
        $Sessions[1].KBNumber | Should -Be 'KB5065381'
        $Json = Get-Content -Path (Join-Path (Join-Path $InfoPath 'json') 'Sessions.json') -Raw | ConvertFrom-Json
        @($Json).Count | Should -Be 2
        Join-Path $OSMediaPath 'Sessions.txt' | Should -FileContentMatch 'KB5066835'
        @(Get-ChildItem -Path (Join-Path $InfoPath 'logs') -Filter '*-Sessions.txt').Count | Should -Be 1
        @(Get-ChildItem -Path (Join-Path $InfoPath 'xml') -Filter '*-Sessions.xml').Count | Should -Be 1
        @(Get-ChildItem -Path (Join-Path $InfoPath 'json') -Filter '*-Sessions.json').Count | Should -Be 1
    }

    It 'skips sessions that are not packages' {
        $Sessions = @(Import-Clixml -Path (Join-Path (Join-Path $InfoPath 'xml') 'Sessions.xml'))
        $Sessions.Client | Should -Not -Contain 'DISM Manager Provider'
    }
}
