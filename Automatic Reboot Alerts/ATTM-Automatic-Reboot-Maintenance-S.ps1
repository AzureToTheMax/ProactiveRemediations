#Windows Endpoint Automatic Reboot Maintenance - System Side

<#
.SYNOPSIS
This script is designed to check the current uptime of a Windows Endpoint machine. If no account is presently logged in (locker or disconnected counts!), and the machine is in violation of uptime limits, the machine will be rebooted forcibly after a configured delay.

.DESCRIPTION
1. Read our configurable variables
2. Declare our functions (some of which rely on the variables we just declared)
3. Create our logging directories and start logging
4. Check if a user is logged-in
5. If not, schedule a reboot in 60 seconds

.NOTES
Author:      Maxton Allen
Contact:     @AzureToTheMax
Website: 	 AzureToTheMax.Net
Created:     3/30/2025
Updated:     

            
Version history:
1 -  03/30/2025 - Script created using the 10/12/2024 edition of Automatic Disk Space alerts as the basis.

#>


#Region Variables
#This region contains the primary configurable variables.

#Uptime Thresholds
	#The maximum amount of uptime in days. Breaking this threshold results in a forced prompt.
	$MaximumUptime = "10"

	#The amount of time in seconds after the machine will wait to restart if conditions are met (no active user and uptime breaks maximum threshold). Default is 300, or 5 minutes.
	$ForcedRebootTime = 300

	#Testing value
	#Use this to set a fake uptime in days (Example, 12 with NO QUOTES). This allows you to test the script and see the popup without having a machine that truly has that uptime, or without playing with the alert threshold logic. 
	#To disable, set to $null
	$TestingMachineUptimeValue = $null

#Storage and cache locations
	#This is the parent folder for us to then create other folders inside of. Try to use only one central parent folder in your organization!
	$LogFileParentFolder = "C:\Windows\AzureToTheMax"

	#The folder which will specifically be used for the cache and logging of this specific script. This includes the log file and image.
    #Note - this should be set to a different path than the user side. If they were the same, and the system created the folder, the user may not have permission to create items inside that folder. That is also why I do NOT use the ProgramData path in this system side script.
	$LogFileFolder = "C:\Windows\AzureToTheMax\RebootMaintenanceSystem"

	#The log file which will be made by this script. New data is always appending to the existing file.
	$LogFileName = "RebootMaintenanceSystem.Log"

#endregion


function New-HiddenDirectory {
	#Used to create our storage paths if they do not exist

	param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the path to create.")]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

	#Only Create our folders if they don't exist to avoid errors
	if (Test-Path $Path) {
		write-host "Log File Location folder Folder exists already."
		} else {
		New-Item $Path -ItemType Directory -force -ErrorAction SilentlyContinue > $null 
		$folder = Get-Item "$Path" 
		$folder.Attributes = 'Directory','Hidden' 
		}
}

function RebootCheck {


    If ($MachineUptimeDays -ge $MaximumUptime) {
    Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Forcing a reboot in $($ForcedRebootTime) seconds as the uptime of $($MachineUptimeDays) days is greater than or equal to the configured maximum threshold of $($MaximumUptime) days." -Force
    shutdown /r /t $ForcedRebootTime /c "This computer has not restarted in $($MachineUptimeDays) days or more and no active users were deteced on this device. This device will reboot automatically in $($ForcedRebootTime) seconds from $($starttime)."
    exit
    } else {
    Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): No action is being taken as the uptime of $($MachineUptimeDays) days is less than the configured maximum threshold of $($MaximumUptime)." -Force
    exit
    }
    
    
}
    


#Region create storage paths
#Before anything else, including starting logging, our storage paths must exist.

write-host "Calling for path creation: $($LogFileParentFolder)"
New-HiddenDirectory -Path $LogFileParentFolder

write-host "Calling for path creation: $($LogFileFolder)"
New-HiddenDirectory -Path $LogFileFolder
#Endregion

#region start logging
#Start our log now that folders/paths have been declared and created
Add-Content "$($LogFileFolder)\$($LogFileName)" "

$(get-date): System Reboot Maintenance running on $($env:COMPUTERNAME)" -Force
#endregion


#region pull system uptime
$MachineUptimeDays = (((get-date) - (gcim Win32_OperatingSystem).LastBootUpTime).Days)
Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Machine $($env:COMPUTERNAME) has been up for ($MachineUptimeDays) days." -Force
$starttime = get-date #used by the script to reference in text the end of the forced reboot timer.
#endregion

#Region testing
#This is used to override the free space we just calculated for testing puposes. See $TestingMachineUptimeValue in the variables region.
if ($null -ne $TestingMachineUptimeValue){
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Testing value is enabled and set to: $($TestingMachineUptimeValue) days" -Force
	Write-Warning "Testing value is enabled!"
	$MachineUptimeDays = $TestingMachineUptimeValue
}
#endregion


#Region Check Active Users
$users = quser

if ($users -like "*Active*"){
#If there IS an ACTIVE user close
Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): An active user was found, exiting." -Force
exit
} else {
#else - main to verify uptime and if less than one day restart
Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): No active users found, proceeding." -Force
RebootCheck 
}
#endregion