BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    foreach ($Public in @('New-OSBuildMultiLang', 'Get-OSDBuilder', 'Get-OSBuilds')) {
        . (Join-Path (Join-Path $RepoRoot 'Public') "$Public.ps1")
    }

    function New-TestOSBuild {
        #Creates an OSBuild directory like New-OSBuild, returns the object of Get-OSBuilds
        param (
            [string]$Name = 'Windows 11 Enterprise x64 25H2 26200.6899 en-US de-DE fr-FR',
            [string]$ImageName = 'Windows 11 Enterprise',
            [string]$InstallationType = 'Client',
            $Architecture = 9,
            [string[]]$Languages = @('en-US', 'de-DE', 'fr-FR'),
            [int]$DefaultLanguageIndex = 1,
            $CurrentVersion = [PSCustomObject]@{CurrentBuild = '26200'; DisplayVersion = '25H2'; ReleaseId = '2009'; UBR = '6899'}
        )
        $FullName = Join-Path $SetOSDBuilderPathOSBuilds $Name
        $Xml = Join-Path (Join-Path $FullName 'info') 'xml'
        New-Item -Path $Xml -ItemType Directory -Force | Out-Null
        #New-OSBuildMultiLang uses OS\Sources, the same case is used here for file systems that are case sensitive
        New-TestFile -Path (Join-Path (Join-Path (Join-Path $FullName 'OS') 'Sources') 'install.wim') | Out-Null
        [PSCustomObject]@{
            ImageName               = $ImageName
            Architecture            = $Architecture
            InstallationType        = $InstallationType
            MajorVersion            = 10
            Build                   = 26200
            Version                 = '10.0.26200.6899'
            Languages               = $Languages
            DefaultLanguageIndex    = $DefaultLanguageIndex
        } | Export-Clixml -Path (Join-Path $Xml 'Get-WindowsImage.xml')
        if ($CurrentVersion) {$CurrentVersion | Export-Clixml -Path (Join-Path $Xml 'CurrentVersion.xml')}
        [PSCustomObject]@{
            Name        = $Name
            FullName    = $FullName
            ImageName   = $ImageName
            Languages   = $Languages
        }
    }

    function New-TestUpdate ([string]$KBNumber, [string]$UpdateOS = 'Windows 11', [string]$UpdateBuild = '25H2', [string]$UpdateArch = 'x64', [string]$UpdateGroup = 'LCU') {
        [PSCustomObject]@{KBNumber = $KBNumber; UpdateOS = $UpdateOS; UpdateBuild = $UpdateBuild; UpdateArch = $UpdateArch; UpdateGroup = $UpdateGroup}
    }

    function Invoke-NewOSBuildMultiLang ([string]$CustomName = 'Contoso') {
        #Runs New-OSBuildMultiLang without console output, returns the warnings as text
        $Output = New-OSBuildMultiLang -CustomName $CustomName 6>$null 3>&1
        ($Output | ForEach-Object {"$_"}) -join "`n"
    }
}

Describe 'New-OSBuildMultiLang' {
    BeforeEach {
        $SetOSDBuilderPathOSBuilds = Join-Path $TestDrive ([guid]::NewGuid().Guid.Substring(0, 8))
        New-Item -Path $SetOSDBuilderPathOSBuilds -ItemType Directory -Force | Out-Null
        $SavedTemp = $env:Temp
        $env:Temp = Join-Path $TestDrive 'Temp'
        New-Item -Path $env:Temp -ItemType Directory -Force | Out-Null
        $Destination = "$SetOSDBuilderPathOSBuilds\Contoso MultiLang"

        $script:OSBuilds = @(New-TestOSBuild)
        $script:Updates = @(
            New-TestUpdate -KBNumber '5066835'
            New-TestUpdate -KBNumber '5065381' -UpdateGroup 'SSU'
            New-TestUpdate -KBNumber '5066793' -UpdateBuild '24H2'
            New-TestUpdate -KBNumber '5066791' -UpdateOS 'Windows 10' -UpdateBuild '22H2'
            New-TestUpdate -KBNumber '5066837' -UpdateArch 'arm64'
            New-TestUpdate -KBNumber '5066999' -UpdateOS 'Windows Server' -UpdateBuild '24H2'
        )
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:Lcu = @()

        Mock Get-OSDBuilder {}
        Mock Get-OSDUpdates {$script:Updates}
        Mock Block-StandardUser {}
        Mock Get-OSBuilds {$script:OSBuilds}
        Mock Out-GridView {$InputObject}
        Mock Start-Sleep {}
        Mock robocopy {
            #robocopy /mir /xf install.wim: copies the OSBuild without the install.wim
            $Source = "$InputObject"
            $Target = $RemainingArguments[0]
            $SourceRoot = (Get-Item -Path $Source).FullName
            foreach ($File in (Get-ChildItem -Path $SourceRoot -Recurse -File | Where-Object {$_.Name -ne 'install.wim'})) {
                $Copy = Join-Path $Target $File.FullName.Substring($SourceRoot.Length + 1)
                New-Item -Path (Split-Path -Path $Copy -Parent) -ItemType Directory -Force | Out-Null
                Copy-Item -Path $File.FullName -Destination $Copy -Force
            }
        }
        Mock Export-WindowsImage {
            $script:Calls.Add("Export-WindowsImage $DestinationName")
            if ($DestinationImagePath -like "$env:Temp*") {New-TestFile -Path $DestinationImagePath | Out-Null}
        }
        Mock Mount-WindowsImage {$script:Calls.Add('Mount-WindowsImage')}
        Mock dism {$script:Calls.Add("Dism $InputObject $($RemainingArguments -join ' ')")}
        Mock Update-CumulativeOS {
            $script:Calls.Add('Update-CumulativeOS')
            $script:Lcu = @($OSDUpdateLCU)
            $script:LcuMountDirectory = $MountDirectory
            $script:LcuOS = $UpdateOS
        }
        Mock Save-WindowsImage {$script:Calls.Add('Save-WindowsImage')}
        Mock Dismount-WindowsImage {$script:Calls.Add('Dismount-WindowsImage')}
        Mock Show-ActionTime {}
    }

    AfterEach {
        $env:Temp = $SavedTemp
    }

    It 'offers only OSBuilds with more than one language that are not MultiLang' {
        $script:OSBuilds = @(
            New-TestOSBuild
            New-TestOSBuild -Name 'Windows 11 Enterprise x64 25H2 26200.6899' -Languages @('en-US')
            New-TestOSBuild -Name 'Contoso MultiLang' -Languages @('en-US', 'de-DE')
        )
        Mock Out-GridView {}
        Invoke-NewOSBuildMultiLang | Out-Null
        Should -Invoke Get-OSDBuilder -Times 1 -Exactly -ParameterFilter {$CreatePaths -and $HideDetails}
        Should -Invoke Block-StandardUser -Times 1 -Exactly
        Should -Invoke Out-GridView -Times 1 -Exactly -ParameterFilter {
            ($InputObject.Name -eq 'Windows 11 Enterprise x64 25H2 26200.6899 en-US de-DE fr-FR') -and $PassThru -and ($Title -like 'OSDBuilder: Select one or more OSBuilds to split*')
        }
    }

    It 'warns about the duration and does nothing when no OSBuild is selected' {
        Mock Out-GridView {}
        $Warnings = Invoke-NewOSBuildMultiLang
        $Warnings | Should -BeLike '*OSBuild MultiLang will take an OSBuild with Language Packs*'
        $Warnings | Should -BeLike '*the LCU will be reapplied*'
        Should -Invoke robocopy -Times 0 -Exactly
        Should -Invoke Export-WindowsImage -Times 0 -Exactly
    }

    It 'copies the OSBuild to <CustomName> MultiLang without the install.wim, ISO and VHD files' {
        Invoke-NewOSBuildMultiLang | Out-Null
        Should -Invoke robocopy -Times 1 -Exactly -ParameterFilter {
            ("$InputObject" -eq $script:OSBuilds[0].FullName) -and ($RemainingArguments[0] -eq $Destination) -and
            ($RemainingArguments -contains '/mir') -and ($RemainingArguments -contains 'install.wim') -and ($RemainingArguments -contains '*.iso') -and ($RemainingArguments -contains '*.vhdx')
        }
        Join-Path (Join-Path (Join-Path $Destination 'info') 'xml') 'Get-WindowsImage.xml' | Should -Exist
    }

    It 'exports the default language as index 1 and every other language as a new index with the LCU reapplied' {
        Invoke-NewOSBuildMultiLang | Out-Null
        $script:Calls[0] | Should -Be 'Export-WindowsImage Windows 11 Enterprise de-DE'
        $script:Calls[1] | Should -Be 'Export-WindowsImage Windows 11 Enterprise'
        $script:Calls[2] | Should -Be 'Mount-WindowsImage'
        $script:Calls | Should -Contain 'Export-WindowsImage Windows 11 Enterprise en-US'
        $script:Calls | Should -Contain 'Export-WindowsImage Windows 11 Enterprise fr-FR'
        $script:Calls | Should -Not -Contain 'Export-WindowsImage Windows 11 Enterprise de-DE de-DE'
        @($script:Calls -like 'Dism*/Set-AllIntl:en-US') | Should -HaveCount 1
        @($script:Calls -like 'Dism*/Set-AllIntl:fr-FR') | Should -HaveCount 1
        @($script:Calls -like 'Dism*/Set-AllIntl:de-DE') | Should -HaveCount 0
        #Set-AllIntl, LCU, Save and Export for each language
        $Language = $script:Calls.IndexOf('Export-WindowsImage Windows 11 Enterprise en-US')
        $script:Calls[$Language - 4] | Should -BeLike 'Dism /Image:* /Set-AllIntl:en-US'
        $script:Calls[$Language - 3] | Should -BeLike 'Dism /Image:* /Get-Intl'
        $script:Calls[$Language - 2] | Should -Be 'Update-CumulativeOS'
        $script:Calls[$Language - 1] | Should -Be 'Save-WindowsImage'
        $script:Calls[$script:Calls.Count - 1] | Should -Be 'Dismount-WindowsImage'
        Should -Invoke Update-CumulativeOS -Times 2 -Exactly -ParameterFilter {$Force}
        Should -Invoke Export-WindowsImage -Times 1 -Exactly -ParameterFilter {
            ($SourceImagePath -eq "$($script:OSBuilds[0].FullName)\OS\Sources\install.wim") -and ($SourceIndex -eq 1) -and ($DestinationImagePath -eq "$Destination\OS\Sources\install.wim")
        }
        Should -Invoke Export-WindowsImage -Times 2 -Exactly -ParameterFilter {($SourceImagePath -like "$env:Temp*install????.wim") -and ($DestinationImagePath -eq "$Destination\OS\Sources\install.wim")}
        Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ParameterFilter {($Path -eq $script:LcuMountDirectory) -and ($ImagePath -like "$env:Temp*install????.wim") -and ($Index -eq 1)}
        Should -Invoke Save-WindowsImage -Times 2 -Exactly -ParameterFilter {$Path -eq $script:LcuMountDirectory}
    }

    It 'reapplies the LCU of the OS, ReleaseId and Architecture of the OSBuild' {
        Invoke-NewOSBuildMultiLang | Out-Null
        $script:LcuOS | Should -Be 'Windows 11'
        $script:Lcu.KBNumber | Should -Be '5066835'
    }

    It 'selects the LCU of <UpdateOS> <Architecture>' -TestCases @(
        @{ImageName = 'Windows 10 Enterprise'; InstallationType = 'Client'; Architecture = 9; CurrentVersion = [PSCustomObject]@{CurrentBuild = '19045'; DisplayVersion = '22H2'}; UpdateOS = 'Windows 10'; KBNumber = '5066791'}
        @{ImageName = 'Windows Server 2025 SERVERDATACENTER'; InstallationType = 'Server'; Architecture = 9; CurrentVersion = [PSCustomObject]@{CurrentBuild = '26100'; ReleaseId = '24H2'}; UpdateOS = 'Windows Server'; KBNumber = '5066999'}
        @{ImageName = 'Windows 11 Enterprise'; InstallationType = 'Client'; Architecture = 12; CurrentVersion = [PSCustomObject]@{CurrentBuild = '26200'; DisplayVersion = '25H2'}; UpdateOS = 'Windows 11'; KBNumber = $null}
    ) {
        $script:OSBuilds = @(New-TestOSBuild -ImageName $ImageName -InstallationType $InstallationType -Architecture $Architecture -CurrentVersion $CurrentVersion)
        $script:Updates += New-TestUpdate -KBNumber '5066838' -UpdateArch 'x64 ARM' -UpdateOS 'Windows 10'
        Invoke-NewOSBuildMultiLang | Out-Null
        $script:LcuOS | Should -Be $UpdateOS
        if ($KBNumber) {$script:Lcu.KBNumber | Should -Be $KBNumber} else {$script:Lcu | Should -BeNullOrEmpty}
    }

    It 'maps the Architecture <Architecture> to <OSArchitecture> for the LCU' -TestCases @(
        @{Architecture = 0; OSArchitecture = 'x86'}
        @{Architecture = 6; OSArchitecture = 'ia64'}
        @{Architecture = 12; OSArchitecture = 'x64 ARM'}
    ) {
        $script:OSBuilds = @(New-TestOSBuild -Architecture $Architecture)
        $script:Updates = @(New-TestUpdate -KBNumber '1' -UpdateArch $OSArchitecture; New-TestUpdate -KBNumber '2')
        Invoke-NewOSBuildMultiLang | Out-Null
        $script:Lcu.KBNumber | Should -Be '1'
    }

    It 'uses the ReleaseId of CurrentVersion.xml when there is no DisplayVersion and no LCU without CurrentVersion.xml' {
        $script:OSBuilds = @(New-TestOSBuild -CurrentVersion ([PSCustomObject]@{CurrentBuild = '26200'; ReleaseId = '24H2'}))
        Invoke-NewOSBuildMultiLang | Out-Null
        $script:Lcu.KBNumber | Should -Be '5066793'

        $script:OSBuilds = @(New-TestOSBuild -Name 'No CurrentVersion' -CurrentVersion $null)
        $script:Updates += New-TestUpdate -KBNumber '5066000' -UpdateBuild ''
        $ReleaseId = $null
        Invoke-NewOSBuildMultiLang -CustomName 'NoCurrentVersion' | Out-Null
        #Only the updates without UpdateBuild match
        $script:Lcu.KBNumber | Should -Be '5066000'
    }

    It 'warns and replaces the install.wim of an existing MultiLang OSBuild' {
        $Existing = New-TestFile -Path (Join-Path (Join-Path (Join-Path $Destination 'OS') 'Sources') 'install.wim') -Value 'old'
        $Warnings = Invoke-NewOSBuildMultiLang
        $Warnings | Should -BeLike "*Existing contents will be replaced in $Destination*"
        $Existing.FullName | Should -Not -Exist
    }

    It 'removes the temporary install.wim and the mount directory' {
        Invoke-NewOSBuildMultiLang | Out-Null
        Get-ChildItem -Path $env:Temp | Should -BeNullOrEmpty
        Should -Invoke Dismount-WindowsImage -Times 1 -Exactly -ParameterFilter {$Discard -and ($Path -eq $script:LcuMountDirectory)}
    }

    It 'waits and dismounts again when the first dismount fails' {
        $script:DismountCall = 0
        Mock Dismount-WindowsImage {
            $script:DismountCall++
            if ($script:DismountCall -eq 1) {throw 'The mounted image is in use'}
        }
        $Warnings = Invoke-NewOSBuildMultiLang
        $Warnings | Should -BeLike '*Could not dismount * ... Waiting 30 seconds ...*'
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {$Seconds -eq 30}
        Should -Invoke Dismount-WindowsImage -Times 2 -Exactly -ParameterFilter {$Discard}
    }

    It 'requires -CustomName' {
        $Parameter = (Get-Command New-OSBuildMultiLang).Parameters['CustomName']
        ($Parameter.Attributes | Where-Object {$_ -is [System.Management.Automation.ParameterAttribute]}).Mandatory | Should -BeTrue
        {New-OSBuildMultiLang -CustomName '' 6>$null 3>$null} | Should -Throw
    }
}
