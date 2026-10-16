#=================================================
#   Platform
#   OSDBuilder services Windows images with DISM, robocopy, oscdimg and offline registry hives
#   These are only available on Windows, macOS and Linux can manage a Windows host with PowerShell Remoting
#=================================================
if (($PSVersionTable.PSEdition -eq 'Core') -and (-not $IsWindows)) {
    throw "OSDBuilder requires Windows. From macOS or Linux, run OSDBuilder on a Windows host with PowerShell Remoting (Enter-PSSession -HostName <WindowsHost>)"
}
#=================================================
#   PowerShell 7
#   DISM and BitsTransfer are Windows PowerShell modules
#   PowerShell 7 loads them natively or with Windows PowerShell Compatibility
#=================================================
if ($PSVersionTable.PSEdition -eq 'Core') {
    foreach ($WindowsPowerShellModule in @('Dism','BitsTransfer')) {
        if (-not (Get-Module -Name $WindowsPowerShellModule)) {
            try {
                Import-Module -Name $WindowsPowerShellModule -ErrorAction Stop -WarningAction SilentlyContinue
            }
            catch {
                try {
                    Import-Module -Name $WindowsPowerShellModule -UseWindowsPowerShell -ErrorAction Stop -WarningAction SilentlyContinue
                }
                catch {
                    Write-Warning "OSDBuilder: Unable to import the $WindowsPowerShellModule module in PowerShell $($PSVersionTable.PSVersion)"
                }
            }
        }
    }
}
#=================================================
#   Import Functions
#   https://github.com/RamblingCookieMonster/PSStackExchange/blob/master/PSStackExchange/PSStackExchange.psm1
#=================================================
$OSDPublicFunctions  = @( Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -Recurse -ErrorAction SilentlyContinue )
$OSDPrivateFunctions = @( Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -Recurse -ErrorAction SilentlyContinue )

foreach ($Import in @($OSDPublicFunctions + $OSDPrivateFunctions)) {
    Try {. $Import.FullName}
    Catch {Write-Error -Message "Failed to import function $($Import.FullName): $_"}
}

Export-ModuleMember -Function $OSDPublicFunctions.BaseName
New-Alias -Name Get-OSBuilder -Value Get-OSDBuilder -Force -ErrorAction SilentlyContinue
New-Alias -Name New-OSBMediaISO -Value New-OSDBuilderISO -Force -ErrorAction SilentlyContinue
New-Alias -Name New-OSBMediaUSB -Value New-OSDBuilderUSB -Force -ErrorAction SilentlyContinue
New-Alias -Name Show-OSBMediaInfo -Value Show-OSDBuilderInfo -Force -ErrorAction SilentlyContinue
New-Alias -Name Get-DownOSDBuilder -Value Save-OSDBuilderDownload -Force -ErrorAction SilentlyContinue

<# #=================================================
#   ImportOSD
#=================================================
try {New-Alias -Name ImportOSD -Value Import-OSMedia -Force -ErrorAction SilentlyContinue}
catch {}
#=================================================
#   UpdateOSD
#=================================================
try {New-Alias -Name UpdateOSD -Value Update-OSMedia -Force -ErrorAction SilentlyContinue}
catch {}
#=================================================
#   BuildOSD
#=================================================
try {New-Alias -Name BuildOSD -Value New-OSBuild -Force -ErrorAction SilentlyContinue}
catch {}

#=================================================
#   OSDISO
#=================================================
try {New-Alias -Name OSDISO -Value New-OSDBuilderISO -Force -ErrorAction SilentlyContinue}
catch {}
#=================================================
#   OSDUSB
#=================================================
try {New-Alias -Name OSDUSB -Value New-OSDBuilderUSB -Force -ErrorAction SilentlyContinue}
catch {}
#=================================================
#   OSDInfo
#=================================================
try {New-Alias -Name OSDInfo -Value Show-OSDBuilderInfo -Force -ErrorAction SilentlyContinue}
catch {} #>

#=================================================
#   Export-ModuleMember
#=================================================
Export-ModuleMember -Function * -Alias *