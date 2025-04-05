#Windows Endpoint Automatic Reboot Maintenance - User Side

<#
.SYNOPSIS
This script is designed to check the current uptime of a Windows Endpoint machine. If the value exceeds a minimum threshold, an optional reminder prompt is sent to the employee asking them to reboot. If the value exceeds a maximum threshold, the machine will be forced to reboot after a chosen timer.

.Description
1. Load necessary assemblies and hide our script window (not that it's visible when ran from Intune anyways)
2. Read our configurable variables
3. Declare our functions (some of which rely on the variables we just declared)
4. Create our logging directories and start logging
5. Check for the existence of the image. If not present, download it or create it from Base64. If present, validate the hash and recreate or redownload as needed.
6. Check the device uptime
7. Declare our windows form and MOST components
8. Determine if we need to now present a form/popup (yes this order is weird, leave it be). This uses our minimum and maximum defined times to determine if a popup should be thrown, and sets the final popup properties to configure which behaviour it will follow.
9. Throw the popup if applicable
10. The script ends when either the popup does not need to be presented, the user chooses to reboot, the user chooses to close the popup, the timeout ends, or the forced reboot countdown ends.

.NOTES
Author:      Maxton Allen
Contact:     @AzureToTheMax
Website: 	 AzureToTheMax.Net
Created:     03/30/2025
Updated:     

            
Version history:
1 -  03/30/2025 - Script created using the 10/12/2024 edition of Automatic Disk Space alerts as the basis.

#>


#Start Script


#region Hide PowerShell Console (this is likely redundant when ran through Proactive Remedations)
#You may want to comment this out for manual testing as well.
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0)
#endregion


# Interface Definitions & Assemblies (neded so you can do things like [System.Drawing.Color] in our variable section)
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")



#Region Variables
#This region contains the primary configurable variables.

#Uptime Thresholds
	#The minimum amount of uptime in days for the device to have which results in an optional prompt. This is greater than or equal to.
	$MinimumUptime = "5"

	#The maximum amount of uptime in days. Being at or breaking this threshold results in a forced prompt. This is greater than or equal to.
	$MaximumUptime = "10"

	#The amount of time in seconds after which the machine will forcibly reboot if it exceeded the Maximum-Uptime above. Default is 900 (15 minutes). Do NOT set this higher than the $TimeOutDuration.
	$ForcedRebootTime = 900

	#Testing value
	#Use this to set a fake uptime in days (Example, 12 with NO QUOTES). This allows you to test the script and see the popup without having a machine that truly has that uptime, or without playing with the alert threshold logic. 
	#When ran through ISE or visual studio code manual, this will tick down too fast. This does not happen when executed from Intune.
	#To disable, set to $null
	$TestingMachineUptimeValue = $null


#Text customization
<#
For the main message, see "$richTextBox1.Text" - Note that this is set in two places depending on which threshold was violated as the dialogue needs to shift for those two possibilities
For the Reboot Now button message, see "$btn2.Text"
For the Close button message, see "$btn1.Text"
#>

#Automatic Timeout
	#This autoclose is used on the OPTIONAL reboot as a means to avoid the 60 minute remediation timeout. It is automatically hidden if the machine exceeds the maximum value as having two timers would be confusing.
	#Show Auto Close Timer (only applicable to optional reboot popup)
	$AutoCloseVisible = $true

	#timeout period in seconds
	$TimeOutDuration = 2700 #default is 2700 (45 minutes). Do NOT set it higher than 55 minutes. When ran through ISE or visual studio code manual, this will tick down too fast. This does not happen when executed from Intune.
	

#Storage and cache locations
	#Note that items are stored in C:\ProgramData unlike my typical C:\Windows because this script must execute as the logged in user, and thus we need to store logs in a standard user accessible location.
	#This is the parent folder for us to then create other folders inside of. Try to use only one central parent folder in your organization!
	$LogFileParentFolder = "C:\programdata\AzureToTheMax"

	#The folder which will specifically be used for the cache and logging of this specific script. This includes the log file and image.
	$LogFileFolder = "C:\programdata\AzureToTheMax\RebootMaintenance"

	#The log file which will be made by this script. New data is always appending to the existing file.
	$LogFileName = "RebootMaintenance.Log"

#Branding and Customization

	#Do you want to download the image from the below URL or create the image from self-contained base64 code (see $ImageB64)? (only one can be true)
	$UseImageDownload = $false
	$UseBase64Image = $true

	#The URL to your image IF you are using $UseImageDownload (by default the image should be 175x175)
	$Imageurl = "https://github.com/AzureToTheMax/ProactiveRemediations/blob/642cb6e965bb9cb72f3b5f5db32498045c92b8a0/Disk%20Space%20Notifications/CompanyLogo.png?raw=true"

	#If using a Base64 image, see the region "Region Base64 image" (CTRL+F) and use the tool there to both collect ands et the value of base 64. Again, use a small 175x175 image.

	#The image hash (updating this lets you signal the app to recreate or redownload the file if it does not match for one reason or another)
	$ImageHash = "B9CB4EC458AA22B48984B2D684EA3D8D14307D2E93BCADB83792B2F9D13CFF8C"
	#Use this to get your image hash
	# Get-SuperFileHash -HashFilePath "$($LogFileFolder)\CompanyLogo.png"

	#The main background color (does not include text box). This is Alpha, Red, Green, Blue numeric. Leave the alpha at 255. Plenty of online tools like https://rgbacolorpicker.com/
	$RebootPromptFormBackgroundColor = [System.Drawing.Color]::FromArgb(255,0,3,32)

	#Button Background Color
	$ButtonBackgroundColor = [System.Drawing.Color]::FromArgb(255,0,198,243)

	#Button text color
	$ButtonTextColor = [System.Drawing.Color]::FromArgb(255,0,0,0)

	#Text box background color
	$TextBoxBackgroundColor = [System.Drawing.Color]::FromArgb(255,0,3,32)

	#Text Box text color
	$TextBoxTextColor = [System.Drawing.Color]::FromArgb(255,255,255,255)
	


#endregion

#Region Functions
Function Get-SuperFileHash {
#Since get-filehash doesn't work in all PS versions...

param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the path to file.")]
        [ValidateNotNullOrEmpty()]
        [string]$HashFilePath
    )

	#Try the normal way
	$ReturnedValue = Get-FileHash $HashFilePath -ErrorAction SilentlyContinue
	$ReturnedValue = $ReturnedValue.Hash

	#If its null, do this madness.
	if ($null -eq $ReturnedValue){
		#Write-Error "get-filehash failed"
	$item = Get-ChildItem $HashFilePath
	$stream = new-object system.IO.FileStream($item.fullname, "Open", "Read", "ReadWrite")
			if ($stream)
					{
						$sha = new-object -type System.Security.Cryptography.SHA256Managed
						$bytes = $sha.ComputeHash($stream)
						$stream.Dispose()
						$stream.Close()
						$sha.Dispose()
						$checksum = [System.BitConverter]::ToString($bytes).Replace("-", [String]::Empty).ToLower();
						$ReturnedValue = $checksum
					}
	}
	return $ReturnedValue

}



Function RebootPrompt {
	#Calls our form to execute
	[System.Windows.Forms.Application]::EnableVisualStyles()
	[System.Windows.Forms.Application]::Run($RebootPromptForm)

	
}

function button_click {
	#What our close button does
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): $($env:USERNAME) closing popup without rebooting." -Force
	$RebootPromptForm.Close()
	$RebootPromptForm.Dispose()
	exit 1 #Exit with a bad status so this device shows a problem in Proactive remediation's report
}

function button2_click {
	#What our reboot now button does
	$RebootPromptForm.Close()
	$RebootPromptForm.Dispose()
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): $($env:USERNAME) has chosen the optional reboot. This unit will reboot in one minute." -Force
	shutdown /r /t 60 /C "Chosen reboot - This device wil restart in one minute." #Fun fact, this shutdown comment will show in the event log
	exit
}

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


Function CountDown {
    
    #Ticks the text down by one
    $timeRemaining.text = $timeRemaining.text - 1
    #Update HHMMSS
    $HHMMSS = [timespan]::fromseconds($timeremaining.text)
    #set the label text back

	#Testing to see just how long it can really go without a timeout.
	#Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Timer is still ticking, now at $($HHMMSS)" -Force

	if ($AutoCloseVisible -eq $true){
    $Countdown_Label.Text = "Auto Close: $("{0:mm\:ss}" -f $HHMMSS)"
	}
    
	If ($timeRemaining.Text -eq 0) {
        $timer.Stop()
        Timer_Over
	}

}

Function Timer_Over {
	# this is used to gracefully close the popup if it times out.
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Popup is timing out." -Force
	write-error "$(get-date): Popup is timing out." #write this so the info returns to proactive remediation (visible in device detailed run export)
	$RebootPromptForm.Close()
	$RebootPromptForm.Dispose()
	exit 1 #Exit with a bad status so this device shows a problem in Proactive remediation's
}


Function ForcedRebootCountDown {
    
    #Ticks the text down by one
    $timeRemainingForcedReboot.text = $timeRemainingForcedReboot.text - 1
    #Update HHMMSS
    $HHMMSS = [timespan]::fromseconds($timeRemainingForcedReboot.text)
    #set the label text back


    $Countdown_Label2.Text = "Time remaining before forced reboot: $("{0:mm\:ss}" -f $HHMMSS)"
    
	If ($timeRemainingForcedReboot.Text -eq 0) {
        $timer.Stop()
        ForcedRebootCountDown_Over
	}

}

Function ForcedRebootCountDown_Over {
	# This is used to forcefully reboot the machine
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Forced reboot countdown reached. The device will restart in one minute." -Force
	$RebootPromptForm.Close()
	$RebootPromptForm.Dispose()
	shutdown /r /t 60 /C "Forced reboot - This device wil restart in one minute." #Fun fact, this shutdown comment will show in the event log
	exit 1 #Exit with a bad status so this device shows a problem in Proactive remediation's
}

#endregion



#Startscript
#Clear any running form (mostly a testing problem). We don't need to actually catch anything, ignoring errors just doesn't work on this command.
try { $RebootPromptForm.Close(); $RebootPromptForm.Dispose() } catch {}

#Region create storage paths
#Before anything else, including starting logging, our storage paths must exist.

write-host "Calling for path creation: $($LogFileParentFolder)"
New-HiddenDirectory -Path $LogFileParentFolder

write-host "Calling for path creation: $($LogFileFolder)"
New-HiddenDirectory -Path $LogFileFolder

#Endregion


#Start our log now that folders/paths have been declared and created
Add-Content "$($LogFileFolder)\$($LogFileName)" "

$(get-date): Reboot Maintenance running as $($env:USERNAME) on $($env:COMPUTERNAME)" -Force

Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Timeout is set to $($TimeOutDuration) seconds." -Force

#check the configuration of our image settings.
if ($UseImageDownload -eq $true -and $UseBase64Image -eq $true) {
Write-Error "You cannot have both UseImageDownload and UseBase64Image set to true!"
Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Error: You cannot have both UseImageDownload and UseBase64Image set to true!" -Force
exit 1
}

#Region download image
if ($UseImageDownload -eq $true){
	#Check if the image is present
	if (Test-Path "$($LogFileFolder)\CompanyLogo.png"){
		#If yes, check the hash.
		$CalculatedImageHash = Get-SuperFileHash -HashFilePath "$($LogFileFolder)\CompanyLogo.png"

		#Check if the hash matches
			if ($CalculatedImageHash -eq $ImageHash){
			#The hash does match
			Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Image -$($LogFileFolder)\CompanyLogo.png- is present and has a matching hash." -Force

			} else {
			#The hash does not match
			Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Warning: Image -$($LogFileFolder)\CompanyLogo.png- is present but the hash does not match, fixing!" -Force
			Write-Warning "$(get-date): Warning: Image -$($LogFileFolder)\CompanyLogo.png- is present but the hash does not match, fixing!"

			#This automatically overrides existing files
			Invoke-WebRequest $Imageurl -OutFile "$($LogFileFolder)\CompanyLogo.png"

				#Check that it worked
				$RecheckCalculatedImageHash = Get-SuperFileHash -HashFilePath "$($LogFileFolder)\CompanyLogo.png"

				if ((Test-Path "$($LogFileFolder)\CompanyLogo.png") -and $RecheckCalculatedImageHash -eq $ImageHash){
				Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Image -$($LogFileFolder)\CompanyLogo.png- file download completed and has corrected."
				} else {
				Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Warning: Image -$($LogFileFolder)\CompanyLogo.png- file creation completed but the file was not detected and/or hash is still not correct!
				Detected hash: $($RecheckCalculatedImageHash)
				Expected hash: $($ImageHash)"
				Write-Warning "$(get-date): Warning: Image -$($LogFileFolder)\CompanyLogo.png- file creation completed but the file was not detected and/or hash is still not correct!
				Detected hash: $($RecheckCalculatedImageHash)
				Expected hash: $($ImageHash)"
				}
			}

	} else {
	#False - Image is not present, download the image
	write-host "Image not present, downloading" -ForegroundColor Yellow
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Image -$($LogFileFolder)\CompanyLogo.png- is NOT present, downloading." -Force
	
	#Download
	Invoke-WebRequest $Imageurl -OutFile "$($LogFileFolder)\CompanyLogo.png"

	#Check that it worked
	$RecheckCalculatedImageHash = Get-SuperFileHash -HashFilePath "$($LogFileFolder)\CompanyLogo.png"
	$Checkpath = Test-Path "$($LogFileFolder)\CompanyLogo.png" #It does not like having this combined with -and directly

	if ($Checkpath -eq $true -and $RecheckCalculatedImageHash -eq $ImageHash){
		Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Image -$($LogFileFolder)\CompanyLogo.png- file download completed and hash correct."
		} else {
		Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Warning: Image -$($LogFileFolder)\CompanyLogo.png- file creation completed but the file was not detected and/or hash is still not correct!"
		Write-Warning "$(get-date): Warning: Image -$($LogFileFolder)\CompanyLogo.png- file creation completed but the file was not detected and/or hash is still not correct!"
		}
	}
}
#endregion



#Region Base64 image
if ($UseBase64Image -eq $true){

	#Use me to get the base64 bytes of your image
	<#
	$image_path = "$($LogFileFolder)\CompanyLogo.png"
	$b64 = [convert]::ToBase64String((get-content $image_path -AsByteStream -Raw))
	write-host $b64 -ForegroundColor Green
	#>

	#Our Base64 encoded image (companylogo.png)
	$ImageB64 = "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"


	#Check if the image is present
	if (Test-Path "$($LogFileFolder)\CompanyLogo.png"){
		#Check the hash if it is present
		$CalculatedImageHash = Get-SuperFileHash -HashFilePath "$($LogFileFolder)\CompanyLogo.png"

		#Check if the hash matches
			if ($CalculatedImageHash -eq $ImageHash){
			#The hash does match
			Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Image -$($LogFileFolder)\CompanyLogo.png- is present and has a matching hash." -Force
			} else {
			#The hash does not match
			Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Warning: Image -$($LogFileFolder)\CompanyLogo.png- is present but the hash does not match, fixing!" -Force
			Write-Warning "$(get-date): Warning: Image -$($LogFileFolder)\CompanyLogo.png- is present but the hash does not match, fixing!"

			#Create image from B64
			$filename = "$($LogFileFolder)\CompanyLogo.png"
			$bytes = [Convert]::FromBase64String($ImageB64)
			[IO.File]::WriteAllBytes($filename, $bytes)

				#Check that it worked
				$RecheckCalculatedImageHash = Get-SuperFileHash -HashFilePath "$($LogFileFolder)\CompanyLogo.png"

				$Checkpath = Test-Path "$($LogFileFolder)\CompanyLogo.png" #It does not like having this combined with -and directly


				if ($Checkpath -eq $true -and $RecheckCalculatedImageHash -eq $ImageHash){
				Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Image -$($LogFileFolder)\CompanyLogo.png- file Base64 creation completed and has corrected."
				} else {
				Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Warning: Image -$($LogFileFolder)\CompanyLogo.png- Base64 file creation completed but the file was not detected and/or hash is still not correct!
				Detected hash: $($RecheckCalculatedImageHash)
				Expected hash: $($ImageHash)"
				Write-Warning "$(get-date): Warning: Image -$($LogFileFolder)\CompanyLogo.png- Base64 file creation completed but the file was not detected and/or hash is still not correct!
				Detected hash: $($RecheckCalculatedImageHash)
				Expected hash: $($ImageHash)"
				}
			}

	} else {
	#False - Image is not present, create the image
	write-host "Image not present, creating from Base64" -ForegroundColor Yellow
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Image -$($LogFileFolder)\CompanyLogo.png- is NOT present, creating from Base64." -Force
	
	#Create image from B64
	$filename = "$($LogFileFolder)\CompanyLogo.png"
	$bytes = [Convert]::FromBase64String($ImageB64)
	[IO.File]::WriteAllBytes($filename, $bytes)

	#Check that it worked
	$RecheckCalculatedImageHash = Get-SuperFileHash -HashFilePath "$($LogFileFolder)\CompanyLogo.png"

	if (Test-Path "$($LogFileFolder)\CompanyLogo.png" -and $RecheckCalculatedImageHash -eq $ImageHash){
		Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Image -$($LogFileFolder)\CompanyLogo.png- file creation from Base64 completed."
		} else {
		Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Warning: Image -$($LogFileFolder)\CompanyLogo.png- file creation from Base64 completed but the file was not detected and/or hash is still not correct!"
		Write-Warning "$(get-date): Warning: Image -$($LogFileFolder)\CompanyLogo.png- file creation from Base64 completed but the file was not detected and/or hash is still not correct!"
		}
	}
}
#endregion


#region pull system uptime
$MachineUptimeDays = (((get-date) - (gcim Win32_OperatingSystem).LastBootUpTime).Days)
Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Machine $($env:COMPUTERNAME) has been up for ($MachineUptimeDays) days." -Force
$starttime = get-date #used by the script to reference in text the end of the forced reboot timer.
#endregion

#Region testing
#This is used to override the free space we just calculated for testing purposes. See $TestingMachineUptimeValue in the variables region.
if ($null -ne $TestingMachineUptimeValue){
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Testing value is enabled and set to: $($TestingMachineUptimeValue) days" -Force
	Write-Warning "Testing value is enabled!"
	$MachineUptimeDays = $TestingMachineUptimeValue
}
#endregion



#region main form setup
# This is where our new Windows Form popup is defined in terms of overall style and dimension.
$RebootPromptForm = New-Object System.Windows.Forms.Form
#$RebootPromptForm.MaximumSize = New-Object System.Drawing.Size(800, 450) #This is defined individually in the two sections that determine what variant of the popup should be tossed as they are not the same size.
#$RebootPromptForm.MinimumSize = New-Object System.Drawing.Size(800, 450) #This is defined individually in the two sections that determine what variant of the popup should be tossed as they are not the same size.
$RebootPromptForm.MaximizeBox = $false
$RebootPromptForm.MinimizeBox = $false
$RebootPromptForm.TopMost = $True
$RebootPromptForm.TopLevel = $True
$RebootPromptForm.StartPosition = "CenterScreen"
$RebootPromptForm.Text = "Reboot Maintenance"


# see variables section to change me!
$RebootPromptForm.BackColor = $RebootPromptFormBackgroundColor


#We don't want this to be closeable in non-logging ways. So, we will hide the normal means of closing such a popup such that employees are forced to click our close button which does log the action.
#Hide the X out option.
$RebootPromptForm.ControlBox = $false
#Hide on taskbar such that it cannot be closed by right-clicking it on the task bar and hitting close
$RebootPromptForm.ShowInTaskbar = $false
#endregion



#region Close button
#This defines our close button, where it is, and what options it has. What it does when clicked is defined by "function button_click".
$btn1 = New-Object System.Windows.Forms.Button
$btn1.DataBindings.DefaultDataSourceUpdateMode = 0
$btn1.Font = New-Object System.Drawing.Font("Aptos",12,[System.Drawing.FontStyle]::Bold)
$btn1.Name = "btn1"
$btn1.Size = New-Object System.Drawing.Size(250, 50)
$btn1.TabIndex = 0
$btn1.TabStop = $False
$btn1.Text = "Close"
$btn1.UseVisualStyleBackColor = $True
$btn1.BackColor = $ButtonBackgroundColor #See the variables region to change me!
$btn1.ForeColor = $ButtonTextColor #See the variables region to change me!
# On click call function to close popup
$btn1.add_Click{
button_click
}
#endregion


#Region Reboot Now
#This defines our reboot now optional button
$btn2 = New-Object System.Windows.Forms.Button
$btn2.DataBindings.DefaultDataSourceUpdateMode = 0
$btn2.Font = New-Object System.Drawing.Font("Aptos",12,[System.Drawing.FontStyle]::Bold)
$btn2.Name = "btn2"
$btn2.Size = New-Object System.Drawing.Size(250, 50)
$btn2.TabIndex = 0
$btn2.TabStop = $False
$btn2.Text = "Reboot Now"
$btn2.UseVisualStyleBackColor = $True
$btn2.BackColor = $ButtonBackgroundColor #See the variables region to change me!
$btn2.ForeColor = $ButtonTextColor #See the variables region to change me!
# On click call function to reboot now
$btn2.add_Click{
button2_click
}
#endregion

#region information message
$richTextBox1 = New-Object System.Windows.Forms.RichTextBox
#background color. Only works if enabled. (see $richTextBox1.Enabled)

$richTextBox1.BackColor = $TextBoxBackgroundColor #See the variables region to change me!
$richTextBox1.ForeColor = $TextBoxTextColor #See the variables region to change me!
$richTextBox1.DataBindings.DefaultDataSourceUpdateMode = 0

#If you enable this ($true), make sure you also leave "ReadOnly" enabled otherwise you can edit the text in the box.
#The upside to enabling this is that you can control the fields background color, otherwise it will just be the default grey.
#The downside is that there is a cursor visible at the start and text can be highlighted. Although, being able to highlight and copy paste the email address is nice.
$richTextBox1.Enabled = $true

#readonly prevents changes. Read only is really only needed if the above is false.
$richTextBox1.ReadOnly = $true 

#Sets the border of our text box to none
$richTextBox1.BorderStyle = "none"

$richTextBox1.Font = New-Object System.Drawing.Font("Aptos",12, [System.Drawing.FontStyle]::Bold)
$richTextBox1.Location = New-Object System.Drawing.Point(60, 195)
$richTextBox1.Size = New-Object System.Drawing.Size(670, 220)
#$richTextBox1.Location = $System_Drawing_Point
$richTextBox1.Name = "richTextBox1"
#$richTextBox1.Size = $System_Drawing_Size
$richTextBox1.TabIndex = 2

#Enable URL detection such that URLS can be inserted and clickable in the text box.
#You can use this if you want however, it requires an ugly full URL in the box and, you will have no logging that they clicked it. This is why we use a button to launch or URL instead. (More so angled towards the original disk space alerts which had a help button that launched a URL)
$richTextBox1.DetectUrls = $True

#center text
$richTextBox1.SelectionAlignment= "Center"

#endregion




#region picture

#Check our image dimensions for some automatic math
$imageFile = "$($LogFileFolder)\CompanyLogo.png"
Add-Type -AssemblyName System.Drawing
$image = New-Object System.Drawing.Bitmap $imageFile
$imageWidth = $image.Width
$imageHeight = $image.Height

if ($imageWidth -gt 500 -or $imageHeight -gt 175){
	Write-Warning "This image may be too large for the default form layout."
}


$pictureBox1 = New-Object System.Windows.Forms.PictureBox
$pictureBox1.BackgroundImage = [System.Drawing.Image]::FromFile("$($LogFileFolder)\CompanyLogo.png")
$pictureBox1.BackgroundImageLayout = 2
$pictureBox1.DataBindings.DefaultDataSourceUpdateMode = 0
$pictureBox1.Location = New-Object System.Drawing.Point(((800/2)-($imageWidth/2)), 10) #To get a centered result, this is your page width (800 by default) divided by two, minus half your image width.
$pictureBox1.Size = New-Object System.Drawing.Size(175, 175)
#$picturebox1.SizeMode = "centerimage"
$pictureBox1.Name = "pictureBox1"
$pictureBox1.TabIndex = 1
$pictureBox1.TabStop = $False
#endregion

#Region Time tracking
#Converts the time-remaning seconds value into a tracked time remaining. This is easier to pass through a in-between variable than to pipe directly to the countdown text.
$HHMMSS = [timespan]::fromseconds($timeremaining.text)

#Create the countdown label for the timeout
$Countdown_Label = New-Object System.Windows.Forms.Label
$Countdown_Label.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$Countdown_Label.Location = New-Object System.Drawing.Point(0, 0)
$Countdown_Label.Size = New-Object System.Drawing.Size(250, 50)
$Countdown_Label.Font = [System.Drawing.Font]::new("Segoe UI","12",[System.Drawing.FontStyle]::Bold)
$Countdown_Label.ForeColor = "#E64F4F"

#Create the countdown label for the forced restart
$Countdown_Label2 = New-Object System.Windows.Forms.Label
$Countdown_Label2.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$Countdown_Label2.Location = New-Object System.Drawing.Point(100, 325)
$Countdown_Label2.Size = New-Object System.Drawing.Size(250, 50)
$Countdown_Label2.Font = [System.Drawing.Font]::new("Segoe UI","12",[System.Drawing.FontStyle]::Bold)
$Countdown_Label2.ForeColor = "#FF0000"
$Countdown_Label2.TextAlign = "TopCenter"


#The content of the text is set as part of the function CountDown as setting a text value or not determines it's visibility (See $AutoCloseVisible)

#This will cause it to align to the center of your drawing size window, which will not be aligned to the top left.
#$Countdown_Label.TextAlign = "TopCenter"

#This must be stored as a label otherwise it will tick once and freeze. It is VERY important you declare this new object AFTER the form has been created.
$TimeRemaining = New-Object System.Windows.Forms.Label #Don't touch this.
$timeRemaining.text = $TimeOutDuration #See the variables region to change me!

# Countdown is decremented every seconde using a timer
# The tick rate is 1000 MS or 1 second. You can drop it to 100 or 10 for testing.
$timer=New-Object System.Windows.Forms.Timer
$timer.Interval=1000
$timer.add_Tick({CountDown})
$timer.Start()
#endregion

#This must be stored as a label otherwise it will tick once and freeze. It is VERY important you declare this new object AFTER the form has been created.
$timeRemainingForcedReboot = New-Object System.Windows.Forms.Label #Don't touch this.
$timeRemainingForcedReboot.text = $ForcedRebootTime #See the variables region to change me!

# Countdown is decremented every seconde using a timer
# The tick rate is 1000 MS or 1 second. You can drop it to 100 or 10 for testing.
$timer2=New-Object System.Windows.Forms.Timer
$timer2.Interval=1000
$timer2.add_Tick({ForcedRebootCountDown})
#endregion


#Assign our timer, picture, two buttons, and help message to our form.
$RebootPromptForm.Controls.Add($Countdown_Label)
$RebootPromptForm.Controls.Add($Countdown_Label2)
$RebootPromptForm.Controls.Add($btn1) #order matters here! Don't put me under the textbook or I will layer under it (and not just where there is text but the full invisible box size)!
$RebootPromptForm.Controls.Add($btn2)
$RebootPromptForm.Controls.Add($pictureBox1)
$RebootPromptForm.controls.add($richTextBox1)



#Region check popup applicability
#This is where we truly check if the device should be prompted or not. This is done last because you really need to declare the form itself along with all content before attempting to call to it.

#If you break the maximum uptime (Greater than or equal to)
if ($MachineUptimeDays -ge $MaximumUptime){
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Machine uptime of $($MachineUptimeDays) days is greater than or equal to the configured MAXIMUM threshold of $($MaximumUptime) days - prompting for FORCED reboot." -Force
	
	#Region Configure form options for a forced reboot

	#Set form size of the form
	$RebootPromptForm.ClientSize = New-Object System.Drawing.Size(800, 450)

	#Set button heights
	$btn1.Location = New-Object System.Drawing.Point(0, 900) #Throw me off screen
	$btn2.Location = New-Object System.Drawing.Point(425, 325)

	#Set the timeout to invisible
	$AutoCloseVisible = $false

	#Start the forced countdown timer
	$timer2.Start()

	#Set our message for our text box
	$richTextBox1.Text = "This device has not restarted in $($MachineUptimeDays) days violating the maximum of $($MaximumUptime) days. Your device will reboot automatically 15 minutes from $($starttime). Be sure to save and close your work prior to rebooting! You can expedite this request by clicking the link below and your device will reboot 60 seconds later."
	
	#endregion

	RebootPrompt #Yes they both call the same thing
	exit #Yes, this really should go here for when the form exits.
}



#If you break the minimum uptime (Greater than or equal to)
if ($MachineUptimeDays -ge $MinimumUptime){
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Machine uptime of $($MachineUptimeDays) days is greater than or equal to the configured MINIMUM threshold of $($MinimumUptime) days - prompting for OPTIONAL reboot." -Force
	
	#Region Configure form options for a optional reboot

	#Set form size
	$RebootPromptForm.ClientSize = New-Object System.Drawing.Size(800, 475)

	#Set button heights
	$btn1.Location = New-Object System.Drawing.Point(425, 375)
	$btn2.Location = New-Object System.Drawing.Point(100, 375)

	#Move the reboot timer off view (it's not active)
	$Countdown_Label2.Location = New-Object System.Drawing.Point(800, 325)

	#Set our message for our text box
	$richTextBox1.Text = "Your computer has not restarted in $($MachineUptimeDays) days. Please reboot at your earliest convenience. Be sure to save and close your work prior to rebooting! You can expedite this request by clicking the link below and your device will reboot 60 seconds later.  

If now is not a good time, please click the Close button and you will be reminded again at a later time."
	
	#endregion

	RebootPrompt #Yes they both call the same thing
	exit #Yes, this really should go here for when the function exits.
	
} else {
	#You did not violate either value - good job!
	Add-Content "$($LogFileFolder)\$($LogFileName)" "$(get-date): Machine uptime of $($MachineUptimeDays) days is not greater than the maximum uptime of $($MaximumUptime) days, or the minimum uptime of $($MinimumUptime) days - exiting." -Force
	write-host "$(get-date): Machine uptime of $($MachineUptimeDays) days is not greater than the maximum uptime of $($MaximumUptime) days, or the minimum uptime of $($MinimumUptime) days - exiting."
	exit
}

#endregion
