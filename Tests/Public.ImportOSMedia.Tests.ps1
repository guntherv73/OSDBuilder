<#
Import-OSMedia finds install.wim and install.esd on the mounted Windows ISOs (or in -Path and the FeatureUpdates directory),
filters the Windows Images and imports each selected image into OSImport\<OSMediaName>.
DISM, robocopy and the Private worker functions are mocked, the ISO is a fixture directory in $TestDrive.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    foreach ($PublicName in 'Import-OSMedia', 'Get-OSDBuilder', 'Update-OSMedia', 'New-OSBuild', 'Show-OSDBuilderInfo') {
        . (Join-Path (Join-Path $RepoRoot 'Public') "$PublicName.ps1")
    }

    $UpdateOSMediaFixtures = Join-Path $FixturesPath 'UpdateOSMedia'
    $script:FixtureImages = Get-Content -Path (Join-Path $UpdateOSMediaFixtures 'WindowsImages.json') -Raw | ConvertFrom-Json
    $script:FixtureRegistry = Get-Content -Path (Join-Path $UpdateOSMediaFixtures 'CurrentVersion.json') -Raw | ConvertFrom-Json

    $script:SavedGlobals = @{}
    foreach ($VariableName in 'SetOSDBuilder', 'SetOSDBuilderPathOSImport', 'SetOSDBuilderPathMount', 'SetOSDBuilderPathFeatureUpdates') {
        $script:SavedGlobals[$VariableName] = Get-Variable -Name $VariableName -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    }
    $script:SavedTemp = $env:Temp

    function New-TestWindowsImage {
        <#
        .SYNOPSIS
        Get-WindowsImage -Index result from Fixtures\UpdateOSMedia\WindowsImages.json
        #>
        param ([string]$Key, [string]$ImagePath, [hashtable]$Property = @{})
        $Image = $script:FixtureImages.$Key | Select-Object -Property *
        $Image | Add-Member -MemberType NoteProperty -Name ImagePath -Value $ImagePath -Force
        foreach ($Item in $Property.GetEnumerator()) {$Image | Add-Member -MemberType NoteProperty -Name $Item.Key -Value $Item.Value -Force}
        $Image
    }

    function New-TestIsoMedia {
        <#
        .SYNOPSIS
        Creates the files of a Windows ISO (setup.exe, Sources\boot.wim, Sources\install.wim or install.esd)
        and registers the Windows Images of install.wim for the Get-WindowsImage mock
        The directory is Sources (not sources) because Import-OSMedia tests "<Root>Sources" and Linux is case sensitive
        #>
        param (
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string[]]$Image,
            [hashtable]$ImageProperty = @{},
            [string]$FileName = 'install.wim'
        )
        $Sources = Join-Path $Path 'Sources'
        New-TestFile -Path (Join-Path $Path 'setup.exe') | Out-Null
        New-TestFile -Path (Join-Path $Sources 'boot.wim') | Out-Null
        $InstallWim = (New-TestFile -Path (Join-Path $Sources $FileName) -Value 'MSWIM').FullName
        $Indexes = @{}
        foreach ($Key in $Image) {
            $WindowsImage = New-TestWindowsImage -Key $Key -ImagePath $InstallWim -Property $ImageProperty
            $Indexes["$($WindowsImage.ImageIndex)"] = $WindowsImage
        }
        $script:ImageMap[$InstallWim] = $Indexes
        $InstallWim
    }

    function Invoke-ImportOSMedia {
        <#
        .SYNOPSIS
        Runs Import-OSMedia and returns the warnings
        Break in the Begin block of Import-OSMedia leaves the nearest loop, the foreach keeps it inside this function
        #>
        param ([hashtable]$Parameters = @{})
        #collected in a list, an assignment would be lost when Break leaves the pipeline
        $Warnings = New-Object System.Collections.Generic.List[string]
        foreach ($Guard in 1) {
            Import-OSMedia @Parameters 3>&1 6>$null | ForEach-Object {
                if ($_ -is [System.Management.Automation.WarningRecord]) {$Warnings.Add($_.Message)}
            }
        }
        ,$Warnings.ToArray()
    }

    function Get-ImportedOSMedia {
        @(Get-ChildItem -Path $global:SetOSDBuilderPathOSImport -Directory | Select-Object -ExpandProperty Name | Sort-Object)
    }
}

AfterAll {
    foreach ($Item in $script:SavedGlobals.GetEnumerator()) {
        Set-Variable -Name $Item.Key -Value $Item.Value -Scope Global
    }
    $env:Temp = $script:SavedTemp
}

Describe 'Import-OSMedia' {
    BeforeEach {
        $Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $global:SetOSDBuilder = $null
        $global:SetOSDBuilderPathOSImport = Join-Path $Root 'OSImport'
        $global:SetOSDBuilderPathMount = Join-Path $Root 'Mount'
        $global:SetOSDBuilderPathFeatureUpdates = Join-Path $Root 'FeatureUpdates'
        foreach ($Directory in $global:SetOSDBuilderPathOSImport, $global:SetOSDBuilderPathMount, $global:SetOSDBuilderPathFeatureUpdates) {
            New-Item -Path $Directory -ItemType Directory -Force | Out-Null
        }
        $env:Temp = Join-Path $Root 'Temp'
        New-Item -Path $env:Temp -ItemType Directory -Force | Out-Null

        $script:ImageMap = @{}
        $script:Registry = $script:FixtureRegistry.'Win11-24H2-1742' | Select-Object -Property *
        $script:Drives = @()
        $script:Seen = @{}

        Mock Get-OSDBuilder {}
        Mock Block-StandardUser {}
        Mock Pause {}
        Mock Get-PSDrive {$script:Drives}
        Mock Out-GridView {$InputObject}
        Mock Get-WindowsImage {
            $Indexes = $script:ImageMap[$ImagePath]
            if (-not $Indexes) {return}
            if ($Index) {
                $Indexes["$Index"] | Select-Object -Property *
            } else {
                $Indexes.Values | Sort-Object -Property {[int]$_.ImageIndex} | Select-Object -Property ImagePath, ImageIndex, ImageName
            }
        }
        #The exported image is the source image, registered for Get-WindowsImage -ImagePath <DestinationImagePath> -Index 1
        Mock Export-WindowsImage {
            $Source = $script:ImageMap[$SourceImagePath]["$SourceIndex"] | Select-Object -Property *
            $Source.ImagePath = $DestinationImagePath
            $Source.ImageIndex = 1
            $Exported = @{'1' = $Source}
            $script:ImageMap[$DestinationImagePath] = $Exported
            if ($DestinationImagePath -like "$($env:Temp)*") {New-TestFile -Path $DestinationImagePath | Out-Null}
        }
        Mock Mount-ImportOSMediaWim {
            $script:Seen['Mount'] = @($script:Seen['Mount']) + @("$SourceImageIndex|$MountDirectory") | Where-Object {$_}
        }
        Mock Get-RegCurrentVersion {$script:Registry}
        Mock Dismount-WindowsImage {}
        Mock robocopy {}
        Mock Start-Transcript {}
        Mock Stop-Transcript {}
        foreach ($Worker in 'Show-OSMediaInfo', 'Save-AutoExtraFilesOS', 'Save-SessionsXmlOS', 'Save-InventoryOS', 'Save-WimsPE', 'Save-InventoryPE',
            'Save-OSMediaWindowsImageContent', 'Save-OSMediaVariables', 'Show-OSDBuilderInfo', 'Update-OSMedia', 'New-OSBuild') {
            Mock -CommandName $Worker -MockWith {}
        }

        $Win11Name = 'Windows 11 Enterprise x64 24H2 26100.1742'
        $DvdRoot = Join-Path $Root 'DVD'
    }

    Context 'finding the Windows Images' {
        It 'scans Sources, x64\Sources and x86\Sources of every drive and the FeatureUpdates' {
            $DvdWim = New-TestIsoMedia -Path $DvdRoot -Image 'Win11Enterprise24H2'
            $DualRoot = Join-Path $Root 'DualArch'
            $X64Wim = New-TestIsoMedia -Path (Join-Path $DualRoot 'x64') -Image 'Win10Enterprise22H2'
            $X86Wim = New-TestIsoMedia -Path (Join-Path $DualRoot 'x86') -Image 'Win10Enterprise22H2' -ImageProperty @{Architecture = 0}
            $FeatureUpdateEsd = New-TestIsoMedia -Path (Join-Path $global:SetOSDBuilderPathFeatureUpdates 'Windows 11 24H2 x64 en-US') -Image 'Win11Pro24H2' -FileName 'install.esd'
            New-Item -Path (Join-Path $Root 'Data') -ItemType Directory | Out-Null
            $script:Drives = @(
                [PSCustomObject]@{Name = 'C'; Root = (Join-Path $Root 'Data') + [System.IO.Path]::DirectorySeparatorChar}
                [PSCustomObject]@{Name = 'D'; Root = $DvdRoot + [System.IO.Path]::DirectorySeparatorChar}
                [PSCustomObject]@{Name = 'E'; Root = $DualRoot + [System.IO.Path]::DirectorySeparatorChar}
            )
            Mock Out-GridView {$script:Seen['Grid'] = @($script:Seen['Grid']) + @("$($InputObject.ImageName) $($InputObject.Architecture)") | Where-Object {$_}}
            Invoke-ImportOSMedia | Out-Null
            Should -Invoke Get-PSDrive -Times 1 -Exactly -ParameterFilter {$PSProvider -eq 'FileSystem'}
            foreach ($InstallWim in $DvdWim, $X64Wim, $X86Wim, $FeatureUpdateEsd) {
                Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq $InstallWim) -and (-not $Index)}
            }
            $script:Seen['Grid'] | Sort-Object | Should -Be @('Windows 10 Enterprise x64', 'Windows 10 Enterprise x86', 'Windows 11 Enterprise x64', 'Windows 11 Pro x64')
        }

        It 'does not scan the FeatureUpdates with -SkipFeatureUpdates' {
            New-TestIsoMedia -Path $DvdRoot -Image 'Win11Enterprise24H2' | Out-Null
            $FeatureUpdateEsd = New-TestIsoMedia -Path (Join-Path $global:SetOSDBuilderPathFeatureUpdates 'Windows 11 24H2 x64 en-US') -Image 'Win11Pro24H2' -FileName 'install.esd'
            $script:Drives = @([PSCustomObject]@{Name = 'D'; Root = $DvdRoot + [System.IO.Path]::DirectorySeparatorChar})
            Invoke-ImportOSMedia -Parameters @{SkipFeatureUpdates = $true; SkipGrid = $true} | Out-Null
            Should -Invoke Get-WindowsImage -Times 0 -Exactly -ParameterFilter {$ImagePath -eq $FeatureUpdateEsd}
            Get-ImportedOSMedia | Should -Be @($Win11Name)
        }

        It 'finds the Windows Images in the subdirectories of -Path' {
            $PathRoot = Join-Path $Root 'Extracted'
            $NestedWim = New-TestIsoMedia -Path (Join-Path (Join-Path $PathRoot 'Win11') '24H2') -Image 'Win11Enterprise24H2'
            Invoke-ImportOSMedia -Parameters @{Path = $PathRoot; SkipGrid = $true} | Out-Null
            Should -Invoke Get-PSDrive -Times 0 -Exactly
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -eq $NestedWim) -and (-not $Index)}
            Get-ImportedOSMedia | Should -Be @($Win11Name)
        }

        It 'stops when -Path does not exist' {
            $Warnings = Invoke-ImportOSMedia -Parameters @{Path = (Join-Path $Root 'Missing')}
            ($Warnings -like "Test-Path: Could not find specified Path '*Missing'. Throw BREAK") | Should -HaveCount 1
            Should -Invoke Pause -Times 1 -Exactly
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
        }

        It 'warns and stops when no drive has a Windows Image' {
            $Warnings = Invoke-ImportOSMedia
            $Warnings | Should -Contain 'Windows Image could not be found on any CD or DVD Drives.  Throw BREAK'
            Should -Invoke Get-WindowsImage -Times 0 -Exactly
            Should -Invoke Mount-ImportOSMediaWim -Times 0 -Exactly
        }
    }

    Context 'selecting the Windows Images' {
        BeforeEach {
            $DvdWim = New-TestIsoMedia -Path $DvdRoot -Image 'Win11Education24H2', 'Win11Enterprise24H2', 'Win11Pro24H2', 'Win11ProWorkstations24H2'
            $script:Drives = @([PSCustomObject]@{Name = 'D'; Root = $DvdRoot + [System.IO.Path]::DirectorySeparatorChar})
        }

        It 'imports the Windows Images selected in Out-GridView' {
            Mock Out-GridView {
                $script:Seen['GridTitle'] = $Title
                $script:Seen['Grid'] = @($script:Seen['Grid']) + @($InputObject.ImageIndex) | Where-Object {$_}
                if ($InputObject.EditionId -eq 'Enterprise') {$InputObject}
            }
            Invoke-ImportOSMedia | Out-Null
            $script:Seen['GridTitle'] | Should -Be 'Import-OSMedia: Select OSMedia to Import and press OK (Cancel to Exit)'
            $script:Seen['Grid'] | Should -Be @(1, 3, 5, 9)
            Should -Invoke Mount-ImportOSMediaWim -Times 1 -Exactly
            Get-ImportedOSMedia | Should -Be @($Win11Name)
        }

        It 'does not show Windows 7 and older in Out-GridView' {
            $Win7Root = Join-Path $Root 'Win7'
            New-TestIsoMedia -Path $Win7Root -Image 'Win7Enterprise' | Out-Null
            $script:Drives = @([PSCustomObject]@{Name = 'F'; Root = $Win7Root + [System.IO.Path]::DirectorySeparatorChar})
            $Warnings = Invoke-ImportOSMedia
            $Warnings | Should -Contain 'Import-OSMedia: OSMedia was not found . . . Exiting!'
            Should -Invoke Out-GridView -Times 0 -Exactly
        }

        It 'stops when nothing is selected in Out-GridView' {
            Mock Out-GridView {}
            $Warnings = Invoke-ImportOSMedia
            $Warnings | Should -Contain 'Import-OSMedia: Compatible OSMedia was not selected . . . Exiting!'
            Should -Invoke Mount-ImportOSMediaWim -Times 0 -Exactly
        }

        It 'imports every Windows Image with -SkipGrid' {
            Invoke-ImportOSMedia -Parameters @{SkipGrid = $true} | Out-Null
            Should -Invoke Out-GridView -Times 0 -Exactly
            Get-ImportedOSMedia | Should -Be @(
                'Windows 11 Education x64 24H2 26100.1742', $Win11Name,
                'Windows 11 Pro for Workstations x64 24H2 26100.1742', 'Windows 11 Pro x64 24H2 26100.1742'
            )
        }

        It 'uses the SkipGrid default of Set-OSDBuilder' {
            $global:SetOSDBuilder = [PSCustomObject]@{ImportOSMediaSkipGrid = $true; ImportOSMediaEditionId = 'Education'}
            Invoke-ImportOSMedia | Out-Null
            Should -Invoke Out-GridView -Times 0 -Exactly
            Get-ImportedOSMedia | Should -Be @('Windows 11 Education x64 24H2 26100.1742')
        }

        It 'imports only the images of <Filter>' -ForEach @(
            @{Filter = '-EditionId Enterprise'; Parameters = @{EditionId = 'Enterprise'}; Index = 3}
            @{Filter = '-EditionId ProfessionalWorkstation, Education'; Parameters = @{EditionId = 'ProfessionalWorkstation', 'Education'}; Index = 1, 9}
            @{Filter = "-ImageName 'Windows 11 Pro'"; Parameters = @{ImageName = 'Windows 11 Pro'}; Index = 5}
            @{Filter = '-ImageIndex 9'; Parameters = @{ImageIndex = 9}; Index = 9}
            @{Filter = '-InstallationType Client -EditionId Professional'; Parameters = @{InstallationType = 'Client'; EditionId = 'Professional'}; Index = 5}
        ) {
            Invoke-ImportOSMedia -Parameters ($Parameters + @{SkipGrid = $true}) | Out-Null
            Should -Invoke Mount-ImportOSMediaWim -Times @($Index).Count -Exactly
            foreach ($ExpectedIndex in $Index) {
                Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {($SourceIndex -eq $ExpectedIndex) -and ($DestinationImagePath -like '*OS*sources*install.wim')}
            }
        }

        It 'stops when no image matches the filter' {
            $Warnings = Invoke-ImportOSMedia -Parameters @{InstallationType = 'Server Core'; SkipGrid = $true}
            $Warnings | Should -Contain 'Import-OSMedia: OSMedia was not found . . . Exiting!'
            Should -Invoke Mount-ImportOSMediaWim -Times 0 -Exactly
        }
    }

    Context 'importing a Windows Image' {
        BeforeEach {
            $script:Drives = @([PSCustomObject]@{Name = 'D'; Root = $DvdRoot + [System.IO.Path]::DirectorySeparatorChar})
        }

        It 'creates the OSMedia directories and exports the registry CurrentVersion and the Windows Image information' {
            New-TestIsoMedia -Path $DvdRoot -Image 'Win11Enterprise24H2' | Out-Null
            Invoke-ImportOSMedia -Parameters @{SkipGrid = $true} | Out-Null
            $OSMediaPath = Join-Path $global:SetOSDBuilderPathOSImport $Win11Name
            $Info = Join-Path $OSMediaPath 'info'
            foreach ($Directory in 'json', 'logs', 'xml') {Test-Path (Join-Path $Info $Directory) -PathType Container | Should -BeTrue}
            foreach ($Directory in 'json', 'logs', 'xml') {Test-Path (Join-Path (Join-Path (Join-Path $OSMediaPath 'WinPE') 'info') $Directory) -PathType Container | Should -BeTrue}
            Test-Path (Join-Path $OSMediaPath 'OS') -PathType Container | Should -BeTrue
            (Import-Clixml -Path (Join-Path (Join-Path $Info 'xml') 'CurrentVersion.xml')).UBR | Should -Be 1742
            (Get-Content -Path (Join-Path (Join-Path $Info 'json') 'CurrentVersion.json') -Raw | ConvertFrom-Json).DisplayVersion | Should -Be '24H2'
            Test-Path (Join-Path $OSMediaPath 'CurrentVersion.txt') | Should -BeTrue
            $WindowsImage = Import-Clixml -Path (Join-Path (Join-Path $Info 'xml') 'Get-WindowsImage.xml')
            $WindowsImage.UBR | Should -Be '26100.1742'
            $WindowsImage.ReleaseId | Should -Be '24H2'
            $WindowsImage.OSMGuid | Should -Not -BeNullOrEmpty
            (Get-Content -Path (Join-Path (Join-Path $Info 'json') 'Get-WindowsImage.json') -Raw | ConvertFrom-Json).CurrentBuild | Should -Be '26100'
            Get-Content -Path (Join-Path $OSMediaPath 'WindowsImage.txt') | Where-Object {-not $_.Trim()} | Should -BeNullOrEmpty
            (Get-Content -Path (Join-Path $OSMediaPath 'WindowsImage.txt')) -join ' ' | Should -BeLike '*Windows 11 Enterprise*'
            Should -Invoke Start-Transcript -Times 1 -Exactly -ParameterFilter {$Path -like '*info*logs*Import-OSMedia.log'}
            Should -Invoke Stop-Transcript -Times 1 -Exactly
        }

        It 'copies the media without install.wim and exports the image index to OS\sources\install.wim' {
            $DvdWim = New-TestIsoMedia -Path $DvdRoot -Image 'Win11Education24H2', 'Win11Enterprise24H2'
            Invoke-ImportOSMedia -Parameters @{EditionId = 'Enterprise'; SkipGrid = $true} | Out-Null
            $OSMediaPath = Join-Path $global:SetOSDBuilderPathOSImport $Win11Name
            Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {
                $Arguments = @($InputObject) + @($RemainingArguments)
                ($Arguments[0] -eq $DvdRoot) -and ($Arguments[1] -like '*OSImport*OS') -and (($Arguments -join ' ') -like '*/e /xf install.wim install.esd')
            }
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
                ($SourceImagePath -eq $DvdWim) -and ($SourceIndex -eq 3) -and ($DestinationImagePath -like "*$Win11Name*OS*sources*install.wim") -and ($LogPath -like '*Export-WindowsImage.log')
            }
            Should -Invoke Get-WindowsImage -Times 1 -Exactly -ParameterFilter {($ImagePath -like "*$Win11Name*install.wim") -and ($Index -eq 1)}
            foreach ($Worker in 'Save-AutoExtraFilesOS', 'Save-SessionsXmlOS', 'Save-InventoryOS', 'Save-WimsPE', 'Save-InventoryPE') {
                Should -Invoke -CommandName $Worker -Times 1 -Exactly -ParameterFilter {$OSMediaPath -like "*OSImport*$Win11Name"}
            }
            Should -Invoke Dismount-WindowsImage -Times 1 -Exactly -ParameterFilter {$Discard -and ($Path -match 'Mount.os\d{6}$')}
            Should -Invoke Save-OSMediaWindowsImageContent -Times 1 -Exactly
            Should -Invoke Save-OSMediaVariables -Times 1 -Exactly
            Should -Invoke Show-OSDBuilderInfo -Times 0 -Exactly
            Should -Invoke Update-OSMedia -Times 0 -Exactly
            Should -Invoke New-OSBuild -Times 0 -Exactly
        }

        It 'mounts the install.wim read only in the Mount directory' {
            $DvdWim = New-TestIsoMedia -Path $DvdRoot -Image 'Win11Enterprise24H2'
            Mock Mount-ImportOSMediaWim {$script:Seen['Mount'] = "$SourceImagePath|$SourceImageIndex|$MountDirectory"}
            Invoke-ImportOSMedia -Parameters @{SkipGrid = $true} | Out-Null
            $Parts = $script:Seen['Mount'] -split '\|'
            $Parts[0] | Should -Be $DvdWim
            $Parts[1] | Should -Be '3'
            $Parts[2] | Should -BeLike "$($global:SetOSDBuilderPathMount)*os*"
            Should -Invoke Get-RegCurrentVersion -Times 1 -Exactly -ParameterFilter {$Path -eq $Parts[2]}
        }

        It 'removes the parentheses from the name of <ImageName>' -ForEach @(
            @{ImageName = 'Windows Server 2022 Datacenter (Desktop Experience)'; Image = 'Server2022Datacenter'; Registry = 'Server2022-587'; Expected = 'Windows Server 2022 Datacenter Desktop Experience x64 21H2 20348.587'}
        ) {
            New-TestIsoMedia -Path $DvdRoot -Image $Image | Out-Null
            $script:Registry = $script:FixtureRegistry.$Registry
            Invoke-ImportOSMedia -Parameters @{SkipGrid = $true} | Out-Null
            Get-ImportedOSMedia | Should -Be @($Expected)
        }

        It 'keeps the languages in the name of a multi language image' {
            New-TestIsoMedia -Path $DvdRoot -Image 'Win11Enterprise24H2DeDE' | Out-Null
            Invoke-ImportOSMedia -Parameters @{SkipGrid = $true} | Out-Null
            Get-ImportedOSMedia | Should -Be @("$Win11Name en-US de-DE")
        }

        It 'uses the ReleaseId when the registry has no DisplayVersion (Windows 10 1809)' {
            New-TestIsoMedia -Path $DvdRoot -Image 'Win10Enterprise1809' | Out-Null
            $script:Registry = $script:FixtureRegistry.'Win10-1809-1'
            Invoke-ImportOSMedia -Parameters @{SkipGrid = $true} | Out-Null
            Get-ImportedOSMedia | Should -Be @('Windows 10 Enterprise x64 1809 17763.1')
        }

        It 'names the architecture <Architecture> as <Name>' -ForEach @(
            @{Architecture = 0; Name = 'x86'}
            @{Architecture = 6; Name = 'ia64'}
            @{Architecture = 9; Name = 'x64'}
            @{Architecture = 12; Name = 'x64 ARM'}
        ) {
            New-TestIsoMedia -Path $DvdRoot -Image 'Win11Enterprise24H2' -ImageProperty @{Architecture = $Architecture} | Out-Null
            Mock Out-GridView {$script:Seen['GridArchitecture'] = $InputObject.Architecture; $InputObject}
            Invoke-ImportOSMedia | Out-Null
            $script:Seen['GridArchitecture'] | Should -Be $Name
            Get-ImportedOSMedia | Should -Be @("Windows 11 Enterprise $Name 24H2 26100.1742")
        }

        It 'replaces an existing OSMedia' {
            New-TestIsoMedia -Path $DvdRoot -Image 'Win11Enterprise24H2' | Out-Null
            New-TestFile -Path (Join-Path (Join-Path $global:SetOSDBuilderPathOSImport $Win11Name) 'old.txt') | Out-Null
            $Warnings = Invoke-ImportOSMedia -Parameters @{SkipGrid = $true}
            ($Warnings -like '*exists.  Contents will be replaced!') | Should -HaveCount 1
            Test-Path (Join-Path (Join-Path $global:SetOSDBuilderPathOSImport $Win11Name) 'old.txt') | Should -BeFalse
        }

        It 'exports the index of an install.esd to a temporary install.wim first' {
            $DvdEsd = New-TestIsoMedia -Path $DvdRoot -Image 'Win11Education24H2', 'Win11Enterprise24H2' -FileName 'install.esd'
            Mock Mount-ImportOSMediaWim {$script:Seen['MountTemp'] = $SourceTempWim}
            Invoke-ImportOSMedia -Parameters @{EditionId = 'Enterprise'; SkipGrid = $true} | Out-Null
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
                ($SourceImagePath -eq $DvdEsd) -and ($SourceIndex -eq 3) -and ($DestinationImagePath -like "$($env:Temp)*.wim") -and $CheckIntegrity -and ($CompressionType -eq 'max')
            }
            Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
                ($SourceImagePath -eq $script:Seen['MountTemp']) -and ($SourceIndex -eq 1) -and ($DestinationImagePath -like "*$Win11Name*OS*sources*install.wim")
            }
            Test-Path $script:Seen['MountTemp'] | Should -BeFalse
            Get-ImportedOSMedia | Should -Be @($Win11Name)
        }

        It 'warns when the temporary install.wim cannot be removed' {
            New-TestIsoMedia -Path $DvdRoot -Image 'Win11Enterprise24H2' -FileName 'install.esd' | Out-Null
            Mock Remove-Item {throw 'The process cannot access the file because it is being used by another process'} -ParameterFilter {$Path -like "$($env:Temp)*.wim"}
            $Warnings = Invoke-ImportOSMedia -Parameters @{SkipGrid = $true}
            ($Warnings -like 'Could not remove *.wim') | Should -HaveCount 1
        }

        It 'shows the OSMedia information with -ShowInfo' {
            New-TestIsoMedia -Path $DvdRoot -Image 'Win11Enterprise24H2' | Out-Null
            Invoke-ImportOSMedia -Parameters @{SkipGrid = $true; ShowInfo = $true} | Out-Null
            Should -Invoke Show-OSDBuilderInfo -Times 1 -Exactly -ParameterFilter {$FullName -like "*OSImport*$Win11Name"}
        }

        It 'updates the imported OSMedia with -Update' {
            New-TestIsoMedia -Path $DvdRoot -Image 'Win11Enterprise24H2' | Out-Null
            Invoke-ImportOSMedia -Parameters @{SkipGrid = $true; Update = $true} | Out-Null
            Should -Invoke Update-OSMedia -Times 1 -Exactly -ParameterFilter {($Name -eq $Win11Name) -and $Download -and $Execute -and $HideCleanupProgress}
            Should -Invoke New-OSBuild -Times 0 -Exactly
        }

        It 'builds the imported OSMedia with NetFX 3.5 with -BuildNetFX' {
            New-TestIsoMedia -Path $DvdRoot -Image 'Win11Enterprise24H2' | Out-Null
            Invoke-ImportOSMedia -Parameters @{SkipGrid = $true; BuildNetFX = $true} | Out-Null
            Should -Invoke New-OSBuild -Times 1 -Exactly -ParameterFilter {($Name -eq $Win11Name) -and $Download -and $Execute -and $HideCleanupProgress -and $SkipTask -and $EnableNetFX}
            Should -Invoke Update-OSMedia -Times 0 -Exactly
        }
    }
}
