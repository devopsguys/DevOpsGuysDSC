# TODO:  Both Role and Environment may be able to accept multiple values when calling Tentacle.exe, so we could make those properties
#        string arrays on the DSC resources as well.  According to the comments posted at
#        http://docs.octopusdeploy.com/display/OD/Automating+Tentacle+installation , the proper syntax for specifying multiple roles
#        is to use the --role parameter multiple times (not comma-separated or anything like that.)  The same may be true for
#        --environment; requires testing.

# TODO:  Is it possible to have tentacle.exe register a Listening tentacle automatically?  If so, we should make it possible for users
#        of this DSC resource to set the ServerName, ServerPort, Environment, Role, and RegistrationCredential properties and have DSC
#        take care of the registration, instead of requiring a manual discovery of the tentacle from the Octopus Deploy web interface
#        later.

# TODO:  Do we need to support a Listening tentacle that trusts multiple Octopus Deploy servers?  ServerThumbprint could be made an array
#        property, and the underlying code updated to support this.

# TODO:  Register-PollingTentacle currently assumes the server's web interface is running on http port 80.  Add options for the user to specify
#        nonstandard ports and/or HTTPS.

. "$PSScriptRoot\..\..\OctopusCommon.ps1"

function Get-TargetResource
{
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [string] $Path
    )

    $configuration = @{
        Path                  = $Path
        Ensure                = 'Absent'
        HomeDirectory         = $null
        DeploymentDirectory   = $null
        Port                  = $null
        CommunicationMode     = $null
        ServerName            = $null
        ServerThumbprint      = $null
        ServerSQUID           = $null
        ServerPort            = $null
        SQUID                 = $null
        CertificateThumbprint = $null
    }

    if (Test-Path -LiteralPath $Path -PathType Leaf)
    {
        $configFile = Import-TentacleConfigFile -Path $Path

        $configuration['Ensure']                = 'Present'
        $configuration['HomeDirectory']         = $configFile.HomeDirectory
        $configuration['DeploymentDirectory']   = $configFile.DeploymentDirectory
        $configuration['Port']                  = $configFile.PortNumber
        $configuration['CertificateThumbprint'] = $configFile.CertificateThumbprint
        $configuration['SQUID']                 = $configFile.SQUID

        # Should the DSC resource support multiple trusted servers?  For now, we're assuming one, which is a little bit ugly.
        $server = $configFile.TrustedServers | Select-Object -First 1

        if ($server)
        {
            $configuration['CommunicationMode'] = if ($server.CommunicationStyle -eq 'TentaclePassive') { 'Listen' } else { 'Poll' }
            $configuration['ServerSQUID']       = $server.Squid
            $configuration['ServerThumbprint']  = $server.Thumbprint

            if (($uri = $server.Address -as [uri]))
            {
                $configuration['ServerName'] = $uri.Host
                $configuration['ServerPort'] = $uri.Port
            }
        }
    }

    return $configuration
}

function Set-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateSet('Present','Absent')]
        [string] $Ensure = 'Present',

        [string] $ServerName,

        [string] $ServerThumbprint,

        [ValidateNotNullOrEmpty()]
        [string] $HomeDirectory = 'C:\Octopus',

        [ValidateNotNullOrEmpty()]
        [string] $DeploymentDirectory = 'C:\Octopus\Applications',

        [uint16] $Port = 10933,

        [ValidateSet('Listen', 'Poll')]
        [string] $CommunicationMode = 'Listen',

        [pscredential] $RegistrationCredential,

        [string] $Role,

        [string] $Environment,

        [uint16] $ServerPort = 10943
    )

    Assert-ValidParameterCombinations @PSBoundParameters

    $tentacleExe = Get-TentacleExecutablePath
    $fileExists = Test-Path -LiteralPath $Path -PathType Leaf
    $instance = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $serviceName = Get-TentacleServiceName -TentacleName $instance

    switch ($Ensure)
    {
        'Present'
        {
            $doRestartService = $false
            $service = Get-Service -Name $serviceName -ErrorAction Ignore

            if ($null -ne $service -and $service.CanStop)
            {
                Write-Verbose "Stopping tentacle service '$serviceName' before modifying the config file."

                try
                {
                    Stop-Service -InputObject $service -ErrorAction Stop
                    $doRestartService = $true
                }
                catch
                {
                    Write-Error -ErrorRecord $_
                    return
                }
            }

            if (-not $fileExists)
            {
                New-TentacleInstance -TentacleExePath $tentacleExe -InstanceName $instance -Path $Path
            }

            $configFile = Import-TentacleConfigFile -Path $Path

            # Should the DSC resource support multiple trusted servers?  For now, we're assuming one, which is a little bit ugly.
            $server = $configFile.TrustedServers | Select-Object -First 1
            $mode = if ($server.CommunicationStyle -eq 'TentaclePassive') { 'Listen' } else { 'Poll' }

            if ([string]::IsNullOrEmpty($configFile.SQUID))
            {
                New-TentacleSquid -TentacleExePath $tentacleExe -InstanceName $instance
            }

            if ([string]::IsNullOrEmpty($configFile.Certificate))
            {
                New-TentacleCertificate -TentacleExePath $tentacleExe -InstanceName $instance
            }

            if ($configFile.HomeDirectory -ne $HomeDirectory)
            {
                Set-TentacleHomeDirectory -TentacleExePath $tentacleExe -InstanceName $instance -HomeDirectory $HomeDirectory
            }

            if ($configFile.DeploymentDirectory -ne $DeploymentDirectory)
            {
                Set-TentacleDeploymentDirectory -TentacleExePath $tentacleExe -InstanceName $instance -DeploymentDirectory $DeploymentDirectory
            }

            if ($configFile.PortNumber -ne $Port)
            {
                Set-TentaclePort -TentacleExePath $tentacleExe -InstanceName $instance -Port $Port
            }

            switch ($CommunicationMode)
            {
                'Listen'
                {
                    if ($server.Thumbprint -ne $ServerThumbprint -or
                        $server.CommunicationStyle -ne 'TentaclePassive')
                    {
                        Set-TentacleListener -TentacleExePath $tentacleExe -InstanceName $instance -ServerThumbprint $ServerThumbprint
                    }
                }

                'Poll'
                {
                    $uri = $server.Address -as [uri]

                    if ($uri.Host -ne $ServerName -or
                        $uri.Port -ne $ServerPort -or
                        $server.CommunicationStyle -ne 'TentacleActive')
                    {
                        Register-PollingTentacle -TentacleExePath $tentacleExe `
                                                 -InstanceName    $instance `
                                                 -ServerName      $ServerName `
                                                 -Environment     $Environment `
                                                 -Credential      $RegistrationCredential `
                                                 -ServerPort      $ServerPort `
                                                 -Role            $Role
                    }
                }
            }

            if ($doRestartService)
            {
                Write-Verbose "Config file modifications complete.  Restarting tentacle service '$serviceName'."
                Start-Service -InputObject $service
            }
        }

        'Absent'
        {
            if ($fileExists)
            {
                Write-Verbose "Configuration file '$Path' exists and Ensure is set to Absent.  Deleting file."
                Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            }
        }
    }

}

function Test-TargetResource
{
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateSet('Present','Absent')]
        [string] $Ensure = 'Present',

        [string] $ServerName,

        [string] $ServerThumbprint,

        [ValidateNotNullOrEmpty()]
        [string] $HomeDirectory = 'C:\Octopus',

        [ValidateNotNullOrEmpty()]
        [string] $DeploymentDirectory = 'C:\Octopus\Applications',

        [uint16] $Port = 10933,

        [ValidateSet('Listen', 'Poll')]
        [string] $CommunicationMode = 'Listen',

        [pscredential] $RegistrationCredential,

        [string] $Role,

        [string] $Environment,

        [uint16] $ServerPort = 10943
    )

    Assert-ValidParameterCombinations @PSBoundParameters

    $fileExists = Test-Path -LiteralPath $Path -PathType Leaf

    switch ($Ensure)
    {
        'Present'
        {
            if (-not $fileExists) { return $false }

            $configFile = Import-TentacleConfigFile -Path $Path

            # Should the DSC resource support multiple trusted servers?  For now, we're assuming one, which is a little bit ugly.
            $server = $configFile.TrustedServers | Select-Object -First 1
            $mode = if ($server.CommunicationStyle -eq 'TentaclePassive') { 'Listen' } else { 'Poll' }

            if ($configFile.HomeDirectory       -ne $HomeDirectory -or
                $configFile.DeploymentDirectory -ne $DeploymentDirectory -or
                $configFile.PortNumber          -ne $Port -or
                $mode                           -ne $CommunicationMode -or
                [string]::IsNullOrEmpty($configFile.CertificateThumbprint) -or
                [string]::IsNullOrEmpty($configFile.SQUID))
            {
                return $false
            }

            if ($CommunicationMode -eq 'Listen')
            {
                if ($server.Thumbprint -ne $ServerThumbprint)
                {
                    return $false
                }
            }
            else
            {
                $uri = $server.Address -as [uri]
                if ($uri.Host -ne $ServerName -or $uri.Port -ne $ServerPort)
                {
                    return $false
                }
            }

            return $true
        }

        'Absent'
        {
            return -not $fileExists
        }
    }
}

function Assert-ValidParameterCombinations
{
    param (
        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateSet('Present','Absent')]
        [string] $Ensure = 'Present',

        [string] $ServerName,

        [string] $ServerThumbprint,

        [ValidateNotNullOrEmpty()]
        [string] $HomeDirectory = 'C:\Octopus',

        [ValidateNotNullOrEmpty()]
        [string] $DeploymentDirectory = 'C:\Octopus\Applications',

        [uint16] $Port = 10933,

        [ValidateSet('Listen', 'Poll')]
        [string] $CommunicationMode = 'Listen',

        [pscredential] $RegistrationCredential,

        [string] $Role,

        [string] $Environment,

        [uint16] $ServerPort = 10943
    )

    if ($CommunicationMode -eq 'Poll')
    {
        if ([string]::IsNullOrEmpty($Role) -or
            [string]::IsNullOrEmpty($Environment) -or
            [string]::IsNullOrEmpty($ServerName) -or
            $null -eq $RegistrationCredential)
        {
            throw 'The ServerName, Role, Environment, and RegistrationCredential parameters are required when CommunicationMode is set to Poll.'
        }
    }
    else
    {
        if ([string]::IsNullOrEmpty($ServerThumbprint))
        {
            throw 'The ServerThumbprint parameter is required when CommunicationMode is set to Listen.'
        }
    }
}

function Import-TentacleConfigFile
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Path
    )

    Write-Verbose "Importing tentacle configuration file from '$Path'"

    if (-not (Test-Path -LiteralPath $Path))
    {
        throw "Path '$Path' does not exist."
    }

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file -isnot [System.IO.FileInfo])
    {
        throw "Path '$Path' does not refer to a file."
    }

    $xml = New-Object xml
    try
    {
        $xml.Load($file.FullName)
    }
    catch
    {
        throw
    }

    try {
        # The extra set of parentheses here looks weird, but is necessary to work around a weird bug with ConvertFrom-Json and the array subexpression operator.
        # For some reason, this results in a nested array by default, which isn't supposed to happen.  The extra set of parens changes how PowerShell evaluates
        # the expression, and causes the array subexpression to work the way it's supposed to; a new array is only created if the result of the inner expression
        # is not already an array.

        $trustedServers = @((ConvertFrom-Json $xml.SelectSingleNode('/octopus-settings/set[@key="Tentacle.Communication.TrustedOctopusServers"]/text()').Value))
    } catch {
        $trustedServers = @()
    }

    return [pscustomobject] @{
        SQUID                 = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Communications.Squid"]/text()').Value
        HomeDirectory         = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Home"]/text()').Value
        MasterKey             = $xml.SelectSingleNode('/octopus-settings/set[@key="Octopus.Storage.MasterKey"]/text()').Value
        Certificate           = $xml.SelectSingleNode('/octopus-settings/set[@key="Tentacle.Certificate"]/text()').Value
        CertificateThumbprint = $xml.SelectSingleNode('/octopus-settings/set[@key="Tentacle.CertificateThumbprint"]/text()').Value
        DeploymentDirectory   = $xml.SelectSingleNode('/octopus-settings/set[@key="Tentacle.Deployment.ApplicationDirectory"]/text()').Value
        PortNumber            = $xml.SelectSingleNode('/octopus-settings/set[@key="Tentacle.Services.PortNumber"]/text()').Value -as [int]
        TrustedServers        = $trustedServers
    }
}

function Get-TentacleExecutablePath
{
    if (Test-Path -LiteralPath HKLM:\Software\Octopus\Tentacle)
    {
        $installLocation = (Get-ItemProperty -Path HKLM:\Software\Octopus\Tentacle).InstallLocation
        if ($installLocation -and (Test-Path -LiteralPath $installLocation -PathType Container))
        {
            $exePath = Join-Path $installLocation Tentacle.exe
            if (Test-Path -LiteralPath $exePath -PathType Leaf)
            {
                Write-Verbose "Identified path to Tentacle.exe: '$exePath'"
                return $exePath
            }
        }
    }

    throw 'Could not determine path to Tentacle.exe based on contents of registry key HKLM:\Software\Octopus\Tentacle'
}

function New-TentacleInstance
{
    param ($TentacleExePath, $InstanceName, $Path)

    Write-Verbose "Creating new tentacle configuration file '$Path', instance '$InstanceName'"

    & $TentacleExePath --console create-instance --instance $InstanceName --config $Path

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when creating a new instance"
    }
}

function New-TentacleSquid
{
    param ($TentacleExePath, $InstanceName)

    Write-Verbose "Generating new SQUID for tentacle instalce '$InstanceName'"

    & $TentacleExePath --console new-squid --instance $InstanceName

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when creating a new client SQUID"
    }
}

function New-TentacleCertificate
{
    param ($TentacleExePath, $InstanceName)

    Write-Verbose "Generating new client certificate for tentacle instalce '$InstanceName'"

    & $TentacleExePath --console new-certificate --instance $InstanceName

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when creating a new client certificate"
    }
}

function Set-TentacleHomeDirectory
{
    param ($TentacleExePath, $InstanceName, $HomeDirectory)

    Write-Verbose "Setting tentacle instance '$InstanceName' home directory to '$HomeDirectory'"

    & $TentacleExePath --console configure --instance $InstanceName --home $HomeDirectory

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when configuring the tentacle Home Directory"
    }
}

function Set-TentacleDeploymentDirectory
{
    param ($TentacleExePath, $InstanceName, $DeploymentDirectory)

    Write-Verbose "Setting tentacle instance '$InstanceName' deployment directory to '$DeploymentDirectory'"

    & $TentacleExePath --console configure --instance $InstanceName --app $DeploymentDirectory

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when configuring the tentacle Deployment Directory"
    }
}

function Set-TentaclePort
{
    param ($TentacleExePath, $InstanceName, $Port)

    Write-Verbose "Setting tentacle instance '$InstanceName' client port to $Port"

    & $TentacleExePath --console configure --instance $InstanceName --port $Port

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when configuring the tentacle client port"
    }
}

function Set-TentacleListener
{
    param ($TentacleExePath, $InstanceName, $ServerThumbprint)

    Write-Verbose "Configuring listening tentacle, instance '$InstanceName', to trust Octopus Deploy server with thumbprint '$ServerThumbprint'"

    & $TentacleExePath --console configure --instance $InstanceName --reset-trust
    & $TentacleExePath --console configure --instance $InstanceName --trust $ServerThumbprint

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when configuring the tentacle trusted server."
    }
}

function Register-PollingTentacle
{
    param ($TentacleExePath, $InstanceName, $ServerName, $Environment, $Credential, $ServerPort, $Role)

    Write-Verbose "Registering polling tentacle, instance '$InstanceName', with Octopus Deploy server ${ServerName}:${ServerPort}."

    $obj = [pscustomobject] @{
        Environment = $Environment
        Role        = $Role
        Username    = $Credential.UserName
    }

    Write-Debug "Registration settings: `r`n$($obj | Format-List | Out-String)"

    $ptr = $null
    try
    {
        $user = $Credential.UserName
        $ptr  = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($Credential.Password)
        $pass = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
    }
    catch
    {
        throw
    }
    finally
    {
        if ($null -ne $ptr) { [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr); $ptr = $null }
    }

    & $TentacleExePath --console configure --instance $InstanceName --reset-trust
    & $TentacleExePath --console register-with --instance $InstanceName --server "http://$ServerName" --environment $Environment --name $env:COMPUTERNAME --username $user --password $pass --comms-style TentacleActive --server-comms-port $ServerPort --force --role $Role

    if ($LASTEXITCODE -ne 0)
    {
        throw "Tentacle returned error code $LASTEXITCODE when registering with the server."
    }
}

Export-ModuleMember -Function Get-TargetResource,
                              Test-TargetResource,
                              Set-TargetResource

