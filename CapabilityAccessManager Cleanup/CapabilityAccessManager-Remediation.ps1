#Delete "C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityAccessManager.DB-wal" to reset it's size


<#
.SYNOPSIS
This is a script designed to be deployed as an Intune Win32 app which deletes the "C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityAccessManager.DB-wal" to reset it's space consumption.

.Description
This is a script designed to be deployed as an Intune Win32 app which deletes the "C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityAccessManager.DB-wal" to reset it's space consumption.
Deployment as an app allows employees to self service (or have your help desk control it through a group as available or required).
It can also be deployed as an Intune remediation. This can then either be a detection-only which is run on demand, or tied to the "CapabilityAccessManager-Detection" for automatic remediation (be careful with your limit!)

See article: 

.NOTES
Author:      Maxton Allen
Contact:     @AzureToTheMax
Website: 	 AzureToTheMax.Net
Created:     4/22/2026
Updated:     
            
Version history:
1 -  4/22/2026 - Initial public release of script.

#>


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


#Region Configure paths
    #Storage and cache locations
	$LogFileParentFolder = "C:\Windows\DE"

	#The folder which will specifically be used for the cache and logging of this specific script. This includes the log file and image.
	$LogFileFolder = "C:\Windows\DE\CapabilityAccessManager"

	#The log file which will be made by this script. New data is always appending to the existing file.
	$LogFileName = "CapabilityAccessManager-Cleanup"
    #Make the log name above contain the date, time, and .Log. This makes it such that each execution is it's own log file, rather than generating one massive file.
    $LogFileName = $LogFileName+$FileDate+".Log"

#Endregion

#Region Create storage paths
    #Before anything else, including starting logging, our storage paths must exist.

    write-host "Calling for path creation: $($LogFileParentFolder)"
    New-HiddenDirectory -Path $LogFileParentFolder

    write-host "Calling for path creation: $($LogFileFolder)"
    New-HiddenDirectory -Path $LogFileFolder

#Endregion


#Start logging

    Add-Content "$($LogFileFolder)\$($LogFileName)" "

$((Get-Date).ToUniversalTime()): CapabilityAccessManager cleanup running on $($env:COMPUTERNAME)" -Force

#Check current size
$DBSizeStart = "{0:N2}" -f ((Get-Item "C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityAccessManager.DB-wal").Length / 1MB)
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Current CapabilityAccessManager.DB-wal size: $($DBSizeStart) MB"

#Cleanup script
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Stop the 'Capability Access Manager Service'"
$id = Get-WmiObject -Class Win32_Service -Filter "Name='camsvc'" | Select-Object -ExpandProperty ProcessId
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Found service with process id: $id"
$process = Get-Process -Id $id
Stop-Process $process.Id -Force -Verbose
Start-Sleep 5 -Verbose
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Stop the 'SuperFetch (SysMain) Service'"
$id = Get-WmiObject -Class Win32_Service -Filter "Name='SysMain'" | Select-Object -ExpandProperty ProcessId
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Found service with process id: $id"
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Stop the 'Geolocation Service'"
$id = Get-WmiObject -Class Win32_Service -Filter "Name='lfsvc'" | Select-Object -ExpandProperty ProcessId
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Found service with process id: $id"
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Delete the large files from: 'C:\ProgramData\Microsoft\Windows\CapabilityAccessManager'"
Remove-Item "C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\*"
Start-Sleep 5 -Verbose
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Re-start the 'Capability Access Manager Service'"
Start-Service -Name "camsvc"
Start-Sleep 5 -Verbose
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Re-start the 'SuperFetch (SysMain) Service'"
Start-Service -Name "SysMain"
Start-Sleep 5 -Verbose
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Re-start the 'Geolocation Service'"
Start-Service -Name "lfsvc"
Start-Sleep 5 -Verbose

#Check final size
start-sleep -Seconds 10
$DBSizeEnd = "{0:N2}" -f ((Get-Item "C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityAccessManager.DB-wal").Length / 1MB)
$SavedSpace = $DBSizeStart - $DBSizeEnd
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Final CapabilityAccessManager.DB-wal size: $($DBSizeEnd) MB"
Add-Content "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Space reclaimed: $($SavedSpace) MB"
Write-Host "$($LogFileFolder)\$($LogFileName)" "$((Get-Date).ToUniversalTime()): Initial CapabilityAccessManager.DB-wal size: $($DBSizeStart) MB. Final CapabilityAccessManager.DB-wal size: $($DBSizeEnd) MB. Space reclaimed: $($SavedSpace) MB."