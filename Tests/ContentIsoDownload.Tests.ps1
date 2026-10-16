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
        $Output = Save-OSDBuilderContentIso -Name $InboxApps.Name 6>&1 3>$null | Out-String
        $Output | Should -BeLike "*$(Join-Path (Join-Path $SetOSDBuilderPathContent 'InboxApps') $InboxApps.Name)*"
    }
}
