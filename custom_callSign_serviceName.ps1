# Version: 20200926.1-alpha
# Status: alpha

# Development environment:
# Windows 8.1 Pro w/Media Center
# PowerShell: 4.0


# Criteria to use
$ChLineUp = 'USA-OTA-97007'							# Channel line up associated with SiliconDust HDHomeRun device
$EPG_Service = 'EPG123'								# EPG service name
$EPG_Data_Dir = 'C:\ProgramData\GaRyan2\epg123'		# Fully qualified EPG data dir path (without trailing slash)
$CFG_File = 'epg123.cfg'							# EPG config file
$MXF_File = 'epg123.mxf'							# EPG MXF file

$Retrive_From_Device = $true						# Retrieve channel names from SiliconDust HDHomeRun device
$Device_Address = '192.168.2.202'					# SiliconDust HDHomeRun device address
$Show = 'found'										# SiliconDust HDHomeRun device channel line up query;  Valid values: all, found

$Custom_CallSign_flag = $true						# Set/Replace (true), Remove (false) custom channel call sign
$Custom_Service_Name_flag = $true					# Set/Replace (true), Remove (false) custom channel service name


#
# 1) Retrieve PSIP VCT short name from SiliconDust HDHomeRun device.  Or use default/fallback channel names.
#
if ($Retrive_From_Device) {
#	Invoke-WebRequest http://$Device_Address/lineup.json?show=found		# Doesn't work with UTF8 encoding
	$webclient = new-object System.Net.WebClient
	$json = $webclient.DownloadString("http://$Device_Address/lineup.json?show=$Show")
}

try {
	$vPSObject = $json | ConvertFrom-Json -ErrorAction Stop;
	"From Device"	# Output for debugging

	# Save device retrieved, guide number and guide name abbreviated, json for default/fallback
	if (!(Test-Path $EPG_Data_Dir'\custom_callSign_serviceName.json')) {	# But don't overwrite existing
		$json = $json -Replace '\[\{', "[`r`n{" -Replace '},{', "},`r`n{" -Replace '}]', "}`r`n]"
		$json = $json -Replace "({`"GuideNumber.*?GuideName`":`".*?`").*(},*)", "`$1`$2"
		$json | Set-Content -Path $EPG_Data_Dir'\custom_callSign_serviceName.json'
	}
} catch {
	# Channel GuideNumber and GuideName json.
	# Use in place of (retrieve from device false) or if SiliconDust HDHomeRun device query fails.
	$json_fallback = Get-Content -path $EPG_Data_Dir'\custom_callSign_serviceName.json' -Raw
	$vPSObject = $json_fallback | ConvertFrom-Json
	"From Fallback"	# Output for debugging
}


$epg123_cfg = Get-Content -path $EPG_Data_Dir'\'$CFG_File -Raw
$epg123_mxf = Get-Content -path $EPG_Data_Dir'\output\'$MXF_File -Raw


#
# 2) Customize epg123.cfg customServiceName and customCallSign fields
#
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

		# Get existing custom service name and call sign strings
		$cSN = ( $epg123_cfg -match "<StationID CallSign=`".*?`".*?(?<Existing_customServiceName> customServiceName=`".*?`").*?>$RegexEscaped_station_id</StationID>" )
		$Existing_customServiceName = $matches['Existing_customServiceName'];		$RegexEscaped_Existing_customServiceName = [Regex]::Escape($Existing_customServiceName)

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

		# Output for debugging
#		$ChNumber[0]+'.'+$ChNumber[1]+"`t"+$ChName+"`t"+$ChCallSign
		$ChNumber[0]+'.'+$ChNumber[1]+"`t"+$ChName+"`t"+$ChCallSign+"`t"+$station_id+"`t"+$lineup_id+"`t"+$service_id
	}
}

$epg123_cfg.TrimEnd() | Set-Content -Encoding UTF8 -Path $EPG_Data_Dir'\'$CFG_File

pause	# For debugging (don't exit/close PS window)
