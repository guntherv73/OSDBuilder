# OSDBuilder

PowerShell Module for offline servicing of Windows images.
https://osdbuilder.osdeploy.com

## Admin host requirements

| Host | Support |
|------|---------|
| Windows 10 / 11, Windows Server 2016+ with Windows PowerShell 5.1 | Supported |
| Windows 10 / 11, Windows Server 2016+ with PowerShell 7.4+ | Experimental (DISM and BitsTransfer are loaded natively or with Windows PowerShell Compatibility) |
| macOS / Linux | Not supported locally, use PowerShell Remoting to a Windows host |

OSDBuilder services Windows images with DISM (CBS), robocopy, oscdimg, bcdboot and offline registry hives.
These components only exist on Windows, so the module refuses to import on macOS and Linux.

### Using OSDBuilder from macOS

Install PowerShell 7 on the Mac and connect to a Windows build host with SSH based PowerShell Remoting
([PowerShell remoting over SSH](https://learn.microsoft.com/en-us/powershell/scripting/security/remoting/ssh-remoting-in-powershell)).
The SSH user on the Windows host must be a local Administrator.

```powershell
# macOS
Enter-PSSession -HostName buildhost.contoso.local -UserName Administrator

# Windows build host (remote session)
Import-Module OSDBuilder
Update-OSMedia -Name 'Windows 11 Enterprise x64 25H2 26200.6584' -Download -Execute
```

Grid views (`Out-GridView`) are not available in a remote session, use the `-SkipGrid` / `-Name` parameters
or create the Tasks once in an interactive session on the Windows host.

## Windows 11 support

This fork supports Windows 11 x64 up to the latest releases:

| Release | Build | Microsoft Updates | Language content (LOF ISO) |
|---------|-------|-------------------|----------------------------|
| 22H2    | 22621 | Microsoft Update Catalog (end of servicing) | 22H2 / 23H2 |
| 23H2    | 22631 | Microsoft Update Catalog | 22H2 / 23H2 |
| 24H2    | 26100 | Microsoft Update Catalog | 24H2 / 25H2 / 26H2 |
| 25H2    | 26200 | Microsoft Update Catalog | 24H2 / 25H2 / 26H2 |
| 26H2    | 26300 | Microsoft Update Catalog | 24H2 / 25H2 / 26H2 |

### Microsoft Updates

The update manifests included in the OSD Module are an archive that is no longer updated
(the last Windows 11 updates are from February 2025, there is no 25H2 or 26H2 content).

OSDBuilder now queries the Microsoft Update Catalog directly for the latest
LCU, .NET Framework CU, Safe OS Dynamic Update and Setup Dynamic Update of each Windows 11 release.

* Results are cached for 12 hours in `<OSDBuilder>\Updates\_Catalog`
* If the Microsoft Update Catalog cannot be reached, the last cached result is used,
  otherwise the OSD Module archive is used
* Windows 10 and Windows Server updates still come from the OSD Module archive
* Windows 11 24H2 and newer LCUs consist of two MSU files (checkpoint cumulative update KB5043080 and the latest LCU).
  Both are downloaded and the checkpoint is installed first
* The Safe OS Dynamic Update is applied to WinRE

### Language Packs and Language Features on Demand

Download and extract the Windows 11 *Languages and Optional Features* ISO published by Microsoft
([source](https://learn.microsoft.com/en-us/azure/virtual-desktop/windows-11-language-packs)):

```powershell
Save-OSDBuilderDownload -ContentDownload 'Windows 11 24H2-26H2 x64 Languages and Optional Features'
Save-OSDBuilderDownload -ContentDownload 'Windows 11 22H2-23H2 x64 Languages and Optional Features'

# Inbox Apps (app packages, license files and framework dependencies), extracted to Content\InboxApps
Save-OSDBuilderDownload -ContentDownload 'Windows 11 24H2-26H2 Inbox Apps'
Save-OSDBuilderDownload -ContentDownload 'Windows 11 22H2-23H2 Inbox Apps'
```

* The ISO (6-7 GB) is saved to `Content\ISO` and reused, an interrupted download is resumed on the next run
* The ISO is extracted to `Content\IsoExtract\<Name>`, about twice the ISO size of free space is required
* Microsoft publishes the 26100 ISO for 24H2 and 25H2, 26H2 uses the same 26100 servicing branch
* Then run `New-OSBuildTask` to select the Language Packs, Language Features and Features on Demand

You can also extract an ISO manually to the `Content\IsoExtract` directory.
The directory name must contain the ReleaseId, for example:

```
Content\IsoExtract\Windows 11 24H2 Language\LanguagesAndOptionalFeatures\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab
```

* Windows 11 24H2, 25H2 and 26H2 share the same ISO (26100), a `24H2` directory is offered for all three releases
* Windows 11 22H2 and 23H2 share the same ISO (22621)
* Directories containing `Windows 10` are not offered for Windows 11 media (and vice versa)
* Language Features are installed in the required order: Basic, Fonts, OCR, Handwriting, TextToSpeech, Speech
* The Windows 11 Language Interface Packs `Microsoft-Windows-Lip-Language-Pack_x64_<lang>.cab`
  (ca-ES, eu-ES, gl-ES, id-ID, vi-VN) are offered as Language Interface Packs and added after the Language Packs.
  Add the base Language Pack too (es-ES for ca-ES, eu-ES and gl-ES, en-US for id-ID and vi-VN)

### Features on Demand (Add-WindowsCapability)

Features on Demand are added with `Add-WindowsCapability` as recommended by Microsoft
([Features on Demand](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-v2--capabilities)).

* `New-OSBuildTask -ContentFeaturesOnDemand` offers the Windows Capabilities that are NotPresent in the OSMedia
  (inventory `info\xml\Get-WindowsCapability.xml`) and saves them in the Task as `AddWindowsCapability`
* The source is every Features on Demand repository in `Content\IsoExtract` that matches the OSMedia
  (a directory with a `metadata` directory, for example `LanguagesAndOptionalFeatures`), Windows Update is not used
* Language Features are added with their capability name (for example `Language.Basic~~~de-DE~0.0.1.0`),
  `Add-WindowsPackage` is only used when the capability cannot be added
* Tasks with Features on Demand `.cab` files (`AddFeatureOnDemand`) still work, recreate the Task to switch to `AddWindowsCapability`
* The LCU is reapplied once after Language and Feature on Demand content is added
