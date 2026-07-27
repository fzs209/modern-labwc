#!/bin/bash

# Path to the file that imports the color scheme
rofi_colors_dir="$HOME/.config/rofi/colors"
rofi_colors="$HOME/.config/rofi/shared/colors.rasi"
# Rofi tube
update_playlist_theme="$HOME/.config/rofi/rofi-tube/rofi_alpha_changer.sh"

# rofi vertical menu
rofi_vertical_menu="$HOME/.config/rofi/vertical_style_menu.rasi"

# Dynamically find all .rasi files in the colors directory
color_files=$(find "$rofi_colors_dir" -maxdepth 1 -type f -name "*.rasi" -printf "%f\n" | sort | sed 's/\.rasi$//')
# Shows wallpaer color at top of list
color_options="wallpaper\n$color_files"
# Display the Rofi menu
selected_color=$(echo -e "$color_options" | rofi -dmenu -mesg "<b>Select Color Scheme</b>" -theme $rofi_vertical_menu \
    -theme-str 'window {height: 90%;} element {border-radius: 8px 0px 0px 8px;} listview { lines: 8; scrollbar: true;}')

# Update only color.rasi
if [ -n "$selected_color" ]; then
    sed -i "s|@import \".*colors/.*\.rasi\"|@import \"~/.config/rofi/colors/${selected_color}.rasi\"|" "$rofi_colors"
    # updates rofi-tube playlist theme
    "$update_playlist_theme"
fi
