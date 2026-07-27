#!/bin/bash

# Config Paths
vertical_style_menu="$HOME/.config/rofi/vertical_style_menu.rasi"
color_scheme_changer="$HOME/.config/waybar/scripts/global_color_scheme_changer.sh"
waybar_customize="$HOME/.config/waybar/scripts/waybar_customize.sh"
launcher_customize="$HOME/.config/rofi/launchers/launcher_customize.sh"
powermenu_customize="$HOME/.config/rofi/powermenu/powermenu_style_changer.sh"
nowplaying_customize="$HOME/.config/rofi/nowplaying/nowplaying_style_changer.sh"
wallpaper_selector="$HOME/.config/rofi/wallselect/wallselect.sh"
menu_generator="$HOME/.config/labwc/menu-generator.sh"

# --- Define Menu Options ---
menu_options="Color_Scheme\nWallpaper\nWaybar\nLauncher\nPowermenu\nNowplaying\nGenerate Desktop Menu\nChange Titlebar Button Theme"

# --- Show the Rofi Menu ---
chosen_option=$(echo -e "$menu_options" | rofi -dmenu -mesg "<b>Customization</b>" -theme "vertical_style_menu" \
    -theme-str 'listview { lines: 8;}')

# --- Process the User's Choice ---
case "$chosen_option" in
"Color_Scheme")
    "$color_scheme_changer"
    ;;
"Wallpaper")
    "$wallpaper_selector"
    ;;
"Waybar")
    "$waybar_customize"
    ;;
"Launcher")
    "$launcher_customize"
    ;;
"Powermenu")
    "$powermenu_customize"
    ;;
"Nowplaying")
    "$nowplaying_customize"
    ;;
"Generate Desktop Menu")
    "$menu_generator"
    ;;
"Change Titlebar Button Theme")
    labwc_dir="$HOME/.config/labwc"
    labwc_rc_xml="$labwc_dir/rc.xml"
    titlebar_theme="$labwc_dir/titlebar_button.theme"
    system_theme="$labwc_dir/system.theme"

    # Check currently used window control theme
    current_theme=$(<"$titlebar_theme")

    # Check if we are using "theme_1" (matugen-labwc)
    if [ "$current_theme" != "matugen-labwc" ]; then
        # apply matugen-labwc theme
        sed -i "/<theme>/,/<\/theme>/ s|<name>.*</name>|<name>matugen-labwc</name>|" "$labwc_rc_xml"
        echo "matugen-labwc" >"$titlebar_theme"
    else
        # Choose labwc theme based on system theme
        if [[ $(<"$system_theme") == "dark" ]]; then
            sed -i "/<theme>/,/<\/theme>/ s|<name>.*</name>|<name>labwc-dark</name>|" "$labwc_rc_xml"
            echo "labwc-dark" >"$titlebar_theme"
        else
            sed -i "/<theme>/,/<\/theme>/ s|<name>.*</name>|<name>labwc-light</name>|" "$labwc_rc_xml"
            echo "labwc-light" >"$titlebar_theme"
        fi
    fi

    # Reload labwc
    pgrep -x labwc >/dev/null && labwc --reconfigure
    ;;
*)
    exit 0
    ;;
esac
