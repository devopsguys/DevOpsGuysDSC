. "$PSScriptRoot\..\..\TeamCityCommon.ps1"

function Get-TargetResource
{
    [OutputType([Hashtable])]
    param (
        [Parameter(Mandatory)]
        [string] $InstallPath
    )

    $Configuration = @{
        InstallPath = $InstallPath
        Ensure      = 'Absent'
    }

    $propertiesPath = Join-Path $InstallPath launcher\conf\wrapper.conf

    if (Test-Path -LiteralPath $propertiesPath -PathType Leaf)
    {
        $Configuration['Ensure'] = 'Present'
    }

    $propertiesFile = ImportPropertiesFile -Path $propertiesPath

    $Configuration['Name']        = GetPropertiesFileItem -PropertiesFile $propertiesFile -Key wrapper.ntservice.name
    $Configuration['DisplayName'] = GetPropertiesFileItem -PropertiesFile $propertiesFile -Key wrapper.ntservice.displayname
    $Configuration['Description'] = GetPropertiesFileItem -PropertiesFile $propertiesFile -Key wrapper.ntservice.description

    return $Configuration
}

function Set-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [string] $InstallPath,

        [ValidateSet('Present','Absent')]
        [string] $Ensure = 'Present',

        [ValidateNotNullOrEmpty()]
        [string] $Name = 'TCBuildAgent',

        [ValidateNotNullOrEmpty()]
        [string] $DisplayName = 'TeamCity Build Agent',

        [ValidateNotNullOrEmpty()]
        [string] $Description = 'TeamCity Build Agent Service'
    )

    $propertiesPath = Join-Path $InstallPath launcher\conf\wrapper.conf

    switch ($Ensure)
    {
        'Present'
        {
            if (-not (Test-Path -LiteralPath $propertiesPath -PathType Leaf))
            {
                Write-Verbose 'wrapper.conf file does not exist for this agent.  Creating the default file first.'
                $parent = Split-Path $propertiesPath -Parent

                if (-not (Test-Path -LiteralPath $parent -PathType Container))
                {
                    $null = New-Item -Path $parent -ItemType Directory -ErrorAction Stop
                }

                Set-Content -LiteralPath $propertiesPath -Value (Get-DefaultWrapperConf) -Encoding Ascii -ErrorAction Stop
            }

            $propertiesFile = ImportPropertiesFile -Path $propertiesPath

            SetPropertiesFileItem -PropertiesFile $propertiesFile -Key wrapper.ntservice.name        -Value $Name
            SetPropertiesFileItem -PropertiesFile $propertiesFile -Key wrapper.ntservice.displayname -Value $DisplayName
            SetPropertiesFileItem -PropertiesFile $propertiesFile -Key wrapper.ntservice.description -Value $Description
            SetPropertiesFileItem -PropertiesFile $propertiesFile -Key wrapper.ntservice.starttype   -Value AUTO_START
            SetPropertiesFileItem -PropertiesFile $propertiesFile -Key wrapper.ntservice.interactive -Value true

            if ($propertiesFile.Dirty)
            {
                Write-Verbose 'Changes were made to the wrapper.conf file.  Saving the new version.'
                Set-Content -Encoding Ascii -LiteralPath $propertiesPath -Value $propertiesFile.Lines
            }
        }

        'Absent'
        {
            if (Test-Path -LiteralPath $propertiesPath -PathType Leaf)
            {
                Remove-Item -LiteralPath $propertiesPath -Force -ErrorAction Stop
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

        [ValidateSet('Present','Absent')]
        [string] $Ensure = 'Present',

        [ValidateNotNullOrEmpty()]
        [string] $Name = 'TCBuildAgent',

        [ValidateNotNullOrEmpty()]
        [string] $DisplayName = 'TeamCity Build Agent',

        [ValidateNotNullOrEmpty()]
        [string] $Description = 'TeamCity Build Agent Service'
    )

    $propertiesPath = Join-Path $InstallPath launcher\conf\wrapper.conf

    switch ($Ensure)
    {
        'Present'
        {
            if (-not (Test-Path $propertiesPath))
            {
                return $false
            }

            $propertiesFile = ImportPropertiesFile -Path $propertiesPath

            $propertiesToCheck = @{
                'wrapper.ntservice.name'        = $Name
                'wrapper.ntservice.displayname' = $DisplayName
                'wrapper.ntservice.description' = $Description
                'wrapper.ntservice.starttype'   = 'AUTO_START'
                'wrapper.ntservice.interactive' = 'true'
            }

            foreach ($dictionaryEntry in $propertiesToCheck.GetEnumerator())
            {
                if ($dictionaryEntry.Value -ne (GetPropertiesFileItem -PropertiesFile $propertiesFile -Key $dictionaryEntry.Key))
                {
                    Write-Verbose "The wrapper.conf file does not contain expected value '$($dictionaryEntry.Value)' for key '$($dictionaryEntry.Key)'."
                    return $false
                }
            }

            return $true
        }

        'Absent'
        {
            $pathExists = Test-Path -LiteralPath $propertiesPath -PathType Leaf
            return -not $pathExists
        }
    }
}

Export-ModuleMember -Function Get-TargetResource,
                              Test-TargetResource,
                              Set-TargetResource

