BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    $PublicPath = Join-Path $RepoRoot 'Public'
    foreach ($Name in 'Get-OSDBuilder', 'Get-OSMedia', 'New-OSDBuilderISO', 'New-OSDCloudOSMedia') {. (Join-Path $PublicPath "$Name.ps1")}

    #The build functions of the OSDCloud OSMedia, every one is mocked
    $BuildFunctions = @(
        'Show-MediaImageInfoOS', 'New-DirectoriesOSMedia', 'Show-WorkingInfoOS', 'Copy-MediaOperatingSystem',
        'Mount-WinPEwim', 'Mount-WinREwim', 'Mount-WinSEwim', 'Import-AutoExtraFilesPE', 'Enable-WinPEOSDCloud', 'Enable-WinREWiFi',
        'Save-PackageInventoryPE', 'Dismount-WimsPE', 'Export-PEWims', 'Export-PEBootWim', 'Save-InventoryPE', 'Mount-InstallwimOS',
        'Set-WinREWimOS', 'Show-ActionTime', 'Save-RegistryCurrentVersionOS', 'Add-ContentPack', 'Add-WindowsPackageOS', 'Add-FeaturesOnDemandOS',
        'Enable-WindowsOptionalFeatureOS', 'Enable-NetFXOS', 'Remove-AppxProvisionedPackageOS', 'Remove-WindowsPackageOS', 'Remove-WindowsCapabilityOS',
        'Disable-WindowsOptionalFeatureOS', 'Add-ContentDriversOS', 'Add-ContentExtraFilesOS', 'Add-ContentStartLayout', 'Add-ContentUnattend',
        'Add-ContentScriptsOS', 'Import-RegistryRegOS', 'Import-RegistryXmlOS', 'Save-AutoExtraFilesOS', 'Save-SessionsXmlOS', 'Save-InventoryOS',
        'Dismount-InstallwimOS', 'Export-InstallwimOS', 'Save-WindowsImageContentOS', 'Save-VariablesOSD'
    )
    #The DaRT and MDT files on drive C: are never used from the real system
    $DartCab = 'C:\Program Files\Microsoft DaRT\v10\Toolsx64.cab'
    $DartConfig = 'C:\Program Files\Microsoft Deployment Toolkit\Templates\DartConfig8.dat'
    $Now = [datetime]'2026-10-16 09:08:07'
    $Stamp = $Now.ToString('yyMMddhhmm')

    function New-TestOSImport {
        <#
        .SYNOPSIS
        Creates an OSImport with WindowsImage.txt, install.wim and info\xml\CurrentVersion.xml and returns the Get-OSMedia object
        #>
        param (
            [string]$Name = 'Windows 11 Enterprise x64 24H2 26100.1742',
            [hashtable]$CurrentVersion = @{CurrentBuild = '26100'; DisplayVersion = '24H2'; ReleaseId = '2009'},
            [switch]$NoCurrentVersion,
            [switch]$NoWindowsImageTxt,
            [switch]$NoInstallWim
        )
        $Path = Join-Path $SetOSDBuilderPathOSImport $Name
        New-Item -Path (Join-Path (Join-Path $Path 'info') 'xml') -ItemType Directory -Force | Out-Null
        if (-not $NoWindowsImageTxt) {New-TestFile -Path (Join-Path $Path 'WindowsImage.txt') | Out-Null}
        if (-not $NoInstallWim) {New-TestFile -Path (Join-Path (Join-Path (Join-Path $Path 'OS') 'sources') 'install.wim') | Out-Null}
        if (-not $NoCurrentVersion) {[PSCustomObject]$CurrentVersion | Export-Clixml -Path (Join-Path (Join-Path (Join-Path $Path 'info') 'xml') 'CurrentVersion.xml')}
        [PSCustomObject]@{Name = $Name; FullName = $Path; MediaType = 'OSImport'; RegBuild = 26100}
    }

    function Invoke-OSDCloudOSMedia {
        #New-OSDCloudOSMedia stops with Break, the loop contains it, returns the warnings
        param ([hashtable]$Parameters = @{})
        foreach ($Run in 1) {New-OSDCloudOSMedia @Parameters 6>$null 4>$null 3>&1}
    }
}

AfterAll {
    Remove-Variable -Name 'ReapplyLCU' -Scope Global -ErrorAction SilentlyContinue
}

Describe 'New-OSDCloudOSMedia' {
    BeforeEach {
        $Root = Join-Path $TestDrive ([guid]::NewGuid())
        $SetOSDBuilderPathOSImport = Join-Path $Root 'OSImport'
        $SetOSDBuilderPathOSMedia = Join-Path $Root 'OSMedia'
        $SetOSDBuilderPathMount = Join-Path $Root 'Mount'
        $GetOSDBuilderPathContentOneDrive = Join-Path (Join-Path $Root 'Content') 'OneDrive'
        $ExpectedWorkingPath = "$SetOSDBuilderPathOSMedia\Windows 11 Enterprise x64 24H2 26100.1742 OSDCloud"
        $ExpectedMountOS = Join-Path $SetOSDBuilderPathMount "os$Stamp"
        $ExpectedMountPE = Join-Path $SetOSDBuilderPathMount "winpe$Stamp"
        $ExpectedMountRE = Join-Path $SetOSDBuilderPathMount "winre$Stamp"
        $ExpectedMountSE = Join-Path $SetOSDBuilderPathMount "setup$Stamp"

        #WinPE optional components of the ADK
        $ExpectedWinPEOCs = Join-Path $Root 'WinPE_OCs'
        foreach ($File in 'WinPE-WMI.cab', 'WinPE-PowerShell.cab', 'en-us\lp.cab', 'en-us\WinPE-WMI_en-us.cab') {
            New-TestFile -Path (Join-Path $ExpectedWinPEOCs $File) | Out-Null
        }
        #The mounted boot images
        foreach ($Mount in $ExpectedMountPE, $ExpectedMountRE, $ExpectedMountSE) {
            New-TestFile -Path (Join-Path $Mount 'Windows\System32\winpeshl.ini') -Value "[LaunchApps]`r`n%SYSTEMDRIVE%\sources\recovery\recenv.exe -prompt" | Out-Null
        }
        New-Item -Path $ExpectedMountOS -ItemType Directory -Force | Out-Null

        $OSImport = New-TestOSImport
        $Image = @{
            ImageName = 'Windows 11 Enterprise'; ImageDescription = 'Windows 11 Enterprise'; Architecture = 9; EditionId = 'Enterprise'
            InstallationType = 'Client'; Languages = @('en-US'); Version = '10.0.26100.1742'; MajorVersion = 10; MinorVersion = 0
            Build = 26100; SPBuild = 1742; SPLevel = 0; ImageBootable = $false; WIMBoot = $false
        }

        Mock Get-OSDBuilder {}
        foreach ($Name in 'Block-WinPE', 'Block-StandardUser', 'Block-WindowsVersionNe10', 'Block-PowerShellVersionLt5', 'Block-NoCurl') {Mock $Name {}}
        foreach ($Name in $BuildFunctions) {Mock $Name {}}
        Mock New-DirectoriesOSMedia {
            foreach ($Directory in 'xml', 'json', 'logs') {New-Item -Path (Join-Path $Info $Directory) -ItemType Directory -Force | Out-Null}
        }
        #Captures the boot images before New-OSDCloudOSMedia removes the mount directories
        $Captured = @{}
        Mock Import-AutoExtraFilesPE {
            $Captured.WinPEIni = Test-Path (Join-Path $ExpectedMountPE 'Windows\System32\winpeshl.ini')
            $Captured.WinSEIni = Test-Path (Join-Path $ExpectedMountSE 'Windows\System32\winpeshl.ini')
            $Captured.WinREIni = Get-Content -Path (Join-Path $ExpectedMountRE 'Windows\System32\winpeshl.ini')
        }
        Mock Get-Date {$Now}
        Mock Get-OSMedia {$OSImport}
        Mock Out-GridView {$InputObject | Where-Object {$_}}
        Mock Get-WindowsImage {[PSCustomObject]$Image}
        Mock Get-AdkPaths {[PSCustomObject]@{WinPEOCs = $ExpectedWinPEOCs}}
        Mock Get-RegCurrentVersion {[PSCustomObject]@{CurrentBuild = '26100'; UBR = '2033'; DisplayVersion = '24H2'; ReleaseId = '2009'}}
        Mock Add-WindowsPackage {}
        Mock Save-WindowsImage {}
        Mock expand.exe {}
        Mock robocopy {}
        Mock Read-Host {}
        Mock Start-Transcript {}
        Mock Stop-Transcript {}
        Mock New-OSDBuilderISO {}
        Mock Test-Path {$false} -ParameterFilter {$Path -like 'C:\Program Files\*'}
    }

    It 'builds the OSDCloud OSMedia of the selected OSImport' {
        $Warnings = (Invoke-OSDCloudOSMedia) -join "`n"
        $Warnings | Should -Not -BeLike '*Exiting*'

        Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
        foreach ($Name in 'Block-WinPE', 'Block-StandardUser', 'Block-WindowsVersionNe10', 'Block-PowerShellVersionLt5', 'Block-NoCurl') {
            Should -Invoke $Name -Times 1 -Exactly
        }
        Should -Invoke Get-OSMedia -Times 1 -Exactly -ParameterFilter {$OSMajorVersion -eq 10}
        Should -Invoke Out-GridView -Times 1 -Exactly -ParameterFilter {$PassThru -and ($InputObject.Name -eq $OSImport.Name)}
        Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq "$($OSImport.FullName)\OS\sources\install.wim") -and ($Index -eq 1)}
        Should -Invoke Get-AdkPaths -Times 1 -Exactly -ParameterFilter {$Arch -eq 'amd64'}
        Should -Invoke Start-Transcript -Times 1 -Exactly -ParameterFilter {$Path -like "$ExpectedWorkingPath\info\logs*New-OSDCloudOSMedia.log"}

        #The boot images are mounted from the new OSMedia
        foreach ($Name in 'Mount-WinPEwim', 'Mount-WinREwim', 'Mount-WinSEwim', 'Save-PackageInventoryPE', 'Dismount-WimsPE', 'Export-PEWims', 'Export-PEBootWim', 'Save-InventoryPE', 'Save-AutoExtraFilesOS', 'Save-SessionsXmlOS', 'Save-InventoryOS') {
            Should -Invoke $Name -Times 1 -Exactly -ParameterFilter {$OSMediaPath -eq $ExpectedWorkingPath}
        }
        foreach ($Name in 'Copy-MediaOperatingSystem', 'Mount-InstallwimOS', 'Set-WinREWimOS', 'Enable-WinPEOSDCloud', 'Enable-WinREWiFi', 'Dismount-InstallwimOS', 'Export-InstallwimOS', 'Save-WindowsImageContentOS', 'Save-VariablesOSD') {
            Should -Invoke $Name -Times 1 -Exactly
        }
        foreach ($PackType in 'OSCapability', 'OSPackages', 'OSDrivers', 'OSExtraFiles', 'OSPoshMods', 'OSRegistry', 'OSScripts', 'OSStartLayout') {
            Should -Invoke Add-ContentPack -Times 1 -Exactly -ParameterFilter {$PackType -eq $PackType}
        }
        Should -Invoke Get-RegCurrentVersion -Times 2 -Exactly -ParameterFilter {$Path -eq $ExpectedMountOS}
        Should -Invoke Read-Host -Times 0 -Exactly
        Should -Invoke New-OSDBuilderISO -Times 1 -Exactly -ParameterFilter {$FullName -eq $ExpectedWorkingPath}
        Should -Invoke Stop-Transcript -Times 1 -Exactly
        $global:ReapplyLCU | Should -BeFalse
    }

    It 'adds the ADK packages with the en-us language packs to WinPE, WinRE and WinSE' {
        Invoke-OSDCloudOSMedia | Out-Null
        foreach ($Mount in $ExpectedMountPE, $ExpectedMountRE, $ExpectedMountSE) {
            foreach ($File in 'WinPE-WMI.cab', 'WinPE-PowerShell.cab', 'lp.cab', 'WinPE-WMI_en-us.cab') {
                Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {($Path -eq $Mount) -and ($PackagePath -like "*$File") -and ($LogPath -like "$ExpectedWorkingPath\info\logs\*")}
            }
            Should -Invoke Save-WindowsImage -Times 1 -Exactly -ParameterFilter {$Path -eq $Mount}
        }
        #Packages that are not in the ADK are skipped
        Should -Invoke Add-WindowsPackage -Times 12 -Exactly
    }

    It 'continues when an ADK package cannot be added' {
        Mock Add-WindowsPackage {throw 'The package is not applicable'}
        Invoke-OSDCloudOSMedia | Out-Null
        Should -Invoke Add-WindowsPackage -Times 12 -Exactly
        Should -Invoke Save-WindowsImage -Times 3 -Exactly
        Should -Invoke New-OSDBuilderISO -Times 1 -Exactly
    }

    It 'warns when the en-us language pack of the ADK is missing' {
        Remove-Item -Path (Join-Path (Join-Path $ExpectedWinPEOCs 'en-us') 'lp.cab')
        $Warnings = (Invoke-OSDCloudOSMedia) -join "`n"
        $Warnings | Should -BeLike '*Could not find*lp.cab*'
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly -ParameterFilter {$PackagePath -like '*lp.cab'}
    }

    It 'removes winpeshl.ini of WinPE and WinSE and starts WinRE with -network' {
        Invoke-OSDCloudOSMedia | Out-Null
        $Captured.WinPEIni | Should -BeFalse
        $Captured.WinSEIni | Should -BeFalse
        ($Captured.WinREIni -join "`n") | Should -BeLike '*recenv.exe -network*'
        ($Captured.WinREIni -join "`n") | Should -Not -BeLike '*-prompt*'
    }

    It 'warns when DaRT is not installed' {
        $Warnings = (Invoke-OSDCloudOSMedia) -join "`n"
        $Warnings | Should -BeLike "*Could not find $DartCab*"
        Should -Invoke expand.exe -Times 0 -Exactly
    }

    It 'expands DaRT to WinPE, WinRE and WinSE and copies DartConfig.dat' {
        Mock Test-Path {$true} -ParameterFilter {($Path -eq $DartCab) -or ($Path -eq $DartConfig)}
        Mock Copy-Item {} -ParameterFilter {$Path -eq $DartConfig}
        Invoke-OSDCloudOSMedia | Out-Null
        foreach ($Mount in $ExpectedMountPE, $ExpectedMountRE, $ExpectedMountSE) {
            Should -Invoke expand.exe -Times 1 -Exactly -ParameterFilter {((@($InputObject) + @($RemainingArguments)) -join '|') -eq "$DartCab|-F:*.*|$Mount"}
            Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter {$Destination -eq "$Mount\Windows\System32\DartConfig.dat"}
        }
    }

    It 'warns when DartConfig8.dat of MDT is missing' {
        Mock Test-Path {$true} -ParameterFilter {$Path -eq $DartCab}
        $Warnings = (Invoke-OSDCloudOSMedia) -join "`n"
        $Warnings | Should -BeLike "*Could not find $DartConfig*"
        Should -Invoke expand.exe -Times 3 -Exactly
    }

    It 'exports the configuration of the new install.wim with the UBR of the registry' {
        Invoke-OSDCloudOSMedia | Out-Null
        Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq "$ExpectedWorkingPath\OS\sources\install.wim") -and ($Index -eq 1)}
        $Info = Join-Path $ExpectedWorkingPath 'info'
        (Import-Clixml -Path (Join-Path (Join-Path $Info 'xml') 'Get-WindowsImage.xml')).UBR | Should -Be '26100.2033'
        (Get-Content -Path (Join-Path (Join-Path $Info 'json') 'Get-WindowsImage.json') -Raw | ConvertFrom-Json).UBR | Should -Be '26100.2033'
        $WindowsImageTxt = Get-Content -Path (Join-Path $ExpectedWorkingPath 'WindowsImage.txt')
        ($WindowsImageTxt -join "`n") | Should -Match 'UBR\s*:\s*26100\.2033'
        $WindowsImageTxt | Where-Object {-not $_.Trim()} | Should -BeNullOrEmpty
    }

    It 'uses the build of the Windows image when the registry has no CurrentBuild and UBR' {
        Mock Get-RegCurrentVersion {[PSCustomObject]@{ReleaseId = '2009'}}
        Invoke-OSDCloudOSMedia | Out-Null
        (Import-Clixml -Path (Join-Path (Join-Path (Join-Path $ExpectedWorkingPath 'info') 'xml') 'Get-WindowsImage.xml')).UBR | Should -Be '1742.1742'
    }

    It 'uses Build.SPBuild of the Windows image as UBR of Windows 6.x' {
        $Image.Version = '6.3.9600.1'
        Invoke-OSDCloudOSMedia | Out-Null
        (Import-Clixml -Path (Join-Path (Join-Path (Join-Path $ExpectedWorkingPath 'info') 'xml') 'Get-WindowsImage.xml')).UBR | Should -Be '26100.1742'
    }

    It 'removes the mount directories and the WimTemp directory' {
        New-Item -Path (Join-Path $ExpectedWorkingPath 'WimTemp') -ItemType Directory -Force | Out-Null
        Mock Remove-Item {} -ParameterFilter {$Path -eq $ExpectedWorkingPath}
        Invoke-OSDCloudOSMedia | Out-Null
        foreach ($Mount in $ExpectedMountOS, $ExpectedMountPE, $ExpectedMountRE, $ExpectedMountSE) {$Mount | Should -Not -Exist}
        Join-Path $ExpectedWorkingPath 'WimTemp' | Should -Not -Exist
    }

    It 'replaces an existing OSDCloud OSMedia' {
        $Old = New-TestFile -Path (Join-Path $ExpectedWorkingPath 'old.txt')
        $Warnings = (Invoke-OSDCloudOSMedia) -join "`n"
        $Warnings | Should -BeLike "*$ExpectedWorkingPath will be replaced!*"
        $Old.FullName | Should -Not -Exist
    }

    It 'keeps the name of an OSImport that contains OSDCloud' {
        $OSImport = New-TestOSImport -Name 'Windows 11 OSDCloud x64'
        Invoke-OSDCloudOSMedia | Out-Null
        Should -Invoke New-OSDBuilderISO -Times 1 -Exactly -ParameterFilter {$FullName -eq "$SetOSDBuilderPathOSMedia\Windows 11 OSDCloud x64"}
    }

    It 'pauses before WinPE and the install.wim are dismounted with -PauseDismountPE and -PauseDismountOS' {
        Invoke-OSDCloudOSMedia -Parameters @{PauseDismountPE = $true; PauseDismountOS = $true} | Out-Null
        Should -Invoke Read-Host -Times 2 -Exactly -ParameterFilter {$Prompt -eq 'Press Enter to Continue'}
    }

    It 'only offers OSImports of Windows 10 2004 or newer' {
        $Old = [PSCustomObject]@{Name = 'Windows 10 1909'; MediaType = 'OSImport'; RegBuild = 18363}
        $Media = [PSCustomObject]@{Name = 'OSMedia'; MediaType = 'OSMedia'; RegBuild = 26100}
        Mock Get-OSMedia {$Old, $Media, $OSImport}
        Invoke-OSDCloudOSMedia | Out-Null
        Should -Invoke Out-GridView -Times 1 -Exactly
        Should -Invoke Out-GridView -Times 1 -Exactly -ParameterFilter {$InputObject.Name -eq $OSImport.Name}
    }

    It 'warns and stops when no OSImport is selected' {
        Mock Out-GridView {}
        $Warnings = (Invoke-OSDCloudOSMedia) -join "`n"
        $Warnings | Should -BeLike '*Could not find a matching OSImport*'
        Should -Invoke Get-WindowsImage -Times 0 -Exactly
    }

    It 'warns when the OSImport directory does not exist' {
        Remove-Item -Path $OSImport.FullName -Recurse -Force
        $Warnings = (Invoke-OSDCloudOSMedia) -join "`n"
        $Warnings | Should -BeLike '*Unable to find an OSMedia to use*'
        Should -Invoke Get-WindowsImage -Times 0 -Exactly
    }

    It 'warns when the OSImport has no WindowsImage.txt' {
        $OSImport = New-TestOSImport -Name 'NoWindowsImageTxt' -NoWindowsImageTxt
        $Warnings = (Invoke-OSDCloudOSMedia) -join "`n"
        $Warnings | Should -BeLike "*$SetOSDBuilderPathOSImport\NoWindowsImageTxt is not a valid OSMedia Directory*"
        Should -Invoke Get-WindowsImage -Times 0 -Exactly
    }

    It 'warns when the OSImport has no install.wim' {
        $OSImport = New-TestOSImport -Name 'NoInstallWim' -NoInstallWim
        $Warnings = (Invoke-OSDCloudOSMedia) -join "`n"
        $Warnings | Should -BeLike '*install.wim is not a valid Windows Image*'
        Should -Invoke Get-WindowsImage -Times 0 -Exactly
    }

    It 'warns and stops without the ADK' {
        Mock Get-AdkPaths {}
        $Warnings = (Invoke-OSDCloudOSMedia) -join "`n"
        $Warnings | Should -BeLike '*Could not get ADK going*'
        Should -Invoke New-DirectoriesOSMedia -Times 0 -Exactly
        Should -Invoke New-OSDBuilderISO -Times 0 -Exactly
    }

    It 'uses the x86 ADK for the architecture <Architecture>' -ForEach @(
        @{Architecture = 0}
        @{Architecture = 6}
        @{Architecture = 12}
    ) {
        $Image.Architecture = $Architecture
        Invoke-OSDCloudOSMedia | Out-Null
        Should -Invoke Get-AdkPaths -Times 1 -Exactly -ParameterFilter {$Arch -eq 'x86'}
    }

    Context 'OneDriveSetup' {
        BeforeEach {
            $OneDriveSetup = New-TestFile -Path (Join-Path $GetOSDBuilderPathContentOneDrive 'OneDriveSetup.exe')
        }

        It 'updates OneDriveSetup.exe in SysWOW64 of a x64 client' {
            Invoke-OSDCloudOSMedia | Out-Null
            Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {
                $Arguments = @($InputObject) + @($RemainingArguments)
                ($Arguments[0] -eq $GetOSDBuilderPathContentOneDrive) -and ($Arguments[1] -eq "$ExpectedMountOS\Windows\SysWOW64") -and ($Arguments[2] -eq 'OneDriveSetup.exe') -and
                ($Arguments[-1] -like "/Log+:$ExpectedWorkingPath\info\logs\*-Update-OneDriveSetup.log")
            }
        }

        It 'updates OneDriveSetup.exe in System32 of a x86 client' {
            $Image.Architecture = 0
            Invoke-OSDCloudOSMedia | Out-Null
            Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {(@($InputObject) + @($RemainingArguments))[1] -eq "$ExpectedMountOS\Windows\System32"}
        }

        It 'updates OneDriveSetup.exe that was not downloaded today' {
            $OneDriveSetup.LastWriteTime = [datetime]::Today.AddDays(-30)
            Invoke-OSDCloudOSMedia | Out-Null
            Should -Invoke robocopy -Times 1 -Exactly
        }

        It 'does not update OneDriveSetup.exe when it is not in the Content directory' {
            Remove-Item -Path $OneDriveSetup.FullName
            Invoke-OSDCloudOSMedia | Out-Null
            Should -Invoke robocopy -Times 0 -Exactly
        }

        It 'does not update OneDriveSetup.exe of Windows Server' {
            $Image.InstallationType = 'Server'
            Invoke-OSDCloudOSMedia | Out-Null
            Should -Invoke robocopy -Times 0 -Exactly
        }

        It 'does not update OneDriveSetup.exe of a x86 client without the Content file' {
            $Image.Architecture = 0
            Remove-Item -Path $OneDriveSetup.FullName
            Invoke-OSDCloudOSMedia | Out-Null
            Should -Invoke robocopy -Times 0 -Exactly
        }
    }

    Context 'ReleaseId without CurrentVersion.xml' {
        It 'builds Windows 10 of <ImageName>' -ForEach @(
            @{ImageName = 'Windows 10 Enterprise'}
            @{ImageName = 'Windows 11 Enterprise'}
        ) {
            $OSImport = New-TestOSImport -Name 'NoCurrentVersion' -NoCurrentVersion
            $Image.ImageName = $ImageName
            Invoke-OSDCloudOSMedia | Out-Null
            Should -Invoke New-OSDBuilderISO -Times 1 -Exactly -ParameterFilter {$FullName -eq "$SetOSDBuilderPathOSMedia\NoCurrentVersion OSDCloud"}
        }

        It 'builds the OSMedia of build <Build>' -ForEach @(
            @{Build = 7600}, @{Build = 7601}, @{Build = 9600}, @{Build = 10240}, @{Build = 14393}, @{Build = 15063}, @{Build = 16299}, @{Build = 17134}, @{Build = 17763}
        ) {
            $OSImport = New-TestOSImport -Name 'NoCurrentVersion' -NoCurrentVersion
            $Image.Build = $Build
            Invoke-OSDCloudOSMedia | Out-Null
            Should -Invoke New-OSDBuilderISO -Times 1 -Exactly
        }
    }
}
