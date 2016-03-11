Param ( )
 
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
  choco install jre8 -y -force 
  Write-Log "done."
    
}

function Install-TeamCity
{
  Write-Log "======================================"
  Write-Log " Install Team City"
  Write-Log ""
  choco install teamcity -force -y
  Write-Log "done."
    
}

function Install-7zip
{
  Write-Log "======================================"
  Write-Log " Install 7zip"
  Write-Log ""
  choco install 7zip -force -y
  Write-Log "done."
    
}

function Install-NotepadPlusPlus
{
  Write-Log "======================================"
  Write-Log " Install Notepad++"
  Write-Log ""
  choco install notepadplusplus.install -force -y
  Write-Log "done."
    
}

function Install-Chrome
{
  Write-Log "======================================"
  Write-Log "Install Chrome"
  Write-Log ""
  choco install googlechrome -force -y
  Write-Log "done."
}


try
{
  Write-Log "======================================"
  Write-Log " Setting up server"
  Write-Log "======================================"
  Write-Log ""
  
  Install-Chocolatey
  Install-JavaRunTime
  Install-TeamCity
  Install-7zip
  Install-NotepadPlusPlus
  Install-Chrome
  
  Write-Log "Server setup complete."
  Write-Log ""
}
catch
{
  Write-Log $_
}
