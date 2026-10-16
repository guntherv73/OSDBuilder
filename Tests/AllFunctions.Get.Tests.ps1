BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}

    #Public OSDBuilder functions used by the Private functions, placeholders so Pester can mock them
    if (-not (Get-Command -Name Get-OSMedia -ErrorAction SilentlyContinue)) {
        function Get-OSMedia {
            [CmdletBinding()]
            param ($OSArch, $OSInstallationType, $OSMajorVersion, $OSReleaseId, $Revision, [switch]$GridView, [switch]$Newest)
            throw 'Get-OSMedia is not loaded, mock it in the test'
        }
    }
    if (-not (Get-Command -Name Get-OSDBuilder -ErrorAction SilentlyContinue)) {
        function Get-OSDBuilder {
            [CmdletBinding()]
            param ([switch]$CreatePaths, [switch]$HideDetails, [switch]$Initialize)
            throw 'Get-OSDBuilder is not loaded, mock it in the test'
        }
    }

    #Content paths are Windows paths, Get-ChildItem is mocked with the objects of a Windows file system
    $ContentRoot = 'C:\OSDBuilder\Content'
    function New-ContentItem {
        param ([string]$FullName, [int]$Length = 1024)
        [PSCustomObject]@{
            Name         = ($FullName -split '\\')[-1]
            FullName     = $FullName
            Length       = $Length
            CreationTime = [datetime]'2026-10-14'
        }
    }
    function New-TaskJson {
        param ([string]$Path, [hashtable]$Task)
        New-Item -Path (Split-Path $Path -Parent) -ItemType Directory -Force | Out-Null
        [PSCustomObject]$Task | ConvertTo-Json | Out-File -FilePath $Path
    }
    #Out-GridView passes everything through, the offered items are collected in $script:GridView
    function Initialize-GridView {
        $script:GridView = New-Object System.Collections.ArrayList
        Mock Out-GridView {[void]$script:GridView.Add($InputObject); $InputObject}
    }
}

Describe 'Get-FeatureUpdateDownloads' {
    BeforeEach {
        $SetOSDBuilderPathFeatureUpdates = Join-Path $TestDrive 'FeatureUpdates'
        New-TestFile -Path (Join-Path $SetOSDBuilderPathFeatureUpdates '26100.4349.250607-1500.ge_release_svc_refresh_CLIENTBUSINESS_VOL_x64FRE_en-us.esd') | Out-Null
        Mock Get-OSDCloudOperatingSystems {
            [PSCustomObject]@{
                Status = $null; ReleaseDate = '2025-06-07'; Name = 'Windows 11 24H2 x64 en-us Volume 26100.4349'; Version = 'Windows 11'; ReleaseID = '24H2'
                Architecture = 'x64'; Language = 'en-us'; Activation = 'Volume'; Build = '26100.4349'
                FileName = '26100.4349.250607-1500.ge_release_svc_refresh_CLIENTBUSINESS_VOL_x64FRE_en-us.esd'
                Url = 'http://dl.delivery.mp.microsoft.com/filestreamingservice/files/client_business_vol_en-us.esd'; SHA1 = '0f0e1d2c3b4a59687766554433221100ffeeddcc'
            }
            [PSCustomObject]@{
                Status = $null; ReleaseDate = '2025-10-01'; Name = 'Windows 11 25H2 x64 de-de Retail 26200.6584'; Version = 'Windows 11'; ReleaseID = '25H2'
                Architecture = 'x64'; Language = 'de-de'; Activation = 'Retail'; Build = '26200.6584'
                FileName = '26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENTCONSUMER_RET_x64FRE_de-de.esd'
                Url = 'http://dl.delivery.mp.microsoft.com/filestreamingservice/files/client_consumer_ret_de-de.esd'; SHA1 = 'aabbccddeeff00112233445566778899aabbccdd'
            }
        }
        $Downloads = @(Get-FeatureUpdateDownloads)
    }

    It 'reads the x64 operating systems of the OSD module newest first' {
        Should -Invoke Get-OSDCloudOperatingSystems -Times 1 -Exactly -ParameterFilter {$OSArch -eq 'x64'}
        $Downloads.Count | Should -Be 2
        $Downloads[0].Title | Should -Be 'Windows 11 25H2 x64 de-de Retail 26200.6584'
        $Downloads[1].Title | Should -Be 'Windows 11 24H2 x64 en-us Volume 26100.4349'
    }

    It 'maps the properties to the OSDBuilder download properties' {
        $Download = $Downloads[1]
        $Download.UpdateOS | Should -Be 'Windows 11'
        $Download.UpdateBuild | Should -Be '24H2'
        $Download.UpdateArch | Should -Be 'x64'
        $Download.CreationDate | Should -Be '2025-06-07'
        $Download.Language | Should -Be 'en-us'
        $Download.Build | Should -Be '26100.4349'
        $Download.OriginUri | Should -Be 'http://dl.delivery.mp.microsoft.com/filestreamingservice/files/client_business_vol_en-us.esd'
        $Download.Hash | Should -Be '0f0e1d2c3b4a59687766554433221100ffeeddcc'
    }

    It 'marks the downloaded feature updates' {
        $Downloads[1].OSDStatus | Should -Be 'Downloaded'
        $Downloads[0].OSDStatus | Should -BeNullOrEmpty
    }

    # KnownBug: Private/AllFunctions.ps1:2948 selects the misspelled property Activaton, the Activation of the operating system is lost
    It 'keeps the Activation of the operating system' -Skip {
        $Downloads[1].Activation | Should -Be 'Volume'
    }
}

Describe 'Get-IsContentPacksEnabled' {
    BeforeEach {
        $script:SetOSDBuilderBackup = $global:SetOSDBuilder
        $global:SetOSDBuilder = [PSCustomObject]@{AllowContentPacks = $true}
        $SetOSDBuilderPathTemplates = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        New-Item -Path $SetOSDBuilderPathTemplates -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        $global:SetOSDBuilder = $script:SetOSDBuilderBackup
    }

    It 'returns $true when ContentPacks are allowed and no Templates exist' {
        Get-IsContentPacksEnabled | Should -BeTrue
    }

    It 'returns $false when ContentPacks are not allowed' {
        $global:SetOSDBuilder.AllowContentPacks = $false
        Get-IsContentPacksEnabled | Should -BeFalse
    }

    It 'returns $false when the Templates contain <_>' -ForEach @('Drivers', 'ExtraFiles', 'Registry', 'Scripts') {
        New-Item -Path (Join-Path $SetOSDBuilderPathTemplates $_) -ItemType Directory -Force | Out-Null
        Get-IsContentPacksEnabled | Should -BeFalse
    }
}

Describe 'Get-IsTemplatesEnabled' {
    BeforeEach {
        $SetOSDBuilderPathTemplates = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        New-Item -Path $SetOSDBuilderPathTemplates -ItemType Directory -Force | Out-Null
    }

    It 'returns $false when no Templates exist' {
        Get-IsTemplatesEnabled | Should -BeFalse
    }

    It 'returns $true when the Templates contain <_>' -ForEach @('Drivers', 'ExtraFiles', 'Registry', 'Scripts') {
        New-Item -Path (Join-Path $SetOSDBuilderPathTemplates $_) -ItemType Directory -Force | Out-Null
        Get-IsTemplatesEnabled | Should -BeTrue
    }
}

Describe 'Get-OSBuildTask' {
    BeforeEach {
        $SetOSDBuilderPathTasks = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        New-TaskJson -Path (Join-Path $SetOSDBuilderPathTasks 'OSBuild Legacy.json') -Task @{TaskName = 'Legacy'; TaskVersion = '19.1.1.0'; MediaName = 'Windows 10 Enterprise x64 1809'}
        New-TaskJson -Path (Join-Path $SetOSDBuilderPathTasks 'OSBuild Win11.json') -Task @{
            TaskType = 'OSBuild'; TaskVersion = '25.10.14.1'; TaskName = 'Win11'; TaskGuid = 'a1b2c3d4-0000-0000-0000-000000000001'; CustomName = 'Win11 Custom'
            Name = 'Windows 11 Enterprise x64 25H2 26200.6899'; ImageName = 'Windows 11 Enterprise'; Arch = 'x64'; ReleaseId = '25H2'; UBR = '26200.6899'
            Languages = @('en-US'); EditionId = 'Enterprise'; CreatedTime = '2026-10-14T10:00:00'; ModifiedTime = '2026-10-15T10:00:00'
            OSMFamily = 'Client Enterprise x64 26200 en-US'; OSMGuid = 'b1b2c3d4-0000-0000-0000-000000000002'
        }
        $Win10Task = Join-Path $SetOSDBuilderPathTasks 'OSBuild Win10.json'
        New-TaskJson -Path $Win10Task -Task @{
            TaskType = 'OSBuild'; TaskVersion = '20.1.1.0'; TaskName = 'Win10'; Name = 'Windows 10 Enterprise x64 20H2 19042.630'; Arch = 'x64'; ReleaseId = '2009'
            InstallationType = 'Client'; EditionId = 'Enterprise'; Build = 19042; CreatedTime = '2020-11-01T10:00:00'; ModifiedTime = '2020-11-02T10:00:00'
            OSMFamily = 'Client Enterprise x64 19042'
        }
        New-TaskJson -Path (Join-Path $SetOSDBuilderPathTasks 'WinPE Task.json') -Task @{TaskName = 'WinPE'; TaskVersion = '25.10.14.1'}
        Mock Get-OSDBuilder {}
        Mock Get-OSMedia {
            [PSCustomObject]@{OSMFamilyV1 = 'Client Enterprise x64 19042'; Languages = 'de-DE'}
            [PSCustomObject]@{OSMFamilyV1 = 'Client Enterprise x64 19042'; Languages = 'en-US'}
            [PSCustomObject]@{OSMFamilyV1 = 'Client Enterprise x64 19041'; Languages = 'fr-FR'}
        }
        Initialize-GridView
    }

    It 'returns the OSBuild Tasks sorted by TaskName' {
        $Tasks = @(Get-OSBuildTask 3>$null 6>$null)
        Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
        $Tasks.TaskName | Should -Be @('Legacy', 'Win10', 'Win11')
        Should -Invoke Out-GridView -Times 0 -Exactly
    }

    It 'returns the properties of a current Task' {
        $Task = Get-OSBuildTask 3>$null 6>$null | Where-Object {$_.TaskName -eq 'Win11'}
        $Task.TaskType | Should -Be 'OSBuild'
        $Task.CustomName | Should -Be 'Win11 Custom'
        $Task.SourceOSMedia | Should -Be 'Windows 11 Enterprise x64 25H2 26200.6899'
        $Task.ReleaseId | Should -Be '25H2'
        $Task.Languages | Should -Be 'en-US'
        $Task.OSMFamily | Should -Be 'Client Enterprise x64 26200 en-US'
        $Task.LastWriteTime | Should -BeOfType [datetime]
        $Task.FullName | Should -Be (Join-Path $SetOSDBuilderPathTasks 'OSBuild Win11.json')
    }

    It 'returns the name of a Task older than 19.1.3' {
        $Task = Get-OSBuildTask 3>$null 6>$null | Where-Object {$_.TaskName -eq 'Legacy'}
        $Task.TaskVersion | Should -Be '19.1.1.0'
        $Task.TaskType | Should -BeNullOrEmpty
        $Task.FullName | Should -Be (Join-Path $SetOSDBuilderPathTasks 'OSBuild Legacy.json')
    }

    It 'renames ReleaseId 2009 to 20H2' {
        (Get-OSBuildTask 3>$null 6>$null | Where-Object {$_.TaskName -eq 'Win10'}).ReleaseId | Should -Be '20H2'
    }

    It 'adds the Languages of the newest OSMedia to a Task without Languages and saves the Task' {
        $Warnings = (Get-OSBuildTask 6>$null 3>&1 | Where-Object {$_ -is [System.Management.Automation.WarningRecord]}) -join "`n"
        $Warnings | Should -BeLike "*Searching for OSMFamily: Client Enterprise x64 19042*"
        $Warnings | Should -BeLike "*Updating Task: $Win10Task*"
        $Saved = Get-Content -Path $Win10Task -Raw | ConvertFrom-Json
        $Saved.Languages | Should -Be 'en-US'
        $Saved.OSMFamily | Should -Be 'Client Enterprise x64 19042 en-US'
        $Saved.ReleaseId | Should -Be '20H2'
    }

    It 'shows the Tasks in a GridView with -GridView' {
        $Selected = @(Get-OSBuildTask -GridView 3>$null 6>$null)
        Should -Invoke Out-GridView -Times 3 -Exactly -ParameterFilter {$PassThru -and ($Title -eq 'OSBuildTask')}
        $Selected.TaskName | Should -Be @('Legacy', 'Win10', 'Win11')
    }
}

Describe 'Get-PEBuildTask' {
    BeforeEach {
        $SetOSDBuilderPathTasks = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $PETask = @{
            TaskType = 'PEBuild'; TaskVersion = '25.10.14.1'; TaskName = 'WinPE x64'; TaskGuid = 'c1b2c3d4-0000-0000-0000-000000000001'; CustomName = 'WinPE Custom'
            Name = 'Windows 11 Enterprise x64 25H2 26200.6899'; ImageName = 'Windows 11 Enterprise'; Arch = 'x64'; ReleaseId = '25H2'; UBR = '26200.6899'
            Languages = @('en-US'); EditionId = 'Enterprise'; CreatedTime = '2026-10-14T10:00:00'; ModifiedTime = '2026-10-15T10:00:00'
            OSMFamily = 'Client Enterprise x64 26200 en-US'; OSMGuid = 'b1b2c3d4-0000-0000-0000-000000000002'
        }
        New-TaskJson -Path (Join-Path $SetOSDBuilderPathTasks 'WinPE x64.json') -Task $PETask
        $PETask.TaskName = 'MDT x64'
        New-TaskJson -Path (Join-Path $SetOSDBuilderPathTasks 'MDT x64.json') -Task $PETask
        $RecoveryTask = Join-Path $SetOSDBuilderPathTasks 'Recovery x64.json'
        New-TaskJson -Path $RecoveryTask -Task @{
            TaskType = 'PEBuild'; TaskVersion = '20.1.1.0'; TaskName = 'Recovery x64'; ReleaseId = '2009'; Arch = 'x64'
            InstallationType = 'Client'; EditionId = 'Enterprise'; Build = 19042; CreatedTime = '2020-11-01T10:00:00'; ModifiedTime = '2020-11-02T10:00:00'
            OSMFamily = 'Client Enterprise x64 19042'
        }
        New-TaskJson -Path (Join-Path $SetOSDBuilderPathTasks 'WinPE Legacy.json') -Task @{TaskName = 'WinPE Legacy'; TaskVersion = '19.1.1.0'; MediaName = 'Windows 10 x64 1809'}
        New-TaskJson -Path (Join-Path $SetOSDBuilderPathTasks 'OSBuild Win11.json') -Task @{TaskName = 'OSBuild Win11'; TaskVersion = '25.10.14.1'}
        Mock Get-OSDBuilder {}
        Mock Get-OSMedia {[PSCustomObject]@{OSMFamilyV1 = 'Client Enterprise x64 19042'; Languages = 'en-US'}}
        Initialize-GridView
    }

    It 'returns the MDT, Recovery and WinPE Tasks sorted by TaskName' {
        $Tasks = @(Get-PEBuildTask 3>$null 6>$null)
        Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
        $Tasks.TaskName | Should -Be @('MDT x64', 'Recovery x64', 'WinPE Legacy', 'WinPE x64')
    }

    It 'returns the properties of a current Task' {
        $Task = Get-PEBuildTask 3>$null 6>$null | Where-Object {$_.TaskName -eq 'WinPE x64'}
        $Task.TaskType | Should -Be 'PEBuild'
        $Task.CustomName | Should -Be 'WinPE Custom'
        $Task.SourceOSMedia | Should -Be 'Windows 11 Enterprise x64 25H2 26200.6899'
        $Task.OSMGuid | Should -Be 'b1b2c3d4-0000-0000-0000-000000000002'
        $Task.FullName | Should -Be (Join-Path $SetOSDBuilderPathTasks 'WinPE x64.json')
    }

    It 'returns the name of a Task older than 19.1.3' {
        $Task = Get-PEBuildTask 3>$null 6>$null | Where-Object {$_.TaskName -eq 'WinPE Legacy'}
        $Task.TaskVersion | Should -Be '19.1.1.0'
        $Task.TaskType | Should -BeNullOrEmpty
    }

    It 'renames ReleaseId 2009 to 20H2, adds the Languages of the OSMedia and saves the Task' {
        $Output = @(Get-PEBuildTask 6>$null 3>&1)
        $Warnings = ($Output | Where-Object {$_ -is [System.Management.Automation.WarningRecord]}) -join "`n"
        $Warnings | Should -BeLike "*Updating Task: $RecoveryTask*"
        ($Output | Where-Object {$_.TaskName -eq 'Recovery x64'}).ReleaseId | Should -Be '20H2'
        $Saved = Get-Content -Path $RecoveryTask -Raw | ConvertFrom-Json
        $Saved.Languages | Should -Be 'en-US'
        $Saved.OSMFamily | Should -Be 'Client Enterprise x64 19042 en-US'
    }

    It 'shows the Tasks in a GridView with -GridView' {
        $Selected = @(Get-PEBuildTask -GridView 3>$null 6>$null)
        Should -Invoke Out-GridView -Times 4 -Exactly -ParameterFilter {$PassThru -and ($Title -eq 'PEBuildTask')}
        $Selected.Count | Should -Be 4
    }
}

Describe 'Get-OSDFromJson' {
    It 'converts nested JSON objects to hashtables and arrays to lists' {
        $Path = Join-Path $TestDrive 'Task.json'
        Set-Content -Path $Path -Value '{"TaskName":"Win11","TaskVersion":"25.10.14.1","Media":{"Arch":"x64","Build":26200},"Languages":["de-DE","fr-FR"],"Drivers":[{"Name":"Dell"},{"Name":"HP"}]}'
        $Result = Get-OSDFromJson -Path $Path
        $Result | Should -BeOfType [hashtable]
        $Result.TaskName | Should -Be 'Win11'
        $Result.Media | Should -BeOfType [hashtable]
        $Result.Media.Arch | Should -Be 'x64'
        $Result.Media.Build | Should -Be 26200
        @($Result.Languages) | Should -Be @('de-DE', 'fr-FR')
        $Result.Drivers[1] | Should -BeOfType [hashtable]
        $Result.Drivers[1].Name | Should -Be 'HP'
    }

    It 'returns an empty hashtable when the file does not exist' {
        $Result = Get-OSDFromJson (Join-Path $TestDrive 'Missing.json')
        $Result | Should -BeOfType [hashtable]
        $Result.Count | Should -Be 0
    }

    # KnownBug: Private/AllFunctions.ps1:3130 (and 4561) calls $value.GetType() on $null, every JSON null writes an error
    It 'returns $null for a JSON null without an error' -Skip {
        $Path = Join-Path $TestDrive 'Null.json'
        Set-Content -Path $Path -Value '{"CustomName":null}'
        $Result = Get-OSDFromJson -Path $Path -ErrorVariable JsonErrors 2>$null
        $Result.ContainsKey('CustomName') | Should -BeTrue
        $Result.CustomName | Should -BeNullOrEmpty
        $JsonErrors | Should -BeNullOrEmpty
    }
}

Describe 'Get-Value' {
    It 'returns a scalar unchanged' {
        Get-Value -value 'Windows 11' | Should -BeExactly 'Windows 11'
        Get-Value -value 26200 | Should -Be 26200
    }

    It 'converts a PSCustomObject recursively to a hashtable' {
        $Result = Get-Value -value ([PSCustomObject]@{Name = 'Win11'; Media = [PSCustomObject]@{Arch = 'x64'}})
        $Result | Should -BeOfType [hashtable]
        $Result.Name | Should -Be 'Win11'
        $Result.Media | Should -BeOfType [hashtable]
        $Result.Media.Arch | Should -Be 'x64'
    }

    It 'converts the items of an array' {
        $Result = @(Get-Value -value @([PSCustomObject]@{Name = 'Dell'}, 'HP'))
        $Result.Count | Should -Be 2
        $Result[0] | Should -BeOfType [hashtable]
        $Result[0].Name | Should -Be 'Dell'
        $Result[1] | Should -Be 'HP'
    }

    # KnownBug: Private/AllFunctions.ps1:4562 returns the ArrayList with return, PowerShell unrolls it: a one item array becomes a scalar, an empty array $null
    It 'keeps a JSON array with one item as a list' -Skip {
        $Result = Get-Value -value ([PSCustomObject]@{Languages = @('de-DE'); Drivers = @()})
        , $Result.Languages | Should -BeOfType [System.Collections.IList]
        , $Result.Drivers | Should -BeOfType [System.Collections.IList]
    }
}

Describe 'Get-OSDUpdateDownloads' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $SourcePath = New-TestFile -Path (Join-Path (Join-Path $TestDrive 'Catalog') 'windows11.0-kb5066835-x64_payload.msu') -Value 'kb5066835 payload'
        $SourceUri = 'file:///' + ($SourcePath.FullName -replace '\\', '/').TrimStart('/')
        Mock Get-OSDUpdates {
            [PSCustomObject]@{FileName = 'windows11.0-kb5066835-x64_payload.msu'; OSDGuid = 'guid-lcu'; UpdateTitle = '2026-10 Cumulative Update'; OriginUri = $SourceUri}
            [PSCustomObject]@{FileName = 'windows11.0-kb5043080-x64_checkpoint.msu'; OSDGuid = 'guid-lcu'; UpdateTitle = '2026-10 Cumulative Update'; OriginUri = 'https://catalog.invalid/windows11.0-kb5043080-x64_checkpoint.msu'}
            [PSCustomObject]@{FileName = 'windows11.0-kb5066128-x64-ndp481.msu'; OSDGuid = 'guid-dotnet'; UpdateTitle = '2026-10 .NET'; OriginUri = 'https://catalog.invalid/windows11.0-kb5066128-x64-ndp481.msu'}
        }
        Mock curl.exe {}
    }

    It 'downloads the update with the FileName with curl and creates the Updates directory' {
        Get-OSDUpdateDownloads -FileName 'windows11.0-kb5043080-x64_checkpoint.msu' 6>$null
        Should -Invoke Get-OSDUpdates -Times 1 -Exactly -ParameterFilter {$Silent}
        $SetOSDBuilderPathUpdates | Should -Exist
        $Output = Join-Path $SetOSDBuilderPathUpdates 'windows11.0-kb5043080-x64_checkpoint.msu'
        Should -Invoke curl.exe -Times 1 -Exactly
        Should -Invoke curl.exe -Times 1 -Exactly -ParameterFilter {
            ($InputObject -eq '--insecure') -and ($RemainingArguments -contains '--location') -and
            ($RemainingArguments -contains $Output) -and ($RemainingArguments -contains 'https://catalog.invalid/windows11.0-kb5043080-x64_checkpoint.msu')
        }
    }

    It 'downloads every update of the OSDGuid' {
        Get-OSDUpdateDownloads -OSDGuid 'guid-lcu' 6>$null
        Should -Invoke curl.exe -Times 2 -Exactly
    }

    It 'downloads the updates with the UpdateTitle' {
        Get-OSDUpdateDownloads -UpdateTitle '2026-10 .NET' 6>$null
        Should -Invoke curl.exe -Times 1 -Exactly -ParameterFilter {$RemainingArguments -contains 'https://catalog.invalid/windows11.0-kb5066128-x64-ndp481.msu'}
    }

    It 'does not download an update that exists' {
        New-TestFile -Path (Join-Path $SetOSDBuilderPathUpdates 'windows11.0-kb5066128-x64-ndp481.msu') | Out-Null
        Get-OSDUpdateDownloads -UpdateTitle '2026-10 .NET' 6>$null
        Should -Invoke curl.exe -Times 0 -Exactly
    }

    It 'downloads with WebClient when curl.exe is not available' {
        Mock Get-Command {} -ParameterFilter {$Name -eq 'curl.exe'}
        Get-OSDUpdateDownloads -FileName 'windows11.0-kb5066835-x64_payload.msu' 6>$null
        Should -Invoke curl.exe -Times 0 -Exactly
        Join-Path $SetOSDBuilderPathUpdates 'windows11.0-kb5066835-x64_payload.msu' | Should -FileContentMatchExactly 'kb5066835 payload'
    }

    It 'stops without a filter' {
        $Completed = $false
        foreach ($Attempt in 1) {
            Get-OSDUpdateDownloads 6>$null
            $Completed = $true
        }
        $Completed | Should -BeFalse
        Should -Invoke Get-OSDUpdates -Times 0 -Exactly
        Should -Invoke curl.exe -Times 0 -Exactly
    }
}

Describe 'Get-OSDUpdates' {
    #The Microsoft Update Catalog updates are tested in OSServicing.Tests.ps1
    BeforeAll {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'OSDUpdatesArchive'
        New-TestFile -Path (Join-Path $SetOSDBuilderPathUpdates 'windows10.0-kb5005698-x64_ssu.msu') | Out-Null
        function New-Manifest ($Title, $Id, $Link, $Architecture = 'x64', $Description = $null) {
            [PSCustomObject]@{
                Title = $Title; Id = $Id; Architecture = $Architecture; Description = $Description; LastModified = '2021-10-12'
                Size = '10 MB'; Classification = 'Updates'; SupportedProducts = 'Windows 10'; UpdateId = "guid-$Id"; Link = $Link; Source = 'OSD'
            }
        }
        Mock Get-Module {[PSCustomObject]@{Name = 'OSD'; Version = [version]'25.10.1.1'}} -ParameterFilter {$Name -eq 'OSD'}
        Mock Get-OSDBuilderCatalogManifests {}
        Mock Get-WindowsUpdateManifests {
            New-Manifest 'Security Update for Adobe Flash Player for Windows 10 Version 1809 for x64-based Systems (KB4580325)' '4580325' 'https://archive.invalid/windows10.0-kb4580325-x64_flash.msu'
            New-Manifest '2021-01 Cumulative Update for .NET Framework 3.5 and 4.8 for Windows 10 Version 1607 for x64 (KB4578969)' '4578969' 'https://archive.invalid/windows10.0-kb4578969-x64-ndp48.msu'
            New-Manifest '2020-01 Update for .NET Framework 4.8 for Windows 10 Version 1507 x64 (KB4486081)' '4486081' 'https://archive.invalid/windows10.0-kb4486081-x64-ndp48.msu'
            New-Manifest '2021-10 Servicing Stack Update for Windows 10 Version 21H2 for x64-based Systems (KB5005698)' '5005698' 'https://archive.invalid/windows10.0-kb5005698-x64_ssu.msu'
            New-Manifest '2023-09 Cumulative Update for Windows 11 Version 22H2 for x64-based Systems (KB5030219)' '5030219' 'https://archive.invalid/windows11.0-kb5030219-x64_lcu.msu'
            New-Manifest '2024-10 Cumulative Update for Windows 11 Version 23H2 for x64-based Systems (KB5044285)' '5044285' 'https://archive.invalid/windows11.0-kb5044285-x64_lcu.msu'
            New-Manifest '2025-10 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB5066835)' '5066835' @(
                'https://archive.invalid/windows11.0-kb5066835-x64_lcu.msu'
                'https://archive.invalid/windows11.0-kb5043080-x64_checkpoint.msu'
            )
            New-Manifest '2026-10 Cumulative Update for Windows 11 Version 26H2 for x64-based Systems (KB5127700)' '5127700' 'https://archive.invalid/windows11.0-kb5127700-x64_lcu.msu'
            New-Manifest '2021-10 Cumulative Update for Windows 11 for x64-based Systems (KB5006674)' '5006674' 'https://archive.invalid/windows10.0-kb5006674-x64_lcu.msu'
            New-Manifest '2022-10 Dynamic Update for Windows 10 Version 22H2 for x64-based Systems (KB5018506)' '5018506' 'https://archive.invalid/windows10.0-kb5018506-x64_du.cab' -Description 'ComponentUpdate'
            New-Manifest '2022-10 Update for Windows 10 Version 22H2 for x64-based Systems (KB5018000)' '5018000' 'https://archive.invalid/windows10.0-kb5018000-x64_update.msu'
            New-Manifest '2025-10 Cumulative Update for Windows 11 Version 24H2 for arm64-based Systems (KB5066835)' '5066835' 'https://archive.invalid/windows11.0-kb5066835-arm64_lcu.msu' -Architecture 'ARM64'
        }
        $Updates = @(Get-OSDUpdates -Silent)
        function Get-Update ($FileKBNumber) {$Updates | Where-Object {$_.FileKBNumber -eq $FileKBNumber}}
    }

    It 'skips ARM64 updates' {
        $Updates.FileName | Should -Not -Contain 'windows11.0-kb5066835-arm64_lcu.msu'
        $Updates.Count | Should -Be 12
    }

    It 'groups <FileKB> as <Group>' -ForEach @(
        @{FileKB = '4580325'; Group = 'AdobeSU'}
        @{FileKB = '4578969'; Group = 'DotNetCU'}
        @{FileKB = '4486081'; Group = 'DotNet'}
        @{FileKB = '5005698'; Group = 'SSU'}
        @{FileKB = '5030219'; Group = 'LCU'}
        @{FileKB = '5018506'; Group = 'ComponentDU Critical'}
        @{FileKB = '5018000'; Group = 'Optional'}
    ) {
        (Get-Update $FileKB).UpdateGroup | Should -Be $Group
    }

    It 'detects <OS> <Build> for <FileKB>' -ForEach @(
        @{FileKB = '4580325'; OS = 'Windows 10'; Build = '1809'}
        @{FileKB = '4578969'; OS = 'Windows 10'; Build = '1607'}
        @{FileKB = '4486081'; OS = 'Windows 10'; Build = '1507'}
        @{FileKB = '5005698'; OS = 'Windows 10'; Build = '21H2'}
        @{FileKB = '5018000'; OS = 'Windows 10'; Build = '22H2'}
        @{FileKB = '5030219'; OS = 'Windows 11'; Build = '22H2'}
        @{FileKB = '5044285'; OS = 'Windows 11'; Build = '23H2'}
        @{FileKB = '5066835'; OS = 'Windows 11'; Build = '24H2'}
        @{FileKB = '5127700'; OS = 'Windows 11'; Build = '26H2'}
        @{FileKB = '5006674'; OS = 'Windows 11'; Build = '21H2'}
    ) {
        $Update = Get-Update $FileKB
        $Update.UpdateOS | Should -Be $OS
        $Update.UpdateBuild | Should -Be $Build
        $Update.Catalog | Should -Be "$OS $Build"
    }

    It 'does not name a checkpoint cumulative update of the OSD archive' {
        (Get-Update '5043080').Title | Should -Be '2025-10 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB5066835)'
        (Get-Update '5043080').KBNumber | Should -Be '5066835'
    }

    It 'returns the OSD module version and the manifest properties' {
        $Update = Get-Update '5005698'
        $Update.OSDVersion | Should -Be ([version]'25.10.1.1')
        $Update.FileName | Should -Be 'windows10.0-kb5005698-x64_ssu.msu'
        $Update.OriginUri | Should -Be 'https://archive.invalid/windows10.0-kb5005698-x64_ssu.msu'
        $Update.OSDGuid | Should -Be 'guid-5005698'
        $Update.UpdateArch | Should -Be 'x64'
    }

    It 'marks the downloaded updates' {
        (Get-Update '5005698').OSDStatus | Should -Be 'Downloaded'
        (Get-Update '5030219').OSDStatus | Should -BeNullOrEmpty
    }
}

Describe 'Get-OSTemplateDrivers' {
    BeforeEach {
        $SetOSDBuilderPathTemplates = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $OSArchitecture = 'x64'; $UpdateOS = 'Windows 10'; $ReleaseId = '22H2'; $OSInstallationType = 'Client'; $OSMajorVersion = 10
        foreach ($Name in 'Global', 'Global x64', 'Windows 10', 'Windows 10 x64', 'Windows 10 x64 22H2', 'Windows 10 x86') {
            New-Item -Path (Join-Path (Join-Path (Join-Path $SetOSDBuilderPathTemplates 'Drivers') 'AutoApply') $Name) -ItemType Directory -Force | Out-Null
        }
        Mock Get-IsContentPacksEnabled {$false}
    }

    It 'returns the AutoApply driver directories of a Windows 10 client' {
        (Get-OSTemplateDrivers).Name | Should -Be @('Global', 'Global x64', 'Windows 10', 'Windows 10 x64', 'Windows 10 x64 22H2')
    }

    It 'returns only the Global and Operating System directories of a server' {
        $OSInstallationType = 'Server'; $UpdateOS = 'Windows 10'
        (Get-OSTemplateDrivers).Name | Should -Be @('Global', 'Global x64', 'Windows 10')
    }

    It 'skips missing directories' {
        Remove-Item -Path (Join-Path (Join-Path (Join-Path $SetOSDBuilderPathTemplates 'Drivers') 'AutoApply') 'Global x64') -Recurse
        (Get-OSTemplateDrivers 2>$null).Name | Should -Not -Contain 'Global x64'
    }

    It 'returns nothing when ContentPacks are enabled' {
        Mock Get-IsContentPacksEnabled {$true}
        Get-OSTemplateDrivers | Should -BeNullOrEmpty
    }
}

Describe 'Get-OSTemplateExtraFiles' {
    BeforeEach {
        $SetOSDBuilderPathTemplates = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $OSArchitecture = 'x64'; $UpdateOS = 'Windows 10'; $ReleaseId = '22H2'; $OSInstallationType = 'Client'; $OSMajorVersion = 10
        $AutoApply = Join-Path (Join-Path $SetOSDBuilderPathTemplates 'ExtraFiles') 'AutoApply'
        foreach ($Name in 'Global', 'Global x64', 'Windows 10', 'Windows 10 x64', 'Windows 10 x64 22H2', 'Windows 10 x86') {
            New-Item -Path (Join-Path (Join-Path $AutoApply $Name) "$Name Files") -ItemType Directory -Force | Out-Null
        }
        New-TestFile -Path (Join-Path (Join-Path $AutoApply 'Global') 'readme.txt') | Out-Null
        Mock Get-IsContentPacksEnabled {$false}
    }

    It 'returns the directories in the AutoApply directories of a Windows 10 client' {
        (Get-OSTemplateExtraFiles).Name | Should -Be @('Global Files', 'Global x64 Files', 'Windows 10 Files', 'Windows 10 x64 Files', 'Windows 10 x64 22H2 Files')
    }

    It 'returns only the Global and Operating System directories of a server' {
        $OSInstallationType = 'Server'
        (Get-OSTemplateExtraFiles).Name | Should -Be @('Global Files', 'Global x64 Files', 'Windows 10 Files')
    }

    It 'skips the release directory when the Operating System is not 10' {
        $OSMajorVersion = 6
        (Get-OSTemplateExtraFiles).Name | Should -Not -Contain 'Windows 10 x64 22H2 Files'
    }

    It 'returns nothing when ContentPacks are enabled' {
        Mock Get-IsContentPacksEnabled {$true}
        Get-OSTemplateExtraFiles | Should -BeNullOrEmpty
    }
}

Describe 'Get-OSTemplateRegistryReg' {
    BeforeEach {
        $SetOSDBuilderPathTemplates = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $OSArchitecture = 'x64'; $UpdateOS = 'Windows 11'; $ReleaseId = '25H2'; $OSInstallationType = 'Client'; $OSMajorVersion = 10
        $AutoApply = Join-Path (Join-Path $SetOSDBuilderPathTemplates 'Registry') 'AutoApply'
        $Reg = "Windows Registry Editor Version 5.00`r`n`r`n[HKEY_CURRENT_USER\Software\Contoso]`r`n[HKEY_LOCAL_MACHINE\SOFTWARE\Contoso]`r`n[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Contoso]`r`n[HKEY_USERS\.DEFAULT\Control Panel\Desktop]"
        foreach ($Name in 'Global', 'Global x64', 'Windows 11', 'Windows 11 x64', 'Windows 11 x64 25H2', 'Windows 10') {
            New-TestFile -Path (Join-Path (Join-Path $AutoApply $Name) "$Name.reg") -Value $Reg | Out-Null
        }
        Mock Get-IsContentPacksEnabled {$false}
    }

    It 'creates an .Offline file for the offline registry hives of every .reg file' {
        Get-OSTemplateRegistryReg 6>$null | Out-Null
        $Offline = Get-Content -Path (Join-Path (Join-Path $AutoApply 'Global') 'Global.reg.Offline') -Raw
        $Offline | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineDefaultUser\Software\Contoso`]*'
        $Offline | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineSoftware\Contoso`]*'
        $Offline | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineSystem\CurrentControlSet\Services\Contoso`]*'
        $Offline | Should -BeLike '*`[HKEY_LOCAL_MACHINE\OfflineDefault\Control Panel\Desktop`]*'
        $Offline | Should -Not -BeLike '*HKEY_CURRENT_USER*'
        Join-Path (Join-Path $AutoApply 'Windows 10') 'Windows 10.reg.Offline' | Should -Exist
    }

    It 'does not overwrite an existing .Offline file' {
        New-TestFile -Path (Join-Path (Join-Path $AutoApply 'Global') 'Global.reg.Offline') -Value 'edited' | Out-Null
        Get-OSTemplateRegistryReg 6>$null | Out-Null
        Join-Path (Join-Path $AutoApply 'Global') 'Global.reg.Offline' | Should -FileContentMatchExactly '^edited$'
    }

    It 'returns the .Offline files of the AutoApply directories of a Windows 11 client' {
        (Get-OSTemplateRegistryReg 6>$null).Name | Should -Be @('Global.reg.Offline', 'Global x64.reg.Offline', 'Windows 11.reg.Offline', 'Windows 11 x64.reg.Offline', 'Windows 11 x64 25H2.reg.Offline')
    }

    It 'returns only the Global and Operating System files of a server' {
        $OSInstallationType = 'Server'
        (Get-OSTemplateRegistryReg 6>$null).Name | Should -Be @('Global.reg.Offline', 'Global x64.reg.Offline', 'Windows 11.reg.Offline')
    }

    It 'returns nothing when ContentPacks are enabled' {
        Mock Get-IsContentPacksEnabled {$true}
        Get-OSTemplateRegistryReg 6>$null | Should -BeNullOrEmpty
        Join-Path (Join-Path $AutoApply 'Global') 'Global.reg.Offline' | Should -Not -Exist
    }
}

Describe 'Get-OSTemplateRegistryXml' {
    BeforeEach {
        $SetOSDBuilderPathTemplates = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $OSArchitecture = 'x64'; $UpdateOS = 'Windows 10'; $ReleaseId = '22H2'; $OSInstallationType = 'Client'; $OSMajorVersion = 10
        $AutoApply = Join-Path (Join-Path $SetOSDBuilderPathTemplates 'Registry') 'AutoApply'
        foreach ($Name in 'Global', 'Global x64', 'Windows 10', 'Windows 10 x64', 'Windows 10 x64 22H2', 'Windows 11') {
            New-TestFile -Path (Join-Path (Join-Path $AutoApply $Name) "$Name.xml") -Value '<RegistrySettings />' | Out-Null
            New-TestFile -Path (Join-Path (Join-Path $AutoApply $Name) "$Name.reg") | Out-Null
        }
        Mock Get-IsContentPacksEnabled {$false}
    }

    It 'returns the xml files of the AutoApply directories of a Windows 10 client' {
        (Get-OSTemplateRegistryXml).Name | Should -Be @('Global.xml', 'Global x64.xml', 'Windows 10.xml', 'Windows 10 x64.xml', 'Windows 10 x64 22H2.xml')
    }

    It 'returns only the Global and Operating System files of a server' {
        $OSInstallationType = 'Server'
        (Get-OSTemplateRegistryXml).Name | Should -Be @('Global.xml', 'Global x64.xml', 'Windows 10.xml')
    }

    It 'returns nothing when ContentPacks are enabled' {
        Mock Get-IsContentPacksEnabled {$true}
        Get-OSTemplateRegistryXml | Should -BeNullOrEmpty
    }
}

Describe 'Get-OSTemplateScripts' {
    BeforeEach {
        $SetOSDBuilderPathTemplates = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $OSArchitecture = 'x64'; $UpdateOS = 'Windows 10'; $ReleaseId = '22H2'; $OSInstallationType = 'Client'; $OSMajorVersion = 10
        $AutoApply = Join-Path (Join-Path $SetOSDBuilderPathTemplates 'Scripts') 'AutoApply'
        foreach ($Name in 'Global', 'Global x64', 'Windows 10', 'Windows 10 x64', 'Windows 10 x64 22H2', 'Global x86') {
            New-TestFile -Path (Join-Path (Join-Path $AutoApply $Name) "$Name.ps1") | Out-Null
            New-TestFile -Path (Join-Path (Join-Path $AutoApply $Name) "$Name.txt") | Out-Null
        }
        Mock Get-IsContentPacksEnabled {$false}
    }

    It 'returns the scripts of the AutoApply directories of a Windows 10 client' {
        (Get-OSTemplateScripts).Name | Should -Be @('Global.ps1', 'Global x64.ps1', 'Windows 10.ps1', 'Windows 10 x64.ps1', 'Windows 10 x64 22H2.ps1')
    }

    It 'returns only the Global and Operating System scripts of a server' {
        $OSInstallationType = 'Server'
        (Get-OSTemplateScripts).Name | Should -Be @('Global.ps1', 'Global x64.ps1', 'Windows 10.ps1')
    }

    It 'returns nothing when ContentPacks are enabled' {
        Mock Get-IsContentPacksEnabled {$true}
        Get-OSTemplateScripts | Should -BeNullOrEmpty
    }
}

Describe 'Get-TaskContentAddFeatureOnDemand' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 11'; InstallationType = 'Client'; Arch = 'x64'; ReleaseId = '25H2'}
        $ExistingTask = $null
        $Lof = 'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LanguagesAndOptionalFeatures'
        $ContentIsoExtract = @(
            New-ContentItem "$Lof\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~amd64~~.cab"
            New-ContentItem "$Lof\Microsoft-Windows-Notepad-System-FoD-Package~31bf3856ad364e35~amd64~~.cab"
            New-ContentItem "$Lof\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab"
            New-ContentItem "$Lof\Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab"
            New-ContentItem "$Lof\Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab"
            New-ContentItem "$Lof\Microsoft-Windows-Language-Interface-Pack-x64-ca-es.cab"
            New-ContentItem "$Lof\LanguageExperiencePack.de-DE.Neutral.appx"
            New-ContentItem "$Lof\de-de\lp.cab"
            New-ContentItem "$Lof\metadata\DesktopTargetCompDB_Neutral.xml.cab"
            New-ContentItem "$Lof\Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0.cab"
            New-ContentItem "$Lof\Rsat.WSUS.Tools~~~~0.0.1.0.cab"
            New-ContentItem 'IsoExtract\Windows 10 2004 x64 FOD\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~amd64~~.cab'
            New-ContentItem 'IsoExtract\Windows Server 2025 24H2 Languages and Optional Features\Microsoft-Windows-Server-AppCompat-FoD-Package~31bf3856ad364e35~amd64~~.cab'
        )
        Mock Test-Path {$false} -ParameterFilter {"$Path" -like '*\Updates\FeatureOnDemand'}
        Initialize-GridView
    }

    It 'offers the Features on Demand of the OSMedia without language packages, metadata and RSAT' {
        $Result = Get-TaskContentAddFeatureOnDemand 6>$null
        $script:GridView.Name | Should -Be @(
            'Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-Notepad-System-FoD-Package~31bf3856ad364e35~amd64~~.cab'
        )
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Install.wim Features On Demand:*')}
        $Result.FullName | Should -Contain "$Lof\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~amd64~~.cab"
    }

    It 'adds the Features on Demand of Content\Updates\FeatureOnDemand relative to the Content directory' {
        Mock Test-Path {$true} -ParameterFilter {"$Path" -like '*\Updates\FeatureOnDemand'}
        Mock Get-ChildItem {New-ContentItem "$ContentRoot\Updates\FeatureOnDemand\Windows 11 25H2 x64\Microsoft-Windows-Contoso-FoD-Package~31bf3856ad364e35~amd64~~.cab"} -ParameterFilter {"$Path" -like '*\Updates\FeatureOnDemand'}
        Get-TaskContentAddFeatureOnDemand 6>$null | Out-Null
        $script:GridView.FullName | Should -Contain 'Updates\FeatureOnDemand\Windows 11 25H2 x64\Microsoft-Windows-Contoso-FoD-Package~31bf3856ad364e35~amd64~~.cab'
    }

    It 'does not offer the Features on Demand of the existing Task' {
        $ExistingTask = [PSCustomObject]@{AddFeatureOnDemand = @("$Lof\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~amd64~~.cab")}
        Get-TaskContentAddFeatureOnDemand 6>$null | Out-Null
        $script:GridView.Name | Should -Be @('Microsoft-Windows-Notepad-System-FoD-Package~31bf3856ad364e35~amd64~~.cab')
    }

    It 'offers only the Windows Server Features on Demand to a server' {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows Server'; InstallationType = 'Server'; Arch = 'x64'; ReleaseId = '24H2'}
        Get-TaskContentAddFeatureOnDemand 6>$null | Out-Null
        $script:GridView.Name | Should -Be @('Microsoft-Windows-Server-AppCompat-FoD-Package~31bf3856ad364e35~amd64~~.cab')
    }

    It 'offers only the x86 Features on Demand to an x86 client' {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 10'; InstallationType = 'Client'; Arch = 'x86'; ReleaseId = '1809'}
        $ContentIsoExtract = @(
            New-ContentItem 'IsoExtract\Windows 10 1809 x86 FOD\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~x86~~.cab'
            New-ContentItem 'IsoExtract\Windows 10 1809 x64 FOD\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~amd64~~.cab'
            New-ContentItem 'IsoExtract\Windows 10 1809 x86 FOD\Rsat.Dns.Tools~~~~0.0.1.0.cab'
        )
        Get-TaskContentAddFeatureOnDemand 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('IsoExtract\Windows 10 1809 x86 FOD\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~x86~~.cab')
    }

    It 'keeps RSAT of Windows 10 1803 and older' {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 10'; InstallationType = 'Client'; Arch = 'x64'; ReleaseId = '1803'}
        $ContentIsoExtract = @(New-ContentItem 'IsoExtract\Windows 10 1803 x64 FOD\Rsat.Dns.Tools~~~~0.0.1.0.cab')
        Get-TaskContentAddFeatureOnDemand 6>$null | Out-Null
        $script:GridView.Name | Should -Be @('Rsat.Dns.Tools~~~~0.0.1.0.cab')
    }

    It 'warns when there are no Features on Demand' {
        $ContentIsoExtract = @()
        $Warnings = (Get-TaskContentAddFeatureOnDemand 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Install.wim Features On Demand: Not Found*'
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskContentAddWindowsCapability' {
    BeforeEach {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 11'; InstallationType = 'Client'; Arch = 'x64'; ReleaseId = '25H2'; FullName = (Join-Path $TestDrive ([guid]::NewGuid().Guid))}
        $ExistingTask = $null
        $GetOSDBuilderPathContentIsoExtract = 'C:\OSDBuilder\Content\IsoExtract'
        $CapabilityXml = Join-Path (Join-Path (Join-Path $OSMedia.FullName 'info') 'xml') 'Get-WindowsCapability.xml'
        New-Item -Path (Split-Path $CapabilityXml -Parent) -ItemType Directory -Force | Out-Null
        @(
            [PSCustomObject]@{Name = 'Browser.InternetExplorer~~~~0.0.11.0'; State = 'NotPresent'}
            [PSCustomObject]@{Name = 'Rsat.Dns.Tools~~~~0.0.1.0'; State = 0}
            [PSCustomObject]@{Name = 'OpenSSH.Client~~~~0.0.1.0'; State = 'Installed'}
            [PSCustomObject]@{Name = 'Language.Basic~~~de-DE~0.0.1.0'; State = 'NotPresent'}
        ) | Export-Clixml -Path $CapabilityXml
        Mock Get-OSDBuilderCapabilitySource {'C:\OSDBuilder\Content\IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LanguagesAndOptionalFeatures'}
        Initialize-GridView
    }

    It 'offers the capabilities that are not present without the language capabilities' {
        $Result = Get-TaskContentAddWindowsCapability 6>$null
        Should -Invoke Get-OSDBuilderCapabilitySource -Times 1 -Exactly -ParameterFilter {$OSMedia.ReleaseId -eq '25H2'}
        $script:GridView.Name | Should -Be @('Browser.InternetExplorer~~~~0.0.11.0', 'Rsat.Dns.Tools~~~~0.0.1.0')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Add-WindowsCapability:*')}
        $Result.Name | Should -Be @('Browser.InternetExplorer~~~~0.0.11.0', 'Rsat.Dns.Tools~~~~0.0.1.0')
    }

    It 'does not offer the capabilities of the existing Task' {
        $ExistingTask = [PSCustomObject]@{AddWindowsCapability = @('Rsat.Dns.Tools~~~~0.0.1.0')}
        Get-TaskContentAddWindowsCapability 6>$null | Out-Null
        $script:GridView.Name | Should -Be @('Browser.InternetExplorer~~~~0.0.11.0')
    }

    It 'warns when all capabilities are in the existing Task' {
        $ExistingTask = [PSCustomObject]@{AddWindowsCapability = @('Rsat.Dns.Tools~~~~0.0.1.0', 'Browser.InternetExplorer~~~~0.0.11.0')}
        $Warnings = (Get-TaskContentAddWindowsCapability 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Install.wim Windows Capabilities: Not Found*'
        Should -Invoke Out-GridView -Times 0 -Exactly
    }

    It 'warns when nothing is selected' {
        Mock Out-GridView {}
        $Warnings = (Get-TaskContentAddWindowsCapability 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Install.wim Windows Capabilities: Skipping*'
    }

    It 'warns when there is no Features on Demand repository' {
        Mock Get-OSDBuilderCapabilitySource {}
        $Warnings = (Get-TaskContentAddWindowsCapability 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*No Features on Demand repository was found in C:\OSDBuilder\Content\IsoExtract*'
        $Warnings | Should -BeLike '*Save-OSDBuilderDownload -ContentDownload*'
        Should -Invoke Out-GridView -Times 0 -Exactly
    }

    It 'warns when the OSMedia has no capability inventory' {
        Remove-Item -Path $CapabilityXml
        $Warnings = (Get-TaskContentAddWindowsCapability 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Get-WindowsCapability.xml was not found, update the OSMedia*'
        Should -Invoke Get-OSDBuilderCapabilitySource -Times 0 -Exactly
    }
}

Describe 'Get-TaskContentAddWindowsPackage' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $GetOSDBuilderPathContentPackages = "$ContentRoot\Packages"
        $OSMedia = [PSCustomObject]@{Arch = 'x64'}
        $ExistingTask = $null
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\Packages\Windows 11 x64\windows11.0-kb5066128-x64-ndp481.msu"
            New-ContentItem "$ContentRoot\Packages\Windows 11 x64\Microsoft-Windows-Contoso-Package.cab"
            New-ContentItem "$ContentRoot\Packages\Windows 10 x86\windows10.0-kb5000000-x86.msu"
        } -ParameterFilter {"$Path" -eq "$ContentRoot\Packages\*"}
        Initialize-GridView
    }

    It 'offers the cab and msu packages of the architecture relative to the Content directory' {
        $Result = Get-TaskContentAddWindowsPackage 6>$null
        Should -Invoke Get-ChildItem -Times 1 -Exactly -ParameterFilter {$Recurse -and ($Include -contains '*.cab') -and ($Include -contains '*.msu')}
        $script:GridView.FullName | Should -Be @('Packages\Windows 11 x64\windows11.0-kb5066128-x64-ndp481.msu', 'Packages\Windows 11 x64\Microsoft-Windows-Contoso-Package.cab')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Packages:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the packages of the existing Task' {
        $ExistingTask = [PSCustomObject]@{AddWindowsPackage = @('Packages\Windows 11 x64\Microsoft-Windows-Contoso-Package.cab')}
        Get-TaskContentAddWindowsPackage 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('Packages\Windows 11 x64\windows11.0-kb5066128-x64-ndp481.msu')
    }

    It 'warns when there are no packages for the architecture' {
        $OSMedia = [PSCustomObject]@{Arch = 'arm64'}
        $Warnings = (Get-TaskContentAddWindowsPackage 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*Packages: To select Windows Packages, add Content to $ContentRoot\Packages*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskContentDrivers' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $GetOSDBuilderPathContentDrivers = "$ContentRoot\Drivers"
        $ExistingTask = $null
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\Drivers\Dell Latitude"
            New-ContentItem "$ContentRoot\Drivers\HP EliteBook"
        } -ParameterFilter {("$Path" -eq "$ContentRoot\Drivers") -and $Directory}
        Initialize-GridView
    }

    It 'offers the driver directories relative to the Content directory' {
        $Result = Get-TaskContentDrivers 6>$null
        $script:GridView.FullName | Should -Be @('Drivers\Dell Latitude', 'Drivers\HP EliteBook')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Drivers:*')}
        $Result.Name | Should -Be @('Dell Latitude', 'HP EliteBook')
    }

    It 'does not offer the drivers of the existing Task' {
        $ExistingTask = [PSCustomObject]@{Drivers = @('Drivers\Dell Latitude')}
        Get-TaskContentDrivers 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('Drivers\HP EliteBook')
    }

    It 'warns when there are no drivers' {
        Mock Get-ChildItem {} -ParameterFilter {$Directory}
        $Warnings = (Get-TaskContentDrivers 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*Drivers: To select Windows Drivers, add Content to $ContentRoot\Drivers*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskContentExtraFiles' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $GetOSDBuilderPathContentExtraFiles = "$ContentRoot\ExtraFiles"
        $ExistingTask = $null
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\ExtraFiles\Wallpaper"
            New-ContentItem "$ContentRoot\ExtraFiles\Empty"
            New-ContentItem "$ContentRoot\ExtraFiles\Tools"
        } -ParameterFilter {("$Path" -eq "$ContentRoot\ExtraFiles") -and $Directory}
        Mock Get-ChildItem {if ("$Path" -notlike '*\Empty') {New-ContentItem "$Path\file.txt"}}
        Initialize-GridView
    }

    It 'offers the directories with files relative to the Content directory' {
        $Result = Get-TaskContentExtraFiles 6>$null
        $script:GridView.FullName | Should -Be @('ExtraFiles\Wallpaper', 'ExtraFiles\Tools')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Extra Files:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the directories of the existing Task' {
        $ExistingTask = [PSCustomObject]@{ExtraFiles = @('ExtraFiles\Wallpaper')}
        Get-TaskContentExtraFiles 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('ExtraFiles\Tools')
    }

    It 'warns when there are no directories with files' {
        Mock Get-ChildItem {New-ContentItem "$ContentRoot\ExtraFiles\Empty"} -ParameterFilter {$Directory}
        $Warnings = (Get-TaskContentExtraFiles 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*Extra Files: To select Extra Files, add Content to $ContentRoot\ExtraFiles*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskContentIsoExtract' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $GetOSDBuilderPathContentIsoExtract = "$ContentRoot\IsoExtract"
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 11'; Arch = 'x64'; ReleaseId = '25H2'}
        $Lof = "$ContentRoot\IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features"
        Mock Get-ChildItem {
            New-ContentItem "$Lof\LanguagesAndOptionalFeatures\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab"
            New-ContentItem "$Lof\LocalExperiencePack\de-de\LanguageExperiencePack.de-DE.Neutral.appx"
            New-ContentItem "$Lof\Windows Preinstallation Environment\arm64\WinPE_OCs\WinPE-WMI.cab"
            New-ContentItem "$Lof\Windows Preinstallation Environment\x86\WinPE_OCs\WinPE-WMI.cab"
            New-ContentItem "$Lof\LanguagesAndOptionalFeatures\Microsoft-Windows-Client-Language-Pack_x86_de-de.cab"
            New-ContentItem "$Lof\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-WMI.cab"
            New-ContentItem "$ContentRoot\IsoExtract\Windows 10 2004 x64 Languages\x64\langpacks\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab"
            New-ContentItem "$ContentRoot\IsoExtract\Windows 11 21H2 x64 FOD\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~amd64~~.cab"
        }
    }

    It 'returns the cab and appx files of the release relative to the Content directory without arm64 and x86' {
        $Result = Get-TaskContentIsoExtract
        Should -Invoke Get-ChildItem -Times 1 -Exactly -ParameterFilter {("$Path" -eq "$ContentRoot\IsoExtract\*") -and $Recurse -and ($Include -contains '*.cab') -and ($Include -contains '*.appx')}
        $Result.FullName | Should -Be @(
            'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LanguagesAndOptionalFeatures\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab'
            'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LocalExperiencePack\de-de\LanguageExperiencePack.de-DE.Neutral.appx'
            'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-WMI.cab'
        )
    }

    It 'returns the x86 files of an x86 OSMedia' {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 10'; Arch = 'x86'; ReleaseId = '1809'}
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\IsoExtract\Windows 10 1809 Languages\x86\langpacks\Microsoft-Windows-Client-Language-Pack_x86_de-de.cab"
            New-ContentItem "$ContentRoot\IsoExtract\Windows 10 1809 Languages\x64\langpacks\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab"
            New-ContentItem "$ContentRoot\IsoExtract\Windows 10 1809 FOD\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~amd64~~.cab"
            New-ContentItem "$ContentRoot\IsoExtract\Windows 10 1809 ADK\amd64\WinPE_OCs\WinPE-WMI.cab"
            New-ContentItem "$ContentRoot\IsoExtract\Windows 10 1809 ADK\x86\WinPE_OCs\WinPE-WMI.cab"
        }
        (Get-TaskContentIsoExtract).FullName | Should -Be @(
            'IsoExtract\Windows 10 1809 Languages\x86\langpacks\Microsoft-Windows-Client-Language-Pack_x86_de-de.cab'
            'IsoExtract\Windows 10 1809 ADK\x86\WinPE_OCs\WinPE-WMI.cab'
        )
    }

    It 'returns the files of every release when the OSMedia has no ReleaseId' {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 10'; Arch = 'x64'; ReleaseId = $null}
        (Get-TaskContentIsoExtract).FullName | Should -Contain 'IsoExtract\Windows 11 21H2 x64 FOD\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~amd64~~.cab'
    }
}

Describe 'Get-TaskContentLanguageCopySources' {
    BeforeEach {
        $OSMedia = [PSCustomObject]@{Arch = 'x64'; Build = '26200'; OperatingSystem = 'Windows 11'; OSMFamily = 'Client Enterprise x64 26200 en-US'}
        $ExistingTask = $null
        Mock Get-OSMedia {
            [PSCustomObject]@{Arch = 'x64'; Build = '26200'; OperatingSystem = 'Windows 11'; OSMFamily = 'Client Enterprise x64 26200 en-US'}
            [PSCustomObject]@{Arch = 'x64'; Build = '26200'; OperatingSystem = 'Windows 11'; OSMFamily = 'Client Enterprise x64 26200 de-DE'}
            [PSCustomObject]@{Arch = 'x64'; Build = '26200'; OperatingSystem = 'Windows 11'; OSMFamily = 'Client Enterprise x64 26200 fr-FR'}
            [PSCustomObject]@{Arch = 'x86'; Build = '26200'; OperatingSystem = 'Windows 11'; OSMFamily = 'Client Enterprise x86 26200 it-IT'}
            [PSCustomObject]@{Arch = 'x64'; Build = '26100'; OperatingSystem = 'Windows 11'; OSMFamily = 'Client Enterprise x64 26100 es-ES'}
            [PSCustomObject]@{Arch = 'x64'; Build = '26200'; OperatingSystem = 'Windows Server'; OSMFamily = 'Server Datacenter x64 26200 ja-JP'}
        }
        Initialize-GridView
    }

    It 'offers the other OSMedia with the same Operating System, Build and Arch' {
        $Result = Get-TaskContentLanguageCopySources 6>$null
        Should -Invoke Get-OSMedia -Times 1 -Exactly -ParameterFilter {$Revision -eq 'OK'}
        $script:GridView.OSMFamily | Should -Be @('Client Enterprise x64 26200 de-DE', 'Client Enterprise x64 26200 fr-FR')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'SourcesLanguageCopy:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the OSMedia of the existing Task' {
        $ExistingTask = [PSCustomObject]@{LanguageCopySources = @('Client Enterprise x64 26200 fr-FR')}
        Get-TaskContentLanguageCopySources 6>$null | Out-Null
        $script:GridView.OSMFamily | Should -Be @('Client Enterprise x64 26200 de-DE')
    }
}

Describe 'Get-TaskContentLanguageFeature' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 11'; InstallationType = 'Client'; Arch = 'x64'; ReleaseId = '25H2'}
        $ExistingTask = $null
        $Lof = 'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LanguagesAndOptionalFeatures'
        $ContentIsoExtract = @(
            New-ContentItem "$Lof\Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab"
            New-ContentItem "$Lof\Microsoft-Windows-LanguageFeatures-OCR-de-de-Package~31bf3856ad364e35~amd64~~.cab"
            New-ContentItem "$Lof\Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~amd64~~.cab"
            New-ContentItem 'IsoExtract\Windows 10 1809 x86 FOD\Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~wow64~~.cab'
        )
        Mock Test-Path {$false} -ParameterFilter {"$Path" -like '*\Updates\LanguageFeature'}
        Initialize-GridView
    }

    It 'offers the Language Features on Demand of the architecture sorted by name' {
        $Result = Get-TaskContentLanguageFeature 6>$null
        $script:GridView.Name | Should -Be @(
            'Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-LanguageFeatures-OCR-de-de-Package~31bf3856ad364e35~amd64~~.cab'
        )
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Install.wim Language Features On Demand:*')}
        @($Result).Count | Should -Be 2
    }

    It 'adds the Language Features of the release in Content\Updates\LanguageFeature' {
        Mock Test-Path {$true} -ParameterFilter {"$Path" -like '*\Updates\LanguageFeature'}
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\Updates\LanguageFeature\Windows 11 25H2 x64\Microsoft-Windows-LanguageFeatures-Speech-de-de-Package~31bf3856ad364e35~amd64~~.cab"
            New-ContentItem "$ContentRoot\Updates\LanguageFeature\Windows 10 22H2 x64\Microsoft-Windows-LanguageFeatures-Speech-fr-fr-Package~31bf3856ad364e35~amd64~~.cab"
            New-ContentItem "$ContentRoot\Updates\LanguageFeature\Windows 11 25H2 x86\Microsoft-Windows-LanguageFeatures-Speech-it-it-Package~31bf3856ad364e35~wow64~~.cab"
        } -ParameterFilter {"$Path" -like '*\Updates\LanguageFeature'}
        Get-TaskContentLanguageFeature 6>$null | Out-Null
        $script:GridView.FullName | Should -Contain 'Updates\LanguageFeature\Windows 11 25H2 x64\Microsoft-Windows-LanguageFeatures-Speech-de-de-Package~31bf3856ad364e35~amd64~~.cab'
        @($script:GridView).Count | Should -Be 3
    }

    It 'offers the x86 Language Features to an x86 OSMedia' {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 10'; InstallationType = 'Client'; Arch = 'x86'; ReleaseId = '1809'}
        Mock Test-Path {$true} -ParameterFilter {"$Path" -like '*\Updates\LanguageFeature'}
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\Updates\LanguageFeature\Windows 10 1809 x86\Microsoft-Windows-LanguageFeatures-Speech-it-it-Package~31bf3856ad364e35~x86~~.cab"
            New-ContentItem "$ContentRoot\Updates\LanguageFeature\Windows 10 1809 x64\Microsoft-Windows-LanguageFeatures-Speech-it-it-Package~31bf3856ad364e35~amd64~~.cab"
        } -ParameterFilter {"$Path" -like '*\Updates\LanguageFeature'}
        Get-TaskContentLanguageFeature 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @(
            'IsoExtract\Windows 10 1809 x86 FOD\Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~wow64~~.cab'
            'Updates\LanguageFeature\Windows 10 1809 x86\Microsoft-Windows-LanguageFeatures-Speech-it-it-Package~31bf3856ad364e35~x86~~.cab'
        )
    }

    It 'does not offer the Language Features of the existing Task' {
        $ExistingTask = [PSCustomObject]@{LanguageFeature = @("$Lof\Microsoft-Windows-LanguageFeatures-OCR-de-de-Package~31bf3856ad364e35~amd64~~.cab")}
        Get-TaskContentLanguageFeature 6>$null | Out-Null
        $script:GridView.Name | Should -Be @('Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab')
    }

    It 'warns when nothing is selected' {
        Mock Out-GridView {}
        $Warnings = (Get-TaskContentLanguageFeature 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Install.wim Language Features On Demand: Skipping*'
    }

    It 'warns when there are no Language Features' {
        $ContentIsoExtract = $null
        Mock Test-Path {$true} -ParameterFilter {"$Path" -like '*\Updates\LanguageFeature'}
        Mock Get-ChildItem {} -ParameterFilter {"$Path" -like '*\Updates\LanguageFeature'}
        $Warnings = (Get-TaskContentLanguageFeature 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Install.wim Language Features On Demand: Not Found*'
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskContentLanguageInterfacePack' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 11'; InstallationType = 'Client'; Arch = 'x64'; ReleaseId = '25H2'}
        $ExistingTask = $null
        $Lof = 'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LanguagesAndOptionalFeatures'
        $ContentIsoExtract = @(
            New-ContentItem "$Lof\Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab"
            New-ContentItem "$Lof\Microsoft-Windows-Lip-Language-Pack_x64_eu-es.cab"
            New-ContentItem "$Lof\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab"
            New-ContentItem 'IsoExtract\Windows 10 1809 x86 LIP\Microsoft-Windows-Language-Interface-Pack-x86-ca-es.cab'
        )
        Mock Test-Path {$false} -ParameterFilter {"$Path" -like '*\Updates\LanguageInterfacePack'}
        Initialize-GridView
    }

    It 'offers the Language Interface Packs of the architecture' {
        $Result = Get-TaskContentLanguageInterfacePack 6>$null
        $script:GridView.Name | Should -Be @('Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab', 'Microsoft-Windows-Lip-Language-Pack_x64_eu-es.cab')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Install.wim Language Interface Packs:*')}
        @($Result).Count | Should -Be 2
    }

    It 'adds the Language Interface Packs of the release in Content\Updates\LanguageInterfacePack' {
        Mock Test-Path {$true} -ParameterFilter {"$Path" -like '*\Updates\LanguageInterfacePack'}
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\Updates\LanguageInterfacePack\Windows 11 25H2 x64\Microsoft-Windows-Lip-Language-Pack_x64_gl-es.cab"
            New-ContentItem "$ContentRoot\Updates\LanguageInterfacePack\Windows 10 22H2 x64\Microsoft-Windows-Lip-Language-Pack_x64_cy-gb.cab"
            New-ContentItem "$ContentRoot\Updates\LanguageInterfacePack\Windows 11 25H2 x86\Microsoft-Windows-Lip-Language-Pack_x86_gl-es.cab"
        } -ParameterFilter {"$Path" -like '*\Updates\LanguageInterfacePack'}
        Get-TaskContentLanguageInterfacePack 6>$null | Out-Null
        $script:GridView.FullName | Should -Contain 'Updates\LanguageInterfacePack\Windows 11 25H2 x64\Microsoft-Windows-Lip-Language-Pack_x64_gl-es.cab'
        @($script:GridView).Count | Should -Be 3
    }

    It 'adds every Language Interface Pack of Content\Updates when the OSMedia has no ReleaseId' {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 11'; InstallationType = 'Client'; Arch = 'x64'; ReleaseId = $null}
        Mock Test-Path {$true} -ParameterFilter {"$Path" -like '*\Updates\LanguageInterfacePack'}
        Mock Get-ChildItem {New-ContentItem "$ContentRoot\Updates\LanguageInterfacePack\Windows 10 22H2 x64\Microsoft-Windows-Lip-Language-Pack_x64_cy-gb.cab"} -ParameterFilter {"$Path" -like '*\Updates\LanguageInterfacePack'}
        Get-TaskContentLanguageInterfacePack 6>$null | Out-Null
        $script:GridView.FullName | Should -Contain 'Updates\LanguageInterfacePack\Windows 10 22H2 x64\Microsoft-Windows-Lip-Language-Pack_x64_cy-gb.cab'
    }

    It 'does not offer the Language Interface Packs of the existing Task' {
        $ExistingTask = [PSCustomObject]@{LanguageInterfacePack = @("$Lof\Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab")}
        Get-TaskContentLanguageInterfacePack 6>$null | Out-Null
        $script:GridView.Name | Should -Be @('Microsoft-Windows-Lip-Language-Pack_x64_eu-es.cab')
    }

    It 'warns when nothing is selected' {
        Mock Out-GridView {}
        $Warnings = (Get-TaskContentLanguageInterfacePack 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Install.wim Language Interface Packs: Skipping*'
    }

    It 'warns when there are no Language Interface Packs' {
        $ContentIsoExtract = $null
        Mock Test-Path {$true} -ParameterFilter {"$Path" -like '*\Updates\LanguageInterfacePack'}
        Mock Get-ChildItem {} -ParameterFilter {"$Path" -like '*\Updates\LanguageInterfacePack'}
        $Warnings = (Get-TaskContentLanguageInterfacePack 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Install.wim Language Interface Packs: Not Found*'
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskContentLanguagePack' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows 11'; InstallationType = 'Client'; Arch = 'x64'; ReleaseId = '25H2'}
        $ExistingTask = $null
        $Lof = 'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LanguagesAndOptionalFeatures'
        $ContentIsoExtract = @(
            New-ContentItem "$Lof\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab"
            New-ContentItem "$Lof\Microsoft-Windows-Client-Language-Pack_x64_fr-fr.cab"
            New-ContentItem "$Lof\Microsoft-Windows-Server-Language-Pack_x64_de-de.cab"
            New-ContentItem "$Lof\Microsoft-Windows-Lip-Language-Pack_x64_ca-es.cab"
            New-ContentItem "$Lof\Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~.cab"
            New-ContentItem 'IsoExtract\Windows 11 24H2 x64 Languages\x64\langpacks\Microsoft-Windows-Client-Language-Pack_x64_it-it.cab'
            New-ContentItem 'IsoExtract\Windows 11 24H2 x64 Languages\x64\langpacks\Microsoft-Windows-Language-Interface-Pack-x64-ca-es.cab'
            New-ContentItem 'IsoExtract\Windows 11 24H2 FOD\x64\langpacks\Microsoft-Windows-Client-Language-Pack_x64_es-es.cab'
            New-ContentItem 'IsoExtract\Windows 10 2004 x64 Languages\x64\langpacks\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab'
            New-ContentItem 'IsoExtract\Windows Server 2025 24H2 Languages\x64\langpacks\Microsoft-Windows-Server-Language-Pack_x64_de-de.cab'
        )
        Mock Test-Path {$false} -ParameterFilter {("$Path" -like '*\Updates\LanguagePack') -or ("$Path" -like '*\LanguagePacks')}
        Initialize-GridView
    }

    It 'offers the client Language Packs of the release from langpacks and the Languages and Optional Features ISO' {
        $Result = Get-TaskContentLanguagePack 6>$null
        $script:GridView.FullName | Should -Be @(
            'IsoExtract\Windows 11 24H2 x64 Languages\x64\langpacks\Microsoft-Windows-Client-Language-Pack_x64_it-it.cab'
            "$Lof\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab"
            "$Lof\Microsoft-Windows-Client-Language-Pack_x64_fr-fr.cab"
        )
        Should -Invoke Out-GridView -Times 3 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Install.wim Language Packs:*')}
        @($Result).Count | Should -Be 3
    }

    It 'offers only the server Language Packs to a server' {
        $OSMedia = [PSCustomObject]@{OperatingSystem = 'Windows Server'; InstallationType = 'Server'; Arch = 'x64'; ReleaseId = '24H2'}
        Get-TaskContentLanguagePack 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('IsoExtract\Windows Server 2025 24H2 Languages\x64\langpacks\Microsoft-Windows-Server-Language-Pack_x64_de-de.cab')
    }

    It 'adds the Language Packs of Content\Updates\LanguagePack and Content\LanguagePacks relative to the Content directory' {
        Mock Test-Path {$true} -ParameterFilter {("$Path" -like '*\Updates\LanguagePack') -or ("$Path" -like '*\LanguagePacks')}
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\Updates\LanguagePack\Windows 11 25H2 x64\Microsoft-Windows-Client-Language-Pack_x64_nl-nl.cab"
            New-ContentItem "$ContentRoot\Updates\LanguagePack\Windows 11 25H2 x86\Microsoft-Windows-Client-Language-Pack_x86_nl-nl.cab"
        } -ParameterFilter {"$Path" -like '*\Updates\LanguagePack'}
        Mock Get-ChildItem {New-ContentItem "$ContentRoot\LanguagePacks\Windows 11 24H2 x64\Microsoft-Windows-Client-Language-Pack_x64_pl-pl.cab"} -ParameterFilter {"$Path" -like '*\LanguagePacks'}
        Get-TaskContentLanguagePack 6>$null | Out-Null
        $script:GridView.FullName | Should -Contain 'Updates\LanguagePack\Windows 11 25H2 x64\Microsoft-Windows-Client-Language-Pack_x64_nl-nl.cab'
        $script:GridView.FullName | Should -Contain 'LanguagePacks\Windows 11 24H2 x64\Microsoft-Windows-Client-Language-Pack_x64_pl-pl.cab'
        @($script:GridView).Count | Should -Be 5
    }

    It 'does not offer the Language Packs of the existing Task' {
        $ExistingTask = [PSCustomObject]@{LanguagePack = @("$Lof\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab")}
        Get-TaskContentLanguagePack 6>$null | Out-Null
        $script:GridView.FullName | Should -Not -Contain "$Lof\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab"
        @($script:GridView).Count | Should -Be 2
    }

    It 'warns when nothing is selected' {
        Mock Out-GridView {}
        $Warnings = (Get-TaskContentLanguagePack 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Install.wim Language Packs: Skipping*'
    }

    It 'warns when there are no Language Packs' {
        $ContentIsoExtract = $null
        $Warnings = (Get-TaskContentLanguagePack 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Install.wim Language Packs: Not Found*'
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskContentLocalExperiencePacks' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $OSMedia = [PSCustomObject]@{InstallationType = 'Client'}
        $ExistingTask = $null
        $ContentIsoExtract = @(
            New-ContentItem 'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LocalExperiencePack\fr-fr\LanguageExperiencePack.fr-FR.Neutral.appx'
            New-ContentItem 'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LocalExperiencePack\de-de\LanguageExperiencePack.de-DE.Neutral.appx'
            New-ContentItem 'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LocalExperiencePack\de-de\License.xml'
            New-ContentItem 'IsoExtract\Windows Server 2022 Languages\LocalExperiencePack\de-de\LanguageExperiencePack.de-DE.Neutral.appx'
            New-ContentItem 'IsoExtract\Windows 10 Server 1809 Languages\LocalExperiencePack\de-de\LanguageExperiencePack.de-DE.Neutral.appx'
        )
        Initialize-GridView
    }

    It 'offers the client Local Experience Packs sorted by name' {
        $Result = Get-TaskContentLocalExperiencePacks 6>$null
        $script:GridView.FullName | Should -Be @(
            'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LocalExperiencePack\de-de\LanguageExperiencePack.de-DE.Neutral.appx'
            'IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LocalExperiencePack\fr-fr\LanguageExperiencePack.fr-FR.Neutral.appx'
        )
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Install.wim Local Experience Packs:*')}
        @($Result).Count | Should -Be 2
    }

    It 'offers the server Local Experience Packs without Windows 10 to a server' {
        $OSMedia = [PSCustomObject]@{InstallationType = 'Server'}
        Get-TaskContentLocalExperiencePacks 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('IsoExtract\Windows Server 2022 Languages\LocalExperiencePack\de-de\LanguageExperiencePack.de-DE.Neutral.appx')
    }

    It 'does not offer the Local Experience Packs of the existing Task' {
        $ExistingTask = [PSCustomObject]@{LocalExperiencePacks = @('IsoExtract\Windows 11 24H2-26H2 x64 Languages and Optional Features\LocalExperiencePack\fr-fr\LanguageExperiencePack.fr-FR.Neutral.appx')}
        Get-TaskContentLocalExperiencePacks 6>$null | Out-Null
        @($script:GridView).Count | Should -Be 1
    }

    It 'warns when nothing is selected' {
        Mock Out-GridView {}
        $Warnings = (Get-TaskContentLocalExperiencePacks 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Install.wim Local Experience Packs: Skipping*'
    }

    It 'warns when there are no Local Experience Packs' {
        $ContentIsoExtract = @()
        $Warnings = (Get-TaskContentLocalExperiencePacks 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Install.wim Local Experience Packs: Not Found*'
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskContentPacks' {
    BeforeEach {
        $SetOSDBuilderPathContentPacks = "$ContentRoot\ContentPacks"
        $ExistingTask = $null
        Mock Get-ChildItem {
            [PSCustomObject]@{Name = '_Global'}
            [PSCustomObject]@{Name = 'Contoso'}
            [PSCustomObject]@{Name = 'Fabrikam'}
        } -ParameterFilter {("$Path" -eq "$ContentRoot\ContentPacks") -and $Directory}
        Initialize-GridView
    }

    It 'offers the ContentPacks without _Global to add to the Task' {
        $Result = Get-TaskContentPacks 6>$null
        $script:GridView.Name | Should -Be @('Contoso', 'Fabrikam')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'ContentPacks: Select ContentPacks to add to this Task*')}
        $Result.Name | Should -Be @('Contoso', 'Fabrikam')
    }

    It 'offers every ContentPack with -Select' {
        Get-TaskContentPacks -Select 6>$null | Out-Null
        $script:GridView.Name | Should -Be @('_Global', 'Contoso', 'Fabrikam')
        Should -Invoke Out-GridView -Times 3 -Exactly -ParameterFilter {$Title -like 'ContentPacks: Select only the ContentPacks to apply*'}
    }

    It 'does not offer the ContentPacks of the existing Task' {
        $ExistingTask = [PSCustomObject]@{ContentPacks = @('Contoso')}
        Get-TaskContentPacks 6>$null | Out-Null
        $script:GridView.Name | Should -Be @('Fabrikam')
    }

    It 'warns when there are no ContentPacks' {
        Mock Get-ChildItem {[PSCustomObject]@{Name = '_Global'}} -ParameterFilter {$Directory}
        $Warnings = (Get-TaskContentPacks 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*ContentPacks: No Packs exist in $ContentRoot\ContentPacks*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskContentScripts' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $GetOSDBuilderPathContentScripts = "$ContentRoot\Scripts"
        $ExistingTask = $null
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\Scripts\Set-Wallpaper.ps1"
            New-ContentItem "$ContentRoot\Scripts\Remove-Bloat.ps1"
        } -ParameterFilter {("$Path" -eq "$ContentRoot\Scripts") -and ($Filter -eq '*.ps1')}
        Initialize-GridView
    }

    It 'offers the scripts sorted by name relative to the Content directory' {
        $Result = Get-TaskContentScripts 6>$null
        $script:GridView.FullName | Should -Be @('Scripts\Remove-Bloat.ps1', 'Scripts\Set-Wallpaper.ps1')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Scripts:*')}
        $Result[0].Length | Should -Be 1024
    }

    It 'does not offer the scripts of the existing Task' {
        $ExistingTask = [PSCustomObject]@{Scripts = @('Scripts\Remove-Bloat.ps1')}
        Get-TaskContentScripts 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('Scripts\Set-Wallpaper.ps1')
    }

    It 'warns when there are no scripts' {
        Mock Get-ChildItem {} -ParameterFilter {$Filter -eq '*.ps1'}
        $Warnings = (Get-TaskContentScripts 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*Scripts: To select PowerShell Scripts add Content to $ContentRoot\Scripts*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskContentStartLayoutXML' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $GetOSDBuilderPathContentStartLayout = "$ContentRoot\StartLayout"
        $ExistingTask = $null
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\StartLayout\Kiosk.xml"
            New-ContentItem "$ContentRoot\StartLayout\Default.xml"
        } -ParameterFilter {("$Path" -eq "$ContentRoot\StartLayout") -and ($Filter -eq '*.xml')}
        Initialize-GridView
    }

    It 'offers the Start Layouts for a single selection' {
        Get-TaskContentStartLayoutXML 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('StartLayout\Default.xml', 'StartLayout\Kiosk.xml')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {($OutputMode -eq 'Single') -and ($Title -like 'StartLayoutXML:*')}
    }

    It 'does not offer the Start Layout of the existing Task' {
        $ExistingTask = [PSCustomObject]@{StartLayoutXML = 'StartLayout\Kiosk.xml'}
        Get-TaskContentStartLayoutXML 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('StartLayout\Default.xml')
    }

    It 'warns when there are no Start Layouts' {
        Mock Get-ChildItem {} -ParameterFilter {$Filter -eq '*.xml'}
        $Warnings = (Get-TaskContentStartLayoutXML 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*StartLayoutXML: To select a Start Layout, add Content to $ContentRoot\StartLayout*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskContentUnattendXML' {
    BeforeEach {
        $SetOSDBuilderPathContent = $ContentRoot
        $GetOSDBuilderPathContentUnattend = "$ContentRoot\Unattend"
        $ExistingTask = $null
        Mock Get-ChildItem {
            New-ContentItem "$ContentRoot\Unattend\OOBE.xml"
            New-ContentItem "$ContentRoot\Unattend\Audit.xml"
        } -ParameterFilter {("$Path" -eq "$ContentRoot\Unattend") -and ($Filter -eq '*.xml')}
        Initialize-GridView
    }

    It 'offers the Unattend files for a single selection' {
        Get-TaskContentUnattendXML 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('Unattend\Audit.xml', 'Unattend\OOBE.xml')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {($OutputMode -eq 'Single') -and ($Title -like 'UnattendXML:*')}
    }

    It 'does not offer the Unattend file of the existing Task' {
        $ExistingTask = [PSCustomObject]@{UnattendXML = 'Unattend\Audit.xml'}
        Get-TaskContentUnattendXML 6>$null | Out-Null
        $script:GridView.FullName | Should -Be @('Unattend\OOBE.xml')
    }

    It 'warns when there are no Unattend files' {
        Mock Get-ChildItem {} -ParameterFilter {$Filter -eq '*.xml'}
        $Warnings = (Get-TaskContentUnattendXML 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*UnattendXML: To select an Unattend XML, add Content to $ContentRoot\Unattend*"
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskDisableWindowsOptionalFeature' {
    BeforeEach {
        $OSMedia = [PSCustomObject]@{FullName = (Join-Path $TestDrive ([guid]::NewGuid().Guid))}
        $ExistingTask = $null
        $FeatureXml = Join-Path (Join-Path (Join-Path $OSMedia.FullName 'info') 'xml') 'Get-WindowsOptionalFeature.xml'
        New-Item -Path (Split-Path $FeatureXml -Parent) -ItemType Directory -Force | Out-Null
        @(
            [PSCustomObject]@{FeatureName = 'SMB1Protocol'; State = 2}
            [PSCustomObject]@{FeatureName = 'Printing-XPSServices-Features'; State = 3}
            [PSCustomObject]@{FeatureName = 'Microsoft-Windows-Subsystem-Linux'; State = 0}
            [PSCustomObject]@{FeatureName = 'Internet-Explorer-Optional-amd64'; State = 2}
        ) | Export-Clixml -Path $FeatureXml
        Initialize-GridView
    }

    It 'offers the enabled features sorted by name' {
        $Result = Get-TaskDisableWindowsOptionalFeature 6>$null
        $script:GridView.FeatureName | Should -Be @('Internet-Explorer-Optional-amd64', 'Printing-XPSServices-Features', 'SMB1Protocol')
        Should -Invoke Out-GridView -Times 3 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Disable-WindowsOptionalFeature:*')}
        @($Result).Count | Should -Be 3
    }

    It 'does not offer the features of the existing Task' {
        $ExistingTask = [PSCustomObject]@{DisableWindowsOptionalFeature = @('SMB1Protocol')}
        Get-TaskDisableWindowsOptionalFeature 6>$null | Out-Null
        $script:GridView.FeatureName | Should -Not -Contain 'SMB1Protocol'
    }

    It 'returns nothing when the OSMedia has no feature inventory' {
        Remove-Item -Path $FeatureXml
        Get-TaskDisableWindowsOptionalFeature 6>$null | Should -BeNullOrEmpty
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskEnableWindowsOptionalFeature' {
    BeforeEach {
        $OSMedia = [PSCustomObject]@{FullName = (Join-Path $TestDrive ([guid]::NewGuid().Guid))}
        $ExistingTask = $null
        $FeatureXml = Join-Path (Join-Path (Join-Path $OSMedia.FullName 'info') 'xml') 'Get-WindowsOptionalFeature.xml'
        New-Item -Path (Split-Path $FeatureXml -Parent) -ItemType Directory -Force | Out-Null
        @(
            [PSCustomObject]@{FeatureName = 'SMB1Protocol'; State = 2}
            [PSCustomObject]@{FeatureName = 'VirtualMachinePlatform'; State = 0}
            [PSCustomObject]@{FeatureName = 'Microsoft-Windows-Subsystem-Linux'; State = 0}
        ) | Export-Clixml -Path $FeatureXml
        Initialize-GridView
    }

    It 'offers the disabled features sorted by name' {
        $Result = Get-TaskEnableWindowsOptionalFeature 6>$null
        $script:GridView.FeatureName | Should -Be @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Enable-WindowsOptionalFeature:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the features of the existing Task' {
        $ExistingTask = [PSCustomObject]@{EnableWindowsOptionalFeature = @('VirtualMachinePlatform')}
        Get-TaskEnableWindowsOptionalFeature 6>$null | Out-Null
        $script:GridView.FeatureName | Should -Be @('Microsoft-Windows-Subsystem-Linux')
    }

    It 'returns nothing when the OSMedia has no feature inventory' {
        Remove-Item -Path $FeatureXml
        Get-TaskEnableWindowsOptionalFeature 6>$null | Should -BeNullOrEmpty
    }
}

Describe 'Get-TaskRemoveAppxProvisionedPackage' {
    BeforeEach {
        $OSMedia = [PSCustomObject]@{InstallationType = 'Client'; FullName = (Join-Path $TestDrive ([guid]::NewGuid().Guid))}
        $ExistingTask = $null
        $AppxXml = Join-Path (Join-Path (Join-Path $OSMedia.FullName 'info') 'xml') 'Get-AppxProvisionedPackage.xml'
        New-Item -Path (Split-Path $AppxXml -Parent) -ItemType Directory -Force | Out-Null
        @(
            [PSCustomObject]@{DisplayName = 'Microsoft.BingNews'; PackageName = 'Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe'; Version = '4.55.62231.0'}
            [PSCustomObject]@{DisplayName = 'Microsoft.XboxGamingOverlay'; PackageName = 'Microsoft.XboxGamingOverlay_7.325.10.0_neutral_~_8wekyb3d8bbwe'; Version = '7.325.10.0'}
        ) | Export-Clixml -Path $AppxXml
        Initialize-GridView
    }

    It 'offers the provisioned packages of a client' {
        $Result = Get-TaskRemoveAppxProvisionedPackage 6>$null
        $script:GridView.DisplayName | Should -Be @('Microsoft.BingNews', 'Microsoft.XboxGamingOverlay')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Remove-AppxProvisionedPackage:*')}
        $Result[0].PSObject.Properties.Name | Should -Be @('DisplayName', 'PackageName')
    }

    It 'does not offer the packages of the existing Task' {
        $ExistingTask = [PSCustomObject]@{RemoveAppxProvisionedPackage = @('Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe')}
        Get-TaskRemoveAppxProvisionedPackage 6>$null | Out-Null
        $script:GridView.DisplayName | Should -Be @('Microsoft.XboxGamingOverlay')
    }

    It 'returns nothing when the OSMedia has no Appx inventory' {
        Remove-Item -Path $AppxXml
        Get-TaskRemoveAppxProvisionedPackage 6>$null | Should -BeNullOrEmpty
        Should -Invoke Out-GridView -Times 0 -Exactly
    }

    It 'warns that a server is not supported' {
        $OSMedia = [PSCustomObject]@{InstallationType = 'Server'; FullName = $OSMedia.FullName}
        $Warnings = (Get-TaskRemoveAppxProvisionedPackage 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Remove-AppxProvisionedPackage: Unsupported*'
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskRemoveWindowsCapability' {
    BeforeEach {
        $OSMedia = [PSCustomObject]@{FullName = (Join-Path $TestDrive ([guid]::NewGuid().Guid))}
        $ExistingTask = $null
        $CapabilityXml = Join-Path (Join-Path (Join-Path $OSMedia.FullName 'info') 'xml') 'Get-WindowsCapability.xml'
        New-Item -Path (Split-Path $CapabilityXml -Parent) -ItemType Directory -Force | Out-Null
        @(
            [PSCustomObject]@{Name = 'App.StepsRecorder~~~~0.0.1.0'; State = 4}
            [PSCustomObject]@{Name = 'MathRecognizer~~~~0.0.1.0'; State = 4}
            [PSCustomObject]@{Name = 'Rsat.Dns.Tools~~~~0.0.1.0'; State = 0}
        ) | Export-Clixml -Path $CapabilityXml
        Initialize-GridView
    }

    It 'offers the installed capabilities' {
        $Result = Get-TaskRemoveWindowsCapability 6>$null
        $script:GridView.Name | Should -Be @('App.StepsRecorder~~~~0.0.1.0', 'MathRecognizer~~~~0.0.1.0')
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Remove-WindowsCapability:*')}
        @($Result).Count | Should -Be 2
    }

    It 'does not offer the capabilities of the existing Task' {
        $ExistingTask = [PSCustomObject]@{RemoveWindowsCapability = @('MathRecognizer~~~~0.0.1.0')}
        Get-TaskRemoveWindowsCapability 6>$null | Out-Null
        $script:GridView.Name | Should -Be @('App.StepsRecorder~~~~0.0.1.0')
    }

    It 'returns nothing when the OSMedia has no capability inventory' {
        Remove-Item -Path $CapabilityXml
        Get-TaskRemoveWindowsCapability 6>$null | Should -BeNullOrEmpty
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}

Describe 'Get-TaskRemoveWindowsPackage' {
    BeforeEach {
        $OSMedia = [PSCustomObject]@{FullName = (Join-Path $TestDrive ([guid]::NewGuid().Guid))}
        $ExistingTask = $null
        $PackageXml = Join-Path (Join-Path (Join-Path $OSMedia.FullName 'info') 'xml') 'Get-WindowsPackage.xml'
        New-Item -Path (Split-Path $PackageXml -Parent) -ItemType Directory -Force | Out-Null
        @(
            [PSCustomObject]@{PackageName = 'Microsoft-Windows-MediaPlayer-Package~31bf3856ad364e35~amd64~~10.0.26100.1'; PackageState = 4}
            [PSCustomObject]@{PackageName = 'Microsoft-Windows-WordPad-FoD-Package~31bf3856ad364e35~amd64~~10.0.26100.1'; PackageState = 4}
        ) | Export-Clixml -Path $PackageXml
        Initialize-GridView
    }

    It 'offers the packages of the OSMedia' {
        $Result = Get-TaskRemoveWindowsPackage 6>$null
        @($script:GridView).Count | Should -Be 2
        Should -Invoke Out-GridView -Times 2 -Exactly -ParameterFilter {$PassThru -and ($Title -like 'Remove-WindowsPackage:*')}
        $Result[0].PSObject.Properties.Name | Should -Be @('PackageName')
    }

    It 'does not offer the packages of the existing Task' {
        $ExistingTask = [PSCustomObject]@{RemoveWindowsPackage = @('Microsoft-Windows-MediaPlayer-Package~31bf3856ad364e35~amd64~~10.0.26100.1')}
        Get-TaskRemoveWindowsPackage 6>$null | Out-Null
        $script:GridView.PackageName | Should -Be @('Microsoft-Windows-WordPad-FoD-Package~31bf3856ad364e35~amd64~~10.0.26100.1')
    }

    It 'returns nothing when the OSMedia has no package inventory' {
        Remove-Item -Path $PackageXml
        Get-TaskRemoveWindowsPackage 6>$null | Should -BeNullOrEmpty
        Should -Invoke Out-GridView -Times 0 -Exactly
    }
}
