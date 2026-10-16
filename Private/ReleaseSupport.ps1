function Get-OSDBuilderLanguageReleasePattern {
    <#
    .SYNOPSIS
    Returns a regex of the ReleaseIds whose Language and Feature on Demand content is compatible with the OSMedia

    .DESCRIPTION
    Windows 10 2004 - 22H2 share the same Languages and Optional Features ISO
    Windows 11 22H2 - 23H2 share the same Languages and Optional Features ISO (22621)
    Windows 11 24H2 - 26H2 share the same Languages and Optional Features ISO (26100)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $OSMedia
    )
    $ReleaseId = [string]$OSMedia.ReleaseId

    if ($OSMedia.OperatingSystem -eq 'Windows 11') {
        switch ($ReleaseId) {
            {$_ -in '22H2','23H2'}          {Return '22H2|23H2'}
            {$_ -in '24H2','25H2','26H2'}   {Return '24H2|25H2|26H2'}
            default                         {Return [regex]::Escape($ReleaseId)}
        }
    }
    switch ($ReleaseId) {
        '1909'                                          {Return '1903|1909'}
        {$_ -in '2009','20H2','21H1','21H2','22H2'}     {Return '2004|2009|20H2|21H1|21H2|22H2'}
        default                                         {Return [regex]::Escape($ReleaseId)}
    }
}
function Get-OSDBuilderLanguageExcludePattern {
    <#
    .SYNOPSIS
    Returns a regex of content paths that belong to a different Operating System
    Windows 10 and Windows 11 share ReleaseIds (21H2, 22H2), so the content must be separated by name
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $OSMedia
    )
    if ($OSMedia.OperatingSystem -eq 'Windows 11') {Return 'Windows 10'}
    if ($OSMedia.OperatingSystem -eq 'Windows 10') {Return 'Windows 11'}
    #Matches nothing
    Return '(?!)'
}
function Get-OSDBuilderLanguageFeatureOrder {
    <#
    .SYNOPSIS
    Returns the install order of a Language Feature on Demand package
    Basic must be installed first, Speech requires TextToSpeech
    https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-language-fod
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    $Leaf = Split-Path $Name -Leaf
    if ($Leaf -like '*LanguageFeatures-Basic*')         {Return 0}
    if ($Leaf -like '*LanguageFeatures-Fonts*')         {Return 1}
    if ($Leaf -like '*LanguageFeatures-OCR*')           {Return 2}
    if ($Leaf -like '*LanguageFeatures-Handwriting*')   {Return 3}
    if ($Leaf -like '*LanguageFeatures-TextToSpeech*')  {Return 4}
    if ($Leaf -like '*LanguageFeatures-Speech*')        {Return 5}
    if ($Leaf -like '*Speech*')                         {Return 5}
    #Other Language Features are installed after Basic and before Speech
    Return 3
}
