#Check for Missing MSIs
<#
.SYNOPSIS
This script is designed to check for MSI files that are effectively missing (the registry expects to be present, but are not), which can cause the MSIInstaller error 1612 when attempting to uninstall or update the given app.


.Description
To achieve this, we query...
HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\XXXXX\Products
Scan through all products, check if the MSI exists, and report back. To be clear, this script does NOT fix the issue, simply report back what is missing. See the article on my blog AzureToTheMax.net over error 1612 for details.

This is designed to be deployed as a Proactive Remediation. Results can be gathered via exporting the Device Status results of running the remediation and checking the "PreRemediationDetectionScriptOutput" column.

Note that results which are too long will be cut off. This is why the total is at the end. If the total is a high number, that device likely cannot reasonably be fixed.


.NOTES
Author:      Maxton Allen
Contact:     @AzureToTheMax
Website: 	 AzureToTheMax.Net
Created:     7/31/25
Updated:     1/10/26

            
Version history:
1 -  1/10/26 - Initial public release of script.

#>


#Start Script


#Variables
$Verbose_Logging = $True #Enabled more console logging. Enable this for local testing or running on one device to see detailed status. Disable when deploying via Intune as a PR or your exported output will be mangled.





#Create our storage array for apps with a missing MSI cache
$MissingProducts = @()

#locate all our users, select the name, and remove the start of the registry path (always same length)
$AllUsers = (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\").Name.Substring(80)

#start cycling through users
$AllUsers | ForEach-Object {

    $CurrentUser = $_ #Yes we really need to pull this into a variable and not use $_
    #Get all products under the current user
    $Products = (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\$($CurrentUser)\Products").Name

    #Clean our product list
    $CleanedProducts = @() #create empty array
    $Products  | ForEach-Object{
    $CleanedProducts += $_.Substring($_.Length - 32) #scrub off everything except the last 32 digits
    } 

    #start cycling through all of the products found under the user we are currently under
    $CleanedProducts | ForEach-Object {

        #Check to see if this product even has values (ignore empties)
        $CheckProductPath = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\$($CurrentUser)\Products\$($_)\InstallProperties"
        if($CheckProductPath -eq $true){

            #Get the properties of the current product. This is why we need $CurrentUser as now $_ has changed.

            #Get the name
            $ProductName = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\$($CurrentUser)\Products\$($_)\InstallProperties").DisplayName

            #Get the full package path to test
            $ProductLocalPackage = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\$($CurrentUser)\Products\$($_)\InstallProperties").LocalPackage

            #Remove unneeded text from the path for logging (used if path fails to be found and is thus missing)
            $ProductLocalPackageFile = split-path $ProductLocalPackage -leaf

            #get the version
            $ProductVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\$($CurrentUser)\Products\$($_)\InstallProperties").DisplayVersion

            #Test our path (Does the MSI exist as it should per the registry)
            $TestResult = Test-Path $ProductLocalPackage -ErrorAction SilentlyContinue #yes do this outside of the if statement so we can ignore error
            if($TestResult -eq $true){
                #Yes it exists, this is good.
                If ($Verbose_Logging -eq $true) {write-host -ForegroundColor Green "$($ProductName) version $($ProductVersion) with path $($ProductLocalPackage) correctly present."}

                } else {
                #The MSI is missing, this is bad.
                If ($Verbose_Logging -eq $true) {Write-Host -ForegroundColor Red "$($ProductName) version $($ProductVersion) is missing MSI source at $($ProductLocalPackage)"}
                $MissingProducts += "$($ProductName), $($ProductVersion), $($ProductLocalPackageFile)"

                #If needed, use this version to report only the product name. This is less text, and can thus be used to confirm the full list in high count scenarios (text is too long with all details).
                #$MissingProducts += "$($ProductName), $ProductVersion, $($ProductLocalPackageFile)"


            }

        } else {
        If ($Verbose_Logging -eq $true) {Write-host "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\$($CurrentUser)\Products\$($_)\InstallProperties does not exist" -ForegroundColor Yellow}

        }
    }
}


#Construct our final output
$TotalMissingMSI = $MissingProducts.Count
$finalmissingproducts = $MissingProducts -join " - "

if ($MissingProducts.count -eq 0){
    write-host "No missing MSI files were found."
    exit 0
    } else {
    write-host "Missing MSI's for: $($finalmissingproducts) - Total: $($TotalMissingMSI)"
    exit 1
    }

