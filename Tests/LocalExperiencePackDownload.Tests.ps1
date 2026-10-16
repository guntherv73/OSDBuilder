BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript -Name 'InboxApps','LocalExperiencePacks','LocalExperiencePackDownload')) {. $Script}

    #Microsoft Store display catalog response of the de-DE LXP (9P6CT0SLW589), trimmed to the used fields
    $StoreProduct = Get-Content -Path (Join-Path $FixturesPath 'StoreProduct-de-DE.json') -Raw | ConvertFrom-Json

    #Simulates winget download: the LXP of the --os-version build and the offline license
    function New-WingetDownload {
        param ([string[]]$Arguments, [string]$Version, [string]$MinVersion, [switch]$NoLicense)
        $Id = $Arguments[[array]::IndexOf($Arguments, '--id') + 1]
        $Directory = Join-Path $Arguments[[array]::IndexOf($Arguments, '--download-directory') + 1] $Id
        New-TestAppx -Path (Join-Path $Directory "Microsoft.LanguageExperiencePackde-DE_$($Version)_Desktop_Neutral.appx") -Name 'Microsoft.LanguageExperiencePackde-DE' -Version $Version -MinVersion $MinVersion | Out-Null
        if (-not $NoLicense) {New-TestFile -Path (Join-Path $Directory "$($Id)_License.xml") -Value '<License />' | Out-Null}
        [PSCustomObject]@{ExitCode = 0; Output = $null}
    }
    function New-WingetResult ([int]$ExitCode = 0, [string]$Output) {[PSCustomObject]@{ExitCode = $ExitCode; Output = $Output}}
}

Describe 'Invoke-OSDBuilderWinget' {
    It 'throws when winget.exe is not installed' {
        Mock Get-Command {$null} -ParameterFilter {$Name -eq 'winget.exe'}
        {Invoke-OSDBuilderWinget -Arguments '--version'} | Should -Throw '*winget.exe was not found*'
    }
}

Describe 'Get-OSDBuilderLocalExperiencePackRelease' {
    It '<Release> -> build <Build>' -ForEach @(
        @{Release = 'Windows 11 24H2-26H2'; Build = 26100}
        @{Release = 'Windows 11 22H2-23H2'; Build = 22621}
        @{Release = 'Windows 10 2004-22H2'; Build = 19041}
    ) {
        $Result = Get-OSDBuilderLocalExperiencePackRelease -Release $Release
        $Result.Build | Should -Be $Build
        $Result.OSVersion | Should -Be "10.0.$Build.0"
        $Result.Directory | Should -Be "$Release x64 Local Experience Packs"
    }
}

Describe 'Get-OSDBuilderLocalExperiencePackProduct' {
    BeforeAll {
        Mock Invoke-RestMethod {$StoreProduct}
        $Product = Get-OSDBuilderLocalExperiencePackProduct -Language 'de-DE'
    }

    It 'looks up the product by the PackageFamilyName' {
        Should -Invoke Invoke-RestMethod -Scope Describe -Times 1 -Exactly -ParameterFilter {
            ([uri]$Uri).AbsoluteUri -like '*alternateId=PackageFamilyName&value=Microsoft.LanguageExperiencePackde-DE_8wekyb3d8bbwe*'
        }
    }

    It 'returns the product id of the Deutsch Local Experience Pack' {
        $Product.ProductId | Should -Be '9P6CT0SLW589'
        $Product.Title | Should -Be 'Deutsch Local Experience Pack'
    }

    It 'decodes the Windows.Desktop MinVersion of every package' {
        ($Product.Packages | Where-Object {$_.Version -eq [version]'26100.169.270.0'}).MinVersion | Should -Be ([version]'10.0.25846.0')
        ($Product.Packages | Where-Object {$_.Version -eq [version]'28000.2.8.0'}).MinVersion | Should -Be ([version]'10.0.27547.0')
        ($Product.Packages | Where-Object {$_.Version -eq [version]'19041.80.275.0'}).MinVersion | Should -Be ([version]'10.0.18823.0')
    }

    It 'ignores Windows.Core packages' {
        $Product.Packages.Version | Should -Not -Contain ([version]'45000.22360.1.0')
    }

    It 'returns nothing for a language without LXP' {
        Mock Invoke-RestMethod {[PSCustomObject]@{Products = @()}}
        Get-OSDBuilderLocalExperiencePackProduct -Language 'xx-YY' | Should -BeNullOrEmpty
    }
}

Describe 'Save-OSDBuilderLocalExperiencePack' {
    BeforeEach {
        $SetOSDBuilderPathContent = Join-Path $TestDrive ([guid]::NewGuid())
        $GetOSDBuilderPathContentIsoExtract = Join-Path $SetOSDBuilderPathContent 'IsoExtract'
        $Destination = Join-Path (Join-Path (Join-Path (Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows 11 24H2-26H2 x64 Local Experience Packs') 'LocalExperiencePack') 'de-de') 'LanguageExperiencePack.de-de.Neutral.appx'
        Mock Invoke-RestMethod {$StoreProduct}
        Mock Invoke-OSDBuilderWinget {New-WingetResult -Output 'usage: winget download [--os-version] [--platform]'} -ParameterFilter {$Arguments -contains '--help'}
        Mock Invoke-OSDBuilderWinget {New-WingetDownload -Arguments $Arguments -Version '26100.169.270.0' -MinVersion '10.0.25846.0'} -ParameterFilter {$Arguments -notcontains '--help'}
    }

    It 'downloads the LXP of the servicing branch with winget --os-version' {
        Save-OSDBuilderLocalExperiencePack -Language 'de-de' 6>$null 3>$null
        Should -Invoke Invoke-OSDBuilderWinget -Times 1 -Exactly -ParameterFilter {
            (($Arguments -join ' ') -like 'download --id 9P6CT0SLW589 --source msstore*') -and
            (($Arguments -join ' ') -like '*--platform Windows.Desktop --os-version 10.0.26100.0*')
        }
    }

    It 'saves the LXP and License.xml in the Local Experience Pack ISO layout' {
        Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>$null
        $Destination | Should -Exist
        Join-Path (Split-Path $Destination -Parent) 'License.xml' | Should -Exist
        (Get-OSDBuilderAppxManifest -Path $Destination).Version | Should -Be '26100.169.270.0'
    }

    It 'passes the Microsoft Entra ID account to winget' {
        Save-OSDBuilderLocalExperiencePack -Language 'de-DE' -AuthenticationAccount 'admin@contoso.invalid' 6>$null 3>$null
        Should -Invoke Invoke-OSDBuilderWinget -Times 1 -Exactly -ParameterFilter {($Arguments -join ' ') -like '*--authentication-account admin@contoso.invalid*'}
    }

    It 'does not download an LXP that is already saved' {
        Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>$null
        Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>$null
        Should -Invoke Invoke-OSDBuilderWinget -Times 1 -Exactly -ParameterFilter {$Arguments -notcontains '--help'}
    }

    It 'stops when winget does not support --os-version' {
        Mock Invoke-OSDBuilderWinget {New-WingetResult -Output 'usage: winget download [--platform]'} -ParameterFilter {$Arguments -contains '--help'}
        $Warnings = (Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*does not support --os-version*'
        Should -Invoke Invoke-OSDBuilderWinget -Times 0 -Exactly -ParameterFilter {$Arguments -notcontains '--help'}
    }

    It 'rejects a downloaded LXP of another Windows build' {
        Mock Invoke-OSDBuilderWinget {New-WingetDownload -Arguments $Arguments -Version '28000.2.8.0' -MinVersion '10.0.27547.0'} -ParameterFilter {$Arguments -notcontains '--help'}
        $Warnings = (Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*this is not the LXP for Windows build 26100*'
        $Destination | Should -Not -Exist
    }

    It 'warns when winget does not download the license' {
        Mock Invoke-OSDBuilderWinget {New-WingetDownload -Arguments $Arguments -Version '26100.169.270.0' -MinVersion '10.0.25846.0' -NoLicense} -ParameterFilter {$Arguments -notcontains '--help'}
        $Warnings = (Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*did not download the license*'
        $Destination | Should -Not -Exist
    }

    It 'warns when winget fails' {
        Mock Invoke-OSDBuilderWinget {New-WingetResult -ExitCode 5} -ParameterFilter {$Arguments -notcontains '--help'}
        $Warnings = (Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*winget download failed for de-DE*'
    }

    It 'warns when winget is not installed' {
        Mock Invoke-OSDBuilderWinget {throw 'winget.exe was not found, install the App Installer from the Microsoft Store'} -ParameterFilter {$Arguments -contains '--help'}
        $Warnings = (Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*winget.exe was not found*'
    }

    It 'warns when the Microsoft Store has no LXP for the language' {
        Mock Invoke-RestMethod {[PSCustomObject]@{Products = @()}}
        $Warnings = (Save-OSDBuilderLocalExperiencePack -Language 'af-ZA' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*has no Local Experience Pack for af-ZA*'
        Should -Invoke Invoke-OSDBuilderWinget -Times 0 -Exactly -ParameterFilter {$Arguments -notcontains '--help'}
    }

    It 'saves Windows 10 LXPs with --os-version 10.0.19041.0' {
        Mock Invoke-OSDBuilderWinget {New-WingetDownload -Arguments $Arguments -Version '19041.80.275.0' -MinVersion '10.0.18823.0'} -ParameterFilter {$Arguments -notcontains '--help'}
        Save-OSDBuilderLocalExperiencePack -Language 'de-DE' -Release 'Windows 10 2004-22H2' 6>$null 3>$null
        Should -Invoke Invoke-OSDBuilderWinget -Times 1 -Exactly -ParameterFilter {$Arguments -contains '10.0.19041.0'}
        Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows 10 2004-22H2 x64 Local Experience Packs' | Should -Exist
    }
}
