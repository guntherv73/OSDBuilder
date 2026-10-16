# Contributing to OSDBuilder

OSDBuilder is developed **test first (TDD)**. Every change to the behavior of the module starts with a failing Pester test.

## Test-driven development

1. **Red**: write a test in `Tests\<Area>.Tests.ps1` that describes the new behavior or reproduces the bug, run it and see it fail
   for the expected reason (not because of a typo in the test)
2. **Green**: write the minimal code in `Private\` or `Public\` that makes the test pass
3. **Refactor**: clean up the code and the test, the tests stay green
4. Run the complete suite with `-CI` before you push

A bug fix always contains the test that reproduced the bug. A pull request without tests for changed behavior is not merged.

## Running the tests

```powershell
# All tests (Windows PowerShell 5.1 or PowerShell 7, Windows, macOS or Linux)
.\Tests\Invoke-OSDBuilderTests.ps1

# One file, detailed output
.\Tests\Invoke-OSDBuilderTests.ps1 -Path .\Tests\LocalExperiencePacks.Tests.ps1 -Output Detailed

# Like the GitHub Actions workflow: PSScriptAnalyzer, tests, code coverage (minimum 75 %), exit code
.\Tests\Invoke-OSDBuilderTests.ps1 -CI
```

The runner installs Pester 5.7.1 and PSScriptAnalyzer 1.24.0 for the current user when they are missing.
The tests do not need administrator rights, a Windows image, DISM or network access.

The GitHub Actions workflow `.github/workflows/tests.yml` runs `-CI` on every push and pull request with
PowerShell 7 on Linux and Windows and with Windows PowerShell 5.1.

## Writing tests

| Area | File |
|------|------|
| Module manifest, syntax of all files | `Tests\Module.Tests.ps1` |
| Release and ContentPack mapping | `Tests\ReleaseSupport.Tests.ps1` |
| Features on Demand, Language capabilities | `Tests\WindowsCapability.Tests.ps1` |
| Microsoft Update Catalog | `Tests\MicrosoftUpdateCatalog.Tests.ps1` |
| ISO downloads (LOF, Inbox Apps, LXP) | `Tests\ContentIsoDownload.Tests.ps1` |
| Inbox Apps | `Tests\InboxApps.Tests.ps1` |
| WinRE and Windows Setup languages | `Tests\WinRELanguages.Tests.ps1` |
| Local Experience Packs | `Tests\LocalExperiencePacks.Tests.ps1`, `Tests\LocalExperiencePackDownload.Tests.ps1` |
| install.wim servicing (`AllFunctions.ps1`) | `Tests\OSServicing.Tests.ps1` |
| `Examples\New-Win11MultiLanguageBuild.ps1` | `Tests\Examples.Tests.ps1` |

* Dot-source `Tests\TestHelpers.ps1` in `BeforeAll`, then the Private scripts under test:
  ```powershell
  BeforeAll {
      . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
      foreach ($Script in (Get-OSDBuilderPrivateScript -Name 'ReleaseSupport','WindowsCapability')) {. $Script}
  }
  ```
* Mock every external effect: DISM and Appx cmdlets, `Invoke-WebRequest`, `Invoke-RestMethod`, `Invoke-OSDBuilderWinget`, BITS.
  `TestHelpers.ps1` defines placeholders for Windows only cmdlets and OSD module commands, so `Mock` works on every platform
* Use `$TestDrive` for files and `Join-Path` for paths, tests run on Windows and Linux
* Use real data from Microsoft as fixtures in `Tests\Fixtures` (Update Catalog HTML, Microsoft Store JSON, file names of the ISOs)
* External programs are called through a wrapper function that can be mocked, for example `Invoke-OSDBuilderWinget`
* Build functions read variables like `$MountDirectory` or `$OSBuild` from the calling scope, set them in the `It` or `BeforeEach` block
* Capture warnings with `3>&1` and assert them as text: `(Some-Function 3>&1) -join "`n" | Should -BeLike '*message*'`
* Check a new test once against the old code (or a deliberately reintroduced bug): it must fail

## Code style

* PSScriptAnalyzer runs with `PSScriptAnalyzerSettings.psd1` on the Private scripts written with tests, `Examples` and `Tests`.
  `AllFunctions.ps1` and `Public` are added when they are refactored with tests
* Windows PowerShell 5.1 compatible syntax, no PowerShell 7 only operators
* Code, comments, commit messages and pull requests in English
