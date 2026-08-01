#!/bin/bash

#####################################
## author @Harsh-bin Github #########
#####################################

# Configuration
config_dir="$HOME/.config/rofi/rofi-tube"
thumb_dir="$HOME/.local/share/rofi-tube/thumbnails"
history_file="$config_dir/search-history.json"
config_file="$config_dir/rofi-tube.conf"
pid_file="$config_dir/rofi-tube.pid"
cookie_file="$config_dir/youtube-cookies.txt"
playlist_file="$config_dir/current-playlist.json"
loop_state_file="$config_dir/playlist_loop.json"

rofi_search_theme="$config_dir/search-window.rasi"
rofi_tube_theme="$config_dir/rofi-tube.rasi"
rofi_menu_theme="$config_dir/horizontal_menu.rasi"
rofi_playlist_theme="$config_dir/playlist-window.rasi"

rofi_v_menu_theme="$HOME/.config/rofi/vertical_style_menu.rasi"
rofi_h_menu_theme="$HOME/.config/rofi/horizontal_menu.rasi"
rofi_prom_theme="$HOME/.config/rofi/placeholder.rasi"

yt_icon="$config_dir/youtube.png"
music_icon="$config_dir/yt-music.png"
delete_icon="$config_dir/delete_icon.png"
settings_icon="$config_dir/settings_icon.png"

mpv_socket_path="/tmp/rofi_tube.sock"
vlc_rc_host="127.0.0.1"
vlc_rc_port=12345
notify_id="string:x-canonical-private-synchronous:nowplaying" # using nowplaying notification id
prefetch_dir="/tmp/rofi_tube_prefetch"

mkdir -p "$thumb_dir"
mkdir -p "$prefetch_dir"

# Dependency Check
is_installed() {
    command -v "$1" &>/dev/null
}

for pkg in jq curl yt-dlp rofi socat nc; do
    if ! is_installed "$pkg"; then
        echo "Error: '$pkg' is not installed."
        exit 1
    fi
done

# Default configs
if is_installed "mpv"; then
    player="mpv"
elif is_installed "vlc"; then
    player="vlc"
else
    echo "[!] Error: neither mpv nor vlc is installed." >&2
    exit 1
fi
resolution="1080"
codec="h264"
playlist="true"
playlist_limit="50"
cache_max_mb="40"
cache_min_mb="35"

# Valid options
valid_players=("mpv" "vlc")
valid_resolutions=("best" "2160" "1440" "1080" "720" "480" "360" "240" "144")
valid_codecs=("h264" "av1" "vp9")
valid_playlist_modes=("true" "false")

# Create default config file if it doesn't exist
if [ ! -f "$config_file" ]; then
    cat >"$config_file" <<EOF
# Player: mpv, vlc
player=$player

# Resolution: best, 2160, 1440, 1080, 720, 480, 360, 240, 144
resolution=$resolution

# Codec: h264, av1, vp9
codec=$codec

# Playlist Mode: true/false
playlist=$playlist

# Max Playlist Items (number)
playlist_limit=$playlist_limit

# Cache Management (in MB)
cache_min_mb=$cache_min_mb
cache_max_mb=$cache_max_mb

EOF
    echo "[*] Created default config file: ~${config_file#$HOME}"
fi

# Function to check if value exists in array
is_valid() {
    local value="$1"
    shift
    local array=("$@")
    for item in "${array[@]}"; do
        [[ "$item" == "$value" ]] && return 0
    done
    return 1
}

# Read and validate config file
while IFS='=' read -r key val; do
    [[ $key == \#* ]] && continue
    [[ -z $key ]] && continue

    key=$(echo "$key" | xargs)
    val=$(echo "$val" | xargs)

    case "$key" in
    player)
        if is_valid "$val" "${valid_players[@]}" && is_installed "$val"; then
            player="$val"
        else
            reason="Invalid"
            is_valid "$val" "${valid_players[@]}" || reason="Unsupported"
            is_installed "$val" || reason="Not installed"
            echo "[!] $reason player '$val' in config. Using default: $player" >&2
            notify-send -t 6000 "󰀦    Important!" "$reason player '$val' in config\nUsing default: $player"
        fi
        ;;
    resolution)
        if is_valid "$val" "${valid_resolutions[@]}"; then
            resolution="$val"
        else
            echo "[!] Invalid resolution '$val' in config. Using default: $resolution" >&2
            notify-send -t 6000 "󰀦    Important!" "Invalid resolution '$val' in config\nUsing default: $resolution"
        fi
        ;;
    codec)
        if is_valid "$val" "${valid_codecs[@]}"; then
            codec="$val"
        else
            echo "[!] Invalid codec '$val' in config. Using default: $codec" >&2
            notify-send -t 6000 "󰀦    Important!" "Invalid codec '$val' in config\nUsing default: $codec"
        fi
        ;;
    playlist)
        if is_valid "${val,,}" "${valid_playlist_modes[@]}"; then
            playlist="${val,,}"
        else
            echo "[!] Invalid playlist mode '$val' in config. Using default: $playlist" >&2
            notify-send -t 6000 "󰀦    Important!" "Invalid playlist mode '$val' in config\nUsing default: $playlist"
        fi
        ;;
    playlist_limit)
        if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -gt 0 ]; then
            playlist_limit="$val"
        else
            echo "[!] Invalid playlist_limit '$val' in config. Using default: $playlist_limit" >&2
            notify-send -t 6000 "󰀦    Important!" "Invalid playlist_limit '$val' in config\nUsing default: $playlist_limit"
        fi
        ;;
    cache_min_mb)
        if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -gt 0 ]; then
            cache_min_mb="$val" 
        else
            echo "[!] Invalid cache_min_mb '$val' in config. Using default: $cache_min_mb" >&2
            notify-send -t 6000 "󰀦    Important!" "Invalid cache_min_mb '$val' in config\nUsing default: $cache_min_mb"
        fi
        ;;
    cache_max_mb)
        if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -gt 0 ]; then
            cache_max_mb="$val"
        else
            echo "[!] Invalid cache_max_mb '$val' in config. Using default: $cache_max_mb" >&2
            notify-send -t 6000 "󰀦    Important!" "[!] Invalid cache_max_mb '$val' in config\nUsing default: $cache_max_mb"
        fi
        ;;
    esac
done <"$config_file"

# Final validation for cache values
if [ "$cache_min_mb" -gt "$cache_max_mb" ]; then
    echo "[!] Fixing cache values: min ($cache_min_mb) > max ($cache_max_mb)" >&2
    notify-send -t 6000 "󰀦    Fixing cache values" "min ($cache_min_mb) > max ($cache_max_mb)"
    
    # Swap values to ensure min is less than max
    temp=$cache_min_mb
    cache_min_mb=$cache_max_mb
    cache_max_mb=$temp
fi

# Player to use
player_bin="$player"

##################################
# Settings window ################
##################################
settings_window() {
    while true; do
        # Build the main menu dynamically based on playlist state
        local menu_options="Player\nResolution\nCodec\n"
        local menu_lines=0

        if [[ "$playlist" == "true" ]]; then
            menu_options+="Disable Playlist Mode\nPlaylist Limit\nCache Size"
            menu_lines=6
        else
            menu_options+="Enable Playlist Mode\nCache Size"
            menu_lines=5
        fi

        # Show main settings menu
        local main_choice=$(echo -e "$menu_options" | rofi -dmenu -mesg "<b>Rofi-Tube Settings</b>" -theme "$rofi_v_menu_theme" \
            -theme-str "listview { lines: $menu_lines; }")
       
        [[ -z "$main_choice" ]] && return 0        

        # Handle choices
        case "$main_choice" in
            "Player")
                local p_options="vlc\nmpv"
                local p_choice=$(echo -e "$p_options" | rofi -dmenu -mesg "$(printf '<b>Choose Player</b>\n(Current: %s)' "$player_bin")" -theme "$rofi_h_menu_theme")
                
                if [[ -n "$p_choice" ]]; then
                    sed -i "s/^player=.*/player=$p_choice/" "$config_file"
                    # Override the script's current variable so settings window can update/refresh
                    player_bin="$p_choice"
                    echo "[#] Player changed to $player_bin"
                fi
                ;;

            "Resolution")
                local res_options="best\n2160p\n1440p\n1080p\n720p\n480p\n360p\n240p\n144p"
                local res_choice=$(echo -e "$res_options" | rofi -dmenu -mesg "$(printf '<b>Choose Video Resolution</b>\n(Current: %s)' "${resolution}p")" \
                    -theme "$rofi_v_menu_theme" -theme-str "listview { lines: 9; }")
                
                if [[ -n "$res_choice" ]]; then
                    res_choice=${res_choice%p}
                    sed -i "s/^resolution=.*/resolution=$res_choice/" "$config_file"
                    # This will not cause problem as when settings window closes entire script exits, This is just to make UI beautiful
                    resolution="${res_choice}p" 
                    echo "[#] Resolution changed to $resolution"
                fi
                ;;

            "Codec")
                local c_options="h264\nav1\nvp9"
                local c_choice=$(echo -e "$c_options" | rofi -dmenu -mesg "$(printf '<b>Choose Video Codec</b>\n(Current: %s)' "$codec")" \
                    -theme "$rofi_h_menu_theme" -theme-str "listview { columns: 3; lines: 1; }")
                
                if [[ -n "$c_choice" ]]; then
                    sed -i "s/^codec=.*/codec=$c_choice/" "$config_file"
                    codec="$c_choice"
                    echo "[#] Video codec changed to $codec"
                fi
                ;;

            "Enable Playlist Mode")
                sed -i 's/^playlist=.*/playlist=true/' "$config_file"
                playlist="true"
                echo "[#] Playlist mode enabled"
                ;;

            "Disable Playlist Mode")
                sed -i 's/^playlist=.*/playlist=false/' "$config_file"
                playlist="false"
                echo "[#] Playlist mode disabled"
                ;;

            "Playlist Limit")
                while true; do
                    local limit_input=$(rofi -dmenu -mesg "$(printf '<b>Enter Playlist Limit</b>\n(Current: %s)' "$playlist_limit")" \
                        -theme "$rofi_prom_theme")

                    [[ -z "$limit_input" ]] && break

                    if [[ "$limit_input" =~ ^[0-9]+$ ]]; then
                        sed -i "s/^playlist_limit=.*/playlist_limit=$limit_input/" "$config_file"
                        playlist_limit="$limit_input"
                        echo "[#] Playlist max limit set to $playlist_limit"
                        break
                    else
                        # Invalid input, loop runs again automatically reprompting window
                        echo "[!] Error: Invalid input please enter number"
                        continue 
                    fi
                done
                ;;

            "Cache Size")
                while true; do
                    local cache_input=$(rofi -dmenu -mesg "$(printf '<b>Enter Cache Min Max Size</b>\n(Current: %sMb %sMb)' "$cache_min_mb" "$cache_max_mb")" \
                        -theme "$rofi_prom_theme")

                    [[ -z "$cache_input" ]] && break
                    
                    # Validates inputs like "30 40", "30MB  40MB"
                    if [[ "$cache_input" =~ ^([0-9]+)(mb|MB|Mb)?\ +([0-9]+)(mb|MB|Mb)?$ ]]; then
                        local min_mb="${BASH_REMATCH[1]}"
                        local max_mb="${BASH_REMATCH[3]}"
                        # Swap values if min is greater than max
                        [[ "$min_mb" -gt "$max_mb" ]] && {
                            local temp=$min_mb
                            min_mb=$max_mb
                            max_mb=$temp
                        }                        
                        
                        sed -i "s/^cache_min_mb=.*/cache_min_mb=$min_mb/" "$config_file"
                        sed -i "s/^cache_max_mb=.*/cache_max_mb=$max_mb/" "$config_file"
                        cache_min_mb="$min_mb"
                        cache_max_mb="$max_mb"
                        echo "[#] Cache limit set (min $cache_min_mb) (max $cache_max_mb)"
                        break
                    else
                        # Invalid input, loop runs again automatically reprompting window
                        echo "[!] Error: Invalid input please enter number seperated by space e.g, 30 40"
                        continue 
                    fi
                done
                ;;
        esac
    done
}

#################################
# Utility Functions #############
#################################

notify() {
    local icon_arg=""
    [ -n "$3" ] && icon_arg="-i $3"

    # Close the animated notification
    if [ "$1" = "close" ]; then
        kill "$(</tmp/notify_loop.pid)" >/dev/null 2>&1 & # Kill the animation loop
        2>/dev/null &
        # Closes the notification
        gdbus call \
            --session \
            --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications \
            --method org.freedesktop.Notifications.CloseNotification \
            "$(</tmp/notify.id)" >/dev/null 2>&1 &

        return 0
    fi

    # Show animated notification
    if [ "$4" = "animate" ]; then
        (
            local dots=("" "." ".." "...")
            for count in {1..5}; do
                for dot in "${dots[@]}"; do
                    animate_id=$(notify-send $icon_arg -p -h "$notify_id" "$1${dot}" "$2" 2>/dev/null)
                    # Save current notification ID to file
                    # So we can stop it from playlist loop
                    echo "$animate_id" >/tmp/notify.id
                    sleep 0.4
                done
            done
            # Close notification immediately after animation is complete
            gdbus call \
                --session \
                --dest org.freedesktop.Notifications \
                --object-path /org/freedesktop/Notifications \
                --method org.freedesktop.Notifications.CloseNotification \
                "$animate_id" >/dev/null 2>&1 &
        ) &
        # Save loop ID to file
        echo "$!" >/tmp/notify_loop.pid
    else
        notify-send $icon_arg -h "$notify_id" "$1" "$2" 2>/dev/null &
    fi
}

run_rofi() {
    local cmd_input="$1" theme="$2" prompt="$3" message="$4" select_pattern="$5"
    # Using -sep (element separator) as "\x1e" so we can show a single element with multiple lines.
    local args=("-dmenu" "-p" "$prompt" "-show-icons" "-theme" "$theme" "-sep" '\x1e' "-markup-rows")
    [ -n "$message" ] && args+=("-mesg" "$message")
    [ -n "$select_pattern" ] && args+=("-select" "$select_pattern")
    echo -ne "$cmd_input" | rofi "${args[@]}"
}

take_control_of_session() {
    local current_pid=$$
    if [ -f "$pid_file" ]; then
        local old_pid=$(<"$pid_file")
        if [ -n "$old_pid" ] && [ "$old_pid" != "$current_pid" ]; then
            if [[ $(ps -p "$old_pid" -o cmd=) == *rofi-tube.sh* ]]; then
                echo "[*] Session Handover: Killed previous playlist loop (PID: $old_pid)"
            fi
            kill -TERM "$old_pid" 2>/dev/null || true
        fi
    fi
    echo "$current_pid" >"$pid_file"
    echo "[*] New Session ID registered: $current_pid"
}

ensure_cookie_file_exists() {
    if [ ! -f "$cookie_file" ]; then
        notify-send -t 0 "󰀦    Important!" \
            "No cookies file was found. Playback may be interrupted at any time.\nA temporary cookies file has been created at:\n$cookie_file\nSee \"get-cookies.txt\" in the same directory for more information."

        echo "[!] Cookie file not found. Creating at: $cookie_file" >&2
        echo "# Netscape HTTP Cookie File" >"$cookie_file"
    fi
}

get_art_file() {
    local vid_id="$1"
    local quality="${2:-default}"
    local art_path=""

    if [ "$quality" = "hq" ]; then
        local hq_dir="$thumb_dir/hq_thumbnails"
        art_path="$hq_dir/${vid_id}.jpg"
        # Fallback to default if HQ doesn't exist
        [ ! -f "$art_path" ] && art_path="$thumb_dir/${vid_id}.jpg"
    else
        art_path="$thumb_dir/${vid_id}.jpg"
    fi

    if [ -f "$art_path" ]; then
        echo "$art_path"
    else
        echo ""
    fi
}

truncate_text() {
    local str="$1"
    if ((${#str} > 70)); then
        echo "${str:0:70}..."
    else
        echo "$str"
    fi
}

###################################
# Cache Management with LRU #######
###################################

manage_cache() {
    # convert megabytes into bytes
    local limit_bytes=$((cache_max_mb * 1024 * 1024))
    local target_bytes=$((cache_min_mb * 1024 * 1024))
    [ ! -d "$thumb_dir" ] && return

    # du -sb calculates exact directory bytes
    local total_bytes
    read -r total_bytes _ < <(du -sb "$thumb_dir" 2>/dev/null)
    [ -z "$total_bytes" ] && return
    # current cache size is under the maximum limit, so return
    [ "$total_bytes" -le "$limit_bytes" ] && return

    # Extract protected IDs from history file using jq
    # create a space-separated string of IDs
    local protected_ids=""
    if [ -f "$history_file" ]; then
        protected_ids=$(jq -r '[.[].id] | join(" ")' "$history_file" 2>/dev/null)
    fi

    echo "[!] Cache limit exceeded ($((total_bytes / 1024 / 1024)) MB). Clearing old files (excluding history)..." >&2

    # Find thumbnail files and process them with awk.

    # 'find' prints:
    # %T@: Last modification time (allows sorting thumbnails based on usage)
    # %s: File size in bytes
    # %p: Full file path
    # Using \0: A null character to separate lines athough not needed as file names are youtube ID

    # sort:
    # -z: Expect null-separated input (\0)
    # -n: Sort numerically. Since the first field is the timestamp, this sorts from oldest to newest.
    find "$thumb_dir" -maxdepth 1 -type f -name "*.jpg" -printf "%T@ %s %p\0" 2>/dev/null |
        sort -z -n |
        awk -v RS='\0' -v ORS='\0' -v total="$total_bytes" -v target="$target_bytes" -v prot_str="$protected_ids" '
            BEGIN {
                # Load protected IDs into an array
                n = split(prot_str, tmp, " ")
                for (i=1; i<=n; i++) {
                    # Map "ID" to "ID.jpg"
                    protected[tmp[i] ".jpg"] = 1
                }
            }
            {
                size = $2
                
                # Isolate the full file path
                path = $0
                sub(/^[^ ]+ [^ ]+ /, "", path)
                
                # Isolate the filename (basename)
                fname = path
                sub(/^.*\//, "", fname)
                
                # Skip protected thumbnails
                if (fname in protected) {
                    next
                }

                if (total > target) {
                    print path        # Send to xargs for deletion
                    total -= size     # Subtract from our running total
                } else {
                    exit 0            # Reached target size
                }
            }
        ' | xargs -0 --no-run-if-empty rm -f
}

#############################
# History Management ########
#############################

get_history() {
    [ ! -f "$history_file" ] && return
    jq -j 'reverse | map("\(.query)\\x00icon\\x1f'"$thumb_dir"'/\(.id).jpg") | join("\\x1e")' "$history_file" 2>/dev/null
}

update_history_file() {
    local query="$1" vid_id="$2"
    [ ! -f "$history_file" ] && echo "[]" >"$history_file"

    jq --arg q "$query" --arg id "$vid_id" '
        [ .[] | select(.query | ascii_downcase != ($q | ascii_downcase)) ]
        + [{"query": $q, "id": $id}]
        | .[-150:]
    ' "$history_file" >"$history_file.tmp" && mv "$history_file.tmp" "$history_file"
}

delete_history_ui() {
    [ ! -f "$history_file" ] && return
    local selected
    selected=$(echo -ne "$(get_history)" | rofi -dmenu \
        -multi-select \
        -p "[ Shift + Enter for multiple selection ]" \
        -sep "\x1e" \
        -theme "$rofi_search_theme")

    [ -z "$selected" ] && return

    # Convert the selected raw lines into a JSON array for filtering
    local selected_json
    selected_json=$(echo "$selected" | jq -R . | jq -s .)

    # Keep items NOT present in the selection array
    jq --argjson sel "$selected_json" '
        [ .[] | select(.query as $q | ($sel | index($q) | not)) ]
    ' "$history_file" >"$history_file.tmp" && mv "$history_file.tmp" "$history_file"

    echo "[!] History Updated. Selected items removed." >&2
    notify "History Updated" "Selected items removed from history." "$delete_icon"
}

#######################################
# Player control and commands #########
#######################################

send_mpv_command() {
    local cmd_json="$1"
    [ ! -S "$mpv_socket_path" ] && return 1
    echo "$cmd_json" | socat -t 1 - "UNIX-CONNECT:$mpv_socket_path" >/dev/null 2>&1
    return $?
}

send_vlc_command() {
    local cmd_str="$1"
    echo "$cmd_str" | nc -q 1 "$vlc_rc_host" "$vlc_rc_port" >/dev/null 2>&1
    return $?
}

# Finds correct player name if multiple instances of mpv is running, so that playerctl can follow it.
set_player_name() {
    if [[ "$player_bin" == *"mpv"* ]]; then
        # Use the PID we captured during startup
        local target_pid="$mpv_pid"

        if [[ -z "$target_pid" ]]; then
            echo "[!] Error: Could not find PID for MPV socket." >&2
            return 1
        fi

        # MPV might take a few seconds to launch and register to D-Bus, so we poll for it (10 seconds is enough)
        local bus_name=""
        for i in {1..100}; do
            bus_name=$(busctl --user list --no-legend | grep "org.mpris.MediaPlayer2.mpv" |
                awk -v pid="$target_pid" '$2 == pid {print $1}')

            [[ -n "$bus_name" ]] && break
            sleep 0.1
        done

        if [[ -n "$bus_name" ]]; then
            # Strip 'org.mpris.MediaPlayer2.' to get 'mpv.instance-xxxx'
            player_name="${bus_name#org.mpris.MediaPlayer2.}"
        else
            echo "[!] Error: MPV started but D-Bus (mpris) name not found." >&2
            return 1
        fi
    # We are killing all vlc instances, so vlc will always show as vlc.
    else
        player_name="vlc"
    fi
}

# Used for Initial Verification Only
is_player_running() {
    if [[ "$player_bin" == *"mpv"* ]]; then
        send_mpv_command '{"command":["get_version"]}'
        return $?
    else
        send_vlc_command "status"
        return $?
    fi
}

ensure_player_running() {
    if is_player_running; then
        echo "[#] $player_bin is already running."
        return 0
    fi

    echo "[#] Starting $player_bin"
    if [[ "$player_bin" == *"mpv"* ]]; then
        rm -f "$mpv_socket_path" # Clean up dead socket just in case
        mpv --idle=yes --force-window=immediate --input-ipc-server="$mpv_socket_path" >/dev/null 2>&1 &
        # Trap the mpv PID. It will be used to find the correct mpv name (ID).
        mpv_pid=$!
        set_player_name
        # Wait up to 10 seconds to genuinely accept commands
        for i in {1..50}; do
            if is_player_running; then
                echo "[#] MPV Socket ready"
                return 0
            fi
            sleep 0.2
        done
    else
        # Check if VLC is already running with the correct RC flags
        if pgrep -f "rc-host $vlc_rc_host:$vlc_rc_port" >/dev/null; then
            echo "[#] VLC (RC Mode) is already running and ready."
            return 0
        fi
        # Check if a "Normal" VLC is running (which blocks the RC instance)
        if pgrep -x "vlc" >/dev/null; then
            echo "[!] Conflict: Standard VLC instance detected." >&2

            local choice
            choice=$(echo -e "Yes\nNo" | rofi -dmenu \
                -theme "$rofi_menu_theme" \
                -p "VLC Conflict" \
                -mesg "VLC is running without Remote Control. Close it to continue?")

            if [[ "$choice" == "Yes" ]]; then
                killall vlc
                sleep 1
            else
                echo "[-] User chose not to close VLC. Exiting."
                exit 1
            fi
        fi

        # Start VLC with RC (disable vlc notifications)
        vlc --one-instance --extraintf rc --rc-host "$vlc_rc_host:$vlc_rc_port" --qt-notification=0 >/dev/null 2>&1 &
        for i in {1..50}; do
            if is_player_running; then
                echo "[#] VLC RC ready"
                set_player_name
                return 0
            fi
            sleep 0.2
        done
    fi
}

##########################
## Build EDL For mpv #####
##########################

edl_escape() {
    local str="$1"
    local len
    len=$(printf '%s' "$str" | wc -c)
    printf '%%%d%%%s' "$len" "$str"
}

build_edl() {
    local v_url="$1"
    local a_url="$2"
    local title="$3"
    local artist="$4"

    local edl="edl://"

    if [ -n "$v_url" ]; then
        local esc_v
        esc_v=$(edl_escape "$v_url")
        edl="${edl}!new_stream;!no_clip;!no_chapters;${esc_v}"
    fi

    if [ -n "$a_url" ] && [ "$a_url" != "$v_url" ]; then
        local esc_a
        esc_a=$(edl_escape "$a_url")
        edl="${edl};!new_stream;!no_clip;!no_chapters;${esc_a}"
    fi

    local tags=""
    if [ -n "$title" ]; then
        local esc_title
        esc_title=$(edl_escape "$title")
        tags="${tags},title=${esc_title}"
    fi
    if [ -n "$artist" ]; then
        local esc_artist
        esc_artist=$(edl_escape "$artist")
        tags="${tags},artist=${esc_artist}"
    fi

    if [ -n "$tags" ]; then
        edl="${edl};!global_tags${tags}"
    fi

    printf '%s' "$edl"
}

play_video_mpv() {
    local v_url="$1" a_url="$2" vid_id="$3" title="$4" artist="$5"
    echo "[>] Sending MPV command for: $title"

    [ -z "$v_url" ] && return 1

    local edl
    edl=$(build_edl "$v_url" "$a_url" "$title" "$artist")

    local art_file
    art_file=$(get_art_file "$vid_id" "hq")
    if [ -n "$art_file" ]; then
        local art_cmd
        art_cmd=$(jq -nc --arg art "$art_file" \
            '{"command": ["set_property", "cover-art-files", [$art]]}')
        send_mpv_command "$art_cmd"
    fi

    local load_cmd
    load_cmd=$(jq -nc \
        --arg url "$edl" \
        --arg title "$title" \
        '{"command": ["loadfile", $url, "replace", 0, {"force-media-title": $title, "vid": "1"}]}')
    send_mpv_command "$load_cmd"
    # Sometimes playback starts paused
    (
        sleep 0.5
        send_mpv_command '{"command": ["set_property", "pause", false]}'
    ) &
}

###############################
## Build xspf file for vlc ####
###############################

# Helper function for escaping
escape_xml_to_var() {
    local val="${!1}"
    val="${val//&/&amp;}"
    val="${val//</&lt;}"
    val="${val//>/&gt;}"
    printf -v "$1" "%s" "$val"
}

generate_xspf_vlc() {
    local vid_id="$1" title="$2" artist="$3" v_url="$4"
    local out_file="$prefetch_dir/${vid_id}.xspf"

    # Prepare variables and escape them using the helper
    local esc_title="$title"
    local esc_artist="$artist"
    local esc_url="$v_url"

    escape_xml_to_var esc_title
    escape_xml_to_var esc_artist
    escape_xml_to_var esc_url

    local art_file
    art_file=$(get_art_file "$vid_id" "hq")
    local image_tag=""
    [ -n "$art_file" ] && image_tag="<image>file://${art_file}</image>"

    cat <<EOF >"$out_file"
<?xml version="1.0" encoding="UTF-8"?>
<playlist version="1" xmlns="http://xspf.org/ns/0/">
  <trackList>
    <track>
      <location>${esc_url}</location>
      <title>${esc_title}</title>
      <creator>${esc_artist}</creator>
      ${image_tag}
    </track>
  </trackList>
</playlist>
EOF
}

play_video_vlc() {
    local v_url="$1" a_url="$2" vid_id="$3" title="$4" artist="$5"
    echo "[>] Sending VLC command for: $title"

    # Generate the XSPF file with video URL and metadata
    generate_xspf_vlc "$vid_id" "$title" "$artist" "$v_url"
    local xspf_file="$prefetch_dir/${vid_id}.xspf"

    send_vlc_command "clear"
    sleep 0.1

    local vlc_cmd="add ${xspf_file}"
    if [ -n "$a_url" ] && [ "$a_url" != "$v_url" ]; then
        vlc_cmd="$vlc_cmd :input-slave=$a_url"
    fi
    send_vlc_command "$vlc_cmd"
}

####################################################
# Main YOUTUBE SCRAPING & Thumbnails downloader ####
####################################################

fetch_youtube_data() {
    local query="$1"
    local encoded_query
    # Converts special characters (like spaces/&) into %XX format using jq @uri
    encoded_query=$(jq -rn --arg q "$query" '$q | @uri')
    local url="https://www.youtube.com/results?search_query=${encoded_query}"

    local ua="Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0"
    # Main web scraper: using curl to scrape youtube data and cookies to get personalized results
    local curl_opts=(-sL --compressed -A "$ua" -H "x-youtube-client-name: 1" -H "x-youtube-client-version: 2.20240315.01.00" -H "Accept-Language: en-US,en;q=0.5")
    [ -s "$cookie_file" ] && curl_opts+=(-b "$cookie_file")

    local raw_data
    # Extract the JSON part from raw data
    raw_data=$(curl --connect-timeout 10 "${curl_opts[@]}" "$url" |
        grep -m 1 "ytInitialData =" |
        sed -E 's/.*ytInitialData[[:space:]]*=[[:space:]]*//; s/;[[:space:]]*<\/script>.*//; s/;$//')

    if [ -z "$raw_data" ]; then
        echo "[]"
        return
    fi

    echo "$raw_data" | jq -c '
    [
      .. | .videoRenderer? | select(. != null)
      # Remove Shorts via URL
      | select(.navigationEndpoint.commandMetadata.webCommandMetadata.url | contains("/shorts/") | not)
      # Remove videos under 1 minute (0:xx)
      | select(.lengthText.simpleText != null and (.lengthText.simpleText | startswith("0:") | not))
    ]
    | map({
        id: .videoId,
        title: (.title.runs[0].text // "No Title"),
        artist: (.ownerText.runs[0].text // "Unknown"),
        duration: (.lengthText.simpleText // "N/A")
    })
    ' 2>/dev/null

}

get_streaming_links() {
    local vid_id="$1" mode="$2"
    echo "[*] Resolving links for: $vid_id ($mode)" >&2
    local url="https://www.youtube.com/watch?v=$vid_id"

    local cmd=("yt-dlp" "-g" "--cookies" "$cookie_file")
    if [ "$mode" == "YT-Music" ]; then
        cmd+=("-f" "bestaudio/best")
    else
        local codec_arg=""
        [ "$codec" == "h264" ] && codec_arg="[vcodec^=avc1]"
        [ "$codec" == "av1" ] && codec_arg="[vcodec^=av01]"
        [ "$codec" == "vp9" ] && codec_arg="[vcodec^=vp9]"

        if [ "$resolution" == "best" ]; then
            cmd+=("-f" "bestvideo${codec_arg}+bestaudio/best")
        else
            cmd+=("-f" "bestvideo[height<=${resolution}]${codec_arg}+bestaudio/best[height<=${resolution}]${codec_arg}/best")
        fi
    fi
    cmd+=("$url")

    local links
    links=$("${cmd[@]}" 2>/dev/null)
    if [ -n "$links" ]; then
        echo "[+] Links acquired for ID: $vid_id" >&2
        echo "$links"
    fi
}

get_playlist_data() {
    local base_id="$1" limit="$2"
    echo -e "\n[*] Fetching Playlist Data for ID: $base_id\n" >&2

    local mix_url="https://www.youtube.com/watch?v=${base_id}&list=RD${base_id}"

    yt-dlp --flat-playlist --print-json --playlist-end "$limit" --cookies "$cookie_file" "$mix_url" 2>/dev/null |
        jq -s --arg base_id "$base_id" '
        # Map to required structure
        map({
            id: .id,
            title: (.title // "Unknown"),
            artist: (.uploader // .channel // "Unknown")
        })
        | . as $items

        # Extract first occurrence of base_id (null if not found)
        | ($items | map(select(.id == $base_id)) | first) as $base_item

        # Build deduped list of everything except base_id
        | ($items | reduce .[] as $item ([];
            if ($item.id == $base_id or any(.[]; .id == $item.id))
            then .
            else . + [$item]
            end
          )) as $others

        # Construct final list
        | if $base_item then
            [$base_item] + $others
          else
            [{
                id: $base_id,
                title: "Unknown",
                artist: "Unknown"
            }] + $others
          end
    '
}

download_thumbnail() {
    local id="$1"
    local mode="${2:-default}"
    local prefix="${3:-}"

    # default thumbnail (gets downloaded in both mode)
    if [ "$mode" = "default" ] || [ "$mode" = "hq" ]; then
        local t_path="$thumb_dir/${id}.jpg"
        if [ -f "$t_path" ]; then
            echo "${prefix}[~] Cached:      $id"
            # Update the modification time so cache management doesn't delete recently used thumbnails
            touch -m "$t_path"
        else
            echo "${prefix}[↓] Downloading: $id"
            curl -sL --connect-timeout 5 -o "$t_path" "https://i.ytimg.com/vi/${id}/hqdefault.jpg"
        fi
    fi

    # sliently download the hq thumbnails for albumart
    if [ "$mode" = "hq" ]; then
        local hq_dir="$thumb_dir/hq_thumbnails"
        mkdir -p "$hq_dir"
        local hq_path="$hq_dir/${id}.jpg"
        [ -f "$hq_path" ] && return 0

        local qualities=("maxresdefault" "sddefault")
        for q in "${qualities[@]}"; do
            local url="https://i.ytimg.com/vi/${id}/${q}.jpg"
            curl -sL --connect-timeout 5 -o "$hq_path" "$url"
            # Validate file size >2KB to avoid placeholder images
            if [ -f "$hq_path" ] && [ "$(stat -c%s "$hq_path" 2>/dev/null || echo 0)" -gt 2000 ]; then
                return 0
            else
                rm -f -- "$hq_path" # delete the placeholder file
            fi
        done
    fi
}

###################################################
# Main ROFI-TUBE logic and playback functions #####
###################################################

prefetch_link_bg() {
    local vid_id="$1" title="$2" artist="$3" mode="$4"
    local target_f="$prefetch_dir/$vid_id"

    if [ ! -s "$target_f" ]; then
        echo "[*] Prefetching: $title"
        get_streaming_links "$vid_id" "$mode" >"$target_f.tmp"
        mv "$target_f.tmp" "$target_f" 2>/dev/null

        # When VLC is active, also generate the XSPF file
        if [[ "$player_bin" = *"vlc"* ]]; then
            mapfile -t fetched_links <"$target_f"
            if [ ${#fetched_links[@]} -gt 0 ]; then
                generate_xspf_vlc "$vid_id" "$title" "$artist" "${fetched_links[0]}"
            fi
        fi
    fi
}

check_playlist_commands() {
    local cmd_file="$config_dir/jump_to.txt"
    [ ! -f "$cmd_file" ] && return 0

    local j_id
    j_id=$(<"$cmd_file")
    # Delete the file
    rm -f "$cmd_file" 2>/dev/null

    if [ -n "$j_id" ]; then
        echo "$j_id"
        return 1
    fi
    return 0
}

manage_playlist_loop() {
    local mode_choice="$1"

    take_control_of_session
    ensure_player_running

    # Clone the pristine data file to serve as our memory backend.
    cp "$playlist_file" "$loop_state_file"

    local is_mpv=0
    [[ "$player_bin" == *"mpv"* ]] && is_mpv=1

    # Extracting playlist details into memory
    mapfile -t playlist_ids < <(jq -r '.items[].id' "$loop_state_file")
    mapfile -t playlist_titles < <(jq -r '.items[].title' "$loop_state_file")
    mapfile -t playlist_artists < <(jq -r '.items[].artist' "$loop_state_file")

    local total=${#playlist_ids[@]}
    local current_index=0
    local thumbnails_downloaded=0

    local player_pid=""
    if [ "$is_mpv" -eq 1 ]; then
        player_pid=$(pgrep -f "input-ipc-server=$mpv_socket_path" | head -n 1)
    else
        player_pid=$(pgrep -f "rc-host $vlc_rc_host:$vlc_rc_port" | head -n 1)
    fi

    # Creating our Communication Tube (FIFO):
    # mkfifo creates a "First In, First Out" file.
    # Anything written to this file is held until another program reads it.
    local monitor_fifo="/tmp/rofi_tube_monitor_$$"
    rm -f "$monitor_fifo"
    mkfifo "$monitor_fifo"

    # 'exec 3<>"$monitor_fifo"' opens the pipe for BOTH reading (<) and writing (>).
    # And assigns this pipe connection to Unit 3.
    exec 3<>"$monitor_fifo"

    # Setting up the Continuous Player Monitor
    local pctl_pid=""
    if command -v playerctl >/dev/null 2>&1; then
        # If playerctl is installed, use it to track player status changes in real-time.
        # '>&3' redirects playerctl's continuous status output directly into Unit 3 (to FIFO file).
        playerctl -p "$player_name" status --follow >&3 2>/dev/null &
        pctl_pid=$! # Save the background process ID so we can stop it later
    else
        # Fallback Monitor: If playerctl is missing, query the player manually in a loop.
        (
            last_state=""
            while true; do
                st=""
                if [ "$is_mpv" -eq 1 ]; then
                    # Manually ping MPV's socket to check status.
                    res=$(echo '{"command": ["get_property", "idle-active"]}' | socat -t 1 - "UNIX-CONNECT:$mpv_socket_path" 2>/dev/null)
                    if [[ -z "$res" ]] || [[ "$res" == *'"data":true'* ]]; then
                        st="Stopped"
                    else
                        st="Playing"
                    fi
                else
                    # Manually ping VLC's network port to check status.
                    st=$(echo "status" | nc -q 1 "$vlc_rc_host" "$vlc_rc_port" 2>/dev/null)
                    if [[ "$st" == *"( state stop )"* ]] || [[ "$st" == *"( state idle )"* ]]; then
                        st="Stopped"
                    elif [[ "$st" == *"( state playing )"* ]]; then
                        st="Playing"
                    fi
                fi
                if [ -n "$st" ] && [ "$st" != "$last_state" ]; then
                    # '>&3' writes to fifo file.
                    echo "$st" >&3
                    last_state="$st"
                fi
                sleep 1
            done
        ) &
        pctl_pid=$!
    fi

    # A helper function to check if the media player is still running.
    is_player_alive() {
        [ -n "$player_pid" ] && kill -0 "$player_pid" 2>/dev/null
    }

    cleanup_monitor() {
        local reason="$1"
        trap - TERM INT EXIT

        # Clean up our background monitoring and prefetching
        [ -n "$pctl_pid" ] && kill "$pctl_pid" 2>/dev/null
        [ -n "$current_prefetch_pid" ] && kill "$current_prefetch_pid" 2>/dev/null

        exec 3>&- 2>/dev/null # This closes the file descriptors for both directions
        rm -f "$monitor_fifo" 2>/dev/null

        if [ "$reason" != "handover" ]; then
            rm -f "$playlist_file" "$loop_state_file" "$pid_file" "$mpv_socket_path"
            kill "$current_prefetch_pid"
            find "$thumb_dir/hq_thumbnails" -maxdepth 1 -type f -name "*.jpg" -delete 2>/dev/null
        fi
    }

    # If loop is killed by 'take_control_of_session' preserve hq thumbnails to avoid re-downloading.
    trap 'cleanup_monitor "handover"; exit 0' TERM
    # exit script on interrupt and clean normally
    trap 'cleanup_monitor "exit"; exit 0' INT EXIT

    # Clear old streaming link files
    rm -f "$prefetch_dir"/* 2>/dev/null
    # Prefetch links for 1st track
    prefetch_link_bg "${playlist_ids[0]}" "${playlist_titles[0]}" "${playlist_artists[0]}" "$mode_choice" &
    current_prefetch_pid=$!

    ######################
    # MAIN PLAYLIST LOOP #
    ######################
    while [ "$current_index" -lt "$total" ]; do
        echo "[*] Waiting for link processing [$((current_index + 1))/$total]"

        local vid_id="${playlist_ids[$current_index]}"
        local raw_title="${playlist_titles[$current_index]}"
        local raw_artist="${playlist_artists[$current_index]}"

        local target_f="$prefetch_dir/$vid_id"
        local jumped=0

        # Wait Loop: Wait for the 'prefetch_link_bg' to finish writing the link file.
        # checks if the prefetch process is still active or if the output file is still empty or doesn't exist.
        while kill -0 "$current_prefetch_pid" 2>/dev/null || [ ! -s "$target_f" ]; do
            # Failsafe: If the prefetch process died, but the output file is still missing/empty.
            if ! kill -0 "$current_prefetch_pid" 2>/dev/null && [ ! -s "$target_f" ]; then
                break
            fi

            # Check if the user clicked a track from playlist window.
            local j_id
            j_id=$(check_playlist_commands)
            if [ $? -eq 1 ]; then
                local new_idx=-1
                # Find the index of the track the user jumped to
                for i in "${!playlist_ids[@]}"; do
                    if [[ "${playlist_ids[$i]}" == "$j_id" ]]; then
                        new_idx=$i
                        break
                    fi
                done
                # If found, update current track info, and start prefetching the new track
                if [ "$new_idx" -ne -1 ]; then
                    echo "[*] Jump requested to playlist item $((new_idx + 1))"
                    current_index="$new_idx"
                    vid_id="${playlist_ids[$current_index]}"
                    raw_title="${playlist_titles[$current_index]}"
                    raw_artist="${playlist_artists[$current_index]}"
                    prefetch_link_bg "$vid_id" "$raw_title" "$raw_artist" "$mode_choice" &
                    current_prefetch_pid=$!
                    jumped=1
                    break
                fi
            fi

            # If the actual MPV/VLC window is closed by the user, stop the entire playlist.
            if ! is_player_alive; then
                echo "[!] Player closed. Playlist Aborted." >&2
                cleanup_monitor
                return
            fi
            sleep 0.5
        done

        # If the user jumped to another song, skip the rest of this loop cycle and start over.
        [ "$jumped" -eq 1 ] && continue

        # If we failed to get a streaming link, skip this song and move to the next.
        if [ ! -s "$target_f" ]; then
            echo "[!] FAILED to get links for: $raw_title" >&2
            ((current_index++))
            continue
        fi

        # Read the resolved audio and video streaming links from the prefetch file.
        mapfile -t links <"$target_f"
        local display_title="[$((current_index + 1))/$total] $raw_title"

        if [ ${#links[@]} -eq 0 ]; then
            echo "[!] FAILED to get links for: $raw_title" >&2
            ((current_index++))
            continue
        fi

        # We inject a Play Icon ("") into the current item's title.
        jq --argjson idx "$current_index" '.items[$idx].title |= "<b>  </b>" + .' "$loop_state_file" >"$playlist_file"

        # Display a desktop notification with the album art.
        # sleep 0.5 so that we don't get false notification when player is closed.
        (
            sleep 0.5
            is_player_alive && {
                # Close the generating link notification if any
                notify close
                # Show playing notification
                notify "YouTube Playing" "$(truncate_text "$raw_title")\n<span alpha='85%'>$raw_artist</span>" "$(get_art_file "$vid_id")"
                echo -e "\n[>>>] PLAYING: $raw_title [>>>]\n"
            }
        )

        # Send the links to the media player to begin playback.
        if [ "$is_mpv" -eq 1 ]; then
            play_video_mpv "${links[0]}" "${links[1]}" "$vid_id" "$display_title" "$raw_artist"
        else
            play_video_vlc "${links[0]}" "${links[1]}" "$vid_id" "$display_title" "$raw_artist"
        fi

        # Thumbnail downloader
        if [ "$thumbnails_downloaded" -eq 0 ]; then
            echo -e "\n[*] Found $total playlist items..."
            echo "[*] Downloading playlist thumbnails..."
            local max_jobs=15
            local thumb_pids=()

            for i in "${!playlist_ids[@]}"; do
                download_thumbnail "${playlist_ids[$i]}" "hq" &
                thumb_pids+=($!) # Track the process ID of this download job
                if [ "${#thumb_pids[@]}" -ge "$max_jobs" ]; then
                    wait "${thumb_pids[0]}" 2>/dev/null
                    thumb_pids=("${thumb_pids[@]:1}") # Remove the finished job from our tracking list
                fi
            done

            # Wait for all remaining active download processes to finish before continuing
            for pid in "${thumb_pids[@]}"; do
                wait "$pid" 2>/dev/null
            done

            echo -e "[*] Thumbnails downloaded...\n"
            thumbnails_downloaded=1
        fi

        # Begin resolving the streaming links for the NEXT track.
        local next_idx=$((current_index + 1))
        if [ "$next_idx" -lt "$total" ]; then
            local next_vid="${playlist_ids[$next_idx]}"
            local next_title="${playlist_titles[$next_idx]}"
            local next_artist="${playlist_artists[$next_idx]}"
            prefetch_link_bg "$next_vid" "$next_title" "$next_artist" "$mode_choice" &
            current_prefetch_pid=$!
        fi

        echo "[*] Monitor: Waiting for playback to START"
        local started_playing=0

        for _ in {1..20}; do
            # Check for manual user song-skips during this transition period.
            local j_id
            j_id=$(check_playlist_commands)
            if [ $? -eq 1 ]; then
                local new_idx=-1
                for i in "${!playlist_ids[@]}"; do
                    if [[ "${playlist_ids[$i]}" == "$j_id" ]]; then
                        new_idx=$i
                        break
                    fi
                done
                if [ "$new_idx" -ne -1 ]; then
                    echo "[*] Jump requested to playlist item $((new_idx + 1))"
                    current_index="$new_idx"
                    vid_id="${playlist_ids[$current_index]}"
                    raw_title="${playlist_titles[$current_index]}"
                    raw_artist="${playlist_artists[$current_index]}"
                    prefetch_link_bg "$vid_id" "$raw_title" "$raw_artist" "$mode_choice" &
                    current_prefetch_pid=$!
                    jumped=1
                    break
                fi
            fi

            if ! is_player_alive; then
                echo "[!] Player closed. Playlist Aborted." >&2
                cleanup_monitor
                return
            fi

            # Read playback status from fifo.
            if read -t 0.5 -u 3 status_line; then
                while :; do
                    status_line=${status_line,,}
                    if [[ "$status_line" == *"playing"* ]]; then
                        started_playing=1
                        break
                    fi
                    # Quick drain of any other status messages in the pipe
                    read -t 0.1 -u 3 status_line || break
                done
            fi
            if [ "$started_playing" -eq 1 ]; then break; fi
        done

        [ "$jumped" -eq 1 ] && continue
        [ "$started_playing" -eq 0 ] && echo "[!] Warning: Player didn't report 'Playing' state. Monitoring anyway." >&2

        # Drain any stale, old status lines leftover in the pipe. So that Watching loop doesn't freezes.
        while read -t 0.1 -u 3 throwaway; do :; done

        echo "[*] Monitor: Watching $raw_title"
        local track_finished=0
        local fs_counter=0

        ###############################################
        # TRACK TRACKING LOOP (Runs while song plays) #
        ###############################################
        while [ "$track_finished" -eq 0 ]; do
            # Check if the user clicked a different track in the launcher mid-song.
            local j_id
            j_id=$(check_playlist_commands)
            if [ $? -eq 1 ]; then
                local new_idx=-1
                for i in "${!playlist_ids[@]}"; do
                    if [[ "${playlist_ids[$i]}" == "$j_id" ]]; then
                        new_idx=$i
                        break
                    fi
                done
                if [ "$new_idx" -ne -1 ]; then
                    echo "[*] Jump requested to playlist item $((new_idx + 1))"
                    current_index="$new_idx"
                    vid_id="${playlist_ids[$current_index]}"
                    raw_title="${playlist_titles[$current_index]}"
                    raw_artist="${playlist_artists[$current_index]}"
                    prefetch_link_bg "$vid_id" "$raw_title" "$raw_artist" "$mode_choice" &
                    current_prefetch_pid=$!
                    jumped=1
                    break
                fi
            fi

            if ! is_player_alive; then
                echo "[!] Player closed. Playlist Aborted." >&2
                cleanup_monitor
                return
            fi

            if read -t 0.5 -u 3 status_line; then
                fs_counter=0 # Reset the failsafe counter because the pipe is working correctly.
                while :; do
                    status_line=${status_line,,}
                    if [[ "$status_line" == *"stopped"* || "$status_line" == *"stop"* || "$status_line" == *"idle"* ]]; then
                        echo "[-] Track Finished: $raw_title"
                        track_finished=1
                        break
                    fi
                    read -t 0.1 -u 3 status_line || break
                done
            else
                # THE FAILSAFE: If the read timed out (no data received on the pipe)
                ((fs_counter++))                 # Add 1 to the failsafe counter
                if [ "$fs_counter" -ge 4 ]; then # If we have 2 seconds of silence (4 timeouts * 0.5s)
                    fs_counter=0
                    if [ "$is_mpv" -eq 1 ]; then
                        # Manually ping MPV's socket to check if it has stopped/gone idle
                        local fs_st
                        fs_st=$(echo '{"command": ["get_property", "idle-active"]}' | socat -t 1 - "UNIX-CONNECT:$mpv_socket_path" 2>/dev/null)
                        if [[ "$fs_st" == *'"data":true'* ]]; then
                            echo "[-] Track Finished (failsafe): $raw_title"
                            track_finished=1
                            break
                        fi
                    else
                        # Manually ping VLC's network port to check if it has stopped/gone idle
                        local fs_st
                        fs_st=$(echo "status" | nc -q 1 "$vlc_rc_host" "$vlc_rc_port" 2>/dev/null)
                        if [[ "$fs_st" == *"( state stop )"* ]] || [[ "$fs_st" == *"( state idle )"* ]]; then
                            echo "[-] Track Finished (failsafe): $raw_title"
                            track_finished=1
                            break
                        fi
                    fi
                fi
            fi
        done

        # If a manual track jump happened, skip incrementing the track index.
        [ "$jumped" -eq 1 ] && continue

        # If the track finished playing normally, increment our index to go to the next song.
        [ "$track_finished" -eq 1 ] && ((current_index++))
    done

    echo "[*] Playlist Finished."
    cleanup_monitor
}

show_playlist_window() {
    local pid=$(<"$pid_file")
    if ! [[ $(ps -p "$pid" -o cmd=) == *rofi-tube.sh* ]]; then
        [ -f "$playlist_file" ] && echo '{"mode":"", "items":[]}' >"$playlist_file"
    fi

    if [ ! -f "$playlist_file" ]; then
        echo "[-] No active playlist found."
        notify "Playlist" "No active playlist found."
        run_rofi "" "$rofi_playlist_theme" "Playlist "
        return
    fi

    local items_len
    items_len=$(jq '.items | length' "$playlist_file" 2>/dev/null)
    if [ -z "$items_len" ] || [ "$items_len" -eq 0 ]; then
        echo "[-] Playlist is empty."
        run_rofi "" "$rofi_playlist_theme" "Playlist "
        return
    fi

    local rofi_list
    # Build rofi entries in the format: video_title - artist | video_id
    rofi_list=$(jq -j --arg thumb_dir "$thumb_dir" '
      .items | map(
        (.title 
          | gsub("&"; "&amp;") 
          | gsub("<"; "&lt;") 
          | gsub(">"; "&gt;") 
          | sub("&lt;b&gt;  &lt;/b&gt;"; "<b>  </b>")
        ) as $safe_title 
        | (.artist
          | gsub("&"; "&amp;")
          | gsub("<"; "&lt;")
          | gsub(">"; "&gt;")
        ) as $safe_artist
        | "\($safe_title) - \($safe_artist) | \(.id)\\x00icon\\x1f\($thumb_dir)/\(.id).jpg"
      ) | join("\\x1e")
    ' "$playlist_file")

    local selected
    # Pass "" to pre-select the playing item
    selected=$(run_rofi "$rofi_list" "$rofi_playlist_theme" "Playlist " "" "")
    [ -z "$selected" ] && {
        echo "[-] Playlist selection cancelled."
        return
    }

    # Extract video_id from selection
    local video_id="${selected##* | }"

    # Get the "Title - Artist" part
    local full_info="${selected% | *}"
    local artist="${full_info##* - }"
    local title="${full_info% - *}"

    echo "[+] Selected from Playlist: $title ($video_id)"
    notify "Playlist Generating link" "$(truncate_text "$title")\n<span alpha='85%'>$artist</span>" "$(get_art_file "$video_id")" "animate"

    echo "$video_id" >"$config_dir/jump_to.txt"
    echo "[+] Jump command sent for: $video_id"
}

navigate_playlist() {
    local direction="$1" # "next" or "previous"
    [ ! -f "$playlist_file" ] && return

    # Get the current index and total count
    local current_idx=$(jq -r '.items | map(.title | contains("<b>  </b>")) | index(true)' "$playlist_file")
    local total=$(jq '.items | length' "$playlist_file")

    [[ "$current_idx" == "null" ]] && current_idx=-1

    local new_idx
    if [[ "$direction" == "next" ]]; then
        # If we are at the last item, do nothing
        if [[ $current_idx -ge $((total - 1)) ]]; then
            echo "[!] Already at the end of the playlist" >&2
            return
        fi
        new_idx=$((current_idx + 1))
    elif [[ "$direction" == "previous" ]]; then
        # If we are at the first item (0) or nothing is playing (-1), do nothing
        if [[ $current_idx -le 0 ]]; then
            echo "[!] Already at the beginning of the playlist" >&2
            return
        fi
        new_idx=$((current_idx - 1))
    fi

    # Extract data for the new track
    local target_id artist title
    IFS=$'\t' read -r target_id artist title < <(
        jq -r ".items[$new_idx] | [.id, .artist, .title] | @tsv" "$playlist_file"
    )

    echo "$target_id" >"$config_dir/jump_to.txt"
    notify "Playlist Generating link" "$(truncate_text "$title")\n<span alpha='85%'>$artist</span>" "$(get_art_file "$target_id")" "animate"
    echo "[+] Playing $direction: $title"
}

main() {
    case "$1" in
    --show-playlist)
        show_playlist_window
        return
        ;;
    --next)
        navigate_playlist "next"
        return
        ;;
    --previous)
        navigate_playlist "previous"
        return
        ;;
    esac

    manage_cache
    ensure_cookie_file_exists

    echo "[+] Opening Mode Selection..."
    local mode_options="YouTube\\x00icon\\x1f$yt_icon\\x1eYT-Music\\x00icon\\x1f$music_icon\\x1eSettings\\x00icon\\x1f$settings_icon"
    local mode_choice=$(run_rofi "$mode_options" "$rofi_menu_theme" "Mode" "<big>Select Mode</big>")

    [ -z "$mode_choice" ] && {
        echo "[-] Selection cancelled."
        return
    }
    # Show settings window
    [ "$mode_choice" == "Settings" ] && {
        echo "[+] Opening Settings Window"
        settings_window
        return
    }

    echo "[+] Selected Mode: $mode_choice"

    local mode_icon="$yt_icon"
    [[ "$mode_choice" == "YT-Music" ]] && mode_icon="$music_icon"

    local history_data
    history_data="Delete History\x00icon\x1f$delete_icon\x1e$(get_history)"

    local query
    query=$(run_rofi "$history_data" "$rofi_search_theme" "Search ($mode_choice) ::")
    [ -z "$query" ] && {
        echo "[-] Search cancelled."
        return
    }
    if [[ "$query" == "Delete History" ]]; then
        delete_history_ui
        query=$(run_rofi "$history_data" "$rofi_search_theme" "Search ($mode_choice) ::")
        [ -z "$query" ] && {
            echo "[-] Search cancelled."
            return
        }
    fi

    notify "$mode_choice Searching" "$query" "$mode_icon" "animate"
    echo "[?] Searching YouTube for: $query"

    local results_json=$(fetch_youtube_data "$query")
    local num_results=$(echo "$results_json" | jq '. | length')
    echo "[+] Found $num_results results."

    echo -e "\n[*] Downloading thumbnails..."
    local max_jobs=15
    local thumb_pids=()
    local ids_list
    ids_list=$(echo "$results_json" | jq -r '.[].id')

    while IFS= read -r r_id; do
        [ -z "$r_id" ] && continue
        download_thumbnail "$r_id" &
        thumb_pids+=($!)

        if [ "${#thumb_pids[@]}" -ge "$max_jobs" ]; then
            wait "${thumb_pids[0]}" 2>/dev/null
            thumb_pids=("${thumb_pids[@]:1}")
        fi
    done <<<"$ids_list"

    for pid in "${thumb_pids[@]}"; do
        wait "$pid" 2>/dev/null
    done
    echo "[*] Thumbnails downloaded..."

    local rofi_list
    # Build rofi entries: Line 1 = Artist [TAB] Duration, Line 2 = Title | ID
    rofi_list=$(echo "$results_json" | jq -j '
        map(
            (.artist | gsub("&";"&amp;") | gsub("<";"&lt;") | gsub(">";"&gt;")) as $artist |
            (.title  | gsub("&";"&amp;") | gsub("<";"&lt;") | gsub(">";"&gt;")) as $title |
            "\($artist)\t[\(.duration)]\n\($title) | \(.id)\\x00icon\\x1f'"$thumb_dir"'/\(.id).jpg"
        ) | join("\\x1e")
    ')

    # Stop notification animation
    notify close

    local selected
    selected=$(run_rofi "$rofi_list" "$rofi_tube_theme" "Select" "Results For: $query")
    [ -z "$selected" ] && {
        echo "[-] Result selection cancelled."
        return
    }

    # Split the multi-line selection into two local variables
    local line1 line2
    line1=$(echo "$selected" | head -n 1)
    line2=$(echo "$selected" | tail -n 1)
    # Extract Artist
    local video_artist="${line1%%$'\t'*}"
    # Extract ID
    local video_id="${line2##* | }"
    # Extract Title
    local video_title="${line2% | *}"

    # Download hq thumbnail for selected id so that player can use
    download_thumbnail "$video_id" "hq" >/dev/null 2>&1 &

    echo -e "\n[+] Selected: $video_title (video_id: $video_id)"
    update_history_file "$query" "$video_id"

    if [ "$playlist" == "true" ]; then
        notify "Playlist Generating Mix" "$(truncate_text "$video_title")\n<span alpha='85%'>$video_artist</span>" "$(get_art_file "$video_id")" "animate"
        local items_json=$(get_playlist_data "$video_id" "$playlist_limit")

        jq --arg mode "$mode_choice" '. as $items | {"mode": $mode, "items": $items}' <<<"$items_json" >"$playlist_file"
        # Stop notification animation
        notify close
        # Run playlist loop
        manage_playlist_loop "$mode_choice"
    else
        take_control_of_session
        ensure_player_running
        notify "YouTube Playing" "$(truncate_text "$video_title")\n<span alpha='85%'>$video_artist</span>" "$(get_art_file "$video_id")"

        local links
        mapfile -t links < <(get_streaming_links "$video_id" "$mode_choice")

        if [ ${#links[@]} -gt 0 ]; then
            if [[ "$player_bin" == *"mpv"* ]]; then
                play_video_mpv "${links[0]}" "${links[1]}" "$video_id" "$video_title" "$video_artist"
            else
                play_video_vlc "${links[0]}" "${links[1]}" "$video_id" "$video_title" "$video_artist"
            fi
        else
            echo "[!] FAILED to get links for: $video_title" >&2
        fi
    fi
}

main "$@"
