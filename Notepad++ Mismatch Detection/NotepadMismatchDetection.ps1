
<#
    .SYNOPSIS
    This script compares the Notepad++ version found in the registry with the version of the Notepad++ EXE pointed to from the registry. 
    If the versions do NOT match indicating an update failure, the script will report back an issue along with the found EXE and reg version for further inspection.
    If the versions do match, the script reports back as success and indicates the items found matched.
    If nothing is found, there is no issue, and thus the script reports as success and notes that nothing was found.
    The results are best viewed by exporting the run results from the proactive remediation. 
                
    .NOTES
    Author:      Maxton Allen
    Contact:     @AzureToTheMax
    Created:     2023-09-24
    Updated:     2023-09-24


   
Version history:
1.0:
#>
#################################################
#Region Variables
#App name
$AppName = "Notepad++"
#The name of the folder to store logs in inside. Feel free to change this. If you do, you may need to adjust line 56.
$LogFolder = "C:\Windows\AzureToTheMax\Notepad"
#The name of the log file - avoid spaces
$LogFile = "Notepad.txt"
#Endregion
#################################################


#Don't touch this.
$tracked = 0
$NonIssuetracked = 0

function New-StorageDirectory {
    #Used to create & hide the storage directory if it does not exist already
    param(
        [parameter(Mandatory = $true, HelpMessage = "Full path to the storage directory to store the marker file in.")]
        $StorageDirectory
    )


    $TestFolder = Test-Path $StorageDirectory
    if ($TestFolder -eq $false) {
    New-Item $StorageDirectory -ItemType Directory -ErrorAction SilentlyContinue > $null 
    #Set dirs as hidden
    $folder = Get-Item $StorageDirectory
    $folder.Attributes = 'Directory','Hidden' 
    }

}

#Create storage directories for logging
New-StorageDirectory -StorageDirectory "C:\Windows\AzureToTheMax"
New-StorageDirectory -StorageDirectory $LogFolder

#Set content to override any existing file content to prevent file size growth
Add-Content "$($LogFolder)\$($LogFile)" "

$(get-date): $($AppName) Detection rule starting on $($env:COMPUTERNAME)" -Force




########################################################################################################################################
########################################################################################################################################
########################################################################################################################################


#Region 64-bit
#Gather all 64-bit instances of Notepad++
$value1 = (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') | Get-ItemProperty -name 'DisplayName' -ErrorAction SilentlyContinue
$value2 = $value1 | Where-Object {$_."Displayname" -like "*$($AppName)*"} | Select-Object PSChildName -ErrorAction SilentlyContinue
$value2 = $value2.PSChildName

#Loop through all items found
$value2 | ForEach-Object {
    if ($_ -ne $null) {
        #Pull various app information
    $value3 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\" + "$($_)"

    $value5 = Get-itemproperty $value3 -name "DisplayVersion" -ErrorAction SilentlyContinue
    $ver = $value5.DisplayVersion

    $value4 = Get-itemproperty $value3 -name "Publisher" -ErrorAction SilentlyContinue
    $publisher = $value4.Publisher

    #Find the exe location using the ICO path
    $value6 = Get-itemproperty $value3 -name "DisplayIcon" -ErrorAction SilentlyContinue
    $EXELocation = $value6.DisplayIcon

    #Find the EXE version
    [string]$Fileversion = (Get-Item $EXELocation).VersionInfo.FileVersionRaw
    #Remove the tailing zero from the version.
    $Fileversion = $Fileversion.TrimEnd(".0")

    #Verify publisher
if ($publisher -eq "Notepad++ Team"){  

    #If the EXE and Registry match.
    if([version]$Fileversion -eq [version]$ver){
        
    Add-Content "$($LogFolder)\$($LogFile)" "$(get-date): Found $($AppName) 64-Bit with matching versions.
    Version: $($ver) 
    MSI code: $($_) 
    publisher: $($publisher)
    EXE Location: $($EXELocation)
    EXE Version: $($Fileversion)" -Force
    $NonIssuetracked = $NonIssuetracked + 1

 } else {
    #If the registry and EXE do NOT match
        Add-Content "$($LogFolder)\$($LogFile)" "$(get-date): Found $($AppName) 64-Bit with NON-matching versions.
        Version: $($ver) 
        MSI code: $($_) 
        publisher: $($publisher)
        EXE Location: $($EXELocation)
        EXE Version: $($Fileversion)
        Verification failed!" -Force

        $AppArray = @()

        $TempAppArray = New-Object -TypeName PSObject
        $TempAppArray | Add-Member -MemberType NoteProperty -Name "AppName" -Value "$($AppName)" -Force
        $TempAppArray | Add-Member -MemberType NoteProperty -Name "AppRegVersion" -Value "$($ver)" -Force
        $TempAppArray | Add-Member -MemberType NoteProperty -Name "MSI Code" -Value "$($_)" -Force
        $TempAppArray | Add-Member -MemberType NoteProperty -Name "Publisher" -Value "$($publisher)" -Force
        $TempAppArray | Add-Member -MemberType NoteProperty -Name "EXELocation" -Value "$($EXELocation)" -Force
        $TempAppArray | Add-Member -MemberType NoteProperty -Name "EXEVersion" -Value "$($Fileversion)" -Force
        $AppArray += $TempAppArray
 
        $tracked = $tracked + 1

    }

    } else {
        Add-Content "$($LogFolder)\$($LogFile)" "$(get-date): No 64-Bit apps found"
    }
}
}
#endregion



########################################################################################################################################
########################################################################################################################################
########################################################################################################################################



#region 32-bit
#Repeat the process for the 32-bit registry paths


$value1 = (Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') | Get-ItemProperty -name 'DisplayName' -ErrorAction SilentlyContinue
$value2 = $value1 | Where-Object {$_."Displayname" -like "*$($AppName)*"} | Select-Object PSChildName -ErrorAction SilentlyContinue
$value2 = $value2.PSChildName


$value2 | ForEach-Object {
    if ($_ -ne $null) {

        $value3 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\" + "$($_)"

        $value5 = Get-itemproperty $value3 -name "DisplayVersion" -ErrorAction SilentlyContinue
        $ver = $value5.DisplayVersion

        $value4 = Get-itemproperty $value3 -name "Publisher" -ErrorAction SilentlyContinue
        $publisher = $value4.Publisher

        $value6 = Get-itemproperty $value3 -name "DisplayIcon" -ErrorAction SilentlyContinue
        $EXELocation = $value6.DisplayIcon
    
        [string]$Fileversion = (Get-Item $EXELocation).VersionInfo.FileVersionRaw
        $Fileversion = $Fileversion.TrimEnd(".0")


if ($publisher -eq "Notepad++ Team"){  

        if([version]$Fileversion -eq [version]$ver){
        
            Add-Content "$($LogFolder)\$($LogFile)" "$(get-date): Found $($AppName) 64-Bit with matching versions.
            Version: $($ver) 
            MSI code: $($_) 
            publisher: $($publisher)
            EXE Location: $($EXELocation)
            EXE Version: $($Fileversion)" -Force
            $NonIssuetracked = $NonIssuetracked + 1
        
         }  else {
                Add-Content "$($LogFolder)\$($LogFile)" "$(get-date): Found $($AppName) 64-Bit with NON-matching versions.
                Version: $($ver) 
                MSI code: $($_) 
                publisher: $($publisher)
                EXE Location: $($EXELocation)
                EXE Version: $($Fileversion)
                Verification failed!" -Force
        
                $AppArray = @()
        
                $TempAppArray = New-Object -TypeName PSObject
                $TempAppArray | Add-Member -MemberType NoteProperty -Name "AppName" -Value "$($AppName)" -Force
                $TempAppArray | Add-Member -MemberType NoteProperty -Name "AppRegVersion" -Value "$($ver)" -Force
                $TempAppArray | Add-Member -MemberType NoteProperty -Name "MSI Code" -Value "$($_)" -Force
                $TempAppArray | Add-Member -MemberType NoteProperty -Name "Publisher" -Value "$($publisher)" -Force
                $TempAppArray | Add-Member -MemberType NoteProperty -Name "EXELocation" -Value "$($EXELocation)" -Force
                $TempAppArray | Add-Member -MemberType NoteProperty -Name "EXEVersion" -Value "$($Fileversion)" -Force
                $AppArray += $TempAppArray
         
                $tracked = $tracked + 1
        
                
        
            }


    } else {
        Add-Content "$($LogFolder)\$($LogFile)" "$(get-date): No 32-Bit apps found"

    }
}
}
#endregion

#Bring together the built app array.
[System.Collections.ArrayList]$AppArrayList = $AppArray

if ($tracked -eq 0 -and $NonIssuetracked -eq 0) {
    #Only pass through here if we NEVER went through any loop for apps found and thus no app is installed which is "success"
    #We just need to write SOMETHING to output
    Write-Host "Notepad++ was not found"
    Add-Content "$($LogFolder)\$($LogFile)" "$(get-date): $($AppName) was not found on $($env:COMPUTERNAME)" -Force
    exit 0
    }

if ($tracked -eq 0 -and $NonIssuetracked -ne 0 ){
    #If Notepad++ was found and the registry and EXE match, no issue.
    Write-Host "Notepad++ was found and the Registry and EXE match"
    Add-Content "$($LogFolder)\$($LogFile)" "$(get-date): $($AppName) was found on $($env:COMPUTERNAME) with matching registry and EXE." -Force
    exit 0

}

if ($tracked -ne 0){
    #If Notepad++ was found and the registry and EXE do NOT match. Now we have a problem.
    Write-Host "Notepad++ was found and the Registry and EXE do NOT match: $($AppArrayList)"
    Add-Content "$($LogFolder)\$($LogFile)" "$(get-date): $($AppName) was found on $($env:COMPUTERNAME) with NON-matching registry and EXE." -Force
    exit 1

}


#Should never get here, if we do exit with failure as something strange has happened.
exit 1


#>
