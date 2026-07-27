#!/bin/bash

#####################################
## author @Harsh-bin Github #########
#####################################

# Change path to wallpaper
wall_dir="/usr/share/backgrounds/images"
# Wallpaper thumbnails folder to be used by rofi
thumb_dir="$HOME/.cache/wallselect/thumbnails"

# New script to generate thumbnails of wallpapers to be used by rofi for lightning fast loading
source "$HOME/.config/rofi/wallselect/wall_cache.sh"

# Wallselect theme file
wallselect_theme="$HOME/.config/rofi/wallselect/style-1.rasi"
# Directories to copy wallpaper
rofi_img="$HOME/.config/rofi/images/"
wall_cache_dir="$HOME/.config/labwc/wallpaper/"
# rofi menu file
horizontal_menu="$HOME/.config/rofi/horizontal_menu.rasi"

# Path to the files that imports the color scheme
rofi_colors="$HOME/.config/rofi/shared/colors.rasi"
waybar_css="$HOME/.config/waybar/style.css"
gtk4_css="$HOME/.config/gtk-4.0/gtk.css"
qt5_conf="$HOME/.config/qt5ct/qt5ct.conf"
qt6_conf="$HOME/.config/qt6ct/qt6ct.conf"

# labwc theme
labwc_theme_file="$HOME/.config/labwc/themerc-override"
labwc_theme_dir="$HOME/.config/labwc/colors"

swaync_css="$HOME/.config/swaync/style.css"

# Hyprlock
hyprlock_conf="$HOME/.config/hypr/hyprlock.conf"
hyprlock_dir="$HOME/.config/hypr/hyprlock"

# Main script to reload running gtk3 applications
# This also runs ~/.config/labwc/gtk.sh that helps in changing system theme like light/dark in chrome
gtk_theme_reload="$HOME/.config/gtk-3.0/live_reload_gtk3.sh"

# Gtk configs
gtk3_settings_file="$HOME/.config/gtk-3.0/settings.ini"
gtk4_settings_file="$HOME/.config/gtk-4.0/settings.ini"

# Notification icon color changer
update_notification_icon_color="$HOME/.config/dunst/change_icon_color.sh"

# Nowplaying
rofi_np_script="$HOME/.config/rofi/nowplaying/nowplaying.sh"

# Rofi tube
update_playlist_theme="$HOME/.config/rofi/rofi-tube/rofi_alpha_changer.sh"

# Check if GTK3 settings file exists
if [ ! -f "$gtk3_settings_file" ]; then
    echo "Error: $gtk3_settings_file not found."
    exit 1
fi
# Check if the wallpaper directory exists
if [[ ! -d "$wall_dir" || ! -d $thumb_dir ]]; then
    echo "Error: Wallpaper directory $wall_dir or $thumb_dir not found."
    exit 1
fi

# New selection logic, now can apply wallpaper with image path without showing rofi window
valid_exts="jpg|jpeg|png|webp|gif"
selected=""

if [ -n "$1" ]; then
    if [ ! -f "$1" ]; then
        echo "Error: File '$1' not found."
        exit 1
    fi
    if ! echo "$1" | grep -q -iE "\.(${valid_exts})$"; then
        echo "Error: File '$1' is not a valid image type ($valid_exts)."
        exit 1
    fi
    selected="$1"
else
    # If no argument is provided, run the rofi
    raw_selected=$(find "$thumb_dir" \
        -type f \
        -regextype posix-extended \
        -iregex ".*\.(${valid_exts})" |
        shuf |
        while read -r img; do
            echo -en "${img}\0icon\x1f${img}\n"
        done |
        rofi -dmenu -mesg "<big><b>󰸉 Select Wallpaper</b></big>" \
            -show-icons -theme "$wallselect_theme")
    if [ -z "$raw_selected" ]; then
        echo "Canceled..."
        exit 0
    fi
    selected="$wall_dir/${raw_selected##*/}"
fi

# Exit if no wallpaper is selected by rofi
if [ -z "$selected" ]; then
    echo "Canceled..."
    exit 0
fi

# Function to set wallpaper, added support for awww and swww both
set_wallpaper() {
    transition="--transition-type random \
                --transition-duration 3 \
                --transition-fps 60 \
                --transition-bezier 0.99,0.99,0.99,0.99"

    if pgrep -x swww-daemon >/dev/null; then
        swww img $transition "$selected" &
    elif pgrep -x awww-daemon >/dev/null; then
        awww img $transition "$selected" &
    fi
}

# Function to change color scheme to wallpaper
change_color_scheme_to_wallpaper() {
    # Apply only wallpaper color scheme
    for file in "$waybar_css" "$gtk4_css" "$swaync_css"; do
        sed -i "s|@import \"colors/.*\.css\";|@import \"colors/wallpaper.css\";|" "$file"
    done

    # Qt Apps
    sed -i "s|\(color_scheme_path=.*/\)[^/]*$|\1wallpaper.conf|" "$qt5_conf" "$qt6_conf"
    # Rofi
    sed -i "s|@import \".*colors/.*\.rasi\"|@import \"~/.config/rofi/colors/wallpaper.rasi\"|" "$rofi_colors"

    cp "$labwc_theme_dir/wallpaper.color" "$labwc_theme_file"
}

# Source theme.sh.
# This script defines the "apply_theme" function:
#   apply_theme <light|dark> [skip_matugen_generation]
#
# Arguments:
#   $1 - Theme mode ("light" or "dark").
#   $2 - Optional. If set to "skip_matugen_generation" skips generating a new Matugen color scheme.
source "$HOME/.config/waybar/scripts/theme.sh"

# --- Main Menu ---
main_options="Yes\nNo"
main_choice=$(echo -e "$main_options" | rofi -dmenu -mesg "<b>Set Color Scheme from wallpaper?</b>" -theme "$horizontal_menu")

# --- Handle the choice with a case statement ---
case "$main_choice" in
"Yes")
    options="Dark\nLight"
    choice=$(echo -e "$options" | rofi -dmenu -mesg "<b>Select Color Scheme</b>" -theme "$horizontal_menu")
    case "$choice" in
    "Light")
        # Generates light color scheme from wallpaper
        matugen image "$selected" -m "light" --source-color-index 0
        sleep 0.2s
        # Sets color scheme to wallpaper
        change_color_scheme_to_wallpaper
        # Applies wallpaper
        set_wallpaper
        # Sets light System theme
        apply_theme "light" "skip_matugen_generation"
        # RUN THEME CHANGER
        "$gtk_theme_reload"
        echo "Switched to light theme."
        ;;
    "Dark")
        # Generates dark color scheme from wallpaper
        matugen image "$selected" -m "dark" --source-color-index 0
        sleep 0.2s
        # Sets color scheme to wallpaper
        change_color_scheme_to_wallpaper
        # Applies wallpaper
        set_wallpaper
        # Sets dark System theme
        apply_theme "dark" "skip_matugen_generation"     
        # RUN THEME CHANGER
        "$gtk_theme_reload"
        echo "Switched to dark theme."
        ;;
    *)
        exit 0
        ;;
    esac
    ;;

"No")
    # Sets wallpaper only
    set_wallpaper
    ;;
*)
    exit 0
    ;;
esac

# Reloads labwc
pgrep -x labwc >/dev/null && labwc --reconfigure
# Reloads swaync css
pgrep -x swaync >/dev/null && swaync-client -rs

# Copy the selected wallpaper to other directories
# Rofi doesn't care about file extension
cp "$selected" "$rofi_img/wallpaper.png"

# Get the file extension of the selected wallpaper
extension=${selected##*.}
new_wallpaper_file="${wall_cache_dir}/wallpaper.${extension}"
find "$wall_cache_dir" -maxdepth 1 -type f -name 'wallpaper.*' -delete
find "$hyprlock_dir" -maxdepth 1 -type f -name 'wallpaper.*' -delete
cp "$selected" "$new_wallpaper_file"
cp "$new_wallpaper_file" "$hyprlock_dir"

# Hyprlock specific color generation
if [ "${extension}" = "gif" ]; then
    # Extracts frame of the gif and set it as hyprlock background.
    magick "$selected[0]" "$hyprlock_dir/background.png" >/dev/null &
    new_path="~/.config/hypr/hyprlock/background.png"
else
    new_path="~/.config/hypr/hyprlock/wallpaper.${extension}"
fi
# Remove 'path = ' and any spaces
clean_path="${new_path##*= }"
hyprlock_background="${clean_path/\~/$HOME}"

# Improved brightness check
# Convert to LAB (perceptual color space) and keep only the L (lightness channel)
wall_brightness=$(magick "$hyprlock_background" -resize 256x256! -colorspace LAB -separate -delete 1,2 -format "%[fx:100*mean]" info:)

# Compare the brightness of wallpaper and then generates hyprlock color accordingly
if (($(echo "$wall_brightness > 70" | bc -l))); then
    matugen -c "$HOME/.config/matugen/hyprlock.toml" image "$hyprlock_background" -m "dark" --source-color-index 0
else
    matugen -c "$HOME/.config/matugen/hyprlock.toml" image "$hyprlock_background" -m "light" --source-color-index 0
fi
# Restores the wallpaper after generating matugen colors
sed -i "/background {/,/}/ s|path = .*|path = $new_path|" "$hyprlock_conf"

# update nowplaying script to use new colors for albumart to match the aesthetics
line=$(awk '
/# CURRENT SONG/ {found=1; next}
found && /color *=/ {print; exit}
' "$hyprlock_conf")

rgb=${line#*rgba(}
rgb=${rgb%%)*}
IFS=',' read -r r g b _ <<<"$rgb"
# update script
hyprlock_np_dir="$HOME/.config/hypr/hyprlock/nowplaying"
hyprlock_np_script="$hyprlock_np_dir/nowplaying.sh"
sed -i "s/-background \"rgba([^)]*)\"/-background \"rgba($r, $g, $b, 0.4)\"/" "$hyprlock_np_script"
# deletes the artfiles to make a refresh
rm -f "$hyprlock_np_dir/album_art.webp" "$rofi_np_dir/album_art.webp" 2>/dev/null

# updates the notification icon color
"$update_notification_icon_color"
# updates rofi-tube playlist theme
"$update_playlist_theme"

exit 0
