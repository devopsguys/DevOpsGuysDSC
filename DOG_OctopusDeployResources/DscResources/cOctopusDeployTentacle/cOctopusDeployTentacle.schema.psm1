. "$PSScriptRoot\..\..\OctopusCommon.ps1"

configuration cOctopusDeployTentacle
{
    param (
        [Parameter(Mandatory)]
        [string] $TentacleName,

        [ValidateSet('Present', 'Absent')]
        [string] $Ensure = 'Present',

        [string] $HomeDirectory = 'C:\Octopus',
        [string] $DeploymentDirectory = 'C:\Octopus\Applications',
        [uint16] $Port = 10933,

        [ValidateSet('Listen', 'Poll')]
        [string] $CommunicationMode = 'Listen',

        [string] $ServerName,
        [string] $ServerThumbprint,
        [uint16] $ServerPort = 10943,

        [string] $TentacleInstallerUrl = 'https://download.octopusdeploy.com/octopus/Octopus.Tentacle.2.6.0.778-x64.msi',

        [string] $InstallPath = 'C:\Program Files\Octopus Deploy\Tentacle',

        [string] $Environment,
        [string] $Role,

        [pscredential] $RegistrationCredential,

        [ValidateSet('', 'LocalService', 'LocalSystem', 'NetworkService')]
        [string] $ServiceBuiltInAccount,

        [pscredential] $ServiceCredential
    )

    Import-DscResource -ModuleName DOG_OctopusDeployResources -Name DOG_OctopusDeployTentacleConfigFile
    Import-DscResource -ModuleName cPSDesiredStateConfiguration -Name PSHOrg_cServiceResource
    Import-DscResource -ModuleName cNetworking -Name PSHOrg_cFirewall

    if (-not $ServiceCredential -and -not $ServiceBuiltInAccount)
    {
        $ServiceBuiltInAccount = 'LocalSystem'
    }

    $guid = [guid]::NewGuid().Guid

    if ($Ensure -eq 'Present')
    {
        Package "tentacleMsi_$guid"
        {
            Ensure    = 'Present'
            Path      = $TentacleInstallerUrl
            Name      = 'Octopus Deploy Tentacle'
            ProductId = ''
            Arguments = "INSTALLLOCATION=`"$InstallPath`""
        }

        cOctopusDeployTentacleConfigFile "tentacleConfig_$guid"
        {
            Path                   = Join-Path $HomeDirectory "Tentacle\$TentacleName.config"
            Ensure                 = 'Present'
            HomeDirectory          = $HomeDirectory
            DeploymentDirectory    = $DeploymentDirectory
            Port                   = $Port
            CommunicationMode      = $CommunicationMode
            ServerName             = $ServerName
            ServerThumbprint       = $ServerThumbprint
            ServerPort             = $ServerPort
            Environment            = $Environment
            Role                   = $Role
            RegistrationCredential = $RegistrationCredential
            DependsOn              = "[Package]tentacleMsi_$guid"
        }

        cFirewall "tentacleFirewall_$guid"
        {
            Name        = "OctopusDeployTentacle_$TentacleName"
            DisplayName = 'Octopus Deploy Tentacle incoming port'
            Ensure      = 'Present'
            Access      = 'Allow'
            State       = 'Enabled'
            Profile     = 'Any'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = "$Port"
        }

        $svcName = Get-TentacleServiceName -TentacleName $TentacleName

        cService "tentacleService_$guid"
        {
            Ensure         = 'Present'
            Name           = $svcName
            DisplayName    = $svcName
            Path           = "`"$InstallPath\Tentacle.exe`" run --instance `"$TentacleName`""
            StartupType    = 'Automatic'
            State          = 'Running'
            Dependencies   = @('LanmanWorkstation', 'TCPIP')
            DependsOn      = "[cOctopusDeployTentacleConfigFile]tentacleConfig_$guid"
            BuiltInAccount = $ServiceBuiltInAccount
            Credential     = $ServiceCredential
            Description    = 'Octopus Deploy: Tentacle deployment agent'
        }
    }
    else
    {
        cService "tentacleService_$guid"
        {
            Ensure         = 'Absent'
            Name           = "OctopusDeploy Tentacle: $TentacleName"
        }

        Package "tentacleMsi_$guid"
        {
            Ensure    = 'Absent'
            Path      = $TentacleInstallerUrl
            Name      = 'Octopus Deploy Tentacle'
            ProductId = ''
            DependsOn = "[cService]tentacleService_$guid"
        }

        File "tentacleFolder_$guid"
        {
            Ensure          = 'Absent'
            DestinationPath = $HomeDirectory
            Recurse         = $true
            DependsOn       = "[Package]tentacleMsi_$guid"
        }

        cFirewall "tentacleFirewall_$guid"
        {
            Name   = "OctopusDeployTentacle_$Port"
            Ensure = 'Absent'
            Access = 'Allow'
        }
    }
}
