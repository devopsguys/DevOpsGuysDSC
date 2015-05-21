# DOG_IISResources

This module currently only contains a single resource, cIISFeatureDelegation.  This is a simple wrapper around the Set-WebConfiguration cmdlet (specifically, with the -Metadata overrideMode option.)

Syntax:

```
cIISFeatureDelegation [String] #ResourceName
{
    FeatureName = [string]{ applicationInitialization | asp | caching | cgi | defaultDocument | directoryBrowse | fastCgi | globalModules | handlers | httpCompression | httpErrors | httpLogging | httpProtocol | httpRedirect | httpTracing | isapiFilters | mo
dules | odbcLogging | serverRuntime | serverSideInclude | staticContent | urlCompression | validation | webSocket }
    Mode = [Int32]{ Allow | Deny | Inherit }
 
```

Example:

```posh

configuration FeatureDelegation
{
    Import-DscResource -ModuleName DOG_IISResources

    node localhost
    {
        cIISFeatureDelegation Handlers
        {
            FeatureName = 'handlers'
            Mode = 'Allow'
        }
    }
}

```

This example will be the equivalent of running `Set-WebConfiguration -Filter '//System.webServer/handlers' -Metadata overrideMode -Value Allow`, and enforcing that configuration over time (if the LCM is configured for ApplyAndAutoCorrect.)
