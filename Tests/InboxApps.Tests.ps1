BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript -Name 'ReleaseSupport','InboxApps','WinRELanguages')) {. $Script}

    function New-TestAppxBundle {
        param ($Path, $Name, $Version, [string[]]$Dependency = @())
        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $Inner = Join-Path $TestDrive "$([guid]::NewGuid()).appx"
        New-TestAppx -Path $Inner -Name $Name -Version $Version -Architecture 'x64' -Dependency $Dependency | Out-Null
        $InnerName = "$($Name)_$($Version)_x64.appx"
        $BundleManifest = '<?xml version="1.0" encoding="utf-8"?>' +
            '<Bundle xmlns="http://schemas.microsoft.com/appx/2013/bundle">' +
            "<Identity Name=`"$Name`" Publisher=`"CN=Microsoft Corporation`" Version=`"$Version`" />" +
            "<Packages><Package Type=`"application`" Version=`"$Version`" Architecture=`"x64`" FileName=`"$InnerName`" /></Packages>" +
            '</Bundle>'
        New-Item -Path (Split-Path $Path -Parent) -ItemType Directory -Force | Out-Null
        $Zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $Entry = $Zip.CreateEntry('AppxMetadata/AppxBundleManifest.xml')
            $Writer = New-Object System.IO.StreamWriter($Entry.Open())
            try {$Writer.Write($BundleManifest)} finally {$Writer.Dispose()}
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Zip, $Inner, $InnerName) | Out-Null
        }
        finally {$Zip.Dispose()}
        Get-Item $Path
    }

    #Bundle with any application and resource packages, Architecture '' writes no Architecture attribute,
    #Missing packages are listed in the bundle manifest but not added to the bundle, EntryName is the escaped zip entry name
    function New-TestAppxBundleCustom {
        param ($Path, $Name, $Version = '1.0.0.0', [hashtable[]]$Packages)
        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $PackageXml = ''
        foreach ($Package in $Packages) {
            $Type = if ($Package.Type) {$Package.Type} else {'application'}
            $ArchAttribute = if ($Package.Architecture) {" Architecture=`"$($Package.Architecture)`""} else {''}
            $PackageXml += "<Package Type=`"$Type`" Version=`"$($Package.Version)`"$ArchAttribute FileName=`"$($Package.FileName)`" />"
        }
        $BundleManifest = '<?xml version="1.0" encoding="utf-8"?>' +
            '<Bundle xmlns="http://schemas.microsoft.com/appx/2013/bundle">' +
            "<Identity Name=`"$Name`" Publisher=`"CN=Microsoft Corporation`" Version=`"$Version`" />" +
            "<Packages>$PackageXml</Packages>" +
            '</Bundle>'
        New-Item -Path (Split-Path $Path -Parent) -ItemType Directory -Force | Out-Null
        if (Test-Path $Path) {Remove-Item -Path $Path -Force}
        $Zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $Entry = $Zip.CreateEntry('AppxMetadata/AppxBundleManifest.xml')
            $Writer = New-Object System.IO.StreamWriter($Entry.Open())
            try {$Writer.Write($BundleManifest)} finally {$Writer.Dispose()}
            foreach ($Package in ($Packages | Where-Object {-not $_.Missing})) {
                $Arch = if ($Package.Architecture) {$Package.Architecture} else {'neutral'}
                $Dependency = if ($Package.Dependency) {$Package.Dependency} else {@()}
                $Inner = Join-Path $TestDrive "$([guid]::NewGuid()).appx"
                New-TestAppx -Path $Inner -Name $Name -Version $Package.Version -Architecture $Arch -Dependency $Dependency | Out-Null
                $EntryName = if ($Package.EntryName) {$Package.EntryName} else {$Package.FileName}
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Zip, $Inner, $EntryName) | Out-Null
            }
        }
        finally {$Zip.Dispose()}
        Get-Item $Path
    }
}

Describe 'Get-OSDBuilderAppxManifest' {
    It 'reads the identity, the dependencies and the MinVersion of an .appx' {
        $Appx = New-TestAppx -Path (Join-Path $TestDrive 'calc.appx') -Name 'Microsoft.WindowsCalculator' -Version '11.2502.2.0' -Architecture 'x64' -MinVersion '10.0.22621.0' -Dependency 'Microsoft.UI.Xaml.2.8','Microsoft.VCLibs.140.00'
        $Manifest = Get-OSDBuilderAppxManifest -Path $Appx.FullName
        $Manifest.Name | Should -Be 'Microsoft.WindowsCalculator'
        $Manifest.Version | Should -Be '11.2502.2.0'
        $Manifest.Architecture | Should -Be 'x64'
        $Manifest.IsBundle | Should -BeFalse
        $Manifest.IsFramework | Should -BeFalse
        $Manifest.MinOSVersion | Should -Be '10.0.22621.0'
        $Manifest.Dependencies.Name | Should -Be @('Microsoft.UI.Xaml.2.8','Microsoft.VCLibs.140.00')
    }

    It 'detects a framework' {
        $Appx = New-TestAppx -Path (Join-Path $TestDrive 'vclibs.appx') -Name 'Microsoft.VCLibs.140.00' -Version '14.0.33519.0' -Architecture 'x86' -Framework
        (Get-OSDBuilderAppxManifest -Path $Appx.FullName).IsFramework | Should -BeTrue
    }

    It 'reads the bundle identity' {
        $Bundle = New-TestAppxBundle -Path (Join-Path $TestDrive 'bundle\notepad.msixbundle') -Name 'Microsoft.WindowsNotepad' -Version '11.2507.26.0'
        $Manifest = Get-OSDBuilderAppxManifest -Path $Bundle.FullName
        $Manifest.IsBundle | Should -BeTrue
        $Manifest.Name | Should -Be 'Microsoft.WindowsNotepad'
        $Manifest.Version | Should -BeNullOrEmpty
    }

    It 'reads the application package of a bundle with -Detailed' {
        $Bundle = New-TestAppxBundle -Path (Join-Path $TestDrive 'bundle2\paint.msixbundle') -Name 'Microsoft.Paint' -Version '11.2508.1.0' -Dependency 'Microsoft.WindowsAppRuntime.1.7'
        $Manifest = Get-OSDBuilderAppxManifest -Path $Bundle.FullName -Detailed
        $Manifest.Version | Should -Be '11.2508.1.0'
        $Manifest.Architecture | Should -Be 'x64'
        $Manifest.Dependencies.Name | Should -Be 'Microsoft.WindowsAppRuntime.1.7'
    }

    It 'returns the bundle identity without version when no application matches the architecture' {
        $Bundle = New-TestAppxBundleCustom -Path (Join-Path (Join-Path $TestDrive 'edge1') 'arm.msixbundle') -Name 'Contoso.Arm' -Packages @(
            @{Version = '2.0.0.0'; Architecture = 'arm64'; FileName = 'Contoso.Arm_2.0.0.0_arm64.appx'}
            @{Type = 'resource'; Version = '2.0.0.0'; Architecture = 'x64'; FileName = 'Contoso.Arm_2.0.0.0_language-de.appx'}
        )
        $Manifest = Get-OSDBuilderAppxManifest -Path $Bundle.FullName -Detailed
        $Manifest.IsBundle | Should -BeTrue
        $Manifest.Name | Should -Be 'Contoso.Arm'
        $Manifest.Version | Should -BeNullOrEmpty
        $Manifest.Architecture | Should -BeNullOrEmpty
        @($Manifest.Dependencies).Count | Should -Be 0
    }

    It 'returns the bundle identity without version when the application package is not in the bundle' {
        $Bundle = New-TestAppxBundleCustom -Path (Join-Path (Join-Path $TestDrive 'edge2') 'missing.msixbundle') -Name 'Contoso.Missing' -Packages @(
            @{Version = '2.0.0.0'; Architecture = 'x64'; FileName = 'Contoso.Missing_2.0.0.0_x64.appx'; Missing = $true}
        )
        $Manifest = Get-OSDBuilderAppxManifest -Path $Bundle.FullName -Detailed
        $Manifest.Name | Should -Be 'Contoso.Missing'
        $Manifest.Version | Should -BeNullOrEmpty
    }

    It 'uses the first architecture of -Architecture that the bundle contains' {
        $Bundle = New-TestAppxBundleCustom -Path (Join-Path (Join-Path $TestDrive 'edge3') 'multi.msixbundle') -Name 'Contoso.Multi' -Packages @(
            @{Version = '3.0.0.64'; Architecture = 'x64'; FileName = 'Contoso.Multi_x64.appx'}
            @{Version = '3.0.0.86'; Architecture = 'x86'; FileName = 'Contoso.Multi_x86.appx'; Dependency = @('Microsoft.VCLibs.140.00')}
        )
        $Manifest = Get-OSDBuilderAppxManifest -Path $Bundle.FullName -Architecture 'arm64', 'x86', 'x64' -Detailed
        $Manifest.Version | Should -Be '3.0.0.86'
        $Manifest.Architecture | Should -Be 'x86'
        $Manifest.Dependencies.Name | Should -Be 'Microsoft.VCLibs.140.00'
        (Get-OSDBuilderAppxManifest -Path $Bundle.FullName -Detailed).Version | Should -Be '3.0.0.64'
    }

    It 'uses an application package without architecture as neutral' {
        $Bundle = New-TestAppxBundleCustom -Path (Join-Path (Join-Path $TestDrive 'edge4') 'neutral.msixbundle') -Name 'Contoso.Neutral' -Packages @(
            @{Version = '4.0.0.0'; Architecture = ''; FileName = 'Contoso.Neutral_4.0.0.0_neutral.appx'}
        )
        $Manifest = Get-OSDBuilderAppxManifest -Path $Bundle.FullName -Detailed
        $Manifest.Version | Should -Be '4.0.0.0'
        $Manifest.Architecture | Should -Be 'neutral'
    }

    It 'finds an application package with an URL encoded zip entry name' {
        $Bundle = New-TestAppxBundleCustom -Path (Join-Path (Join-Path $TestDrive 'edge5') 'escaped.msixbundle') -Name 'Contoso.Escaped' -Packages @(
            @{Version = '5.0.0.0'; Architecture = 'x64'; FileName = 'Contoso Escaped_x64.appx'; EntryName = 'Contoso%20Escaped_x64.appx'}
        )
        (Get-OSDBuilderAppxManifest -Path $Bundle.FullName -Detailed).Version | Should -Be '5.0.0.0'
    }

    It 'returns $null for a bundle with an invalid application package' {
        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $Path = Join-Path (Join-Path $TestDrive 'edge6') 'invalid.msixbundle'
        New-Item -Path (Split-Path $Path -Parent) -ItemType Directory -Force | Out-Null
        $Inner = New-TestFile -Path (Join-Path $TestDrive 'edge6-inner.appx') -Value 'not a zip'
        $Zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $Entry = $Zip.CreateEntry('AppxMetadata/AppxBundleManifest.xml')
            $Writer = New-Object System.IO.StreamWriter($Entry.Open())
            try {$Writer.Write('<Bundle><Identity Name="Contoso.Invalid" /><Packages><Package Type="application" Architecture="x64" FileName="inner.appx" /></Packages></Bundle>')} finally {$Writer.Dispose()}
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Zip, $Inner.FullName, 'inner.appx') | Out-Null
        }
        finally {$Zip.Dispose()}
        $Verbose = (Get-OSDBuilderAppxManifest -Path $Path -Detailed -Verbose 4>&1) | ForEach-Object {"$_"}
        ($Verbose -join "`n") | Should -BeLike "*Unable to read the manifest of $Path*"
        Get-OSDBuilderAppxManifest -Path $Path -Detailed | Should -BeNullOrEmpty
    }

    It 'returns $null for a missing file' {
        Get-OSDBuilderAppxManifest -Path (Join-Path $TestDrive 'missing.appx') | Should -BeNullOrEmpty
    }

    It 'returns $null for a file that is not an app package' {
        $File = New-TestFile -Path (Join-Path $TestDrive 'broken.appx')
        Get-OSDBuilderAppxManifest -Path $File.FullName | Should -BeNullOrEmpty
    }
}

Describe 'Get-OSDBuilderInboxAppsSource' {
    It 'returns the packages directory of the matching release' {
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
        foreach ($Name in 'Windows 11 24H2-26H2 Inbox Apps','Windows 11 22H2-23H2 Inbox Apps') {
            New-Item -Path (Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContent 'InboxApps') $Name) 'packages') -ItemType Directory -Force | Out-Null
        }
        $Result = @(Get-OSDBuilderInboxAppsSource -OSMedia ([PSCustomObject]@{OperatingSystem = 'Windows 11'; ReleaseId = '25H2'}))
        $Result.Count | Should -Be 1
        $Result[0] | Should -BeLike '*Windows 11 24H2-26H2 Inbox Apps*packages'
    }
}

Describe 'Update-InboxAppsOS' {
    BeforeAll {
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'UpdateContent'
        $Packages = Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContent 'InboxApps') 'Windows 11 24H2-26H2 Inbox Apps') 'packages'
        New-TestAppx -Path (Join-Path $Packages 'Microsoft.WindowsCalculator_8wekyb3d8bbwe.appx') -Name 'Microsoft.WindowsCalculator' -Version '11.2502.2.0' -Architecture 'x64' -Dependency 'Microsoft.VCLibs.140.00' | Out-Null
        New-TestFile -Path (Join-Path $Packages 'Microsoft.WindowsCalculator_8wekyb3d8bbwe.xml') | Out-Null
        New-TestAppx -Path (Join-Path $Packages 'Microsoft.BingNews_8wekyb3d8bbwe.appx') -Name 'Microsoft.BingNews' -Version '4.55.1.0' -Architecture 'neutral' | Out-Null
        New-TestAppx -Path (Join-Path $Packages 'Microsoft.Photos_8wekyb3d8bbwe.appx') -Name 'Microsoft.Windows.Photos' -Version '2025.1.0.0' -Architecture 'x64' | Out-Null
        New-TestAppx -Path (Join-Path $Packages 'Microsoft.VCLibs.140.00_14.0.33519.0_x64.appx') -Name 'Microsoft.VCLibs.140.00' -Version '14.0.33519.0' -Architecture 'x64' -Framework | Out-Null
        New-TestAppx -Path (Join-Path $Packages 'Microsoft.VCLibs.140.00_14.0.33519.0_x86.appx') -Name 'Microsoft.VCLibs.140.00' -Version '14.0.33519.0' -Architecture 'x86' -Framework | Out-Null
        New-TestAppx -Path (Join-Path $Packages 'Microsoft.VCLibs.140.00_14.0.30000.0_x64.appx') -Name 'Microsoft.VCLibs.140.00' -Version '14.0.30000.0' -Architecture 'x64' -Framework | Out-Null
        New-TestAppx -Path (Join-Path $Packages 'Microsoft.VCLibs.140.00_14.0.33519.0_arm64.appx') -Name 'Microsoft.VCLibs.140.00' -Version '14.0.33519.0' -Architecture 'arm64' -Framework | Out-Null
    }

    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10; $UpdateOS = 'Windows 11'; $ReleaseId = '25H2'
        $OSInstallationType = 'Client'; $OSArchitecture = 'x64'; $MountDirectory = 'C:\Mount'; $Info = $TestDrive
        $LanguagePacks = @('IsoExtract\de-de.cab'); $LanguageInterfacePacks = $null; $LanguageFeatures = $null; $LocalExperiencePacks = $null
        $RemoveAppx = @()
        Mock Get-OSDBuilderContentPackLanguages {}
        Mock Add-AppxProvisionedPackage {}
        Mock Get-AppxProvisionedPackage {
            [PSCustomObject]@{DisplayName = 'Microsoft.WindowsCalculator'; Version = '11.2400.0.0'; PackageName = 'Microsoft.WindowsCalculator_11.2400.0.0_neutral_~_8wekyb3d8bbwe'}
            [PSCustomObject]@{DisplayName = 'Microsoft.BingNews'; Version = '4.55.1.0'; PackageName = 'Microsoft.BingNews_4.55.1.0_neutral_~_8wekyb3d8bbwe'}
            [PSCustomObject]@{DisplayName = 'Microsoft.Windows.Photos'; Version = '2026.1.0.0'; PackageName = 'Microsoft.Windows.Photos_2026.1.0.0_x64__8wekyb3d8bbwe'}
            [PSCustomObject]@{DisplayName = 'Microsoft.SecHealthUI'; Version = '1000.0.0.0'; PackageName = 'Microsoft.SecHealthUI_1000.0.0.0_x64__8wekyb3d8bbwe'}
        }
    }

    It 'reinstalls a provisioned app with the newest x64 and x86 framework and the license' {
        Update-InboxAppsOS 6>$null
        Should -Invoke Add-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {
            ($PackagePath -like '*Microsoft.WindowsCalculator_8wekyb3d8bbwe.appx') -and
            ($LicensePath -like '*Microsoft.WindowsCalculator_8wekyb3d8bbwe.xml') -and
            (@($DependencyPackagePath).Count -eq 2) -and
            (@($DependencyPackagePath | Where-Object {$_ -like '*14.0.33519.0_x64.appx'}).Count -eq 1) -and
            (@($DependencyPackagePath | Where-Object {$_ -like '*14.0.33519.0_x86.appx'}).Count -eq 1)
        }
    }

    It 'adds an app without a license file with SkipLicense' {
        Update-InboxAppsOS 6>$null
        Should -Invoke Add-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {($PackagePath -like '*Microsoft.BingNews*') -and $SkipLicense}
    }

    It 'keeps a newer app in the image' {
        Update-InboxAppsOS 6>$null
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly -ParameterFilter {$PackagePath -like '*Photos*'}
    }

    It 'does not reinstall an app the Task removes' {
        $RemoveAppx = @('Microsoft.BingNews_4.55.1.0_neutral_~_8wekyb3d8bbwe')
        Update-InboxAppsOS 6>$null
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly -ParameterFilter {$PackagePath -like '*BingNews*'}
    }

    It 'does nothing when no language is added' {
        $LanguagePacks = $null
        Update-InboxAppsOS 6>$null
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }

    It 'does nothing in Update-OSMedia' {
        $ScriptName = 'Update-OSMedia'
        Update-InboxAppsOS 6>$null
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }

    It 'continues with the next app when DISM fails' {
        Mock Add-AppxProvisionedPackage {throw '0x80073cf3'} -ParameterFilter {$PackagePath -like '*Calculator*'}
        Update-InboxAppsOS 6>$null 3>$null 4>$null
        Should -Invoke Add-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {$PackagePath -like '*BingNews*'}
    }

    It 'does nothing when <Case>' -ForEach @(
        @{Case = 'the OS is not Windows 10 or 11'; Variable = 'OSMajorVersion'; Value = 6}
        @{Case = 'the OS is Windows 10'; Variable = 'UpdateOS'; Value = 'Windows 10'}
        @{Case = 'the image is Windows Server'; Variable = 'OSInstallationType'; Value = 'Server'}
    ) {
        Set-Variable -Name $Variable -Value $Value
        Update-InboxAppsOS 6>$null 3>$null
        Should -Invoke Get-AppxProvisionedPackage -Times 0 -Exactly
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }

    It 'reinstalls the apps for <Variable>' -ForEach @(
        @{Variable = 'LanguageInterfacePacks'}
        @{Variable = 'LanguageFeatures'}
        @{Variable = 'LocalExperiencePacks'}
    ) {
        $LanguagePacks = $null
        Set-Variable -Name $Variable -Value @('something')
        Update-InboxAppsOS 6>$null
        Should -Invoke Add-AppxProvisionedPackage -Times 2 -Exactly
    }

    It 'reinstalls the apps for the languages of the OSLanguagePacks ContentPacks' {
        $LanguagePacks = $null
        Mock Get-OSDBuilderContentPackLanguages {'de-de'}
        Update-InboxAppsOS 6>$null
        Should -Invoke Add-AppxProvisionedPackage -Times 2 -Exactly
    }

    It 'writes the log of a failed app' {
        Mock Add-AppxProvisionedPackage {throw '0x80073cf3 conflict'} -ParameterFilter {$PackagePath -like '*Calculator*'}
        $Output = (Update-InboxAppsOS 6>$null 3>&1 4>&1) -join "`n"
        $Output | Should -BeLike '*Inbox Apps: Microsoft.WindowsCalculator could not be reinstalled, 0x80073cf3 conflict*'
        $Output | Should -BeLike '*Update-InboxAppsOS-Microsoft.WindowsCalculator.log*'
    }

    It 'shows the apps that are not in the ISO and newer in the image' {
        $Output = (Update-InboxAppsOS 6>&1 | ForEach-Object {"$_"}) -join "`n"
        $Output | Should -BeLike '*NOT IN ISO*Microsoft.SecHealthUI*'
        $Output | Should -BeLike '*NEWER IN IMAGE*Microsoft.Windows.Photos 2026.1.0.0*'
    }

    Context 'Bundles and dependencies' {
        BeforeAll {
            $SetOSDBuilderPathContent = Join-Path $TestDrive 'BundleContent'
            $BundlePackages = Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContent 'InboxApps') 'Windows 11 24H2-26H2 Inbox Apps') 'packages'
            #The x64 package wins over the bundle and the neutral package
            New-TestAppx -Path (Join-Path $BundlePackages 'Contoso.Pref_x64.appx') -Name 'Contoso.Pref' -Version '1.0.0.64' -Architecture 'x64' | Out-Null
            New-TestAppx -Path (Join-Path $BundlePackages 'Contoso.Pref_neutral.appx') -Name 'Contoso.Pref' -Version '1.0.0.1' -Architecture 'neutral' | Out-Null
            New-TestAppxBundleCustom -Path (Join-Path $BundlePackages 'Contoso.Pref.msixbundle') -Name 'Contoso.Pref' -Packages @(@{Version = '1.0.0.2'; Architecture = 'x64'; FileName = 'Contoso.Pref_x64_inner.appx'}) | Out-Null
            #The bundle wins over the neutral package, its application package has a dependency that is not in the Inbox Apps
            New-TestAppx -Path (Join-Path $BundlePackages 'Contoso.Bundle_neutral.appx') -Name 'Contoso.Bundle' -Version '2.0.0.1' -Architecture 'neutral' | Out-Null
            New-TestAppxBundleCustom -Path (Join-Path $BundlePackages 'Contoso.Bundle.msixbundle') -Name 'Contoso.Bundle' -Packages @(
                @{Version = '2.0.0.64'; Architecture = 'x64'; FileName = 'Contoso.Bundle_x64.appx'; Dependency = @('Microsoft.UI.Xaml.2.8')}
            ) | Out-Null
            New-TestFile -Path (Join-Path $BundlePackages 'Contoso.Bundle.xml') | Out-Null
            #A bundle without an application package for x64, neutral or x86
            New-TestAppxBundleCustom -Path (Join-Path $BundlePackages 'Contoso.Arm.msixbundle') -Name 'Contoso.Arm' -Packages @(@{Version = '3.0.0.0'; Architecture = 'arm64'; FileName = 'Contoso.Arm_arm64.appx'}) | Out-Null
            #An arm64 package is not used for an x64 image
            New-TestAppx -Path (Join-Path $BundlePackages 'Contoso.ArmOnly_arm64.appx') -Name 'Contoso.ArmOnly' -Version '4.0.0.0' -Architecture 'arm64' | Out-Null
        }

        BeforeEach {
            Mock Get-AppxProvisionedPackage {
                [PSCustomObject]@{DisplayName = 'Contoso.Pref'; Version = '1.0.0.0'}
                [PSCustomObject]@{DisplayName = 'Contoso.Bundle'; Version = '2.0.0.0'}
                [PSCustomObject]@{DisplayName = 'Contoso.Arm'; Version = '3.0.0.0'}
                [PSCustomObject]@{DisplayName = 'Contoso.ArmOnly'; Version = '4.0.0.0'}
            }
        }

        It 'prefers the package of the image architecture over a bundle and a neutral package' {
            Update-InboxAppsOS 6>$null 3>$null
            Should -Invoke Add-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {$PackagePath -eq (Join-Path $BundlePackages 'Contoso.Pref_x64.appx')}
            Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly -ParameterFilter {$PackagePath -like '*Contoso.Pref_neutral.appx' -or $PackagePath -like '*Contoso.Pref.msixbundle'}
        }

        It 'reinstalls the bundle with its license and lets DISM use the framework in the image' {
            $Verbose = (Update-InboxAppsOS -Verbose 6>$null 3>$null 4>&1) -join "`n"
            $Verbose | Should -BeLike '*Contoso.Bundle dependency Microsoft.UI.Xaml.2.8 is not in the Inbox Apps, DISM uses the framework in the image*'
            Should -Invoke Add-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {
                ($PackagePath -eq (Join-Path $BundlePackages 'Contoso.Bundle.msixbundle')) -and ($LicensePath -eq (Join-Path $BundlePackages 'Contoso.Bundle.xml')) -and
                (-not $DependencyPackagePath) -and (-not $SkipLicense) -and ($Path -eq 'C:\Mount')
            }
        }

        It 'warns when the application package of a bundle can not be read' {
            $Warnings = (Update-InboxAppsOS 6>$null 3>&1) -join "`n"
            $Warnings | Should -BeLike '*Inbox Apps: Unable to read Contoso.Arm*'
            Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly -ParameterFilter {$PackagePath -like '*Contoso.Arm*'}
        }

        It 'does not use a package of another architecture' {
            $Output = (Update-InboxAppsOS 6>&1 3>$null | ForEach-Object {"$_"}) -join "`n"
            $Output | Should -BeLike '*NOT IN ISO*Contoso.ArmOnly*'
            Should -Invoke Add-AppxProvisionedPackage -Times 2 -Exactly
        }
    }

    It 'warns when the Inbox Apps ISO is not extracted' {
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Empty'
        $Warnings = (Update-InboxAppsOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*No Inbox Apps for Windows 11 25H2*'
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }
}
