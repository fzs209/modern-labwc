#!/bin/bash

#####################################
## author @Harsh-bin Github #########
#####################################

# --- Configuration ---
config_dir="$HOME/.config/rofi/nowplaying"
# This is "webp" so that we can apply any background color to it and convert to jpg
fallback_art_file="$config_dir/fallback_album_art.webp"
rofi_theme="$config_dir/styles/style-4"

cache_dir="/tmp/nowplaying"
mkdir -p "$cache_dir"
art_file="$cache_dir/album_art.jpg"
blur_art_file="$cache_dir/blurred_art.jpg"
raw_art_file="$cache_dir/raw_album_art.jpg"
# Cache files
title_cache_file="$cache_dir/song_title.cache"
player_cache_file="$cache_dir/player.cache"

# Tracks whether a real artwork is being used.
# Stores only "true" or "false" so we know the artwork isn't a fallback
# and can generate ambient colors.
is_art="$cache_dir/art.cache"

# Notification id
notify_id="string:x-canonical-private-synchronous:nowplaying"

# --- Functions ---

# Function to escape special characters
escape_characters() {
    local val="$1"
    val="${val//&/&amp;}"
    val="${val//</&lt;}"
    val="${val//>/&gt;}"
    echo "$val"
}

url_decode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

truncate_text() {
    local str="$1"
    local char_limit="$2"

    if ((${#str} > $char_limit)); then
        short_str="${str:0:$char_limit}..."
    else
        short_str="$str"
    fi
    echo "$(escape_characters "$short_str")"
}

####################################################
# MAIN FUNCTION TO FETCH METADATA AND ALBUM ART  ###
####################################################
#pactl list sink-inputs
fetch_data() {
    # Track the current system theme to:
    # Create the appropriate overlay
    # Apply the correct background color to fallback artwork
    system_theme=$(<"$HOME/.config/labwc/system.theme")

    active_player=""
    cached_player_name=""
    active_player_priority=0

    if [ -f "$player_cache_file" ]; then
        cached_player_name=$(<"$player_cache_file")
    fi

    ##################################
    # Get all player data at once ####
    ##################################
    players_data=$(playerctl -a metadata --format $'{{ playerInstance }}\t{{ status }}\t{{ title }}\t{{ artist }}' 2>/dev/null)

    while IFS=$'\t' read -r player status title artist; do
        if [ -z "$player" ]; then continue; fi

        # Priority Levels:
        # 3 = Playing
        # 2 = Paused
        # 1 = Stopped (but has media/title)
        # 0 = Ghost / No media like chromium based browsers

        current_priority=0

        if [ "$status" == "Playing" ]; then
            current_priority=3
        elif [ "$status" == "Paused" ]; then
            current_priority=2
        elif [ -n "$title" ]; then
            current_priority=1
        else
            current_priority=0
        fi

        if [ "$current_priority" -gt "$active_player_priority" ]; then
            active_player="$player"
            active_player_priority="$current_priority"
            active_player_status="$status"
            active_player_title="$title"
            active_player_artist="$artist"
        fi

        # If this is the cached player, save its current priority and metadata for later
        if [ "$player" == "$cached_player_name" ]; then
            cached_player_priority="$current_priority"
            cached_player_status="$status"
            cached_player_title="$title"
            cached_player_artist="$artist"
        fi

    done <<<"$players_data"

    # If no player is currently 'Playing', and the cached player
    # is alive and has media (Priority >= 1), override the decision.
    if [[ "$active_player_priority" -lt 3 && "$cached_player_priority" -ge 1 ]]; then
        active_player="$cached_player_name"
        active_player_status="$cached_player_status"
        active_player_title="$cached_player_title"
        active_player_artist="$cached_player_artist"
    fi

    ######################################
    # Process metadata and albumart ######
    ######################################

    pre=""
    next=""
    toggle=""
    player_status="Paused"

    if [[ "$active_player_status" = "Playing" ]]; then
        toggle=""
        player_status="Playing"
    fi

    # Metadata used by rofi when nothing is playing
    player_display_name=""
    song_title="Nothing Playing"
    [[ -z "$active_player_artist" ]] && song_artist="Unknown"

    # Clean up art and cache files if no active player
    # Used here so rofi can still show the complete window, while preventing copying of fallback art
    if [[ -z "$active_player" ]]; then
        rm -f "$art_file" "$raw_art_file" "$blur_art_file" "$title_cache_file" "$player_cache_file" "$is_art" 2>/dev/null
        player_status=""
        return # No need for further processing
    fi

    if [[ -n "$active_player" ]]; then
        raw_title="$active_player_title"
        raw_artist="${active_player_artist:-Unknown}"

        # Escape special characters
        clean_name="${active_player%%.*}"
        clean_name="${clean_name^}"
        player_display_name=$(escape_characters "$clean_name")
        song_artist=$(truncate_text "$raw_artist" 50)
        song_title=$(truncate_text "$raw_title" 60)
    fi

    # Generate album art
    # url for fetching album art
    album_art_url=$(playerctl -p "$active_player" metadata mpris:artUrl 2>/dev/null)

    # check cache file and generate album art if needed
    cached_title=""
    if [[ -f "$title_cache_file" ]]; then
        cached_title=$(<"$title_cache_file")
    fi
    if [[ "$raw_title" != "$cached_title" ]] || [[ ! -f "$art_file" ]] || [[ ! -f "$raw_art_file" ]] || [[ ! -f "$blur_art_file" ]]; then
        echo "$raw_title" >"$title_cache_file"

        if [[ -z "$album_art_url" ]]; then
            # Generate album art for local videos (looks good)
            url=$(playerctl -p "$active_player" metadata xesam:url 2>/dev/null)
            if [[ "$url" == file://* ]]; then
                file_path="$(url_decode "${url#file://}")"
                mime=$(file --mime-type -b "$file_path")
                if [[ "$mime" == video/* ]]; then
                    ffmpegthumbnailer -i "$file_path" -o "$art_file" -s 720 -t 15% 2>/dev/null
                    # Verify if a valid art file was generated by checking its size
                    # Some YouTube audio downloads (.m4a files) use the 'video/webm' MIME type, which produces a 0-byte (empty) file
                    if [ -f "$art_file" ] && [ "$(stat -c%s "$art_file" 2>/dev/null || echo 0)" -gt 2000 ]; then
                        # Resize image else it looks ugly when height is small
                        magick "$art_file" -resize x400\! "$art_file"
                        # Save "true" to file since we are using video art
                        echo "true" >"$is_art"
                    else
                        # If we are using fallback art matching system theme then return
                        if [[ $(<"$is_art") == "fallback_$system_theme" ]]; then
                            return
                        else
                            # Save "false" to file since we arn't using video art
                            # It will later be use to generate fallback art
                            echo "false" >"$is_art"
                        fi
                    fi
                else
                    # For any other file like mp3
                    if [[ $(<"$is_art") == "fallback_$system_theme" ]]; then
                        return
                    else
                        echo "false" >"$is_art"
                    fi
                fi
            else
                # When we don't have art url and the file isn't local
                if [[ $(<"$is_art") == "fallback_$system_theme" ]]; then
                    return
                else
                    echo "false" >"$is_art"
                fi
            fi
        elif [[ "$album_art_url" == data:image* ]]; then
            base64_data="${album_art_url#*,}"
            echo "$base64_data" | base64 -d >"$art_file" 2>/dev/null
            echo "true" >"$is_art"
        elif [[ "$album_art_url" == file://* ]]; then
            raw_path="${album_art_url#file://}"
            decoded_path="$(url_decode "$raw_path")"
            cp "$decoded_path" "$art_file" 2>/dev/null
            echo "true" >"$is_art"
        elif [[ "$album_art_url" == https://* ]]; then
            curl -s "$album_art_url" --output "$art_file"
            echo "true" >"$is_art"
        fi

        # Process art file
        if [[ $(<"$is_art") == "true" ]]; then
            # Since this is valid art copy it before Imagemagick processes.
            cp "$art_file" "$raw_art_file" 2>/dev/null
            # Make a blurred art file
            magick -define jpeg:size=16x16 "$art_file" -scale 120 -fill black -colorize 30% -blur 0x4 -resize 400 "$blur_art_file"
            # Using these flags since youtube thumbnails are rectangular, which causes the art file to appear off-centered
            # Keeping background color black as white don't look good
            magick "$art_file" -gravity center -background black -extent "%[w]x%[w]" -quality 90 JPEG:"$art_file"
        else
            if [[ $(<"$is_art") == "false" ]]; then
                # Since we don't have an art file make one using fallback art.
                # Select background color based on system theme.
                [[ "$system_theme" == "dark" ]] && bg_color=black || bg_color=white
                # Save the fallback state to prevent repeatedly regenerating fallback art
                # when consecutive media items (e.g., reels or audio files) without album art
                # are played back-to-back.
                echo "fallback_$system_theme" >"$is_art"
                # Generate fallback art
                magick "$fallback_art_file" -background $bg_color -extent 512x512 "$art_file"
                # Now copy art
                cp "$art_file" "$raw_art_file" 2>/dev/null
                # Make a blurred art file
                magick -define jpeg:size=16x16 "$art_file" -scale 120 -fill black -colorize 30% -blur 0x4 -resize 400 "$blur_art_file"
            fi
        fi
    fi
}

############################################################################################
############################################################################################

########################
# ROFI-TUBE CONTROL
########################

control_rofitube() {
    local cmd="$1"
    local config_dir="$HOME/.config/rofi/rofi-tube"
    local conf_file="$config_dir/rofi-tube.conf"
    local script_path="$config_dir/rofi-tube.sh"
    local pid_file="$config_dir/rofi-tube.pid"

    # Check if PID file exists and process is running
    if [[ -f "$pid_file" ]]; then
        local pid=$(<"$pid_file")
        if [[ $(ps -p "$pid" -o cmd=) == *rofi-tube.sh* ]]; then
            local conf_player
            conf_player=$(grep "^player=" "$conf_file" | cut -d'"' -f2)

            # Match rofi-tube player to active player
            if [[ "$conf_player" == "$active_player"* ]] && [[ "$active_player" == "mpv"* || "$active_player" == "vlc"* ]]; then
                # Map playerctl commands to rofi-tube flags
                case "$cmd" in
                "next")
                    "$script_path" "--next"
                    ;;
                "previous")
                    "$script_path" "--previous"
                    ;;
                *)
                    return 1
                    ;;
                esac
                return 0
            fi
        fi
    fi
    return 1
}

# Send commands to player

player_do() {
    local cmd="$1" # next, previous, play-pause

    [ -n "$active_player" ] || return 1

    # Try to control rofi-tube first (for next/previous)
    if [[ "$cmd" == "next" || "$cmd" == "previous" ]]; then
        if control_rofitube "$cmd"; then
            return 0
        fi
    fi
    # Control players normally if rofi-tube isn't running
    playerctl -p "$active_player" "$cmd"
}

# Function to send notification
send_notification() {
    if [[ -z "$active_player" ]]; then
        echo "Nothing Playing No Notification Sent..."
        return
    fi
    while true; do
        # Fetch data and send notification
        fetch_data
        action=$(timeout 100s notify-send -h $notify_id "$player_display_name $player_status" \
            "$song_title\n<span alpha='90%'>$song_artist</span>" \
            --icon="$raw_art_file" \
            --action="previous=Previous" \
            --action="play-pause=$toggle" \
            --action="next=Next")

        # Handle Actions
        case "$action" in
        "previous")
            player_do previous
            sleep 0.2 # Give the player a moment to update metadata
            ;;
        "play-pause")
            player_do play-pause
            echo "$active_player" >"$player_cache_file"
            return
            ;;
        "next")
            player_do next
            sleep 0.2
            ;;
        *)
            return
            ;;
        esac
    done
}

########################
########################

############################################################
# Generate Spotify-style ambient colors from album art #####
############################################################

# The Imagemagick '-colorize' operator written in bash
#
# To blend two colors, the formula applied to each channel (R, G, B) is:
# C_out = C_in * (1 - p) + C_fill * p            [ p: The percentage of the fill color to apply ]
# Because our fill color is Black (0). The formula simplifies to:
# C_out = C_in * (1 - p)

darken_color() {
    # Strip # from hex
    local hex="${1//#/}"
    local percent="$2"

    # Convert Hex strings to Decimal integers
    local r_dec=$((16#${hex:0:2}))
    local g_dec=$((16#${hex:2:2}))
    local b_dec=$((16#${hex:4:2}))

    # Calculate the remaining percentage factor (e.g., 30% black means 70% color remains)
    local factor=$((100 - percent))

    # Formula: (Color * Factor + 50) / 100
    # Apply the formula per channel with rounding
    local r_out=$(((r_dec * factor + 50) / 100))
    local g_out=$(((g_dec * factor + 50) / 100))
    local b_out=$(((b_dec * factor + 50) / 100))

    # Convert back to zero-padded, uppercase 2-character Hex and print
    printf "#%02X%02X%02X\n" "$r_out" "$g_out" "$b_out"
}

# Add alpha channel to hex
hex_alpha() {
    local hex=$1
    local alpha=$(($2 * 255 / 100))
    printf "%s%02X\n" "$hex" "$alpha"
}

extract_colors() {
    # 1. -scale 1x2! (1px width and 2px height): Averages the top half and bottom half
    # 2. -modulate 100,150,100: Boosts saturation by 50% so that colors don't look "muddy"
    # 3. Convert to HSL color space
    # 4. -evaluate Min 40% on the Blue channel (which is Lightness in IM's HSL) guarantees white text is readable
    # 5. -evaluate Max 15% ensures the color never becomes pitch black
    # 6. Convert back to sRGB for hex output

    raw_colors=$(magick -define jpeg:size=16x16 "$raw_art_file" -resize 1x2! \
        -modulate 100,150,100 \
        -colorspace HSL \
        -channel B -evaluate Min 40% \
        -channel B -evaluate Max 15% \
        +channel -colorspace sRGB -depth 8 \
        -format "%[hex:p{0,0}] %[hex:p{0,1}]" info:)

    c1=${raw_colors% *} # Top average color
    c2=${raw_colors#* } # Bottom average color

    # Now, darken them so white text stays readable
    # Top color gets a 20% black, bottom gets a 35% black for a smooth gradient
    top_color=$(darken_color "$c1" 20)
    bottom_color=$(darken_color "$c2" 30)

    dark_color=$(darken_color "$c1" 70)
    bg_color=$(hex_alpha "$dark_color" 50)
    hover_color=$(hex_alpha "$dark_color" 70)
}

#############################################
#############################################

###########################
# Nowplaying Daemon #######
###########################

# The script will still work without this daemon running,
# but it may be slightly slower depending on the artwork file.
# For example, Spotify artwork need to be downloaded first.
#
# The daemon's only job is to handle the heavy lifting of generating the artwork file.
#
# The main script itself is very fast:
# ~0.02s script execution time + rofi rendering time ~(0.1x)s

if [[ "$1" == "--daemon" ]]; then
    clear
    echo "╔═════════════════════════════════════════════════════════════╗"
    echo "║  NOWPLAYING DAEMON • RUNNING                                ║"
    echo "╠═════════════════════════════════════════════════════════════╣"
    echo "║  » Hooked into D-Bus for instant track updates.             ║"
    echo "║  » It only triggers on track change or media player launch. ║"
    echo "║  » Event-driven: No polling, no CPU bloat.                  ║"
    echo "╚═════════════════════════════════════════════════════════════╝"

    hyprlock_np="$HOME/.config/hypr/hyprlock/nowplaying/nowplaying.sh"

    # Monitor D-Bus for Media Player (MPRIS) activity
    while read -r line; do
        # Ensure the script only reacts when:
        # 1. media player is opened or closed (NameOwnerChanged)
        # 2. or new track starts, changing the song metadata (string "Metadata")
        if [[ "$line" == *"member=NameOwnerChanged"* ]] || [[ "$line" == *"string \"Metadata\""* ]]; then
            # wait 0.8s to absorb rapid-fire signals and prevents calling function multiple times
            while read -t 0.8 -r _; do :; done
            # Update everything
            fetch_data
            if [ -n "$active_player" ]; then
                # Run hyprlock nowplaying script only when there is a active player.
                "$hyprlock_np" >/dev/null 2>&1
                echo "» Player detected: "\"$active_player\"". Nowplaying updated..."
            else
                echo "» Player closed or loading... "
            fi
        fi
    done < <(dbus-monitor --session \
        "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0namespace='org.mpris.MediaPlayer2'" \
        "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.mpris.MediaPlayer2.Player'")
fi

#########################################################
# Calls the fetch data function for building UI  ########
#########################################################
fetch_data
#########################################################

# Check currently used theme
current_theme=${rofi_theme##*/}

theme_str=""
# Just some mappings for each theme
case $current_theme in
"style-1")
    metadata_full=true
    [ -n "$active_player" ] && theme_str+="window {background-color: transparent; border-color: transparent; border: 0px;}"
    ;;
"style-2")
    metadata_full=true
    ambient_colors=true
    [ -n "$active_player" ] && theme_str+="mainbox {background-image: linear-gradient(90deg, rgba(0,0,0,55%), rgba(0,0,0,65%), rgba(0,0,0,95%));}"
    ;;
"style-3" | "style-4" | "style-5")
    metadata_full=true
    ;;
"style-6")
    metadata_full=true
    ambient_colors=true
    ;;
"style-7")
    metadata_full=true
    ambient_colors=true
    ;;
"style-8" | "style-9")
    [ -n "$active_player" ] && {
        song_title=$(truncate_text "$raw_title" 25)
        song_artist=$(truncate_text "$raw_artist" 25)
    }
    metadata_minimal=true
    ambient_colors=true
    ;;
"style-10")
    [ -n "$active_player" ] && {
        song_title=$(truncate_text "$raw_title" 28)
    }
    metadata_full=true
    ambient_colors=true
    ;;
*)
    ;;
esac

##############################################################
# Build the rofi UI based on selected style  #################
##############################################################

# Print Output based on selected theme
if [[ "$metadata_full" == "true" ]]; then
    display_text="<span weight='light' size='small' alpha='75%'>${player_display_name} ${player_status}</span>\
\n\n${song_title}\n<span size='4000'> </span>\n\
<span size='small' alpha='90%'>${song_artist}</span>"
elif [[ "$metadata_minimal" == "true" ]]; then
    display_text="${song_title}\n<span size='small' alpha='90%'>${song_artist}</span>"
fi

# Base theme string for rofi
theme_str+="textbox-custom { str: \"$display_text\"; }"

#################################################
# Overlay Effects for rofi ######################
#################################################

if [[ -n "$active_player" ]]; then
    if [[ "$system_theme" == "dark" ]]; then
        case "$current_theme" in
        "style-1")
            theme_str+="mainbox {background-image: linear-gradient(135deg, rgba(0,0,0,70%), rgba(10,10,10,60%), rgba(0,0,0,80%));} textbox-custom {text-color: #ffffff;}"
            ;;
        "style-4")
            theme_str+="mainbox {background-image: linear-gradient(135deg, rgba(0,0,0,40%), rgba(10,10,10,50%), rgba(0,0,0,60%));} textbox-custom {text-color: #ffffff;}"
            ;;
        *)
            ;;
        esac
    elif [[ "$system_theme" == "light" ]]; then
        case "$current_theme" in
        "style-1")
            theme_str+="mainbox {background-image: linear-gradient(135deg, rgba(255,255,255,50%), rgba(240,240,240,40%), rgba(255,255,255,60%));} textbox-custom {text-color: #000000;}"
            ;;
        "style-4")
            theme_str+="mainbox {background-image: linear-gradient(135deg, rgba(255,255,255,30%), rgba(240,240,240,20%), rgba(255,255,255,50%));} textbox-custom {text-color: #000000;}"
            ;;
        *)
            ;;
        esac
    fi
fi
############################################################################################
############################################################################################

# Only trigger the ambient effect if there is an actual art file, not for the fallback art file.
if [[ "$ambient_colors" == "true" ]] && [[ -n "$active_player" ]] && [[ $(<"$is_art") == "true" ]]; then
    extract_colors
    if [[ "$current_theme" != "style-2" ]]; then
        theme_str+="window {background-image: linear-gradient( 90, ${top_color}, ${bottom_color});}"
    fi
    theme_str+="window {background-color: transparent; border-color: transparent; border: 0px;}"
    theme_str+="element { text-color: #ffffff; background-color: ${bg_color};} element.selected { text-color: #ffffff; background-color: ${hover_color};}"
    theme_str+="album-art {background-color: ${bg_color};}"
    theme_str+="textbox-custom { text-color: #ffffff; }"
    theme_str+="textbox-title { text-color: #ffffff; }"
fi

###############################
# Launch Rofi window  #########
###############################
selected_option=$(
    echo -e "$pre\n$toggle\n$next" | rofi -dmenu \
        -theme "$rofi_theme" \
        -theme-str "$theme_str" \
        -select "$toggle"
)
# Control player
case "$selected_option" in
"$pre")
    player_do previous
    sleep 0.2
    send_notification
    ;;
"$toggle")
    player_do play-pause
    echo "$active_player" >"$player_cache_file"
    send_notification
    ;;
"$next")
    player_do next
    sleep 0.2
    send_notification
    ;;
esac
