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

## Example: fully patched multi-language Windows 11 image

[`Examples/New-Win11MultiLanguageBuild.ps1`](Examples/New-Win11MultiLanguageBuild.ps1) runs the complete build unattended (no Out-GridView):
download of the Languages and Optional Features and Inbox Apps ISOs, Import-OSMedia, Update-OSMedia,
a Task with the Language Packs, Language Features and Windows Capabilities of the selected languages, and New-OSBuild.

```powershell
.\Examples\New-Win11MultiLanguageBuild.ps1 -CustomerName 'Contoso' -OSDBuilderHome 'G:\OSDBuilder' `
    -SourceIso 'D:\ISO\Win11_25H2_x64.iso' -ReleaseId 25H2 -EditionId Enterprise `
    -Languages 'en-US','de-DE','fr-FR','sv-SE','ru-RU','sk-SK','th-TH' -DefaultLanguage 'en-US' `
    -CreateISO

# Windows Setup in English, German and French, German is the default Setup language
.\Examples\New-Win11MultiLanguageBuild.ps1 -CustomerName 'Contoso' -OSDBuilderHome 'G:\OSDBuilder' `
    -SourceIso 'D:\ISO\Win11_25H2_English_x64.iso' -MediaLanguage 'en-US' `
    -SetupLanguages 'de-DE','fr-FR' -SetupUILanguage 'de-DE' `
    -SetupLanguageIso 'D:\ISO\Win11_25H2_German_x64.iso','D:\ISO\Win11_25H2_French_x64.iso'
```

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
  (ca-ES, eu-ES, gl-ES, id-ID, vi-VN) are offered as Language Interface Packs and added after the Language Packs

### Local Experience Packs (LXP)

Windows 11 publishes 43 languages as `.cab` Language Packs (38) and Language Interface Packs (5) on the Languages and Optional Features ISO.
The other languages are only available as Local Experience Packs (`.appx`)
([Languages overview](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/languages-overview)), they are not on the ISO.

* Copy the LXPs to a directory in `Content\IsoExtract` that contains the ReleaseId, with the `License.xml` next to each `.appx`:
  ```
  Content\IsoExtract\Windows 11 24H2 LXP\LocalExperiencePack\nn-no\LanguageExperiencePack.nn-no.Neutral.appx
  Content\IsoExtract\Windows 11 24H2 LXP\LocalExperiencePack\nn-no\License.xml
  ```
* `New-OSBuildTask -ContentLanguagePackages` offers them as Local Experience Packs, the example script uses an LXP for every language without a `.cab`
* `New-OSBuild` adds each LXP with `Add-AppxProvisionedPackage` and checks:
  * the AppxManifest identity is a `Microsoft.LanguageExperiencePack*`
  * the `Windows.Desktop` MinVersion is in the servicing branch of the image (an LXP for 26100 is used for 24H2, 25H2 and 26H2, not for 23H2)
  * the License.xml exists
  * the same or a newer version is not already provisioned (no LCU reapply then)
  * the LXP is provisioned afterwards, the build shows a warning for every LXP that was not added
* OSLocalExperiencePacks ContentPacks use the same checks and only apply `LanguageExperiencePack*.appx`
* LXP languages are not added to WinRE and Windows Setup, Microsoft publishes WinRE and Setup languages only for the `.cab` languages

### Windows Recovery Environment languages

Microsoft distributes the WinRE language packs on the Languages and Optional Features ISO and recommends
the same languages in WinRE as in the Windows image
([Customize Windows RE](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/customize-windows-re)).

* `New-OSBuild` adds the Language Packs and Language Interface Packs of the Task to WinRE from
  `Windows Preinstallation Environment\x64\WinPE_OCs` of the extracted ISO:
  `lp.cab`, the language pack of every optional component in WinRE (not WinPE-WiFi) and the font support for Japanese, Korean and Chinese
* Optional components added to WinRE by the Task also get the language packs of the languages already in WinRE
* `SetAllIntl` of the Task is also set in WinRE
* With the ISO extracted, the WinRE ADK selection of `New-OSBuildTask` no longer offers the ADK language packs

### Windows Setup languages (LanguageCopySources)

Windows Setup shows its display languages and the language selection of the image from the Setup resources of each
language ([Add languages to Windows Setup](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-multilingual-support-to-windows-setup)).

1. Import the Windows 11 ISO of each Setup language with `Import-OSMedia` (same release and build, the OSMedia name contains the language)
2. Select these OSMedia with `New-OSBuildTask -SourcesLanguageCopy` (`LanguageCopySources`), set the default with `-SetSetupUILang`
3. `New-OSBuild`
   * adds `lp.cab`, `WinPE-Setup_<lang>`, `WinPE-Setup-Client_<lang>` (Server: `WinPE-Setup-Server_<lang>`), the language pack of every
     optional component of the Setup image and the font support (Japanese, Korean, Chinese, Thai `WinPE-FontSupport-WinRE`)
     to boot.wim index 2 (WinSE), from the Languages and Optional Features ISO, `Content\ADK` as fallback
   * copies the localized Setup resources (`sources\<lang>`) of the LanguageCopySources to the media
   * creates Lang.ini with `Dism /Gen-LangIni`, sets `SetSetupUILang` and copies Lang.ini to boot.wim

Language Interface Packs are not supported by Windows Setup.

### ContentPacks

* The `<OS> <ReleaseId> <Arch>` directory of a ContentPack type is used when it contains files, otherwise the directory
  of a compatible release: `Windows 11 24H2 x64` is used for Windows 11 25H2 and 26H2 (same 26100 servicing branch),
  `Windows 10 2004 x64` for Windows 10 20H2 - 22H2
* OSLanguageFeatures are added in the required order (Basic first) and with `Add-WindowsCapability`
  when the directory or a Languages and Optional Features ISO contains the metadata, otherwise with `Add-WindowsPackage`
* Languages of OSLanguagePacks ContentPacks are also added to WinRE and trigger the reinstall of the inbox apps

### .NET Framework 3.5

* `New-OSBuildTask -EnableNetFX3` enables NetFx3 in `New-OSBuild` after the image cleanup, followed by the .NET Framework CU
  (Microsoft order for install.wim: LCU, cleanup, .NET and .NET CU, export)
* Windows 11 24H2 and newer media has no `sources\sxs`, NetFx3 is added with `Add-WindowsCapability -Name NetFX3~~~~` from the
  Languages and Optional Features ISO (`Content\IsoExtract`), `sources\sxs` is used when the media contains it
* `Enable-WindowsOptionalFeature` is used when the capability cannot be added, the build shows a warning when NetFx3 is not Enabled afterwards
* Windows 11: the LCU is not applied again after NetFx3, Windows 10: the LCU is applied again as before
* The example script enables NetFx3 by default, use `-SkipNetFX3` to skip

### Inbox Apps

Microsoft recommends to reinstall the inbox apps after adding languages and updates, so the apps include the language resources.

* When the Task adds languages, `New-OSBuild` reinstalls the provisioned apps of the image from `Content\InboxApps`
* Only apps that are provisioned in the image are reinstalled, removed apps are not added again, and an app is skipped when the image contains a newer version
* The dependencies are read from the AppxManifest of each app (x64 and x86 frameworks for an x64 image), the license is the `.xml` with the same name
* `RemoveAppxProvisionedPackage` of the Task runs afterwards

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
