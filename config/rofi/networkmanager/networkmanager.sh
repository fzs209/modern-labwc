#!/bin/bash

#####################################
## author @Harsh-bin Github #########
#####################################

#  Configuration
notify_id="string:x-canonical-private-synchronous:networkmanager"
config_dir="$HOME/.config/rofi/networkmanager"
list_theme="$config_dir/list.rasi"
enable_theme="$config_dir/enable.rasi"
ssid_theme="$config_dir/ssid.rasi"
password_theme="$config_dir/password.rasi"
# captive portal url
url_file="/tmp/captive_login.url"

####################################################
# Functions ########################################
####################################################

############################
# Notification functionns ##
############################
notify() {
    # Close the animated notification
    if [ "$1" = "close" ]; then
        gdbus call \
            --session \
            --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications \
            --method org.freedesktop.Notifications.CloseNotification \
            "$(</tmp/notify.id)" >/dev/null 2>&1 &
        return 0
    fi
    notify-send -p -h "$notify_id" "$@"
}

# Animate WIFI connection
animate_connection() {
    local title="$1"
    local ssid_name="$2"
    local icons=("󰤯" "󰤟" "󰤢" "󰤥" "󰤨")

    for count in {1..5}; do
        for icon in "${icons[@]}"; do
            animate_id=$(notify "$icon    $title" "$ssid_name")
            # Save notification id
            echo "$animate_id" >/tmp/notify.id
            sleep 0.4
        done
    done
}

# Generic animation for VPN/Ethernet and Others
animate_action() {
    local icon="$1"
    local title="$2"
    local target_name="$3"
    local dots=("" "." ".." "...")

    for count in {1..5}; do
        for dot in "${dots[@]}"; do
            animate_id=$(notify "$icon    $title${dot}" "$target_name")
            echo "$animate_id" >/tmp/notify.id
            sleep 0.4
        done
    done
}

###################
# WIFI Functions ##
###################

# Check internet connection
connectivity_check() {
    local ssid="$1"
    local sig="$2"
    local notify_u=${3:-no}

    # Map icons to signal strength
    if [[ -n "$sig" ]]; then
        if ((sig >= 80)); then
            icon="󰤩"
        elif ((sig >= 60)); then
            icon="󰤦"
        elif ((sig >= 40)); then
            icon="󰤣"
        elif ((sig >= 20)); then
            icon="󰤠"
        else
            icon="󰤫"
        fi
    fi

    local url="http://connectivitycheck.gstatic.com/generate_204"
    response=$(curl -s -o /dev/null -w "%{http_code}\t%{redirect_url}" \
        --connect-timeout 2 "$url")
    curl_exit=$?

    IFS=$'\t' read -r http_code redirect_url <<<"$response"

    if [[ $curl_exit -ne 0 || "$http_code" == "000" ]]; then
        echo -e "$icon   $ssid\n<span weight='light' size='small' alpha='85%'>      Connected, no internet</span>"
        [[ "$notify_u" == "notify" ]] && notify "$icon    $ssid" "Connected, no internet"
    elif [[ "$http_code" == "204" ]]; then
        echo -e " Connected to $ssid\n<span weight='light' size='small' alpha='85%'>      Click to disconnect</span>"
    else
        # Captive portal
        echo -e "$icon   $ssid\n<span weight='light' size='small' alpha='85%'>      Click to sign in to network</span>"
        [[ "$notify_u" == "notify" ]] && notify "$icon    $ssid" "Sign in to Wi-Fi network"
        [[ -n "$redirect_url" ]] && echo "$redirect_url" >"$url_file"
    fi
}

prompt_password() {
    retry="${1:-no}"

    if [ "$retry" == "no" ]; then
        rofi -dmenu -password -p "Password" -theme "$password_theme"
    else
        rofi -dmenu -password -p "Password (Retry)" -theme "$password_theme"
    fi
}

connect_and_verify() {
    local target_ssid="$1"
    local target_sig="$2"
    local anim_pid="$3"
    local pass="$4"
    local silent_fail="$5"

    local output
    if [[ -n "$pass" ]]; then
        output=$(nmcli dev wifi connect "$target_ssid" password "$pass" 2>&1)
    else
        output=$(nmcli dev wifi connect "$target_ssid" 2>&1)
    fi
    local connect_exit=$?

    # Stop animation
    kill "$anim_pid" 2>/dev/null

    if [[ $connect_exit -eq 0 ]]; then
        notify "    Connected to" "$target_ssid"
        sleep 0.5
        connectivity_check "$target_ssid" "$target_sig" "notify"
        return 0
    else
        if [[ "$output" == *"could not be found"* ]] || [[ "$output" == *"No network with SSID"* ]]; then
            notify "    Connection Failed..." "'$target_ssid' is not in rang..."
            return 1
        else
            # Only trigger generic fail if we didn't specify 'silent'
            [[ "$silent_fail" != "silent" ]] && notify "    Connection Failed..."
            return 2 # Represents an auth error or other general failure
        fi
    fi
}

connect_secure_loop() {
    local target_ssid="$1"
    local target_sig="$2"
    local retry="no"

    while true; do
        local pass
        pass=$(prompt_password "$retry")

        [[ -z "$pass" ]] && exit 0

        animate_connection "Connecting to" "$target_ssid" &
        local anim_pid=$!

        # Delete the old connection profile to ensure a fresh start
        nmcli connection delete id "$target_ssid" &>/dev/null

        connect_and_verify "$target_ssid" "$target_sig" "$anim_pid" "$pass" "silent"
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            break
        elif [[ $exit_code -eq 1 ]]; then
            return 0 # Out of range, exit loop entirely
        elif [[ $exit_code -eq 2 ]]; then
            retry="yes"
            notify "    Connection Failed Retrying..."
        fi
    done
}

handle_wifi_connection() {
    local target_ssid="$1"
    local target_sig="$2"
    local raw_selection="$3"
    local saved_profile_exists=false

    # Check if a saved profile already exists
    if nmcli -g NAME connection show | grep -Fxq "$target_ssid"; then
        saved_profile_exists=true
    fi

    # Try saved profile first (Auto-Connect)
    if [[ "$saved_profile_exists" == "true" ]]; then
        animate_connection "Connecting to saved network" "$target_ssid" &
        local anim_pid=$!

        # Use shared logic without a password
        connect_and_verify "$target_ssid" "$target_sig" "$anim_pid" "" "silent"
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            exit 0
        elif [[ $exit_code -eq 1 ]]; then
            exit 0 # Not in range, error already notified natively by connect_and_verify
        else
            notify "    Login failed. Retrying with password..."
            # Auto-connect failed, falls through to password logic below
        fi
    fi

    # Handle Security
    if [[ "$raw_selection" =~ (󰤪|󰤧|󰤤|󰤡|󰤬) ]]; then
        connect_secure_loop "$target_ssid" "$target_sig"
    else
        # Open Network
        animate_connection "Connecting to" "$target_ssid" &
        local anim_pid=$!

        connect_and_verify "$target_ssid" "$target_sig" "$anim_pid"
    fi
}

manual_connect() {
    manual_ssid=$(rofi -dmenu -p "SSID" -theme "$ssid_theme")
    [[ -z "$manual_ssid" ]] && exit 0

    manual_password=$(prompt_password)

    animate_connection "Connecting to" "$manual_ssid" &
    anim_pid=$!

    if nmcli dev wifi connect "$manual_ssid" hidden yes password "$manual_password" >/dev/null 2>&1; then
        kill "$anim_pid" 2>/dev/null
        notify "    Connected to" "$manual_ssid"
    else
        kill "$anim_pid" 2>/dev/null
        notify "    Connection Failed..."
    fi
}

###########################
# VPN/ETHERNET Functions ##
###########################

# Connection handler for VPN and Ethernet
toggle_connection() {
    local icon="$1"
    local target="$2"
    local action="$3"
    local network_type="$4"

    if [[ "$action" == "up" ]]; then
        animate_action "$icon" "Connecting" "$target" &
        local anim_pid=$!

        local cmd
        if [[ "$network_type" == "Ethernet" ]]; then
            cmd="nmcli device connect $target"
        else
            cmd="nmcli connection up $target"
        fi

        if eval "$cmd" >/dev/null 2>&1; then
            kill "$anim_pid" 2>/dev/null
            notify "    Connected to" "$target"
        else
            kill "$anim_pid" 2>/dev/null
            notify "    $network_type Connection Failed" "$target"
        fi
    else
        local cmd
        if [[ "$network_type" == "Ethernet" ]]; then
            cmd="nmcli device disconnect $target"
        else
            cmd="nmcli connection down $target"
        fi

        if eval "$cmd" >/dev/null 2>&1; then
            notify "$icon    Disconnected from" "$target"
        else
            notify "    Failed to disconnect" "$target"
        fi
    fi
}

show_rofi_list() {
    local icon="$1"
    local network_type="$2"
    local raw_list="$3"

    local list=""
    local list_entry=""

    local active name type
    while IFS=':' read -r active name type; do
        [[ -z "$name" ]] && continue
        if [[ "$active" == "yes" ]]; then
            list_entry="$icon   $name\n<span weight='light' size='small' alpha='85%'>      Click to disconnect</span>"
        else
            list_entry="$icon   $name\n<span weight='light' size='small' alpha='85%'>      Click to connect</span>"
        fi

        if [[ -z "$list" ]]; then
            list="$list_entry"
        else
            list="${list}\x1f${list_entry}"
        fi
    done <<<"$raw_list"

    local choice
    choice=$(echo -en "$list" | rofi -sep '\x1f' -markup-rows -dmenu -theme-str "textbox-prompt-colon{str: \"$icon \";}" -theme "$list_theme")
    [[ -z "$choice" ]] && exit 0

    local first_line="${choice%%$'\n'*}"
    local target="${first_line#*󰒄   }"

    local action="up"
    [[ "$choice" == *"disconnect"* ]] && action="down"

    toggle_connection "$icon" "$target" "$action" "$network_type"
}

############################################################
### Main Logic #############################################
############################################################

# Check Wi-Fi status
wifi_status=$(nmcli radio wifi)

if [[ "$wifi_status" == "disabled" ]]; then
    choice=$(echo -e "   Enable Wi-Fi" | rofi -dmenu -theme "$enable_theme")
    [[ -z "$choice" ]] && exit 0

    nmcli radio wifi on
    notify "󱚽    Wi-Fi Enabled..."
fi

animate_action " " "Checking for Wi-Fi" &
anim_pid=$!

###############################
# Build WIFI List #############
###############################

# Gather WIFI network information
raw_wifi_data=$(nmcli -t -f active,ssid,security,signal dev wifi list --rescan no)
# Trigger wifi scan in background
nmcli device wifi rescan
# Get the currently connected SSID
connected=$(awk -F: '$1=="yes" {print $2 "|" $4}' <<<"$raw_wifi_data")
IFS='|' read -r connected_ssid connected_sig <<<"$connected"

# Compose status line
if [[ -n "$connected_ssid" ]]; then
    connection_status=$(connectivity_check "$connected_ssid" "$connected_sig")
else
    connection_status="󱛅   Wi-Fi not connected"
fi

# Format the list with Security Icons, Signal Strength and Sort based on Signal Strength
raw_wifi_list=$(awk -F: '
{
    if ($2 != "") {
        sig = $4
        is_locked = ($3 ~ /WPA|WEP|802\.1X/)
        
        if (is_locked) {
            if      (sig >= 80) icon = "󰤪"
            else if (sig >= 60) icon = "󰤧" 
            else if (sig >= 40) icon = "󰤤" 
            else if (sig >= 20) icon = "󰤡"
            else                icon = "󰤬" 
        } else {
            if      (sig >= 80) icon = "󰤨" 
            else if (sig >= 60) icon = "󰤥" 
            else if (sig >= 40) icon = "󰤢" 
            else if (sig >= 20) icon = "󰤟" 
            else                icon = "󰤯" 
        }

        printf "%3d:%s   %s\n", sig, icon, $2
    }
}' <<<"$raw_wifi_data" | sort -rn)

wifi_list=$(cut -d: -f2- <<<"$raw_wifi_list" | tr '\n' '\037')

#################################################
# Fetch VPN and Ethernet profiles dynamically ###
#################################################
# Fetch VPNs
vpn_raw=$(nmcli -g ACTIVE,NAME,TYPE connection show | grep -iE ':(vpn|wireguard)$')
# Fetch physical Ethernet devices
eth_raw=$(nmcli -t -f STATE,DEVICE,TYPE device | awk -F: '/:ethernet$/ && /^(connected|disconnected):/ {print ($1=="connected"?"yes":"no") ":" $2 ":" $3}')

build_menu_entry() {
    local icon="$1"
    local network_type="$2"
    local raw_list="$3"
    
    local list_count=0
    local menu_entry=""

    [[ -n "$raw_list" ]] && list_count=$(wc -l <<< "$raw_list")

    if [[ $list_count -eq 1 ]]; then
        local active name type
        IFS=':' read -r active name type <<< "$raw_list"
        
        if [[ "$active" == "yes" ]]; then
            menu_entry="$icon   $name\n<span weight='light' size='small' alpha='85%'>      Click to disconnect</span>"
        else
            menu_entry="$icon   $name\n<span weight='light' size='small' alpha='85%'>      Click to connect</span>"
        fi
    elif [[ $list_count -gt 1 ]]; then
        if [[ "$raw_list" =~ (^|$'\n')yes: ]]; then
            menu_entry="$icon   $network_type Connected\n<span weight='light' size='small' alpha='85%'>      Click to view $network_type networks</span>"
        else
            menu_entry="$icon   $network_type\n<span weight='light' size='small' alpha='85%'>      Click to view $network_type networks</span>"
        fi
    fi

    # Output
    [[ -n "$menu_entry" ]] && printf '%s' "$menu_entry"
}

dynamic_entries=""

# Build VPN Menu Entry
vpn_entry=$(build_menu_entry "󰒄" "VPN" "$vpn_raw")
if [[ -n "$vpn_entry" ]]; then
    dynamic_entries="${vpn_entry}"
fi

# Build Ethernet Menu Entry
eth_entry=$(build_menu_entry "󰈀" "ETHERNET" "$eth_raw")
if [[ -n "$eth_entry" ]]; then
    # Add the \x1f separator only if dynamic_entries is not empty
    [[ -n "$dynamic_entries" ]] && dynamic_entries="${dynamic_entries}\x1f"
    dynamic_entries="${dynamic_entries}${eth_entry}"
fi

# Stop and close wifi search notification
kill "$anim_pid" 2>/dev/null
notify close

# Show Rofi Menu (using '\x1f' as seperator)
choice=$(echo -en "󱚼   Disable Wi-Fi\x1f${dynamic_entries}\x1f${connection_status}\x1f   Manual Setup\x1f${wifi_list}" |
    rofi -sep '\x1f' -markup-rows -dmenu -theme "$list_theme")
[[ -z "$choice" ]] && exit 0

# Extract raw line and just the SSID
raw_choice="$choice"
ssid_name="${choice#*   }"

# Extract the wifi signal
if [[ "$wifi_list" == *"$choice"* ]]; then
    matched_line=$(grep -F ":$choice" <<<"$raw_wifi_list")
    ssid_sig="${matched_line%%:*}"
    ssid_sig="${ssid_sig// /}" # trim whitespace from the %3d formatting
fi

##############################
# Handle user selection ######
##############################
case "$raw_choice" in

"󰒄   VPN"*)
    show_rofi_list "󰒄" "VPN" "$vpn_raw"
    ;;

"󰈀   ETHERNET"*)
    show_rofi_list "󰈀" "ETHERNET" "$eth_raw"
    ;;

*"󰒄   "*) # Single VPN item selected
    first_line="${raw_choice%%$'\n'*}"
    vpn_target="${first_line#*󰒄   }"
    action="up"
    [[ "$raw_choice" == *"disconnect"* ]] && action="down"
    toggle_connection "󰒄" "$vpn_target" "$action" "VPN"
    ;;

*"󰈀   "*) # Single Ethernet item selected
    first_line="${raw_choice%%$'\n'*}"
    eth_target="${first_line#*󰈀   }"
    action="up"
    [[ "$raw_choice" == *"disconnect"* ]] && action="down"
    toggle_connection "󰈀" "$eth_target" "$action" "Ethernet"
    ;;

*"Disable Wi-Fi"*)
    nmcli radio wifi off
    notify "󱚼    Wi-Fi Disabled..."
    ;;

*"Manual Setup"*)
    manual_connect
    ;;

*"Connected to $connected_ssid"*)
    # Disconnect from the current active network
    nmcli connection down "$connected_ssid"
    notify "󱛅    Disconnected From" "$connected_ssid"
    ;;

*"Click to sign in to network"*)
    login_url=$(<"$url_file")
    xdg-open "$login_url"
    ;;

*"no internet"* | *"Wi-Fi not connected"*)
    exit 0
    ;;

*)
    # Connect to a specific Wi-Fi network
    handle_wifi_connection "$ssid_name" "$ssid_sig" "$raw_choice"
    ;;

esac
