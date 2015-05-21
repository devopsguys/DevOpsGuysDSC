#requires -Version 4.0

$modulePath = $PSCommandPath -replace '\.Tests\.ps1$', '.psm1'
$module = $null

try
{
    # This is necessary due to some scope voodoo that's happening in Pester.  $PSScriptRoot doesn't work
    # at the point where we need it.
    $global:__scriptRoot = $PSScriptRoot

    $prefix = [guid]::NewGuid().Guid -replace '-'
    $module = Import-Module $modulePath -Prefix $prefix -PassThru -ErrorAction Stop

    InModuleScope $module.Name {
        Describe 'Cache directory management' {
            Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*buildAgent.zip' -and $null -ne $OutFile } {
                Copy-Item $global:__scriptRoot\buildAgent.zip -Destination $OutFile
            }

            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*/version' } {
                return '8.1.5 (build 30240)'
            }

            $cacheDirectory = GetCacheDirectory
            $buildAgentCache = Join-Path $cacheDirectory.FullName buildAgent

            Context 'When the cache folder does not exist' {
                It 'Reports the cache is not up-to-date' {
                    Remove-Item -LiteralPath $cacheDirectory.FullName -Recurse -Force -ErrorAction Stop

                    BuildAgentCacheIsUpToDate -CachePath $buildAgentCache -ServerBaseUri 'https://servername:1234' | Should Be $false
                }
            }

            Context 'Creating the cache folder' {
                It 'Successfully downloads and extracts the zip file from the server' {
                    { UpdateCache -CachePath $buildAgentCache -ServerBaseUri 'https://servername:1234' } | Should Not Throw
                    $buildAgentCache | Should Exist
                }

                It 'Called the Invoke-WebRequest command with the correct URL' {
                    Assert-MockCalled Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://servername:1234/update/buildAgent.zip' }
                }
            }

            Context 'After updating the cache' {
                Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*.zip' }

                It 'Reports the cache is up-to-date, and does not re-download the zip file' {
                    BuildAgentCacheIsUpToDate -CachePath $buildAgentCache -ServerBaseUri 'https://servername:1234' | Should Be $true
                    Assert-MockCalled Invoke-WebRequest -Times 0 -Scope It
                }

                It 'Calls the Invoke-RestMethod command with the correct URL' {
                    Assert-MockCalled Invoke-RestMethod -ParameterFilter { $Uri -eq 'https://servername:1234/app/rest/server/version' }
                }
            }

            Context 'When the server version changes' {
                Mock GetServerBuildNumber { return 1234567890 }

                It 'Reports that the cache is not up-to-date' {
                    BuildAgentCacheIsUpToDate -CachePath $buildAgentCache -ServerBaseUri 'mocked' | Should Be $false
                }
            }

            Context 'When a cached file is deleted' {
                $file = Get-ChildItem -LiteralPath $buildAgentCache -File -Exclude 'BUILD_*' |
                        Select-Object -First 1

                $moved = $false
                try
                {
                    Move-Item -LiteralPath $file.FullName -Destination TestDrive:\ -ErrorAction Stop
                    $moved = $true

                    It 'Reports that the cache is not up-to-date' {
                        BuildAgentCacheIsUpToDate -CachePath $buildAgentCache -ServerBaseUri 'mocked' | Should Be $false
                    }
                }
                finally
                {
                    # Restoring the cache to avoid potential unnecessary re-downloads of the zip file later in the script.

                    if ($moved)
                    {
                        Move-Item -LiteralPath "TestDrive:\$($file.Name)" -Destination $file.FullName -ErrorAction Stop
                    }
                }
            }
        }

        Describe 'Agent directory management' {
            Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*buildAgent.zip' -and $null -ne $OutFile } {
                Copy-Item $global:__scriptRoot\buildAgent.zip -Destination $OutFile
            }

            Mock Invoke-RestMethod -ParameterFilter { $Uri -like '*/version' } {
                return '8.1.5 (build 30240)'
            }

            $cacheDirectory = (GetCacheDirectory).FullName

            # Ensure our cache is ready before performing these tests.
            if (-not (BuildAgentCacheIsUpToDate -CachePath $cacheDirectory -ServerBaseUri 'mocked'))
            {
                UpdateCache -CachePath $cacheDirectory -ServerBaseUri 'mocked'
            }

            $agentDirectory = "$env:temp\TCAgent"
            if (Test-Path -LiteralPath $agentDirectory)
            {
                Remove-Item -LiteralPath $agentDirectory -Recurse -Force -ErrorAction Stop
            }

            Context 'When the agent folder does not exist' {
                It 'Reports that the agent folder requires an update' {
                    $agentUpToDate = AgentDirectoryContainsAllRequiredFiles -AgentDirectory $agentDirectory -SourceDirectory $cacheDirectory
                    $agentUpToDate | Should Be $false
                }
            }

            Context 'Updating the agent folder' {
                It 'Copies the cached binaries without error' {
                    { CopyAgentBinaries -AgentDirectory $agentDirectory -SourceDirectory $cacheDirectory } | Should Not Throw
                }

                It 'Reports that the agent folder is up to date after the installation' {
                    $agentUpToDate = AgentDirectoryContainsAllRequiredFiles -AgentDirectory $agentDirectory -SourceDirectory $cacheDirectory
                    $agentUpToDate | Should Be $true
                }
            }

            Context 'When files change in the agent folder' {
                $file = Get-ChildItem -LiteralPath $agentDirectory -Exclude *.properties -File |
                        Select-Object -First 1

                Set-Content -LiteralPath $file.FullName -Value 'This is a test.'

                # We're not validating the contents of the files, only their existence.
                # The TeamCity agent is responsible for updating itself once it's installed.

                It 'Still reports that the agent folder is up to date' {
                    $agentUpToDate = AgentDirectoryContainsAllRequiredFiles -AgentDirectory $agentDirectory -SourceDirectory $cacheDirectory
                    $agentUpToDate | Should Be $true
                }
            }

            Context 'Configuration files' {
                Set-Content -LiteralPath $cacheDirectory\bogus.properties -Value 'This is a test.'

                It 'Ignores *.properties files when evaluating the agent folder state' {
                    $agentUpToDate = AgentDirectoryContainsAllRequiredFiles -AgentDirectory $agentDirectory -SourceDirectory $cacheDirectory
                    $agentUpToDate | Should Be $true
                }
            }
        }

        Describe 'Properties files' {
            Set-Content -Path TestDrive:\test.properties -Value "#commentedKey=commentedValue`r`ntestKey=testValue"
            BeforeEach {
                $propertiesFile = ImportPropertiesFile -Path TestDrive:\test.properties
            }

            It 'Imports a properties file correctly' {
                $propertiesFile.Dirty | Should Be $false
                $propertiesFile.Lines.Count | Should Be 2
                $propertiesFile.Lines[1] | Should Be 'testKey=testValue'
            }

            It 'Does not mark a file as dirty if setting a pre-existing key/value pair' {
                SetPropertiesFileItem -PropertiesFile $propertiesFile -Key testKey -Value testValue

                $propertiesFile.Dirty | Should Be $false
                $propertiesFile.Lines.Count | Should Be 2
                $propertiesFile.Lines[1] | Should Be 'testKey=testValue'
            }

            It 'Treats keys as case sensitive' {
                SetPropertiesFileItem -PropertiesFile $propertiesFile -Key TESTKEY -Value testValue

                $propertiesFile.Dirty | Should Be $true
                $propertiesFile.Lines.Count | Should Be 3
            }

            It 'Treats values as case sensitive' {
                SetPropertiesFileItem -PropertiesFile $propertiesFile -Key testKey -Value TESTVALUE

                $propertiesFile.Dirty | Should Be $true
                $propertiesFile.Lines.Count | Should Be 2
            }

            It 'Uncomments lines from the default file rather than adding new ones, if applicable' {
                SetPropertiesFileItem -PropertiesFile $propertiesFile -Key commentedKey -Value newValue

                $propertiesFile.Dirty | Should Be $true
                $propertiesFile.Lines.Count | Should Be 2
                $propertiesFile.Lines[0] | Should Be 'commentedKey=newValue'
                $propertiesFile.Lines[1] | Should Be 'testKey=testValue'
            }

            It 'Does not modify comment lines if a matching uncommented line exists' {
                $propertiesFile.Lines += 'commentedKey=uncommentedValue'

                SetPropertiesFileItem -PropertiesFile $propertiesFile -Key commentedKey -Value newValue

                $propertiesFile.Dirty | Should Be $true
                $propertiesFile.Lines.Count | Should Be 3
                $propertiesFile.Lines[0] | Should Be '#commentedKey=commentedValue'
                $propertiesFile.Lines[1] | Should Be 'testKey=testValue'
                $propertiesFile.Lines[2] | Should Be 'commentedKey=newValue'
            }

            It 'Uncomments the line properly if the value matches' {
                SetPropertiesFileItem -PropertiesFile $propertiesFile -Key commentedKey -Value commentedValue

                $propertiesFile.Dirty | Should Be $true
                $propertiesFile.Lines.Count | Should Be 2
                $propertiesFile.Lines[0] | Should Be 'commentedKey=commentedValue'
            }
        }
    }
}
finally
{
    if ($module) { Remove-Module -ModuleInfo $module }
    Remove-Variable -Scope Global -Name __scriptRoot -ErrorAction Ignore
}
