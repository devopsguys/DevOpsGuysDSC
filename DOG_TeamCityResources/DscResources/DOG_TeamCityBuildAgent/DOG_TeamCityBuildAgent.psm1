. "$PSScriptRoot\..\..\TeamCityCommon.ps1"

function Get-TargetResource
{
    [OutputType([Hashtable])]
    param (
        [Parameter(Mandatory)]
        [string] $InstallPath,

        [Parameter(Mandatory)]
        [string] $TeamCityServerUrl
    )

    $Configuration = @{
        InstallPath = $InstallPath
        Ensure      = 'Absent'
    }

    $buildAgentCache = Join-Path (GetCacheDirectory).FullName buildAgent
    UpdateCache -CachePath $buildAgentCache -ServerBaseUri $TeamCityServerUrl

    if (AgentDirectoryContainsAllRequiredFiles -AgentDirectory $InstallPath -SourceDirectory $buildAgentCache)
    {
        $Configuration['Ensure'] = 'Present'
    }

    $propertiesPath = Join-Path $InstallPath conf\buildAgent.properties
    $propertiesFile = ImportPropertiesFile -Path $propertiesPath

    $Configuration['TeamCityServerUrl'] = GetPropertiesFileItem -PropertiesFile $propertiesFile -Key serverUrl
    $Configuration['Address']           = GetPropertiesFileItem -PropertiesFile $propertiesFile -Key ownAddress
    $Configuration['Port']              = GetPropertiesFileItem -PropertiesFile $propertiesFile -Key ownPort
    $Configuration['Name']              = GetPropertiesFileItem -PropertiesFile $propertiesFile -Key name
    $Configuration['TempDirectory']     = GetPropertiesFileItem -PropertiesFile $propertiesFile -Key tempDir
    $Configuration['WorkDirectory']     = GetPropertiesFileItem -PropertiesFile $propertiesFile -Key workDir
    $Configuration['SystemDirectory']   = GetPropertiesFileItem -PropertiesFile $propertiesFile -Key systemDir
    $Configuration['BuildProperties']   = GetBuildProperties -PropertiesFile $propertiesFile

    return $Configuration
}

function Set-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [string] $InstallPath,

        [Parameter(Mandatory)]
        [string] $TeamCityServerUrl,

        [ValidateSet('Present','Absent')]
        [string] $Ensure = 'Present',

        [string] $Name,

        [string] $WorkDirectory = '../work',

        [string] $TempDirectory = '../temp',

        [string] $SystemDirectory = '../system',

        [string] $Address,

        [uint32] $Port = 9090,

        [ciminstance[]] $BuildProperties
    )

    $serverUri = $TeamCityServerUrl -as [uri]
    if ($null -eq $serverUri)
    {
        throw "TeamCityServerUrl '$TeamCityServerUrl' is not a valid URL."
    }

    $cacheDirectory = GetCacheDirectory
    $buildAgentCache = Join-Path $cacheDirectory.FullName buildAgent
    UpdateCache -CachePath $buildAgentCache -ServerBaseUri $TeamCityServerUrl

    $properties = Get-HashtableFromKeyValuePairArray $BuildProperties

    switch ($Ensure)
    {
        'Present'
        {
            $agentFilesArePresent = AgentDirectoryContainsAllRequiredFiles -AgentDirectory $InstallPath -SourceDirectory $buildAgentCache

            if (-not $agentFilesArePresent)
            {
                CopyAgentBinaries -AgentDirectory $InstallPath -SourceDirectory $buildAgentCache
            }

            $propertiesPath = Join-Path $InstallPath conf\buildAgent.properties

            if (-not (Test-Path $propertiesPath))
            {
                Write-Verbose 'buildAgent.properties file does not exist for this agent.  Creating the default file first.'
                Set-Content -Encoding Ascii -LiteralPath $propertiesPath -Value (Get-DefaultBuildAgentProperties)
            }

            $propertiesFile = ImportPropertiesFile -Path $propertiesPath

            SetPropertiesFileItem -PropertiesFile $propertiesFile -Key serverUrl -Value $TeamCityServerUrl
            SetPropertiesFileItem -PropertiesFile $propertiesFile -Key ownPort   -Value $Port
            SetPropertiesFileItem -PropertiesFile $propertiesFile -Key name      -Value $Name
            SetPropertiesFileItem -PropertiesFile $propertiesFile -Key workDir   -Value $WorkDirectory
            SetPropertiesFileItem -PropertiesFile $propertiesFile -Key tempDir   -Value $TempDirectory
            SetPropertiesFileItem -PropertiesFile $propertiesFile -Key systemDir -Value $SystemDirectory

            if ($Address)
            {
                SetPropertiesFileItem -PropertiesFile $propertiesFile -Key ownAddress -Value $Address
            }
            else
            {
                CommentOutPropertiesFileItem -PropertiesFile $propertiesFile -Key ownAddress
            }

            foreach ($dictionaryEntry in $properties.GetEnumerator())
            {
                SetPropertiesFileItem -PropertiesFile $propertiesFile -Key $dictionaryEntry.Key -Value $dictionaryEntry.Value
            }

            if ($propertiesFile.Dirty)
            {
                Write-Verbose 'Changes were made to the properties file.  Saving the new version.'
                Set-Content -Encoding Ascii -LiteralPath $propertiesPath -Value $propertiesFile.Lines
            }
        }

        'Absent'
        {
            if (Test-Path -LiteralPath $InstallPath -PathType Container)
            {
                Remove-Item -LiteralPath $InstallPath -Recurse -Force -ErrorAction Stop
            }
        }
    }
}

function Test-TargetResource
{
    [OutputType([boolean])]
    param (
        [Parameter(Mandatory)]
        [string] $InstallPath,

        [Parameter(Mandatory)]
        [string] $TeamCityServerUrl,

        [ValidateSet('Present','Absent')]
        [string] $Ensure = 'Present',

        [string] $Name,

        [string] $WorkDirectory = '../work',

        [string] $TempDirectory = '../temp',

        [string] $SystemDirectory = '../system',

        [string] $Address,

        [uint32] $Port = 9090,

        [ciminstance[]] $BuildProperties
    )

    $cacheDirectory = GetCacheDirectory
    $buildAgentCache = Join-Path $cacheDirectory.FullName buildAgent
    UpdateCache -CachePath $buildAgentCache -ServerBaseUri $TeamCityServerUrl

    $customBuildProperties = Get-HashtableFromKeyValuePairArray $BuildProperties

    $serverUri = $TeamCityServerUrl -as [uri]
    if ($null -eq $serverUri)
    {
        throw "TeamCityServerUrl '$TeamCityServerUrl' is not a valid URL."
    }

    switch ($Ensure)
    {
        'Present'
        {
            if (-not (BuildAgentCacheIsUpToDate -CachePath $buildAgentCache -ServerBaseUri $serverUri))
            {
                UpdateCache -CachePath $buildAgentCache -ServerBaseUri $serverUri
            }

            if (-not (AgentDirectoryContainsAllRequiredFiles -AgentDirectory $InstallPath -SourceDirectory $buildAgentCache))
            {
                return $false
            }

            $propertiesPath = Join-Path $InstallPath conf\buildAgent.properties

            if (-not (Test-Path $propertiesPath))
            {
                return $false
            }

            $propertiesFile = ImportPropertiesFile -Path $propertiesPath

            $propertiesToCheck = @{
                serverUrl  = $TeamCityServerUrl
                ownAddress = if ($Address) { $Address } else { $null }
                ownPort    = $Port
                name       = $Name
                tempDir    = $TempDirectory
                workDir    = $WorkDirectory
                systemDir  = $SystemDirectory
            }

            foreach ($dictionaryEntry in $customBuildProperties.GetEnumerator())
            {
                if ($propertiesToCheck.ContainsKey($dictionaryEntry.Key))
                {
                    throw "BuildProperties table may not contain key name '$($dictionaryEntry.Key)'"
                }

                $propertiesToCheck.Add($dictionaryEntry.Key, $dictionaryEntry.Value)
            }

            foreach ($dictionaryEntry in $propertiesToCheck.GetEnumerator())
            {
                if ($dictionaryEntry.Value -ne (GetPropertiesFileItem -PropertiesFile $propertiesFile -Key $dictionaryEntry.Key))
                {
                    Write-Verbose "The buildAgent.properties file does not contain expected value '$($dictionaryEntry.Value)' for key '$($dictionaryEntry.Key)'."
                    return $false
                }
            }

            return $true
        }

        'Absent'
        {
            $pathExists = Test-Path -LiteralPath $InstallPath -PathType Container
            return -not $pathExists
        }
    }
}

Export-ModuleMember -Function Get-TargetResource,
                              Test-TargetResource,
                              Set-TargetResource

