# Before using see observed issues, change log and development environment information at bottom.

# Version: 20230801.2-alpha
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

$Physical_Channel_Number_flag = $true, `			# Set/Replace (true), Remove (false) physical channel number
$Guide_Channel_Number_flag = $true, `				# Set/Replace (true), Remove (false) guide channel number
$Custom_Service_Name_flag = $true, `				# Set/Replace (true), Remove (false) custom channel service name
$Custom_CallSign_flag = $true, `					# Set/Replace (true), Remove (false) custom channel call sign

$Sort_By_Station_Attribute = 'GuideChNumber', `		# Sort by station attribute

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
		$lineup_json_url = 'http://'+$Device_IP_Address+'/lineup.json?show='+$Show+'&tuning'
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
# Set/Remove/Replace epg123.cfg station attributes and sort (GuideChNumber, PhyChNumber, customCallSign and customServiceName)
#
function Customize-Configuration {

	[xml]$epg123_cfg = Get-Content -Encoding UTF8 -path $EPG_Data_Dir'\'$CFG_File -Raw
	[xml]$epg123_mxf = Get-Content -Encoding UTF8 -path $EPG_Data_Dir'\output\'$MXF_File -Raw

	$StationNodes = $epg123_cfg.SelectNodes('//StationID')
	$ChannelNodes = $epg123_mxf.SelectNodes('//Channel')

	"B-Cast`tDisplay`tStation`tCustom`tCustom`tStation`tLineup`tService"
	"Channel`tChannel`tSign`tName`tSign`tID`tID`tID"
	"-------`t-------`t-------`t-------`t-------`t-------`t-------`t-------"

	# Set/Remove/Replace additional station attributes (Guide Ch Number, Physical Ch Number, Custom Call Sign, Custom Service Name)
	foreach($StationNode in $StationNodes) {

		if ([int]$StationNode.'#text' -gt 0) {
			$CallSign = $StationNode.CallSign
			$Station_ID = $StationNode.'#text'

			$epgChNumber = $null
			# Get matching channel info from MXF (Lineup ID, Service ID, EPG Channel Number)
			foreach ($ChannelNode in $ChannelNodes) {
				if ($ChannelNode.uid -match '!Channel!'+$ChLineUp+'!'+$Station_ID+'_[0-9]+_[0-9]+') {
					$Lineup_ID = $ChannelNode.lineup
					$Service_ID = $ChannelNode.service
					$epgChNumber = $ChannelNode.number+'.'+$ChannelNode.subNumber
					break
				}
			}

			# Remove existing additional attributes
			$StationNode.RemoveAttribute("PhyChNumber")
			$StationNode.RemoveAttribute("GuideChNumber")
			$StationNode.RemoveAttribute("customCallSign")
			$StationNode.RemoveAttribute("customServiceName")

			# Set/Replace additional attributes
			foreach ($ch in $vPSObject) {
				if ($ch.GuideNumber -eq $epgChNumber) {
					$PhyChNumber = $ch.ChannelNumber
					$ChNumber = $ch.GuideNumber
					$ChName = $ch.GuideName
					$ChCallSign = $ch.GuideName

					if ($ch.CustomGuideName) {
						$ChName = $ch.CustomGuideName
						$ChCallSign = $ch.CustomGuideName
					}

					if ($Physical_Channel_Number_flag) { $StationNode.SetAttribute("PhyChNumber", $PhyChNumber) }
					if ($Guide_Channel_Number_flag) { $StationNode.SetAttribute("GuideChNumber", $ChNumber) }
					if ($Custom_CallSign_flag) { $StationNode.SetAttribute("customCallSign", $ChCallSign) }
					if ($Custom_Service_Name_flag) { $StationNode.SetAttribute("customServiceName", $ChName) }

					# Display channel info
					$PhyChNumber+"`t"+$ChNumber+"`t"+$CallSign+"`t"+$ChName+"`t"+$ChCallSign+"`t"+$Station_ID+"`t"+$Lineup_ID+"`t"+$Service_ID

					break
				}
			}
		}
	}

	# Sort by station attribute (enabled channels first, followed by disabled channels)
	$epg123_cfg.EPG123.StationID | sort {         $_.CallSign}                   | % { if ([int]$_.'#text' -gt 0 -And -Not $_.$Sort_By_Station_Attribute) { [void]$epg123_cfg.EPG123.AppendChild($_) } }
	$epg123_cfg.EPG123.StationID | sort {[decimal]$_.$Sort_By_Station_Attribute} | % { if ([int]$_.'#text' -gt 0 -And      $_.$Sort_By_Station_Attribute) { [void]$epg123_cfg.EPG123.AppendChild($_) } }

	$epg123_cfg.EPG123.StationID | sort {         $_.CallSign}                   | % { if ([int]$_.'#text' -lt 0 -And -Not $_.$Sort_By_Station_Attribute) { [void]$epg123_cfg.EPG123.AppendChild($_) } }
	$epg123_cfg.EPG123.StationID | sort {[decimal]$_.$Sort_By_Station_Attribute} | % { if ([int]$_.'#text' -lt 0 -And      $_.$Sort_By_Station_Attribute) { [void]$epg123_cfg.EPG123.AppendChild($_) } }


	''	# Blank line
	'Customized epg123.cfg saved to: '
	if ($Dry_Run) {
		$EPG_Data_Dir+'\custom_callSign_serviceName.Dry_Run.cfg'
		$epg123_cfg.save($EPG_Data_Dir+'\custom_callSign_serviceName.Dry_Run.cfg')
	} else {
		$EPG_Data_Dir+'\'+$CFG_File
		$epg123_cfg.save($EPG_Data_Dir+'\'+$CFG_File)
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

#	$json = $webclient.DownloadString($lineup_json_url)

	$Channel_Frequency_Map = @{
		 '57000000' =  '2'
		 '63000000' =  '3'
		 '69000000' =  '4'
		 '79000000' =  '5'
		 '85000000' =  '6'
		'177000000' =  '7'
		'183000000' =  '8'
		'189000000' =  '9'
		'195000000' = '10'
		'201000000' = '11'
		'207000000' = '12'
		'213000000' = '13'
		'473000000' = '14'
		'479000000' = '15'
		'485000000' = '16'
		'491000000' = '17'
		'497000000' = '18'
		'503000000' = '19'
		'509000000' = '20'
		'515000000' = '21'
		'521000000' = '22'
		'527000000' = '23'
		'533000000' = '24'
		'539000000' = '25'
		'545000000' = '26'
		'551000000' = '27'
		'557000000' = '28'
		'563000000' = '29'
		'569000000' = '30'
		'575000000' = '31'
		'581000000' = '32'
		'587000000' = '33'
		'593000000' = '34'
		'599000000' = '35'
		'605000000' = '36'
	}

	foreach ($ch in ($webclient.DownloadString($lineup_json_url) | ConvertFrom-Json)) {
		$key = $ch.Frequency.ToString()
		$channel_number = $Channel_Frequency_Map[$key]
		$json += '{"ChannelNumber":"'+$channel_number+'","GuideNumber":"'+$ch.GuideNumber+'","GuideName":"'+$ch.GuideName+'"},'
#		$json += '{"ChannelNumber":"'+$channel_number+'","GuideNumber":"'+$ch.GuideNumber+'","GuideName":"'+$ch.GuideName+'","CustomGuideName":""},'
		$found++
	}

	# Final status
#	$found = ('['+$json.TrimEnd(',')+']' | ConvertFrom-Json).length
	$progress = 100
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

	# Use the device IP Address to avoid LAN broadcast
	if ($Device_IP_Address) {
		$Utility_Device_Address = $Device_IP_Address
	} else {
		$Utility_Device_Address = $Device_ID
	}

	Get-Device_Information 'client'

	# Find/Select available tuner
	for ($tuner = 0; $tuner -le 64; $tuner++) {		# Loop depth failsafe (64)
		$tuner_lockkey = & "$HDHR_Prog_Dir\$HDHR_Client_Utility" $Utility_Device_Address get /tuner$tuner/lockkey
		if ($tuner_lockkey -match "none" -Or $tuner_lockkey -match "ERROR") {
			break
		}
	}

	if ($tuner_lockkey -notmatch "none") {
		' No Tuner Available'
		''	# Blank line
		pause; exit;
	}

	$channel_map = & "$HDHR_Prog_Dir\$HDHR_Client_Utility" $Utility_Device_Address 'get' "/tuner$tuner/channelmap"

	'Channel Detection: '
	' Scanning device ('+$Device_ID+')... Tuner: '+$tuner+' '+$channel_map
	''	# Blank line

	& "$HDHR_Prog_Dir\$HDHR_Client_Utility" $Utility_Device_Address 'scan' "/tuner$tuner" | ForEach-Object -Process { $found = 0; $progress = 0 } {

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

		$matched = $_ -match "PROGRAM *[0-9]*: *(?<GuideNumber>[0-9]{1,2}\.[0-9]*) *(?<GuideName>.*)"
		if ($matched) {
			$matches['GuideName'] = $matches['GuideName'] -Replace "(.*?) \(control\)(.*)", "`$1`$2"
			$matches['GuideName'] = $matches['GuideName'] -Replace "(.*?) \(encrypted\)(.*)", "`$1`$2"
			$matches['GuideName'] = $matches['GuideName'] -Replace "(.*?) \(no data\)(.*)", "`$1`$2"
			$json += '{"ChannelNumber":"'+$channel_number+'","GuideNumber":"'+$matches['GuideNumber']+'","GuideName":"'+$matches['GuideName']+'"},'
#			$json += '{"ChannelNumber":"'+$channel_number+'","GuideNumber":"'+$matches['GuideNumber']+'","GuideName":"'+$matches['GuideName']+'","CustomGuideName":""},'
			$found++
		}

		if ($Verbose) {
			Write-Host $_
		}
	}

	# Clear the tuner channel
	& "$HDHR_Prog_Dir\$HDHR_Client_Utility" $Utility_Device_Address 'set' "/tuner$tuner/channel" "none"

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
		$ModelNumber = & "$HDHR_Prog_Dir\$HDHR_Client_Utility" $Utility_Device_Address get /sys/hwmodel
		$FirmwareVersion = & "$HDHR_Prog_Dir\$HDHR_Client_Utility" $Utility_Device_Address get /sys/version

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

# Version: 20230801.2-alpha
# Add guide and physical channel numbers to configuration.
# Sort Stations by Guide Channel Number (enabled channels first, followed by disabled channels)

# Version: 20230801.1-alpha
# Use XML to customize configuration rather than RegEx.

# Version: 20220922.3-alpha
# Clear the tuner channel after scan.

# Version: 20220922.2-alpha
# Use optional CustomGuideName field in JSON.

# Version: 20220922.1-alpha
# Use IP address for Utility_Device_Address (to avoid LAN broadcast when using device ID).

# Version: 20210719.1-alpha
# Include broadcast channel in display output and JSON.

# Version: 20210228.1-alpha
# Include station call sign in display output.

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
