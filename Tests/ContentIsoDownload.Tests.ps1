BeforeDiscovery {
    $RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path (Join-Path $RepoRoot 'Private') 'ContentIsoDownload.ps1')
    $CatalogItems = Get-OSDBuilderContentIsoCatalog | ForEach-Object {@{Item = $_; Name = $_.Name}}
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript -Name 'ContentIsoDownload')) {. $Script}

    #ValidateSet of Save-OSDBuilderDownload -ContentDownload
    $SaveDownload = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path $RepoRoot 'Public') 'Save-OSDBuilderDownload.ps1'), [ref]$null, [ref]$null)
    $ContentDownloadParameter = $SaveDownload.FindAll({($args[0] -is [System.Management.Automation.Language.ParameterAst]) -and ($args[0].Name.VariablePath.UserPath -eq 'ContentDownload')}, $true) | Select-Object -First 1
    $ContentDownloadValues = $ContentDownloadParameter.Attributes | Where-Object {$_.TypeName.Name -eq 'ValidateSet'} | ForEach-Object {$_.PositionalArguments.Value}
}

Describe 'Get-OSDBuilderContentIsoCatalog' {
    It 'has unique names' {
        $Names = (Get-OSDBuilderContentIsoCatalog).Name
        ($Names | Sort-Object -Unique).Count | Should -Be $Names.Count
    }

    Context '<Name>' -ForEach $CatalogItems {
        It 'downloads from a Microsoft HTTPS URL' {
            $Item.Url | Should -Match '^https://software-(static|download)\.(download\.prss\.)?microsoft\.com/'
        }

        It 'has the file name of the URL' {
            $Item.Url | Should -BeLike "*/$($Item.FileName)"
        }

        It 'has a size, a type, the ReleaseIds and the content folder' {
            $Item.Size | Should -BeGreaterThan 1GB
            $Item.Type | Should -BeIn @('LanguagesAndOptionalFeatures','InboxApps','LocalExperiencePacks')
            $Item.ReleaseId | Should -Not -BeNullOrEmpty
            $Item.ContentFolder | Should -Not -BeNullOrEmpty
        }

        It 'contains the ReleaseIds in the name, so New-OSBuildTask offers the content' {
            $Item.Name | Should -Match ($Item.ReleaseId[0])
            $Item.Name | Should -Match ($Item.ReleaseId[-1])
        }

        It 'can be downloaded with Save-OSDBuilderDownload -ContentDownload' {
            $ContentDownloadValues | Should -Contain $Item.Name
        }
    }
}

Describe 'Save-OSDBuilderContentIso' {
    BeforeEach {
        $SetOSDBuilderPathContent = Join-Path $TestDrive ([guid]::NewGuid())
        $GetOSDBuilderPathContentIsoExtract = Join-Path $SetOSDBuilderPathContent 'IsoExtract'
        $Item = Get-OSDBuilderContentIsoCatalog | Where-Object {$_.Type -eq 'LanguagesAndOptionalFeatures'} | Select-Object -First 1
        $IsoFile = Join-Path (Join-Path $SetOSDBuilderPathContent 'ISO') $Item.FileName
        $ExtractPath = Join-Path $GetOSDBuilderPathContentIsoExtract $Item.Name

        #The published size is 10 bytes, the tests never download a real ISO
        Mock Invoke-WebRequest {[PSCustomObject]@{Headers = @{'Content-Length' = '10'}}}
        Mock Start-BitsTransfer {Set-Content -Path $Destination -Value '1234567890' -NoNewline -Encoding ascii}
        #BITS is used, curl.exe (the fallback) is not installed
        Mock Get-Command {[PSCustomObject]@{Name = 'Start-BitsTransfer'}} -ParameterFilter {$Name -eq 'Start-BitsTransfer'}
        Mock Get-Command {$null} -ParameterFilter {$Name -eq 'curl.exe'}
        Mock Mount-DiskImage {throw 'Mount-DiskImage is mocked'}
    }

    It 'warns for an unknown name' {
        $Warnings = (Save-OSDBuilderContentIso -Name 'Windows 11 99H9 x64 Languages and Optional Features' 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*is not available*'
        Should -Invoke Start-BitsTransfer -Times 0 -Exactly
    }

    It 'downloads the ISO with BITS when it does not exist' {
        Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>$null
        Should -Invoke Start-BitsTransfer -Times 1 -Exactly -ParameterFilter {$Source -eq $Item.Url}
        (Get-Item $IsoFile).Length | Should -Be 10
    }

    It 'does not download an ISO with the published size again' {
        New-Item -Path (Split-Path $IsoFile -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -Path $IsoFile -Value '1234567890' -NoNewline -Encoding ascii
        Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>$null
        Should -Invoke Start-BitsTransfer -Times 0 -Exactly
    }

    It 'does nothing when the ISO is downloaded and extracted' {
        New-Item -Path (Split-Path $IsoFile -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -Path $IsoFile -Value '1234567890' -NoNewline -Encoding ascii
        New-TestFile -Path (Join-Path $ExtractPath "$($Item.FileName).extracted") | Out-Null
        Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>$null
        Should -Invoke Start-BitsTransfer -Times 0 -Exactly
        Should -Invoke Mount-DiskImage -Times 0 -Exactly
    }

    It 'warns and stops when the download is incomplete' {
        Mock Start-BitsTransfer {throw 'BITS is not available'}
        $Warnings = (Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Content ISO: The download is incomplete, run the command again to resume*'
        Should -Invoke Mount-DiskImage -Times 0 -Exactly
    }

    It 'warns and stops when there is not enough free space' {
        Mock Get-PSDrive {[PSCustomObject]@{Free = 5}}
        $Warnings = (Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*of free space is required*'
        Should -Invoke Start-BitsTransfer -Times 0 -Exactly
    }

    It 'does not write the extracted marker when the extract fails' {
        $Warnings = (Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Mount-DiskImage is mocked*'
        Join-Path $ExtractPath "$($Item.FileName).extracted" | Should -Not -Exist
    }

    It 'extracts Inbox Apps to Content\InboxApps' {
        $InboxApps = Get-OSDBuilderContentIsoCatalog | Where-Object {$_.Type -eq 'InboxApps'} | Select-Object -First 1
        New-TestFile -Path (Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContent 'InboxApps') $InboxApps.Name) "$($InboxApps.FileName).extracted") | Out-Null
        $Output = (Save-OSDBuilderContentIso -Name $InboxApps.Name 6>&1 3>$null | ForEach-Object {"$_"}) -join "`n"
        $Output | Should -BeLike "*$(Join-Path (Join-Path $SetOSDBuilderPathContent 'InboxApps') $InboxApps.Name)*"
    }

    It 'uses the catalog size when the published size can not be read' {
        Mock Invoke-WebRequest {throw 'offline'}
        Mock Get-PSDrive {throw 'no drive'}
        $Verbose = (Save-OSDBuilderContentIso -Name $Item.Name -Verbose 6>$null 3>$null 4>&1) -join "`n"
        $Verbose | Should -BeLike "*Unable to read the published size, using $($Item.Size) bytes*"
        $Verbose | Should -BeLike '*Unable to read the free space of*'
        Should -Invoke Start-BitsTransfer -Times 1 -Exactly
        #10 bytes are not the catalog size
        Should -Invoke Mount-DiskImage -Times 0 -Exactly
    }

    It 'uses the catalog size when the published size is <Case>' -ForEach @(
        @{Case = 'missing'; Headers = @{}}
        @{Case = 'zero'; Headers = @{'Content-Length' = '0'}}
        @{Case = 'not a number'; Headers = @{'Content-Length' = 'abc'}}
    ) {
        Mock Invoke-WebRequest {[PSCustomObject]@{Headers = $Headers}}
        $Warnings = (Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*The download is incomplete*'
    }

    It 'deletes an incomplete ISO before the BITS download' {
        New-Item -Path (Split-Path $IsoFile -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -Path $IsoFile -Value '12345' -NoNewline -Encoding ascii
        Mock Remove-Item {} -ParameterFilter {$Path -eq $IsoFile}
        Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>$null
        Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter {$Path -eq $IsoFile}
        Should -Invoke Start-BitsTransfer -Times 1 -Exactly -ParameterFilter {$Destination -eq $IsoFile -and $DisplayName -eq $Item.Name}
    }

    Context 'curl.exe fallback' {
        BeforeEach {
            Mock Get-Command {$null} -ParameterFilter {$Name -eq 'Start-BitsTransfer'}
            Mock Get-Command {[PSCustomObject]@{Name = 'curl.exe'}} -ParameterFilter {$Name -eq 'curl.exe'}
            Mock curl.exe {
                $Arguments = @($InputObject) + @($RemainingArguments)
                $Output = $Arguments[[array]::IndexOf($Arguments, '--output') + 1]
                Set-Content -Path $Output -Value '1234567890' -NoNewline -Encoding ascii
                $global:LASTEXITCODE = 0
            }
        }

        It 'resumes the download with curl.exe when BITS is not available' {
            Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>$null
            Should -Invoke Start-BitsTransfer -Times 0 -Exactly
            Should -Invoke curl.exe -Times 1 -Exactly -ParameterFilter {
                $Arguments = @($InputObject) + @($RemainingArguments)
                (($Arguments -join ' ') -like '*--location*--fail*--retry 3*--continue-at -*') -and ($Arguments -contains $IsoFile) -and ($Arguments -contains $Item.Url)
            }
            (Get-Item $IsoFile).Length | Should -Be 10
            #The download is complete, the extract starts
            Should -Invoke Mount-DiskImage -Times 1 -Exactly
        }

        It 'uses curl.exe when the BITS download fails' {
            Mock Get-Command {[PSCustomObject]@{Name = 'Start-BitsTransfer'}} -ParameterFilter {$Name -eq 'Start-BitsTransfer'}
            Mock Start-BitsTransfer {throw 'BITS service is stopped'}
            $Warnings = (Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>&1) -join "`n"
            $Warnings | Should -BeLike '*Content ISO: BITS download failed, BITS service is stopped*'
            Should -Invoke curl.exe -Times 1 -Exactly
            (Get-Item $IsoFile).Length | Should -Be 10
        }

        It 'warns when curl.exe fails' {
            Mock curl.exe {$global:LASTEXITCODE = 22}
            $Warnings = (Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>&1) -join "`n"
            $Warnings | Should -BeLike '*Content ISO: curl.exe download failed with exit code 22*'
            $Warnings | Should -BeLike '*The download is incomplete*'
            Should -Invoke Mount-DiskImage -Times 0 -Exactly
        }
    }

    Context 'Extract' {
        BeforeEach {
            New-Item -Path (Split-Path $IsoFile -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $IsoFile -Value '1234567890' -NoNewline -Encoding ascii
            $script:DiskImage = [PSCustomObject]@{ImagePath = $IsoFile}
            Mock Mount-DiskImage {$script:DiskImage}
            Mock Dismount-DiskImage {}
            #On Windows the DiskImage parameter of Get-Volume takes MSFT_DiskImage CIM instances only
            Mock Get-Volume {[PSCustomObject]@{DriveLetter = 'X'}} -RemoveParameterType 'DiskImage'
            Mock Start-Sleep {}
            #robocopy copies the content folder of the catalog item
            Mock robocopy {
                $Arguments = @($InputObject) + @($RemainingArguments)
                New-Item -Path (Join-Path $Arguments[1] $Item.ContentFolder) -ItemType Directory -Force | Out-Null
                $global:LASTEXITCODE = 1
            }
        }

        It 'copies the ISO with robocopy and writes the extracted marker' {
            $Output = (Save-OSDBuilderContentIso -Name $Item.Name 6>&1 3>$null | ForEach-Object {"$_"}) -join "`n"
            Should -Invoke Mount-DiskImage -Times 1 -Exactly -ParameterFilter {$ImagePath -eq $IsoFile -and $StorageType -eq 'ISO' -and $PassThru}
            Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {
                $Arguments = @($InputObject) + @($RemainingArguments)
                ($Arguments[0] -eq 'X:\') -and ($Arguments[1] -eq $ExtractPath) -and ($Arguments -contains '/e') -and ($Arguments -contains '/xj') -and
                (@($Arguments | Where-Object {$_ -like "/log:*Extract-$($Item.Build)-$($Item.Type).log"}).Count -eq 1)
            }
            Should -Invoke Dismount-DiskImage -Times 1 -Exactly -ParameterFilter {$ImagePath -eq $IsoFile}
            Join-Path $ExtractPath "$($Item.FileName).extracted" | Should -Exist
            $Output | Should -BeLike '*Content ISO: Complete*'
            $Output | Should -BeLike "*Use New-OSBuildTask to select the Language Packs, Language Features and Features on Demand for Windows 11 $($Item.ReleaseId -join ', ')*"
        }

        It 'repeats an extract without marker' {
            New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null
            Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>$null
            Should -Invoke robocopy -Times 1 -Exactly
            Join-Path $ExtractPath "$($Item.FileName).extracted" | Should -Exist
        }

        It 'shows the content of <Type>' -ForEach @(
            @{Type = 'InboxApps'; Expected = '*The Inbox Apps for Windows 11 * are in *packages*'}
            @{Type = 'LocalExperiencePacks'; Expected = '*Use New-OSBuildTask -ContentLanguagePackages to select the Local Experience Packs for Windows 10 2004*'}
        ) {
            $Item = Get-OSDBuilderContentIsoCatalog | Where-Object {$_.Type -eq $Type} | Select-Object -First 1
            $IsoFile = Join-Path (Join-Path $SetOSDBuilderPathContent 'ISO') $Item.FileName
            Set-Content -Path $IsoFile -Value '1234567890' -NoNewline -Encoding ascii
            $Output = (Save-OSDBuilderContentIso -Name $Item.Name 6>&1 3>$null | ForEach-Object {"$_"}) -join "`n"
            $Output | Should -BeLike $Expected
            if ($Type -eq 'InboxApps') {$Target = Join-Path (Join-Path $SetOSDBuilderPathContent 'InboxApps') $Item.Name}
            else {$Target = Join-Path $GetOSDBuilderPathContentIsoExtract $Item.Name}
            Join-Path $Target "$($Item.FileName).extracted" | Should -Exist
        }

        It 'waits for the drive letter of the mounted ISO' {
            $script:VolumeCalls = 0
            Mock Get-Volume {$script:VolumeCalls++; if ($script:VolumeCalls -ge 3) {[PSCustomObject]@{DriveLetter = 'Y'}}} -RemoveParameterType 'DiskImage'
            Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>$null
            Should -Invoke Start-Sleep -Times 2 -Exactly
            Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {$InputObject -eq 'Y:\'}
        }

        It 'warns and dismounts when the ISO has no drive letter' {
            Mock Get-Volume {} -RemoveParameterType 'DiskImage'
            $Warnings = (Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>&1) -join "`n"
            $Warnings | Should -BeLike "*Content ISO: Unable to get the drive letter of $IsoFile*"
            Should -Invoke Start-Sleep -Times 10 -Exactly
            Should -Invoke robocopy -Times 0 -Exactly
            Should -Invoke Dismount-DiskImage -Times 1 -Exactly
            Join-Path $ExtractPath "$($Item.FileName).extracted" | Should -Not -Exist
        }

        It 'warns and does not write the marker when robocopy fails' {
            Mock robocopy {$global:LASTEXITCODE = 8}
            $Warnings = (Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>&1) -join "`n"
            $Warnings | Should -BeLike '*Content ISO: robocopy failed with exit code 8, review *Extract-*.log*'
            $Warnings | Should -Not -BeLike '*Complete*'
            Should -Invoke Dismount-DiskImage -Times 1 -Exactly
            Join-Path $ExtractPath "$($Item.FileName).extracted" | Should -Not -Exist
        }

        It 'warns and does not write the marker when the content folder is missing' {
            Mock robocopy {$global:LASTEXITCODE = 0}
            $Warnings = (Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>&1) -join "`n"
            $Warnings | Should -BeLike "*Content ISO: $IsoFile does not contain a $($Item.ContentFolder) directory*"
            Should -Invoke Dismount-DiskImage -Times 1 -Exactly
            Join-Path $ExtractPath "$($Item.FileName).extracted" | Should -Not -Exist
        }

        It 'does not dismount when the mount fails' {
            Mock Mount-DiskImage {throw 'Access denied'}
            $Warnings = (Save-OSDBuilderContentIso -Name $Item.Name 6>$null 3>&1) -join "`n"
            $Warnings | Should -BeLike '*Content ISO: Access denied*'
            Should -Invoke Dismount-DiskImage -Times 0 -Exactly
        }
    }
}
