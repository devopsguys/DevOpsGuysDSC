configuration cTeamCityBuildAgentAndService
{
    param (
        [Parameter(Mandatory)]
        [string] $InstallPath,

        [Parameter(Mandatory)]
        [string] $TeamCityServerUrl,

        [ValidateSet('Present','Absent')]
        [string] $Ensure = 'Present',

        [string] $Name,

        [string] $Address,

        [uint32] $Port = 9090,

        [hashtable] $BuildProperties,

        [ValidateNotNullOrEmpty()]
        [string] $ServiceName = 'TCBuildAgent',

        [ValidateNotNullOrEmpty()]
        [string] $ServiceDisplayName = 'TeamCity Build Agent',

        [ValidateNotNullOrEmpty()]
        [string] $ServiceDescription = 'TeamCity Build Agent Service',

        [ValidateSet('LocalService', 'LocalSystem', 'NetworkService')]
        [string] $ServiceBuiltInAccount,

        [pscredential] $ServiceCredential
    )

    Import-DscResource -ModuleName cPSDesiredStateConfiguration -Name PSHOrg_cServiceResource
    Import-DscResource -ModuleName cNetworking -Name PSHOrg_cFirewall
    Import-DscResource -ModuleName DOG_TeamCityResources -Name DOG_TeamCityBuildAgent, DOG_TeamCityBuildAgentServiceConfigFile

    if (-not $ServiceCredential -and -not $ServiceBuiltInAccount)
    {
        $ServiceBuiltInAccount = 'LocalSystem'
    }

    $guid = [guid]::NewGuid().Guid

    if ($Ensure -eq 'Present')
    {
        cTeamCityBuildAgent "Agent_$guid"
        {
            InstallPath       = $InstallPath
            TeamCityServerUrl = $TeamCityServerUrl
            Ensure            = 'Present'
            Name              = $Name
            Address           = $Address
            Port              = $Port
            BuildProperties   = $BuildProperties
        }

        $binaryPath = Join-Path $InstallPath launcher\bin\TeamCityAgentService-windows-x86-32.exe
        $configPath = Join-Path $InstallPath launcher\conf\wrapper.conf

        cTeamCityBuildAgentServiceConfigFile "AgentServiceConfig_$guid"
        {
            InstallPath = $InstallPath
            Ensure      = 'Present'
            Name        = $ServiceName
            DisplayName = $ServiceDisplayName
            Description = $ServiceDescription
            DependsOn   = "[cTeamCityBuildAgent]Agent_$guid"
        }

        cService "AgentService_$guid"
        {
            Name           = $ServiceName
            BuiltInAccount = $ServiceBuiltInAccount
            Credential     = $ServiceCredential
            DisplayName    = $ServiceDisplayName
            Description    = $ServiceDescription
            Ensure         = 'Present'
            State          = 'Running'
            Path           = "`"$binaryPath`" -s `"$configPath`""
            DependsOn      = @(
                "[cTeamCityBuildAgent]Agent_$guid"
                "[cTeamCityBuildAgentServiceConfigFile]AgentServiceConfig_$guid"
            )
        }

        cFirewall "FirewallRule_$guid"
        {
            Name        = "TeamCityAgent_$ServiceName"
            DisplayName = 'TeamCity Build Agent incoming port'
            Ensure      = 'Present'
            Access      = 'Allow'
            State       = 'Enabled'
            Profile     = 'Any'
            Direction   = 'Inbound'
            Protocol    = 'TCP'
            LocalPort   = "$Port"
        }
    }
    else
    {
        cService "AgentService_$guid"
        {
            Name   = $ServiceName
            Ensure = 'Absent'
        }

        cTeamCityBuildAgent "Agent_$guid"
        {
            InstallPath       = $InstallPath
            TeamCityServerUrl = $TeamCityServerUrl
            Ensure            = 'Absent'
            DependsOn         = "[cService]AgentService_$guid"
        }

        cFirewall "FirewallRule_$guid"
        {
            Name   = "TeamCityAgent_$ServiceName"
            Access = 'Allow'
            Ensure = 'Absent'
        }
    }
}
