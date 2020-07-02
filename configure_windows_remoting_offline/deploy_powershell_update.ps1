# deploy_powershell_update.ps1
# Description: This script connects to remote hosts and updates Powershell
#              to version 5.1 via a Windows login script
# Author:      Nick Marriotti
# Date:        6/30/2020

Param(
    [string]$IPAddress,
    [string]$username = "Administrator",
    [string]$password = "password",
    [switch]$verbose = $true
)

$password_ = ConvertTo-SecureString 'password' -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($username, $password_)

net use Z: \\$IPAddress\c$ /user:$username $password
Copy-Item -Path "C:\configure_windows_remoting_offline\upgrade.ps1" -Destination "Z:\" -Recurse -Verbose -Force
net use Z: /delete

Start-Process -WindowStyle Normal -FilePath c:\pstools\psexec.exe -ArgumentList "-acceptEula -s -u $username -p $password -h \\$IPAddress cmd /c powershell.exe -ExecutionPolicy ByPass -File C:\upgrade.ps1 -username $username -password $password"