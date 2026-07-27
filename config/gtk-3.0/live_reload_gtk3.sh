#!/bin/bash

#####################################
## author @Harsh-bin Github #########
#####################################

# A script to update running gtk3 applications themes when colors scheme is changed

# configuration variables
theme_1="do-not-delete-theme-1"
theme_2="do-not-delete-theme-2"

# Default to the "wallpaper" color scheme if no argument is provided.
selected="${1:-wallpaper}"

# Prevent this script from changing the active color scheme.
# Used by toggle-theme.sh, which only needs to alternate the GTK theme to force a reload.
# Without this flag, the default "wallpaper" scheme would be applied and overwrite the user's current color scheme.
skip_colors=false
if [ "$1" == "no_color_change" ]; then
    skip_colors=true
fi

# file paths
css_file_1="$HOME/.themes/$theme_1/gtk-3.0/gtk.css"
css_file_2="$HOME/.themes/$theme_2/gtk-3.0/gtk.css"
gtk_settings="$HOME/.config/gtk-3.0/settings.ini"
reload_script="$HOME/.config/labwc/gtk.sh"

# update gtk.css for both themes with new colors
if [ "$skip_colors" = false ]; then
    for css_file in "$css_file_1" "$css_file_2"; do
        if [ -f "$css_file" ]; then
            sed -i "s|@import \".*/colors/.*\.css\";|@import \"$HOME/.config/gtk-3.0/colors/${selected}.css\";|" "$css_file"
        else
            echo "Warning: $css_file not found."
        fi
    done
else
    echo "Skipping color update (no_color_change flag used)"
fi

# track and toggle the theme
if [ ! -f "$gtk_settings" ]; then
    echo "Error: GTK settings file not found at $gtk_settings"
    exit 1
fi

# read the current theme directly from settings.ini
current_theme=$(grep "^gtk-theme-name=" "$gtk_settings" | cut -d'=' -f2)

# decide which theme to apply next
if [ "$current_theme" == "$theme_1" ]; then
    next_theme="$theme_2"
else
    next_theme="$theme_1"
fi

# update settings.ini with the new theme
sed -i "s|^gtk-theme-name=.*|gtk-theme-name=$next_theme|" "$gtk_settings"

echo "CSS updated to use: $selected"
echo "Switched GTK theme to: $next_theme"

# run the GTK reload script to apply the new theme
if [ -f "$reload_script" ]; then
    "$reload_script"
    echo "Theme reload GTK.sh script executed successfully."
else
    echo "Error: reload script not found at $reload_script"
fi
