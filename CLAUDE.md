# OSDBuilder

PowerShell module for offline servicing of Windows images (DISM). Fork with Windows 11 24H2 - 26H2, language and Microsoft Store support.

## Test-driven development is mandatory

Every change follows Red - Green - Refactor (see CONTRIBUTING.md):

1. Write or extend a Pester test in `Tests\` first and run it, it must fail for the expected reason
2. Implement the minimal change in `Private\`, `Public\` or `Examples\`
3. Run `Tests\Invoke-OSDBuilderTests.ps1 -CI` before every commit: PSScriptAnalyzer, all tests and code coverage >= 75 % must pass
4. Bug fixes include the test that reproduces the bug
5. Never skip, disable or weaken a test to get green

Run the tests in this environment with `pwsh -NoProfile -File Tests/Invoke-OSDBuilderTests.ps1 -CI`.

## Conventions

* Windows PowerShell 5.1 and PowerShell 7 compatible code
* DISM, Appx, BITS, web requests and winget are mocked in tests, never call real services in tests
* External programs are wrapped in a mockable function (`Invoke-OSDBuilderWinget`)
* Real Microsoft responses are stored as fixtures in `Tests\Fixtures`
* Validate claims about Microsoft products against Microsoft Learn or the published files, do not guess file names or versions
* Code, comments, commit messages and PR texts in English
* Never store names of customers in the repository, examples use `Contoso`
