#!/bin/bash

# clear_failed_mdm_commands.sh
# Hypoport hub SE -=- Mirko Steinbrecher
# Created on 27.11.2024

# This script checks and clears failed mdm commands.

# Configuration
JAMF_URL="https://XXX.jamfcloud.com"
CLIENT_ID="XXX"
CLIENT_SECRET="XXX"

# Function to get an OAuth access token
get_access_token() {
	local response
	response=$(curl -s \
		--request POST "$JAMF_URL/api/oauth/token" \
		--header 'Content-Type: application/x-www-form-urlencoded' \
		--data-urlencode "client_id=$CLIENT_ID" \
		--data-urlencode "grant_type=client_credentials" \
		--data-urlencode "client_secret=$CLIENT_SECRET")
	
	access_token=$(echo "$response" | plutil -extract access_token raw -)
	token_expires_in=$(echo "$response" | plutil -extract expires_in raw -)
	current_epoch=$(date +%s)
	token_expiration_epoch=$(($current_epoch + $token_expires_in - 1))
}

checkTokenExpiration() {
	current_epoch=$(date +%s)
	if [[ $token_expiration_epoch -ge $current_epoch ]]; then
		echo "Token valid until the following epoch time: $token_expiration_epoch"
	else
		echo "No valid token available, getting new token"
		get_access_token
	fi
}

# Function to automatically retrieve the serial number of the device
get_serial_number() {
	local serial_number
	serial_number=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $NF}')
	
	if [[ -z "$serial_number" ]]; then
		echo "Error: Unable to retrieve the serial number!"
		exit 1
	fi
	
	echo "$serial_number"
}

# Function to retrieve the Jamf Pro Computer ID based on the serial number
get_computer_id_by_serial() {
	local serial="$1"
	
	# API call to fetch the computer ID
	local response
	response=$(curl -s -H "Authorization: Bearer $access_token" \
		-H "Accept: application/xml" \
		"$JAMF_URL/JSSResource/computers/serialnumber/$serial")
	
	# Extract the computer ID from the XML response
	local computer_id
	computer_id=$(echo "$response" | xmllint --xpath "//computer/general/id/text()" - 2>/dev/null)
	
	if [[ -z "$computer_id" ]]; then
		echo "Error: No computer ID found for serial number $serial!"
		exit 1
	fi
	
	echo "$computer_id"
}

# Function to check if failed MDM commands exist
check_failed_mdm_commands() {
	local device_id="$1"
	
	# API call to fetch failed commands
	local response
	response=$(curl -s --header "Authorization: Bearer $access_token" \
		-H "Accept: application/xml" \
		"${JAMF_URL}/JSSResource/computerhistory/id/$device_id/subset/Commands")
	
	# Extract failed commands
	local failed_commands
	failed_commands=$(echo "$response" | xmllint --xpath "/computer_history/commands/failed/node()" - 2>/dev/null)
	
	if [[ -z "$failed_commands" ]]; then
		echo "No failed MDM commands found for device with ID $device_id. Exiting."
		exit 0
	fi
	
	echo "Failed MDM commands found for device with ID $device_id."
}

# Function to delete failed MDM commands
delete_failed_mdm_commands() {
	local device_id="$1"
	
	# API call
	local response
	response=$(curl -sf --header "Authorization: Bearer ${access_token}" \
		"${JAMF_URL}/JSSResource/commandflush/computers/id/$device_id/status/Failed" -X DELETE)
	
	# Check the response for success
	if echo "$response" | xmllint --xpath "//commandflush/status/text()" - 2>/dev/null | grep -q "+failed"; then
		echo "Success: Failed MDM commands for device with ID $device_id have been deleted."
	else
		echo "Error: Failed to delete MDM commands for device with ID $device_id."
		echo "Response: $response"
	fi
}

# Automatic workflow
get_access_token

serial_number=$(get_serial_number)
echo "Serial Number: $serial_number"

computer_id=$(get_computer_id_by_serial "$serial_number")
echo "Found Computer ID: $computer_id"

checkTokenExpiration

check_failed_mdm_commands "$computer_id"

delete_failed_mdm_commands "$computer_id"

exit 0
