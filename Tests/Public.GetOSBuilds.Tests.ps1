BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    . (Join-Path (Join-Path $RepoRoot 'Public') 'Get-OSDBuilder.ps1')
    . (Join-Path (Join-Path $RepoRoot 'Public') 'Get-OSBuilds.ps1')
    . (Join-Path (Join-Path $RepoRoot 'Public') 'Get-PEBuilds.ps1')
    . (Join-Path (Join-Path $FixturesPath 'GetOSMedia') 'New-OSMediaFixture.ps1')
}

Describe 'Get-OSBuilds' {
    BeforeEach {
        $Root = Join-Path $TestDrive ([guid]::NewGuid().Guid.Substring(0, 8))
        $SetOSDBuilderPathOSBuilds = Join-Path $Root 'OSBuilds'
        New-Item -Path $SetOSDBuilderPathOSBuilds -ItemType Directory -Force | Out-Null

        $script:OSDUpdates = @()
        Mock Get-OSDBuilder {}
        Mock Get-OSDUpdates {$script:OSDUpdates}
        Mock Out-GridView {$InputObject | Where-Object Name -like '*Old'}
    }

    It 'initializes OSDBuilder with -CreatePaths -HideDetails and reads the updates silently' {
        Get-OSBuilds | Should -BeNullOrEmpty
        Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
        Should -Invoke Get-OSDUpdates -Times 1 -Exactly -ParameterFilter {$Silent}
    }

    It 'returns the properties of Get-WindowsImage.xml and CurrentVersion.xml' {
        $Build = New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Win11 Enterprise x64 24H2 Build')

        $Result = @(Get-OSBuilds)

        $Result.Count | Should -Be 1
        $Result[0].MediaType | Should -Be 'OSBuild'
        $Result[0].Name | Should -Be 'Win11 Enterprise x64 24H2 Build'
        $Result[0].FullName | Should -Be $Build.FullName
        $Result[0].ImageName | Should -Be 'Windows 11 Enterprise'
        $Result[0].OperatingSystem | Should -Be 'Windows 11'
        $Result[0].Arch | Should -Be 'x64'
        $Result[0].ReleaseId | Should -Be '24H2'
        $Result[0].RegBuild | Should -Be '26100'
        $Result[0].UBR | Should -Be ([version]'26100.4061')
        $Result[0].Version | Should -Be ([version]'10.0.26100.4061')
        $Result[0].MajorVersion | Should -Be 10
        $Result[0].MinorVersion | Should -Be 0
        $Result[0].Build | Should -Be '26100'
        $Result[0].Languages | Should -Be 'en-US'
        $Result[0].EditionId | Should -Be 'Enterprise'
        $Result[0].InstallationType | Should -Be 'Client'
        $Result[0].CreatedTime | Should -Be ([datetime]'2026-01-10 10:00:00')
        $Result[0].ModifiedTime | Should -Be ([datetime]'2026-01-10 12:00:00')
        $Result[0].OSMFamily | Should -Be 'Client Enterprise x64 26100 en-US'
        $Result[0].Revision | Should -Be 'OK'
        $Result[0].Updates | Should -Be 'OK'
        $Result[0].PSObject.Properties.Name | Should -Not -Contain 'OSMFamilyV1'
    }

    It 'ignores directories without <Missing>' -TestCases @(
        @{Missing = 'Get-WindowsImage.xml'; Switch = 'NoWindowsImage'}
        @{Missing = 'CurrentVersion.xml'; Switch = 'NoCurrentVersion'}
        @{Missing = 'Sessions.xml'; Switch = 'NoSessions'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Complete') | Out-Null
        $Parameters = @{Path = (Join-Path $SetOSDBuilderPathOSBuilds 'Incomplete')}
        $Parameters[$Switch] = $true
        New-OSMediaFixture @Parameters | Out-Null

        (Get-OSBuilds).Name | Should -Be 'Complete'
    }

    It 'maps the Architecture <Architecture> to <Arch>' -TestCases @(
        @{Architecture = 0; Arch = 'x86'}
        @{Architecture = 9; Arch = 'x64'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Build') -Architecture $Architecture | Out-Null
        (Get-OSBuilds -OSArch $Arch).Arch | Should -Be $Arch
    }

    It 'does not return <Arch> OSBuilds, -OSArch only accepts x64 and x86' -TestCases @(
        @{Architecture = 6; Arch = 'ia64'}
        @{Architecture = 12; Arch = 'x64 ARM'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Build') -Architecture $Architecture | Out-Null
        Get-OSBuilds | Should -BeNullOrEmpty
        Get-OSBuilds -OSArch x86 | Should -BeNullOrEmpty
    }

    It 'returns only x64 OSBuilds without -OSArch' {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'x64') | Out-Null
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'x86') -Architecture 0 | Out-Null

        (Get-OSBuilds).Name | Should -Be 'x64'
        (Get-OSBuilds -OSArch x86).Name | Should -Be 'x86'
    }

    It 'detects <OperatingSystem> from <ImageName> (<InstallationType>)' -TestCases @(
        @{ImageName = 'Windows 10 Enterprise'; InstallationType = 'Client'; OperatingSystem = 'Windows 10'}
        @{ImageName = 'Windows 11 Pro'; InstallationType = 'Client'; OperatingSystem = 'Windows 11'}
        @{ImageName = 'Windows Server 2025 SERVERDATACENTER'; InstallationType = 'Server'; OperatingSystem = 'Windows Server'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Build') -ImageName $ImageName -InstallationType $InstallationType | Out-Null
        (Get-OSBuilds).OperatingSystem | Should -Be $OperatingSystem
    }

    It 'maps Build <Build> to ReleaseId <Expected>' -TestCases @(
        @{Build = 10240; DisplayVersion = ''; ReleaseId = ''; Expected = '1507'}
        @{Build = 14393; DisplayVersion = ''; ReleaseId = '1607'; Expected = '1607'}
        @{Build = 15063; DisplayVersion = ''; ReleaseId = ''; Expected = '1703'}
        @{Build = 16299; DisplayVersion = ''; ReleaseId = ''; Expected = '1709'}
        @{Build = 17134; DisplayVersion = ''; ReleaseId = ''; Expected = '1803'}
        @{Build = 17763; DisplayVersion = ''; ReleaseId = ''; Expected = '1809'}
        @{Build = 18363; DisplayVersion = ''; ReleaseId = '1909'; Expected = '1909'}
        @{Build = 19041; DisplayVersion = '22H2'; ReleaseId = '2009'; Expected = '22H2'}
        @{Build = 26100; DisplayVersion = '24H2'; ReleaseId = '2009'; Expected = '24H2'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Build') -Build $Build -UBR "$Build.1000" `
            -CurrentBuild "$Build" -DisplayVersion $DisplayVersion -ReleaseId $ReleaseId | Out-Null
        (Get-OSBuilds).ReleaseId | Should -Be $Expected
    }

    It 'warns and skips an OSBuild that is not Windows 10 or later' {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Windows 8.1') -ImageName 'Windows 8.1 Enterprise' -MajorVersion 6 -MinorVersion 3 -Build 9600 -UBR '9600.20000' -CurrentBuild '9600' -DisplayVersion '' -ReleaseId '' | Out-Null

        $Output = @(Get-OSBuilds 3>&1)

        $Output.Count | Should -Be 1
        $Output[0] | Should -BeOfType [System.Management.Automation.WarningRecord]
        $Output[0].Message | Should -BeLike '*Windows 8.1 is no longer supported by OSDBuilder'
    }

    It 'sets Revision OK on the newest OSBuild of an OSMFamily and Superseded on the older ones' {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'B Old') -ModifiedTime '2026-01-10' | Out-Null
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'A New') -ModifiedTime '2026-02-10' -UBR '26100.4200' | Out-Null

        $Result = Get-OSBuilds

        $Result.Name | Should -Be @('A New', 'B Old')
        $Result.Revision | Should -Be @('OK', 'Superseded')
    }

    It 'sets Updates <Expected> when <Description>' -TestCases @(
        @{Description = 'all required updates are installed'; InstalledKB = @('5050001', '5050002'); StagedKB = @(); Expected = 'OK'}
        @{Description = 'an update is only staged'; InstalledKB = @('5050002'); StagedKB = @('5050001'); Expected = 'Update'}
        @{Description = 'an update is missing'; InstalledKB = @('5050001'); StagedKB = @(); Expected = 'Update'}
    ) {
        $script:OSDUpdates = @(
            New-OSDUpdateFixture -UpdateGroup 'LCU' -FileKBNumber '5050001'
            New-OSDUpdateFixture -UpdateGroup 'SSU' -FileKBNumber '5050002'
            New-OSDUpdateFixture -UpdateGroup 'Setup' -FileKBNumber '5050003'
            New-OSDUpdateFixture -UpdateGroup 'Optional' -FileKBNumber '5050004'
            New-OSDUpdateFixture -UpdateGroup '' -FileKBNumber '5050005'
            New-OSDUpdateFixture -UpdateOS 'Windows 10' -UpdateBuild '22H2' -FileKBNumber '5050006'
            New-OSDUpdateFixture -UpdateArch 'x86' -FileKBNumber '5050007'
        )
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Build') -InstalledKB $InstalledKB -StagedKB $StagedKB | Out-Null

        (Get-OSBuilds).Updates | Should -Be $Expected
    }

    It 'does not require Adobe Flash updates for Server Core' {
        $script:OSDUpdates = @(New-OSDUpdateFixture -UpdateOS 'Windows Server' -UpdateBuild '1809' -UpdateGroup 'AdobeSU' -FileKBNumber '4580325')
        $Parameters = @{ImageName = 'Windows Server 2019 SERVERSTANDARD'; Build = 17763; UBR = '17763.1000'; CurrentBuild = '17763'; DisplayVersion = ''; ReleaseId = '1809'}
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Core') -InstallationType 'Server Core' @Parameters | Out-Null
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Desktop') -InstallationType 'Server' @Parameters | Out-Null

        $Result = Get-OSBuilds

        ($Result | Where-Object Name -eq 'Core').Updates | Should -Be 'OK'
        ($Result | Where-Object Name -eq 'Desktop').Updates | Should -Be 'Update'
    }

    Context 'Filters' {
        BeforeEach {
            $script:OSDUpdates = @(New-OSDUpdateFixture -UpdateOS 'Windows 10' -UpdateBuild '22H2' -FileKBNumber '5060001')
            $Windows10 = @{ImageName = 'Windows 10 Enterprise'; Build = 19041; UBR = '19045.5000'; CurrentBuild = '19045'; DisplayVersion = '22H2'}
            $Server = @{ImageName = 'Windows Server 2025 SERVERDATACENTER'; InstallationType = 'Server'; EditionId = 'ServerDatacenter'}
            New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Win11 24H2 New') -ModifiedTime '2026-02-01' | Out-Null
            New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Win11 24H2 Old') -ModifiedTime '2026-01-01' | Out-Null
            New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Win10 22H2') -ModifiedTime '2026-01-15' @Windows10 | Out-Null
            New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Server 2025') -ModifiedTime '2026-01-20' @Server | Out-Null
        }

        It 'returns <Expected> for <Description>' -TestCases @(
            @{Description = 'no filter'; Parameters = @{}; Expected = @('Server 2025', 'Win10 22H2', 'Win11 24H2 New', 'Win11 24H2 Old')}
            @{Description = '-OSReleaseId 22H2'; Parameters = @{OSReleaseId = '22H2'}; Expected = @('Win10 22H2')}
            @{Description = '-OSInstallationType Client'; Parameters = @{OSInstallationType = 'Client'}; Expected = @('Win10 22H2', 'Win11 24H2 New', 'Win11 24H2 Old')}
            @{Description = '-OSInstallationType Server'; Parameters = @{OSInstallationType = 'Server'}; Expected = @('Server 2025')}
            @{Description = '-OSMajorVersion 10'; Parameters = @{OSMajorVersion = '10'}; Expected = @('Server 2025', 'Win10 22H2', 'Win11 24H2 New', 'Win11 24H2 Old')}
            @{Description = '-Revision OK'; Parameters = @{Revision = 'OK'}; Expected = @('Server 2025', 'Win10 22H2', 'Win11 24H2 New')}
            @{Description = '-Revision Superseded'; Parameters = @{Revision = 'Superseded'}; Expected = @('Win11 24H2 Old')}
            @{Description = '-Updates Update'; Parameters = @{Updates = 'Update'}; Expected = @('Win10 22H2')}
            @{Description = '-Updates OK'; Parameters = @{Updates = 'OK'}; Expected = @('Server 2025', 'Win11 24H2 New', 'Win11 24H2 Old')}
            @{Description = '-Newest'; Parameters = @{Newest = $true}; Expected = @('Win11 24H2 New')}
        ) {
            @((Get-OSBuilds @Parameters).Name) | Should -Be $Expected
        }

        It 'returns the OSBuilds selected in Out-GridView with -GridView' {
            (Get-OSBuilds -GridView).Name | Should -Be 'Win11 24H2 Old'
            Should -Invoke Out-GridView -ParameterFilter {$PassThru -and ($Title -eq 'OSBuilds')}
        }
    }

    # KnownBug: Get-OSBuilds.ps1:181 [string]$RegValueCurrentBuild is never $null, OSMFamily uses an empty CurrentBuild instead of Build
    It 'uses the Build in OSMFamily when CurrentVersion.xml has no CurrentBuild' -Skip {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSBuilds 'Build') -CurrentBuild '' | Out-Null
        (Get-OSBuilds).OSMFamily | Should -Be 'Client Enterprise x64 26100 en-US'
    }
}

Describe 'Get-PEBuilds' {
    BeforeEach {
        $Root = Join-Path $TestDrive ([guid]::NewGuid().Guid.Substring(0, 8))
        $SetOSDBuilderPathPEBuilds = Join-Path $Root 'PEBuilds'
        New-Item -Path $SetOSDBuilderPathPEBuilds -ItemType Directory -Force | Out-Null
        $WinPE = @{ImageName = 'Microsoft Windows PE (x64)'; EditionId = 'WindowsPE'; InstallationType = 'WindowsPE'}

        Mock Get-OSDBuilder {}
        Mock Out-GridView {$InputObject | Where-Object Name -eq 'WinPE B'}
    }

    It 'initializes OSDBuilder with -CreatePaths -HideDetails' {
        Get-PEBuilds | Should -BeNullOrEmpty
        Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
    }

    It 'returns the properties of Get-WindowsImage.xml and CurrentVersion.xml' {
        $PEBuild = New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathPEBuilds 'WinPE x64 24H2') -NoSessions @WinPE

        $Result = @(Get-PEBuilds)

        $Result.Count | Should -Be 1
        $Result[0].MediaType | Should -Be 'PEBuild'
        $Result[0].Name | Should -Be 'WinPE x64 24H2'
        $Result[0].FullName | Should -Be $PEBuild.FullName
        $Result[0].ImageName | Should -Be 'Microsoft Windows PE (x64)'
        $Result[0].OperatingSystem | Should -Be 'Windows 10'
        $Result[0].Arch | Should -Be 'x64'
        $Result[0].ReleaseId | Should -Be '24H2'
        $Result[0].RegBuild | Should -Be '26100'
        $Result[0].UBR | Should -Be ([version]'26100.4061')
        $Result[0].Version | Should -Be ([version]'10.0.26100.4061')
        $Result[0].MajorVersion | Should -Be 10
        $Result[0].MinorVersion | Should -Be 0
        $Result[0].Build | Should -Be '26100'
        $Result[0].Languages | Should -Be 'en-US'
        $Result[0].EditionId | Should -Be 'WindowsPE'
        $Result[0].InstallationType | Should -Be 'WindowsPE'
        $Result[0].CreatedTime | Should -Be ([datetime]'2026-01-10 10:00:00')
        $Result[0].ModifiedTime | Should -Be ([datetime]'2026-01-10 12:00:00')
        $Result[0].OSMFamily | Should -Be 'WindowsPE WindowsPE x64 26100 en-US'
        $Result[0].PSObject.Properties.Name | Should -Not -Contain 'Revision'
    }

    It 'ignores directories without <Missing>' -TestCases @(
        @{Missing = 'Get-WindowsImage.xml'; Switch = 'NoWindowsImage'}
        @{Missing = 'CurrentVersion.xml'; Switch = 'NoCurrentVersion'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathPEBuilds 'Complete') @WinPE | Out-Null
        $Parameters = @{Path = (Join-Path $SetOSDBuilderPathPEBuilds 'Incomplete')}
        $Parameters[$Switch] = $true
        New-OSMediaFixture @Parameters @WinPE | Out-Null

        (Get-PEBuilds).Name | Should -Be 'Complete'
    }

    It 'maps the Architecture <Architecture> to <Arch>' -TestCases @(
        @{Architecture = 0; Arch = 'x86'}
        @{Architecture = 6; Arch = 'ia64'}
        @{Architecture = 9; Arch = 'x64'}
        @{Architecture = 12; Arch = 'x64 ARM'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathPEBuilds 'WinPE') -Architecture $Architecture @WinPE | Out-Null
        (Get-PEBuilds).Arch | Should -Be $Arch
    }

    It 'detects <OperatingSystem> from <ImageName> (<InstallationType>)' -TestCases @(
        @{ImageName = 'Microsoft Windows PE (x64)'; InstallationType = 'WindowsPE'; OperatingSystem = 'Windows 10'}
        @{ImageName = 'Microsoft Windows Recovery Environment 11 (x64)'; InstallationType = 'WindowsPE'; OperatingSystem = 'Windows 11'}
        @{ImageName = 'Microsoft Windows Setup (x64)'; InstallationType = 'Server'; OperatingSystem = 'Windows Server'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathPEBuilds 'WinPE') -ImageName $ImageName -InstallationType $InstallationType | Out-Null
        (Get-PEBuilds).OperatingSystem | Should -Be $OperatingSystem
    }

    It 'maps Build <Build> to ReleaseId <Expected>' -TestCases @(
        @{Build = 10240; DisplayVersion = ''; ReleaseId = ''; Expected = '1507'}
        @{Build = 14393; DisplayVersion = ''; ReleaseId = '1607'; Expected = '1607'}
        @{Build = 15063; DisplayVersion = ''; ReleaseId = ''; Expected = '1703'}
        @{Build = 16299; DisplayVersion = ''; ReleaseId = ''; Expected = '1709'}
        @{Build = 17134; DisplayVersion = ''; ReleaseId = ''; Expected = '1803'}
        @{Build = 17763; DisplayVersion = ''; ReleaseId = ''; Expected = '1809'}
        @{Build = 19041; DisplayVersion = ''; ReleaseId = '2004'; Expected = '2004'}
        @{Build = 26100; DisplayVersion = '24H2'; ReleaseId = '2009'; Expected = '24H2'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathPEBuilds 'WinPE') -Build $Build -UBR "$Build.1000" `
            -CurrentBuild "$Build" -DisplayVersion $DisplayVersion -ReleaseId $ReleaseId @WinPE | Out-Null
        (Get-PEBuilds).ReleaseId | Should -Be $Expected
    }

    It 'warns and skips a PEBuild that is not Windows 10 or later' {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathPEBuilds 'WinPE 8.1') -MajorVersion 6 -MinorVersion 3 -Build 9600 -UBR '9600.20000' -CurrentBuild '9600' -DisplayVersion '' -ReleaseId '' @WinPE | Out-Null
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathPEBuilds 'WinPE 11') @WinPE | Out-Null

        $Output = @(Get-PEBuilds 3>&1)

        ($Output | Where-Object {$_ -is [System.Management.Automation.WarningRecord]}).Message | Should -BeLike '*WinPE 8.1 is no longer supported by OSDBuilder'
        ($Output | Where-Object {$_ -isnot [System.Management.Automation.WarningRecord]}).Name | Should -Be 'WinPE 11'
    }

    It 'returns all PEBuilds sorted by Name' {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathPEBuilds 'WinPE B') @WinPE | Out-Null
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathPEBuilds 'WinPE A') -Architecture 0 @WinPE | Out-Null

        (Get-PEBuilds).Name | Should -Be @('WinPE A', 'WinPE B')
    }

    It 'returns the PEBuilds selected in Out-GridView with -GridView' {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathPEBuilds 'WinPE A') @WinPE | Out-Null
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathPEBuilds 'WinPE B') @WinPE | Out-Null

        (Get-PEBuilds -GridView).Name | Should -Be 'WinPE B'
        Should -Invoke Out-GridView -ParameterFilter {$PassThru -and ($Title -eq 'PEBuilds')}
    }

    # KnownBug: Get-PEBuilds.ps1:144 [string]$RegValueCurrentBuild is never $null, OSMFamily uses an empty CurrentBuild instead of Build
    It 'uses the Build in OSMFamily when CurrentVersion.xml has no CurrentBuild' -Skip {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathPEBuilds 'WinPE') -CurrentBuild '' @WinPE | Out-Null
        (Get-PEBuilds).OSMFamily | Should -Be 'WindowsPE WindowsPE x64 26100 en-US'
    }
}
