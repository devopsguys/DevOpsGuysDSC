#requires -Version 4.0

$modulePath = $PSCommandPath -replace '\.Tests\.ps1$', '.psm1'
$module = $null

try
{
    $prefix = [guid]::NewGuid().Guid -replace '-'
    $module = Import-Module $modulePath -Prefix $prefix -PassThru -ErrorAction Stop

    InModuleScope $module.Name {
        Describe 'Import-TentacleConfigFile' {
            Context 'Fully populated file' {
                $content = @'
<?xml version="1.0" encoding="utf-8"?>
<octopus-settings xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <set key="Octopus.Communications.Squid">CLIENTSQUID</set>
  <set key="Octopus.Home">C:\Octopus</set>
  <set key="Octopus.Storage.MasterKey">_ClientMasterKey_</set>
  <set key="Tentacle.Certificate">_ClientCertificateData_</set>
  <set key="Tentacle.CertificateThumbprint">_ClientCertificateThumbprint_</set>
  <set key="Tentacle.Communication.TrustedOctopusServers">[{"Thumbprint":"_ServerCertificateThumbprint_","CommunicationStyle":"TentacleActive","Address":"https://servername:10943","Squid":"SERVERSQUID"}]</set>
  <set key="Tentacle.Deployment.ApplicationDirectory">C:\Octopus\Applications</set>
  <set key="Tentacle.Services.NoListen">true</set>
  <set key="Tentacle.Services.PortNumber">10933</set>
</octopus-settings>
'@

                $content | Out-File -Encoding ascii -FilePath TestDrive:\test.xml

                It 'Imports the file properly' {
                    $imported = Import-TentacleConfigFile -Path TestDrive:\test.xml

                    $imported.SQUID                | Should Be CLIENTSQUID
                    $imported.HomeDirectory        | Should Be C:\Octopus
                    $imported.DeploymentDirectory  | Should Be C:\Octopus\Applications
                    $imported.Certificate          | Should Be _ClientCertificateData_
                    $imported.MasterKey            | Should Be _ClientMasterKey_
                    $imported.PortNumber           | Should Be 10933
                    $imported.TrustedServers.Count | Should Be 1

                    $server = $imported.TrustedServers[0]

                    $server.Thumbprint         | Should Be _ServerCertificateThumbprint_
                    $server.CommunicationStyle | Should Be TentacleActive
                    $server.Address            | Should Be https://servername:10943
                    $server.Squid              | Should Be SERVERSQUID
                }
            }

            Context 'File with missing information' {
                $content = @'
<?xml version="1.0" encoding="utf-8"?>
<octopus-settings xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
</octopus-settings>
'@

                $content | Out-File -Encoding ascii -FilePath TestDrive:\test.xml

                It 'Imports the file without errors, assigning appropriate default values' {
                    $imported = Import-TentacleConfigFile -Path TestDrive:\test.xml

                    $imported.SQUID                | Should Be $null
                    $imported.HomeDirectory        | Should Be $null
                    $imported.DeploymentDirectory  | Should Be $null
                    $imported.Certificate          | Should Be $null
                    $imported.MasterKey            | Should Be $null
                    $imported.PortNumber           | Should Be 0
                    ,$imported.TrustedServers      | Should Not Be $null
                    $imported.TrustedServers.Count | Should Be 0
                }
            }
        }

        Describe '*-TargetResource Functions' {
            BeforeEach {
                $mockConfigFile = [pscustomobject] @{
                    SQUID                 = 'StubClientSquid'
                    HomeDirectory         = 'StubHomeDirectory'
                    MasterKey             = 'StubMasterKey'
                    Certificate           = 'StubCertificate'
                    CertificateThumbprint = 'StubCertificateThumbprint'
                    DeploymentDirectory   = 'StubDeploymentDirectory'
                    PortNumber            = 10933
                    TrustedServers        = @(
                        [pscustomobject] @{
                            Thumbprint         = 'StubServerThumbprint'
                            CommunicationStyle = 'TentacleActive'
                            Address            = 'https://servername.domain.com:10943'
                            Squid              = 'StubServerSquid'
                        }
                    )
                }

                $splat = @{
                    TentacleName           = 'Stub'
                    Ensure                 = 'Present'
                    ServerName             = 'servername.domain.com'
                    ServerThumbprint       = 'StubServerThumbprint'
                    HomeDirectory          = 'StubHomeDirectory'
                    DeploymentDirectory    = 'StubDeploymentDirectory'
                    Port                   = 10933
                    CommunicationMode      = 'Poll'
                    RegistrationCredential = $bogusCredential
                    Role                   = 'SomeRole'
                    Environment            = 'SomeEnvironment'
                    ServerPort             = 10943
                }

                $stubPath = 'TestDrive:\stub.xml'

                if (-not (Test-Path $stubPath))
                {
                    New-Item -Path $stubPath -ItemType File
                }
            }

            Mock Import-TentacleConfigFile { return $mockConfigFile }
            Mock Get-TentacleConfigPath { return 'TestDrive:\stub.xml' }
            Mock Get-TentacleVersion { return [version] '2.0' }

            $bogusPassword = 'Whatever' | ConvertTo-SecureString -AsPlainText -Force
            $bogusCredential = New-Object pscredential('BogusUserName', $bogusPassword)

            Context 'Get-TargetResource' {
                It 'Returns the proper data' {
                    $config = Get-TargetResource -HomeDirectory 'StubHomeDirectory' -TentacleName 'Stub'

                    $config.GetType()                | Should Be ([hashtable])
                    $config.PSBase.Count             | Should Be 12

                    $config['TentacleName']          | Should Be Stub
                    $config['Ensure']                | Should Be 'Present'
                    $config['HomeDirectory']         | Should Be StubHomeDirectory
                    $config['DeploymentDirectory']   | Should Be StubDeploymentDirectory
                    $config['Port']                  | Should Be 10933
                    $config['CommunicationMode']     | Should Be Poll
                    $config['ServerName']            | Should be servername.domain.com
                    $config['ServerThumbprint']      | Should Be StubServerThumbprint
                    $config['ServerSQUID']           | Should Be StubServerSquid
                    $config['SQUID']                 | Should Be StubClientSquid
                    $config['CertificateThumbprint'] | Should Be StubCertificateThumbprint
                    $config['ServerPort']            | Should Be 10943
                }
            }

            Context 'Test-TargetResource' {
                It 'Returns True when Ensure is set to Absent and the file does not exist' {
                    $splat['Ensure'] = 'Absent'
                    Remove-Item TestDrive:\stub.xml

                    Test-TargetResource @splat | Should Be $true
                }

                It 'Returns False when Ensure is set to Present and the file does not exist' {
                    Remove-Item TestDrive:\stub.xml

                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when Ensure is set to Absent and the file does exist' {
                    $splat['Ensure'] = 'Absent'

                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns True when the configuration matches the desired state' {
                    Test-TargetResource @splat | Should Be $true
                }

                It 'Returns False when the ServerName does not match the desired state and CommunicationMode is set to Poll' {
                    $splat['ServerName'] = 'Bogus'
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Ignores the ServerName when CommunicationMode is set to Listen' {
                    $splat['ServerName']        = 'Bogus'
                    $splat['CommunicationMode'] = 'Listen'

                    $mockConfigFile.TrustedServers[0].CommunicationStyle = 'TentaclePassive'

                    Test-TargetResource @splat | Should Be $true
                }

                It 'Ignores the ServerThumbprint when CommunicationMode is set to Poll' {
                    $splat['ServerThumbprint']  = 'Bogus'

                    Test-TargetResource @splat | Should Be $true
                }

                It 'Returns False when the ServerThumbprint does not match the desired state and CommunicationMode is set to Listen' {
                    $splat['ServerThumbprint']  = 'Bogus'
                    $splat['CommunicationMode'] = 'Listen'

                    $mockConfigFile.TrustedServers[0].CommunicationStyle = 'TentaclePassive'

                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the Home Directory does not match the desired state' {
                    $splat['HomeDirectory'] = 'Bogus'
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the Deployment Directory does not match the desired state' {
                    $splat['DeploymentDirectory'] = 'Bogus'
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the Port does not match the desired state' {
                    $splat['Port'] = 0
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the Communication Mode does not match the desired state' {
                    $splat['CommunicationMode'] = 'Listen'
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Returns False when the Server Port does not match the desired state and CommunicationMode is set to Poll' {
                    $splat['ServerPort'] = 0
                    Test-TargetResource @splat | Should Be $false
                }

                It 'Ignores the Server Port when CommunicationMode is set to Listen' {
                    $splat['ServerPort']        = 0
                    $splat['CommunicationMode'] = 'Listen'

                    $mockConfigFile.TrustedServers[0].CommunicationStyle = 'TentaclePassive'

                    Test-TargetResource @splat | Should Be $true
                }

            }

            Context 'Set-TargetResource' {
                Mock Get-TentacleExecutablePath { return 'TestDrive:\mocked' }

                Mock New-TentacleInstance
                Mock New-TentacleSquid
                Mock New-TentacleCertificate
                Mock Set-TentacleHomeDirectory
                Mock Set-TentacleDeploymentDirectory
                Mock Set-TentaclePort
                Mock Set-TentacleListener
                Mock Register-PollingTentacle

                It 'Makes no changes if the configuration matches the desired state' {
                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 0 New-TentacleInstance
                    Assert-MockCalled -Scope It -Times 0 New-TentacleSquid
                    Assert-MockCalled -Scope It -Times 0 New-TentacleCertificate
                    Assert-MockCalled -Scope It -Times 0 Set-TentacleHomeDirectory
                    Assert-MockCalled -Scope It -Times 0 Set-TentacleDeploymentDirectory
                    Assert-MockCalled -Scope It -Times 0 Set-TentaclePort
                    Assert-MockCalled -Scope It -Times 0 Set-TentacleListener
                    Assert-MockCalled -Scope It -Times 0 Register-PollingTentacle
                }

                It 'Calls New-TentacleInstance if the file does not exist and Ensure is set to Present' {
                    Remove-Item TestDrive:\stub.xml
                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 1 New-TentacleInstance
                }

                It 'Calls New-TentacleSquid if the config file does not have a Squid set' {
                    $mockConfigFile.Squid = $null
                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 1 New-TentacleSquid
                }

                It 'Calls New-TentacleCertificate if the file does not contain a certificate' {
                    $mockConfigFile.Certificate = $null
                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 1 New-TentacleCertificate
                }

                It 'Calls Set-TentacleHomeDirectory if the home directory does not match the desired state' {
                    $splat['HomeDirectory'] = 'Bogus'
                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 1 Set-TentacleHomeDirectory -ParameterFilter { $HomeDirectory -eq 'Bogus' }
                }

                It 'Calls Set-TentacleDeploymentDirectory if the Deployment directory does not match the desired state' {
                    $splat['DeploymentDirectory'] = 'Bogus'
                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 1 Set-TentacleDeploymentDirectory -ParameterFilter { $DeploymentDirectory -eq 'Bogus' }
                }

                It 'Calls Set-TentaclePort if the port does not match the desired state' {
                    $splat['Port'] = 12345
                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 1 Set-TentaclePort -ParameterFilter { $Port -eq 12345 }
                }

                It 'Calls Register-PollingTentacle if CommunicationMode is set to Poll, and ServerName does not match the desired state' {
                    $splat['ServerName'] = 'Bogus'
                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 1 Register-PollingTentacle
                }

                It 'Calls Register-PollingTentacle if CommunicationMode is set to Poll, and ServerPort does not match the desired state' {
                    $splat['ServerPort'] = 12345
                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 1 Register-PollingTentacle
                }

                It 'Calls Register-PollingTentacle if CommunicationMode is set to Poll, and the current state is set for Listen' {
                    $mockConfigFile.TrustedServers[0].CommunicationStyle = 'TentaclePassive'
                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 1 Register-PollingTentacle
                }

                It 'Ignores the ServerThumbprint when CommunicationMode is set to Poll, even if it does not match the desired state parameter.' {
                    $splat['ServerThumbprint'] = 'Bogus'
                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 0 Set-TentacleListener
                }

                It 'Makes no changes if the configuration matches the desired state (Listen Mode)' {
                    $mockConfigFile.TrustedServers[0].CommunicationStyle = 'TentaclePassive'
                    $splat['CommunicationMode'] = 'Listen'

                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 0 New-TentacleInstance
                    Assert-MockCalled -Scope It -Times 0 New-TentacleSquid
                    Assert-MockCalled -Scope It -Times 0 New-TentacleCertificate
                    Assert-MockCalled -Scope It -Times 0 Set-TentacleHomeDirectory
                    Assert-MockCalled -Scope It -Times 0 Set-TentacleDeploymentDirectory
                    Assert-MockCalled -Scope It -Times 0 Set-TentaclePort
                    Assert-MockCalled -Scope It -Times 0 Set-TentacleListener
                    Assert-MockCalled -Scope It -Times 0 Register-PollingTentacle
                }

                It 'Calls Set-TentacleListener if CommunicationMode is set to Listen and the ServerThumbprint does not match the desired state' {
                    $mockConfigFile.TrustedServers[0].CommunicationStyle = 'TentaclePassive'

                    $splat['CommunicationMode'] = 'Listen'
                    $splat['ServerThumbprint'] = 'Bogus'

                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 1 Set-TentacleListener
                }

                It 'Calls Set-TentacleListener if the desired CommunicationMode is set to Listen and the current communication mode is set to Poll' {
                    $splat['CommunicationMode'] = 'Listen'

                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 1 Set-TentacleListener
                }

                It 'Ignores the ServerName when CommunicationMode is set to Listen, even if it does not match the desired state parameter.' {
                    $mockConfigFile.TrustedServers[0].CommunicationStyle = 'TentaclePassive'
                    $splat['ServerName'] = 'Bogus.domain.com'

                    Set-TargetResource @splat

                    Assert-MockCalled -Scope It -Times 0 Set-TentacleListener
                }

            }
        }

        Describe 'Octopus v3.x updates' {
            Mock Get-TentacleExecutablePath { return 'TestDrive:\mocked' }

            Context 'Get-TentacleConfigPath - v2' {
                Mock Get-TentacleVersion { return [version] '2.0' }

                It 'Returns the proper path for v2' {
                    $path = Get-TentacleConfigPath -RootPath TestDrive:\ -TentacleName Tentacle
                    $path | Should Be 'TestDrive:\Tentacle\Tentacle.config'
                }
            }

            Context 'Get-TentacleConfigPath - v3' {
                Mock Get-TentacleVersion { return [version] '3.0' }

                It 'Returns the proper path for v3' {
                    $path = Get-TentacleConfigPath -RootPath TestDrive:\ -TentacleName Tentacle
                    $path | Should Be 'TestDrive:\Tentacle.config'
                }
            }
        }
    }
}
finally
{
    if ($module) { Remove-Module -ModuleInfo $module }
}
