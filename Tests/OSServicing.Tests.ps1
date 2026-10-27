BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}

    function New-UpdateItem ($Group, $Title, $KB, $FileKB, $Date = '2026-10-14') {
        [PSCustomObject]@{
            UpdateGroup     = $Group
            Title           = $Title
            KBNumber        = $KB
            FileKBNumber    = $FileKB
            CreationDate    = $Date
            OriginUri       = "https://catalog.invalid/windows11.0-kb$($FileKB)-x64_0123456789.msu"
        }
    }
}

Describe 'Enable-NetFXOS' {
    BeforeEach {
        $ScriptName = 'New-OSBuild'; $EnableNetFX3 = 'True'; $OSMajorVersion = 10
        $UpdateOS = 'Windows 11'; $ReleaseId = '25H2'; $OSInstallationType = 'Client'
        $MountDirectory = 'C:\Mount'; $Info = $TestDrive
        $OS = Join-Path $TestDrive 'OS11'
        New-Item -Path (Join-Path $OS 'sources') -ItemType Directory -Force | Out-Null
        $GetOSDBuilderPathContentIsoExtract = Join-Path $TestDrive 'IsoExtract'
        New-Item -Path (Join-Path $GetOSDBuilderPathContentIsoExtract 'Windows 11 24H2-26H2 x64 Languages and Optional Features/LanguagesAndOptionalFeatures/metadata') -ItemType Directory -Force | Out-Null

        $script:NetFx3State = 'DisabledWithPayloadRemoved'
        Mock Get-WindowsOptionalFeature {[PSCustomObject]@{FeatureName = 'NetFx3'; State = $script:NetFx3State}}
        Mock Add-WindowsCapability {$script:NetFx3State = 'Enabled'}
        Mock Enable-WindowsOptionalFeature {$script:NetFx3State = 'Enabled'}
        Mock Update-DotNetOS {}
        Mock Update-CumulativeOS {}
    }

    It 'adds NetFX3~~~~ from the Languages and Optional Features ISO on Windows 11 without sources\sxs' {
        Enable-NetFXOS 6>$null
        Should -Invoke Add-WindowsCapability -Times 1 -Exactly -ParameterFilter {($Name -eq 'NetFX3~~~~') -and ($Source -like '*LanguagesAndOptionalFeatures') -and $LimitAccess}
    }

    It 'applies the .NET CU and does not reapply the LCU on Windows 11' {
        Enable-NetFXOS 6>$null
        Should -Invoke Update-DotNetOS -Times 1 -Exactly -ParameterFilter {$Force}
        Should -Invoke Update-CumulativeOS -Times 0 -Exactly
    }

    It 'uses sources\sxs and reapplies the LCU on Windows 10' {
        $UpdateOS = 'Windows 10'; $ReleaseId = '22H2'
        $OS = Join-Path $TestDrive 'OS10'
        New-Item -Path (Join-Path (Join-Path $OS 'sources') 'sxs') -ItemType Directory -Force | Out-Null
        Enable-NetFXOS 6>$null
        Should -Invoke Add-WindowsCapability -Times 1 -Exactly -ParameterFilter {$Source -like '*sxs'}
        Should -Invoke Update-CumulativeOS -Times 1 -Exactly -ParameterFilter {$Force}
    }

    It 'falls back to Enable-WindowsOptionalFeature when the capability cannot be added' {
        Mock Add-WindowsCapability {throw '0x800f081f'}
        Enable-NetFXOS 6>$null 4>$null
        Should -Invoke Enable-WindowsOptionalFeature -Times 1 -Exactly -ParameterFilter {($FeatureName -eq 'NetFX3') -and $All -and $LimitAccess}
        Should -Invoke Update-DotNetOS -Times 1 -Exactly
    }

    It 'warns and does not apply the .NET CU when NetFx3 is not enabled' {
        Mock Add-WindowsCapability {throw '0x800f081f'}
        Mock Enable-WindowsOptionalFeature {throw '0x800f081f'}
        $Warnings = (Enable-NetFXOS 6>$null 4>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*NetFX 3.5 could not be enabled*'
        Should -Invoke Update-DotNetOS -Times 0 -Exactly
    }

    It 'warns with the download command when there is no source' {
        $GetOSDBuilderPathContentIsoExtract = Join-Path $TestDrive 'Missing'
        $Warnings = (Enable-NetFXOS 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*Save-OSDBuilderDownload -ContentDownload 'Windows 11 24H2-26H2 x64 Languages and Optional Features'*"
        Should -Invoke Add-WindowsCapability -Times 0 -Exactly
    }

    It 'does nothing when NetFx3 is already enabled' {
        $script:NetFx3State = 'Enabled'
        Enable-NetFXOS 6>$null
        Should -Invoke Add-WindowsCapability -Times 0 -Exactly
        Should -Invoke Update-DotNetOS -Times 0 -Exactly
    }

    It 'does nothing when the Task does not enable NetFX3' {
        $EnableNetFX3 = 'False'
        Enable-NetFXOS 6>$null
        Should -Invoke Get-WindowsOptionalFeature -Times 0 -Exactly
    }
}

Describe 'Update-ComponentOS' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'Updates'
        $MountDirectory = 'C:\Mount'; $Info = $TestDrive
        $OSDUpdateComponentDU = @(
            New-UpdateItem 'ComponentDU SafeOS' '2026-10 Safe OS Dynamic Update for Windows 11, version 25H2' '5127654' '5127654'
            New-UpdateItem 'ComponentDU Critical' '2026-10 Dynamic Update for Windows 11' '5000001' '5000001'
        )
        foreach ($Update in $OSDUpdateComponentDU) {New-TestFile -Path (Join-Path $SetOSDBuilderPathUpdates (Split-Path $Update.OriginUri -Leaf)) | Out-Null}
        Mock Get-SessionsXml {}
        Mock Get-WindowsPackage {}
        Mock Add-WindowsPackage {}
    }

    It 'does not apply the Safe OS Dynamic Update to install.wim' {
        Update-ComponentOS 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly -ParameterFilter {$PackagePath -like '*kb5127654*'}
    }

    It 'applies the other Component Dynamic Updates' {
        Update-ComponentOS 6>$null
        Should -Invoke Add-WindowsPackage -Times 1 -Exactly -ParameterFilter {$PackagePath -like '*kb5000001*'}
    }

    It 'does nothing when only a Safe OS Dynamic Update exists' {
        $OSDUpdateComponentDU = @($OSDUpdateComponentDU[0])
        Update-ComponentOS 6>$null
        Should -Invoke Add-WindowsPackage -Times 0 -Exactly
    }
}

Describe 'Update-CumulativeOS' {
    BeforeEach {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'LCU'
        $MountDirectory = 'C:\Mount'; $Info = $TestDrive; $OSMajorVersion = 10; $OSImageName = 'Windows 11 Enterprise'; $ReleaseID = '25H2'
        $OSDUpdateLCU = @(
            New-UpdateItem 'LCU' '2026-10 Cumulative Update (KB5127648)' '5127648' '5127648'
            New-UpdateItem 'LCU' '2026-10 Cumulative Update (KB5127648) - Checkpoint Cumulative Update (KB5043080)' '5127648' '5043080'
        )
        foreach ($Update in $OSDUpdateLCU) {New-TestFile -Path (Join-Path $SetOSDBuilderPathUpdates (Split-Path $Update.OriginUri -Leaf)) | Out-Null}
        $script:Installed = [System.Collections.Generic.List[string]]::new()
        Mock Get-SessionsXml {}
        Mock Test-WindowsPackageCAB {'MSU'}
        Mock Add-WindowsPackage {$script:Installed.Add((Split-Path $PackagePath -Leaf))}
    }

    It 'installs the checkpoint cumulative update before the LCU' {
        Update-CumulativeOS 6>$null 4>$null
        $script:Installed[0] | Should -BeLike '*kb5043080*'
        $script:Installed[1] | Should -BeLike '*kb5127648*'
    }

    It 'reapplies the LCU but not an installed checkpoint cumulative update with -Force' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}}
        Update-CumulativeOS -Force 6>$null 4>$null
        $script:Installed.Count | Should -Be 1
        $script:Installed[0] | Should -BeLike '*kb5127648*'
    }

    It 'installs the LCU from a folder that contains only the LCU and its checkpoint cumulative update' {
        #DISM uses every MSU in the folder of the LCU as a source, an older LCU breaks languages added to the image (0x80070570)
        New-TestFile -Path (Join-Path $SetOSDBuilderPathUpdates 'windows11.0-kb5051987-x64_0123456789.msu') | Out-Null
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}}
        $script:Folders = [System.Collections.Generic.List[string]]::new()
        Mock Add-WindowsPackage {
            $Folder = Split-Path $PackagePath -Parent
            $script:Folders.Add($Folder)
            $script:Installed.Add(((Get-ChildItem -Path $Folder -File).Name | Sort-Object) -join ',')
        }
        Update-CumulativeOS -Force 6>$null 4>$null
        $script:Installed | Should -Be @('windows11.0-kb5043080-x64_0123456789.msu,windows11.0-kb5127648-x64_0123456789.msu')
        $script:Folders[0] | Should -Not -Be $SetOSDBuilderPathUpdates
        Test-Path $script:Folders[0] | Should -BeFalse
    }

    It 'removes the folder of the LCU when the installation fails' {
        Mock Get-SessionsXml {[PSCustomObject]@{TargetState = 'Installed'}}
        $script:Folders = [System.Collections.Generic.List[string]]::new()
        Mock Add-WindowsPackage {$script:Folders.Add((Split-Path $PackagePath -Parent)); throw '0x80070570'}
        Update-CumulativeOS -Force 6>$null 4>$null
        $script:Folders.Count | Should -Be 1
        Test-Path $script:Folders[0] | Should -BeFalse
    }
}

Describe 'New-OSDBuilderLCUFolder' {
    BeforeEach {
        $Source = Join-Path $TestDrive 'Updates'
        $PackagePath = @(
            New-TestFile -Path (Join-Path $Source 'windows11.0-kb5043080-x64_0123456789.msu') -Value 'checkpoint'
            New-TestFile -Path (Join-Path $Source 'windows11.0-kb5127648-x64_0123456789.msu') -Value 'lcu'
        ) | ForEach-Object {"$_"}
        $Destination = Join-Path $Source '_LCU'
    }

    It 'adds only the packages to an empty folder' {
        New-TestFile -Path (Join-Path $Destination 'windows11.0-kb5051987-x64_0123456789.msu') | Out-Null
        New-OSDBuilderLCUFolder -PackagePath $PackagePath -Destination $Destination
        (Get-ChildItem -Path $Destination -File).Name | Sort-Object | Should -Be @('windows11.0-kb5043080-x64_0123456789.msu', 'windows11.0-kb5127648-x64_0123456789.msu')
        Get-Content (Join-Path $Destination 'windows11.0-kb5127648-x64_0123456789.msu') | Should -Be 'lcu'
        Test-Path $PackagePath[1] | Should -BeTrue
    }

    It 'copies a package that cannot be hard linked' {
        Mock New-Item {throw 'The hard link could not be created'} -ParameterFilter {$ItemType -eq 'HardLink'}
        New-OSDBuilderLCUFolder -PackagePath $PackagePath -Destination $Destination
        Get-Content (Join-Path $Destination 'windows11.0-kb5043080-x64_0123456789.msu') | Should -Be 'checkpoint'
    }
}

Describe 'Save-RegistryCurrentVersionOS' {
    It 'writes the registry values without the provider properties and without a JSON depth warning' {
        $Info = Join-Path $TestDrive 'Info'
        $WorkingPath = Join-Path $TestDrive 'Working'
        foreach ($Path in @($WorkingPath, (Join-Path $Info 'json'), (Join-Path $Info 'xml'), (Join-Path $Info 'logs'))) {New-Item -Path $Path -ItemType Directory -Force | Out-Null}
        $RegKeyCurrentVersion = [PSCustomObject]@{
            CurrentBuild        = '26200'
            UBR                 = 9457
            DigitalProductId    = [byte[]](1, 2, 3)
            PSPath              = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\OSD\Microsoft\Windows NT\CurrentVersion'
            PSDrive             = (Get-PSDrive | Select-Object -First 1)
            PSProvider          = (Get-PSProvider -PSProvider FileSystem)
        }
        $Warnings = @(Save-RegistryCurrentVersionOS 3>&1)
        $Warnings.Count | Should -Be 0
        $Json = Get-Content -Path (Join-Path (Join-Path $Info 'json') 'CurrentVersion.json') -Raw | ConvertFrom-Json
        $Json.CurrentBuild | Should -Be '26200'
        $Json.UBR | Should -Be 9457
        $Json.PSObject.Properties.Name | Should -Not -Contain 'PSProvider'
    }
}

Describe 'Get-OSDUpdates' {
    BeforeAll {
        $SetOSDBuilderPathUpdates = Join-Path $TestDrive 'OSDUpdates'
        New-Item -Path $SetOSDBuilderPathUpdates -ItemType Directory -Force | Out-Null
        function New-Manifest ($Title, $Id, [string[]]$Link, $Source = 'Microsoft Update Catalog', $Description = $null) {
            [PSCustomObject]@{
                Title = $Title; Id = $Id; Architecture = 'x64'; Language = ''; Description = $Description; LastModified = '2026-10-14'
                Size = '1 MB'; Classification = 'Security Updates'; SupportedProducts = @('Windows 11'); UpdateId = [guid]::NewGuid().Guid
                Link = $Link; ReleaseId = '25H2'; Source = $Source
            }
        }
        Mock Get-OSDBuilderCatalogManifests {
            New-Manifest '2026-10 Cumulative Update for Windows 11, version 25H2 for x64-based Systems (KB5127648) (26200.9711)' '5127648' @(
                'https://catalog.invalid/windows11.0-kb5127648-x64_2b88.msu'
                'https://catalog.invalid/windows11.0-kb5043080-x64_9534.msu'
            )
            New-Manifest '2026-10 Safe OS Dynamic Update for Windows 11, version 25H2 for x64-based Systems (KB5127654)' '5127654' 'https://catalog.invalid/windows11.0-kb5127654-x64_87d6.cab'
            New-Manifest '2026-10 Setup Dynamic Update for Windows 11, version 25H2 for x64-based Systems (KB5127650)' '5127650' 'https://catalog.invalid/windows11.0-kb5127650-x64_1111.cab'
            New-Manifest '2026-10 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 25H2 for x64 (KB5127690)' '5127690' 'https://catalog.invalid/windows11.0-kb5127690-x64-ndp481_2222.msu'
        }
        Mock Get-WindowsUpdateManifests {
            New-Manifest '2025-02 Cumulative Update for Windows 11, version 25H2 for x64-based Systems (KB5051987)' '5051987' 'https://archive.invalid/windows11.0-kb5051987-x64_aaaa.msu' 'OSD'
            New-Manifest '2025-02 Cumulative Update for Windows 10 Version 22H2 for x64-based Systems (KB5051974)' '5051974' 'https://archive.invalid/windows10.0-kb5051974-x64_bbbb.msu' 'OSD'
        }
        $Updates = @(Get-OSDUpdates -Silent)
    }

    It 'groups the Microsoft Update Catalog updates' {
        ($Updates | Where-Object {$_.FileKBNumber -eq '5127648'}).UpdateGroup | Should -Be 'LCU'
        ($Updates | Where-Object {$_.FileKBNumber -eq '5127654'}).UpdateGroup | Should -Be 'ComponentDU SafeOS'
        ($Updates | Where-Object {$_.FileKBNumber -eq '5127650'}).UpdateGroup | Should -Be 'SetupDU'
        ($Updates | Where-Object {$_.FileKBNumber -eq '5127690'}).UpdateGroup | Should -Be 'DotNetCU'
    }

    It 'returns one update per link of an LCU with checkpoint' {
        @($Updates | Where-Object {$_.KBNumber -eq '5127648'}).Count | Should -Be 2
    }

    It 'names the checkpoint cumulative update in the title' {
        ($Updates | Where-Object {$_.FileKBNumber -eq '5043080'}).Title | Should -BeLike '*- Checkpoint Cumulative Update (KB5043080)'
        ($Updates | Where-Object {$_.FileKBNumber -eq '5127648'}).Title | Should -Not -BeLike '*Checkpoint*'
    }

    It 'replaces the archived updates of a release returned by the Microsoft Update Catalog' {
        $Updates.FileKBNumber | Should -Not -Contain '5051987'
    }

    It 'keeps the archived updates of other releases' {
        ($Updates | Where-Object {$_.FileKBNumber -eq '5051974'}).UpdateOS | Should -Be 'Windows 10'
    }

    It 'detects Windows 11 25H2' {
        ($Updates | Where-Object {$_.FileKBNumber -eq '5127648'}).UpdateBuild | Should -Be '25H2'
        ($Updates | Where-Object {$_.FileKBNumber -eq '5127648'}).UpdateOS | Should -Be 'Windows 11'
    }
}
