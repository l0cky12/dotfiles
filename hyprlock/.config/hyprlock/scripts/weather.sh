#!/bin/bash

cache_file="$HOME/.cache/wttr_cache.txt"
default_weather="Weather unavailable"
max_output_length=160

# Weather lookup is disabled by default because wttr.in geolocates the public
# IP address. Launch Hyprlock with HYPRLOCK_ENABLE_WEATHER=1 to opt in.
if [[ ${HYPRLOCK_ENABLE_WEATHER:-0} != 1 ]]; then
	printf '%s\n' "$default_weather"
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
if response=$(curl --fail --silent --show-error --location \
	--proto '=https' --proto-redir '=https' \
	--connect-timeout 5 --max-time 15 'https://wttr.in?format=%c+%C+%t'); then
	:
else
	response=""
fi

if valid_output "$response"; then
	mkdir -p "$(dirname "$cache_file")"
	printf '%s\n' "$response" >"$cache_file"
	printf '%s\n' "$response"
else
	printf '%s\n' "$default_weather"
fi
