#requires -Module WebAdministration

<#
    This resource is deliberately narrow in focus for the moment.  Maybe we could expand it to support any
    usage of Get-WebConfiguration and Set-WebConfiguration, but that would require a lot of testing that we
    don't need yet.

    This has only been tested on Windows Server 2012 R2.
#>

function Get-TargetResource
{
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('applicationInitialization', 'httpProtocol', 'httpErrors', 'httpRedirect', 'globalModules',
                     'cgi', 'serverRuntime', 'directoryBrowse', 'urlCompression', 'webSocket', 'httpLogging',
                     'modules', 'odbcLogging', 'validation', 'fastCgi', 'handlers', 'httpTracing', 'staticContent',
                     'isapiFilters', 'defaultDocument', 'asp', 'httpCompression', 'serverSideInclude', 'caching')]
        [string] $FeatureName,

        [Parameter(Mandatory)]
        [ValidateSet('Allow', 'Deny')]
        [string] $Mode
    )

    return @{
        FeatureName = $FeatureName
        Mode = (Get-WebConfiguration -Filter "//System.webServer/$FeatureName" -Metadata).OverrideMode
    }
}

function Set-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [ValidateSet('applicationInitialization', 'httpProtocol', 'httpErrors', 'httpRedirect', 'globalModules',
                     'cgi', 'serverRuntime', 'directoryBrowse', 'urlCompression', 'webSocket', 'httpLogging',
                     'modules', 'odbcLogging', 'validation', 'fastCgi', 'handlers', 'httpTracing', 'staticContent',
                     'isapiFilters', 'defaultDocument', 'asp', 'httpCompression', 'serverSideInclude', 'caching')]
        [string] $FeatureName,

        [Parameter(Mandatory)]
        [ValidateSet('Allow', 'Deny')]
        [string] $Mode
    )

    $appCmd = Join-Path $env:SystemRoot 'system32\inetsrv\appcmd.exe'
    if (-not (Test-Path -LiteralPath $appCmd -PathType Leaf))
    {
        throw "Required commad '$appcmd' was not found."
    }

    $command = if ($Mode -eq 'Allow') { 'unlock' } else { 'lock' }

    & $appCmd $command config /section:$FeatureName
    if ($LASTEXITCODE -ne 0)
    {
        throw "appcmd.exe returned error code $LASTEXITCODE"
    }

    #Set-WebConfiguration -Filter "//System.webServer/$FeatureName" -Metadata overrideMode -Value $Mode
}

function Test-TargetResource
{
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('applicationInitialization', 'httpProtocol', 'httpErrors', 'httpRedirect', 'globalModules',
                     'cgi', 'serverRuntime', 'directoryBrowse', 'urlCompression', 'webSocket', 'httpLogging',
                     'modules', 'odbcLogging', 'validation', 'fastCgi', 'handlers', 'httpTracing', 'staticContent',
                     'isapiFilters', 'defaultDocument', 'asp', 'httpCompression', 'serverSideInclude', 'caching')]
        [string] $FeatureName,

        [Parameter(Mandatory)]
        [ValidateSet('Allow', 'Deny')]
        [string] $Mode
    )

    $currentMode = (Get-WebConfiguration -Filter "//System.webServer/$FeatureName" -Metadata).OverrideMode

    return $currentMode -eq $Mode
}

Export-ModuleMember -Function Get-TargetResource, Set-TargetResource, Test-TargetResource
