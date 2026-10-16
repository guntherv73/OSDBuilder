<#
Tests of the ContentPack functions in Private\AllFunctions.ps1: Add-ContentPack and the Add-ContentPack<Type> functions
that apply the content of a ContentPack directory to the mounted install.wim, WinPE, WinRE and WinSE images or the media
#>
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}

    #Arguments of a mocked Windows program (dism, robocopy), the first positional argument is bound to $InputObject
    function Join-ProgramArgument ($InputObject, $RemainingArguments) {
        (@($InputObject) + @($RemainingArguments) | Where-Object {$null -ne $_}) -join ' '
    }
    #Paths built by the module mix \ and / on Linux and macOS
    function ConvertTo-TestPath ([string]$Path) {
        ($Path -replace '\\', '/').TrimEnd('/')
    }
    #An empty directory in TestDrive
    function New-TestDirectory {
        $Path = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        $Path
    }
    #A WinPE, WinRE or WinSE mount directory with Windows\System32
    function New-TestMount ([string]$Name) {
        $Path = Join-Path (New-TestDirectory) $Name
        New-Item -Path (Join-Path $Path 'Windows/System32') -ItemType Directory -Force | Out-Null
        $Path
    }
    $RegFileContent = @(
        'Windows Registry Editor Version 5.00'
        '[HKEY_CURRENT_USER\Software\Contoso]'
        '[HKEY_LOCAL_MACHINE\SOFTWARE\Contoso]'
        '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Contoso]'
        '[HKEY_USERS\.DEFAULT\Control Panel\Desktop]'
    )
}

AfterAll {
    Remove-Variable -Name ReapplyLCU, UpdateLanguageContent, AddTestScriptRan -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Add-ContentPack' {
    BeforeAll {
        $ContentPackFunctions = @(
            'Add-ContentPackMEDIA', 'Add-ContentPackOSDrivers', 'Add-ContentPackOSExtraFiles', 'Add-ContentPackOSCapability',
            'Add-ContentPackOSLanguageFeatures', 'Add-ContentPackOSLanguagePacks', 'Add-ContentPackOSLocalExperiencePacks',
            'Add-ContentPackOSPackages', 'Add-ContentPackOSPoshMods', 'Add-ContentPackOSPoshModsSystem', 'Add-ContentPackOSRegistry',
            'Add-ContentPackOSScripts', 'Add-ContentPackOSStartLayouts', 'Add-ContentPackPEADK', 'Add-ContentPackPEDaRT',
            'Add-ContentPackPEDrivers', 'Add-ContentPackPEExtraFiles', 'Add-ContentPackPEPoshMods', 'Add-ContentPackPEPoshModsSystem',
            'Add-ContentPackPERegistry', 'Add-ContentPackPEScripts'
        )
    }
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $SkipContentPacks = $false
        $UpdateOS = 'Windows 11'; $ReleaseID = '25H2'; $OSArchitecture = 'x64'
        $SetOSDBuilderPathContentPacks = New-TestDirectory
        $ContentPacks = @('_Global', 'Contoso')
        Mock Get-IsTemplatesEnabled {$false}
        foreach ($Name in $ContentPackFunctions) {Mock -CommandName $Name -MockWith {}}
    }

    It '<PackType> applies ALL, the architecture and the release directory of every ContentPack with <Function>' -ForEach @(
        @{PackType = 'MEDIA'; Function = 'Add-ContentPackMEDIA'}
        @{PackType = 'OSDrivers'; Function = 'Add-ContentPackOSDrivers'}
        @{PackType = 'OSExtraFiles'; Function = 'Add-ContentPackOSExtraFiles'}
        @{PackType = 'OSRegistry'; Function = 'Add-ContentPackOSRegistry'}
        @{PackType = 'OSScripts'; Function = 'Add-ContentPackOSScripts'}
        @{PackType = 'OSStartLayout'; Function = 'Add-ContentPackOSStartLayouts'}
        @{PackType = 'PEDrivers'; Function = 'Add-ContentPackPEDrivers'}
        @{PackType = 'PEExtraFiles'; Function = 'Add-ContentPackPEExtraFiles'}
        @{PackType = 'PERegistry'; Function = 'Add-ContentPackPERegistry'}
        @{PackType = 'PEScripts'; Function = 'Add-ContentPackPEScripts'}
    ) {
        Add-ContentPack -PackType $PackType 6>$null
        Should -Invoke $Function -Times 6 -Exactly
        foreach ($ContentPack in $ContentPacks) {
            foreach ($Leaf in 'ALL', 'x64', 'Windows 11 25H2 x64') {
                $Expected = ConvertTo-TestPath (Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContentPacks $ContentPack) $PackType) $Leaf)
                Should -Invoke $Function -Times 1 -Exactly -ParameterFilter {(ConvertTo-TestPath $ContentPackContent) -eq $Expected}
                Test-Path $Expected -PathType Container | Should -BeTrue
            }
        }
    }

    It '<PackType> applies the release directory of every ContentPack with <Function>' -ForEach @(
        @{PackType = 'OSLanguageFeatures'; Function = 'Add-ContentPackOSLanguageFeatures'}
        @{PackType = 'OSLanguagePacks'; Function = 'Add-ContentPackOSLanguagePacks'}
        @{PackType = 'OSLocalExperiencePacks'; Function = 'Add-ContentPackOSLocalExperiencePacks'}
        @{PackType = 'OSPackages'; Function = 'Add-ContentPackOSPackages'}
        @{PackType = 'PEADK'; Function = 'Add-ContentPackPEADK'}
    ) {
        Add-ContentPack -PackType $PackType 6>$null
        Should -Invoke $Function -Times 2 -Exactly
        foreach ($ContentPack in $ContentPacks) {
            $Expected = ConvertTo-TestPath (Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContentPacks $ContentPack) $PackType) 'Windows 11 25H2 x64')
            Should -Invoke $Function -Times 1 -Exactly -ParameterFilter {(ConvertTo-TestPath $ContentPackContent) -eq $Expected}
            Test-Path $Expected -PathType Container | Should -BeTrue
        }
    }

    It 'PEADKLang applies the release directory of PEADKLang as language content' {
        Add-ContentPack -PackType PEADKLang 6>$null
        Should -Invoke Add-ContentPackPEADK -Times 2 -Exactly -ParameterFilter {$Lang -and ($ContentPackContent -like '*PEADKLang?Windows 11 25H2 x64')}
    }

    It 'OSCapability applies the release directory and the RSAT directory' {
        Add-ContentPack -PackType OSCapability 6>$null
        Should -Invoke Add-ContentPackOSCapability -Times 2 -Exactly -ParameterFilter {(-not $RSAT) -and ($ContentPackContent -like '*OSCapability?Windows 11 25H2 x64')}
        Should -Invoke Add-ContentPackOSCapability -Times 2 -Exactly -ParameterFilter {$RSAT -and ($ContentPackContent -like '*OSCapability?Windows 11 25H2 x64 RSAT')}
        Test-Path (Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContentPacks 'Contoso') 'OSCapability') 'Windows 11 25H2 x64 RSAT') | Should -BeTrue
    }

    It 'uses the ContentPack of a compatible release when the release directory is empty' {
        New-TestFile -Path (Join-Path (Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContentPacks 'Contoso') 'OSPackages') 'Windows 11 24H2 x64') 'Package.cab') | Out-Null
        Add-ContentPack -PackType OSPackages 6>$null
        Should -Invoke Add-ContentPackOSPackages -Times 1 -Exactly -ParameterFilter {$ContentPackContent -like '*Contoso?OSPackages?Windows 11 24H2 x64'}
        Should -Invoke Add-ContentPackOSPackages -Times 1 -Exactly -ParameterFilter {$ContentPackContent -like '*_Global?OSPackages?Windows 11 25H2 x64'}
    }

    It 'PEDaRT applies the PEDaRT directory of every ContentPack' {
        Add-ContentPack -PackType PEDaRT 6>$null
        Should -Invoke Add-ContentPackPEDaRT -Times 2 -Exactly
        Should -Invoke Add-ContentPackPEDaRT -Times 1 -Exactly -ParameterFilter {$ContentPackContent -like '*Contoso?PEDaRT'}
        Test-Path (Join-Path (Join-Path $SetOSDBuilderPathContentPacks '_Global') 'PEDaRT') | Should -BeTrue
    }

    It '<PackType> applies ProgramFiles with <Function> and System with <SystemFunction>' -ForEach @(
        @{PackType = 'OSPoshMods'; Function = 'Add-ContentPackOSPoshMods'; SystemFunction = 'Add-ContentPackOSPoshModsSystem'}
        @{PackType = 'PEPoshMods'; Function = 'Add-ContentPackPEPoshMods'; SystemFunction = 'Add-ContentPackPEPoshModsSystem'}
    ) {
        Add-ContentPack -PackType $PackType 6>$null
        Should -Invoke $Function -Times 2 -Exactly -ParameterFilter {$ContentPackContent -like "*${PackType}?ProgramFiles"}
        Should -Invoke $SystemFunction -Times 2 -Exactly -ParameterFilter {$ContentPackContent -like "*${PackType}?System"}
        Test-Path (Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContentPacks 'Contoso') $PackType) 'System') | Should -BeTrue
    }

    It '<PackType> also applies every directory in "<AllSubdirs>" and "x64 Subdirs"' -ForEach @(
        @{PackType = 'OSExtraFiles'; Function = 'Add-ContentPackOSExtraFiles'; AllSubdirs = 'All Subdirs'}
        @{PackType = 'PEExtraFiles'; Function = 'Add-ContentPackPEExtraFiles'; AllSubdirs = 'ALL Subdirs'}
    ) {
        $ContentPacks = @('Contoso')
        $ContentPackPath = Join-Path (Join-Path $SetOSDBuilderPathContentPacks 'Contoso') $PackType
        New-Item -Path (Join-Path (Join-Path $ContentPackPath $AllSubdirs) 'Wallpaper') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path (Join-Path $ContentPackPath 'x64 Subdirs') 'Tools') -ItemType Directory -Force | Out-Null
        Add-ContentPack -PackType $PackType 6>$null
        Should -Invoke $Function -Times 5 -Exactly
        Should -Invoke $Function -Times 1 -Exactly -ParameterFilter {$ContentPackContent -like "*${AllSubdirs}?Wallpaper"}
        Should -Invoke $Function -Times 1 -Exactly -ParameterFilter {$ContentPackContent -like '*x64 Subdirs?Tools'}
    }

    It 'applies the ContentPacks of Windows 10 <ReleaseID>' -ForEach @(
        @{ReleaseID = '1909'}, @{ReleaseID = '20H2'}, @{ReleaseID = '21H1'}, @{ReleaseID = '21H2'}, @{ReleaseID = '22H2'}, @{ReleaseID = '2004'}
    ) {
        $UpdateOS = 'Windows 10'; $ReleaseID = $_.ReleaseID
        Add-ContentPack -PackType OSPackages 6>$null
        Should -Invoke Add-ContentPackOSPackages -Times 2 -Exactly -ParameterFilter {$ContentPackContent -like "*OSPackages?Windows 10 $ReleaseID x64"}
    }

    It 'applies the ContentPacks in New-PEBuild' {
        $ScriptName = 'New-PEBuild'
        Add-ContentPack -PackType PEDrivers 6>$null
        Should -Invoke Add-ContentPackPEDrivers -Times 6 -Exactly
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'Templates are enabled'; Templates = $true; Skip = $false; Script = 'New-OSBuild'; Packs = @('Contoso'); Type = 'OSPackages'}
        @{Case = 'ContentPacks are skipped'; Templates = $false; Skip = $true; Script = 'New-OSBuild'; Packs = @('Contoso'); Type = 'OSPackages'}
        @{Case = 'the script is Update-OSMedia'; Templates = $false; Skip = $false; Script = 'Update-OSMedia'; Packs = @('Contoso'); Type = 'OSPackages'}
        @{Case = 'the Task has no ContentPacks'; Templates = $false; Skip = $false; Script = 'New-OSBuild'; Packs = $null; Type = 'OSPackages'}
        @{Case = 'no PackType is given'; Templates = $false; Skip = $false; Script = 'New-OSBuild'; Packs = @('Contoso'); Type = $null}
    ) {
        $Result = $Templates
        Mock Get-IsTemplatesEnabled {$Result}
        $SkipContentPacks = $Skip; $ScriptName = $Script; $ContentPacks = $Packs
        if ($Type) {Add-ContentPack -PackType $Type 6>$null} else {Add-ContentPack 6>$null}
        foreach ($Name in $ContentPackFunctions) {Should -Invoke $Name -Times 0 -Exactly}
        @(Get-ChildItem -Path $SetOSDBuilderPathContentPacks).Count | Should -Be 0
    }
}

Describe 'Add-ContentPackMEDIA' {
    BeforeEach {
        $Info = $TestDrive; $OS = 'C:\OSBuilds\Build\OS'
        $Content = New-TestDirectory
        $script:Robocopy = [System.Collections.Generic.List[string]]::new()
        Mock robocopy {$script:Robocopy.Add((Join-ProgramArgument $InputObject $RemainingArguments))}
    }

    It 'copies the files to the OS media and lists them' {
        New-TestFile -Path (Join-Path (Join-Path $Content 'sources') 'ei.cfg') | Out-Null
        $Output = (Add-ContentPackMEDIA -ContentPackContent $Content 6>&1) -join "`n"
        $script:Robocopy.Count | Should -Be 1
        $script:Robocopy[0] | Should -BeLike "$Content C:\OSBuilds\Build\OS ``*.``* /s /ndl /xx /b /np /ts /tee /r:0 /w:0 /Log+:*-Add-ContentPackMEDIA.log"
        $Output | Should -BeLike '*ei.cfg*'
    }

    It 'copies nothing from an empty or missing directory' -ForEach @(@{Leaf = ''}, @{Leaf = 'Missing'}) {
        Add-ContentPackMEDIA -ContentPackContent (Join-Path $Content $Leaf) 6>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackOSDrivers' {
    BeforeEach {
        $Info = $TestDrive; $MountDirectory = 'C:\Mount'; $OSMajorVersion = 10
        $Content = New-TestDirectory
        New-TestFile -Path (Join-Path (Join-Path $Content 'Intel') 'netwtw08.inf') | Out-Null
        Mock Add-WindowsDriver {}
        Mock dism {}
    }

    It 'adds the drivers of the directory recursively and unsigned' {
        $Output = (Add-ContentPackOSDrivers -ContentPackContent $Content 6>&1) -join "`n"
        Should -Invoke Add-WindowsDriver -Times 1 -Exactly -ParameterFilter {
            ($Driver -eq $Content) -and ($Path -eq 'C:\Mount') -and $Recurse -and $ForceUnsigned -and ($LogPath -like '*-Add-ContentPackOSDrivers.log')
        }
        $Output | Should -BeLike '*netwtw08.inf*'
    }

    It 'uses dism.exe when OSMajorVersion is 6' {
        $OSMajorVersion = 6
        Add-ContentPackOSDrivers -ContentPackContent $Content 6>$null
        Should -Invoke dism -Times 1 -Exactly -ParameterFilter {($InputObject -eq '/Image:C:\Mount') -and ($RemainingArguments -contains "/Driver:$Content") -and ($RemainingArguments -contains '/ForceUnsigned')}
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
    }

    It 'adds nothing from an empty directory' {
        Add-ContentPackOSDrivers -ContentPackContent (New-TestDirectory) 6>$null
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
        Should -Invoke dism -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackOSExtraFiles' {
    BeforeEach {
        $Info = $TestDrive; $MountDirectory = 'C:\Mount'
        $Content = New-TestDirectory
        $script:Robocopy = [System.Collections.Generic.List[string]]::new()
        Mock robocopy {$script:Robocopy.Add((Join-ProgramArgument $InputObject $RemainingArguments))}
    }

    It 'copies the files to the mounted image' {
        New-TestFile -Path (Join-Path (Join-Path $Content 'Windows') 'Web.jpg') | Out-Null
        Add-ContentPackOSExtraFiles -ContentPackContent $Content 6>$null
        $script:Robocopy.Count | Should -Be 1
        $script:Robocopy[0] | Should -BeLike "$Content C:\Mount ``*.``* /s /ndl /xx /b /np /ts /tee /r:0 /w:0 /Log+:*-Add-ContentPackOSExtraFiles.log"
    }

    It 'copies nothing from an empty directory' {
        Add-ContentPackOSExtraFiles -ContentPackContent $Content 6>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackOSCapability' {
    BeforeEach {
        $Info = $TestDrive; $MountDirectory = 'C:\Mount'
        $Content = New-TestDirectory
        New-TestFile -Path (Join-Path $Content 'FoDMetadata_Client.cab') | Out-Null
        $global:ReapplyLCU = $false
        Mock Get-WindowsCapability {
            [PSCustomObject]@{Name = 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'; State = 'NotPresent'}
            [PSCustomObject]@{Name = 'Rsat.Dns.Tools~~~~0.0.1.0'; State = 'Installed'}
            [PSCustomObject]@{Name = 'Language.Basic~~~de-DE~0.0.1.0'; State = 'NotPresent'}
            [PSCustomObject]@{Name = 'Browser.InternetExplorer~~~~0.0.11.0'; State = 'NotPresent'}
            [PSCustomObject]@{Name = 'NetFX3~~~~'; State = 'Installed'}
        }
        Mock Add-WindowsCapability {}
    }

    It 'adds the capabilities that are not present except Language and RSAT from the ContentPack' {
        Add-ContentPackOSCapability -ContentPackContent $Content 6>$null
        Should -Invoke Get-WindowsCapability -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and $LimitAccess}
        Should -Invoke Add-WindowsCapability -Times 1 -Exactly
        Should -Invoke Add-WindowsCapability -Times 1 -Exactly -ParameterFilter {
            ($Name -eq 'Browser.InternetExplorer~~~~0.0.11.0') -and ($Path -eq 'C:\Mount') -and ($Source -eq $Content) -and $LimitAccess -and ($LogPath -like '*-ContentPackOSCapability-Browser.InternetExplorer~~~~0.0.11.0.log')
        }
        $global:ReapplyLCU | Should -BeTrue
    }

    It 'adds only the RSAT capabilities that are not present with -RSAT' {
        Add-ContentPackOSCapability -ContentPackContent $Content -RSAT 6>$null
        Should -Invoke Add-WindowsCapability -Times 1 -Exactly
        Should -Invoke Add-WindowsCapability -Times 1 -Exactly -ParameterFilter {($Name -eq 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0') -and ($Source -eq $Content) -and $LimitAccess}
    }

    It 'does not use -LimitAccess when the DISM module does not support it (RSAT <RSAT>)' -ForEach @(@{RSAT = $false}, @{RSAT = $true}) {
        Mock Get-Command -ParameterFilter {$Name -eq 'Get-WindowsCapability'} {[PSCustomObject]@{Name = 'Get-WindowsCapability'; Parameters = @{Path = $null; Name = $null}}}
        Add-ContentPackOSCapability -ContentPackContent $Content -RSAT:$RSAT 6>$null
        Should -Invoke Get-WindowsCapability -Times 1 -Exactly -ParameterFilter {-not $LimitAccess}
        Should -Invoke Add-WindowsCapability -Times 1 -Exactly -ParameterFilter {(-not $LimitAccess) -and ($Source -eq $Content)}
    }

    It 'continues when a capability is not applicable (0x800f081e, RSAT <RSAT>, LimitAccess <LimitAccess>)' -ForEach @(
        @{RSAT = $false; LimitAccess = $true}, @{RSAT = $true; LimitAccess = $true}, @{RSAT = $false; LimitAccess = $false}, @{RSAT = $true; LimitAccess = $false}
    ) {
        if (-not $LimitAccess) {Mock Get-Command -ParameterFilter {$Name -eq 'Get-WindowsCapability'} {[PSCustomObject]@{Parameters = @{}}}}
        Mock Add-WindowsCapability {throw 'Add-WindowsCapability failed. Error code = 0x800f081e'}
        $Output = (Add-ContentPackOSCapability -ContentPackContent $Content -RSAT:$RSAT 6>$null 3>&1 4>&1) -join "`n"
        $Output | Should -BeLike '*0x800f081e The package is not applicable to this image*'
    }

    It 'warns with the error code and message when a capability fails (RSAT <RSAT>, LimitAccess <LimitAccess>)' -ForEach @(
        @{RSAT = $false; LimitAccess = $true}, @{RSAT = $true; LimitAccess = $true}, @{RSAT = $false; LimitAccess = $false}, @{RSAT = $true; LimitAccess = $false}
    ) {
        if (-not $LimitAccess) {Mock Get-Command -ParameterFilter {$Name -eq 'Get-WindowsCapability'} {[PSCustomObject]@{Parameters = @{}}}}
        Mock Add-WindowsCapability {throw (New-Object System.Runtime.InteropServices.COMException -ArgumentList 'The source files could not be found', -2146498529)}
        $Warnings = (Add-ContentPackOSCapability -ContentPackContent $Content -RSAT:$RSAT 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*-2146498529*'
        $Warnings | Should -BeLike '*The source files could not be found*'
    }

    It 'does nothing when the DISM cmdlets are not available' {
        Mock Get-Command -ParameterFilter {$Name -eq 'Get-WindowsCapability'} {}
        Add-ContentPackOSCapability -ContentPackContent $Content 6>$null
        Should -Invoke Get-WindowsCapability -Times 0 -Exactly
    }

    It 'does nothing without FoDMetadata_Client.cab' {
        Add-ContentPackOSCapability -ContentPackContent (New-TestDirectory) 6>$null
        Should -Invoke Get-WindowsCapability -Times 0 -Exactly
        $global:ReapplyLCU | Should -BeFalse
    }
}

Describe 'Add-ContentPackOSLanguageFeatures' {
    BeforeEach {
        $Info = $TestDrive; $MountDirectory = 'C:\Mount'
        $UpdateOS = 'Windows 11'; $ReleaseId = '25H2'; $OSInstallationType = 'Client'
        $Content = New-TestDirectory
        foreach ($Name in @(
            'Microsoft-Windows-LanguageFeatures-Speech-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-InternationalFeatures-Germany-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-Fonts-Thai-Package~31bf3856ad364e35~amd64~~.cab'
        )) {New-TestFile -Path (Join-Path $Content $Name) | Out-Null}
        $global:ReapplyLCU = $false
        $script:Capability = [System.Collections.Generic.List[string]]::new()
        $script:Package = [System.Collections.Generic.List[string]]::new()
        Mock Get-OSDBuilderCapabilitySource {}
        Mock Add-OSDBuilderWindowsCapability {$script:Capability.Add($Name); $true}
        Mock Add-WindowsPackage {$script:Package.Add((Split-Path $PackagePath -Leaf))}
    }

    It 'adds Basic, Fonts and Speech with Add-WindowsCapability from a ContentPack with metadata' {
        New-Item -Path (Join-Path $Content 'metadata') -ItemType Directory -Force | Out-Null
        Add-ContentPackOSLanguageFeatures -ContentPackContent $Content 6>$null
        $script:Capability | Should -Be @('Language.Basic~~~de-DE~0.0.1.0', 'Language.Fonts.Thai~~~und-THAI~0.0.1.0', 'Language.Speech~~~de-DE~0.0.1.0')
        Should -Invoke Add-OSDBuilderWindowsCapability -Times 3 -Exactly -ParameterFilter {
            ($Path -eq 'C:\Mount') -and ((ConvertTo-TestPath $Source[0]) -eq (ConvertTo-TestPath $Content)) -and ($LogPath -like '*-ContentPackOSLanguageFeatures-*.cab.log')
        }
        $script:Package | Should -Be @('Microsoft-Windows-InternationalFeatures-Germany-Package~31bf3856ad364e35~amd64~~.cab')
        $global:ReapplyLCU | Should -BeTrue
    }

    It 'uses the Features on Demand repository of the Languages and Optional Features ISO' {
        $Repository = New-TestDirectory
        New-Item -Path (Join-Path $Repository 'metadata') -ItemType Directory -Force | Out-Null
        Mock Get-OSDBuilderCapabilitySource {$Repository}
        Add-ContentPackOSLanguageFeatures -ContentPackContent $Content 6>$null
        Should -Invoke Add-OSDBuilderWindowsCapability -Times 3 -Exactly -ParameterFilter {$Source -contains $Repository}
        Should -Invoke Get-OSDBuilderCapabilitySource -Times 1 -Exactly -ParameterFilter {($OSMedia.OperatingSystem -eq 'Windows 11') -and ($OSMedia.ReleaseId -eq '25H2') -and ($OSMedia.InstallationType -eq 'Client')}
    }

    It 'adds Basic before Fonts before the other packages before Speech with Add-WindowsPackage without a repository' {
        $Warnings = @(Add-ContentPackOSLanguageFeatures -ContentPackContent $Content 6>$null 3>&1)
        $Warnings.Count | Should -Be 0
        Should -Invoke Add-OSDBuilderWindowsCapability -Times 0 -Exactly
        $script:Package[0] | Should -BeLike '*LanguageFeatures-Basic-de-de*'
        $script:Package[1] | Should -BeLike '*LanguageFeatures-Fonts-Thai*'
        $script:Package[2] | Should -BeLike '*InternationalFeatures-Germany*'
        $script:Package[3] | Should -BeLike '*LanguageFeatures-Speech-de-de*'
        Should -Invoke Add-WindowsPackage -Times 4 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and ($LogPath -like '*-ContentPackOSLanguageFeatures-*.log')}
    }

    It 'falls back to Add-WindowsPackage when Add-WindowsCapability fails' {
        New-Item -Path (Join-Path $Content 'metadata') -ItemType Directory -Force | Out-Null
        Mock Add-OSDBuilderWindowsCapability {$false}
        $Warnings = (Add-ContentPackOSLanguageFeatures -ContentPackContent $Content 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Add-WindowsCapability failed, adding Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab with Add-WindowsPackage*'
        $script:Package.Count | Should -Be 4
    }

    It 'continues when a package is not applicable (0x800f081e)' {
        Mock Add-WindowsPackage {throw 'Error 0x800f081e'}
        $Verbose = (Add-ContentPackOSLanguageFeatures -ContentPackContent $Content 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*-ContentPackOSLanguageFeatures-*'
    }

    It 'adds nothing without a mounted image' {
        $MountDirectory = $null
        Add-ContentPackOSLanguageFeatures -ContentPackContent $Content 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        Should -Invoke Add-OSDBuilderWindowsCapability -Times 0 -Exactly
        $global:ReapplyLCU | Should -BeFalse
    }

    It 'adds nothing from an empty directory' {
        Add-ContentPackOSLanguageFeatures -ContentPackContent (New-TestDirectory) 6>$null
        Should -Invoke Get-OSDBuilderCapabilitySource -Times 0 -Exactly
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackOSLanguagePacks' {
    BeforeEach {
        $Info = $TestDrive; $MountDirectory = 'C:\Mount'
        $Content = New-TestDirectory
        New-TestFile -Path (Join-Path $Content 'Microsoft-Windows-Client-Language-Pack_x64_de-de.cab') -Value ('x' * 2000) | Out-Null
        New-TestFile -Path (Join-Path $Content 'Microsoft-Windows-Client-Language-Pack_x64_fr-fr.cab') -Value ('x' * 4000) | Out-Null
        New-TestFile -Path (Join-Path (Join-Path $Content 'Sub') 'Microsoft-Windows-Client-Language-Pack_x64_it-it.cab') | Out-Null
        New-TestFile -Path (Join-Path $Content 'readme.txt') | Out-Null
        $global:ReapplyLCU = $false; $global:UpdateLanguageContent = $false
        $script:Package = [System.Collections.Generic.List[string]]::new()
        Mock Add-WindowsPackage {$script:Package.Add((Split-Path $PackagePath -Leaf))}
    }

    It 'adds the .cab Language Packs of the directory, largest first, and updates the language content' {
        Add-ContentPackOSLanguagePacks -ContentPackContent $Content 6>$null
        $script:Package | Should -Be @('Microsoft-Windows-Client-Language-Pack_x64_fr-fr.cab', 'Microsoft-Windows-Client-Language-Pack_x64_de-de.cab')
        Should -Invoke Add-WindowsPackage -Times 2 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and ($LogPath -like '*-ContentPackOSLanguagePacks-Microsoft-Windows-Client-Language-Pack_x64_*.cab.log')}
        $global:ReapplyLCU | Should -BeTrue
        $global:UpdateLanguageContent | Should -BeTrue
    }

    It 'continues when a package is not applicable (0x800f081e)' {
        Mock Add-WindowsPackage {throw 'Error 0x800f081e'}
        $Verbose = (Add-ContentPackOSLanguagePacks -ContentPackContent $Content 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        Should -Invoke Add-WindowsPackage -Times 2 -Exactly
    }

    It 'adds nothing without a mounted image' {
        $MountDirectory = ''
        Add-ContentPackOSLanguagePacks -ContentPackContent $Content 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }

    It 'adds nothing from an empty directory' {
        Add-ContentPackOSLanguagePacks -ContentPackContent (New-TestDirectory) 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        $global:UpdateLanguageContent | Should -BeFalse
    }
}

Describe 'Add-ContentPackOSLocalExperiencePacks' {
    BeforeEach {
        $Info = $TestDrive; $MountDirectory = 'C:\Mount'; $OSBuild = '26200'
        $Content = New-TestDirectory
        New-TestFile -Path (Join-Path (Join-Path $Content 'de-de') 'LanguageExperiencePack.de-de.Neutral.appx') | Out-Null
        New-TestFile -Path (Join-Path (Join-Path $Content 'fr-fr') 'LanguageExperiencePack.fr-fr.Neutral.appx') | Out-Null
        New-TestFile -Path (Join-Path (Join-Path $Content 'apps') 'Microsoft.WindowsCalculator.appx') | Out-Null
        $global:ReapplyLCU = $false
        $script:Result = @{de = 'Added'; fr = 'Installed'}
        Mock Add-OSDBuilderLocalExperiencePack {if ($PackagePath -like '*de-de*') {$script:Result.de} else {$script:Result.fr}}
    }

    It 'adds only the Local Experience Packs for the build of the image' {
        Add-ContentPackOSLocalExperiencePacks -ContentPackContent $Content 6>$null
        Should -Invoke Add-OSDBuilderLocalExperiencePack -Times 2 -Exactly
        Should -Invoke Add-OSDBuilderLocalExperiencePack -Times 1 -Exactly -ParameterFilter {
            ($Path -eq 'C:\Mount') -and ($PackagePath -like '*de-de?LanguageExperiencePack.de-de.Neutral.appx') -and ($Build -eq 26200) -and ($LogPath -like '*-ContentPackOSLocalExperiencePacks-LanguageExperiencePack.de-de.Neutral.appx.log')
        }
        Should -Invoke Add-OSDBuilderLocalExperiencePack -Times 0 -Exactly -ParameterFilter {$PackagePath -like '*Calculator*'}
        $global:ReapplyLCU | Should -BeTrue
    }

    It 'does not reapply the LCU when no LXP was added' {
        $script:Result = @{de = 'Installed'; fr = 'Failed'}
        Add-ContentPackOSLocalExperiencePacks -ContentPackContent $Content 6>$null
        $global:ReapplyLCU | Should -BeFalse
    }

    It 'adds nothing without a mounted image' {
        $MountDirectory = $null
        Add-ContentPackOSLocalExperiencePacks -ContentPackContent $Content 6>$null
        Should -Invoke Add-OSDBuilderLocalExperiencePack -Times 0 -Exactly
    }

    It 'adds nothing from an empty directory' {
        Add-ContentPackOSLocalExperiencePacks -ContentPackContent (New-TestDirectory) 6>$null
        Should -Invoke Add-OSDBuilderLocalExperiencePack -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackOSPackages' {
    BeforeEach {
        $Info = $TestDrive; $MountDirectory = 'C:\Mount'
        $Content = New-TestDirectory
        New-TestFile -Path (Join-Path $Content 'b-Package.cab') | Out-Null
        New-TestFile -Path (Join-Path (Join-Path $Content 'Sub') 'a-Package.cab') | Out-Null
        New-TestFile -Path (Join-Path $Content 'readme.txt') | Out-Null
        $global:ReapplyLCU = $false
        $script:Package = [System.Collections.Generic.List[string]]::new()
        Mock Add-WindowsPackage {$script:Package.Add((Split-Path $PackagePath -Leaf))}
    }

    It 'adds every .cab of the directory and its subdirectories by name' {
        Add-ContentPackOSPackages -ContentPackContent $Content 6>$null
        $script:Package | Should -Be @('a-Package.cab', 'b-Package.cab')
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {($Path -eq 'C:\Mount') -and ($LogPath -like '*-ContentPackOSPackages-b-Package.cab.log')}
        $global:ReapplyLCU | Should -BeTrue
    }

    It 'continues when a package is not applicable (0x800f081e)' {
        Mock Add-WindowsPackage {throw 'Error 0x800f081e'}
        $Verbose = (Add-ContentPackOSPackages -ContentPackContent $Content 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        Should -Invoke Add-WindowsPackage -Times 2 -Exactly
    }

    It 'adds nothing without a mounted image' {
        $MountDirectory = $null
        Add-ContentPackOSPackages -ContentPackContent $Content 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        $global:ReapplyLCU | Should -BeFalse
    }

    It 'adds nothing from an empty directory' {
        Add-ContentPackOSPackages -ContentPackContent (New-TestDirectory) 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackOSPoshMods' {
    BeforeEach {
        $Info = $TestDrive; $MountDirectory = 'C:\Mount'
        $Content = New-TestDirectory
        $script:Robocopy = [System.Collections.Generic.List[string]]::new()
        Mock robocopy {$script:Robocopy.Add((Join-ProgramArgument $InputObject $RemainingArguments))}
    }

    It 'copies the modules to Program Files and warns about the deprecation' {
        New-TestFile -Path (Join-Path (Join-Path $Content 'Contoso') 'Contoso.psm1') | Out-Null
        $Warnings = (Add-ContentPackOSPoshMods -ContentPackContent $Content 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*OSPoshMods is being deprecated*'
        $script:Robocopy[0] | Should -BeLike "$Content C:\Mount\Program Files\WindowsPowerShell\Modules ``*.``* /s *-Add-ContentPackOSPoshMods.log"
    }

    It 'copies nothing from an empty directory' {
        Add-ContentPackOSPoshMods -ContentPackContent $Content 6>$null 3>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackOSPoshModsSystem' {
    BeforeEach {
        $Info = $TestDrive; $MountDirectory = 'C:\Mount'
        $Content = New-TestDirectory
        $script:Robocopy = [System.Collections.Generic.List[string]]::new()
        Mock robocopy {$script:Robocopy.Add((Join-ProgramArgument $InputObject $RemainingArguments))}
    }

    It 'copies the modules to System32 and warns about the deprecation' {
        New-TestFile -Path (Join-Path (Join-Path $Content 'Contoso') 'Contoso.psm1') | Out-Null
        $Warnings = (Add-ContentPackOSPoshModsSystem -ContentPackContent $Content 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*OSPoshModsSystem is being deprecated*'
        $script:Robocopy[0] | Should -BeLike "$Content C:\Mount\Windows\System32\WindowsPowerShell\v1.0\Modules ``*.``* /s *-Add-ContentPackOSPoshModsSystem.log"
    }

    It 'copies nothing from an empty directory' {
        Add-ContentPackOSPoshModsSystem -ContentPackContent $Content 6>$null 3>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackOSRegistry' {
    BeforeEach {
        $Info = $TestDrive
        $MountDirectory = New-TestDirectory
        foreach ($Hive in 'Users/Default/NTUser.dat', 'Windows/System32/Config/DEFAULT', 'Windows/System32/Config/SOFTWARE', 'Windows/System32/Config/SYSTEM') {
            New-TestFile -Path (Join-Path $MountDirectory $Hive) | Out-Null
        }
        $Content = New-TestDirectory
        New-TestFile -Path (Join-Path (Join-Path $Content 'Contoso') 'Settings.reg') -Value ($RegFileContent -join [Environment]::NewLine) | Out-Null
        $script:Temp = $env:TEMP
        $env:TEMP = New-TestDirectory
        Mock Get-Random {4242}
        $script:Reg = [System.Collections.Generic.List[string]]::new()
        $script:Imported = [System.Collections.Generic.List[string]]::new()
        Mock Start-Process {
            $Arguments = @($ArgumentList)
            $script:Reg.Add($Arguments -join ' ')
            if ($Arguments[0] -eq 'import') {$script:Imported.Add((Get-Content -Path $Arguments[1].Trim('"') -Raw))}
        }
        Mock Dismount-OSDOfflineRegistry {}
    }
    AfterEach {
        $env:TEMP = $script:Temp
    }

    It 'loads the offline registry hives of the mounted image' {
        Add-ContentPackOSRegistry -ContentPackContent $Content 6>$null
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {($FilePath -eq 'reg') -and ($ArgumentList -like 'load HKLM\OfflineDefaultUser *NTUser.dat')}
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {$ArgumentList -like 'load HKLM\OfflineDefault *DEFAULT'}
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {$ArgumentList -like 'load HKLM\OfflineSoftware *SOFTWARE'}
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {$ArgumentList -like 'load HKLM\OfflineSystem *SYSTEM'}
        Should -Invoke Dismount-OSDOfflineRegistry -Times 1 -Exactly -ParameterFilter {$MountPath -eq $MountDirectory}
    }

    It 'imports the .reg files with the keys of the offline hives' {
        Add-ContentPackOSRegistry -ContentPackContent $Content 6>$null
        $script:Imported.Count | Should -Be 1
        $script:Imported[0] | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineDefaultUser\Software\Contoso`]*'
        $script:Imported[0] | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineSoftware\Contoso`]*'
        $script:Imported[0] | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineSystem\CurrentControlSet\Services\Contoso`]*'
        $script:Imported[0] | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineDefault\Control Panel\Desktop`]*'
        $script:Imported[0] | Should -Not -BeLike '*HKEY_CURRENT_USER*'
        Test-Path (Join-Path $env:TEMP '4242') | Should -BeFalse
    }

    It 'loads only the hives that exist' {
        Remove-Item -Path (Join-Path $MountDirectory 'Users') -Recurse -Force
        Remove-Item -Path (Join-Path $MountDirectory 'Windows/System32/Config/DEFAULT') -Force
        Add-ContentPackOSRegistry -ContentPackContent $Content 6>$null
        Should -Invoke Start-Process -Times 0 -Exactly -ParameterFilter {$ArgumentList -like 'load HKLM\OfflineDefault*'}
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {$ArgumentList -like 'load HKLM\OfflineSoftware *'}
    }

    It 'shows the content of the .reg files with -ShowRegContent' {
        $Output = (Add-ContentPackOSRegistry -ContentPackContent $Content -ShowRegContent 6>&1) -join "`n"
        $Output | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineSoftware\Contoso`]*'
    }

    It 'imports nothing from an empty directory' {
        Add-ContentPackOSRegistry -ContentPackContent (New-TestDirectory) 6>$null
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Dismount-OSDOfflineRegistry -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackOSScripts' {
    BeforeEach {
        $Content = New-TestDirectory
        $global:AddTestScriptRan = @()
    }

    It 'runs every .ps1 of the directory and its subdirectories' {
        New-TestFile -Path (Join-Path $Content 'First.ps1') -Value '$global:AddTestScriptRan += @("First")' | Out-Null
        New-TestFile -Path (Join-Path (Join-Path $Content 'Sub') 'Second.ps1') -Value '$global:AddTestScriptRan += @("Second")' | Out-Null
        New-TestFile -Path (Join-Path $Content 'readme.txt') -Value 'not a script' | Out-Null
        Add-ContentPackOSScripts -ContentPackContent $Content 6>$null
        @($global:AddTestScriptRan | Sort-Object) | Should -Be @('First', 'Second')
    }

    It 'runs nothing from an empty directory' {
        Add-ContentPackOSScripts -ContentPackContent $Content 6>$null
        $global:AddTestScriptRan.Count | Should -Be 0
    }
}

Describe 'Add-ContentPackOSStartLayouts' {
    BeforeEach {
        $Content = New-TestDirectory
        $MountDirectory = New-TestDirectory
        $Shell = Join-Path $MountDirectory 'Users/Default/AppData/Local/Microsoft/Windows/Shell'
        New-Item -Path $Shell -ItemType Directory -Force | Out-Null
        $Destination = Join-Path $Shell 'LayoutModification.xml'
    }

    It 'copies the .xml of the directory to LayoutModification.xml of the Default User' {
        New-TestFile -Path (Join-Path $Content 'Contoso.xml') -Value '<LayoutModificationTemplate Contoso="1" />' | Out-Null
        New-TestFile -Path (Join-Path (Join-Path $Content 'Sub') 'Other.xml') -Value '<Other />' | Out-Null
        Add-ContentPackOSStartLayouts -ContentPackContent $Content 6>$null
        Get-Content $Destination | Should -Be '<LayoutModificationTemplate Contoso="1" />'
    }

    It 'warns when the Start Layout cannot be copied' {
        New-TestFile -Path (Join-Path $Content 'Contoso.xml') | Out-Null
        Mock Copy-Item {throw 'Access to the path is denied'}
        $Warnings = (Add-ContentPackOSStartLayouts -ContentPackContent $Content 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Access to the path is denied*'
    }

    It 'copies nothing from an empty directory' {
        Add-ContentPackOSStartLayouts -ContentPackContent $Content 6>$null
        Test-Path $Destination | Should -BeFalse
    }
}

Describe 'Add-ContentPackPEADK' {
    BeforeEach {
        $Info = $TestDrive; $ScriptName = 'New-OSBuild'
        $MountWinPE = 'C:\MountWinPE'; $MountWinRE = 'C:\MountWinRE'; $MountWinSE = 'C:\MountWinSE'
        $Content = New-TestDirectory
        New-TestFile -Path (Join-Path $Content 'WinPE-Setup.cab') | Out-Null
        New-TestFile -Path (Join-Path $Content 'WinPE-WMI.cab') -Value ('x' * 4000) | Out-Null
        New-TestFile -Path (Join-Path $Content 'WinPE-SecureStartup.cab') -Value ('x' * 2000) | Out-Null
        #The packages of the subdirectories ("$ContentPackContent\*\*" -Recurse) are returned by a mock:
        #PowerShell 7 on Linux returns the files of the directory for a wildcard path with -Recurse
        $Lang = Join-Path $Content 'de-de'
        $script:SubPackages = @(
            [PSCustomObject]@{Name = 'lp.cab'; FullName = (Join-Path $Lang 'lp.cab'); Length = 1000}
            foreach ($Name in 'WinPE-WMI_de-de.cab', 'WinPE-Setup_de-de.cab', 'WinPE-WiFi-Package_de-de.cab', 'WinPE-LegacySetup_de-de.cab', 'WinPE-Rejuv_de-de.cab') {
                [PSCustomObject]@{Name = $Name; FullName = (Join-Path $Lang $Name); Length = 3000}
            }
        )
        Mock Get-ChildItem -ParameterFilter {"$Path".EndsWith('\*\*')} {$script:SubPackages}
        $global:ReapplyLCU = $false; $global:UpdateLanguageContent = $false
        $script:Added = [System.Collections.Generic.List[string]]::new()
        Mock Add-WindowsPackage {$script:Added.Add("$Path|$(Split-Path $PackagePath -Leaf)")}
        function Get-Added ([string]$Mount) {
            @($script:Added | Where-Object {$_ -like "$Mount|*"} | ForEach-Object {($_ -split '\|')[1]})
        }
    }

    It 'adds the packages of the directory except Setup to WinPE, WinRE and WinSE' {
        Add-ContentPackPEADK -ContentPackContent $Content 6>$null
        foreach ($Mount in $MountWinPE, $MountWinRE, $MountWinSE) {
            (Get-Added $Mount)[0..1] | Should -Be @('WinPE-WMI.cab', 'WinPE-SecureStartup.cab')
        }
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly -ParameterFilter {$PackagePath -like '*WinPE-Setup.cab'}
        Should -Invoke Add-WindowsPackage -ParameterFilter {$LogPath -like '*-ContentPackPEADK-WinPE-WMI.cab.log'} -Times 3 -Exactly
        $global:ReapplyLCU | Should -BeFalse
    }

    It 'adds lp.cab first and only the packages of the subdirectories that fit the image' {
        Add-ContentPackPEADK -ContentPackContent $Content 6>$null
        (Get-Added $MountWinPE) | Select-Object -Skip 2 | Should -Be @('lp.cab', 'WinPE-WMI_de-de.cab')
        @(Get-Added $MountWinRE | Select-Object -Skip 2)[0] | Should -Be 'lp.cab'
        @(Get-Added $MountWinRE | Select-Object -Skip 3 | Sort-Object) | Should -Be @('WinPE-Rejuv_de-de.cab', 'WinPE-WiFi-Package_de-de.cab', 'WinPE-WMI_de-de.cab')
        @(Get-Added $MountWinSE | Select-Object -Skip 2)[0] | Should -Be 'lp.cab'
        @(Get-Added $MountWinSE | Select-Object -Skip 3 | Sort-Object) | Should -Be @('WinPE-Setup_de-de.cab', 'WinPE-WMI_de-de.cab')
    }

    It 'updates the language content with -Lang' {
        Add-ContentPackPEADK -ContentPackContent $Content -Lang 6>$null
        $global:ReapplyLCU | Should -BeTrue
        $global:UpdateLanguageContent | Should -BeTrue
    }

    It 'adds nothing to WinRE and WinSE when only WinPE is mounted' {
        $MountWinRE = $null; $MountWinSE = ''
        Add-ContentPackPEADK -ContentPackContent $Content 6>$null
        Should -Invoke Add-WindowsPackage -Times 4 -Exactly
        Should -Invoke Add-WindowsPackage -Times 4 -Exactly -ParameterFilter {$Path -eq 'C:\MountWinPE'}
    }

    It 'continues when a package is not applicable (0x800f081e)' {
        Mock Add-WindowsPackage {throw 'Error 0x800f081e'}
        $Verbose = (Add-ContentPackPEADK -ContentPackContent $Content 6>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
        $Verbose | Should -BeLike '*-ContentPackPEADK-lp.cab.log*'
        Should -Invoke Add-WindowsPackage -Times 15 -Exactly
    }

    It 'adds nothing from an empty directory' {
        Add-ContentPackPEADK -ContentPackContent (New-TestDirectory) -Lang 6>$null
        Should -Invoke Get-ChildItem -Times 0 -Exactly -ParameterFilter {"$Path".EndsWith('\*\*')}
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        $global:UpdateLanguageContent | Should -BeFalse
    }

    Context 'New-PEBuild' {
        BeforeEach {
            $ScriptName = 'New-PEBuild'; $MountDirectory = 'C:\Mount'; $WinPEOutput = 'WinPE'
            $MountWinPE = $null; $MountWinRE = $null; $MountWinSE = $null
            New-TestFile -Path (Join-Path $Content 'lp.cab') | Out-Null
        }

        It 'adds lp.cab first, then the packages, then lp.cab and the packages of the subdirectories to a WinPE source (<Output>)' -ForEach @(
            @{Output = 'WinPE'}, @{Output = 'MDT'}, @{Output = 'Recovery'}
        ) {
            $WinPEOutput = $Output; $SourceWim = 'WinPE'
            Add-ContentPackPEADK -ContentPackContent $Content 6>$null
            Get-Added 'C:\Mount' | Should -Be @('lp.cab', 'WinPE-WMI.cab', 'WinPE-SecureStartup.cab', 'lp.cab', 'WinPE-WMI_de-de.cab')
            Should -Invoke Add-WindowsPackage -Times 5 -Exactly -ParameterFilter {$LogPath -like '*-ContentPackPEADK-*.cab.log'}
        }

        It 'adds the packages of the directory except Setup to a WinRE source' {
            $SourceWim = 'WinRE'
            Add-ContentPackPEADK -ContentPackContent $Content 6>$null
            @(Get-Added 'C:\Mount')[0..2] | Should -Be @('lp.cab', 'WinPE-WMI.cab', 'WinPE-SecureStartup.cab')
            Should -Invoke Add-WindowsPackage -Times 0 -Exactly -ParameterFilter {$PackagePath -like '*Setup.cab'}
        }

        It 'adds lp.cab and the packages of the subdirectories except Setup to a WinRE source' {
            $SourceWim = 'WinRE'
            Add-ContentPackPEADK -ContentPackContent $Content 6>$null
            @(Get-Added 'C:\Mount' | Select-Object -Skip 3)[0] | Should -Be 'lp.cab'
            @(Get-Added 'C:\Mount' | Select-Object -Skip 4 | Sort-Object) | Should -Be @('WinPE-Rejuv_de-de.cab', 'WinPE-WiFi-Package_de-de.cab', 'WinPE-WMI_de-de.cab')
        }

        It 'continues when a package is not applicable (0x800f081e)' {
            $SourceWim = 'WinPE'
            Mock Add-WindowsPackage {throw 'Error 0x800f081e'}
            $Verbose = (Add-ContentPackPEADK -ContentPackContent $Content 6>$null 4>&1) -join "`n"
            $Verbose | Should -BeLike '*0x800f081e The package is not applicable to this image*'
            Should -Invoke Add-WindowsPackage -Times 5 -Exactly
        }

        It 'adds nothing without a mounted image' {
            $MountDirectory = $null; $SourceWim = 'WinPE'
            Add-ContentPackPEADK -ContentPackContent $Content 6>$null
            Should -Invoke Add-WindowsPackage -Times 0 -Exactly
        }
    }
}

Describe 'Add-ContentPackPEDaRT' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSArchitecture = 'x64'
        $Content = New-TestDirectory
        $Cab = (New-TestFile -Path (Join-Path $Content 'Toolsx64.cab')).FullName
        New-TestFile -Path (Join-Path $Content 'DartConfig8.dat') -Value 'DartConfig8' | Out-Null
        $MountWinPE = New-TestMount 'WinPE'; $MountWinRE = New-TestMount 'WinRE'; $MountWinSE = New-TestMount 'WinSE'
        foreach ($Mount in $MountWinPE, $MountWinRE, $MountWinSE) {
            New-TestFile -Path (Join-Path $Mount 'Windows/System32/winpeshl.ini') -Value ('[LaunchApps]', '%windir%\system32\netstart.exe, -prompt' -join [Environment]::NewLine) | Out-Null
        }
        Mock expand.exe {}
    }

    It 'expands DaRT to WinPE, WinRE and WinSE' {
        Add-ContentPackPEDaRT -ContentPackContent $Content 6>$null
        foreach ($Mount in $MountWinPE, $MountWinRE, $MountWinSE) {
            Should -Invoke expand.exe -Times 1 -Exactly -ParameterFilter {((ConvertTo-TestPath $InputObject) -eq (ConvertTo-TestPath $Cab)) -and ($RemainingArguments -contains $Mount)}
        }
    }

    It 'copies DartConfig8.dat as DartConfig.dat to every image' {
        Add-ContentPackPEDaRT -ContentPackContent $Content 6>$null
        foreach ($Mount in $MountWinPE, $MountWinRE, $MountWinSE) {
            Get-Content (Join-Path $Mount 'Windows/System32/DartConfig.dat') | Should -Be 'DartConfig8'
        }
    }

    It 'copies DartConfig.dat to every image' {
        Remove-Item -Path (Join-Path $Content 'DartConfig8.dat') -Force
        New-TestFile -Path (Join-Path $Content 'DartConfig.dat') -Value 'DartConfig' | Out-Null
        Add-ContentPackPEDaRT -ContentPackContent $Content 6>$null
        foreach ($Mount in $MountWinPE, $MountWinRE, $MountWinSE) {
            Get-Content (Join-Path $Mount 'Windows/System32/DartConfig.dat') | Should -Be 'DartConfig'
        }
    }

    It 'copies DartConfig.dat to WinRE when only WinRE is mounted' {
        $MountWinPE = $null; $MountWinSE = $null
        Add-ContentPackPEDaRT -ContentPackContent $Content 6>$null
        Get-Content (Join-Path $MountWinRE 'Windows/System32/DartConfig.dat') | Should -Be 'DartConfig8'
    }

    It 'starts DaRT from WinRE with network and removes winpeshl.ini from WinPE and WinSE in New-OSBuild' {
        Add-ContentPackPEDaRT -ContentPackContent $Content 6>$null
        Test-Path (Join-Path $MountWinPE 'Windows/System32/winpeshl.ini') | Should -BeFalse
        Test-Path (Join-Path $MountWinSE 'Windows/System32/winpeshl.ini') | Should -BeFalse
        Get-Content (Join-Path $MountWinRE 'Windows/System32/winpeshl.ini') | Should -Be @('[LaunchApps]', '%windir%\system32\netstart.exe, -network')
    }

    It 'starts DaRT with network in a New-PEBuild Recovery image' {
        $ScriptName = 'New-PEBuild'; $WinPEOutput = 'Recovery'
        $MountDirectory = $MountWinRE; $MountWinPE = $null; $MountWinRE = $null; $MountWinSE = $null
        Add-ContentPackPEDaRT -ContentPackContent $Content 6>$null
        Get-Content (Join-Path $MountDirectory 'Windows/System32/winpeshl.ini') | Should -Be @('[LaunchApps]', '%windir%\system32\netstart.exe, -network')
        Should -Invoke expand.exe -Times 0 -Exactly
    }

    It 'keeps winpeshl.ini in a New-PEBuild <Output> image' -ForEach @(@{Output = 'WinPE'}, @{Output = 'MDT'}) {
        $ScriptName = 'New-PEBuild'; $WinPEOutput = $Output
        $MountDirectory = $MountWinPE; $MountWinPE = $null; $MountWinRE = $null; $MountWinSE = $null
        Add-ContentPackPEDaRT -ContentPackContent $Content 6>$null
        Get-Content (Join-Path $MountDirectory 'Windows/System32/winpeshl.ini') | Should -Be @('[LaunchApps]', '%windir%\system32\netstart.exe, -prompt')
    }

    It 'warns when the DaRT cab cannot be read' {
        $script:TestPathCount = 0
        Mock Test-Path -ParameterFilter {$Path -like '*Toolsx64.cab'} {$script:TestPathCount++; $script:TestPathCount -eq 1}
        $Warnings = (Add-ContentPackPEDaRT -ContentPackContent $Content 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Microsoft DaRT do not exist in *Toolsx64.cab*'
        Should -Invoke expand.exe -Times 0 -Exactly
    }

    It 'does nothing without Tools<Arch>.cab of the architecture' -ForEach @(@{Arch = 'x86'}, @{Arch = 'arm64'}) {
        $OSArchitecture = $Arch
        Add-ContentPackPEDaRT -ContentPackContent $Content 6>$null
        Should -Invoke expand.exe -Times 0 -Exactly
        Test-Path (Join-Path $MountWinPE 'Windows/System32/winpeshl.ini') | Should -BeTrue
    }
}

Describe 'Add-ContentPackPEDrivers' {
    BeforeEach {
        $Info = $TestDrive; $OSMajorVersion = 10
        $MountWinPE = 'C:\MountWinPE'; $MountWinRE = 'C:\MountWinRE'; $MountWinSE = 'C:\MountWinSE'
        $Content = New-TestDirectory
        New-TestFile -Path (Join-Path (Join-Path $Content 'Intel') 'e1d68x64.inf') | Out-Null
        Mock Add-WindowsDriver {}
        Mock dism {}
    }

    It 'adds the drivers to WinPE, WinRE and WinSE' {
        $Output = (Add-ContentPackPEDrivers -ContentPackContent $Content 6>&1) -join "`n"
        foreach ($Mount in 'C:\MountWinPE', 'C:\MountWinRE', 'C:\MountWinSE') {
            Should -Invoke Add-WindowsDriver -Times 1 -Exactly -ParameterFilter {
                ($Path -eq $Mount) -and ($Driver -eq $Content) -and $Recurse -and $ForceUnsigned -and ($LogPath -like '*-Add-ContentPackPEDrivers.log')
            }
        }
        $Output | Should -BeLike '*e1d68x64.inf*'
    }

    It 'uses dism.exe when OSMajorVersion is 6' {
        $OSMajorVersion = 6
        Add-ContentPackPEDrivers -ContentPackContent $Content 6>$null
        foreach ($Mount in 'C:\MountWinPE', 'C:\MountWinRE', 'C:\MountWinSE') {
            Should -Invoke dism -Times 1 -Exactly -ParameterFilter {($InputObject -eq "/Image:$Mount") -and ($RemainingArguments -contains "/Driver:$Content")}
        }
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
    }

    It 'adds the drivers only to the mounted images (OSMajorVersion <Major>)' -ForEach @(@{Major = 10}, @{Major = 6}) {
        $OSMajorVersion = $Major; $MountWinRE = $null; $MountWinSE = $null
        Add-ContentPackPEDrivers -ContentPackContent $Content 6>$null
        if ($Major -eq 6) {Should -Invoke dism -Times 1 -Exactly} else {Should -Invoke Add-WindowsDriver -Times 1 -Exactly -ParameterFilter {$Path -eq 'C:\MountWinPE'}}
    }

    It 'adds nothing from an empty directory' {
        Add-ContentPackPEDrivers -ContentPackContent (New-TestDirectory) 6>$null
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackPEExtraFiles' {
    BeforeEach {
        $Info = $TestDrive
        $MountWinPE = 'C:\MountWinPE'; $MountWinRE = 'C:\MountWinRE'; $MountWinSE = 'C:\MountWinSE'
        $Content = New-TestDirectory
        $script:Robocopy = [System.Collections.Generic.List[string]]::new()
        Mock robocopy {$script:Robocopy.Add((Join-ProgramArgument $InputObject $RemainingArguments))}
    }

    It 'copies the files to WinPE, WinRE and WinSE' {
        New-TestFile -Path (Join-Path (Join-Path $Content 'Windows') 'Tool.exe') | Out-Null
        Add-ContentPackPEExtraFiles -ContentPackContent $Content 6>$null
        $script:Robocopy.Count | Should -Be 3
        $script:Robocopy[0] | Should -BeLike "$Content C:\MountWinPE ``*.``* /S /B /COPY:D /NODCOPY /XJ /FP /NS /NC /NDL /NJH /NJS /NP /TEE /XX /R:0 /W:0 /LOG+:*-Add-ContentPackPEExtraFiles.log"
        $script:Robocopy[1] | Should -BeLike "$Content C:\MountWinRE *"
        $script:Robocopy[2] | Should -BeLike "$Content C:\MountWinSE *"
    }

    It 'copies only to the mounted images' {
        New-TestFile -Path (Join-Path $Content 'Tool.exe') | Out-Null
        $MountWinPE = $null; $MountWinRE = $null
        Add-ContentPackPEExtraFiles -ContentPackContent $Content 6>$null
        $script:Robocopy.Count | Should -Be 1
        $script:Robocopy[0] | Should -BeLike "$Content C:\MountWinSE *"
    }

    It 'copies nothing from an empty directory' {
        Add-ContentPackPEExtraFiles -ContentPackContent $Content 6>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackPEPoshMods' {
    BeforeEach {
        $Info = $TestDrive
        $MountWinPE = 'C:\MountWinPE'; $MountWinRE = 'C:\MountWinRE'; $MountWinSE = 'C:\MountWinSE'
        $Content = New-TestDirectory
        $script:Robocopy = [System.Collections.Generic.List[string]]::new()
        Mock robocopy {$script:Robocopy.Add((Join-ProgramArgument $InputObject $RemainingArguments))}
    }

    It 'copies the modules to Program Files of WinPE, WinRE and WinSE' {
        New-TestFile -Path (Join-Path (Join-Path $Content 'Contoso') 'Contoso.psm1') | Out-Null
        Add-ContentPackPEPoshMods -ContentPackContent $Content 6>$null
        $script:Robocopy.Count | Should -Be 3
        foreach ($Mount in 'C:\MountWinPE', 'C:\MountWinRE', 'C:\MountWinSE') {
            $script:Robocopy | Where-Object {$_ -like "$Content $Mount\Program Files\WindowsPowerShell\Modules ``*.``* /s *-Add-ContentPackPEPoshMods.log"} | Should -Not -BeNullOrEmpty
        }
    }

    It 'copies only to the mounted images' {
        New-TestFile -Path (Join-Path $Content 'Contoso.psm1') | Out-Null
        $MountWinRE = $null; $MountWinSE = $null
        Add-ContentPackPEPoshMods -ContentPackContent $Content 6>$null
        $script:Robocopy.Count | Should -Be 1
    }

    It 'copies nothing from an empty directory' {
        Add-ContentPackPEPoshMods -ContentPackContent $Content 6>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackPEPoshModsSystem' {
    BeforeEach {
        $Info = $TestDrive
        $MountWinPE = 'C:\MountWinPE'; $MountWinRE = 'C:\MountWinRE'; $MountWinSE = 'C:\MountWinSE'
        $Content = New-TestDirectory
        $script:Robocopy = [System.Collections.Generic.List[string]]::new()
        Mock robocopy {$script:Robocopy.Add((Join-ProgramArgument $InputObject $RemainingArguments))}
    }

    It 'copies the modules to System32 of WinPE, WinRE and WinSE' {
        New-TestFile -Path (Join-Path (Join-Path $Content 'Contoso') 'Contoso.psm1') | Out-Null
        Add-ContentPackPEPoshModsSystem -ContentPackContent $Content 6>$null
        $script:Robocopy.Count | Should -Be 3
        foreach ($Mount in 'C:\MountWinPE', 'C:\MountWinRE', 'C:\MountWinSE') {
            $script:Robocopy | Where-Object {$_ -like "$Content $Mount\Windows\System32\WindowsPowerShell\v1.0\Modules ``*.``* /s *-Add-ContentPackPEPoshModsSystem.log"} | Should -Not -BeNullOrEmpty
        }
    }

    It 'copies only to the mounted images' {
        New-TestFile -Path (Join-Path $Content 'Contoso.psm1') | Out-Null
        $MountWinPE = $null; $MountWinSE = $null
        Add-ContentPackPEPoshModsSystem -ContentPackContent $Content 6>$null
        $script:Robocopy.Count | Should -Be 1
        $script:Robocopy[0] | Should -BeLike "$Content C:\MountWinRE\Windows\System32\*"
    }

    It 'copies nothing from an empty directory' {
        Add-ContentPackPEPoshModsSystem -ContentPackContent $Content 6>$null
        Should -Invoke robocopy -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackPERegistry' {
    BeforeEach {
        $MountWinPE = New-TestMount 'WinPE'; $MountWinRE = New-TestMount 'WinRE'; $MountWinSE = New-TestMount 'WinSE'
        $Content = New-TestDirectory
        New-TestFile -Path (Join-Path $Content 'Settings.reg') -Value ($RegFileContent -join [Environment]::NewLine) | Out-Null
        $script:Temp = $env:TEMP
        $env:TEMP = New-TestDirectory
        Mock Get-Random {4242}
        $script:Imported = [System.Collections.Generic.List[string]]::new()
        Mock Start-Process {
            $Arguments = @($ArgumentList)
            if ($Arguments[0] -eq 'import') {$script:Imported.Add((Get-Content -Path $Arguments[1].Trim('"') -Raw))}
        }
        Mock Mount-OSDOfflineRegistryPE {}
        Mock Dismount-OSDOfflineRegistry {}
    }
    AfterEach {
        $env:TEMP = $script:Temp
    }

    It 'imports the .reg files with the keys of the offline hives into WinPE, WinRE and WinSE' {
        Add-ContentPackPERegistry -ContentPackContent $Content 6>$null
        foreach ($Mount in $MountWinPE, $MountWinRE, $MountWinSE) {
            Should -Invoke Mount-OSDOfflineRegistryPE -Times 1 -Exactly -ParameterFilter {$MountPath -eq $Mount}
            Should -Invoke Dismount-OSDOfflineRegistry -Times 1 -Exactly -ParameterFilter {$MountPath -eq $Mount}
        }
        $script:Imported.Count | Should -Be 3
        foreach ($Item in $script:Imported) {
            $Item | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineDefaultUser\Software\Contoso`]*'
            $Item | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineSoftware\Contoso`]*'
            $Item | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineSystem\CurrentControlSet\Services\Contoso`]*'
            $Item | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineDefault\Control Panel\Desktop`]*'
        }
        Should -Invoke Start-Process -Times 3 -Exactly -ParameterFilter {($FilePath -eq 'reg') -and ($ArgumentList[0] -eq 'import')}
        Test-Path (Join-Path $env:TEMP '4242') | Should -BeFalse
    }

    It 'shows the content of the .reg files with -ShowRegContent' {
        $Output = @(Add-ContentPackPERegistry -ContentPackContent $Content -ShowRegContent 6>&1) | Where-Object {"$_" -eq '[HKEY_LOCAL_MACHINE\OfflineSoftware\Contoso]'}
        @($Output).Count | Should -Be 3
    }

    It 'imports only into WinPE when WinRE is not mounted' {
        $MountWinRE = $null
        Add-ContentPackPERegistry -ContentPackContent $Content 6>$null
        $script:Imported.Count | Should -Be 1
        Should -Invoke Dismount-OSDOfflineRegistry -Times 1 -Exactly -ParameterFilter {$MountPath -eq $MountWinPE}
        Should -Invoke Mount-OSDOfflineRegistryPE -Times 1 -Exactly
    }

    It 'imports into WinPE and WinRE when WinSE is not mounted' {
        $MountWinSE = Join-Path $TestDrive 'MissingWinSE'
        Add-ContentPackPERegistry -ContentPackContent $Content 6>$null
        $script:Imported.Count | Should -Be 2
        Should -Invoke Mount-OSDOfflineRegistryPE -Times 0 -Exactly -ParameterFilter {$MountPath -eq $MountWinSE}
    }

    It 'imports nothing when WinPE is not mounted' {
        $MountWinPE = $null
        Add-ContentPackPERegistry -ContentPackContent $Content 6>$null
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Mount-OSDOfflineRegistryPE -Times 0 -Exactly
    }

    It 'imports nothing from an empty directory' {
        Add-ContentPackPERegistry -ContentPackContent (New-TestDirectory) 6>$null
        Should -Invoke Mount-OSDOfflineRegistryPE -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

Describe 'Add-ContentPackPEScripts' {
    BeforeEach {
        $Content = New-TestDirectory
        $global:AddTestScriptRan = @()
    }

    It 'runs every .ps1 of the directory and its subdirectories' {
        New-TestFile -Path (Join-Path $Content 'First.ps1') -Value '$global:AddTestScriptRan += @("First")' | Out-Null
        New-TestFile -Path (Join-Path (Join-Path $Content 'Sub') 'Second.ps1') -Value '$global:AddTestScriptRan += @("Second")' | Out-Null
        New-TestFile -Path (Join-Path $Content 'readme.txt') -Value 'not a script' | Out-Null
        Add-ContentPackPEScripts -ContentPackContent $Content 6>$null
        @($global:AddTestScriptRan | Sort-Object) | Should -Be @('First', 'Second')
    }

    It 'runs nothing from an empty directory' {
        Add-ContentPackPEScripts -ContentPackContent $Content 6>$null
        $global:AddTestScriptRan.Count | Should -Be 0
    }
}
