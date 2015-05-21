# DOG_JavaResources

This module contains a single DSC resource, cOracleJRE.  This is based on the code in xPackage, but has been tweaked to handle Oracle's JRE successfully, considering that the JRE changes both its ProductID guid and its Name with every new patch.  This allows you to install the JRE and leave its auto-updater enabled, without confusing DSC.  (Another option would be to install the JRE using the normal Package resources, and passing in the "STATIC=1" argument to enable side-by-side version installations without the auto updater.  In that scenario, the cOracleJRE resource is not required.)

Syntax:

```
cOracleJRE [String] #ResourceName
{
    Path = [string]
    Version = [string]
    [Arguments = [string]]
    [Credential = [PSCredential]]
    [Ensure = [string]{ Absent | Present }]
    [LogPath = [string]]
    [ReturnCode = [Int32[]]]
    [RunAsCredential = [PSCredential]]
}
```

Most of the parameters in this resource are identical to xPackage.  The only unique parameter here is Version, which is the minimum version of the JRE that should be installed.  If a system does not have the JRE at all, or if the system has an older version installed, then the resource will execute its Set method.

_Note:  The Version number comes from the DisplayVersion registry value found under the JRE's Uninstall key.  For example, Java 8 Update 45 would have version number "8.0.450"._

Example:

```posh
configuration InstallJRE
{
    Import-DscResource -ModuleName DOG_JavaResources

    node localhost
    {
        cOracleJRE 8u45
        {
            Path    = 'C:\Installers\jre-8u45-windows-i586.exe'
            Version = '8.0.450'
            Ensure  = 'Present'
        }
}
```
