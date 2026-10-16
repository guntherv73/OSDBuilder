BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    $PublicPath = Join-Path $RepoRoot 'Public'
    foreach ($Name in 'Get-OSDBuilder', 'Get-OSMedia', 'Get-OSBuilds', 'Get-PEBuilds', 'New-OSDBuilderContentPack', 'New-OSDBuilderISO', 'New-OSDBuilderUSB', 'New-OSDBuilderVHD', 'Show-OSDBuilderInfo') {
        . (Join-Path $PublicPath "$Name.ps1")
    }

    #The functions build paths with $env:PROCESSOR_ARCHITECTURE and $env:Temp, they are not set on Linux
    $SavedProcessorArchitecture = $env:PROCESSOR_ARCHITECTURE
    $SavedTemp = $env:Temp
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'

    function New-TestMedia {
        <#
        .SYNOPSIS
        Creates an OSMedia, OSBuild or PEBuild directory with info\xml\Get-WindowsImage.xml and the boot files of the OS directory
        #>
        param (
            [string]$Name,
            [hashtable]$Property = @{},
            [hashtable]$Image = @{},
            [switch]$NoOS,
            [switch]$NoEtfsboot,
            [switch]$NoEfisys
        )
        $FullName = Join-Path (Join-Path $TestDrive 'OSMedia') $Name
        $Xml = Join-Path (Join-Path $FullName 'info') 'xml'
        New-Item -Path $Xml -ItemType Directory -Force | Out-Null
        $WindowsImage = @{Architecture = 9; ImageName = 'Windows 10 Enterprise (x64)'; UBR = '19045.1'}
        foreach ($Key in $Image.Keys) {$WindowsImage[$Key] = $Image[$Key]}
        [PSCustomObject]$WindowsImage | Export-Clixml -Path (Join-Path $Xml 'Get-WindowsImage.xml')
        if (-not $NoOS) {
            $OS = Join-Path $FullName 'OS'
            New-Item -Path $OS -ItemType Directory -Force | Out-Null
            if (-not $NoEtfsboot) {New-TestFile -Path (Join-Path (Join-Path $OS 'boot') 'etfsboot.com') | Out-Null}
            if (-not $NoEfisys) {New-TestFile -Path (Join-Path (Join-Path (Join-Path (Join-Path $OS 'efi') 'microsoft') 'boot') 'efisys.bin') | Out-Null}
        }
        $Media = @{
            Name = $Name; FullName = $FullName; MediaType = 'OSMedia'; OperatingSystem = 'Windows 10'; MajorVersion = 10
            Version = '10.0.19045.1'; Arch = 'x64'; ReleaseId = '22H2'; UBR = '19045.1'
        }
        foreach ($Key in $Property.Keys) {$Media[$Key] = $Property[$Key]}
        [PSCustomObject]$Media
    }
}

AfterAll {
    $env:PROCESSOR_ARCHITECTURE = $SavedProcessorArchitecture
    $env:Temp = $SavedTemp
    foreach ($Name in 'GetAppxProvisionedPackage', 'GetWindowsCapability', 'GetWindowsOptionalFeature', 'GetWindowsPackage', 'GetWindowsImage') {
        Remove-Variable -Name $Name -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'New-OSDBuilderContentPack' {
    BeforeEach {
        $SetOSDBuilderPathContentPacks = Join-Path $TestDrive ([guid]::NewGuid())
        Mock Get-OSDBuilder {}
    }

    It 'creates the OS and WinPE directories of a ContentPack with -ContentType All' {
        New-OSDBuilderContentPack -Name 'Contoso'
        Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$HideDetails}
        $Pack = Join-Path $SetOSDBuilderPathContentPacks 'Contoso'
        foreach ($Directory in 'Media\ALL', 'OSDrivers\x64', 'OSExtraFiles\ALL Subdirs', 'OSPoshMods\System', 'OSRegistry\ALL', 'OSScripts\x64', 'OSStartLayout\ALL',
            'PEDaRT', 'PEDrivers\x64', 'PEExtraFiles\x64 Subdirs', 'PEPoshMods\ProgramFiles', 'PERegistry\ALL', 'PEScripts\x64') {
            Join-Path $Pack $Directory | Should -Exist
        }
        @(Get-ChildItem -Path $Pack -Directory -Recurse).Count | Should -Be 37
    }

    It 'creates only the OS directories with -ContentType OS' {
        New-OSDBuilderContentPack -Name 'OSOnly' -ContentType OS
        $Pack = Join-Path $SetOSDBuilderPathContentPacks 'OSOnly'
        Join-Path $Pack 'OSDrivers\ALL' | Should -Exist
        Join-Path $Pack 'PEDrivers' | Should -Not -Exist
    }

    It 'creates only the WinPE directories with -ContentType WinPE' {
        New-OSDBuilderContentPack -Name 'PEOnly' -ContentType WinPE
        $Pack = Join-Path $SetOSDBuilderPathContentPacks 'PEOnly'
        Join-Path $Pack 'PEDaRT' | Should -Exist
        Join-Path $Pack 'OSDrivers' | Should -Not -Exist
    }

    It 'creates no directories with -ContentType MultiLang, the MultiLang ContentPack has no directories' {
        New-OSDBuilderContentPack -Name 'MultiLang' -ContentType MultiLang
        Join-Path $SetOSDBuilderPathContentPacks 'MultiLang' | Should -Not -Exist
    }

    It 'keeps the content of an existing ContentPack' {
        New-OSDBuilderContentPack -Name 'Contoso'
        $Driver = New-TestFile -Path (Join-Path (Join-Path $SetOSDBuilderPathContentPacks 'Contoso') 'OSDrivers\x64\driver.inf')
        New-OSDBuilderContentPack -Name 'Contoso'
        $Driver.FullName | Should -Exist
    }

    It 'requires a name' {
        {New-OSDBuilderContentPack -Name ''} | Should -Throw
    }
}

Describe 'New-OSDBuilderISO' {
    BeforeEach {
        $SetOSDBuilderPathContent = Join-Path $TestDrive ([guid]::NewGuid())
        $OscdimgFolder = Join-Path (Join-Path (Join-Path $SetOSDBuilderPathContent 'Tools') 'AMD64') 'Oscdimg'
        $Oscdimg = New-TestFile -Path (Join-Path $OscdimgFolder 'oscdimg.exe')
        Mock Get-OSDBuilder {}
        Mock Get-OSMedia {$OSMedia}
        Mock Get-OSBuilds {}
        Mock Get-PEBuilds {}
        Mock Start-Process {}
        Mock Out-GridView {$InputObject | Where-Object {$_.Name -eq 'Selected'}}
        #The ADK is never used from the real system
        Mock Test-Path {$false} -ParameterFilter {$Path -like 'C:\Program Files*'}
    }

    Context 'ISO name and label' {
        It 'creates <IsoName>.iso of a <MediaType> <OperatingSystem> <Version>' -ForEach @(
            @{MediaType = 'PEBuild'; OperatingSystem = 'Windows 10'; MajorVersion = 10; Version = '10.0.19041.1'; Architecture = 9; IsoName = 'WinPE10 x64 2004 19041.1'; Label = 'WinPE10 x64 2004 19041.1'}
            @{MediaType = 'PEBuild'; OperatingSystem = 'Windows 8.1'; MajorVersion = 6; Version = '6.3.9600.1'; Architecture = 0; IsoName = 'WinPE5 x64 19041.1'; Label = 'WinPE5 x64 19041.1'}
            @{MediaType = 'PEBuild'; OperatingSystem = 'Windows 8'; MajorVersion = 6; Version = '6.2.9200.1'; Architecture = 6; IsoName = 'WinPE4 x64 19041.1'; Label = 'WinPE4 x64 19041.1'}
            @{MediaType = 'PEBuild'; OperatingSystem = 'Windows 7'; MajorVersion = 6; Version = '6.1.7601.1'; Architecture = 12; IsoName = 'WinPE3 x64 19041.1'; Label = 'WinPE3 x64 19041.1'}
            @{MediaType = 'OSMedia'; OperatingSystem = 'Windows Server 2022'; MajorVersion = 10; Version = '10.0.20348.1'; Architecture = 9; IsoName = 'Server 10.0.20348.1'; Label = 'Server 10.0.20348.1'}
            @{MediaType = 'OSBuild'; OperatingSystem = 'Windows 11'; MajorVersion = 10; Version = '10.0.26100.1'; Architecture = 9; IsoName = 'Win11 x64 2004 19041.1'; Label = 'Win11 x64 2004 19041.1'}
            @{MediaType = 'OSMedia'; OperatingSystem = 'Windows 10'; MajorVersion = 10; Version = '10.0.19041.1'; Architecture = 9; IsoName = 'Win10 x64 2004 19041.1'; Label = 'Win10 x64 2004 19041.1'}
            @{MediaType = 'OSMedia'; OperatingSystem = 'Windows 8.1'; MajorVersion = 6; Version = '6.3.9600.1'; Architecture = 9; IsoName = 'Win8.1 x64 19041.1'; Label = 'Win8.1 x64 19041.1'}
            @{MediaType = 'OSMedia'; OperatingSystem = 'Windows 8'; MajorVersion = 6; Version = '6.2.9200.1'; Architecture = 9; IsoName = 'Win8 x64 19041.1'; Label = 'Win8 x64 19041.1'}
            @{MediaType = 'OSMedia'; OperatingSystem = 'Windows 7'; MajorVersion = 6; Version = '6.1.7601.1'; Architecture = 9; IsoName = 'Win7 x64 19041.1'; Label = 'Win7 x64 19041.1'}
            @{MediaType = 'OSMedia'; OperatingSystem = 'Windows Vista'; MajorVersion = 6; Version = '6.0.6002.1'; Architecture = 9; IsoName = 'Win x64 19041.1'; Label = 'Win x64 19041.1'}
        ) {
            $Media = New-TestMedia -Name 'Media' -Image @{Architecture = $Architecture} -Property @{
                MediaType = $MediaType; OperatingSystem = $OperatingSystem; MajorVersion = $MajorVersion; Version = $Version; ReleaseId = '2004'; UBR = '19041.1'
            }
            $OSMedia = @($Media)
            $Result = New-OSDBuilderISO -FullName $Media.FullName -PassThru 6>$null

            $IsoFile = "$($Media.FullName)\ISO\$IsoName.iso"
            $Result.FilePath | Should -Be $IsoFile
            $Result.Label | Should -Be $Label
            $Result.SourceFolder | Should -Be "$($Media.FullName)\OS"
            Join-Path $Media.FullName 'ISO' | Should -Exist
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                ($FilePath -eq "$SetOSDBuilderPathContent\Tools\AMD64\Oscdimg\oscdimg.exe") -and ($ArgumentList[-3] -eq "-l`"$Label`"") -and ($ArgumentList[-1] -eq "`"$IsoFile`"")
            }
        }

        It 'names the ISO of a PEBuild of an unknown version like the label' -Skip {
            # KnownBug: New-OSDBuilderISO.ps1:136 names the ISO of a PEBuild of an unknown version 'WinPE5 ...' instead of 'WinPE ...'
            $Media = New-TestMedia -Name 'Media' -Property @{MediaType = 'PEBuild'; MajorVersion = 5; Version = '5.0.1'; UBR = '1.1'}
            $OSMedia = @($Media)
            $Result = New-OSDBuilderISO -FullName $Media.FullName -PassThru 6>$null
            $Result.Label | Should -Be 'WinPE x64 1.1'
            $Result.FilePath | Should -Be "$($Media.FullName)\ISO\WinPE x64 1.1.iso"
        }
    }

    It 'calls oscdimg with the boot data of etfsboot.com and efisys.bin of the OS' {
        $Media = New-TestMedia -Name 'Win10' -Image @{ImageName = 'Windows 10 Enterprise (x64)'}
        $OSMedia = @($Media)
        New-OSDBuilderISO -FullName $Media.FullName 6>$null | Should -BeNullOrEmpty

        $OS = "$($Media.FullName)\OS"
        $BootData = '-bootdata:2#p0,e,b"{0}"#pEF,e,b"{1}"' -f "$OS\boot\etfsboot.com", "$OS\efi\microsoft\boot\efisys.bin"
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            ($Wait) -and
            (($ArgumentList -join '|') -eq (@('-m', '-o', '-u2', $BootData, '-u2', '-udfver102', '-l"Win10 x64 22H2 19045.1"', "`"$OS`"", "`"$($Media.FullName)\ISO\Win10 x64 22H2 19045.1.iso`"") -join '|'))
        }
    }

    It 'creates an ISO of every media of -FullName' {
        $First = New-TestMedia -Name 'First' -Property @{UBR = '19045.1'}
        $Second = New-TestMedia -Name 'Second' -Property @{UBR = '19045.2'}
        $OSMedia = @($First, $Second, (New-TestMedia -Name 'Third'))
        $Result = New-OSDBuilderISO -FullName $First.FullName, $Second.FullName -PassThru 6>$null
        $Result.FilePath | Should -Be @("$($First.FullName)\ISO\Win10 x64 22H2 19045.1.iso", "$($Second.FullName)\ISO\Win10 x64 22H2 19045.2.iso")
        Should -Invoke Start-Process -Times 2 -Exactly
    }

    It 'selects the media in Out-GridView without -FullName' {
        $OSMedia = @((New-TestMedia -Name 'Selected'), (New-TestMedia -Name 'NotSelected'))
        $Result = New-OSDBuilderISO -PassThru 6>$null
        Should -Invoke Out-GridView -Times 1 -ParameterFilter {$PassThru -and ($Title -like '*create an ISO*')}
        $Result.SourceFolder | Should -Be "$($OSMedia[0].FullName)\OS"
        Should -Invoke Start-Process -Times 1 -Exactly
    }

    It 'uses oscdimg of the ADK at <Path>' -ForEach @(
        @{Path = 'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\AMD64\Oscdimg'}
        @{Path = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\AMD64\Oscdimg'}
    ) {
        Remove-Item -Path $Oscdimg.FullName
        $AdkOscdimg = "$Path\oscdimg.exe"
        Mock Test-Path {$true} -ParameterFilter {$Path -eq $AdkOscdimg}
        $OSMedia = @(New-TestMedia -Name 'Win10')
        New-OSDBuilderISO -FullName $OSMedia[0].FullName 6>$null
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {$FilePath -eq $AdkOscdimg}
    }

    It 'warns and stops when oscdimg is not found' {
        Remove-Item -Path $Oscdimg.FullName
        $OSMedia = @(New-TestMedia -Name 'Win10')
        #New-OSDBuilderISO stops with Break, the loop contains it
        $Warnings = foreach ($Run in 1) {New-OSDBuilderISO -FullName $OSMedia[0].FullName 6>$null 3>&1}
        ($Warnings -join "`n") | Should -BeLike '*Could not locate OSCDIMG in Windows ADK*'
        ($Warnings -join "`n") | Should -BeLike "*$SetOSDBuilderPathContent\Tools\AMD64\Oscdimg\oscdimg.exe*"
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'warns when the media has no OS directory' {
        $OSMedia = @(New-TestMedia -Name 'NoOS' -NoOS)
        $Warnings = (New-OSDBuilderISO -FullName $OSMedia[0].FullName 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike "*Could not locate $($OSMedia[0].FullName)\OS*"
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'warns when etfsboot.com is missing' {
        $OSMedia = @(New-TestMedia -Name 'NoEtfsboot' -NoEtfsboot)
        $Warnings = (New-OSDBuilderISO -FullName $OSMedia[0].FullName 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Could not locate*etfsboot.com*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'creates the ISO of the next media when a media has no OS directory' -Skip {
        # KnownBug: New-OSDBuilderISO.ps1:284 Return in the foreach of the Process block skips all remaining selected media
        $NoOS = New-TestMedia -Name 'NoOS' -NoOS
        $Valid = New-TestMedia -Name 'Valid'
        $OSMedia = @($NoOS, $Valid)
        New-OSDBuilderISO -FullName $NoOS.FullName, $Valid.FullName 6>$null 3>$null
        Should -Invoke Start-Process -Times 1 -Exactly
    }

    It 'uses efisys.bin of <Location> when the OS has none' -ForEach @(
        @{Location = 'Content\Tools'; Path = $null}
        @{Location = 'the ADK'; Path = 'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\AMD64\Oscdimg\efisys.bin'}
        @{Location = 'the x86 ADK'; Path = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\AMD64\Oscdimg\efisys.bin'}
    ) {
        $OSMedia = @(New-TestMedia -Name 'NoEfisys' -NoEfisys)
        if ($Path) {
            $Efisys = $Path
            Mock Test-Path {$true} -ParameterFilter {$Path -eq $Efisys}
        } else {
            $Efisys = "$SetOSDBuilderPathContent\Tools\AMD64\Oscdimg\efisys.bin"
            New-TestFile -Path (Join-Path $OscdimgFolder 'efisys.bin') | Out-Null
        }
        New-OSDBuilderISO -FullName $OSMedia[0].FullName 6>$null
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {$ArgumentList[3] -like "*#pEF,e,b`"$Efisys`""}
    }

    It 'warns when efisys.bin is not found' {
        $OSMedia = @(New-TestMedia -Name 'NoEfisys' -NoEfisys)
        $Warnings = (New-OSDBuilderISO -FullName $OSMedia[0].FullName 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Could not locate*efisys.bin*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

Describe 'New-OSDBuilderUSB' {
    BeforeEach {
        $Media = New-TestMedia -Name 'Win10'
        Mock Get-OSDBuilder {}
        Mock Block-StandardUser {}
        Mock Get-OSMedia {$Media}
        Mock Get-OSBuilds {}
        Mock Get-PEBuilds {}
        Mock Get-Disk {
            [PSCustomObject]@{Number = 1; Size = 512GB; BusType = 'NVMe'}
            [PSCustomObject]@{Number = 2; Size = 64GB; BusType = 'USB'}
            [PSCustomObject]@{Number = 3; Size = 16GB; BusType = 'USB'}
        }
        Mock Out-GridView {$InputObject | Where-Object {$_}}
        #The Storage cmdlets take CimInstances on Windows, the tests pipe PSCustomObjects
        Mock Clear-Disk {$InputObject} -RemoveParameterType InputObject
        Mock New-Partition {[PSCustomObject]@{DiskNumber = $InputObject.Number; PartitionNumber = 1}} -RemoveParameterType InputObject
        Mock Format-Volume {[PSCustomObject]@{DriveLetter = 'U'; FileSystemLabel = $NewFileSystemLabel}} -RemoveParameterType InputObject
        Mock Set-Location {}
        Mock bootsect.exe {}
        Mock Copy-Item {}
    }

    It 'formats the selected USB drive of up to 32 GB with FAT32, makes it bootable and copies the OS' {
        $Warnings = (New-OSDBuilderUSB -FullName $Media.FullName 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*USB will be formatted FAT32*'
        Should -Invoke Block-StandardUser -Times 1 -Exactly
        Should -Invoke Out-GridView -Times 1 -Exactly -ParameterFilter {($InputObject.Number -eq 3) -and ($OutputMode -eq 'Single')}
        Should -Invoke Clear-Disk -Times 1 -Exactly -ParameterFilter {($InputObject.Number -eq 3) -and $RemoveData -and $RemoveOEM -and $PassThru -and ($Confirm -eq $false)}
        Should -Invoke New-Partition -Times 1 -Exactly -ParameterFilter {$UseMaximumSize -and $IsActive -and $AssignDriveLetter}
        Should -Invoke Format-Volume -Times 1 -Exactly -ParameterFilter {($FileSystem -eq 'FAT32') -and ($NewFileSystemLabel -eq 'OSDBuilder')}
        Should -Invoke Set-Location -Times 1 -Exactly -ParameterFilter {$Path -eq "$($Media.FullName)\OS\boot"}
        Should -Invoke bootsect.exe -Times 1 -Exactly -ParameterFilter {((@($InputObject) + @($RemainingArguments)) -join ' ') -eq '/nt60 U:'}
        Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter {($Path -eq "$($Media.FullName)\OS\*") -and ($Destination -eq 'U:') -and $Recurse}
    }

    It 'uses -USBLabel as the volume label' {
        New-OSDBuilderUSB -FullName $Media.FullName -USBLabel 'CONTOSO' 6>$null 3>$null 4>$null
        Should -Invoke Format-Volume -Times 1 -Exactly -ParameterFilter {$NewFileSystemLabel -eq 'CONTOSO'}
    }

    It 'rejects a -USBLabel longer than 11 characters' {
        {New-OSDBuilderUSB -FullName $Media.FullName -USBLabel 'ABCDEFGHIJKL'} | Should -Throw
    }

    It 'selects the media in Out-GridView without -FullName' {
        New-OSDBuilderUSB 6>$null 3>$null 4>$null
        Should -Invoke Out-GridView -Times 1 -Exactly -ParameterFilter {($InputObject.FullName -eq $Media.FullName) -and ($Title -like '*create an USB*')}
        Should -Invoke Set-Location -Times 1 -Exactly -ParameterFilter {$Path -eq "$($Media.FullName)\OS\boot"}
    }

    It 'warns and formats nothing when no USB drive is selected' {
        Mock Out-GridView {$InputObject | Where-Object {$_}} -ParameterFilter {$Title -like '*create an USB*'}
        Mock Out-GridView {} -ParameterFilter {$Title -like '*USB Drive to FORMAT*'}
        $Warnings = (New-OSDBuilderUSB -FullName $Media.FullName 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*No USB Drive was Found or Selected*'
        Should -Invoke Clear-Disk -Times 0 -Exactly
        Should -Invoke bootsect.exe -Times 0 -Exactly
        Should -Invoke Copy-Item -Times 0 -Exactly
    }

    It 'never offers a fixed disk or a USB drive larger than 32 GB' {
        Mock Get-Disk {[PSCustomObject]@{Number = 0; Size = 1TB; BusType = 'SATA'}}
        New-OSDBuilderUSB -FullName $Media.FullName 6>$null 3>$null
        Should -Invoke Out-GridView -Times 0 -Exactly -ParameterFilter {$Title -like '*USB Drive to FORMAT*'}
        Should -Invoke Clear-Disk -Times 0 -Exactly
    }
}

Describe 'New-OSDBuilderVHD' {
    BeforeEach {
        $env:Temp = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -Path $env:Temp -ItemType Directory -Force | Out-Null
        $Media = New-TestMedia -Name 'Win10'
        $VhdFolder = Join-Path $Media.FullName 'VHD'
        New-Item -Path $VhdFolder -ItemType Directory -Force | Out-Null
        Mock Get-OSDBuilder {}
        Mock Block-StandardUser {}
        Mock Get-Module {[PSCustomObject]@{Name = 'Hyper-V'}} -ParameterFilter {$Name -eq 'Hyper-V'}
        Mock Get-OSMedia {$Media}
        Mock Get-OSBuilds {}
        Mock Out-GridView {$InputObject | Where-Object {$_}}
        Mock New-VHD {}
        Mock Mount-DiskImage {}
        Mock Dismount-DiskImage {}
        Mock Get-DiskImage {[PSCustomObject]@{ImagePath = $ImagePath}}
        #Get-Disk takes the DiskImage CimInstance on Windows
        Mock Get-Disk {[PSCustomObject]@{Number = 7}} -RemoveParameterType InputObject, DiskImage
        Mock Initialize-Disk {}
        Mock New-Partition {
            if ($GptType -eq '{e3c9e316-0b5c-4db8-817d-f92df00215ae}') {[PSCustomObject]@{PartitionNumber = 2}}
            elseif ($GptType -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}') {[PSCustomObject]@{PartitionNumber = 4}}
            elseif ($Size -eq 200MB) {[PSCustomObject]@{PartitionNumber = 1}}
            else {[PSCustomObject]@{PartitionNumber = 3}}
        }
        Mock Format-Volume {} -RemoveParameterType InputObject
        Mock Add-PartitionAccessPath {}
        Mock Get-Partition {
            $Letter = @{1 = 'S'; 3 = 'W'}
            [PSCustomObject]@{PartitionNumber = $PartitionNumber; DriveLetter = $Letter[[int]$PartitionNumber]}
        }
        Mock Get-PartitionSupportedSize {[PSCustomObject]@{SizeMin = 1GB; SizeMax = 49GB}}
        Mock Resize-Partition {}
        Mock Expand-WindowsImage {}
        Mock cmd {}
    }

    It 'creates a GPT VHDX with System, MSR and OS partition, applies the install.wim and makes it bootable' {
        New-OSDBuilderVHD -FullName $Media.FullName 6>$null

        $VhdFile = "$($Media.FullName)\VHD\OSDBuilder.vhdx"
        Should -Invoke Block-StandardUser -Times 1 -Exactly
        Should -Invoke New-VHD -Times 1 -Exactly -ParameterFilter {($Path -eq $VhdFile) -and $Dynamic -and ($SizeBytes -eq 50GB)}
        Should -Invoke Mount-DiskImage -Times 1 -Exactly -ParameterFilter {$ImagePath -eq $VhdFile}
        Should -Invoke Initialize-Disk -Times 1 -Exactly -ParameterFilter {($Number -eq '7') -and ($PartitionStyle -eq 'GPT')}
        Should -Invoke New-Partition -Times 1 -Exactly -ParameterFilter {($DiskNumber -eq '7') -and ($GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}') -and ($Size -eq 200MB)}
        Should -Invoke New-Partition -Times 1 -Exactly -ParameterFilter {($GptType -eq '{e3c9e316-0b5c-4db8-817d-f92df00215ae}') -and ($Size -eq 128MB)}
        Should -Invoke New-Partition -Times 1 -Exactly -ParameterFilter {($GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}') -and $UseMaximumSize}
        Should -Invoke New-Partition -Times 3 -Exactly
        Should -Invoke Format-Volume -Times 1 -Exactly -ParameterFilter {($FileSystem -eq 'FAT32') -and ($NewFileSystemLabel -eq 'System')}
        Should -Invoke Format-Volume -Times 1 -Exactly -ParameterFilter {($FileSystem -eq 'NTFS') -and ($NewFileSystemLabel -eq 'OSDisk')}
        Should -Invoke Resize-Partition -Times 1 -Exactly -ParameterFilter {($PartitionNumber -eq 3) -and ($Size -eq (49GB - 984MB))}
        Should -Invoke Add-PartitionAccessPath -Times 2 -Exactly -ParameterFilter {$AssignDriveLetter}
        Should -Invoke Expand-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq "$($Media.FullName)\OS\Sources\Install.wim") -and ($Index -eq 1) -and ($ApplyPath -eq 'W:\')}
        Should -Invoke cmd -Times 1 -Exactly -ParameterFilter {((@($InputObject) + @($RemainingArguments)) -join ' ') -eq '/c W:\Windows\system32\bcdboot W:\Windows /s S: /f ALL'}
        Should -Invoke cmd -Times 1 -Exactly -ParameterFilter {((@($InputObject) + @($RemainingArguments)) -join ' ') -eq "/c diskpart.exe /s $env:Temp\OSDBuilderVHD.txt"}
        Get-Content -Path (Join-Path $env:Temp 'OSDBuilderVHD.txt') | Should -Be @(
            'Select Disk 7', 'Select Partition 1', 'Set ID=c12a7328-f81f-11d2-ba4b-00a0c93ec93b OVERRIDE', 'GPT Attributes=0x8000000000000000'
        )
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly -ParameterFilter {$ImagePath -eq $VhdFile}
    }

    It 'creates a Recovery partition with -IncludeRecoveryPartition and uses -OSDriveLabel and -VHDSizeGB' {
        New-OSDBuilderVHD -FullName $Media.FullName -IncludeRecoveryPartition -OSDriveLabel 'Windows' -VHDSizeGB 80 6>$null
        Should -Invoke New-VHD -Times 1 -Exactly -ParameterFilter {$SizeBytes -eq 80GB}
        Should -Invoke New-Partition -Times 1 -Exactly -ParameterFilter {($GptType -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}') -and $UseMaximumSize}
        Should -Invoke Format-Volume -Times 1 -Exactly -ParameterFilter {($FileSystem -eq 'NTFS') -and ($NewFileSystemLabel -eq 'Recovery')}
        Should -Invoke Format-Volume -Times 1 -Exactly -ParameterFilter {($FileSystem -eq 'NTFS') -and ($NewFileSystemLabel -eq 'Windows')}
    }

    It 'creates an active MBR VHD for a Windows version older than 10' {
        $Media = New-TestMedia -Name 'Win81' -Property @{MajorVersion = 6; Version = '6.3.9600.1'}
        Mock New-Partition {[PSCustomObject]@{PartitionNumber = 1}}
        Mock Get-Partition {[PSCustomObject]@{PartitionNumber = 1; DriveLetter = 'V'}}
        New-OSDBuilderVHD -FullName $Media.FullName 6>$null

        $VhdFile = "$($Media.FullName)\VHD\OSDBuilder.vhd"
        Should -Invoke New-VHD -Times 1 -Exactly -ParameterFilter {$Path -eq $VhdFile}
        Should -Invoke Initialize-Disk -Times 1 -Exactly -ParameterFilter {$PartitionStyle -eq 'MBR'}
        Should -Invoke New-Partition -Times 1 -Exactly -ParameterFilter {($DiskNumber -eq '7') -and $UseMaximumSize -and $IsActive}
        Should -Invoke Format-Volume -Times 1 -Exactly -ParameterFilter {($FileSystem -eq 'NTFS') -and ($NewFileSystemLabel -eq 'OSDisk')}
        Should -Invoke Add-PartitionAccessPath -Times 1 -Exactly -ParameterFilter {($DiskNumber -eq '7') -and ($PartitionNumber -eq 1) -and $AssignDriveLetter}
        Should -Invoke Expand-WindowsImage -Times 1 -Exactly -ParameterFilter {$ApplyPath -eq 'V:\'}
        Should -Invoke cmd -Times 1 -Exactly -ParameterFilter {((@($InputObject) + @($RemainingArguments)) -join ' ') -eq '/c V:\Windows\system32\bcdboot V:\Windows /s V:'}
        Should -Invoke cmd -Times 1 -Exactly
        Should -Invoke Resize-Partition -Times 0 -Exactly
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly -ParameterFilter {$ImagePath -eq $VhdFile}
    }

    It 'continues with bcdboot when Expand-WindowsImage fails' {
        Mock Expand-WindowsImage {throw 'The image could not be applied'}
        {New-OSDBuilderVHD -FullName $Media.FullName 6>$null} | Should -Not -Throw
        Should -Invoke cmd -Times 2 -Exactly
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
    }

    It 'continues with bcdboot when Expand-WindowsImage of an MBR VHD fails' {
        $Media = New-TestMedia -Name 'Win7' -Property @{MajorVersion = 6; Version = '6.1.7601.1'}
        Mock Expand-WindowsImage {throw 'The image could not be applied'}
        {New-OSDBuilderVHD -FullName $Media.FullName 6>$null} | Should -Not -Throw
        Should -Invoke cmd -Times 1 -Exactly
    }

    It 'warns and deletes an existing VHD' {
        $Existing = New-TestFile -Path (Join-Path $VhdFolder 'OSDBuilder.vhdx')
        $Warnings = (New-OSDBuilderVHD -FullName $Media.FullName 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*OSDBuilder.vhdx exists and will be deleted*'
        $Existing.FullName | Should -Not -Exist
        Should -Invoke New-VHD -Times 1 -Exactly
    }

    It 'selects the media in Out-GridView without -FullName' {
        New-OSDBuilderVHD 6>$null
        Should -Invoke Out-GridView -ParameterFilter {($InputObject.FullName -eq $Media.FullName) -and ($OutputMode -eq 'Single') -and ($Title -like '*create an VHD*')}
        Should -Invoke New-VHD -Times 1 -Exactly -ParameterFilter {$Path -eq "$($Media.FullName)\VHD\OSDBuilder.vhdx"}
    }

    It 'warns and creates no VHD when no media is selected' {
        Mock Out-GridView {}
        $Warnings = (New-OSDBuilderVHD 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*OSDBuilder Media was not selected or found*'
        Should -Invoke New-VHD -Times 0 -Exactly
    }

    It 'warns and stops without the Hyper-V module' {
        Mock Get-Module {} -ParameterFilter {$Name -eq 'Hyper-V'}
        #New-OSDBuilderVHD stops with Break, the loop contains it
        $Warnings = foreach ($Run in 1) {New-OSDBuilderVHD -FullName $Media.FullName 6>$null 3>&1}
        ($Warnings -join "`n") | Should -BeLike '*requires PowerShell Module HyperV*'
        Should -Invoke Get-OSMedia -Times 0 -Exactly
        Should -Invoke New-VHD -Times 0 -Exactly
    }
}

Describe 'Show-OSDBuilderInfo' {
    BeforeEach {
        Mock Get-OSDBuilder {}
        Mock Get-OSBuilds {}
        Mock Get-PEBuilds {}
        $Media = New-TestMedia -Name 'Win11' -Image @{Architecture = 9; ImageName = 'Windows 11 Enterprise'; EditionId = 'Enterprise'}
        $Xml = Join-Path (Join-Path $Media.FullName 'info') 'xml'
        @(
            [PSCustomObject]@{DisplayName = 'Microsoft.WindowsCalculator'; PackageName = 'Microsoft.WindowsCalculator_2021.2210.0.0_neutral_~_8wekyb3d8bbwe'}
            [PSCustomObject]@{DisplayName = 'Microsoft.LanguageExperiencePackde-DE'; PackageName = 'Microsoft.LanguageExperiencePackde-DE_26100.1.1.0_neutral__8wekyb3d8bbwe'}
        ) | Export-Clixml -Path (Join-Path $Xml 'Get-AppxProvisionedPackage.xml')
        @(
            [PSCustomObject]@{Name = 'Browser.InternetExplorer~~~~0.0.11.0'; State = 4}
            [PSCustomObject]@{Name = 'XPS.Viewer~~~~0.0.1.0'; State = 0}
            [PSCustomObject]@{Name = 'Language.Basic~~~de-DE~0.0.1.0'; State = 4}
            [PSCustomObject]@{Name = 'Language.Speech~~~fr-FR~0.0.1.0'; State = 0}
        ) | Export-Clixml -Path (Join-Path $Xml 'Get-WindowsCapability.xml')
        @(
            [PSCustomObject]@{FeatureName = 'NetFx4-AdvSrvs'; State = 2}
            [PSCustomObject]@{FeatureName = 'NetFx3'; State = 3}
            [PSCustomObject]@{FeatureName = 'TelnetClient'; State = 0}
            [PSCustomObject]@{FeatureName = 'SMB1Protocol'; State = 6}
        ) | Export-Clixml -Path (Join-Path $Xml 'Get-WindowsOptionalFeature.xml')
        @(
            [PSCustomObject]@{PackageName = 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.1.1.1'; PackageState = 6}
            [PSCustomObject]@{PackageName = 'Microsoft-Windows-Client-LanguagePack-Package~31bf3856ad364e35~amd64~de-DE~10.0.26100.1'; PackageState = 4}
            [PSCustomObject]@{PackageName = 'Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~10.0.26100.1'; PackageState = 4}
            [PSCustomObject]@{PackageName = 'Microsoft-OneCore-ApplicationModel-Sync-Desktop-FOD-Package~31bf3856ad364e35~amd64~~10.0.26100.1'; PackageState = 4}
            [PSCustomObject]@{PackageName = 'Microsoft-Windows-Foundation-Package~31bf3856ad364e35~amd64~~10.0.26100.1'; PackageState = 4}
            [PSCustomObject]@{PackageName = 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.2.1.1'; PackageState = 4}
        ) | Export-Clixml -Path (Join-Path $Xml 'Get-WindowsPackage.xml')
        Mock Get-OSMedia {$Media}
        Mock Out-GridView {$InputObject | Where-Object {$_}}
    }

    It 'shows the Appx packages, capabilities, optional features, packages and the Windows image of the media' {
        $Output = (Show-OSDBuilderInfo -FullName $Media.FullName 6>&1 | Out-String -Width 400) -split "`r?`n" | ForEach-Object {$_.TrimEnd()}
        $Text = $Output -join "`n"

        #Section headers are followed by their items
        foreach ($Pair in @(
            @('Get-AppxProvisionedPackage (DisplayName)', 'Microsoft.WindowsCalculator')
            @('Get-AppxProvisionedPackage Language Experience Packs (DisplayName)', 'Microsoft.LanguageExperiencePackde-DE')
            @('Get-WindowsCapability (State: Installed)', 'Browser.InternetExplorer~~~~0.0.11.0')
            @('Get-WindowsCapability (State: NotPresent)', 'XPS.Viewer~~~~0.0.1.0')
            @('Get-WindowsCapability Language (State: Installed)', 'Language.Basic~~~de-DE~0.0.1.0')
            @('Get-WindowsCapability Language (State: NotPresent)', 'Language.Speech~~~fr-FR~0.0.1.0')
            @('Get-WindowsOptionalFeature (State: Enabled)', 'NetFx4-AdvSrvs')
            @('Get-WindowsOptionalFeature (State: EnablePending)', 'NetFx3')
            @('Get-WindowsOptionalFeature (State: Disabled)', 'TelnetClient')
            @('Get-WindowsOptionalFeature (State: DisabledWithPayloadRemoved)', 'SMB1Protocol')
            @('Get-WindowsPackage (PackageState: Superseded)', 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.1.1.1')
            @('Get-WindowsPackage (PackageState: Installed) Language Packs', 'Microsoft-Windows-Client-LanguagePack-Package~31bf3856ad364e35~amd64~de-DE~10.0.26100.1')
            @('Get-WindowsPackage (PackageState: Installed) Language Features', 'Microsoft-Windows-LanguageFeatures-Basic-de-de-Package~31bf3856ad364e35~amd64~~10.0.26100.1')
            @('Get-WindowsPackage (PackageState: Installed) Features on Demand', 'Microsoft-OneCore-ApplicationModel-Sync-Desktop-FOD-Package~31bf3856ad364e35~amd64~~10.0.26100.1')
            @('Get-WindowsPackage (PackageState: Installed)', 'Microsoft-Windows-Foundation-Package~31bf3856ad364e35~amd64~~10.0.26100.1')
            @('Get-WindowsPackage (PackageState: Installed) Updates', 'Package_for_RollupFix~31bf3856ad364e35~amd64~~26100.2.1.1')
        )) {
            $Index = [array]::IndexOf($Output, $Pair[0])
            $Index | Should -BeGreaterThan -1 -Because "the section $($Pair[0]) is shown"
            $Output[$Index + 1] | Should -Be $Pair[1]
        }
        $Text | Should -Match 'Architecture\s*:\s*x64'
        $Text | Should -Match 'EditionId\s*:\s*Enterprise'
        $global:GetWindowsImage.Architecture | Should -Be 'x64'
        @($global:GetWindowsPackage).Count | Should -Be 6
        @($global:GetAppxProvisionedPackage).Count | Should -Be 2
    }

    It 'shows the architecture <Name> for <Architecture>' -ForEach @(
        @{Architecture = 0; Name = 'x86'}
        @{Architecture = 6; Name = 'ia64'}
        @{Architecture = 12; Name = 'x64 ARM'}
    ) {
        $Media = New-TestMedia -Name "Arch$Architecture" -Image @{Architecture = $Architecture}
        $Text = Show-OSDBuilderInfo -FullName $Media.FullName 6>$null | Out-String
        $Text | Should -Match "Architecture\s*:\s*$Name"
    }

    It 'shows only the Windows image of a media without inventory' {
        $Media = New-TestMedia -Name 'NoInventory'
        $Text = (Show-OSDBuilderInfo -FullName $Media.FullName 6>&1 | Out-String)
        $Text | Should -Not -BeLike '*Get-WindowsPackage*'
        $Text | Should -BeLike '*Get-WindowsImage*'
        @($global:GetWindowsPackage).Count | Should -Be 0
    }

    It 'selects the media in Out-GridView without -FullName' {
        $Text = Show-OSDBuilderInfo 6>&1 | Out-String
        Should -Invoke Out-GridView -Times 1 -Exactly -ParameterFilter {$PassThru}
        $Text | Should -BeLike "*Show-OSDBuilderInfo -FullName '$($Media.FullName)'*"
    }

    It 'warns when the media has no Get-WindowsImage.xml' {
        Remove-Item -Path (Join-Path $Xml 'Get-WindowsImage.xml')
        $Warnings = (Show-OSDBuilderInfo -FullName $Media.FullName 6>$null 3>&1) -join "`n"
        $Warnings | Should -BeLike '*Could not find an OSDBuilder Operating System at*'
    }

    It 'names the media path in the warning when the media has no Get-WindowsImage.xml' -Skip {
        # KnownBug: Show-OSDBuilderInfo.ps1:73 "$Media.FullName" expands the whole object followed by '.FullName' instead of the path
        Remove-Item -Path (Join-Path $Xml 'Get-WindowsImage.xml')
        $Warnings = (Show-OSDBuilderInfo -FullName $Media.FullName 6>$null 3>&1) -join "`n"
        $Warnings | Should -Be "Could not find an OSDBuilder Operating System at $($Media.FullName)"
    }
}
