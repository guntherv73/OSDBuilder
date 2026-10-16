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

    It 'warns when the Inbox Apps ISO is not extracted' {
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Empty'
        $Warnings = (Update-InboxAppsOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*No Inbox Apps for Windows 11 25H2*'
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }
}
