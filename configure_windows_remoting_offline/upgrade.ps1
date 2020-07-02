Param(
    [bool]$Local = $false,
    [string]$username = "Administrator",
    [string]$password = "password"
)

Function Upgrade-Powershell($username, $password) {

    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "psupdate" -Value '"C:\configure_windows_remoting_offline\update.bat"'

    if ($username -and $password) {
        $reg_winlogon_path = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
        Set-ItemProperty -Path $reg_winlogon_path -Name AutoAdminLogon -Value 1
        Set-ItemProperty -Path $reg_winlogon_path -Name DefaultUserName -Value $username
        Set-ItemProperty -Path $reg_winlogon_path -Name DefaultPassword -Value $password
        echo "rebooting server to continue powershell upgrade"
    } else {
        echo "need to reboot server to continue powershell upgrade"
        $reboot_confirmation = Read-Host -Prompt "need to reboot server to continue powershell upgrade, do you wish to proceed (y/n)"
        if ($reboot_confirmation -ne "y") {
            $error_msg = "please reboot server manually and login to continue upgrade process, the script will restart on the next login automatically"
            echo $error_msg 
        }
    }

    Write-Host "Restarting..."
    sleep(5)

    if (Get-Command -Name Restart-Computer -ErrorAction SilentlyContinue) {
        Restart-Computer -Force
    } else {
        # PS v1 (Server 2008) doesn't have the cmdlet Restart-Computer, use el-traditional
        shutdown /r /t 0
    }
}

# Check PowerShell version and update if necessary
$psversion = Get-Host | Select-Object Version
if($psversion.Version.Major -ne 5) {

    echo "Upgrade required!"

        # Map Network Drive to files on backup server
        net use Z: \\192.168.1.26\configure_windows_remoting_offline /user:Administrator password
        copy-item -Path "Z:\" -Destination "C:\configure_windows_remoting_offline" -Recurse -Verbose -Force
        net use Z: /delete

    # Call function to trigger update
    Upgrade-Powershell $username $password
} else {
    echo "Powershell major version >=5 already installed."
}