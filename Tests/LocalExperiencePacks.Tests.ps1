BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript -Name 'AllFunctions','InboxApps','LocalExperiencePacks')) {. $Script}

    function New-TestLxp {
        param ($Language, $Version, $MinVersion, [switch]$NoLicense, [string]$LicenseName = 'License.xml', [string]$Directory)
        if (-not $Directory) {$Directory = Join-Path (Join-Path $TestDrive ([guid]::NewGuid())) $Language.ToLower()}
        $Appx = New-TestAppx -Path (Join-Path $Directory "LanguageExperiencePack.$($Language.ToLower()).Neutral.appx") -Name "Microsoft.LanguageExperiencePack$Language" -Version $Version -MinVersion $MinVersion
        if (-not $NoLicense) {New-TestFile -Path (Join-Path $Directory $LicenseName) -Value '<License />' | Out-Null}
        $Appx.FullName
    }
}

Describe 'Get-OSDBuilderServicingBuild' {
    It 'build <Build> is serviced as <Expected>' -ForEach @(
        @{Build = 19041; Expected = 19041}
        @{Build = 19045; Expected = 19041}
        @{Build = 22621; Expected = 22621}
        @{Build = 22631; Expected = 22621}
        @{Build = 26100; Expected = 26100}
        @{Build = 26200; Expected = 26100}
        @{Build = 26300; Expected = 26100}
        @{Build = 28000; Expected = 28000}
    ) {
        Get-OSDBuilderServicingBuild -Build $Build | Should -Be $Expected
    }
}

Describe 'Test-OSDBuilderLocalExperiencePackBuild' {
    It 'LXP <Version> (MinVersion <MinVersion>) on build <Build>: <Expected>' -ForEach @(
        #Microsoft Store packages of the de-DE LXP
        @{Version = '26100.169.270.0'; MinVersion = '10.0.25846.0'; Build = 26200; Expected = $true}
        @{Version = '26100.169.270.0'; MinVersion = '10.0.25846.0'; Build = 26100; Expected = $true}
        @{Version = '28000.2.8.0'; MinVersion = '10.0.27547.0'; Build = 26200; Expected = $false}
        @{Version = '22621.146.465.0'; MinVersion = '10.0.22350.0'; Build = 22631; Expected = $true}
        @{Version = '22621.146.465.0'; MinVersion = '10.0.22350.0'; Build = 26200; Expected = $false}
        @{Version = '26100.169.270.0'; MinVersion = '10.0.25846.0'; Build = 22631; Expected = $false}
        #Local Experience Pack ISO 2206C, the MinVersion is lower than the servicing branch
        @{Version = '19041.29.88.0'; MinVersion = '10.0.18823.0'; Build = 19045; Expected = $true}
        @{Version = '19041.29.88.0'; MinVersion = '10.0.18823.0'; Build = 26200; Expected = $false}
        #No TargetDeviceFamily
        @{Version = '26100.9.1.0'; MinVersion = $null; Build = 26200; Expected = $true}
    ) {
        $Manifest = [PSCustomObject]@{Version = $Version; MinOSVersion = $MinVersion}
        Test-OSDBuilderLocalExperiencePackBuild -Manifest $Manifest -Build $Build | Should -Be $Expected
    }
}

Describe 'Add-OSDBuilderLocalExperiencePack' {
    BeforeEach {
        $script:Provisioned = @()
        Mock Get-AppxProvisionedPackage {$script:Provisioned}
        Mock Add-AppxProvisionedPackage {
            $Manifest = Get-OSDBuilderAppxManifest -Path $PackagePath
            $script:Provisioned += [PSCustomObject]@{DisplayName = $Manifest.Name; Version = $Manifest.Version}
        }
    }

    It 'adds the LXP with its License.xml' {
        $Lxp = New-TestLxp -Language 'nn-NO' -Version '26100.129.249.0' -MinVersion '10.0.25846.0'
        Add-OSDBuilderLocalExperiencePack -Path 'C:\Mount' -PackagePath $Lxp -Build 26200 6>$null | Should -Be 'Added'
        Should -Invoke Add-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {$LicensePath -like '*License.xml'}
    }

    It 'accepts the <ProductId>_License.xml of winget download' {
        $Lxp = New-TestLxp -Language 'de-DE' -Version '26100.169.270.0' -MinVersion '10.0.25846.0' -LicenseName '9P6CT0SLW589_License.xml'
        Add-OSDBuilderLocalExperiencePack -Path 'C:\Mount' -PackagePath $Lxp -Build 26200 6>$null | Should -Be 'Added'
        Should -Invoke Add-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter {$LicensePath -like '*9P6CT0SLW589_License.xml'}
    }

    It 'returns Installed when the same version is provisioned' {
        $Lxp = New-TestLxp -Language 'nn-NO' -Version '26100.129.249.0' -MinVersion '10.0.25846.0'
        $script:Provisioned = @([PSCustomObject]@{DisplayName = 'Microsoft.LanguageExperiencePacknn-NO'; Version = '26100.129.249.0'})
        Add-OSDBuilderLocalExperiencePack -Path 'C:\Mount' -PackagePath $Lxp -Build 26200 6>$null | Should -Be 'Installed'
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }

    It 'updates an older provisioned version' {
        $Lxp = New-TestLxp -Language 'nn-NO' -Version '26100.129.249.0' -MinVersion '10.0.25846.0'
        $script:Provisioned = @([PSCustomObject]@{DisplayName = 'Microsoft.LanguageExperiencePacknn-NO'; Version = '26100.1.0.0'})
        Add-OSDBuilderLocalExperiencePack -Path 'C:\Mount' -PackagePath $Lxp -Build 26200 6>$null | Should -Be 'Added'
    }

    It 'rejects the LXP of the newest Windows build (winget without --os-version)' {
        $Lxp = New-TestLxp -Language 'de-DE' -Version '28000.2.8.0' -MinVersion '10.0.27547.0'
        Add-OSDBuilderLocalExperiencePack -Path 'C:\Mount' -PackagePath $Lxp -Build 26200 6>$null 3>$null | Should -Be 'Failed'
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }

    It 'rejects a Windows 10 LXP for Windows 11' {
        $Lxp = New-TestLxp -Language 'af-ZA' -Version '19041.29.88.0' -MinVersion '10.0.18823.0'
        Add-OSDBuilderLocalExperiencePack -Path 'C:\Mount' -PackagePath $Lxp -Build 26200 6>$null 3>$null | Should -Be 'Failed'
    }

    It 'fails without a license' {
        $Lxp = New-TestLxp -Language 'af-ZA' -Version '26100.3.3.0' -MinVersion '10.0.25846.0' -NoLicense
        $Warnings = (Add-OSDBuilderLocalExperiencePack -Path 'C:\Mount' -PackagePath $Lxp -Build 26200 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Unable to find the License.xml*'
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }

    It 'fails for an app that is not an LXP' {
        $Appx = New-TestAppx -Path (Join-Path (Join-Path $TestDrive 'other') 'Some.App.appx') -Name 'Contoso.App' -Version '1.0.0.0' -MinVersion '10.0.19041.0'
        New-TestFile -Path (Join-Path (Join-Path $TestDrive 'other') 'License.xml') | Out-Null
        Add-OSDBuilderLocalExperiencePack -Path 'C:\Mount' -PackagePath $Appx.FullName -Build 26200 6>$null 3>$null | Should -Be 'Failed'
    }

    It 'fails for a missing file' {
        Add-OSDBuilderLocalExperiencePack -Path 'C:\Mount' -PackagePath (Join-Path $TestDrive 'missing.appx') -Build 26200 6>$null 3>$null | Should -Be 'Failed'
    }

    It 'fails when DISM fails' {
        Mock Add-AppxProvisionedPackage {throw '0x80073cf3 Package failed updates, dependency or conflict validation'}
        $Lxp = New-TestLxp -Language 'nn-NO' -Version '26100.129.249.0' -MinVersion '10.0.25846.0'
        Add-OSDBuilderLocalExperiencePack -Path 'C:\Mount' -PackagePath $Lxp -Build 26200 6>$null 3>$null | Should -Be 'Failed'
    }

    It 'fails when the LXP is not provisioned afterwards' {
        Mock Add-AppxProvisionedPackage {}
        $Lxp = New-TestLxp -Language 'nn-NO' -Version '26100.129.249.0' -MinVersion '10.0.25846.0'
        Add-OSDBuilderLocalExperiencePack -Path 'C:\Mount' -PackagePath $Lxp -Build 26200 6>$null 3>$null | Should -Be 'Failed'
    }
}

Describe 'Add-LocalExperiencePacksOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $OSMajorVersion = 10; $MountDirectory = 'C:\Mount'; $Info = $TestDrive; $OSBuild = '26200'
        $SetOSDBuilderPathContent = Join-Path $TestDrive 'Content'
        $Valid = New-TestLxp -Language 'nn-NO' -Version '26100.129.249.0' -MinVersion '10.0.25846.0' -Directory (Join-Path $SetOSDBuilderPathContent 'IsoExtract\Windows 11 24H2 LXP\LocalExperiencePack\nn-no')
        $Wrong = New-TestLxp -Language 'af-ZA' -Version '22621.5.10.0' -MinVersion '10.0.22350.0' -Directory (Join-Path $SetOSDBuilderPathContent 'IsoExtract\Windows 11 23H2 LXP\LocalExperiencePack\af-za')
        $LocalExperiencePacks = @($Valid, $Wrong) | ForEach-Object {$_.Substring($SetOSDBuilderPathContent.Length + 1)}
        $global:ReapplyLCU = $false
        $script:Provisioned = @()
        Mock Get-AppxProvisionedPackage {$script:Provisioned}
        Mock Add-AppxProvisionedPackage {$script:Provisioned += [PSCustomObject]@{DisplayName = 'Microsoft.LanguageExperiencePacknn-NO'; Version = '26100.129.249.0'}}
    }
    AfterAll {
        Remove-Variable -Name ReapplyLCU -Scope Global -ErrorAction SilentlyContinue
    }

    It 'adds the valid LXP, reapplies the LCU and lists the LXPs that were not added' {
        $Warnings = (Add-LocalExperiencePacksOS 6>$null 3>&1) -join "`n"
        Should -Invoke Add-AppxProvisionedPackage -Times 1 -Exactly
        $global:ReapplyLCU | Should -BeTrue
        $Warnings | Should -BeLike '*1 of 2 were not added*'
        $Warnings | Should -BeLike '*Windows 11 23H2 LXP*'
    }

    It 'does not reapply the LCU when the LXP is already provisioned' {
        $LocalExperiencePacks = @($LocalExperiencePacks[0])
        $script:Provisioned = @([PSCustomObject]@{DisplayName = 'Microsoft.LanguageExperiencePacknn-NO'; Version = '26100.129.249.0'})
        Add-LocalExperiencePacksOS 6>$null 3>$null
        $global:ReapplyLCU | Should -BeFalse
    }

    It 'does nothing in Update-OSMedia' {
        $ScriptName = 'Update-OSMedia'
        Add-LocalExperiencePacksOS 6>$null 3>$null
        Should -Invoke Add-AppxProvisionedPackage -Times 0 -Exactly
    }
}
