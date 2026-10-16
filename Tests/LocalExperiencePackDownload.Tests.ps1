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

    Context 'winget.exe is installed' {
        BeforeAll {
            #Stands in for winget.exe, writes to the output and the error stream and sets the exit code
            function Invoke-TestWinget {
                $global:OSDBuilderTestWingetArgs = @($args)
                Write-Output "winget $($args -join ' ')"
                Write-Error 'winget stderr'
                $global:LASTEXITCODE = 3
            }
        }

        BeforeEach {
            Mock Get-Command {[PSCustomObject]@{Name = 'winget.exe'; Source = 'Invoke-TestWinget'}} -ParameterFilter {$Name -eq 'winget.exe' -and $CommandType -eq 'Application'}
            $global:OSDBuilderTestWingetArgs = $null
        }

        AfterAll {
            Remove-Variable -Name OSDBuilderTestWingetArgs -Scope Global -ErrorAction SilentlyContinue
        }

        It 'returns the exit code and the output with the error stream with -CaptureOutput' {
            $Result = Invoke-OSDBuilderWinget -Arguments 'download', '--help' -CaptureOutput -ErrorAction SilentlyContinue
            $Result.ExitCode | Should -Be 3
            $Result.Output | Should -BeLike '*winget download --help*'
            $Result.Output | Should -BeLike '*winget stderr*'
            $global:OSDBuilderTestWingetArgs -join ' ' | Should -Be 'download --help'
        }

        It 'writes the output to the console without -CaptureOutput' {
            Mock Out-Host {}
            $Result = Invoke-OSDBuilderWinget -Arguments 'download', '--id', '9P6CT0SLW589' -ErrorAction SilentlyContinue 2>$null
            $Result.ExitCode | Should -Be 3
            $Result.Output | Should -BeNullOrEmpty
            Should -Invoke Out-Host -Times 1 -Exactly -ParameterFilter {"$InputObject" -eq 'winget download --id 9P6CT0SLW589'}
        }
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
        $Result.Release | Should -Be $Release
    }

    It 'rejects an unknown release' {
        {Get-OSDBuilderLocalExperiencePackRelease -Release 'Windows 11 21H2'} | Should -Throw
    }

    It 'requires a release' {
        (Get-Command Get-OSDBuilderLocalExperiencePackRelease).Parameters['Release'].Attributes.Mandatory | Should -Contain $true
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

    It 'warns for an invalid language and continues with the next language' {
        $Warnings = (Save-OSDBuilderLocalExperiencePack -Language 'not a language', 'de-DE' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Local Experience Packs: not a language is not a valid language*'
        $Destination | Should -Exist
    }

    It 'warns when the Microsoft Store can not be queried' {
        Mock Invoke-RestMethod {throw 'The remote name could not be resolved'}
        $Warnings = (Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Unable to query the Microsoft Store for de-DE, The remote name could not be resolved*'
        Should -Invoke Invoke-OSDBuilderWinget -Times 0 -Exactly -ParameterFilter {$Arguments -notcontains '--help'}
    }

    It 'warns when the Microsoft Store has no package for the build' {
        Mock Get-OSDBuilderLocalExperiencePackProduct {
            [PSCustomObject]@{Language = 'de-DE'; ProductId = '9P6CT0SLW589'; Title = 'Deutsch Local Experience Pack'; Packages = @(
                [PSCustomObject]@{PackageFullName = 'x'; Version = [version]'28000.2.8.0'; MinVersion = [version]'10.0.27547.0'}
                #MinVersion newer than the build
                [PSCustomObject]@{PackageFullName = 'y'; Version = [version]'26100.1.1.0'; MinVersion = [version]'10.0.26200.0'}
            )}
        }
        $Warnings = (Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Deutsch Local Experience Pack `[9P6CT0SLW589`] has no package for Windows build 26100*'
        Should -Invoke Invoke-OSDBuilderWinget -Times 0 -Exactly -ParameterFilter {$Arguments -notcontains '--help'}
    }

    It 'downloads again when the saved LXP can not be read' {
        Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>$null
        Set-Content -Path $Destination -Value 'not a zip'
        $Verbose = (Save-OSDBuilderLocalExperiencePack -Language 'de-DE' -Verbose 6>$null 3>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike "*Unable to read $Destination, it is downloaded again*"
        Should -Invoke Invoke-OSDBuilderWinget -Times 2 -Exactly -ParameterFilter {$Arguments -notcontains '--help'}
        (Get-OSDBuilderAppxManifest -Path $Destination).Version | Should -Be '26100.169.270.0'
    }

    It 'downloads again when the saved LXP is older' {
        New-TestAppx -Path $Destination -Name 'Microsoft.LanguageExperiencePackde-DE' -Version '26100.1.1.0' -MinVersion '10.0.25846.0' | Out-Null
        New-TestFile -Path (Join-Path (Split-Path $Destination -Parent) 'License.xml') | Out-Null
        Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>$null
        Should -Invoke Invoke-OSDBuilderWinget -Times 1 -Exactly -ParameterFilter {$Arguments -notcontains '--help'}
        (Get-OSDBuilderAppxManifest -Path $Destination).Version | Should -Be '26100.169.270.0'
    }

    It 'removes an old download directory and the download after saving' {
        $DownloadPath = Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContent 'ISO') 'LocalExperiencePack') '9P6CT0SLW589'
        $Stale = New-TestFile -Path (Join-Path $DownloadPath 'Microsoft.LanguageExperiencePackde-DE_99999.0.0.0_Desktop_Neutral.appx') -Value 'stale'
        Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>$null
        $Stale.FullName | Should -Not -Exist
        $DownloadPath | Should -Not -Exist
        (Get-OSDBuilderAppxManifest -Path $Destination).Version | Should -Be '26100.169.270.0'
    }

    It 'warns when winget does not download an LXP' {
        Mock Invoke-OSDBuilderWinget {New-WingetResult} -ParameterFilter {$Arguments -notcontains '--help'}
        $Warnings = (Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*winget did not download a Local Experience Pack for de-DE*'
        $Destination | Should -Not -Exist
    }

    It 'warns when the downloaded LXP can not be read' {
        Mock Invoke-OSDBuilderWinget {
            $Directory = $Arguments[[array]::IndexOf($Arguments, '--download-directory') + 1]
            New-TestFile -Path (Join-Path $Directory 'Microsoft.LanguageExperiencePackde-DE_26100.169.270.0_Desktop_Neutral.appx') -Value 'not a zip' | Out-Null
            New-TestFile -Path (Join-Path $Directory '9P6CT0SLW589_License.xml') -Value '<License />' | Out-Null
            New-WingetResult
        } -ParameterFilter {$Arguments -notcontains '--help'}
        $Output = (Save-OSDBuilderLocalExperiencePack -Language 'de-DE' -Verbose 6>$null 3>&1 4>&1) -join "`n"
        $Output | Should -BeLike '*Unable to read the AppxManifest of*Microsoft.LanguageExperiencePackde-DE_26100.169.270.0_Desktop_Neutral.appx*'
        $Output | Should -BeLike '*Microsoft.LanguageExperiencePackde-DE_26100.169.270.0_Desktop_Neutral.appx is not the Local Experience Pack of de-DE*'
        $Destination | Should -Not -Exist
    }

    It 'warns when winget downloads the LXP of another language' {
        Mock Invoke-OSDBuilderWinget {
            $Directory = $Arguments[[array]::IndexOf($Arguments, '--download-directory') + 1]
            New-TestAppx -Path (Join-Path $Directory 'Microsoft.LanguageExperiencePackfr-FR_26100.1.1.0_Desktop_Neutral.appx') -Name 'Microsoft.LanguageExperiencePackfr-FR' -Version '26100.1.1.0' -MinVersion '10.0.25846.0' | Out-Null
            New-TestFile -Path (Join-Path $Directory '9P6CT0SLW589_License.xml') -Value '<License />' | Out-Null
            New-WingetResult
        } -ParameterFilter {$Arguments -notcontains '--help'}
        $Warnings = (Save-OSDBuilderLocalExperiencePack -Language 'de-DE' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Microsoft.LanguageExperiencePackfr-FR_26100.1.1.0_Desktop_Neutral.appx is not the Local Experience Pack of de-DE*'
        $Destination | Should -Not -Exist
    }
}
