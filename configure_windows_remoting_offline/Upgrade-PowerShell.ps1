
# PSScriptInfo
# .VERSION 1.0
# .GUID 23743bae-7604-459d-82c5-a23d36b0820e
# .AUTHOR
#     Jordan Borean <jborean93@gmail.com>
# .COPYRIGHT
#     Jordan Borean 2017
# .TAGS
#     PowerShell,Ansible
# .LICENSEURI https://github.com/jborean93/ansible-windows/blob/master/LICENSE
# .PROJECTURI https://github.com/jborean93/ansible-windows
# .RELEASENOTES
#     Version 1.0: 2017-09-27
#         Initial script created
# .DESCRIPTION
# The script will upgrade the powershell version to whatever is supplied as
# the 'version' on the host. The current versions can be set as the target
# 'version':
#     - 3.0
#     - 4.0
#     - 5.1 (default if -Version not set)
# 
# This script can be run on the following OS'
#     Windows Server 2008 (with SP2) - only supported version 3.0
#     Windows Server 2008 R2 (with SP1)
#     Windows Server 2012
#     Windows Server 2012 R2
#     Windows Server 2016
# 
#     Windows 7 (with SP1)
#     Windows 8.1
#     Windows 10
# 
# All OS' can be upgraded to 5.1 except for Windows Server 2008. If running
# on Powershell 1.0 then this script will first upgrade the version to 2.0
# before running the checks. This is because a lot of the upgrade paths need
# this version installed as a baseline. If the .NET Framework version
# installed is less than 4.5.2, it will be upgraded to 4.5.2 as this is
# supported on all hosts and is required for v5.0.
# 
# As multiple packages can be installed in this process, multiple reboots may
# be required to continue with the install. If a reboot is required the
# script will detect if the 'username' and 'password' parameters have been
# supplied. If they have been supplied it will automatically reboot and login
# to continue the install process until it is all complete. If these
# parameters are not set then it will prompt the user for a reboot and
# require the user to log back in manually after the reboot before
# continuing.
# 
# A log of this process is created in
# $env:SystemDrive\temp\upgrade_powershell.log which is usually C:\temp\. This
# log can used to see how the script faired after an automatic reboot.
# 
# See https://github.com/jborean93/ansible-windows/tree/master/scripts for more
# details.
# .PARAMETER version
#     [string] - The target powershell version to upgrade to. This can be;
#         3.0,
#         4.0, or
#         5.1 (default)
#     Depending on the circumstances, the process to reach the target version
#     may require multiple reboots.
# .PARAMETER username
#     [string] - The username of a local admin user that will be automatically
#     logged in after a reboot to continue the script install. The 'password'
#     parameter is also required if this is set.
# .PARAMETER password
#     [string] - The password for 'username', this is required if the 'username'
#     parameter is also set.
# .PARAMETER Verbose
#     [switch] - Whether to display Verbose logs on the console
# .EXAMPLE
#     # upgrade from powershell 1.0 to 3.0 with automatic login and reboots
#     Set-ExecutionPolicy Unrestricted -Force
#     &.\Upgrade-PowerShell.ps1 -version 3.0 -username "Administrator" -password "Password" -Verbose
# .EXAMPLE
#     # upgrade to 5.1 with defaults and manual login and reboots
#     powershell.exe -ExecutionPolicy ByPass -File Upgrade-PowerShell.ps1
# .EXAMPLE
#     # upgrade to powershell 4.0 with automatic login and reboots
#     powershell.exe -ExecutionPolicy ByPass -File Upgrade-PowerShell.ps1 -version 4.0 -username "Administrator" -password "Password" -Verbose

Param(
    [string]$version = "5.1",
    [string]$username = "Administrator",
    [string]$password = "password",
    [switch]$verbose = $true,
    [string]$tmp_dir = "C:\configure_windows_remoting_offline"
)
$ErrorActionPreference = 'Stop'
if ($verbose) {
    $VerbosePreference = "Continue"
}

Write-Host $tmp_dir

if (-not (Test-Path -Path $tmp_dir)) {
    New-Item -Path $tmp_dir -ItemType Directory > $null
}

Function Write-Log($message, $level="INFO") {
    # Poor man's implementation of Log4Net
    $date_stamp = Get-Date -Format s
    $log_entry = "$date_stamp - $level - $message"
    $log_file = "$tmp_dir\upgrade_powershell.log"
    Write-Verbose -Message $log_entry
    Add-Content -Path $log_file -Value $log_entry
}

Function Reboot-AndResume ($username, $password) {
    
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "psupdate" -Value '"C:\configure_windows_remoting_offline\update.bat"'
    Write-Log -message "Added task to RunOnce"
    echo "Added task to RunOnce"

    if ($username -and $password) {
        $reg_winlogon_path = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
        Set-ItemProperty -Path $reg_winlogon_path -Name AutoAdminLogon -Value 1
        Set-ItemProperty -Path $reg_winlogon_path -Name DefaultUserName -Value $username
        Set-ItemProperty -Path $reg_winlogon_path -Name DefaultPassword -Value $password
        Write-Log -message "rebooting server to continue powershell upgrade"
    } else {
        Write-Log -message "need to reboot server to continue powershell upgrade"
        $reboot_confirmation = Read-Host -Prompt "need to reboot server to continue powershell upgrade, do you wish to proceed (y/n)"
        if ($reboot_confirmation -ne "y") {
            $error_msg = "please reboot server manually and login to continue upgrade process, the script will restart on the next login automatically"
            Write-Log -message $error_msg -level "ERROR"
            throw $error_msg
        }
    }
if (Get-Command -Name Restart-Computer -ErrorAction SilentlyContinue) {
    Restart-Computer -Force
} else {
    # PS v1 (Server 2008) doesn't have the cmdlet Restart-Computer, use el-traditional
    shutdown /r /t 0
}

}

Function Run-Process($executable, $arguments) {

    if($executable -contains ".msu") {
        $executable = "wusa.exe $executable"
    }
    $process = New-Object -TypeName System.Diagnostics.Process
    $psi = $process.StartInfo
    $psi.FileName = $executable
    $psi.Arguments = $arguments
    Write-Log -message "starting new process '$executable $arguments'"
    $process.Start() | Out-Null
    
    $process.WaitForExit() | Out-Null
    $exit_code = $process.ExitCode
    Write-Log -message "process completed with exit code '$exit_code'"

    return $exit_code
}

Function Download-File($url, $path) {
    Write-Log -message "downloading url '$url' to '$path'"
    $client = New-Object -TypeName System.Net.WebClient
    $client.DownloadFile($url, $path)
}

Function Clear-AutoLogon {
    $reg_winlogon_path = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Write-Log -message "clearing auto logon registry properties"
    Set-ItemProperty -Path $reg_winlogon_path -Name AutoAdminLogon -Value 0
    Remove-ItemProperty -Path $reg_winlogon_path -Name DefaultUserName -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $reg_winlogon_path -Name DefaultPassword -ErrorAction SilentlyContinue
    shutdown /r /t 0
}

Function Download-Wmf5Server2008($architecture) {
    if ($architecture -eq "x64") {
        $file = "$tmp_dir\installers\Win7AndW2K8R2-KB3191566-x64.msu"
    } else {
        $file = "$tmp_dir\installers\Win7-KB3191566-x86.msu"
    }
    if (Test-Path -Path $file) {
        return $file
    }

    return $file
}

Write-Log -message "starting script"
# on PS v1.0, upgrade to 2.0 and then run the script again
if ($PSVersionTable -eq $null) {
    Write-Log -message "upgrading powershell v1.0 to v2.0"
    $architecture = $env:PROCESSOR_ARCHITECTURE
    if ($architecture -eq "AMD64") {
        $file = "$tmp_dir\installers\Windows6.0-KB968930-x64.msu"
    } else {
        $file = "$tmp_dir\installers\Windows6.0-KB968930-x86.msu"
    }

    #Download-File -url $url -path $file

    $exit_code = Run-Process -executable $file -arguments "/quiet /norestart" # /norestart goes here
    if ($exit_code -ne 0 -and $exit_code -ne 3010) {
        $error_msg = "failed to update Powershell from 1.0 to 2.0: exit code $exit_code"
        Write-Log -message $error_msg -level "ERROR"
        throw $error_msg
    }
    Reboot-AndResume $username $password
}

# exit if the target version is the same as the actual version
$current_ps_version = [version]"$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
if ($current_ps_version -eq [version]$version) {
    Write-Log -message "current and target PS version are the same, no action is required"
    Clear-AutoLogon
    shutdown /r /t 0
}

$os_version = [Version](Get-Item -Path "$env:SystemRoot\System32\kernel32.dll").VersionInfo.ProductVersion
$architecture = $env:PROCESSOR_ARCHITECTURE
if ($architecture -eq "AMD64") {
    $architecture = "x64"
} else {
    $architecture = "x86"
}

$actions = @()
switch ($version) {
    "3.0" {
        $actions += "3.0"
        break
    }
    "4.0" {
        if ($os_version -lt [version]"6.1") {
            $error_msg = "cannot upgrade Server 2008 to Powershell v4, v3 is the latest supported"
            Write-Log -message $error_msg -level "ERROR"
            throw $error_msg
        }
        $actions += "4.0"
        break
    }
    "5.1" {
        if ($os_version -lt [version]"6.1") {
            $error_msg = "cannot upgrade Server 2008 to Powershell v5.1, v3 is the latest supported"
            Write-Log -message $error_msg -level "ERROR"
            throw $error_msg
        }
        # check if WMF 3 is installed, need to be uninstalled before 5.1
        if ($os_version.Minor -lt 2) {
            $wmf3_installed = Get-Hotfix -Id "KB2506143" -ErrorAction SilentlyContinue
            if ($wmf3_installed) {
                $actions += "remove-3.0"
            }
        }
        $actions += "5.1"
        break
    }
    default {
        $error_msg = "version '$version' is not supported in this upgrade script"
        Write-Log -message $error_msg -level "ERROR"
        throw $error_msg
    }
}

# detect if .NET 4.5.2 is not installed and add to the actions
$dotnet_path = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
if (-not (Test-Path -Path $dotnet_path)) {
    $dotnet_upgrade_needed = $true
} else {
    $dotnet_version = Get-ItemProperty -Path $dotnet_path -Name Release -ErrorAction SilentlyContinue
    if ($dotnet_version) {
        # 379893 == 4.5.2
        if ($dotnet_version.Release -lt 379893) {
            $dotnet_upgrade_needed = $true
        }        
    } else {
        $dotnet_upgrade_needed = $true
    }
}
if ($dotnet_upgrade_needed) {
    $actions = @("dotnet") + $actions
}

Write-Log -message "The following actions will be performed: $($actions -join ", ")"
foreach ($action in $actions) {
    $url = $null
    $file = $null
    $arguments = "/quiet /norestart"

    switch ($action) {
        "dotnet" {
            Write-Log -message "running .NET update to 4.5.2"
            $url = "\installers\NDP452-KB2901907-x86-x64-AllOS-ENU.exe"
            $error_msg = "failed to update .NET to 4.5.2"
            $arguments = "/q /norestart"
            break
        }
        "remove-3.0" {
            # this is only run before a 5.1 install on Windows 7/2008 R2, the
            # install zip needs to be downloaded and extracted before
            # removing 3.0 as then the FileSystem assembly cannot be loaded
            Write-Log -message "downloading WMF/PS v5.1 and removing WMF/PS v3 before version 5.1 install"
            $file = Download-Wmf5Server2008 -architecture $architecture

            $file = "wusa.exe"
            $arguments = "/uninstall /KB:2506143 /quiet /norestart"
            break
        }
        "3.0" {
            Write-Log -message "running powershell update to version 3"    
            if ($os_version.Minor -eq 1) {
                $url = "\installers\Windows6.1-KB2506143-$($architecture).msu"
            } else {
                $url = "\installers\Windows6.0-KB2506146-$($architecture).msu"
            }
            $error_msg = "failed to update Powershell to version 3"
            break
        }
        "4.0" {
            Write-Log -message "running powershell update to version 4"
            if ($os_version.Minor -eq 1) {
                $url = "\installers\Windows6.1-KB2819745-$($architecture)-MultiPkg.msu"
            } else {
                $url = "\installers\Windows8-RT-KB2799888-x64.msu"
            }
            $error_msg = "failed to update Powershell to version 4"
            break
        }
        "5.1" {
            Write-Log -message "running powershell update to version 5.1"
            if ($os_version.Minor -eq 1) {
                # Server 2008 R2 and Windows 7, already downloaded in remove-3.0
                $file = Download-Wmf5Server2008 -architecture $architecture
            } elseif ($os_version.Minor -eq 2) {
                # Server 2012
                $url = "\installers\W2K12-KB3191565-x64.msu"
            } else {
                # Server 2012 R2 and Windows 8.1
                if ($architecture -eq "x64") {
                    $url = "\installers\Win8.1AndW2K12R2-KB3191564-x64.msu"
                } else {
                    $url = "\installers\Win8.1-KB3191564-x86.msu"
                }
            }
            break
        }
        default {
            $error_msg = "unknown action '$action'"
            Write-Log -message $error_msg -level "ERROR"
        }
    }

    if ($file -eq $null) {
        $filename = $url.Split("\")[-1]
        $file = "$tmp_dir\installers\$filename"
    }
    if ($url -ne $null) {
        #Download-File -url $url -path $file
    }
    
    $exit_code = Run-Process -executable $file -arguments $arguments
    if ($exit_code -ne 0 -and $exit_code -ne 3010) {
        $log_msg = "$($error_msg): exit code $exit_code"
        Write-Log -message $log_msg -level "ERROR"
        throw $log_msg
    }
    if ($exit_code -eq 3010) {
        Reboot-AndResume $username $password
        break
    }
}