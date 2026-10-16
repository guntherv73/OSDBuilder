# OSDBuilder

PowerShell Module for offline servicing of Windows images.
https://osdbuilder.osdeploy.com

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

Use the Windows 11 *Languages and Optional Features* ISO and extract it to the `Content\IsoExtract` directory.
The directory name must contain the ReleaseId, for example:

```
Content\IsoExtract\Windows 11 24H2 Language\LanguagesAndOptionalFeatures\Microsoft-Windows-Client-Language-Pack_x64_de-de.cab
```

* Windows 11 24H2, 25H2 and 26H2 share the same ISO (26100), a `24H2` directory is offered for all three releases
* Windows 11 22H2 and 23H2 share the same ISO (22621)
* Directories containing `Windows 10` are not offered for Windows 11 media (and vice versa)
* Language Features are installed in the required order: Basic, Fonts, OCR, Handwriting, TextToSpeech, Speech
* The LCU is reapplied after Language content is added
