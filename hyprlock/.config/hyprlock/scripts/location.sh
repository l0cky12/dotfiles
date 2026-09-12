#!/bin/bash

cache_file="$HOME/.cache/ip_cache.txt"
default_location="Location unavailable"
max_output_length=120

# Location lookup is disabled by default because it sends the public IP address
# to a third party. Launch Hyprlock with HYPRLOCK_ENABLE_LOCATION=1 to opt in.
if [[ ${HYPRLOCK_ENABLE_LOCATION:-0} != 1 ]]; then
	printf '%s\n' "$default_location"
	exit 0
fi

expiry_time=86400

valid_output() {
	local value="$1"
	[[ -n "$value" && ${#value} -le $max_output_length &&
		"$value" != *$'\n'* && "$value" != *$'\r'* &&
		"$value" =~ [^[:space:]] ]]
}

if [[ -f "$cache_file" ]]; then
	last_modified=$(stat -c %Y "$cache_file")
	current_date=$(date +%s)
	time_diff=$((current_date - last_modified))
	cached_data=$(<"$cache_file")

	if ((time_diff < expiry_time)) && valid_output "$cached_data"; then
		printf '%s\n' "$cached_data"
		exit 0
	fi
fi

response=""
if raw_response=$(curl --fail --silent --show-error --location \
	--connect-timeout 5 --max-time 15 'https://ipinfo.io'); then
	response=$(jq -er '
		select(.country | type == "string" and length > 0) |
		select(.city | type == "string" and length > 0) |
		.country + ", " + .city
	' <<<"$raw_response" 2>/dev/null) || response=""
fi

if valid_output "$response"; then
	mkdir -p "$(dirname "$cache_file")"
	printf '%s\n' "$response" >"$cache_file"
	printf '%s\n' "$response"
else
	printf '%s\n' "$default_location"
fi
