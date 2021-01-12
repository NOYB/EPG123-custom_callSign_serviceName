# Version: 20200928.1-alpha
# Status: alpha

# Standard file system locations
# Folder: C:\ProgramData\GaRyan2\epg123
# PS Script File: custom_callSign_serviceName.ps1
# JSON Data File: custom_callSign_serviceName.json
# Dry Run CFG File: custom_callSign_serviceName.Dry_Run.cfg

# Development environment:
# Windows 8.1 Pro w/Media Center
# PowerShell: 4.0
# SiliconDust: HDHomeRun CONNECT, Model: HDHR4-2US, Firmware: 20200907


# Criteria to use
$Dry_Run = $true								# Save to $EPG_Data_Dir'\custom_callSign_serviceName.Dry_Run.cfg'
$ChLineUp = 'USA-OTA-97007'						# Channel line up associated with HDHomeRun device
$EPG_Service = 'EPG123'							# EPG service name

$EPG_Data_Dir = 'C:\ProgramData\GaRyan2\epg123'	# Fully qualified EPG data dir path (without trailing slash)
$CFG_File = 'epg123.cfg'						# EPG config file
$MXF_File = 'epg123.mxf'						# EPG MXF file

$Custom_CallSign_flag = $true					# Set/Replace (true), Remove (false) custom channel call sign
$Custom_Service_Name_flag = $true				# Set/Replace (true), Remove (false) custom channel service name

# Can be used standalone with guide name and number JSON data: ex: [{"GuideNumber":"10.4","GuideName":"OPBKids"}]
$Retrive_Data_From_Device = $true				# Retrieve channels & names from HDHomeRun device
$Device_Channel_Dectection_Scan = $false		# Perform HDHomeRun device channel detection scan
#$Device_ID = '1040dddd'						# HDHomeRun device ID (only for client utility scan)
$Device_Address = '192.168.2.202'				# HDHomeRun device address
$Show = 'found'									# HDHomeRun device channel line up query: all, found, favorites
# End Criteria to use


function Invoke-Main {
	Get-Channels_Service_Name_Data
	Customize-Configuration
}


#
# Retrieve PSIP VCT short name from HDHomeRun device.  Or use default/fallback channel names.
#
function Get-Channels_Service_Name_Data {

	if ($Retrive_Data_From_Device) {
		$webclient = new-object System.Net.WebClient
		$lineup_json_url = 'http://'+$Device_Address+'/lineup.json?show='+$Show
		if ($Device_Channel_Dectection_Scan) {
			Invoke-Device_Channel_Dectection_Scan_Web
#			Invoke-Device_Channel_Dectection_Scan_Utility	# SliconDust hdhomerun_config.exe
		} else {
			$json = $webclient.DownloadString($lineup_json_url)
		}
	}

	try {
		$vPSObject = $json | ConvertFrom-Json -ErrorAction Stop;
		'Using data retrieved from device ('+$Device_Address+')'
		''	# Blank line

		# Save device retrieved, guide number and guide name abbreviated, json for default/fallback, don't overwrite existing
		if (!(Test-Path $EPG_Data_Dir'\custom_callSign_serviceName.json')) {
			$json = $json -Replace '\[\{', "[`r`n{" -Replace '},{', "},`r`n{" -Replace '}]', "}`r`n]"	# Line-ized
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
			pause
			exit
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
			"service=`"(?<service_id>.*?)`" number=`""+$ChNumber[0]+"`" subNumber=`""+$ChNumber[1]+"`" />" ) {

			$station_id = $matches['station_id'];	$RegexEscaped_station_id = [Regex]::Escape($station_id)
			$lineup_id = $matches['lineup_id'];		$RegexEscaped_lineup_id = [Regex]::Escape($lineup_id)
			$service_id = $matches['service_id'];	$RegexEscaped_service_id = [Regex]::Escape($service_id)

			# Get existing custom service name string
			$cSN = ( $epg123_cfg -match "<StationID CallSign=`".*?`".*?(?<Existing_customServiceName> customServiceName=`".*?`").*?>$RegexEscaped_station_id</StationID>" )
			$Existing_customServiceName = $matches['Existing_customServiceName'];		$RegexEscaped_Existing_customServiceName = [Regex]::Escape($Existing_customServiceName)

			# Get existing custom call sign string
			$cCS = ( $epg123_cfg -match "<StationID CallSign=`".*?`".*?(?<Existing_customCallSign> customCallSign=`".*?`").*?>$RegexEscaped_station_id</StationID>" )
			$Existing_customCallSign = $matches['Existing_customCallSign'];				$RegexEscaped_Existing_customCallSign = [Regex]::Escape($Existing_customCallSign)

			if ($Custom_Service_Name_flag) { $customServiceName = " customServiceName=`"$ChName`"" }
			if ($Custom_CallSign_flag) { $customCallSign = " customCallSign=`"$ChCallSign`"" }

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
# Run HDHomeRun device channel scan (web based)
#
function Invoke-Device_Channel_Dectection_Scan_Web {

	$status_json_url = 'http://'+$Device_Address+'/lineup_status.json'

	$scan_status = $webclient.DownloadString($status_json_url) | ConvertFrom-Json
	if ($scan_status.ScanInProgress -eq 0) {
		if ($scan_status.ScanPossible -eq 1) {
			'Channel Detection: '
			' Scanning device ('+$Device_Address+')...'
			$lineup_scan_start_url = 'http://'+$Device_Address+'/lineup.post?scan=start&source='+$scan_status.Source
#			Invoke-WebRequest -Uri $lineup_scan_start_url -Method POST
			$webclient.UploadString($lineup_scan_start_url,'')
		} else { 'Scan not possible.  May not be an available tuner.' }
	} else { 'Channel detection scan already in progress...' }

	# While scanning...
	Do {
		$scan_status = $webclient.DownloadString($status_json_url) | ConvertFrom-Json
		if ($scan_status.ScanInProgress -ge 1) {
			$status = 'Found '+$scan_status.Found+' programs ('+$scan_status.Progress+'%)'
			Write-Host "`r"$status -NoNewLine
			Start-Sleep 1
		}
	} While ( $scan_status.ScanInProgress -eq 1)

	$json = $webclient.DownloadString($lineup_json_url)

	# Final status
	$Found = ($json | ConvertFrom-Json).length; $Progress = 100
	$status = "Found "+$Found+" programs ("+$Progress+"%)"
	Write-Host "`r"$status
	''	# Blank line

	$script:json = $json
}


#
# Run HDHomeRun device channel scan; Return GuideNumber and GuideName JSON string (client utility based)
#
function Invoke-Device_Channel_Dectection_Scan_Utility {
	$tuner0 = & 'C:\Program Files\Silicondust\HDHomeRun\hdhomerun_config.exe' $Device_ID get /tuner0/status
	$tuner1 = & 'C:\Program Files\Silicondust\HDHomeRun\hdhomerun_config.exe' $Device_ID get /tuner1/status

	"Scanning device $Device_ID for channels..."
	if ($tuner0 -match "lock=none") {
		$channel_scan = & 'C:\Program Files\Silicondust\HDHomeRun\hdhomerun_config.exe' $Device_ID 'scan' '/tuner0'
		$Device_Channel_Dectection_Scan_Status = & 'C:\Program Files\Silicondust\HDHomeRun\hdhomerun_config.exe' $Device_ID 'get' '/lineup/scan'
	} elseif ($tuner1 -match "lock=none") {
		$channel_scan = & 'C:\Program Files\Silicondust\HDHomeRun\hdhomerun_config.exe' $Device_ID 'scan' '/tuner1'
		$Device_Channel_Dectection_Scan_Status = & 'C:\Program Files\Silicondust\HDHomeRun\hdhomerun_config.exe' $Device_ID 'get' '/lineup/scan'
	} else {
		"No Tuner Available"
	}

	if ($Device_Channel_Dectection_Scan_Status -match "state=complete") {
		$json = '['
		$lines = $channel_scan.split("`r`n")
		foreach ($line in $lines) {
			$matched = $line -match "PROGRAM *[0-9]*: *(?<GuideNumber>[0-9]{1,2}\.[0-9]*) *(?<GuideName>.*)"
			if ($matched) {
				$json += '{"GuideNumber":"'+$matches['GuideNumber']+'","GuideName":"'+$matches['GuideName']+'"},'
			}
		}
		$json = $json.TrimEnd(',')
		$json += ']'
	}

	# Sort by ascending GuideNumber
	$array = $json | ConvertFrom-Json
	$array_sorted = $array | Sort-Object { [float]$_.GuideNumber }
	$json = $array_sorted | ConvertTo-Json
	$json = $json -Replace "[`r`n]","" -Replace " *{ *","{" -Replace " *} *", "}" -Replace "`": *`"","`":`"" -Replace "`", *`"","`",`""

	$script:json = $json
}


Invoke-Main

''	# Blank line
pause	# Wait for user to exit/close PS window



# NOTE:
# $json = Invoke-WebRequest http://$Device_Address/lineup.json?show=found		# Doesn't work with UTF8 encoding

# Workaround A
# $json = Invoke-WebRequest -Uri 'http://$Device_Address/lineup.json?show=found' -Outfile $EPG_Data_Dir'\hdhrlineup.json'
# $json = Get-Content -Path $EPG_Data_Dir'\hdhrlineup.json' -Encoding UTF8 -Raw
# Remove-Item -Path $EPG_Data_Dir'\hdhrlineup.json' -Force

# Workaround B
# $webclient = new-object System.Net.WebClient
# $json = $webclient.DownloadString("http://$Device_Address/lineup.json?show=$Show")
