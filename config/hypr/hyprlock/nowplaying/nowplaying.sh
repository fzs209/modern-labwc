#!/bin/bash

#####################################
## author @Harsh-bin Github #########
#####################################

# --- Configuration ---
fallback_art_file="$HOME/.config/hypr/hyprlock/nowplaying/fallback_album_art.webp"

cache_dir="/tmp/nowplaying/hypr"
mkdir -p "$cache_dir"
art_file="$cache_dir/album_art.webp"
# cache files
title_cache_file="$cache_dir/song_title.cache"
player_cache_file="$cache_dir/player.cache"

# --- Functions ---

# Determine active player

players_list=$(playerctl -l 2>/dev/null)
active_player=""
active_player_priority=0

if [ -f "$player_cache_file" ]; then
    cached_player_name=$(<"$player_cache_file")
fi

# Get all player data at once
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

########################
# ROFI-TUBE CONTROL
########################
control_rofitube() {
    local cmd="$1"
    local config_dir="$HOME/.config/rofi/rofi-tube"
    local conf_file="$config_dir/rofi-tube.conf"
    local script_path="$config_dir/rofi-tube.sh"
    local pid=$(<"$config_dir/rofi-tube.pid")

    if [[ $(ps -p "$pid" -o cmd=) == *rofi-tube.sh* ]]; then
        local conf_player
        conf_player=$(grep "^player=" "$conf_file" | cut -d'"' -f2)
        if [[ "$active_player" == *"$conf_player"* ]] && [[ "$active_player" == *"mpv"* || "$active_player" == *"vlc"* ]]; then
            "$script_path" "$cmd"
            return 0
        fi
    fi
    return 1
}

# New functions for buttons
cleanup() {
    rm -f "$art_file" "$title_cache_file" "$player_cache_file" 2>/dev/null
}
# Helper to instantly trigger hyprlock to update the labels
update_ui() {
    pkill -USR2 hyprlock >/dev/null 2>&1
}
player_do() {
    [[ -n "$active_player" ]] || return
    playerctl -p "$active_player" "$1"
}

case "$1" in
--toggle-pause)
    player_do play-pause
    echo "$active_player" >"$player_cache_file"
    sleep 0.05
    update_ui
    exit 0
    ;;
--next)
    if ! control_rofitube "--next"; then
        player_do next
        sleep 3
        cleanup
    fi
    exit 0
    ;;
--previous)
    if ! control_rofitube "--previous"; then
        player_do previous
        sleep 3
        cleanup
    fi
    exit 0
    ;;
--get-previous-btn)
    [[ -n "$active_player" ]] && echo "<tt> </tt>"
    exit 0
    ;;
--get-next-btn)
    [[ -n "$active_player" ]] && echo "<tt> </tt>"
    exit 0
    ;;
--get-toggle-btn)
    if [[ -n "$active_player" ]]; then
        [[ "$active_player_status" == "Playing" ]] && echo "<tt>  </tt>" || echo "<tt>  </tt>"
    fi
    exit 0
    ;;
esac

# Art clean up if no valid player found for clean look on hyprlock screen.
if [[ -z "$active_player" ]]; then
    cleanup
    exit 0
fi

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

if [[ -n "$active_player" ]]; then
    raw_title="$active_player_title"
    raw_artist="${active_player_artist:-Unknown}"
    # Escape special characters
    clean_name="${active_player%%.*}"
    clean_name="${clean_name^}"
    player_display_name=$(escape_characters "$clean_name")
    song_artist=$(escape_characters "$raw_artist")

    if ((${#raw_title} > 60)); then
        raw_short_title="${raw_title:0:60}..."
    else
        raw_short_title="$raw_title"
    fi
    song_title=$(escape_characters "$raw_short_title")

    # Handle album_art_url output
    cached_title=""
    if [[ -f "$title_cache_file" ]]; then
        cached_title=$(<"$title_cache_file")
    fi
    if [[ "$raw_title" != "$cached_title" ]] || [[ ! -f "$art_file" ]]; then
        echo "$raw_title" >"$title_cache_file"
        # url for fetching albumart
        album_art_url=$(playerctl -p "$active_player" metadata mpris:artUrl 2>/dev/null)

        if [[ -z "$album_art_url" ]]; then
            # Generate artfiles for local videos (looks good)
            url=$(playerctl -p "$active_player" metadata xesam:url 2>/dev/null)
            if [[ "$url" == file://* ]]; then
                file_path="$(url_decode "${url#file://}")"
                mime=$(file --mime-type -b "$file_path")
                if [[ "$mime" == video/* ]]; then
                    ffmpegthumbnailer -i "$file_path" -o "$art_file" -s 160 -t 15% 2>/dev/null
                    # Verify if a valid art file was generated by checking its size.
                    # Some YouTube audio downloads (.m4a files) use the 'video/webm' MIME type, which produces a 0-byte (empty) file.
                    if [ -f "$art_file" ] && [ "$(stat -c%s "$art_file" 2>/dev/null || echo 0)" -le 2000 ]; then                        
                        cp "$fallback_art_file" "$art_file" 2>/dev/null
                    fi
                else
                    # copy fallback art for music files
                    cp "$fallback_art_file" "$art_file" 2>/dev/null
                fi
            else
                # copy fallback art for everything else
                cp "$fallback_art_file" "$art_file" 2>/dev/null
            fi
        elif [[ "$album_art_url" == data:image* ]]; then
            base64_data="${album_art_url#*,}"
            echo "$base64_data" | base64 -d >"$art_file" 2>/dev/null
        elif [[ "$album_art_url" == file://* ]]; then
            raw_path="${album_art_url#file://}"
            decoded_path="$(url_decode "$raw_path")"
            cp "$decoded_path" "$art_file" 2>/dev/null
        elif [[ "$album_art_url" == https://* ]]; then
            curl -s "$album_art_url" --output "$art_file"
        fi
        # Convert all to webp
        # Using these flags since youtube thumbnails are rectangular, which causes the buttons to appear off-centered
        # background color updates when wallpaper is changed
        magick "$art_file" -gravity center -background "rgba(35,  76,  89, 0.4)" -extent "%[w]x%[w]" -quality 80 WEBP:"$art_file"
    fi
fi

if [[ "$active_player_status" != "Playing" ]]; then
    player_status="Paused"
else
    player_status=""
fi

# Print Output
# Added a zero-width space (&#8203;) at the beginning to fix Pango rendering.
# without it, the first line won't be rendered with the 'small' size.
echo -e "&#8203;<span size='small' alpha='90%'>${player_display_name} ${player_status}</span>\n<span size='4000'> </span>\
\n${song_title}\n<span size='small' alpha='95%'>${song_artist}</span>"
