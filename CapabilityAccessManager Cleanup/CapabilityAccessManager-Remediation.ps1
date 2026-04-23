#Check size of "C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityAccessManager.DB-wal"


<#
.SYNOPSIS
This is a script designed to be deployed as an Intune remediation (detection script only) to report back on the size of the "C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityAccessManager.DB-wal" file.
It will report as failed if the file is over a certain size.

.Description
This is a simple file size query and determination of worst size.

See article: https://azuretothemax.net/2026/04/22/out-of-control-capabilityaccessmanager-db-wal-file-size/

.NOTES
Author:      Maxton Allen
Contact:     @AzureToTheMax
Website: 	 AzureToTheMax.Net
Created:     4/22/2026
Updated:     
            
Version history:
1 -  4/22/2026 - Initial public release of script.

#>

#Max file size in MB
#Note, as of writing, the expected size is not yet known. The current median is 550 MB.
$MaxSize = 1024.00 #leave my decimal points in

#Get the size of the DB file
$DBSize = "{0:N2}" -f ((Get-Item "C:\ProgramData\Microsoft\Windows\CapabilityAccessManager\CapabilityAccessManager.DB-wal").Length / 1MB)

#If the size is over $MaxSize MB (default is 1024 MB, or 1 GB), exit with failure. Leave it as gt. PowerShell doesn't like eq, including ge, with decimals apparently, so leave it as gt.
if($DBSize -gt $MaxSize){
    #File is over max size
    write-host "$DBSize" #Note that the write-host lacks anything but the data value (no "MB", etc). When exported, you simply need to know this is in MB. This is done for easy Excel sorting.
    exit 1
} else {
    #File is under max size
    write-host "$DBSize" #Note that the write-host lacks anything but the data value (no "MB", etc). When exported, you simply need to know this is in MB. This is done for easy Excel sorting.
    exit 0
}
