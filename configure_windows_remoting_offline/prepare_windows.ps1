Param(
[string]$username = "Administrator",
[string]$password = "password"
)

$tmp_dir = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

$client_path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client"
$service_path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service"

if(Get-ItemProperty -Path $client_path  -Name AllowUnencrypted -ErrorAction SilentlyContinue) {
     Write-Host "Updating  $client_path registry key to AllowUnencrypted"
     Set-ItemProperty -Path $client_path -Name AllowUnencrypted -Value 1 -Force
} else {
    Write-Host "Creating new registry key at $client_path to AllowUnencrypted"
    New-Item -Path $client_path -Name AllowUnencrypted -Force
    New-ItemProperty -Path $client_path -Name AllowUnencrypted -PropertyType DWORD -Value 1
}

if(Get-ItemProperty -Path $client_path  -Name AllowBasic -ErrorAction SilentlyContinue) {
    Write-Host "Updating  $client_path registry key to AllowBasic"
    # Key exists
    Set-ItemProperty -Path $client_path -Name AllowBasic -Value 1 -Force
} else {
    Write-Host "Creating new registry key at $client_path to AllowBasic"
    # Key does not exist, need to create it
    New-Item -Path $client_path -Name AllowBasic -Force
    New-ItemProperty -Path $client_path -Name AllowBasic -PropertyType DWORD -Value 1
}



if(Get-ItemProperty -Path $service_path  -Name AllowUnencrypted -ErrorAction SilentlyContinue) {
     Write-Host "Updating  $service_path registry key to AllowUnencrypted"
     Set-ItemProperty -Path $service_path -Name AllowUnencrypted -Value 1 -Force
} else {
    Write-Host "Creating new registry key at $service_path to AllowUnencrypted"
    # Key does not exist, need to create it
    New-Item -Path $service_path -Name AllowUnencrypted -ItemType DWORD -Force
    New-ItemProperty -Path $service_path -Name AllowUnencrypted -PropertyType DWORD -Value 1
}

if(Get-ItemProperty -Path $service_path  -Name AllowBasic -ErrorAction SilentlyContinue) {
    Write-Host "Updating  $service_path registry key to AllowBasic"
    # Key exists
    Set-ItemProperty -Path $service_path -Name AllowBasic -Value 1 -Force
} else {
    Write-Host "Creating new registry key at $service_path to AllowBasic"
    # Key does not exist, need to create it
    New-Item -Path $service_path -Name AllowBasic -Force
    New-ItemProperty -Path $service_path -Name AllowBasic -PropertyType DWORD -Value 1
}


# Change Network Profile from Public to Private
$NLMType = [Type]::GetTypeFromCLSID(‘DCB00C01-570F-4A9B-8D69-199FDBA5723B’) 
$INetworkListManager = [Activator]::CreateInstance($NLMType) 
 
$NLM_ENUM_NETWORK_CONNECTED  = 1 
$NLM_NETWORK_CATEGORY_PUBLIC = 0x00 
$NLM_NETWORK_CATEGORY_PRIVATE = 0x01 
$UNIDENTIFIED = "Unidentified network" 
 
$INetworks = $INetworkListManager.GetNetworks($NLM_ENUM_NETWORK_CONNECTED) 

foreach ($INetwork in $INetworks) 
{ 
    $Name = $INetwork.GetName() 
    $Category = $INetwork.GetCategory() 

 
    if ($INetwork.IsConnected -and ($Category -eq $NLM_NETWORK_CATEGORY_PUBLIC)) 
    { 
        $INetwork.SetCategory($NLM_NETWORK_CATEGORY_PRIVATE) 
    } 
} 

# Upgrading PowerShell and .NET Framework
$file = "$tmp_dir\Upgrade-PowerShell.ps1"
# Version can be 3.0, 4.0 or 5.1
&$file -Version 5.1 -Username $username -Password $password -Verbose -tmp_dir $tmp_dir


$reg_winlogon_path = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $reg_winlogon_path -Name AutoAdminLogon -Value 0
Remove-ItemProperty -Path $reg_winlogon_path -Name DefaultUserName -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $reg_winlogon_path -Name DefaultPassword -ErrorAction SilentlyContinue


# WinRM Memory Hotfix
$hotfix_file = "$tmp_dir\Install-WMF3Hotfix.ps1"
powershell.exe -ExecutionPolicy ByPass -File $hotfix_file -Verbose


# Configure Remoting
$remoting_file = "$tmp_dir\ConfigureRemotingForAnsible.ps1"
powershell.exe -ExecutionPolicy ByPass -File $remoting_file -Verbose


# Set TrustedHosts
winrm set winrm/config/client '@{TrustedHosts="*"}'
winrm set winrm/config/client '@{AllowUnencrypted="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'

winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'