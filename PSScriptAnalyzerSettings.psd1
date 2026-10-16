@{
    #Used by Tests\Invoke-OSDBuilderTests.ps1 -Lint and the GitHub Actions workflow
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        #OSDBuilder writes its progress to the console
        'PSAvoidUsingWriteHost'
        #Private servicing functions are called by New-OSBuild and Update-OSMedia, they do not support -WhatIf
        'PSUseShouldProcessForStateChangingFunctions'
        #Function names follow the existing module, for example Get-OSDUpdates
        'PSUseSingularNouns'
        #The module uses global OSDBuilder paths, for example $global:SetOSDBuilderPathContent
        'PSAvoidGlobalVars'
        #Pester scopes and the dynamic scoping of the build functions, variables are set in one scope and read in another
        'PSUseDeclaredVarsMoreThanAssignments'
        #Test stubs declare the parameters of the commands they replace
        'PSReviewUnusedParameter'
    )
}
