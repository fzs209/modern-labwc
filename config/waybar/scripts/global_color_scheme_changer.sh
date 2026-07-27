#!/bin/bash

rofi_colors="$HOME/.config/rofi/shared/colors.rasi"
waybar_css="$HOME/.config/waybar/style.css"
gtk4_css="$HOME/.config/gtk-4.0/gtk.css"
qt5_conf="$HOME/.config/qt5ct/qt5ct.conf"
qt6_conf="$HOME/.config/qt6ct/qt6ct.conf"
labwc_theme_dir="$HOME/.config/labwc/colors"
labwc_theme_file="$HOME/.config/labwc/themerc-override"
swaync_css="$HOME/.config/swaync/style.css"

# Main script to reload running gtk3 applications
# This also runs ~/.config/labwc/gtk.sh that helps in changing system theme like light/dark in chrome
gtk_theme_reload="$HOME/.config/gtk-3.0/live_reload_gtk3.sh"

# Mpv theme updater
mpv_theme_updater="$HOME/.config/mpv/script-opts/update_theme.sh"

# Rofi tube
update_playlist_theme="$HOME/.config/rofi/rofi-tube/rofi_alpha_changer.sh"

# Notification icon color changer
update_notification_icon_color="$HOME/.config/dunst/change_icon_color.sh"

# rofi vertical menu
rofi_vertical_menu="$HOME/.config/rofi/vertical_style_menu.rasi"

# Path to the file that imports the color scheme
rofi_colors_dir="$HOME/.config/rofi/colors"
# Dynamically find all .rasi files in the colors directory "waybar, gtk, Qt etc also have same names so..."
color_files=$(find "$rofi_colors_dir" -maxdepth 1 -type f -name "*.rasi" -printf "%f\n" | sort | sed 's/\.rasi$//')
# Shows wallpaer color at top of list
color_options="wallpaper\n$color_files"
# Display the Rofi menu
selected_color=$(echo -e "$color_options" | rofi -dmenu -mesg "<b>Select Color Scheme</b>" -theme $rofi_vertical_menu \
    -theme-str 'window {height: 90%;} element {border-radius: 8px 0px 0px 8px;} listview { lines: 8; scrollbar: true;}')

# Source theme.sh.
# This script defines the "apply_theme" function:
#   apply_theme <light|dark> [skip_matugen_generation]
#
# Arguments:
#   $1 - Theme mode ("light" or "dark").
#   $2 - Optional. If set to "skip_matugen_generation" skips generating a new Matugen color scheme.
source "$HOME/.config/waybar/scripts/theme.sh"

# Updates everything
if [ -n "$selected_color" ]; then
    # Update all config files
    for file in "$waybar_css" "$gtk4_css" "$swaync_css"; do
        sed -i "s|@import \"colors/.*\.css\";|@import \"colors/${selected_color}.css\";|" "$file"
    done

    # Qt Apps
    sed -i "s|\(color_scheme_path=.*/\)[^/]*$|\1${selected_color}.conf|" "$qt5_conf" "$qt6_conf"
    # Rofi
    sed -i "s|@import \".*colors/.*\.rasi\"|@import \"~/.config/rofi/colors/${selected_color}.rasi\"|" "$rofi_colors"

    # Applies dark/light theme accordingly
    case "$selected_color" in
    "paper" | "lavender-pastel" | "everforest-light" | "yousai")
        apply_theme "light"
        ;;
    "wallpaper")
        system_theme="$HOME/.config/labwc/system.theme"
        if [[ $(<"$system_theme") == "dark" ]]; then
            apply_theme "dark"
        else
            apply_theme "light"
        fi
        ;;
    *)
        apply_theme "dark"
        ;;
    esac

    # Reloads running gtk3 apps
    # Pass "selected_color" to gtk_theme_reload script.
    # This script also runs ~/.config/labwc/gtk.sh
    "$gtk_theme_reload" "$selected_color"
    # updates mpv theme to use same color scheme
    "$mpv_theme_updater"
    # Reloads swaync css
    pgrep -x swaync >/dev/null && swaync-client -rs
    # Reloads labwc
    cp "$labwc_theme_dir/${selected_color}".color "$labwc_theme_file"
    pgrep -x labwc >/dev/null && labwc --reconfigure
    # updates the notification icon color
    "$update_notification_icon_color"
    # updates rofi-tube playlist theme
    "$update_playlist_theme"
    # deletes the artfiles to make a refresh
    rm -f "/tmp/nowplaying/album_art.webp" "/tmp/nowplaying/hypr/album_art.webp" 2>/dev/null
    # send notification
    notify-send "Color scheme changed to ( ${selected_color^^} )"
fi
