BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    . (Join-Path (Join-Path $RepoRoot 'Public') 'Get-OSDBuilder.ps1')
    #Public\Get-OSImport.ps1 contains an older copy of Get-OSMedia and Repair-GetOSDMediaTemplateDirectories
    #The module dot-sources Get-OSImport.ps1 before Get-OSMedia.ps1, so these functions are replaced in the module
    . (Join-Path (Join-Path $RepoRoot 'Public') 'Get-OSImport.ps1')
    . (Join-Path (Join-Path $FixturesPath 'GetOSMedia') 'New-OSMediaFixture.ps1')
}

Describe 'Get-OSMedia' {
    BeforeEach {
        $Root = Join-Path $TestDrive ([guid]::NewGuid().Guid.Substring(0, 8))
        $SetOSDBuilderPathOSImport = Join-Path $Root 'OSImport'
        $SetOSDBuilderPathOSMedia = Join-Path $Root 'OSMedia'
        $SetOSDBuilderPathTemplates = Join-Path $Root 'Templates'
        New-Item -Path $SetOSDBuilderPathOSImport, $SetOSDBuilderPathOSMedia -ItemType Directory -Force | Out-Null

        $script:OSDUpdates = @()
        Mock Get-OSDBuilder {}
        Mock Get-OSDUpdates {$script:OSDUpdates}
        Mock Out-GridView {$InputObject | Where-Object Name -like 'Win11*'}
    }

    It 'initializes OSDBuilder with -CreatePaths -HideDetails and reads the updates silently' {
        Get-OSMedia | Should -BeNullOrEmpty
        Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
        Should -Invoke Get-OSDUpdates -Times 1 -Exactly -ParameterFilter {$Silent}
    }

    It 'returns the properties of Get-WindowsImage.xml and CurrentVersion.xml' {
        $Guid = [guid]::NewGuid().Guid
        $Media = New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Windows 11 Enterprise x64 24H2 26100.4061 en-US') -OSMGuid $Guid

        $Result = @(Get-OSMedia)

        $Result.Count | Should -Be 1
        $Result[0].MediaType | Should -Be 'OSMedia'
        $Result[0].Name | Should -Be 'Windows 11 Enterprise x64 24H2 26100.4061 en-US'
        $Result[0].FullName | Should -Be $Media.FullName
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
        $Result[0].OSMFamilyV1 | Should -Be '20260110100000Enterprise'
        $Result[0].OSMGuid | Should -Be $Guid
        $Result[0].Revision | Should -Be 'OK'
        $Result[0].Superseded | Should -BeFalse
        $Result[0].Updates | Should -Be 'OK'
        $Result[0].NeedsUpdate | Should -BeFalse
    }

    It 'ignores directories without <Missing>' -TestCases @(
        @{Missing = 'Get-WindowsImage.xml'; Switch = 'NoWindowsImage'}
        @{Missing = 'CurrentVersion.xml'; Switch = 'NoCurrentVersion'}
        @{Missing = 'Sessions.xml'; Switch = 'NoSessions'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Complete') | Out-Null
        $Parameters = @{Path = (Join-Path $SetOSDBuilderPathOSMedia 'Incomplete')}
        $Parameters[$Switch] = $true
        New-OSMediaFixture @Parameters | Out-Null

        (Get-OSMedia).Name | Should -Be 'Complete'
    }

    It 'writes an error and still returns the OSMedia when Get-WindowsPackage.xml is missing' {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'NoPackages') -NoWindowsPackage | Out-Null
        $Result = Get-OSMedia -ErrorVariable ImportErrors -ErrorAction SilentlyContinue
        $Result.Name | Should -Be 'NoPackages'
        "$ImportErrors" | Should -BeLike '*Get-WindowsPackage.xml*'
    }

    It 'maps the Architecture <Architecture> to <Arch>' -TestCases @(
        @{Architecture = 0; Arch = 'x86'}
        @{Architecture = 6; Arch = 'ia64'}
        @{Architecture = 9; Arch = 'x64'}
        @{Architecture = 12; Arch = 'x64 ARM'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Media') -Architecture $Architecture | Out-Null
        (Get-OSMedia).Arch | Should -Be $Arch
    }

    It 'detects <OperatingSystem> from <ImageName> (<InstallationType>)' -TestCases @(
        @{ImageName = 'Windows 10 Enterprise'; InstallationType = 'Client'; OperatingSystem = 'Windows 10'}
        @{ImageName = 'Windows 11 Pro'; InstallationType = 'Client'; OperatingSystem = 'Windows 11'}
        @{ImageName = 'Windows Server 2025 SERVERDATACENTER'; InstallationType = 'Server'; OperatingSystem = 'Windows Server'}
        @{ImageName = 'Windows Server 2022 SERVERSTANDARDCORE'; InstallationType = 'Server Core'; OperatingSystem = 'Windows Server'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Media') -ImageName $ImageName -InstallationType $InstallationType | Out-Null
        (Get-OSMedia).OperatingSystem | Should -Be $OperatingSystem
    }

    It 'maps Build <Build> and CurrentBuild <CurrentBuild> to ReleaseId <Expected>' -TestCases @(
        @{Build = 10240; CurrentBuild = '10240'; DisplayVersion = ''; ReleaseId = ''; Expected = '1507'}
        @{Build = 14393; CurrentBuild = '14393'; DisplayVersion = ''; ReleaseId = '1607'; Expected = '1607'}
        @{Build = 15063; CurrentBuild = '15063'; DisplayVersion = ''; ReleaseId = ''; Expected = '1703'}
        @{Build = 16299; CurrentBuild = '16299'; DisplayVersion = ''; ReleaseId = ''; Expected = '1709'}
        @{Build = 17134; CurrentBuild = '17134'; DisplayVersion = ''; ReleaseId = ''; Expected = '1803'}
        @{Build = 17763; CurrentBuild = '17763'; DisplayVersion = ''; ReleaseId = ''; Expected = '1809'}
        @{Build = 18362; CurrentBuild = '18362'; DisplayVersion = ''; ReleaseId = ''; Expected = '1903'}
        @{Build = 18362; CurrentBuild = '18363'; DisplayVersion = ''; ReleaseId = '1909'; Expected = '1909'}
        @{Build = 19041; CurrentBuild = '19041'; DisplayVersion = ''; ReleaseId = '2004'; Expected = '2004'}
        @{Build = 19041; CurrentBuild = '19042'; DisplayVersion = '20H2'; ReleaseId = '2009'; Expected = '20H2'}
        @{Build = 19041; CurrentBuild = '19043'; DisplayVersion = ''; ReleaseId = '2009'; Expected = '21H1'}
        @{Build = 19041; CurrentBuild = '19044'; DisplayVersion = ''; ReleaseId = '2009'; Expected = '21H2'}
        @{Build = 19041; CurrentBuild = '19045'; DisplayVersion = '22H2'; ReleaseId = '2009'; Expected = '22H2'}
        @{Build = 22000; CurrentBuild = '22000'; DisplayVersion = ''; ReleaseId = '2009'; Expected = '21H2'}
        @{Build = 20348; CurrentBuild = '20348'; DisplayVersion = ''; ReleaseId = '2009'; Expected = '21H2'}
        @{Build = 22621; CurrentBuild = '22621'; DisplayVersion = ''; ReleaseId = '2009'; Expected = '22H2'}
        @{Build = 22621; CurrentBuild = '22631'; DisplayVersion = ''; ReleaseId = '2009'; Expected = '23H2'}
        @{Build = 26100; CurrentBuild = '26100'; DisplayVersion = ''; ReleaseId = '2009'; Expected = '24H2'}
        @{Build = 26100; CurrentBuild = '26200'; DisplayVersion = ''; ReleaseId = '2009'; Expected = '25H2'}
        @{Build = 26100; CurrentBuild = '26300'; DisplayVersion = ''; ReleaseId = '2009'; Expected = '26H2'}
        @{Build = 27000; CurrentBuild = '27000'; DisplayVersion = '27H2'; ReleaseId = '2009'; Expected = '27H2'}
        @{Build = 27000; CurrentBuild = '27000'; DisplayVersion = ''; ReleaseId = '2009'; Expected = '2009'}
    ) {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Media') -Build $Build -UBR "$CurrentBuild.1000" `
            -CurrentBuild $CurrentBuild -DisplayVersion $DisplayVersion -ReleaseId $ReleaseId | Out-Null
        $Result = Get-OSMedia
        $Result.ReleaseId | Should -Be $Expected
        $Result.RegBuild | Should -Be $CurrentBuild
    }

    It 'warns and skips an OSMedia that is not Windows 10 or later' {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Windows 8.1') -ImageName 'Windows 8.1 Enterprise' -MajorVersion 6 -MinorVersion 3 -Build 9600 -UBR '9600.20000' -CurrentBuild '9600' -DisplayVersion '' -ReleaseId '' | Out-Null
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Windows 11') | Out-Null

        $Output = @(Get-OSMedia 3>&1)

        $Warnings = @($Output | Where-Object {$_ -is [System.Management.Automation.WarningRecord]})
        $Warnings.Count | Should -Be 1
        $Warnings[0].Message | Should -BeLike '*Windows 8.1 is no longer supported by OSDBuilder'
        @($Output | Where-Object {$_ -isnot [System.Management.Automation.WarningRecord]}).Name | Should -Be 'Windows 11'
    }

    It 'creates and saves an OSMGuid when Get-WindowsImage.xml has none' {
        $Media = New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'NoGuid') -OSMGuid ''

        $Guid = (Get-OSMedia).OSMGuid

        "$Guid" | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        $Xml = Join-Path (Join-Path $Media.FullName 'info') 'xml'
        "$((Import-Clixml -Path (Join-Path $Xml 'Get-WindowsImage.xml')).OSMGuid)" | Should -Be "$Guid"
        @(Get-ChildItem -Path $Xml -Filter '*-Get-WindowsImage.xml').Count | Should -Be 1
        $Json = Join-Path (Join-Path $Media.FullName 'info') 'json'
        (Get-Content -Path (Join-Path $Json 'Get-WindowsImage.json') -Raw | ConvertFrom-Json).ImageName | Should -Be 'Windows 11 Enterprise'
        @(Get-ChildItem -Path $Json -Filter '*-Get-WindowsImage.json').Count | Should -Be 1
        @(Get-ChildItem -Path (Join-Path (Join-Path $Media.FullName 'info') 'logs') -Filter '*-Get-WindowsImage.txt').Count | Should -Be 1
        $Text = Get-Content -Path (Join-Path $Media.FullName 'WindowsImage.txt')
        @($Text | Where-Object {$_ -match "^OSMGuid\s+: $Guid"}).Count | Should -Be 1
        $Text | Where-Object {-not $_.Trim()} | Should -BeNullOrEmpty

        #The saved OSMGuid is returned again
        "$((Get-OSMedia).OSMGuid)" | Should -Be "$Guid"
    }

    It 'sets Revision OK on the newest OSMedia of an OSMFamily and Superseded on the older ones' {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Win11 24H2 January') -ModifiedTime '2026-01-10' | Out-Null
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Win11 24H2 February') -UBR '26100.4200' -ModifiedTime '2026-02-10' | Out-Null
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Win11 24H2 German') -Languages 'de-DE' -ModifiedTime '2026-01-01' | Out-Null

        $Result = Get-OSMedia

        ($Result | Where-Object Name -eq 'Win11 24H2 February').Revision | Should -Be 'OK'
        ($Result | Where-Object Name -eq 'Win11 24H2 February').Superseded | Should -BeFalse
        ($Result | Where-Object Name -eq 'Win11 24H2 January').Revision | Should -Be 'Superseded'
        ($Result | Where-Object Name -eq 'Win11 24H2 January').Superseded | Should -BeTrue
        ($Result | Where-Object Name -eq 'Win11 24H2 German').Revision | Should -Be 'OK'
        #Sorted by Name
        $Result.Name | Should -Be @('Win11 24H2 February', 'Win11 24H2 German', 'Win11 24H2 January')
    }

    It 'prefers the OSMedia in OSMedia over the OSImport of the same OSMFamily' {
        $script:Directories = @(
            New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSImport 'Imported') -ModifiedTime '2026-01-10'
            New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Updated') -ModifiedTime '2026-01-10'
        ) | ForEach-Object {
            #Get-OSMedia detects OSImport with a Windows path (\OSImport\), on macOS and Linux the full name uses / as separator
            [PSCustomObject]@{Name = $_.Name; FullName = $_.FullName.Replace('/', '\')}
        }
        Mock Get-ChildItem -ParameterFilter {$Directory} {$script:Directories}

        $Result = Get-OSMedia

        ($Result | Where-Object Name -eq 'Imported').MediaType | Should -Be 'OSImport'
        ($Result | Where-Object Name -eq 'Updated').MediaType | Should -Be 'OSMedia'
        ($Result | Where-Object Name -eq 'Updated').Revision | Should -Be 'OK'
        ($Result | Where-Object Name -eq 'Imported').Revision | Should -Be 'Superseded'
        Should -Invoke Get-ChildItem -Times 1 -Exactly -ParameterFilter {$Directory -and ($Path -contains $SetOSDBuilderPathOSImport) -and ($Path -contains $SetOSDBuilderPathOSMedia)}
    }

    It 'sets Updates OK when all required updates are installed' {
        $script:OSDUpdates = @(
            New-OSDUpdateFixture -UpdateGroup 'SSU' -FileKBNumber '5050002'
            New-OSDUpdateFixture -UpdateGroup 'LCU' -FileKBNumber '5050001'
            #Not required for the OSMedia
            New-OSDUpdateFixture -UpdateGroup 'Setup' -FileKBNumber '5050003'
            New-OSDUpdateFixture -UpdateGroup 'Optional' -FileKBNumber '5050004'
            New-OSDUpdateFixture -UpdateGroup '' -FileKBNumber '5050005'
            New-OSDUpdateFixture -UpdateOS 'Windows 10' -UpdateBuild '22H2' -FileKBNumber '5050006'
            New-OSDUpdateFixture -UpdateBuild '25H2' -FileKBNumber '5050007'
            New-OSDUpdateFixture -UpdateArch 'arm64' -FileKBNumber '5050008'
        )
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Updated') -InstalledKB '5050001', '5050002' | Out-Null

        $Result = Get-OSMedia

        $Result.Updates | Should -Be 'OK'
        $Result.NeedsUpdate | Should -BeFalse
    }

    It 'sets Updates Update when a required update is missing or only staged in Sessions.xml' {
        $script:OSDUpdates = @(
            New-OSDUpdateFixture -UpdateGroup 'SSU' -FileKBNumber '5050002'
            New-OSDUpdateFixture -UpdateGroup 'LCU' -FileKBNumber '5050001'
        )
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Staged') -InstalledKB '5050002' -StagedKB '5050001' | Out-Null

        $Result = Get-OSMedia

        $Result.Updates | Should -Be 'Update'
        $Result.NeedsUpdate | Should -BeTrue
    }

    It 'does not require Adobe Flash updates for Server Core' {
        $script:OSDUpdates = @(New-OSDUpdateFixture -UpdateOS 'Windows Server' -UpdateBuild '1809' -UpdateGroup 'AdobeSU' -FileKBNumber '4580325')
        $Parameters = @{ImageName = 'Windows Server 2019 SERVERSTANDARD'; Build = 17763; UBR = '17763.1000'; CurrentBuild = '17763'; DisplayVersion = ''; ReleaseId = '1809'}
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Core') -InstallationType 'Server Core' @Parameters | Out-Null
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Desktop') -InstallationType 'Server' @Parameters | Out-Null

        $Result = Get-OSMedia

        ($Result | Where-Object Name -eq 'Core').Updates | Should -Be 'OK'
        ($Result | Where-Object Name -eq 'Desktop').Updates | Should -Be 'Update'
    }

    Context 'Filters' {
        BeforeEach {
            $script:OSDUpdates = @(New-OSDUpdateFixture -UpdateOS 'Windows 10' -UpdateBuild '22H2' -UpdateArch 'x86' -FileKBNumber '5060001')
            $Windows10 = @{ImageName = 'Windows 10 Enterprise'; Architecture = 0; Build = 19041; UBR = '19045.5000'; CurrentBuild = '19045'; DisplayVersion = '22H2'}
            $Server = @{ImageName = 'Windows Server 2025 SERVERDATACENTER'; InstallationType = 'Server'; EditionId = 'ServerDatacenter'}
            New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Win11 x64 24H2 New') -ModifiedTime '2026-02-01' | Out-Null
            New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Win11 x64 24H2 Old') -ModifiedTime '2026-01-01' | Out-Null
            New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Win10 x86 22H2') -ModifiedTime '2026-01-15' @Windows10 | Out-Null
            New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Server 2025 x64 24H2') -ModifiedTime '2026-01-20' @Server | Out-Null
        }

        It 'returns <Expected> for <Description>' -TestCases @(
            @{Description = 'no filter'; Parameters = @{}; Expected = @('Server 2025 x64 24H2', 'Win10 x86 22H2', 'Win11 x64 24H2 New', 'Win11 x64 24H2 Old')}
            @{Description = '-OSArch x86'; Parameters = @{OSArch = 'x86'}; Expected = @('Win10 x86 22H2')}
            @{Description = '-OSArch x64'; Parameters = @{OSArch = 'x64'}; Expected = @('Server 2025 x64 24H2', 'Win11 x64 24H2 New', 'Win11 x64 24H2 Old')}
            @{Description = '-OSReleaseId 22H2'; Parameters = @{OSReleaseId = '22H2'}; Expected = @('Win10 x86 22H2')}
            @{Description = '-OSInstallationType Client'; Parameters = @{OSInstallationType = 'Client'}; Expected = @('Win10 x86 22H2', 'Win11 x64 24H2 New', 'Win11 x64 24H2 Old')}
            @{Description = '-OSInstallationType Server'; Parameters = @{OSInstallationType = 'Server'}; Expected = @('Server 2025 x64 24H2')}
            @{Description = '-OSMajorVersion 10'; Parameters = @{OSMajorVersion = '10'}; Expected = @('Server 2025 x64 24H2', 'Win10 x86 22H2', 'Win11 x64 24H2 New', 'Win11 x64 24H2 Old')}
            @{Description = '-Revision OK'; Parameters = @{Revision = 'OK'}; Expected = @('Server 2025 x64 24H2', 'Win10 x86 22H2', 'Win11 x64 24H2 New')}
            @{Description = '-Revision Superseded'; Parameters = @{Revision = 'Superseded'}; Expected = @('Win11 x64 24H2 Old')}
            @{Description = '-Updates Update'; Parameters = @{Updates = 'Update'}; Expected = @('Win10 x86 22H2')}
            @{Description = '-Updates OK'; Parameters = @{Updates = 'OK'}; Expected = @('Server 2025 x64 24H2', 'Win11 x64 24H2 New', 'Win11 x64 24H2 Old')}
            @{Description = '-Newest'; Parameters = @{Newest = $true}; Expected = @('Win11 x64 24H2 New')}
            @{Description = '-OSArch x64 -OSInstallationType Client -Revision OK'; Parameters = @{OSArch = 'x64'; OSInstallationType = 'Client'; Revision = 'OK'}; Expected = @('Win11 x64 24H2 New')}
        ) {
            @((Get-OSMedia @Parameters).Name) | Should -Be $Expected
        }

        It 'returns the OSMedia selected in Out-GridView with -GridView' {
            $Result = Get-OSMedia -GridView
            @($Result.Name) | Should -Be @('Win11 x64 24H2 New', 'Win11 x64 24H2 Old')
            $Result[0].PSObject.Properties.Name | Should -Not -Contain 'OSMFamilyV1'
            $Result[0].PSObject.Properties.Name | Should -Contain 'OSMGuid'
            Should -Invoke Out-GridView -ParameterFilter {$PassThru -and ($Title -eq 'OSMedia')}
        }

        It 'rejects a value that is not in the ValidateSet of <Parameter>' -TestCases @(
            @{Parameter = 'OSArch'; Value = 'arm64'}
            @{Parameter = 'OSInstallationType'; Value = 'Desktop'}
            @{Parameter = 'OSMajorVersion'; Value = '11'}
            @{Parameter = 'OSReleaseId'; Value = '1803'}
            @{Parameter = 'Revision'; Value = 'Old'}
            @{Parameter = 'Updates'; Value = 'Missing'}
        ) {
            $Parameters = @{$Parameter = $Value}
            {Get-OSMedia @Parameters} | Should -Throw -ErrorId 'ParameterArgumentValidationError,Get-OSMedia'
        }
    }

    It 'creates the AutoApply template directories when Templates are used' {
        New-Item -Path (Join-Path $SetOSDBuilderPathTemplates 'Drivers') -ItemType Directory -Force | Out-Null
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Media') | Out-Null

        Get-OSMedia | Out-Null

        foreach ($Template in 'Drivers', 'ExtraFiles', 'Registry', 'Scripts') {
            $AutoApply = Join-Path (Join-Path $SetOSDBuilderPathTemplates $Template) 'AutoApply'
            foreach ($Name in 'Global', 'Global x64', 'Windows 11', 'Windows 11 x64', 'Windows 11 x64 24H2') {
                Join-Path $AutoApply $Name | Should -Exist
            }
        }
    }

    It 'does not create template directories when Templates are not used' {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Media') | Out-Null
        Get-OSMedia | Out-Null
        $SetOSDBuilderPathTemplates | Should -Not -Exist
    }

    # KnownBug: Get-OSImport.ps1:194 [string]$RegValueCurrentBuild is never $null, OSMFamily uses an empty CurrentBuild instead of Build
    It 'uses the Build in OSMFamily when CurrentVersion.xml has no CurrentBuild' -Skip {
        New-OSMediaFixture -Path (Join-Path $SetOSDBuilderPathOSMedia 'Media') -CurrentBuild '' | Out-Null
        (Get-OSMedia).OSMFamily | Should -Be 'Client Enterprise x64 26100 en-US'
    }
}

Describe 'Repair-GetOSDMediaTemplateDirectories' {
    BeforeEach {
        $SetOSDBuilderPathTemplates = Join-Path (Join-Path $TestDrive ([guid]::NewGuid().Guid.Substring(0, 8))) 'Templates'
    }

    It 'creates Global, Arch, OS, OS Arch and OS Arch ReleaseId directories for a Client OS' {
        $OSMArch = 'x86'; $UpdateOS = 'Windows 10'; $OSMInstallationType = 'Client'; $OSMMajorVersion = 10; $ReleaseId = '22H2'

        Repair-GetOSDMediaTemplateDirectories

        foreach ($Template in 'Drivers', 'ExtraFiles', 'Registry', 'Scripts') {
            $AutoApply = Join-Path (Join-Path $SetOSDBuilderPathTemplates $Template) 'AutoApply'
            @(Get-ChildItem -Path $AutoApply -Directory).Name | Sort-Object | Should -Be @('Global', 'Global x86', 'Windows 10', 'Windows 10 x86', 'Windows 10 x86 22H2')
        }
    }

    It 'creates only Global, Arch and OS directories for a Server OS' {
        $OSMArch = 'x64'; $UpdateOS = 'Windows Server'; $OSMInstallationType = 'Server Core'; $OSMMajorVersion = 10; $ReleaseId = '24H2'

        Repair-GetOSDMediaTemplateDirectories

        foreach ($Template in 'Drivers', 'ExtraFiles', 'Registry', 'Scripts') {
            $AutoApply = Join-Path (Join-Path $SetOSDBuilderPathTemplates $Template) 'AutoApply'
            @(Get-ChildItem -Path $AutoApply -Directory).Name | Sort-Object | Should -Be @('Global', 'Global x64', 'Windows Server')
        }
    }

    It 'keeps existing directories and their content' {
        $OSMArch = 'x64'; $UpdateOS = 'Windows 11'; $OSMInstallationType = 'Client'; $OSMMajorVersion = 10; $ReleaseId = '24H2'
        $Driver = New-TestFile -Path (Join-Path (Join-Path (Join-Path (Join-Path $SetOSDBuilderPathTemplates 'Drivers') 'AutoApply') 'Global') 'driver.inf')

        Repair-GetOSDMediaTemplateDirectories
        Repair-GetOSDMediaTemplateDirectories

        $Driver.FullName | Should -Exist
        @(Get-ChildItem -Path (Join-Path (Join-Path $SetOSDBuilderPathTemplates 'Scripts') 'AutoApply') -Directory).Count | Should -Be 5
    }
}
