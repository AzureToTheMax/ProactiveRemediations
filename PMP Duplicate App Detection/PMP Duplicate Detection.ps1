#Check for duplicate Patch My PC packages

<#
.SYNOPSIS
This script checks for Patch My PC packages which have duplicated (orphaned, unassigned *copies* of apps).
This is not the same as single apps that didn't get assigned.
This is intended for use with PMP cloud and supports multiple tenants.

.Description
To achieve this we...

1) Build a list of tenants to auth to (this is MSP friendly).
2) Cycle through every tenant and pull managed apps from Intune.
3) Cycle through each app and...
    A) Confirm it is from PMP
    B) Confirm it has more than the expected count (current + n-1 count as set by $ExpectedAppCount)
4) Assemble each matching app into a table with its tenant, App Name, Count, publish dates, App IDs, and the count of the packages which are from the last 24 hours.
5) Report on the combined matching apps from all tenants and export to CSV (if enabled)


.NOTES
Author:      Maxton Allen
Contact:     @AzureToTheMax
Website: 	 AzureToTheMax.Net
Created:     10/15/26
Updated:     

            
Version history:
1 -  11/18/26 - Initial public release of script.

#>


# Global config
$export = $true #Drop to CSV
$ExportPath = ".\PMP-Duplicates.csv"

#Expected app count
#Explanation: If your default template is to always retain 2 prior copies of every app, then the expected total is 3 (N-2, N-1, N). You need to configure this as the expected total of apps.
$ExpectedAppCount = 3

#If you want to turn certain tenants on and off on certain runs for some reason
$Tenant1 = $true
$Tenant2 = $true


#Per tenant config
$TenantArray = @()

#Establish our list of tenants to cycle through and means of authing to them.
#Just copy paste as many tenants as you need and fill out each one accordingly.

#Tenant1
if($Tenant1 -eq $true){
$TenantTempArray = New-Object System.Object
$TenantTempArray | Add-Member -MemberType NoteProperty -Name "ApplicationClientId" -Value 'Tenant1-App-ID'
$TenantTempArray | Add-Member -MemberType NoteProperty -Name "ApplicationClientSecret" -Value $env:Tenant1Secret
$TenantTempArray | Add-Member -MemberType NoteProperty -Name "TenantId" -Value 'Tenant1-ID'
$TenantTempArray | Add-Member -MemberType NoteProperty -Name "TenantName" -Value "Tenant-1-ID"
$TenantArray += $TenantTempArray 
}

#Tenant2
if($Tenant2 -eq $true){
$TenantTempArray = New-Object System.Object
$TenantTempArray | Add-Member -MemberType NoteProperty -Name "ApplicationClientId" -Value 'Tenant2-App-ID'
$TenantTempArray | Add-Member -MemberType NoteProperty -Name "ApplicationClientSecret" -Value $env:Tenant2Secret
$TenantTempArray | Add-Member -MemberType NoteProperty -Name "TenantId" -Value 'Tenant2-ID'
$TenantTempArray | Add-Member -MemberType NoteProperty -Name "TenantName" -Value "Tenant-2-ID"
$TenantArray += $TenantTempArray 
}



#Declare our final results table (needs to be done outside of the loop)
$results = $null
$results = @()


#There has got to be a better way to do this but this works
foreach ($Tenant in $TenantArray) {



#  Connect to Microsoft Graph. Feel free to change this to whatever auth method you prefer. You can add needed values (certs, key vaults, etc) to the above tenant parameters and then use them in this cycling call.
$SecureClientSecret      = ConvertTo-SecureString -String $Tenant.ApplicationClientSecret -AsPlainText -Force
$ClientSecretCredential  = New-Object -TypeName System.Management.Automation.PSCredential `
                               -ArgumentList $Tenant.ApplicationClientId, $SecureClientSecret

write-host "Starting tenant $($tenant.TenantName)..." -ForegroundColor Cyan
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
$Connected = $true
try {
    Connect-MgGraph -TenantId $Tenant.TenantId -ClientSecretCredential $ClientSecretCredential | Out-Null
}
catch {
    Write-host -ForegroundColor red "Error: Authentication to $($tenant.TenantName) failed!"
    $Connected = $False
}


    if($Connected -eq $true){
    # Retrieve all apps with expanded assignments
    Write-Host "Retrieving Intune applications and assignments..." -ForegroundColor Cyan

    $graphApiVersion = "beta"
    $uri             = "https://graph.microsoft.com/$graphApiVersion/deviceAppManagement/mobileApps"

    $Apps = $null #null me out at the start of each loop
    $response = $null #null me out at the start of each loop
    $apps = @()
    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        $apps    += $response.Value
        $uri      = $response.'@odata.nextLink'
    } while ($uri)

    Write-Host "  Found $($apps.Count) apps total." -ForegroundColor Green


    # Process each app
    Write-Host "Searching for bad apps..." -ForegroundColor Cyan


    $AppsFiltered = $null #null me out at the start of each loop

    #group our apps by name.
    $AppsFiltered = $apps | Group-Object -Property displayName

    #cycle through all apps to identify oddballs.
    $App = $null #null me out at the start of each loop
        foreach ($app in $AppsFiltered) {


            if ($app.Count -le $ExpectedAppCount) { continue } #I read backwards. It's really if I'm X or more. Otherwise, then we don't violate our limit, and can ignore this app.
            if ($app.group.installCommandLine -notlike "*PatchMyPC*") { continue } #I read backwards. Where it's a PMP app (determined via command line).

            write-host "App $($app.Name) appears to have too many copies - $($App.count)" -ForegroundColor Yellow

            #I want to specifically call out duplicates made in the last 24 hours.
            $Flag2 = 0
            foreach ($Date in $app.group.createdDateTime){
                if([datetime]$Date -ge ((get-date).adddays(-1))){
                    $Flag2 = $flag2+1
                }
            }

            #Form a new table of data I actually want
            $TempArray = $null
            $TempArray = New-Object System.Object
            $TempArray | Add-Member -MemberType NoteProperty -Name "Tenant" -Value "$($tenant.TenantName)"
            $TempArray | Add-Member -MemberType NoteProperty -Name "App Name" -Value "$($app.Name)"
            $TempArray | Add-Member -MemberType NoteProperty -Name "Count" -Value "$($app.Count)"
            $TempArray | Add-Member -MemberType NoteProperty -Name "Publish Dates" -Value "$($app.group.createdDateTime)"
            $TempArray | Add-Member -MemberType NoteProperty -Name "AppIDs" -Value "$($app.group.ID)"
            $TempArray | Add-Member -MemberType NoteProperty -Name "24-Hour-Count" -Value $flag2


            #Bring our table in
            $results += $TempArray

            
        } #complete our app loop
    } #complete our graph connected loop

Write-Host "Completing tenant $($tenant.TenantName)." -ForegroundColor Cyan
Disconnect-MgGraph | Out-Null

} #Complete our per tenant loop


#if we found something to report on
if($results.Count -gt 0){

    # Export results if enabled
    if ($export -eq $true){
    $results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    }

# Console preview
Write-Host ""
Write-Host "Final Report:" -ForegroundColor Red
$results | Format-Table | out-string | Write-Host -ForegroundColor Red
Write-host "Final count is $($results.Count)"

} else {

    Write-Host -ForegroundColor Green "No duplicate apps found."
}

