function Get-TentacleServiceName
{
    param (
        [string] $TentacleName = 'Tentacle'
    )

    $svcName = 'OctopusDeploy Tentacle'
    if ($TentacleName -ne 'Tentacle')
    {
        $svcName += ": $TentacleName"
    }

    return $svcName
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

function Get-TentacleVersion
{
    param ($TentacleExePath)

    $ErrorActionPreference = 'Stop'

    try
    {
        if (-not $TentacleExePath) { $TentacleExePath = Get-TentacleExecutablePath }
        return (Get-Item $TentacleExePath).VersionInfo.FileVersion -as [version]
    }
    catch
    {
        return [version]'0.0'
    }
}

function Get-TentacleConfigPath
{
    param (
        [Parameter(Mandatory)]
        [string] $RootPath,

        [Parameter(Mandatory)]
        [string] $TentacleName,

        [Version] $OctopusVersion
    )

    # This is a bit awkward.  Once a tentacle is created, its config file path is stored in the registry, and we
    # should continue to return that value here.  (That way, if a tentacle is upgraded from v2 to v3+, we don't
    # generate a new config file with new certificates, etc.)  However, this makes it tricky to move a config
    # file from one place to another once it's been created via the DSC resource.  We won't worry about that
    # edge case for now, but may need to revisit this later.

    $regPath = "HKLM:\Software\Octopus\Tentacle\$TentacleName"
    if (Test-Path $regPath)
    {
        $path = (Get-ItemProperty -Path $regPath -Name ConfigurationFilePath).ConfigurationFilePath
    }

    if (-not $path)
    {
        if ($null -eq $OctopusVersion) { $OctopusVersion = Get-TentacleVersion }

        $path = $RootPath

        if ($OctopusVersion.Major -lt 3)
        {
            $path = Join-Path $path $TentacleName
        }

        $path = Join-Path $path "$TentacleName.config"
    }

    return $path
}
