#!/bin/bash

waybar_config_dir="$HOME/.config/waybar"
style_file="$waybar_config_dir/style.css"
dunstrc="$HOME/.config/dunst/dunstrc"

# --- COLOR EXTRACTION LOGIC ---

# Default Fallbacks
bg_color="#121318"
fg_color="#e3e1e9"
icon_color="#b7c4ff" # icon color will be used for text color too
mute_color="#ffb4ab" # will be used for critical highlight in notification

# Find the active color file from style.css
imported_file=$(sed -n 's/.*@import "colors\/\(.*\)";.*/\1/p' "$style_file" | head -n 1)

get_color() {
    grep "@define-color $1" "$full_color_path" | sed -n 's/.*#\([0-9a-fA-F]\{6\}\).*/#\1/p'
}

if [ -n "$imported_file" ]; then
    full_color_path="$waybar_config_dir/colors/$imported_file"
    if [ -f "$full_color_path" ]; then
            extracted_bg_color=$(get_color "module_bg") 
            extracted_fg_color=$(get_color "bar_fg")
            extracted_icon_color=$(get_color "primary")
            extracted_mute_color=$(get_color "power")
            extracted_border_color=$(get_color "border_color")
        if [ -n "$extracted_bg_color" ]; then bg_color="$extracted_bg_color"; fi
        if [ -n "$extracted_fg_color" ]; then fg_color="$extracted_fg_color"; fi
        if [ -n "$extracted_icon_color" ]; then icon_color="$extracted_icon_color"; fi
        if [ -n "$extracted_mute_color" ]; then mute_color="$extracted_mute_color"; fi
        if [ -n "$extracted_border_color" ]; then border_color="$extracted_border_color"; fi
    fi
else
    notify-send "Warning failed to extract colors using fallback!"
fi

# directories to look into
dirs=(
    "$HOME/.config/dunst/brightness-icon"
    "$HOME/.config/dunst/volume-icon"
)

for dir in "${dirs[@]}"; do
    if [ -d "$dir" ]; then
        # Iterate over every png file in the directory
        for img in "$dir"/*.png; do
            if [ -f "$img" ]; then
                # Run ImageMagick
                magick "$img" -channel RGB -fill "$icon_color" -colorize 100 "$img"
                echo "Recolored: ${img##*/} to $icon_color"
            fi
        done
    else
        echo "Directory not found: $dir"
    fi
done

# mute icons
mute_icons=(
    "$HOME/.config/dunst/volume-icon/mute.png"
    "$HOME/.config/dunst/volume-icon/mute-microphone.png"
    "$HOME/.config/dunst/volume-icon/mute-both.png"
)

for mute_icons in "${mute_icons[@]}"; do
    if [[ -f "$mute_icons" ]]; then
        magick "$mute_icons" -channel RGB -fill "$mute_color" -colorize 100 "$mute_icons"
        echo "Recolored: ${mute_icons##*/} to $mute_color"
    else
        echo "Warning: $mute_icons not found."
    fi
done

# applies color to alarm icons
alarm="$HOME/.config/waybar/scripts/clock_calendar/alarm/clock.png"
snooze="$HOME/.config/waybar/scripts/clock_calendar/alarm/snooze.png"
magick "$alarm" -channel RGB -fill "$mute_color" -colorize 100 "$alarm"
magick "$snooze" -channel RGB -fill "$icon_color" -colorize 100 "$snooze"

# applies color to rofi nowplaying icon
rofi_albumart_icon="$HOME/.config/rofi/nowplaying/fallback_album_art.webp"
magick "$rofi_albumart_icon" -channel RGB -fill "$icon_color" -colorize 100 "$rofi_albumart_icon"
echo "Recolored: ${rofi_albumart_icon##*/} to $icon_color"

# applies color to hyprlock nowplaying icon
hyprlock_conf="$HOME/.config/hypr/hyprlock.conf"
hyprlock_albumart_icon="$HOME/.config/hypr/hyprlock/nowplaying/fallback_album_art.webp"
# extracts rgba color value from config file
hyprlock_icon_color=$(awk -F'=[[:space:]]*' '
/# Time/ {found=1; next}
found && /color *=/ {print $2; exit}
' "$hyprlock_conf")
magick "$hyprlock_albumart_icon" -channel RGB -fill "$hyprlock_icon_color" -colorize 100 "$hyprlock_albumart_icon"
echo "Recolored: ${hyprlock_albumart_icon##*/} to $hyprlock_icon_color"

# rofi-tube delete history icon
delete_icon="$HOME/.config/rofi/rofi-tube/delete_icon.png"
magick "$delete_icon" -channel RGB -fill "$fg_color" -colorize 100 "$delete_icon"

# Prevent old cached album art from being shown when using fallback image
[ -f "$HOME/.config/hypr/hyprlock/nowplaying/album_art.webp" ] && rm "$HOME/.config/hypr/hyprlock/nowplaying/album_art.webp"
[ -f "$HOME/.config/rofi/nowplaying/album_art.webp" ] && rm "$HOME/.config/rofi/nowplaying/album_art.webp"

# seed color to dunstrc file and reloads the daemon

if [ -f "$dunstrc" ]; then
    sed -i \
        -e "s/^\s*frame_color\s*=.*/    frame_color = \"$border_color\"/" \
        -e "s/^\s*separator_color\s*=.*/    separator_color = \"$icon_color\"/" \
        -e "s/^\s*foreground\s*=.*/    foreground = \"$fg_color\"/" \
        -e "s/^\s*highlight\s*=.*/    highlight = \"$icon_color\"/" \
        -e "s/^\s*background\s*=.*/    background = \"$bg_color\"/" \
        -e "71s/^\s*foreground\s*=.*/    foreground = \"$mute_color\"/" \
        -e "72s/^\s*highlight\s*=.*/    highlight = \"$mute_color\"/" \
        "$dunstrc"
    # reloads daemon
    pgrep -x dunst >/dev/null && dunstctl reload
else
    echo "File not found! $dunstrc"
fi

exit 0
