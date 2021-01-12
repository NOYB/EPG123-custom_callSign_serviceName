# Before using see observed issues, change log and development environment information at bottom.

# Version: 20210111.1-alpha
# Status: alpha

# Typical file system locations
# Folder: C:\ProgramData\GaRyan2\epg123
# PS Script File: custom_callSign_serviceName.ps1
# JSON Data File: custom_callSign_serviceName.json
# Dry Run CFG File: custom_callSign_serviceName.Dry_Run.cfg


# Criteria to use parameters (must be first line of script)
param(`
$Dry_Run = $true, `									# Save to $EPG_Data_Dir'\custom_callSign_serviceName.Dry_Run.cfg'
$CHLineUP = 'USA-OTA-97007', `						# Channel line up associated with HDHomeRun device
$EPG_Service = 'EPG123', `							# EPG service name

$EPG_Data_Dir = 'C:\ProgramData\GaRyan2\epg123', `	# Fully qualified EPG data dir path (without trailing slash)
$CFG_File = 'epg123.cfg', `							# EPG config file
$MXF_File = 'epg123.mxf', `							# EPG MXF file

$Custom_Service_Name_flag = $true, `				# Set/Replace (true), Remove (false) custom channel service name
$Custom_CallSign_flag = $true, `					# Set/Replace (true), Remove (false) custom channel call sign

# Can be used standalone with guide name and number JSON data: ex: [{"GuideNumber":"10.4","GuideName":"OPBKids"}]
$Retrieve_Data_From_Device = $true, `				# Retrieve channels & names from HDHomeRun device
$Device_Channel_Detection_Scan = 'none', `			# Perform HDHomeRun device channel detection scan: web, client, none

# HD HomeRun Web Utility Settings
# A web utility channel detection scan...
# 1) updates the device stored channel lineup
# 2) interrupts viewing and recording
$Device_IP_Address = '192.168.2.202', `				# HDHomeRun device IP address (required for web scan)
$Show = 'found', `									# HDHomeRun device channel line up web query: all, found, favorites

# HD HomeRun Client Utility Settings
# A client utility channel detection scan...
# 1) does not update the device stored channel lineup
# 2) may append a status comment to the channel name.  ex: '(control)', '(encrypted)', '(no data)'  Unknown what effects this may have.
$HDHR_Prog_Dir = 'C:\Program Files\Silicondust\HDHomeRun', `	# HDHomeRund installation folder path (without trailing slash)
$HDHR_Client_Utility = 'hdhomerun_config.exe', `	# HDHomeRun client configuration utility executable
$Device_ID = '1040nnnn', `							# Needed only for device without IP address
$Verbose = $false `									# Client utility verbose output
)
# End Criteria to use parameters


#
# Genesis
#
function Invoke-Main {
	Get-Channels_Guide_Name_Data
	Customize-Configuration
}


#
# Retrieve PSIP VCT short name from HDHomeRun device.  Or use default/fallback channel names.
#
function Get-Channels_Guide_Name_Data {

	if ($Retrieve_Data_From_Device) {
		$webclient = new-object System.Net.WebClient
		$lineup_json_url = 'http://'+$Device_IP_Address+'/lineup.json?show='+$Show
		if ($Device_Channel_Detection_Scan -eq 'web') {
			Invoke-Device_Channel_Detection_Scan_Web
		} elseif ($Device_Channel_Detection_Scan -eq 'client') {
			Invoke-Device_Channel_Detection_Scan_Utility	# SliconDust hdhomerun_config.exe
		} else {
			Get-Device_Information 'web'
			$json = $webclient.DownloadString($lineup_json_url)
			$Device_Address = $Device_IP_Address
		}
	}

	try {
		$vPSObject = $json | ConvertFrom-Json -ErrorAction Stop;
		'Using data retrieved from device ('+$Device_Address+')'
		''	# Blank line

		# Save device retrieved, guide number and guide name abbreviated, json for default/fallback, don't overwrite existing
		if (!(Test-Path $EPG_Data_Dir'\custom_callSign_serviceName.json')) {
			$json = $json -Replace '\[\{', "[`r`n{" -Replace '},{', "},`r`n{" -Replace '}]', "}`r`n]"	# Line-ized (each channel)
			$json = $json -Replace "({`"GuideNumber.*?GuideName`":`".*?`").*(},*)", "`$1`$2"			# Only GuideNumber and GuideName
			$json | Set-Content -Path $EPG_Data_Dir'\custom_callSign_serviceName.json'
		}
	} catch {
		# Channel GuideNumber and GuideName json.
		# Use in place of (retrieve from device false) or if HDHomeRun device query fails.
		if (Test-Path $EPG_Data_Dir'\custom_callSign_serviceName.json') {
			$json_fallback = Get-Content -path $EPG_Data_Dir'\custom_callSign_serviceName.json' -Raw
			$vPSObject = $json_fallback | ConvertFrom-Json
			'Using default/fallback data: '
			$EPG_Data_Dir+'\custom_callSign_serviceName.json'
			''	# Blank line
		} else {
			'Default/Fallback data not found: '
			$EPG_Data_Dir+'\custom_callSign_serviceName.json'
			''	# Blank line
			pause; exit;
		}
	}

	$script:vPSObject = $vPSObject
}


#
# Set/Remove/Replace epg123.cfg customServiceName and customCallSign fields
#
function Customize-Configuration {

	$epg123_cfg = Get-Content -path $EPG_Data_Dir'\'$CFG_File -Raw
	$epg123_mxf = Get-Content -path $EPG_Data_Dir'\output\'$MXF_File -Raw

	"Channel`tName`tSign`tSta ID`tLineup`tSrv ID"
	foreach ($ch in $vPSObject) {

		$ChNumber = $ch.GuideNumber.Split('.')
		$ChName = $ch.GuideName
		$ChCallSign = $ch.GuideName

		# Get EPG channel lineup station ID, and perform Set/Remove/Replace
		if ( $epg123_mxf -match `
			"<Channel uid=`"!Channel!$ChLineUp!(?<station_id>[0-9]*)_"+$ChNumber[0]+"_"+$ChNumber[1]+"`" lineup=`"(?<lineup_id>l[0-9]*)`" " + `
			"service=`"(?<service_id>.*?)`" matchName=`"(?<matchName>.*?)`" number=`""+$ChNumber[0]+"`" subNumber=`""+$ChNumber[1]+"`" />" ) {

			$station_id = $matches['station_id'];	$RegexEscaped_station_id = [Regex]::Escape($station_id)
			$lineup_id = $matches['lineup_id'];		$RegexEscaped_lineup_id = [Regex]::Escape($lineup_id)
			$service_id = $matches['service_id'];	$RegexEscaped_service_id = [Regex]::Escape($service_id)

			# Get existing custom service name string
			$cSN = ( $epg123_cfg -match "<StationID CallSign=`".*?`".*?(?<Existing_customServiceName> customServiceName=`".*?`").*?>$RegexEscaped_station_id</StationID>" )
			$Existing_customServiceName = $matches['Existing_customServiceName'];		$RegexEscaped_Existing_customServiceName = [Regex]::Escape($Existing_customServiceName)

			# Get existing custom call sign string
			$cCS = ( $epg123_cfg -match "<StationID CallSign=`".*?`".*?(?<Existing_customCallSign> customCallSign=`".*?`").*?>$RegexEscaped_station_id</StationID>" )
			$Existing_customCallSign = $matches['Existing_customCallSign'];				$RegexEscaped_Existing_customCallSign = [Regex]::Escape($Existing_customCallSign)

			if ($Custom_Service_Name_flag) { $customServiceName = " customServiceName=`"$ChName`"" } else { $ChName = '' }
			if ($Custom_CallSign_flag) { $customCallSign = " customCallSign=`"$ChCallSign`"" } else { $ChCallSign = '' }

			# Set/Remove/Replace custom service name
			$epg123_cfg = $epg123_cfg -replace `
				"<StationID CallSign=`"(.*?)`"(.*?)$RegexEscaped_Existing_customServiceName(.*?)>$RegexEscaped_station_id</StationID>", `
				"<StationID CallSign=`"`$1`"`$2$customServiceName`$3>$station_id</StationID>"

			# Set/Remove/Replace custom call sign
			$epg123_cfg = $epg123_cfg -replace `
				"<StationID CallSign=`"(.*?)`"(.*?)$RegexEscaped_Existing_customCallSign(.*?)>$RegexEscaped_station_id</StationID>", `
				"<StationID CallSign=`"`$1`"`$2$customCallSign`$3>$station_id</StationID>"

			$ChNumber[0]+'.'+$ChNumber[1]+"`t"+$ChName+"`t"+$ChCallSign+"`t"+$station_id+"`t"+$lineup_id+"`t"+$service_id
		}
	}

	''	# Blank line
	'Customized epg123.cfg saved to: '
	if ($Dry_Run) {
		$EPG_Data_Dir+'\custom_callSign_serviceName.Dry_Run.cfg'
		$epg123_cfg.TrimEnd() | Set-Content -Encoding UTF8 -Path $EPG_Data_Dir'\custom_callSign_serviceName.Dry_Run.cfg'
	} else {
		$EPG_Data_Dir+'\'+$CFG_File
		$epg123_cfg.TrimEnd() | Set-Content -Encoding UTF8 -Path $EPG_Data_Dir'\'$CFG_File
	}
}


#
# Run HDHomeRun device channel detection scan (web utility)
#
function Invoke-Device_Channel_Detection_Scan_Web {

	Get-Device_Information 'web'

	$status_json_url = 'http://'+$Device_IP_Address+'/lineup_status.json'

	$scan_status = $webclient.DownloadString($status_json_url) | ConvertFrom-Json
	if ($scan_status.ScanInProgress -eq 0) {
		if ($scan_status.ScanPossible -eq 1) {
			'Channel Detection: '
			' Scanning device ('+$Device_IP_Address+')...'
			$lineup_scan_start_url = 'http://'+$Device_IP_Address+'/lineup.post?scan=start&source='+$scan_status.Source
#			Invoke-WebRequest -Uri $lineup_scan_start_url -Method POST
			$webclient.UploadString($lineup_scan_start_url,'')
		} else { 'Scan not possible.  May not be an available tuner.' }
	} else { 'Channel detection scan already in progress...' }

	# While scanning...
	Do {
		$scan_status = $webclient.DownloadString($status_json_url) | ConvertFrom-Json
		if ($scan_status.ScanInProgress -ge 1) {
			$status = ' Found '+$scan_status.Found+' programs ('+$scan_status.Progress+'%)'
			Write-Host "`r"$status -NoNewLine
			Start-Sleep 1
		}
	} While ( $scan_status.ScanInProgress -eq 1)

	$json = $webclient.DownloadString($lineup_json_url)

		'479000000' = '15'
	# Final status
	$found = ($json | ConvertFrom-Json).length; $progress = 100
	$status = ' Found '+$found+' programs ('+$progress+'%)       '
	Write-Host "`r"$status
	''	# Blank line

	$Script:json = $json; $Script:Device_Address = $Device_IP_Address
}


#
# Run HDHomeRun device channel detection scan; Return GuideNumber and GuideName JSON (client utility)
#
function Invoke-Device_Channel_Detection_Scan_Utility {

	# Get Device ID from discover.json URL
	if (!$Device_ID) {
		if ($Device_IP_Address) {
#			$Device = $webclient.DownloadString($discover_json_url) | ConvertFrom-Json
			$Device = $webclient.DownloadString('http://'+$Device_IP_Address+'/discover.json') | ConvertFrom-Json
			$Device_ID = $Device.DeviceID
		} else {
			'Device not found'
			''	# Blank line
			pause; exit;
		}
	}

	Get-Device_Information 'client'

	# Find/Select available tuner
	for ($tuner = 0; $tuner -le 64; $tuner++) {		# Loop depth failsafe (64)
		$tuner_lockkey = & "$HDHR_Prog_Dir\$HDHR_Client_Utility" $Device_ID get /tuner$tuner/lockkey
		if ($tuner_lockkey -match "none" -Or $tuner_lockkey -match "ERROR") {
			break
		}
	}

	if ($tuner_lockkey -notmatch "none") {
		' No Tuner Available'
		''	# Blank line
		pause; exit;
	}

	$channel_map = & "$HDHR_Prog_Dir\$HDHR_Client_Utility" $Device_ID 'get' "/tuner$tuner/channelmap"

	'Channel Detection: '
	' Scanning device ('+$Device_ID+')... Tuner: '+$tuner+' '+$channel_map
	''	# Blank line

	& "$HDHR_Prog_Dir\$HDHR_Client_Utility" $Device_ID 'scan' "/tuner$tuner" | ForEach-Object -Process { $found = 0; $progress = 0 } {

		$matched = $_ -match "PROGRAM *[0-9]*: *(?<GuideNumber>[0-9]{1,2}\.[0-9]*) *(?<GuideName>.*)"
		if ($matched) {
			$matches['GuideName'] = $matches['GuideName'] -Replace "(.*?) \(control\)(.*)", "`$1`$2"
			$matches['GuideName'] = $matches['GuideName'] -Replace "(.*?) \(encrypted\)(.*)", "`$1`$2"
			$matches['GuideName'] = $matches['GuideName'] -Replace "(.*?) \(no data\)(.*)", "`$1`$2"
			$json += '{"GuideNumber":"'+$matches['GuideNumber']+'","GuideName":"'+$matches['GuideName']+'"},'
			$found++
		}

		$matched = $_ -match "SCANNING: .*? \(${channel_map}:(?<channel_number>[0-9]*)\).*"
		if ($matched) {
			$channel_number = $matches['channel_number']
			if (!$total_channels) { $total_channels = $channel_number }
			$status = ' Found '+$found+' programs ('+$progress+'%) Ch. '+$channel_number+' '
			$progress = [int]((($total_channels - $channel_number + 1 ) / ($total_channels - 1)) * 100)
			if (!$Verbose) {
				Write-Host "`r"$status -NoNewLine
			}
		}

		if ($Verbose) {
			Write-Host $_
		}
	}
	if ($Verbose) {
		''	# Blank line
	}

	# Final Status
	$status = ' Found '+$found+' programs ('+$progress+'%)       '
	Write-Host "`r"$status
	''	# Blank line

	if ($json) {
		$json = $json.TrimEnd(',')
		$json = '['+$json+']'		# As array

		# Sort by ascending GuideNumber
		$array = $json | ConvertFrom-Json
		$array_sorted = $array | Sort-Object { [Version]$_.GuideNumber }
		$json = $array_sorted | ConvertTo-Json -Compress
	}

	$Script:json = $json; $Script:Device_Address = $Device_ID
}


#
# Get Device Information
#
function Get-Device_Information ($method){
	if ($method -eq 'web') {
		$discover_json_url = 'http://'+$Device_IP_Address+'/discover.json'
		$Device = $webclient.DownloadString($discover_json_url) | ConvertFrom-Json

		$Device.FriendlyName
		'Model: '+$Device.ModelNumber
		'Firmware: '+$Device.FirmwareVersion
		'Device ID: '+$Device.DeviceID
		'Device IP Address: '+$Device_IP_Address
	} elseif ($method -eq 'client') {
		$ModelNumber = & "$HDHR_Prog_Dir\$HDHR_Client_Utility" $Device_ID get /sys/hwmodel
		$FirmwareVersion = & "$HDHR_Prog_Dir\$HDHR_Client_Utility" $Device_ID get /sys/version

		''	# Blank line
		'Model: '+$ModelNumber
		'Firmware: '+$FirmwareVersion
		'Device ID: '+$Device_ID
		'Device IP Address: '+$Device_IP_Address
	}
	''	# Blank line
}


Invoke-Main

''	# Blank line
pause; exit;	# Wait for user to exit/close PS window



# NOTE:
# $json = Invoke-WebRequest http://$Device_IP_Address/lineup.json?show=found		# Doesn't work with UTF8 encoding

# Workaround A
# $json = Invoke-WebRequest -Uri 'http://$Device_IP_Address/lineup.json?show=found' -Outfile $EPG_Data_Dir'\hdhrlineup.json'
# $json = Get-Content -Path $EPG_Data_Dir'\hdhrlineup.json' -Encoding UTF8 -Raw
# Remove-Item -Path $EPG_Data_Dir'\hdhrlineup.json' -Force

# Workaround B
# $webclient = new-object System.Net.WebClient
# $json = $webclient.DownloadString("http://$Device_IP_Address/lineup.json?show=$Show")



# Development Environment
# Windows 8.1 Pro w/Media Center
# PowerShell: 4.0
# SiliconDust: HDHomeRun CONNECT, Model: HDHR4-2US, Firmware: 20200907


# Observed Issues
# Running a channel detection scan (web) interrupts in process viewing/recording signal.
# Running a channel detection scan (client) may append a status comment to the channel name.  ex: '(control)', '(encrypted)', '(no data)'  Unknown what effects this may have.


# Change Log

# Version: 20210111.1-alpha
# Accommodate the "matchName" field in "epg123.mxf"

# Version: 20201106.1-alpha
# Learned to select channel detection scan method (web/client/none) from variable setting.
# Learned to retrieve device information (model, firmware, ID)
# Learned how not to be verbose (client utility)
# Learned to dynamically find and select from more than two tuners (0/1) (client utility)
# Learned to override settings with parameters passed on command line
# Example command line shortcuts
# Client Scan: %SystemRoot%\system32\WindowsPowerShell\v1.0\powershell.exe -Command "C:\ProgramData\GaRyan2\epg123\custom_callSign_serviceName.ps1" -Device_ID '1040nnnn' -Device_Channel_Detection_Scan 'client' -Device_IP_Address ''
#     Default: %SystemRoot%\system32\WindowsPowerShell\v1.0\powershell.exe -Command "C:\ProgramData\GaRyan2\epg123\custom_callSign_serviceName.ps1" -Retrieve_Data_From_Device $false
#     No Scan: %SystemRoot%\system32\WindowsPowerShell\v1.0\powershell.exe -Command "C:\ProgramData\GaRyan2\epg123\custom_callSign_serviceName.ps1" -Device_IP_Address '192.168.2.202' -Device_Channel_Detection_Scan 'none'
#     Verbose: %SystemRoot%\system32\WindowsPowerShell\v1.0\powershell.exe -Command "C:\ProgramData\GaRyan2\epg123\custom_callSign_serviceName.ps1" -Device_ID '1040nnnn' -Device_Channel_Detection_Scan 'client' -Device_IP_Address '' -Verbose $true
#    Web Scan: %SystemRoot%\system32\WindowsPowerShell\v1.0\powershell.exe -Command "C:\ProgramData\GaRyan2\epg123\custom_callSign_serviceName.ps1" -Device_IP_Address '192.168.2.202' -Device_Channel_Detection_Scan 'web'

# Version: 20200928.1-alpha
# Learned how to run HDHomeRun device channel detection scan
# Learned to operate standalone (without a HDHR device) using guide number and name JSON data.
# Learned to do a dry run
# Factored into functions
 
# Version: 20200926.1-alpha
# Genesis
