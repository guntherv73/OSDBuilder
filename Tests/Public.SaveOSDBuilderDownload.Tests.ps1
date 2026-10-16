BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    $PublicPath = Join-Path $RepoRoot 'Public'
    foreach ($Name in 'Get-OSDBuilder', 'Save-OSDBuilderDownload') {. (Join-Path $PublicPath "$Name.ps1")}

    #A system proxy switches to System.Net.WebClient, the tests run without one
    $SavedDefaultWebProxy = [System.Net.WebRequest]::DefaultWebProxy
    [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy
    $SavedSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

    function New-TestUpdate {
        param ($Title, $UpdateOS = 'Windows 11', $UpdateBuild = '24H2', $UpdateArch = 'x64', $UpdateGroup = 'LCU', $CreationDate = '2026-09-09', $Hash = '')
        $FileName = ($Title -replace '[^A-Za-z0-9]', '').ToLower()
        [PSCustomObject]@{
            Catalog = 'Windows 11'; OSDVersion = '26.9.1'; OSDStatus = ''; UpdateOS = $UpdateOS; UpdateBuild = $UpdateBuild; UpdateArch = $UpdateArch
            UpdateGroup = $UpdateGroup; CreationDate = [datetime]$CreationDate; KBNumber = '5000001'; Title = $Title
            OriginUri = "https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2026/09/$FileName.msu"; Hash = $Hash
        }
    }

    function New-TestOperatingSystem {
        #Get-OSDCloudOperatingSystems of the OSD module
        param ($Version = 'Windows 11', $ReleaseID = '24H2', $Architecture = 'x64', $Activation = 'Volume', $Language = 'en-us')
        $Edition = if ($Activation -eq 'Volume') {'CLIENTBUSINESS_VOL'} else {'CLIENTCONSUMER_RET'}
        $FileName = "26100.4349.250607-1500.ge_release_svc_refresh_$($Edition)_$($Architecture)FRE_$Language.esd"
        [PSCustomObject]@{
            OSDStatus = $null; Name = "$Version $ReleaseID $Architecture $Activation $Language 26100.4349"; Version = $Version; ReleaseID = $ReleaseID
            Architecture = $Architecture; Activation = $Activation; Language = $Language; Build = '26100.4349'; ReleaseDate = [datetime]'2025-06-10'
            FileName = $FileName; Url = "http://dl.delivery.mp.microsoft.com/filestreamingservice/files/00000000-0000-0000-0000-000000000000/$FileName"; SHA1 = 'abc'
        }
    }
}

AfterAll {
    [System.Net.WebRequest]::DefaultWebProxy = $SavedDefaultWebProxy
    [Net.ServicePointManager]::SecurityProtocol = $SavedSecurityProtocol
}

Describe 'Save-OSDBuilderDownload' {
    BeforeEach {
        $Root = Join-Path $TestDrive ([guid]::NewGuid())
        $SetOSDBuilderPathUpdates = Join-Path $Root 'Updates'
        $SetOSDBuilderPathFeatureUpdates = Join-Path $Root 'FeatureUpdates'
        $GetOSDBuilderPathContentOneDrive = Join-Path (Join-Path $Root 'Content') 'OneDrive'
        $SetOSDBuilderPathContent = Join-Path $Root 'Content'

        Mock Get-OSDBuilder {}
        Mock Block-StandardUser {}
        #curl.exe is installed, the download writes the file of --output
        Mock Get-Command {[PSCustomObject]@{Name = 'curl.exe'}} -ParameterFilter {$Name -eq 'curl.exe'}
        Mock Invoke-Expression {
            if ($Command -match '--output "([^"]+)"') {Set-Content -Path $Matches[1] -Value 'curl' -NoNewline}
        }
        #System.Net.WebClient records the downloads
        $WebClientDownloads = [System.Collections.ArrayList]::new()
        Mock New-Object {
            $Client = [PSCustomObject]@{Downloads = $WebClientDownloads}
            $Client | Add-Member -MemberType ScriptMethod -Name DownloadFile -Value {
                param ($Address, $FileName)
                [void]$this.Downloads.Add([PSCustomObject]@{Address = $Address; FileName = $FileName})
                Set-Content -Path $FileName -Value 'webclient' -NoNewline
            }
            $Client
        } -ParameterFilter {$TypeName -eq 'System.Net.WebClient'}
        Mock Start-BitsTransfer {}
        Mock Invoke-WebRequest {}
        Mock Out-GridView {$InputObject | Where-Object {$_}}
    }

    Context 'LocalExperiencePack' {
        BeforeEach {
            Mock Save-OSDBuilderLocalExperiencePack {}
        }

        It 'downloads the Local Experience Packs with Save-OSDBuilderLocalExperiencePack' {
            Save-OSDBuilderDownload -LocalExperiencePack 'nn-NO', 'af-ZA' -LocalExperiencePackRelease 'Windows 11 22H2-23H2' -AuthenticationAccount 'admin@contoso.com'
            Should -Invoke Block-StandardUser -Times 1 -Exactly
            Should -Invoke Save-OSDBuilderLocalExperiencePack -Times 1 -Exactly -ParameterFilter {
                (($Language -join ',') -eq 'nn-NO,af-ZA') -and ($Release -eq 'Windows 11 22H2-23H2') -and ($AuthenticationAccount -eq 'admin@contoso.com')
            }
            Should -Invoke Invoke-Expression -Times 0 -Exactly
        }

        It 'uses Windows 11 24H2-26H2 and no account by default' {
            Save-OSDBuilderDownload -LocalExperiencePack 'de-DE'
            Should -Invoke Save-OSDBuilderLocalExperiencePack -Times 1 -Exactly -ParameterFilter {
                ($Language -eq 'de-DE') -and ($Release -eq 'Windows 11 24H2-26H2') -and (-not $AuthenticationAccount)
            }
        }
    }

    Context 'Content' {
        BeforeEach {
            Mock Save-OSDBuilderContentIso {}
        }

        It 'downloads <IsoName> with Save-OSDBuilderContentIso' -ForEach @(
            @{IsoName = 'Windows 11 24H2-26H2 x64 Languages and Optional Features'}
            @{IsoName = 'Windows 11 22H2-23H2 Inbox Apps'}
            @{IsoName = 'Windows 10 2004-22H2 x64 Local Experience Packs'}
        ) {
            Save-OSDBuilderDownload -ContentDownload $IsoName
            Should -Invoke Save-OSDBuilderContentIso -Times 1 -Exactly -ParameterFilter {$Name -eq $IsoName}
            Should -Invoke Invoke-Expression -Times 0 -Exactly
        }

        It 'downloads <Name> from <Url> with curl.exe' -ForEach @(
            @{Name = 'OneDriveSetup Production'; Url = 'https://go.microsoft.com/fwlink/?linkid=844652'}
            @{Name = 'OneDriveSetup Enterprise'; Url = 'https://go.microsoft.com/fwlink/p/?linkid=860987'}
        ) {
            $Verbose = (Save-OSDBuilderDownload -ContentDownload $Name 4>&1) -join "`n"
            $OneDriveSetup = "$GetOSDBuilderPathContentOneDrive\OneDriveSetup.exe"
            Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter {
                $Command -like "& curl.exe --insecure --location --output `"$OneDriveSetup`" --url `"$Url`"*"
            }
            Should -Invoke Save-OSDBuilderContentIso -Times 0 -Exactly
            Join-Path $GetOSDBuilderPathContentOneDrive 'OneDriveSetup.exe' | Should -Exist
            $Verbose | Should -BeLike "*DownloadUrl: $Url*"
            $Verbose | Should -BeLike '*Complete*'
        }

        It 'downloads OneDriveSetup with System.Net.WebClient without curl.exe' {
            Mock Get-Command {} -ParameterFilter {$Name -eq 'curl.exe'}
            Save-OSDBuilderDownload -ContentDownload 'OneDriveSetup Production' 4>$null
            $WebClientDownloads.Count | Should -Be 1
            $WebClientDownloads[0].Address | Should -Be 'https://go.microsoft.com/fwlink/?linkid=844652'
            $WebClientDownloads[0].FileName | Should -Be "$GetOSDBuilderPathContentOneDrive\OneDriveSetup.exe"
            Should -Invoke Invoke-Expression -Times 0 -Exactly
        }

        It 'downloads with System.Net.WebClient when a system proxy is set' {
            [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy('http://proxy.contoso.com:8080')
            try {
                Save-OSDBuilderDownload -ContentDownload 'OneDriveSetup Production' 4>$null
            }
            finally {
                [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy
            }
            $WebClientDownloads.Count | Should -Be 1
            $WebClientDownloads[0].Address | Should -Be 'https://go.microsoft.com/fwlink/?linkid=844652'
            Should -Invoke Invoke-Expression -Times 0 -Exactly
        }

        It 'warns when OneDriveSetup could not be downloaded' {
            Mock Invoke-Expression {}
            $Warnings = (Save-OSDBuilderDownload -ContentDownload 'OneDriveSetup Enterprise' 4>$null 3>&1) -join "`n"
            $Warnings | Should -BeLike '*Content could not be downloaded*'
        }

        It 'rejects an unknown content' {
            {Save-OSDBuilderDownload -ContentDownload 'OneDriveSetup Insider'} | Should -Throw
        }
    }

    Context 'OSDUpdate' {
        BeforeEach {
            $Updates = @(
                New-TestUpdate -Title '2026-09 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB5000001)' -UpdateGroup 'LCU' -CreationDate '2026-09-09'
                New-TestUpdate -Title '2026-08 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB5000000)' -UpdateGroup 'LCU' -CreationDate '2026-08-12'
                New-TestUpdate -Title 'Servicing Stack Update for Windows 11 Version 24H2 x64' -UpdateGroup 'SSU' -CreationDate '2026-07-01'
                New-TestUpdate -Title 'Setup Dynamic Update for Windows 11 Version 24H2 x64' -UpdateGroup 'SetupDU' -CreationDate '2026-06-01'
                New-TestUpdate -Title 'Safe OS Dynamic Update for Windows 11 Version 24H2 x64' -UpdateGroup 'ComponentDU Critical' -CreationDate '2026-05-01'
                New-TestUpdate -Title 'Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11 Version 24H2 x64' -UpdateGroup 'DotNetCU' -CreationDate '2026-04-01'
                New-TestUpdate -Title 'Security Update for Adobe Flash Player for Windows 10 Version 1809 x64' -UpdateOS 'Windows 10' -UpdateBuild '1809' -UpdateGroup 'AdobeSU' -CreationDate '2020-10-01'
                New-TestUpdate -Title 'Update for Windows 11 Version 24H2 x64 without group' -UpdateGroup '' -CreationDate '2026-03-01'
                New-TestUpdate -Title 'Optional Update for Windows 11 Version 24H2 x64' -UpdateGroup 'Optional' -CreationDate '2026-02-01'
                New-TestUpdate -Title '2026-09 Cumulative Update for Windows 10 Version 22H2 for x86-based Systems (KB5000002)' -UpdateOS 'Windows 10' -UpdateBuild '22H2' -UpdateArch 'x86' -UpdateGroup 'LCU' -CreationDate '2026-09-10'
            )
            Mock Get-OSDUpdates {$Updates}
        }

        It 'returns all updates, newest first, without downloading them' {
            $Result = Save-OSDBuilderDownload 4>$null
            $Result.Count | Should -Be 10
            $Result[0].Title | Should -Be '2026-09 Cumulative Update for Windows 10 Version 22H2 for x86-based Systems (KB5000002)'
            $Result[-1].Title | Should -BeLike 'Security Update for Adobe Flash Player*'
            ($Result[0].PSObject.Properties.Name -join ',') | Should -Be 'Catalog,OSDVersion,OSDStatus,UpdateOS,UpdateBuild,UpdateArch,UpdateGroup,CreationDate,KBNumber,Title'
            Should -Invoke Invoke-Expression -Times 0 -Exactly
        }

        It 'filters by -UpdateOS, -UpdateArch and -UpdateBuild' {
            $Result = Save-OSDBuilderDownload -UpdateOS 'Windows 10' -UpdateArch 'x86' -UpdateBuild '22H2' 4>$null
            @($Result).Count | Should -Be 1
            $Result.Title | Should -BeLike '*KB5000002*'
        }

        It 'filters -UpdateGroup <UpdateGroup>' -ForEach @(
            @{UpdateGroup = 'SSU Servicing Stack Update'; Expected = @('Servicing Stack Update for Windows 11 Version 24H2 x64')}
            @{UpdateGroup = 'LCU Latest Cumulative Update'; Expected = @('2026-09 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB5000001)', '2026-08 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB5000000)')}
            @{UpdateGroup = 'DUSU Setup Dynamic Update'; Expected = @('Setup Dynamic Update for Windows 11 Version 24H2 x64')}
            @{UpdateGroup = 'DUCU Component Dynamic Update'; Expected = @('Safe OS Dynamic Update for Windows 11 Version 24H2 x64')}
            @{UpdateGroup = 'Adobe Flash Player'; UpdateOS = 'Windows 10'; Expected = @('Security Update for Adobe Flash Player for Windows 10 Version 1809 x64')}
            @{UpdateGroup = 'DotNet Framework'; Expected = @('Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11 Version 24H2 x64')}
            @{UpdateGroup = 'Optional'; Expected = @('Update for Windows 11 Version 24H2 x64 without group', 'Optional Update for Windows 11 Version 24H2 x64')}
        ) {
            if (-not $UpdateOS) {$UpdateOS = 'Windows 11'}
            $Result = Save-OSDBuilderDownload -UpdateOS $UpdateOS -UpdateGroup $UpdateGroup 4>$null
            @($Result.Title) | Should -Be $Expected
        }

        It 'returns the updates selected in Out-GridView with -GridView' {
            Mock Out-GridView {$InputObject | Where-Object {$_.UpdateGroup -eq 'SSU'}}
            $Result = Save-OSDBuilderDownload -GridView 4>$null
            Should -Invoke Out-GridView -ParameterFilter {$PassThru -and ($Title -eq 'Select Updates to Download and press OK')}
            $Result.Title | Should -Be 'Servicing Stack Update for Windows 11 Version 24H2 x64'
        }

        It 'downloads the selected updates with curl.exe to the Updates directory' {
            $Selected = $Updates | Where-Object {$_.UpdateGroup -eq 'LCU'}
            $Result = Save-OSDBuilderDownload -UpdateGroup 'LCU Latest Cumulative Update' -UpdateOS 'Windows 11' -Download 4>$null 6>$null
            $Result | Should -BeNullOrEmpty
            Should -Invoke Invoke-Expression -Times 2 -Exactly
            foreach ($Update in ($Selected | Where-Object {$_.UpdateOS -eq 'Windows 11'})) {
                $File = Join-Path $SetOSDBuilderPathUpdates (Split-Path $Update.OriginUri -Leaf)
                $File | Should -Exist
                Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter {
                    $Command -like "& curl.exe --insecure --location --output `"$File`" --url `"$($Update.OriginUri)`"*"
                }
            }
        }

        It 'does not download an update again' {
            $Update = $Updates | Where-Object {$_.UpdateGroup -eq 'SSU'}
            New-TestFile -Path (Join-Path $SetOSDBuilderPathUpdates (Split-Path $Update.OriginUri -Leaf)) | Out-Null
            Save-OSDBuilderDownload -UpdateGroup 'SSU Servicing Stack Update' -Download 4>$null 6>$null
            Should -Invoke Invoke-Expression -Times 0 -Exactly
        }

        It 'downloads with System.Net.WebClient with -WebClient' {
            $Verbose = (Save-OSDBuilderDownload -UpdateGroup 'SSU Servicing Stack Update' -Download -WebClient 4>&1 6>$null) -join "`n"
            $Verbose | Should -BeLike '*Downloading OSDUpdates using System.Net.WebClient*'
            Should -Invoke New-Object -Times 2 -Exactly -ParameterFilter {$TypeName -eq 'System.Net.WebClient'}
            $WebClientDownloads.Count | Should -Be 1
            $WebClientDownloads[0].Address | Should -Be ($Updates | Where-Object {$_.UpdateGroup -eq 'SSU'}).OriginUri
            Should -Invoke Invoke-Expression -Times 0 -Exactly
        }

        It 'checks the SHA1 hash of the download with -CheckFileHash' {
            #Invoke-Expression writes 'curl' to the file
            $Bytes = [System.Security.Cryptography.SHA1]::Create().ComputeHash([System.Text.Encoding]::ASCII.GetBytes('curl'))
            $Updates = @(New-TestUpdate -Title 'Servicing Stack Update' -UpdateGroup 'SSU' -Hash ($Bytes -join ' '))
            Save-OSDBuilderDownload -Download -CheckFileHash 4>$null 6>$null -ErrorVariable HashErrors -ErrorAction SilentlyContinue
            $HashErrors | Should -BeNullOrEmpty
        }

        It 'writes an error when the SHA1 hash of the download does not match' {
            $Updates = @(New-TestUpdate -Title 'Servicing Stack Update' -UpdateGroup 'SSU' -Hash ((1..20) -join ' '))
            Save-OSDBuilderDownload -Download -CheckFileHash 4>$null 6>$null -ErrorVariable HashErrors -ErrorAction SilentlyContinue
            ($HashErrors -join "`n") | Should -BeLike "*Hashes don't match*"
        }
    }

    Context 'OSDUpdateSuperseded' {
        BeforeEach {
            $Updates = @(New-TestUpdate -Title 'Current Update')
            Mock Get-OSDUpdates {$Updates}
            $Current = Join-Path (Join-Path $SetOSDBuilderPathUpdates 'Windows 11') 'Current Update'
            $Old = Join-Path (Join-Path $SetOSDBuilderPathUpdates 'Windows 11') 'Superseded Update'
            New-TestFile -Path (Join-Path $Current 'update.msu') | Out-Null
            New-TestFile -Path (Join-Path $Old 'update.msu') | Out-Null
        }

        It 'lists the superseded updates' {
            #Save-OSDBuilderDownload stops with Break, the loop contains it
            $Output = foreach ($Run in 1) {Save-OSDBuilderDownload -Superseded List 4>$null 3>&1 6>&1}
            $Text = $Output -join "`n"
            $Text | Should -BeLike '*Superseded Updates:*'
            $Text | Should -BeLike "*$Old*"
            $Text | Should -Not -BeLike "*$Current*"
            $Old | Should -Exist
        }

        It 'removes the superseded updates' {
            $Warnings = $(foreach ($Run in 1) {Save-OSDBuilderDownload -Superseded Remove 4>$null 3>&1 6>$null}) -join "`n"
            $Warnings | Should -BeLike "*Deleting $Old*"
            $Old | Should -Not -Exist
            $Current | Should -Exist
        }

        It 'creates the Updates directory' {
            Remove-Item -Path $SetOSDBuilderPathUpdates -Recurse -Force
            foreach ($Run in 1) {Save-OSDBuilderDownload -Superseded List 4>$null 3>$null 6>$null}
            $SetOSDBuilderPathUpdates | Should -Exist
        }

        It 'returns to the loop of the caller after listing the superseded updates' {
            $Runs = 0
            foreach ($Run in 1..2) {
                Save-OSDBuilderDownload -Superseded List 4>$null 3>$null 6>$null
                $Runs++
            }
            $Runs | Should -Be 2
        }
    }

    Context 'FeatureUpdates' {
        BeforeEach {
            $OperatingSystems = @(
                New-TestOperatingSystem -Language 'en-us'
                New-TestOperatingSystem -Language 'de-de'
                New-TestOperatingSystem -Language 'de-de' -Activation 'Retail'
                New-TestOperatingSystem -Language 'en-us' -Version 'Windows 10' -ReleaseID '22H2'
                New-TestOperatingSystem -Language 'en-us' -Architecture 'x86'
            )
            Mock Get-OSDCloudOperatingSystems {$OperatingSystems}
            Mock Get-WindowsImage {
                [PSCustomObject]@{ImagePath = $ImagePath; ImageIndex = 1; ImageName = 'Windows Setup Media'}
                [PSCustomObject]@{ImagePath = $ImagePath; ImageIndex = 2; ImageName = 'Microsoft Windows PE (x64)'}
                [PSCustomObject]@{ImagePath = $ImagePath; ImageIndex = 3; ImageName = 'Microsoft Windows Setup (x64)'}
                [PSCustomObject]@{ImagePath = $ImagePath; ImageIndex = 4; ImageName = 'Windows 11 Enterprise'}
            }
            Mock Expand-WindowsImage {}
            Mock Export-WindowsImage {}
            $Esd = $OperatingSystems[0]
            $EsdFile = Join-Path $SetOSDBuilderPathFeatureUpdates $Esd.FileName
            $EsdDirectory = Join-Path $SetOSDBuilderPathFeatureUpdates ($Esd.FileName -replace '\.esd$')
        }

        It 'downloads the ESD with curl.exe and expands it to the FeatureUpdates directory' {
            $Warnings = (Save-OSDBuilderDownload -FeatureUpdates -SkipGridView -FeatureOS 'Windows 11' -FeatureArch 'x64' -FeatureBuild '24H2' -FeatureEdition 'Business' 6>$null 3>&1) -join "`n"
            Should -Invoke Get-OSDCloudOperatingSystems -Times 1 -Exactly -ParameterFilter {$OSArch -eq 'x64'}
            Should -Invoke Out-GridView -Times 0 -Exactly
            #en-us and de-de Business of Windows 11 24H2 x64
            Should -Invoke Invoke-Expression -Times 2 -Exactly
            Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter {
                $Command -like "& curl.exe --insecure --location --output `"$EsdFile`" --url `"$($Esd.Url)`"*"
            }
            $EsdFile | Should -Exist
            $EsdDirectory | Should -Exist
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {$ImagePath -eq $EsdFile}
            Should -Invoke Expand-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq $EsdFile) -and ($ApplyPath -eq $EsdDirectory) -and ($Index -eq '1')}
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
                ($SourceImagePath -eq $EsdFile) -and ($SourceIndex -eq 2) -and ($DestinationImagePath -eq "$EsdDirectory\sources\boot.wim") -and ($CompressionType -eq 'Max') -and (-not $Setbootable)
            }
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
                ($SourceIndex -eq 3) -and ($DestinationImagePath -eq "$EsdDirectory\sources\boot.wim") -and $Setbootable
            }
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
                ($SourceImagePath -eq $EsdFile) -and ($SourceIndex -eq 4) -and ($DestinationImagePath -eq "$EsdDirectory\sources\install.wim")
            }
            $Warnings | Should -BeLike '*Use Import-OSMedia to import this Feature Update to OSMedia*'
        }

        It 'filters the Consumer edition with -FeatureEdition' {
            Save-OSDBuilderDownload -FeatureUpdates -SkipGridView -FeatureEdition 'Consumer' 6>$null 3>$null
            Should -Invoke Invoke-Expression -Times 1 -Exactly
            Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter {$Command -like "*$($OperatingSystems[2].FileName)*"}
        }

        It 'downloads the ESD files selected in Out-GridView' {
            Mock Out-GridView {$InputObject | Where-Object {$_.UpdateOS -eq 'Windows 10'}}
            Save-OSDBuilderDownload -FeatureUpdates 6>$null 3>$null
            Should -Invoke Out-GridView -ParameterFilter {$PassThru -and ($Title -eq 'Select ESD Files to Download and Build and press OK')}
            Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter {$Command -like "*$($OperatingSystems[3].Url)*"}
            Should -Invoke Invoke-Expression -Times 1 -Exactly
        }

        It 'downloads the ESD of -FeatureLang' {
            Save-OSDBuilderDownload -FeatureUpdates -SkipGridView -FeatureEdition 'Business' -FeatureLang 'de-de' -FeatureOS 'Windows 11' -FeatureArch 'x64' 6>$null 3>$null
            Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter {$Command -like "*$($OperatingSystems[1].FileName)*"}
        }

        It 'downloads only the ESDs of the languages of -FeatureLang' {
            Save-OSDBuilderDownload -FeatureUpdates -SkipGridView -FeatureLang 'de-de' 6>$null 3>$null
            Should -Invoke Invoke-Expression -Times 2 -Exactly
            Should -Invoke Invoke-Expression -Times 0 -Exactly -ParameterFilter {$Command -like "*$($OperatingSystems[0].FileName)*"}
        }

        It 'downloads the ESD with System.Net.WebClient without curl.exe' {
            Mock Get-Command {} -ParameterFilter {$Name -eq 'curl.exe'}
            Save-OSDBuilderDownload -FeatureUpdates -SkipGridView -FeatureOS 'Windows 10' 6>$null 3>$null
            $WebClientDownloads.Count | Should -Be 1
            $WebClientDownloads[0].Address | Should -Be $OperatingSystems[3].Url
            $WebClientDownloads[0].FileName | Should -Be (Join-Path $SetOSDBuilderPathFeatureUpdates $OperatingSystems[3].FileName)
            Should -Invoke Invoke-Expression -Times 0 -Exactly
        }

        It 'does not download or expand an existing ESD again' {
            New-TestFile -Path $EsdFile | Out-Null
            New-TestFile -Path (Join-Path (Join-Path $EsdDirectory 'Sources') 'Install.wim') | Out-Null
            $Verbose = (Save-OSDBuilderDownload -FeatureUpdates -SkipGridView -FeatureOS 'Windows 11' -FeatureArch 'x64' -FeatureEdition 'Business' -FeatureBuild '24H2' 6>$null 3>$null 4>&1) -join "`n"
            Should -Invoke Invoke-Expression -Times 0 -Exactly -ParameterFilter {$Command -like "*$($Esd.FileName)*"}
            Should -Invoke Get-WindowsImage -Times 0 -Exactly -ParameterFilter {$ImagePath -eq $EsdFile}
            $Verbose | Should -BeLike "*Image already exists at $EsdDirectory\Sources\Install.wim*"
        }

        It 'warns and stops when the download fails' {
            Mock Invoke-Expression {}
            $Warnings = $(foreach ($Run in 1) {Save-OSDBuilderDownload -FeatureUpdates -SkipGridView -FeatureOS 'Windows 10' 6>$null 3>&1}) -join "`n"
            $Warnings | Should -BeLike "*Could not complete download of*$($OperatingSystems[3].FileName)*"
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'warns and stops when the ESD information cannot be read' {
            Mock Get-WindowsImage {throw 'The file is not a valid image'}
            $Warnings = $(foreach ($Run in 1) {Save-OSDBuilderDownload -FeatureUpdates -SkipGridView -FeatureOS 'Windows 10' 6>$null 3>&1}) -join "`n"
            $Warnings | Should -BeLike '*Could not get ESD information*'
            Should -Invoke Expand-WindowsImage -Times 0 -Exactly
            Should -Invoke Export-WindowsImage -Times 0 -Exactly
        }
    }
}
