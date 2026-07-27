#!/bin/bash

# Toggles between light and dark themes

labwc_dir="$HOME/.config/labwc"
labwc_rc_xml="$labwc_dir/rc.xml"
labwc_theme_file="$labwc_dir/themerc-override"
labwc_theme_dir="$labwc_dir/colors"

# File that tracks system theme (light/dark)
system_theme="$labwc_dir/system.theme"

# Main script to reload running gtk3 applications
# This also runs ~/.config/labwc/gtk.sh that helps in changing system theme like light/dark in chrome
gtk_theme_reload="$HOME/.config/gtk-3.0/live_reload_gtk3.sh"

# Notification icon color changer
update_notification_icon_color="$HOME/.config/dunst/change_icon_color.sh"

# Rofi tube
update_playlist_theme="$HOME/.config/rofi/rofi-tube/rofi_alpha_changer.sh"

# Source theme.sh.
# This script defines the "apply_theme" function:
#   apply_theme <light|dark> [skip_matugen_generation]
#
# Arguments:
#   $1 - Theme mode ("light" or "dark").
#   $2 - Optional. If set to "skip_matugen_generation" skips generating a new Matugen color scheme.
source "$HOME/.config/waybar/scripts/theme.sh"

# Toggle theme based on current setting in GTK3 file
if [[ $(<"$system_theme") == "dark" ]]; then
    # Switch to light theme
    apply_theme "light"
    # RUN THEME CHANGER
    # Pass "no_color_change" to gtk_theme_reload script.
    # This skips updating the color scheme in the GTK CSS file while still
    # alternating between theme_1 and theme_2 to force GTK to reload the theme.
    "$gtk_theme_reload" "no_color_change"
    # updates rofi-tube playlist theme
    "$update_playlist_theme"
    echo "Switched to light theme."
else
    # Switch to dark theme
    apply_theme "dark"
    # RUN THEME CHANGER
    "$gtk_theme_reload" "no_color_change"
    # updates rofi-tube playlist theme
    "$update_playlist_theme"
    echo "Switched to dark theme."
fi

# Set labwc theme (light or dark) based on current GTK color scheme.
gtk_css="$HOME/.config/gtk-4.0/gtk.css"
if ! grep -qE '@import\s+"colors/wallpaper\.css"' "$gtk_css"; then
    if [ "$labwc_theme_2" = true ]; then
        if grep -qE '@import\s+"colors/(paper|lavender-pastel|everforest-light)\.css"' "$gtk_css"; then
            sed -i '/<theme>/,/<\/theme>/ s|<name>.*</name>|<name>labwc-light</name>|' "$labwc_rc_xml"
        else
            sed -i '/<theme>/,/<\/theme>/ s|<name>.*</name>|<name>labwc-dark</name>|' "$labwc_rc_xml"
        fi
    fi
fi

# Only matugen theme contails "General"
if grep -q "General" "$labwc_theme_file"; then
    cp "$labwc_theme_dir/wallpaper.color" "$labwc_theme_file"
    # Reloads labwc
    pgrep -x labwc >/dev/null && labwc --reconfigure
fi

# Qt Apps (this refreshes the running app theme)
touch "$HOME/.config/"{qt5ct/qt5ct.conf,qt6ct/qt6ct.conf}

# deletes the artfiles to make a refresh
rm -f "/tmp/nowplaying/album_art.webp" "/tmp/nowplaying/hypr/album_art.webp" 2>/dev/null
# updates the notification icon color
"$update_notification_icon_color"
exit 0
