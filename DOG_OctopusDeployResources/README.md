# DOG_TeamCityResources
This module contains the following DSC resources for installing and configuring an Octopus Deploy Tentacle:

## cOctopusDeployTentacleConfigFile

This resource handles the settings in the XML configuration file for the Tentacle.

Syntax:
```
cOctopusDeployTentacleConfigFile [String] #ResourceName
{
    Path                    = [string]
    [CommunicationMode      = [string]{ Listen | Poll }]
    [DeploymentDirectory    = [string]]
    [Ensure                 = [string]{ Absent | Present }]
    [Environment            = [string]]
    [HomeDirectory          = [string]]
    [Port                   = [UInt16]]
    [RegistrationCredential = [PSCredential]]
    [Role                   = [string]]
    [ServerName             = [string]]
    [ServerPort             = [UInt16]]
    [ServerThumbprint       = [string]]
}
```

Octopus Deploy Tentacles may be set up as either Listening or Polling tentacles (analogous to Push and Pull mode in the DSC Local Configuration Manager.)  Each type of Tentacle uses a different set of parameters, so we'll separate the lists here.

_Note: If anything needs to be changed in the config file (Test-TargetResource returns $false), and if the associated Windows service for this tentacle config file exists and is running, it will be stopped while Set-TargetResource executes, then started up again when Set-TargetResource completes.  This is necessary for the config file changes to take effect (and to not be overwritten by the Tentacle when the service stops.)_

### Parameters common to both Listening and Polling tentacles:
- **Path**: The path to the .config file that will be managed by this resource.
- **CommunicationMode**: Set to either Listen or Poll.  Listen is the default mode.
- **Ensure**: Set to Present or Absent, like most other DSC resources.  Present is the default.
- **HomeDirectory**: The Octopus Deploy home directory.  Defaults to C:\Octopus.
- **DeploiymentDirectory**: The directory where the tentacle will unpack nuget packages.  Defaults to C:\Octopus\Applications.

### Parameters for Listening Tentacles:
- **Port**: The TCP port that the tentacle will use to receive communication from the Octopus server.  Defaults to 10933.
- **ServerThumbprint**: The certificate thumbprint of the Octopus Deploy server.  This is used to authenticate and trust incoming connections, and may be found in the server's web interface.

_Note: Listening tentacles do not automatically register with the server when you install them with DSC, which is why no credentials are required when using the resource in that mode.  You also don't need to specify an Environment or Role, since those will be set manually when the tentacle is registered._

### Parameters for Polling Tentacles:
- **ServerName**: The host name of the Octopus Deploy server.
- **ServerPort**: The port that the Octopus Deploy server is listening on for agent-initiated communication.  Defaults to 10943.
- **RegistrationCredential**: The username and password that should be used when registering the Tentacle with the server.
- **Role**: The role that should be assigned to this machine in Octopus Deploy.
- **Environment**: The environment where this machine should be placed in Octopus Deploy.

_Note: Polling tentacles are registered with the Octopus Deploy server when this DSC resource's Set function executes, so you must define all of these settings in order for the machine to be registered and placed properly in Octopus Deploy._

## cOctopusDeployTentacle

A composite resource which provides the most convenient way to install a Tentacle and run it as a Windows service.  This composes the following resources for you:

- **Package**: To install the Tentacle msi package.
- **cOctopusDeployTentacleConfigFile**: To configure the tentacle, and in the case of a Polling tentacle, to register it with the server.
- **cService**: To create the Windows service for the tentacle, if necessary, and ensure that it's running.
- **cFirewall**: To open a Windows Firewall rule for incoming connections to a Listening tentacle's TCP port.

_Note:  Using this composite resource requires the cPSDesiredStateConfiguration and cNetworking modules from PowerShell.org:  https://github.com/PowerShellOrg/cPSDesiredStateConfiguration , https://github.com/PowerShellOrg/cNetworking_

Syntax:
```
cOctopusDeployTentacle [String] #ResourceName
{
    TentacleName            = [String]
    [Ensure                 = [String]]
    [HomeDirectory          = [String]]
    [DeploymentDirectory    = [String]]
    [Port                   = [UInt16]]
    [CommunicationMode      = [string]{ Listen | Poll }]
    [ServerName             = [String]]
    [ServerThumbprint       = [String]]
    [ServerPort             = [UInt16]]
    [TentacleInstallerUrl   = [String]]
    [InstallPath            = [String]]
    [Environment            = [String]]
    [Role                   = [String]]
    [RegistrationCredential = [PSCredential]]
    [ServiceBuiltInAccount  = [String]{ LocalSystem | LocalService | NetworkService }]
    [ServiceCredential      = [PSCredential]]
}
```

- **TentacleName**: The name of the Octopus Deploy tentacle.  This name is used when creating both the config file and the Windows service (which must both be named correctly, or the tentacle will fail to restart itself during updates.)
- **HomeDirectory**: The value passed to the HomeDirectory property of cOctopusDeployTentacleConfigFile.  Also used to generate the path to the config file itself, which is "$HomeDirectory\Tentacle\$TentacleName.config"
- **DeploymentDirectory**: The value passed to the DeploymentDirectory property of cOctopusDeployTentacleConfigFile.
- **Ensure**: The standard Present | Absent property for DSC resources.  Present by default.
- **Port**: The value passed to the Port property of cOctopusDeployTentacleConfigFile.  Also used in setting up the cFirewall rule.
- **CommunicationMode**: The value passed to the CommunicationMode property of cOctopusDeployTentacleConfigFile.
- **ServerName**: The value passed to the ServerName property of cOctopusDeployTentacleConfigFile.
- **ServerPort**: The value passed to the ServerPort property of cOctopusDeployTentacleConfigFile.
- **ServerThumbprint**: The value passed to the ServerThumbprint property of cOctopusDeployTentacleConfigFile.
- **Environment**: The value passed to the Environment property of cOctopusDeployTentacleConfigFile.
- **Role**: The value passed to the Role property of cOctopusDeployTentacleConfigFile.
- **RegistrationCredential**: The value passed to the RegistrationCredential property of cOctopusDeployTentacleConfigFile.
- **TentacleInstallerUrl**: The url to download the MSI file used to install the Tentacle.  Defaults to https://download.octopusdeploy.com/octopus/Octopus.Tentacle.2.6.0.778-x64.msi .  _Note: The tentacle will automatically update itself from the Octopus Deploy server anyway, so it's usually fine to leave this at the default value._
- **ServiceBuiltInAccount**: The value passed to the BuiltInAccount property of cService.
- **ServiceCredential**: The value passed to the Credential property of cService.

_Note:  If neither ServiceBuiltInAccount or ServiceCredential are specified, the service will run as LocalSystem by default._

## Examples

```posh
configuration ListeningTentacle
{
    Import-DscResource -ModuleName DOG_OctopusDeployResources

    node localhost
    {
        cOctopusDeployTentacle Tentacle
        {
            TentacleName     = 'Tentacle'
            ServerThumbprint = '73FF4CC16433C9557BFFDC637827C936D2A7D98E'
        }
    }
}
```

This sets up a Listening tentacle named "Tentacle" with the default values for Home and Deployment directories (C:\Octopus and C:\Octopus\Applications, respectively.)  It listens on the default port of 10933, and the service runs as LocalSystem.  The only trusted Octopus server is one with certificate thumbprint 73FF4CC16433C9557BFFDC637827C936D2A7D98E

```posh
configuration PollingTentacle
{
    Import-DscResource -ModuleName DOG_OctopusDeployResources

    node localhost
    {
        cOctopusDeployTentacle Tentacle
        {
            TentacleName           = 'Tentacle'
            CommunicationMode      = 'Poll'
            ServerName             = 'OctopusDeploy.local'
            Role                   = 'web-server'
            Environment            = 'Production'
            RegistrationCredential = $aValidPSCredentialObject
            ServiceCredential      = $anotherValidPSCredentialObject
        }
    }
}
```

This example sets up a Polling tentacle, which is registered with Octopus server OctopusDeploy.local on the default port of 10943.  The machine is registered into the Production environment, with an assigned role of 'web-server'.  Instead of running as LocalSystem, the Tentacle service will run with whatever credentials are specified in the $anotherValidPSCredentialObject variable.
