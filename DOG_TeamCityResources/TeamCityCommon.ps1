function GetCacheDirectory
{
    $cachePath = Join-Path $env:TEMP DOG_TeamCityBuildAgent.cache

    if (-not (Test-Path -LiteralPath $cachePath -PathType Container))
    {
        $null = New-Item -Path $cachePath -ItemType Directory -ErrorAction Stop
    }

    return Get-Item -LiteralPath $cachePath
}

function UpdateCache
{
    param (
        [string] $CachePath,
        [uri] $ServerBaseUri
    )

    if (BuildAgentCacheIsUpToDate @PSBoundParameters) { return }

    $CachePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CachePath)

    if (Test-Path -LiteralPath $CachePath -PathType Container)
    {
        Remove-Item -Path $CachePath\* -Recurse -Force -ErrorAction Stop
    }

    $localZipPath = "$env:TEMP\DOG_TeamCityBuildAgent.zip"
    if (Test-Path -LiteralPath $localZipPath -PathType Leaf)
    {
        Remove-Item -Path $localZipPath -Force -ErrorAction Stop
    }

    $agentZipDownloadUri = '{0}://{1}:{2}/update/buildAgent.zip' -f $ServerBaseUri.Scheme, $ServerBaseUri.Host, $ServerBaseUri.Port

    Invoke-WebRequest -Uri $agentZipDownloadUri -OutFile $localZipPath -ErrorAction Stop
    ExtractZipFile -ZipFile $localZipPath -Destination $CachePath

    if (Test-Path -Path $CachePath\conf\buildAgent.dist.properties)
    {
        Rename-Item -LiteralPath $CachePath\conf\buildAgent.dist.properties -NewName buildAgent.properties
    }
}

function BuildAgentCacheIsUpToDate
{
    param (
        [string] $CachePath,
        [uri] $ServerBaseUri
    )

    $cacheBuildNumber = GetAgentCacheBuildNumber -CachePath $CachePath
    if ($null -eq $cacheBuildNumber) { return $false }

    $serverBuildNumber = GetServerBuildNumber -ServerBaseUri $ServerBaseUri

    return $cacheBuildNumber -eq $serverBuildNumber
}

function GetAgentCacheBuildNumber
{
    param ([string] $CachePath)

    if (-not (Test-Path -Path $CachePath -PathType Container))
    {
        return
    }

    $source = Join-Path $CachePath *

    $buildFiles = Get-ChildItem -Path $CachePath\* -Include BUILD_* -File
    $buildNumbers = foreach ($file in $buildFiles)
    {
        if ($file.Name -match '^BUILD_(\d+)$')
        {
            [int]$matches[1]
        }
    }

    if ($buildNumbers.Count -gt 0)
    {
        return $buildNumbers | Sort-Object -Descending | Select-Object -First 1
    }
}

function GetServerBuildNumber
{
    param ([Uri] $ServerBaseUri)

    $versionQueryUri = '{0}://{1}:{2}/app/rest/server/version' -f $ServerBaseUri.Scheme, $ServerBaseUri.Host, $ServerBaseUri.Port

    $serverVersion = Invoke-RestMethod -Uri $versionQueryUri -ErrorAction Stop

    if ($serverVersion -notmatch '\(build\s+(\d+)\)')
    {
        throw "Response from URL '$versionQueryUri' did not match expected pattern."
    }

    return [int]$matches[1]
}

function ExtractZipFile
{
    param ([string] $ZipFile, [string] $Destination)

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFile, $Destination)
}

function AgentDirectoryContainsAllRequiredFiles
{
    param (
        [string] $AgentDirectory,
        [string] $SourceDirectory
    )

    $hashTable = @{
        Result = $true
    }

    VisitCacheFiles -Source                     $SourceDirectory `
                    -Destination                $AgentDirectory `
                    -OnMissingFile              ${function:TestAgentDirectory_OnMissingFile} `
                    -OnMissingDestinationFolder ${function:TestAgentDirectory_OnMissingDestinationFolder} `
                    -IgnoreConfigurationFiles

    return $hashTable['Result']
}

function CopyAgentBinaries
{
    param (
        [string] $AgentDirectory,
        [string] $SourceDirectory
    )

    VisitCacheFiles -Source                     $SourceDirectory `
                    -Destination                $AgentDirectory `
                    -OnMissingFile              ${function:CopyAgentFiles_OnMissingFile} `
                    -OnMissingDestinationFolder ${function:CopyAgentFiles_OnMissingDestinationFolder}
}

function VisitCacheFiles
{
    param (
        [string] $Source,
        [string] $Destination,

        [switch] $IgnoreConfigurationFiles,

        [scriptblock] $OnMissingDestinationFolder,
        [scriptblock] $OnMissingFile
    )

    # Note:  This function deliberately only checks for the existence of files in the destination
    # directory, rather than checking their hashes.  This is because TeamCity agents update themselves
    # as time goes on, and we don't want to screw with the newer binaries.

    # Per communication with JetBrains, we can treat the contents of the buildAgent.zip file as the bare minimum
    # binaries that need to be present in order for the agent to function.  It may download or create other files
    # during normal operation; these extras can be ignored.

    $Source      = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Source)
    $Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)

    if (-not (Test-Path -LiteralPath $Destination -PathType Container))
    {
        $shouldContinue = & $OnMissingDestinationFolder $Destination
        if (-not $shouldContinue) { return }
    }

    $exclude = @(
        if ($IgnoreConfigurationFiles)
        {
            '*.properties'
            '*.conf'
        }
    )

    $sourceFiles = Get-ChildItem -Path (Join-Path $Source *) -File -Recurse -Force -Exclude $exclude

    foreach ($file in $sourceFiles)
    {
        $relativePath = GetRelativePath -Path $file.FullName -RelativeTo $Source
        $destPath = Join-Path $Destination $relativePath

        if (-not (Test-Path -LiteralPath $destPath -PathType Leaf))
        {
            & $OnMissingFile $Source $Destination $relativePath
        }
    }
}
function TestAgentDirectory_OnMissingDestinationFolder
{
    param ( [string] $Path )

    Write-Verbose "Agent folder '$Path' does not exist."
    $hashTable['Result'] = $false

    return $false
}

function TestAgentDirectory_OnMissingFile
{
    param (
        [string] $Source,
        [string] $Destination,
        [string] $RelativePathOfMissingFile
    )

    Write-Verbose "File '$RelativePathOfMissingFile' is missing from agent directory '$AgentDirectory'"
    $hashTable['Result'] = $false
}

function CopyAgentFiles_OnMissingFile
{
    param (
        [string] $Source,
        [string] $Destination,
        [string] $RelativePathOfMissingFile
    )

    Write-Verbose "Copying '$RelativePathOfMissingFile' from cache to agent directory '$AgentDirectory'."

    $sourcePath = Join-Path $Source $RelativePathOfMissingFile
    $destPath   = Join-Path $Destination $RelativePathOfMissingFile

    $parent = Split-Path -Path $destPath -Parent

    if (-not (Test-Path -LiteralPath $parent -PathType Container))
    {
        New-Item -Path $parent -ItemType Directory -Force -ErrorAction Stop
    }

    Copy-Item -LiteralPath $sourcePath -Destination $destPath -Force -ErrorAction Stop
}

function CopyAgentFiles_OnMissingDestinationFolder
{
    param ( [string] $Path )

    Write-Verbose "Creating agent folder '$Path'"
    $null = New-Item -Path $Path -ItemType Directory -ErrorAction Stop

    return $true
}

function GetRelativePath
{
    param ( [string] $Path, [string] $RelativeTo )
    return $Path -replace "^$([regex]::Escape($RelativeTo))\\?"
}

function ImportPropertiesFile
{
    param ([string] $Path)

    $lines = @(
        if (Test-Path -Path $Path -PathType Leaf)
        {
            Get-Content -LiteralPath $Path -ErrorAction Stop
        }
    )

    return [pscustomobject] @{
        Lines = $lines
        Dirty = $false
    }
}

function SetPropertiesFileItem
{
    param (
        [object] $PropertiesFile,
        [string] $Key,
        [string] $Value,
        [switch] $Uncomment
    )

    if ($Uncomment)
    {
        $pattern = "^\s*#*\s*$([regex]::Escape($Key))=(.*)$"
    }
    else
    {
        $pattern = "^$([regex]::Escape($Key))=(.*)$"
    }

    for ($i = 0; $i -lt $PropertiesFile.Lines.Count; $i++)
    {
        if ($PropertiesFile.Lines[$i] -cmatch $pattern)
        {
            if ($Value -cne $matches[1] -or $Uncomment)
            {
                $commented = if ($Uncomment) { 'and uncommenting ' }
                Write-Verbose "Updating ${commented}property '$Key' from value '$($matches[1])' to value '$Value'"

                $PropertiesFile.Lines[$i] = "$Key=$Value"
                $PropertiesFile.Dirty = $true
            }
            else
            {
                Write-Verbose "Property '$Key' is already set to value '$Value'"
            }

            return
        }
    }

    if (-not $Uncomment)
    {
        $null = $PSBoundParameters.Remove('Uncomment')
        SetPropertiesFileItem @PSBoundParameters -Uncomment
    }
    else
    {
        Write-Verbose "Adding new property '$Key' with value '$Value'"

        $PropertiesFile.Lines += @("$Key=$Value")
        $PropertiesFile.Dirty = $true
    }
}

function CommentOutPropertiesFileItem
{
    param (
        [object] $PropertiesFile,
        [string] $Key
    )

    $pattern = "^$([regex]::Escape($Key))=.*$"

    for ($i = 0; $i -lt $PropertiesFile.Lines.Count; $i++)
    {
        if ($PropertiesFile.Lines[$i] -cmatch $pattern)
        {
            Write-Verbose "Commenting out property '$Key'"

            $PropertiesFile.Lines[$i] = "#$($PropertiesFile.Lines[$i])"
            $PropertiesFile.Dirty = $true

            return
        }
    }
}

function GetPropertiesFileItem
{
    param (
        [object] $PropertiesFile,
        [string] $Key
    )

    $pattern = "^$([regex]::Escape($Key))=(.*)$"
    for ($i = 0; $i -lt $PropertiesFile.Lines.Count; $i++)
    {
        if ($PropertiesFile.Lines[$i] -cmatch $pattern)
        {
            return $matches[1]
        }
    }
}

function GetBuildProperties
{
    param (
        [object] $PropertiesFile
    )

    $buildProperties = @{}

    $pattern = "^(?!\s*#)((?:system\.|env\.)[^=]+)=(.*)$"
    for ($i = 0; $i -lt $PropertiesFile.Lines.Count; $i++)
    {
        if ($PropertiesFile.Lines[$i] -cmatch $pattern)
        {
            # The TeamCity documentation states that values should be properly escaped, and specifically calls out doubling up backslashes.
            # Presumably this is following java rules; should we look for other escape sequences, such as \r, \n, \t, etc?  Are those likely
            # to ever need to be in the config file?

            $buildProperties[$matches[1]] = $matches[2] -replace '\\\\', '\'
        }
    }

    return $buildProperties
}

function Get-HashtableFromKeyValuePairArray
{
    param (
        #[ValidateScript({
        #    if ($_.CimClass.CimClassName -ne 'MSFT_KeyValuePair')
        #    {
        #        throw 'Input objects must be of CIM type MSFT_KeyValuePair'
        #    }
        #
        #    return $true
        #})]
        [ciminstance[]] $KeyValuePairArray
    )

    $hashtable = @{}

    foreach ($entry in $KeyValuePairArray)
    {
        $hashtable[$entry.Key] = $entry.Value
    }

    return $hashtable
}

function Get-DefaultBuildAgentProperties
{
    return @'
## TeamCity build agent configuration file

######################################
#   Required Agent Properties        #
######################################

## The address of the TeamCity server. The same as is used to open TeamCity web interface in the browser.
serverUrl=http://localhost:8111/

## The unique name of the agent used to identify this agent on the TeamCity server
## Use blank name to let server generate it. By default, this name would be created from the build agent's host name
name=

## Container directory to create default checkout directories for the build configurations.
workDir=../work

## Container directory for the temporary directories.
## Please note that the directory may be cleaned between the builds.
tempDir=../temp

## Container directory for agent system files
systemDir=../system


######################################
#   Optional Agent Properties        #
######################################

## The IP address which will be used by TeamCity server to connect to the build agent.
## If not specified, it is detected by build agent automatically,
## but if the machine has several network interfaces, automatic detection may fail.
#ownAddress=<own IP address or server-accessible domain name>

## Optional
## A port that TeamCity server will use to connect to the agent.
## Please make sure that incoming connections for this port
## are allowed on the agent computer (e.g. not blocked by a firewall)
ownPort=9090

## A token which is used to identify this agent on the TeamCity server.
## It is automatically generated and saved on the first agent connection to the server.
authorizationToken=


######################################
#   Default Build Properties         #
######################################
## All properties starting with "system.name" will be passed to the build script as "name"
## All properties starting with "env.name" will be set as environment variable "name" for the build process
## Note that value should be properly escaped. (use "\\" to represent single backslash ("\"))
## More on file structure: http://java.sun.com/j2se/1.5.0/docs/api/java/util/Properties.html#load(java.io.InputStream)

# Build Script Properties

#system.exampleProperty=example Value

# Environment Variables

#env.exampleEnvVar=example Env Value
'@
}

function Get-DefaultWrapperConf
{
    return @'
#********************************************************************
# Java Service Wrapper Properties for TeamCity Agent Launcher
#********************************************************************

#####################################################################
###
###   The path should point to 'java' program.
###
#####################################################################

wrapper.java.command=java

wrapper.java.mainclass=org.tanukisoftware.wrapper.WrapperSimpleApp

# Java Classpath
wrapper.java.classpath.1=../launcher/lib/wrapper.jar
wrapper.java.classpath.2=../launcher/lib/launcher.jar 

# Java Library Path (location of Wrapper.DLL or libwrapper.so)
wrapper.java.library.path.1=../launcher/lib
wrapper.java.library.path.2=../launcher/bin

# TeamCity agent launcher parameters
#Preventing launcher exit on x64 when user logs off
wrapper.java.additional.1=-Xrs

# Initial Java Heap Size (in MB)
#wrapper.java.initmemory=3

# Maximum Java Heap Size (in MB)
#wrapper.java.maxmemory=384

###########################################################
### TeamCity agent JVM parameters
###
### NOTE: There should be no gaps in parameters numbers, if
### NOTE: you change parameters, you need to update numbering
###
##########################################################
# Application parameters.
wrapper.app.parameter.1=jetbrains.buildServer.agent.StandAloneLauncher
wrapper.app.parameter.2=-ea
wrapper.app.parameter.3=-Xmx512m
# The next line can be removed (and the rest of the parameter names MUST BE renumbered) to prevent memory dumps on OutOfMemoryErrors
wrapper.app.parameter.4=-XX:+HeapDumpOnOutOfMemoryError
# Preventing process exiting on user log off
wrapper.app.parameter.5=-Xrs
# Uncomment the next line (insert the number instead of "N" and renumber the rest of the lines) to improve JVM performance
# wrapper.app.parameter.N=-server
wrapper.app.parameter.6=-Dlog4j.configuration=file:../conf/teamcity-agent-log4j.xml
wrapper.app.parameter.7=-Dteamcity_logs=../logs/
wrapper.app.parameter.8=jetbrains.buildServer.agent.AgentMain
# TeamCity agent parameters
wrapper.app.parameter.9=-file
wrapper.app.parameter.10=../conf/buildAgent.properties


wrapper.working.dir=../../bin

wrapper.ping.timeout=0

#********************************************************************
# Wrapper Logging Properties
#********************************************************************
# Format of output for the console.  (See Java Service Wrapper documentation for formats)
wrapper.console.format=PM

# Log Level for console output.  (See docs for log levels)
wrapper.console.loglevel=INFO

# Log file to use for wrapper output logging.
wrapper.logfile=../logs/wrapper.log

# Format of output for the log file.  (See docs for formats)
wrapper.logfile.format=LPTM

# Log Level for log file output.  (See docs for log levels)
wrapper.logfile.loglevel=INFO

# Maximum size that the log file will be allowed to grow to before
#  the log is rolled. Size is specified in bytes.  The default value
#  of 0, disables log rolling.  May abbreviate with the 'k' (kb) or
#  'm' (mb) suffix.  For example: 10m = 10 megabytes.
wrapper.logfile.maxsize=10m

# Maximum number of rolled log files which will be allowed before old
#  files are deleted.  The default value of 0 implies no limit.
wrapper.logfile.maxfiles=10

# Log Level for sys/event log output.  (See docs for log levels)
wrapper.syslog.loglevel=NONE

#********************************************************************
# Wrapper Windows Properties
#********************************************************************
# Title to use when running as a console
wrapper.console.title=TeamCity Build Agent

#********************************************************************
# Wrapper Windows NT/2000/XP Service Properties
#********************************************************************
# WARNING - Do not modify any of these properties when an application
#  using this configuration file has been installed as a service.
#  Please uninstall the service before modifying this section.  The
#  service can then be reinstalled.

# Name of the service
wrapper.ntservice.name=TCBuildAgent

# Display name of the service
wrapper.ntservice.displayname=TeamCity Build Agent

# Description of the service
wrapper.ntservice.description=TeamCity Build Agent Service

# Service dependencies.  Add dependencies as needed starting from 1
wrapper.ntservice.dependency.1=

# Mode in which the service is installed.  AUTO_START or DEMAND_START
wrapper.ntservice.starttype=AUTO_START

# Allow the service to interact with the desktop.
wrapper.ntservice.interactive=true
'@
}