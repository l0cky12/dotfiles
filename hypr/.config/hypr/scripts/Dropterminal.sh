#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
#
# Made and brought to by Kiran George
# /* -- ✨ https://github.com/SherLock707 ✨ -- */  ##
# Dropdown Terminal
# Usage: ./Dropdown.sh [-d] <terminal_command>
# Example: ./Dropdown.sh foot
#          ./Dropdown.sh -d foot (with debug output)
#          ./Dropdown.sh "kitty -e zsh"
#          ./Dropdown.sh "alacritty --working-directory /home/user"

DEBUG=false
SPECIAL_WS="special:scratchpad"
ADDR_FILE="${DROPTERMINAL_ADDR_FILE:-/tmp/dropdown_terminal_addr}"

# Dropdown size and position configuration (percentages)
WIDTH_PERCENT=65  # Width as percentage of screen width
HEIGHT_PERCENT=65 # Height as percentage of screen height
Y_PERCENT=10      # Y position as percentage from top (X is auto-centered)

# Animation settings
ANIMATION_DURATION=100 # milliseconds
SLIDE_STEPS=5
SLIDE_DELAY=5 # milliseconds between steps

# Parse arguments
if [ "$1" = "-d" ]; then
  DEBUG=true
  shift
fi

TERMINAL_CMD="$1"

# Cached client list, fetched lazily (at most one hyprctl clients -j per phase)
CLIENTS=""
refresh_clients() {
  if [ -z "$CLIENTS" ]; then
    CLIENTS=$(hyprctl clients -j)
  fi
}

# Debug echo function
debug_echo() {
  if [ "$DEBUG" = true ]; then
    echo "$@"
  fi
}

lua_string() {
  jq -Rn --arg value "$1" '$value'
}

dispatch_window_move() {
  local addr="$1" x="$2" y="$3"
  hyprctl dispatch "hl.dsp.window.move({ x = $x, y = $y, window = \"address:$addr\" })"
}

dispatch_window_resize() {
  local addr="$1" width="$2" height="$3"
  hyprctl dispatch "hl.dsp.window.resize({ x = $width, y = $height, window = \"address:$addr\" })"
}

dispatch_window_workspace() {
  local addr="$1" workspace="$2"
  hyprctl dispatch "hl.dsp.window.move({ workspace = $(lua_string "$workspace"), follow = false, window = \"address:$addr\" })"
}

dispatch_window_pin() {
  hyprctl dispatch "hl.dsp.window.pin({ window = \"address:$1\" })"
}

dispatch_window_focus() {
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })"
}

# Validate input
if [ -z "$TERMINAL_CMD" ]; then
  echo "Missing terminal command. Usage: $0 [-d] <terminal_command>"
  echo "Examples:"
  echo "  $0 foot"
  echo "  $0 -d foot (with debug output)"
  echo "  $0 'kitty -e zsh'"
  echo "  $0 'alacritty --working-directory /home/user'"
  echo ""
  echo "Edit the script to modify size and position:"
  echo "  WIDTH_PERCENT  - Width as percentage of screen (default: 50)"
  echo "  HEIGHT_PERCENT - Height as percentage of screen (default: 50)"
  echo "  Y_PERCENT      - Y position from top as percentage (default: 5)"
  echo "  Note: X position is automatically centered"
  exit 1
fi

# Function to get window geometry
get_window_geometry() {
  local addr="$1"
  jq -r --arg ADDR "$addr" '.[] | select(.address == $ADDR) | "\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"' <<<"$CLIENTS"
}

# Function to animate window slide down (show)
animate_slide_down() {
  local addr="$1"
  local target_x="$2"
  local target_y="$3"
  local width="$4"
  local height="$5"

  debug_echo "Animating slide down for window $addr to position $target_x,$target_y"

  # Start position (above screen)
  local start_y=$((target_y - height - 50))

  # Calculate step size
  local step_y=$(((target_y - start_y) / SLIDE_STEPS))

  # Move window to start position instantly (off-screen)
  dispatch_window_move "$addr" "$target_x" "$start_y" >/dev/null 2>&1
  sleep 0.05

  # Animate slide down
  for i in $(seq 1 $SLIDE_STEPS); do
    local current_y=$((start_y + (step_y * i)))
    dispatch_window_move "$addr" "$target_x" "$current_y" >/dev/null 2>&1
    sleep 0.03
  done

  # Ensure final position is exact
  dispatch_window_move "$addr" "$target_x" "$target_y" >/dev/null 2>&1
}

# Function to animate window slide up (hide)
animate_slide_up() {
  local addr="$1"
  local start_x="$2"
  local start_y="$3"
  local width="$4"
  local height="$5"

  debug_echo "Animating slide up for window $addr from position $start_x,$start_y"

  # End position (above screen)
  local end_y=$((start_y - height - 50))

  # Calculate step size
  local step_y=$(((start_y - end_y) / SLIDE_STEPS))

  # Animate slide up
  for i in $(seq 1 $SLIDE_STEPS); do
    local current_y=$((start_y - (step_y * i)))
    dispatch_window_move "$addr" "$start_x" "$current_y" >/dev/null 2>&1
    sleep 0.03
  done

  debug_echo "Slide up animation completed"
}

# Function to get monitor info including scale and name of focused monitor
get_monitor_info() {
  local monitor_data
  monitor_data=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | "\(.x) \(.y) \(.width) \(.height) \(.scale) \(.name)"')
  if [ -z "$monitor_data" ] || [[ "$monitor_data" =~ ^null ]]; then
    debug_echo "Error: Could not get focused monitor information"
    return 1
  fi
  echo "$monitor_data"
}

# Function to calculate dropdown position with proper scaling and centering
calculate_dropdown_position() {
  local monitor_info
  monitor_info=$(get_monitor_info)

  if [ $? -ne 0 ] || [ -z "$monitor_info" ]; then
    debug_echo "Error: Failed to get monitor info, using fallback values"
    echo "100 100 800 600 fallback-monitor"
    return 1
  fi

  local mon_x mon_y mon_width mon_height mon_scale mon_name
  read -r mon_x mon_y mon_width mon_height mon_scale mon_name <<<"$monitor_info"

  debug_echo "Monitor info: x=$mon_x, y=$mon_y, width=$mon_width, height=$mon_height, scale=$mon_scale"

  # Validate scale value and provide fallback
  if [ -z "$mon_scale" ] || [ "$mon_scale" = "null" ] || [ "$mon_scale" = "0" ]; then
    debug_echo "Invalid scale value, using 1.0 as fallback"
    mon_scale="1.0"
  fi

  # Calculate logical dimensions by dividing physical dimensions by scale
  # awk int() truncates toward zero, same as the previous bc scale=0 + cut pipeline
  local logical_width logical_height
  logical_width=$(awk "BEGIN{print int($mon_width / $mon_scale)}")
  logical_height=$(awk "BEGIN{print int($mon_height / $mon_scale)}")

  # Ensure we have valid integer values
  if ! [[ "$logical_width" =~ ^-?[0-9]+$ ]]; then logical_width=$mon_width; fi
  if ! [[ "$logical_height" =~ ^-?[0-9]+$ ]]; then logical_height=$mon_height; fi

  debug_echo "Physical resolution: ${mon_width}x${mon_height}"
  debug_echo "Logical resolution: ${logical_width}x${logical_height} (physical ÷ scale)"

  # Calculate window dimensions based on LOGICAL space percentages
  local width=$((logical_width * WIDTH_PERCENT / 100))
  local height=$((logical_height * HEIGHT_PERCENT / 100))

  # Calculate Y position from top based on percentage of LOGICAL height
  local y_offset=$((logical_height * Y_PERCENT / 100))

  # Calculate centered X position in LOGICAL space
  local x_offset=$(((logical_width - width) / 2))

  # Apply monitor offset to get final positions in logical coordinates
  local final_x=$((mon_x + x_offset))
  local final_y=$((mon_y + y_offset))

  debug_echo "Window size: ${width}x${height} (logical pixels)"
  debug_echo "Final position: x=$final_x, y=$final_y (logical coordinates)"
  debug_echo "Hyprland will scale these to physical coordinates automatically"

  echo "$final_x $final_y $width $height $mon_name"
}

# Get the current workspace
CURRENT_WS=$(hyprctl activeworkspace -j | jq -r '.id')

# Function to get stored terminal address
get_terminal_address() {
  if [ -f "$ADDR_FILE" ] && [ -s "$ADDR_FILE" ]; then
    cut -d' ' -f1 "$ADDR_FILE"
  fi
}

# Function to get stored monitor name
get_terminal_monitor() {
  if [ -f "$ADDR_FILE" ] && [ -s "$ADDR_FILE" ]; then
    cut -d' ' -f2- "$ADDR_FILE"
  fi
}

# Function to check if terminal exists (lazily fetches and caches CLIENTS)
terminal_exists() {
  local addr
  addr=$(get_terminal_address)
  if [ -n "$addr" ]; then
    refresh_clients
    jq -e --arg ADDR "$addr" 'any(.[]; .address == $ADDR)' <<<"$CLIENTS" >/dev/null 2>&1
  else
    return 1
  fi
}

# Function to check if terminal is in special workspace (uses cached CLIENTS)
terminal_in_special() {
  local addr
  addr=$(get_terminal_address)
  if [ -n "$addr" ]; then
    refresh_clients
    jq -e --arg ADDR "$addr" 'any(.[]; .address == $ADDR and .workspace.name == "special:scratchpad")' <<<"$CLIENTS" >/dev/null 2>&1
  else
    return 1
  fi
}

# Function to spawn terminal and capture its address
spawn_terminal() {
  debug_echo "Creating new dropdown terminal with command: $TERMINAL_CMD"

  # Calculate dropdown position for later use
  local pos_info
  pos_info=$(calculate_dropdown_position)
  if [ $? -ne 0 ]; then
    debug_echo "Warning: Using fallback positioning"
  fi

  local target_x target_y width height monitor_name
  read -r target_x target_y width height monitor_name <<<"$pos_info"

  debug_echo "Target position: ${target_x},${target_y}, size: ${width}x${height}"

  # Get window count before spawning
  local windows_before
  windows_before=$(hyprctl clients -j)
  local count_before
  count_before=$(jq 'length' <<<"$windows_before")

  # Launch terminal directly in special workspace to avoid visible spawn
  hyprctl dispatch "hl.dsp.exec_cmd($(lua_string "$TERMINAL_CMD"), { float = true, size = { $width, $height }, workspace = \"special:scratchpad silent\" })"

  # Wait for window to appear
  sleep 0.1

  # Get windows after spawning
  local windows_after
  windows_after=$(hyprctl clients -j)
  local count_after
  count_after=$(jq 'length' <<<"$windows_after")

  local new_addr=""

  if [ "$count_after" -gt "$count_before" ]; then
    # Find the new window by comparing before/after lists
    new_addr=$(comm -13 \
      <(jq -r '.[].address' <<<"$windows_before" | sort) \
      <(jq -r '.[].address' <<<"$windows_after" | sort) |
      head -1)
  fi

  # Fallback: try to find by the most recently mapped window
  if [ -z "$new_addr" ] || [ "$new_addr" = "null" ]; then
    new_addr=$(hyprctl clients -j | jq -r 'sort_by(.focusHistoryID) | .[-1] | .address')
  fi

  if [ -n "$new_addr" ] && [ "$new_addr" != "null" ]; then
    # Store the address and monitor name
    echo "$new_addr $monitor_name" >"$ADDR_FILE"
    debug_echo "Terminal created with address: $new_addr in special workspace on monitor $monitor_name"

    # Small delay to ensure it's properly in special workspace
    sleep 0.2

    # Now bring it back with the same animation as subsequent shows
    # Use movetoworkspacesilent to avoid affecting workspace history
    dispatch_window_workspace "$new_addr" "$CURRENT_WS"
    dispatch_window_pin "$new_addr"
    animate_slide_down "$new_addr" "$target_x" "$target_y" "$width" "$height"

    return 0
  fi

  debug_echo "Failed to get terminal address"
  return 1
}

# Main logic
if terminal_exists; then
  TERMINAL_ADDR=$(get_terminal_address)
  debug_echo "Found existing terminal: $TERMINAL_ADDR"
  focused_monitor=$(get_monitor_info | awk '{print $6}')
  dropdown_monitor=$(get_terminal_monitor)
  if [ "$focused_monitor" != "$dropdown_monitor" ]; then
    debug_echo "Monitor focus changed: moving dropdown to $focused_monitor"
    # Calculate new position for focused monitor
    pos_info=$(calculate_dropdown_position)
    read -r target_x target_y width height monitor_name <<<"$pos_info"
    # Move and resize window
    dispatch_window_move "$TERMINAL_ADDR" "$target_x" "$target_y"
    dispatch_window_resize "$TERMINAL_ADDR" "$width" "$height"
    # Update ADDR_FILE
    echo "$TERMINAL_ADDR $monitor_name" >"$ADDR_FILE"
  fi

  if terminal_in_special; then
    debug_echo "Bringing terminal from scratchpad with slide down animation"

    # Calculate target position
    pos_info=$(calculate_dropdown_position)
    read -r target_x target_y width height <<<"$pos_info"

    # Use movetoworkspacesilent to avoid affecting workspace history
    dispatch_window_workspace "$TERMINAL_ADDR" "$CURRENT_WS"
    dispatch_window_pin "$TERMINAL_ADDR"

    # Set size and animate slide down
    dispatch_window_resize "$TERMINAL_ADDR" "$width" "$height"
    animate_slide_down "$TERMINAL_ADDR" "$target_x" "$target_y" "$width" "$height"

    dispatch_window_focus "$TERMINAL_ADDR"
  else
    debug_echo "Hiding terminal to scratchpad with slide up animation"

    # Get current geometry for animation
    CLIENTS=""
    refresh_clients
    geometry=$(get_window_geometry "$TERMINAL_ADDR")
    if [ -n "$geometry" ]; then
      read -r curr_x curr_y curr_width curr_height <<<"$geometry"

      debug_echo "Current geometry: ${curr_x},${curr_y} ${curr_width}x${curr_height}"

      # Animate slide up first
      animate_slide_up "$TERMINAL_ADDR" "$curr_x" "$curr_y" "$curr_width" "$curr_height"

      # Small delay then move to special workspace and unpin
      sleep 0.1
      dispatch_window_pin "$TERMINAL_ADDR" # Unpin (toggle)
      dispatch_window_workspace "$TERMINAL_ADDR" "$SPECIAL_WS"
    else
      debug_echo "Could not get window geometry, moving to scratchpad without animation"
      dispatch_window_pin "$TERMINAL_ADDR"
      dispatch_window_workspace "$TERMINAL_ADDR" "$SPECIAL_WS"
    fi
  fi
else
  debug_echo "No existing terminal found, creating new one"
  if spawn_terminal; then
    TERMINAL_ADDR=$(get_terminal_address)
    if [ -n "$TERMINAL_ADDR" ]; then
      dispatch_window_focus "$TERMINAL_ADDR"
    fi
  fi
fi
