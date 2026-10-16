BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    foreach ($Script in (Get-OSDBuilderPrivateScript)) {. $Script}
    foreach ($Name in 'Initialize-OSDBuilder', 'Get-OSDBuilder', 'Get-OSMedia', 'Update-OSMedia', 'Save-OSDBuilderDownload', 'New-OSDBuilderContentPack') {
        . (Join-Path (Join-Path $RepoRoot 'Public') "$Name.ps1")
    }

    #Initialize-OSDBuilder and Get-OSDBuilder set these global variables, they are restored in AfterAll
    $script:GlobalVariableNames = @('GetOSDBuilder*', 'SetOSDBuilder*')
    $script:SavedGlobalVariables = @(Get-Variable -Scope Global -Name $script:GlobalVariableNames -ErrorAction SilentlyContinue)
    $script:SavedProgramData = $env:ProgramData
    $script:SavedSystemDrive = $env:SystemDrive

    function Write-JsonFile ($Path, $Value) {
        $Parent = Split-Path -Path $Path -Parent
        if (-not (Test-Path $Parent)) {New-Item -Path $Parent -ItemType Directory -Force | Out-Null}
        Set-Content -Path $Path -Value $Value
    }
}

AfterAll {
    Get-Variable -Scope Global -Name $script:GlobalVariableNames -ErrorAction SilentlyContinue | Remove-Variable -Scope Global -Force
    foreach ($Variable in $script:SavedGlobalVariables) {Set-Variable -Scope Global -Name $Variable.Name -Value $Variable.Value}
    $env:ProgramData = $script:SavedProgramData
    $env:SystemDrive = $script:SavedSystemDrive
}

Describe 'Initialize-OSDBuilder' {
    BeforeEach {
        $Root = Join-Path $TestDrive ([guid]::NewGuid().Guid.Substring(0, 8))
        $OSDBuilderHome = Join-Path $Root 'OSDBuilder'
        New-Item -Path $OSDBuilderHome -ItemType Directory -Force | Out-Null
        #Never read or write the real ProgramData or SystemDrive
        $env:ProgramData = Join-Path $Root 'ProgramData'
        $env:SystemDrive = Join-Path $Root 'SystemDrive'
        $GlobalJson = Join-Path (Join-Path $env:ProgramData 'OSDeploy') 'OSDBuilder.json'
        $LocalJson = Join-Path $OSDBuilderHome 'OSDBuilder.json'

        #HKCU:\Software\OSDeploy
        $script:RegistryKey = $true
        $script:Registry = @{GetOSDBuilderHome = $OSDBuilderHome}
        Mock Test-Path -ParameterFilter {"$Path" -like 'HKCU:*'} {$script:RegistryKey}
        Mock New-Item -ParameterFilter {"$Path" -like 'HKCU:*'} {$script:RegistryKey = $true}
        Mock Get-ItemProperty -ParameterFilter {"$Path" -like 'HKCU:*'} {
            if ($Name) {
                if ($script:Registry.ContainsKey("$Name")) {[PSCustomObject]@{"$Name" = $script:Registry["$Name"]}}
            }
            else {[PSCustomObject]$script:Registry}
        }
        Mock Rename-ItemProperty -ParameterFilter {"$Path" -like 'HKCU:*'} {
            $script:Registry["$NewName"] = $script:Registry["$Name"]
            $script:Registry.Remove("$Name")
        }
        Mock New-ItemProperty -ParameterFilter {"$Path" -like 'HKCU:*'} {$script:Registry["$Name"] = ''}
        Mock Set-ItemProperty -ParameterFilter {"$Path" -like 'HKCU:*'} {$script:Registry["$Name"] = $Value}

        Get-Variable -Scope Global -Name 'GetOSDBuilder', 'SetOSDBuilder' -ErrorAction SilentlyContinue | Remove-Variable -Scope Global -Force
    }

    It 'reads the home path from HKCU:\Software\OSDeploy GetOSDBuilderHome' {
        Initialize-OSDBuilder 4>$null

        $global:GetOSDBuilderHome | Should -Be $OSDBuilderHome
        $global:GetOSDBuilder.Home | Should -Be $OSDBuilderHome
        $global:GetOSDBuilder.Initialize | Should -BeTrue
        $global:GetOSDBuilder.JsonLocal | Should -Be $LocalJson
        $global:GetOSDBuilder.JsonGlobal | Should -Be $GlobalJson
        Should -Invoke New-Item -Times 0 -Exactly -ParameterFilter {"$Path" -like 'HKCU:*'}
        Should -Invoke New-ItemProperty -Times 0 -Exactly -ParameterFilter {"$Path" -like 'HKCU:*'}
        Should -Invoke Set-ItemProperty -Times 0 -Exactly -ParameterFilter {"$Path" -like 'HKCU:*'}
    }

    It 'sets the OSDBuilder path variables below the home path' {
        Initialize-OSDBuilder 4>$null

        $Content = Join-Path $OSDBuilderHome 'Content'
        $global:SetOSDBuilderPathContent | Should -Be $Content
        $global:SetOSDBuilderPathContentPacks | Should -Be (Join-Path $OSDBuilderHome 'ContentPacks')
        $global:SetOSDBuilderPathFeatureUpdates | Should -Be (Join-Path $OSDBuilderHome 'FeatureUpdates')
        $global:SetOSDBuilderPathMount | Should -Be (Join-Path $OSDBuilderHome 'Mount')
        $global:SetOSDBuilderPathOSBuilds | Should -Be (Join-Path $OSDBuilderHome 'OSBuilds')
        $global:SetOSDBuilderPathOSImport | Should -Be (Join-Path $OSDBuilderHome 'OSImport')
        $global:SetOSDBuilderPathOSMedia | Should -Be (Join-Path $OSDBuilderHome 'OSMedia')
        $global:SetOSDBuilderPathPEBuilds | Should -Be (Join-Path $OSDBuilderHome 'PEBuilds')
        $global:SetOSDBuilderPathTasks | Should -Be (Join-Path $OSDBuilderHome 'Tasks')
        $global:SetOSDBuilderPathTemplates | Should -Be (Join-Path $OSDBuilderHome 'Templates')
        $global:SetOSDBuilderPathUpdates | Should -Be (Join-Path $OSDBuilderHome 'Updates')
        $global:GetOSDBuilderPathContentADK | Should -Be (Join-Path $Content 'ADK')
        $global:GetOSDBuilderPathContentDaRT | Should -Be (Join-Path $Content 'DaRT')
        $global:GetOSDBuilderPathContentDrivers | Should -Be (Join-Path $Content 'Drivers')
        $global:GetOSDBuilderPathContentExtraFiles | Should -Be (Join-Path $Content 'ExtraFiles')
        $global:GetOSDBuilderPathContentIsoExtract | Should -Be (Join-Path $Content 'IsoExtract')
        $global:GetOSDBuilderPathContentOneDrive | Should -Be (Join-Path $Content 'OneDrive')
        $global:GetOSDBuilderPathContentPackages | Should -Be (Join-Path $Content 'Packages')
        $global:GetOSDBuilderPathContentScripts | Should -Be (Join-Path $Content 'Scripts')
        $global:GetOSDBuilderPathContentStartLayout | Should -Be (Join-Path $Content 'StartLayout')
        $global:GetOSDBuilderPathContentUnattend | Should -Be (Join-Path $Content 'Unattend')
        $global:GetOSDBuilder.PathContentIsoExtract | Should -Be (Join-Path $Content 'IsoExtract')
    }

    It 'sets the default settings' {
        Initialize-OSDBuilder 4>$null

        $global:SetOSDBuilder.AllowContentPacks | Should -BeTrue
        $global:SetOSDBuilder.AllowGlobalOptions | Should -BeTrue
        $global:SetOSDBuilder.NewOSBuildCreateISO | Should -BeFalse
        $global:SetOSDBuilder.UpdateOSMediaDownload | Should -BeFalse
        $global:SetOSDBuilder.UpdateOSMediaName | Should -BeNullOrEmpty
        $global:SetOSDBuilder.NewPEBuildExecute | Should -BeFalse
        $global:GetOSDBuilder.Contains('LocalSettings') | Should -BeFalse
        $global:GetOSDBuilder.Contains('GlobalSettings') | Should -BeFalse
    }

    It 'writes "Initializing OSDBuilder ..." to the verbose stream' {
        (Initialize-OSDBuilder 4>&1) -join "`n" | Should -BeLike '*Initializing OSDBuilder ...*'
    }

    It 'creates the registry key and value and uses SystemDrive\OSDBuilder when nothing is set' {
        $script:RegistryKey = $false
        $script:Registry = @{}

        Initialize-OSDBuilder 4>$null

        Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {("$Path" -eq 'HKCU:\Software') -and ($Name -eq 'OSDeploy')}
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {$Name -eq 'GetOSDBuilderHome'}
        $script:Registry.GetOSDBuilderHome | Should -Be "$env:SystemDrive\OSDBuilder"
        $global:GetOSDBuilderHome | Should -Be "$env:SystemDrive\OSDBuilder"
        $global:SetOSDBuilderPathOSMedia | Should -Be (Join-Path "$env:SystemDrive\OSDBuilder" 'OSMedia')
    }

    It 'renames the OSBuilderPath value of OSBuilder to GetOSDBuilderHome' {
        $script:Registry = @{OSBuilderPath = $OSDBuilderHome}

        Initialize-OSDBuilder 4>$null

        Should -Invoke Rename-ItemProperty -Times 1 -Exactly -ParameterFilter {($Name -eq 'OSBuilderPath') -and ($NewName -eq 'GetOSDBuilderHome')}
        $script:Registry.ContainsKey('OSBuilderPath') | Should -BeFalse
        $global:GetOSDBuilderHome | Should -Be $OSDBuilderHome
    }

    It 'saves -SetHome in the registry and uses it as home path' {
        $NewHome = Join-Path $Root 'NewHome'

        Initialize-OSDBuilder -SetHome $NewHome 4>$null

        Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter {($Name -eq 'GetOSDBuilderHome') -and ($Value -eq $NewHome)}
        $script:Registry.GetOSDBuilderHome | Should -Be $NewHome
        $global:GetOSDBuilderHome | Should -Be $NewHome
        $global:SetOSDBuilderPathOSBuilds | Should -Be (Join-Path $NewHome 'OSBuilds')
    }

    It 'imports the settings of OSDBuilder.json in the home path' {
        $CustomContent = Join-Path $Root 'SharedContent'
        Write-JsonFile -Path $LocalJson -Value (@{NewOSBuildCreateISO = $true; UpdateOSMediaName = 'Windows 11 Enterprise x64 24H2'; PathContent = $CustomContent} | ConvertTo-Json)

        Initialize-OSDBuilder 4>$null

        $global:SetOSDBuilder.NewOSBuildCreateISO | Should -BeTrue
        $global:SetOSDBuilder.UpdateOSMediaName | Should -Be 'Windows 11 Enterprise x64 24H2'
        $global:SetOSDBuilderPathContent | Should -Be $CustomContent
        $global:GetOSDBuilderPathContentDrivers | Should -Be (Join-Path $CustomContent 'Drivers')
        @($global:GetOSDBuilder.LocalSettings.Name) | Sort-Object | Should -Be @('NewOSBuildCreateISO', 'PathContent', 'UpdateOSMediaName')
    }

    It 'imports ProgramData\OSDeploy\OSDBuilder.json after the local settings' {
        Write-JsonFile -Path $LocalJson -Value (@{UpdateOSMediaName = 'Local'; NewOSBuildCreateISO = $true} | ConvertTo-Json)
        Write-JsonFile -Path $GlobalJson -Value (@{UpdateOSMediaName = 'Global'; NewPEBuildCreateISO = $true} | ConvertTo-Json)

        Initialize-OSDBuilder 4>$null

        $global:SetOSDBuilder.UpdateOSMediaName | Should -Be 'Global'
        $global:SetOSDBuilder.NewOSBuildCreateISO | Should -BeTrue
        $global:SetOSDBuilder.NewPEBuildCreateISO | Should -BeTrue
        @($global:GetOSDBuilder.GlobalSettings.Name) | Sort-Object | Should -Be @('NewPEBuildCreateISO', 'UpdateOSMediaName')
    }

    It 'does not import the global settings when the local settings set AllowGlobalOptions to false' {
        Write-JsonFile -Path $LocalJson -Value (@{AllowGlobalOptions = $false} | ConvertTo-Json)
        Write-JsonFile -Path $GlobalJson -Value (@{NewPEBuildCreateISO = $true} | ConvertTo-Json)

        Initialize-OSDBuilder 4>$null

        $global:SetOSDBuilder.AllowGlobalOptions | Should -BeFalse
        $global:SetOSDBuilder.NewPEBuildCreateISO | Should -BeFalse
        $global:GetOSDBuilder.Contains('GlobalSettings') | Should -BeFalse
    }

    It 'warns when the <Settings> settings cannot be imported' -TestCases @(
        @{Settings = 'local'; Json = 'LocalJson'}
        @{Settings = 'global'; Json = 'GlobalJson'}
    ) {
        $Path = Get-Variable -Name $Json -ValueOnly
        Write-JsonFile -Path $Path -Value '{"NewOSBuildCreateISO": tru'

        $Warnings = (Initialize-OSDBuilder 4>$null 3>&1) -join "`n"

        $Warnings | Should -Be "Unable to import $Path"
        $global:SetOSDBuilder.NewOSBuildCreateISO | Should -BeFalse
    }

    It 'renames the old <Directory> directory to FeatureUpdates' -TestCases @(
        @{Directory = 'Media'}
        @{Directory = 'OSDownload'}
    ) {
        New-TestFile -Path (Join-Path (Join-Path $OSDBuilderHome $Directory) 'Windows 11 24H2.esd') | Out-Null

        $Warnings = (Initialize-OSDBuilder 4>$null 3>&1) -join "`n"

        $Warnings | Should -BeLike "Renaming *$Directory to $(Join-Path $OSDBuilderHome 'FeatureUpdates')"
        Join-Path $OSDBuilderHome $Directory | Should -Not -Exist
        Join-Path (Join-Path $OSDBuilderHome 'FeatureUpdates') 'Windows 11 24H2.esd' | Should -Exist
    }

    It 'moves Content\OSDUpdate to Updates' {
        $OSDUpdate = Join-Path (Join-Path $OSDBuilderHome 'Content') 'OSDUpdate'
        New-TestFile -Path (Join-Path (Join-Path $OSDUpdate 'Windows 10 22H2') 'kb5050001.msu') | Out-Null

        $Warnings = (Initialize-OSDBuilder 4>$null 3>&1) -join "`n"

        $Updates = Join-Path $OSDBuilderHome 'Updates'
        $Warnings | Should -BeLike "Moving *OSDUpdate to $Updates"
        Join-Path (Join-Path $Updates 'Windows 10 22H2') 'kb5050001.msu' | Should -Exist
        $OSDUpdate | Should -Not -Exist
    }

    It 'warns that Content\Mount has been moved to Mount' {
        New-Item -Path (Join-Path (Join-Path $OSDBuilderHome 'Content') 'Mount') -ItemType Directory -Force | Out-Null

        $Warnings = @(Initialize-OSDBuilder 4>$null 3>&1)

        $Warnings[0] | Should -BeLike "*Mount has been moved to $(Join-Path $OSDBuilderHome 'Mount')"
        $Warnings[1] | Should -Be "Verify that you don't have any active mounted images and remove this directory"
    }

    It 'warns and stops when <Command> fails' -TestCases @(
        @{Command = 'New-Item'; Registry = @{}; RegistryKey = $false; SetHome = $null; Warning = 'Unable to New-Item HKCU:\Software\OSDeploy'}
        @{Command = 'Rename-ItemProperty'; Registry = @{OSBuilderPath = 'D:\OSBuilder'}; RegistryKey = $true; SetHome = $null; Warning = 'Unable to Rename-ItemProperty HKCU:\Software\OSDeploy OSBuilderPath to GetOSDBuilderHome'}
        @{Command = 'New-ItemProperty'; Registry = @{}; RegistryKey = $true; SetHome = $null; Warning = 'Unable to New-ItemProperty HKCU:\Software\OSDeploy GetOSDBuilderHome'}
        @{Command = 'Set-ItemProperty'; Registry = @{GetOSDBuilderHome = 'D:\OSDBuilder'}; RegistryKey = $true; SetHome = 'E:\OSDBuilder'; Warning = 'Unable to Set-ItemProperty HKCU:\Software\OSDeploy GetOSDBuilderHome to E:\OSDBuilder'}
    ) {
        $script:RegistryKey = $RegistryKey
        $script:Registry = $Registry
        Mock $Command -ParameterFilter {"$Path" -like 'HKCU:*'} {throw 'Access is denied'}

        #Initialize-OSDBuilder stops with Break, Break leaves the enclosing loop
        $Warnings = foreach ($Attempt in 1) {
            if ($SetHome) {Initialize-OSDBuilder -SetHome $SetHome 4>$null 3>&1}
            else {Initialize-OSDBuilder 4>$null 3>&1}
        }

        "$Warnings" | Should -Be $Warning
        $global:GetOSDBuilder | Should -BeNullOrEmpty
    }
}

Describe 'Get-OSDBuilder' {
    BeforeEach {
        $Root = Join-Path $TestDrive ([guid]::NewGuid().Guid.Substring(0, 8))
        $OSDBuilderHome = Join-Path $Root 'OSDBuilder'
        $env:ProgramData = Join-Path $Root 'ProgramData'
        $env:SystemDrive = Join-Path $Root 'SystemDrive'

        $script:RegistryKey = $true
        $script:Registry = @{GetOSDBuilderHome = $OSDBuilderHome}
        Mock Test-Path -ParameterFilter {"$Path" -like 'HKCU:*'} {$script:RegistryKey}
        Mock New-Item -ParameterFilter {"$Path" -like 'HKCU:*'} {$script:RegistryKey = $true}
        Mock Get-ItemProperty -ParameterFilter {"$Path" -like 'HKCU:*'} {
            if ($Name) {
                if ($script:Registry.ContainsKey("$Name")) {[PSCustomObject]@{"$Name" = $script:Registry["$Name"]}}
            }
            else {[PSCustomObject]$script:Registry}
        }
        Mock New-ItemProperty -ParameterFilter {"$Path" -like 'HKCU:*'} {$script:Registry["$Name"] = ''}
        Mock Set-ItemProperty -ParameterFilter {"$Path" -like 'HKCU:*'} {$script:Registry["$Name"] = $Value}

        Initialize-OSDBuilder 4>$null

        $script:ModuleOSDBuilder = @([PSCustomObject]@{Name = 'OSDBuilder'; Version = [version]'26.10.1'})
        Mock Get-Module -ParameterFilter {$Name -eq 'OSD'} {[PSCustomObject]@{Name = 'OSD'; Version = [version]'25.5.1'}}
        Mock Get-Module -ParameterFilter {$Name -eq 'OSDBuilder'} {$script:ModuleOSDBuilder}

        $script:PublicJson = [PSCustomObject]@{
            OSD                 = '25.5.1'
            OSDBuilder          = '26.10.1'
            OSDBuilderUpdates   = @('26.10.1 Windows 11 26H2')
            OSDBuilderHelp      = @('https://osdbuilder.osdeploy.com')
            OSDBuilderNew       = @('https://github.com/OSDeploy/OSDBuilder')
        }
        Mock Invoke-WebRequest {[PSCustomObject]@{StatusCode = 200}}
        Mock Invoke-RestMethod {$script:PublicJson}

        Mock Show-OSDBuilderHomeTips {}
        Mock New-OSDBuilderContentPack {}
        Mock Get-OSMedia {[PSCustomObject]@{Name = 'Windows 11 Enterprise x64 24H2 26100.4061 en-US'}}
        Mock Update-OSMedia {}
        Mock Save-OSDBuilderDownload {}
        Mock Update-ModuleOSDBuilder {}
    }

    It 'initializes OSDBuilder when the variables are not set' {
        Remove-Variable -Scope Global -Name 'GetOSDBuilder' -Force

        Get-OSDBuilder -HideDetails 4>$null

        $global:GetOSDBuilder.Home | Should -Be $OSDBuilderHome
        $global:SetOSDBuilderPathOSMedia | Should -Be (Join-Path $OSDBuilderHome 'OSMedia')
    }

    It 'resets the settings with -Initialize' {
        $global:SetOSDBuilder.NewOSBuildCreateISO = $true
        Get-OSDBuilder -HideDetails 4>$null
        $global:SetOSDBuilder.NewOSBuildCreateISO | Should -BeTrue

        Get-OSDBuilder -Initialize -HideDetails 4>$null

        $global:SetOSDBuilder.NewOSBuildCreateISO | Should -BeFalse
    }

    It 'changes the home path with -<Parameter>' -TestCases @(
        @{Parameter = 'SetHome'}
        @{Parameter = 'SetPath'}
        @{Parameter = 'Path'}
    ) {
        $NewHome = Join-Path $Root 'NewHome'
        $Parameters = @{HideDetails = $true; $Parameter = $NewHome}

        Get-OSDBuilder @Parameters 4>$null

        $script:Registry.GetOSDBuilderHome | Should -Be $NewHome
        $global:GetOSDBuilderHome | Should -Be $NewHome
        $global:SetOSDBuilderPathOSMedia | Should -Be (Join-Path $NewHome 'OSMedia')
    }

    It 'initializes again when the home path in the registry was changed' {
        $script:Registry.GetOSDBuilderHome = Join-Path $Root 'ChangedHome'

        Get-OSDBuilder -HideDetails 4>$null

        $global:GetOSDBuilderHome | Should -Be (Join-Path $Root 'ChangedHome')
        $global:SetOSDBuilderPathOSBuilds | Should -Be (Join-Path (Join-Path $Root 'ChangedHome') 'OSBuilds')
    }

    It 'saves the OSD and OSDBuilder module versions and does not use the network with -HideDetails' {
        Get-OSDBuilder -HideDetails 4>$null

        $global:GetOSDBuilder.PSModuleOSD.Name | Should -Be 'OSD'
        $global:GetOSDBuilder.PSModuleOSDBuilder.Name | Should -Be 'OSDBuilder'
        $global:GetOSDBuilder.VersionOSD | Should -Be ([version]'25.5.1')
        $global:GetOSDBuilder.VersionOSDBuilder | Should -Be ([version]'26.10.1')
        $global:GetOSDBuilder.VersionOSDPublic | Should -Be ([version]'25.5.1')
        $global:GetOSDBuilder.VersionOSDBuilderPublic | Should -Be ([version]'26.10.1')
        $global:GetOSDBuilder.PublicJsonURL | Should -Be 'https://raw.githubusercontent.com/OSDeploy/OSD.Public/master/OSD.json'
        $global:GetOSDBuilder.PublicJson | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        Should -Invoke Show-OSDBuilderHomeTips -Times 0 -Exactly
    }

    It 'reads the public versions from OSD.json and shows the home paths, updates and links' {
        $Output = (Get-OSDBuilder 4>$null 6>&1) -join "`n"

        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {$Uri -eq 'https://raw.githubusercontent.com/OSDeploy/OSD.Public/master/OSD.json'}
        $global:GetOSDBuilder.PublicJson.OSDBuilder | Should -Be '26.10.1'
        $global:GetOSDBuilder.VersionOSDBuilderPublic | Should -Be '26.10.1'
        $global:GetOSDBuilder.VersionOSDPublic | Should -Be '25.5.1'
        $Output | Should -BeLike '*OSDBuilder 26.10.1*|*OSD 25.5.1*'
        $Output | Should -BeLike "*Home                $OSDBuilderHome*"
        $Output | Should -BeLike "*-OSMedia            $(Join-Path $OSDBuilderHome 'OSMedia')*"
        $Output | Should -BeLike "*-Updates            $(Join-Path $OSDBuilderHome 'Updates')*"
        $Output | Should -BeLike '*Latest Updates:*26.10.1 Windows 11 26H2*Helpful Links:*https://osdbuilder.osdeploy.com*New Links:*https://github.com/OSDeploy/OSDBuilder*'
        $Output | Should -Not -BeLike '*Release Preview*'
        Should -Invoke Show-OSDBuilderHomeTips -Times 1 -Exactly
    }

    It 'shows OFFLINE when OSD.json <Description>' -TestCases @(
        @{Description = 'cannot be downloaded'; WebRequest = {throw (New-Object -TypeName System.Net.WebException -ArgumentList 'The remote name could not be resolved')}}
        @{Description = 'returns 404'; WebRequest = {[PSCustomObject]@{StatusCode = 404}}}
    ) {
        Mock Invoke-WebRequest $WebRequest

        $Verbose = (Get-OSDBuilder 6>$null 4>&1) -join "`n"

        $Verbose | Should -BeLike '*OSDBuilder 26.10.1 | OSD 25.5.1 | OFFLINE*'
        $global:GetOSDBuilder.PublicJson | Should -BeNullOrEmpty
        $global:GetOSDBuilder.VersionOSDBuilderPublic | Should -Be ([version]'26.10.1')
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        Should -Invoke Show-OSDBuilderHomeTips -Times 1 -Exactly
    }

    # KnownBug: Get-OSDBuilder.ps1:78 catch [Net.WebException] does not catch the HttpRequestException of Invoke-WebRequest in PowerShell 7
    It 'shows OFFLINE when Invoke-WebRequest fails with another exception' -Skip {
        Mock Invoke-WebRequest {throw (New-Object -TypeName System.Exception -ArgumentList 'No such host is known')}

        {Get-OSDBuilder -ErrorAction Stop 6>$null 4>$null} | Should -Not -Throw
        $global:GetOSDBuilder.PublicJson | Should -BeNullOrEmpty
    }

    It 'warns when OSDBuilder and OSD can be updated' {
        $script:PublicJson.OSDBuilder = '26.11.1'
        $script:PublicJson.OSD = '25.6.1'

        $Output = (Get-OSDBuilder 4>$null 6>&1 3>&1) -join "`n"

        $Output | Should -BeLike '*OSDBuilder can be updated to 26.11.1*OSDBuilder -Update*'
        $Output | Should -BeLike '*OSD can be updated to 25.6.1*Update-Module OSD -Force*'
    }

    It 'shows a Release Preview when OSDBuilder and OSD are newer than the public versions' {
        $script:PublicJson.OSDBuilder = '26.9.1'
        $script:PublicJson.OSD = '25.4.1'

        $Output = (Get-OSDBuilder 4>$null 6>&1 3>&1) -join "`n"

        $Output | Should -BeLike '*OSDBuilder Release Preview*The current Public version is 26.9.1*OSD Release Preview*The current Public version is 25.4.1*'
        $Output | Should -Not -BeLike '*can be updated*'
    }

    It 'creates the OSDBuilder directories and the _Global ContentPack with -<Parameter>' -TestCases @(
        @{Parameter = 'CreatePaths'}
        @{Parameter = 'Create'}
    ) {
        $Parameters = @{HideDetails = $true; $Parameter = $true}

        Get-OSDBuilder @Parameters 4>$null

        foreach ($Directory in 'Content', 'ContentPacks', 'FeatureUpdates', 'Mount', 'OSBuilds', 'OSImport', 'OSMedia', 'PEBuilds', 'Tasks', 'Templates', 'Updates') {
            Join-Path $OSDBuilderHome $Directory | Should -Exist
        }
        foreach ($Directory in 'ADK', 'DaRT', 'Drivers', 'ExtraFiles', 'OneDrive', 'Packages', 'Scripts', 'StartLayout', 'Unattend') {
            Join-Path (Join-Path $OSDBuilderHome 'Content') $Directory | Should -Exist
        }
        Should -Invoke New-OSDBuilderContentPack -Times 1 -Exactly -ParameterFilter {$Name -eq '_Global'}
    }

    It 'does not create directories without -CreatePaths' {
        Get-OSDBuilder -HideDetails 4>$null
        $OSDBuilderHome | Should -Not -Exist
        Should -Invoke New-OSDBuilderContentPack -Times 0 -Exactly
    }

    It 'warns and stops when multiple OSDBuilder modules are loaded' {
        $script:ModuleOSDBuilder = @(
            [PSCustomObject]@{Name = 'OSDBuilder'; Version = [version]'26.10.1'}
            [PSCustomObject]@{Name = 'OSDBuilder'; Version = [version]'26.9.1'}
        )

        #Get-OSDBuilder stops with Break, Break leaves the enclosing loop
        $Warnings = foreach ($Attempt in 1) {Get-OSDBuilder -CreatePaths -HideDetails 4>$null 3>&1}

        @($Warnings) | Should -Be @('Multiple OSDBuilder Modules are loaded', 'Close all open PowerShell sessions before using OSDBuilder')
        $global:GetOSDBuilder.VersionOSDBuilder | Should -Be ([version]'26.10.1')
        $OSDBuilderHome | Should -Not -Exist
        Should -Invoke New-OSDBuilderContentPack -Times 0 -Exactly
    }

    It 'warns about directories that are no longer required' {
        $Content = Join-Path $OSDBuilderHome 'Content'
        foreach ($Directory in (Join-Path $Content 'UpdateStacks'), (Join-Path $Content 'UpdateWindows'), (Join-Path (Join-Path $OSDBuilderHome 'Updates') 'Windows 10 1903')) {
            New-Item -Path $Directory -ItemType Directory -Force | Out-Null
        }

        $Warnings = @(Get-OSDBuilder -HideDetails 4>$null 3>&1)

        $Warnings.Count | Should -Be 3
        $Warnings[0] | Should -BeLike "'*UpdateStacks' is no longer required and should be removed"
        $Warnings[1] | Should -BeLike "'*UpdateWindows' is no longer required and should be removed"
        $Warnings[2] | Should -BeLike "'*Windows 10 1903' is no longer required and should be removed"
    }

    It 'downloads the missing updates of all OSMedia with <Description>' -TestCases @(
        @{Description = '-Download OSMediaUpdates'; Parameters = @{Download = 'OSMediaUpdates'}}
        @{Description = '-Quick Download'; Parameters = @{Quick = 'Download'}}
    ) {
        Get-OSDBuilder @Parameters 4>$null 6>$null

        Should -Invoke Get-OSMedia -Times 1 -Exactly
        Should -Invoke Update-OSMedia -Times 1 -Exactly -ParameterFilter {$Download -and ($Name -eq 'Windows 11 Enterprise x64 24H2 26100.4061 en-US')}
        Should -Invoke Save-OSDBuilderDownload -Times 0 -Exactly
        Should -Invoke Show-OSDBuilderHomeTips -Times 0 -Exactly
    }

    It 'calls Save-OSDBuilderDownload <Expected> with <Description>' -TestCases @(
        @{Description = '-Quick Cleanup'; Parameters = @{Quick = 'Cleanup'}; Expected = '-Superseded Remove'; Filter = {$Superseded -eq 'Remove'}}
        @{Description = '-Download FeatureUpdates'; Parameters = @{Download = 'FeatureUpdates'}; Expected = '-FeatureUpdates'; Filter = {$FeatureUpdates}}
        @{Description = '-Download OneDrive'; Parameters = @{Download = 'OneDrive'}; Expected = '-ContentDownload "OneDriveSetup Production"'; Filter = {$ContentDownload -eq 'OneDriveSetup Production'}}
        @{Description = '-Quick OneDrive'; Parameters = @{Quick = 'OneDrive'}; Expected = '-ContentDownload "OneDriveSetup Production"'; Filter = {$ContentDownload -eq 'OneDriveSetup Production'}}
        @{Description = '-Download OneDriveEnterprise'; Parameters = @{Download = 'OneDriveEnterprise'}; Expected = '-ContentDownload "OneDriveSetup Enterprise"'; Filter = {$ContentDownload -eq 'OneDriveSetup Enterprise'}}
    ) {
        Get-OSDBuilder @Parameters 4>$null 6>$null

        Should -Invoke Save-OSDBuilderDownload -Times 1 -Exactly -ParameterFilter $Filter
        Should -Invoke Update-OSMedia -Times 0 -Exactly
        Should -Invoke Show-OSDBuilderHomeTips -Times 0 -Exactly
    }

    It 'updates the module with -<Parameter>' -TestCases @(
        @{Parameter = 'UpdateModule'}
        @{Parameter = 'Update'}
    ) {
        $Parameters = @{HideDetails = $true; $Parameter = $true}

        Get-OSDBuilder @Parameters 4>$null

        Should -Invoke Update-ModuleOSDBuilder -Times 1 -Exactly
    }

    It 'does not update the module without -UpdateModule' {
        Get-OSDBuilder 4>$null 6>$null
        Should -Invoke Update-ModuleOSDBuilder -Times 0 -Exactly
    }
}
