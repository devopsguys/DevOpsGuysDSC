Param ( )

Import-DscResource -ModuleName PSDesiredStateConfiguration

function Write-Log
{
  param (
    [string] $message
  )
  
  $timestamp = ([System.DateTime]::UTCNow).ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss")
  Write-Output "[$timestamp] $message"
}

function Write-CommandOutput 
{
  param (
    [string] $output
  )    
  
  if ($output -eq "") { return }
  
  Write-Output ""
  $output.Trim().Split("`n") |% { Write-Output "`t| $($_.Trim())" }
  Write-Output ""
}

function Install-Chocolatey
{
  Write-Log "======================================"
  Write-Log " Install Java Runtime"
  Write-Log ""
    
  Write-Log "Installing Chocolatey package manager"
 (iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')))>$null 2>&1
  Write-Log "done."    
}

function Install-JavaRunTime
{
  Write-Log "======================================"
  Write-Log " Install Java Runtime"
  Write-Log ""  
  choco install -y -force jre8
  Write-Log "done."
    
}

function Install-TeamCity
{
  Write-Log "======================================"
  Write-Log " Install Team City"
  Write-Log ""
  choco install -y teamcity -force
  Write-Log "done."
    
}


try
{
  Write-Log "======================================"
  Write-Log " Installing 'Team City'"
  Write-Log "======================================"
  Write-Log ""
  
  Install-Chocolatey
  Install-JavaRunTime
  Install-TeamCity
  
  Write-Log "Installation successful."
  Write-Log ""
}
catch
{
  Write-Log $_
}
