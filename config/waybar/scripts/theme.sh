#!/bin/bash

# This file will be sourced by other scripts to change system theme.

apply_theme() {
    # GTK settings file
    local gtk3_settings_file="$HOME/.config/gtk-3.0/settings.ini"
    local gtk4_settings_file="$HOME/.config/gtk-4.0/settings.ini"

    # labwc
    local labwc_dir="$HOME/.config/labwc"
    local labwc_rc_xml="$labwc_dir/rc.xml"
    local titlebar_theme="$labwc_dir/titlebar_button.theme"

    # Check current titlebar button theme
    if [[ -f "$titlebar_theme" ]] && [[ $(<"$titlebar_theme") != "matugen-labwc" ]]; then
        local labwc_theme_2=true
    fi

    # Track the current system theme
    # This file stores either "dark" or "light", which is used by other scripts to determine the current system theme.
    # This could be done by checking the GTK settings file, but that would require spawning "grep", which I'd rather avoid.
    # This is especially important for the nowplaying script, which needs to be very fast.
    local system_theme="$labwc_dir/system.theme"

    local wall_dir="$labwc_dir/wallpaper"
    local wall_cache=$(find "$wall_dir" -maxdepth 1 -type f -name "wallpaper.*")

    # Check if GTK3 settings file exists
    if [[ ! -f "$gtk3_settings_file" ]]; then
        echo "Error: $gtk3_settings_file not found."
        exit 1
    fi

    # Skip generating a new Matugen color scheme.
    # Used by wallselect.sh, which already generates the color scheme after selecting a wallpaper.
    local skip_matugen=false
    if [[ "$2" == "skip_matugen_generation" ]]; then
        local skip_matugen=true
    fi

    # Apply theme
    case "$1" in
    "light")
        # Switch to light theme
        sed -i 's/gtk-application-prefer-dark-theme=1/gtk-application-prefer-dark-theme=0/' "$gtk3_settings_file"
        sed -i 's/^gtk-icon-theme-name=.*/gtk-icon-theme-name=Papirus-Light/' "$gtk3_settings_file"
        sed -i 's/gtk-application-prefer-dark-theme=true/gtk-application-prefer-dark-theme=false/' "$gtk4_settings_file"
        # Generate colors from wallpaper if needed
        if [[ "$skip_matugen" != true ]]; then
            matugen image "$wall_cache" -m "light" --source-color-index 0
        fi
        sleep 0.2
        # Updates labwc theme if using theme 2
        if [[ "$labwc_theme_2" = true ]]; then
            sed -i "/<theme>/,/<\/theme>/ s|<name>.*</name>|<name>labwc-light</name>|" "$labwc_rc_xml"
        fi
        # Save system theme state to file
        echo "light" >"$system_theme"

        ;;
    "dark")
        # Switch to dark theme
        sed -i 's/gtk-application-prefer-dark-theme=0/gtk-application-prefer-dark-theme=1/' "$gtk3_settings_file"
        sed -i 's/^gtk-icon-theme-name=.*/gtk-icon-theme-name=Papirus-Dark/' "$gtk3_settings_file"
        sed -i 's/gtk-application-prefer-dark-theme=false/gtk-application-prefer-dark-theme=true/' "$gtk4_settings_file"
        # Generate colors from wallpaper if needed
        if [[ "$skip_matugen" != true ]]; then
            matugen image "$wall_cache" -m "dark" --source-color-index 0
        fi
        sleep 0.2
        # Updates labwc theme if using theme 2
        if [[ "$labwc_theme_2" = true ]]; then
            sed -i "/<theme>/,/<\/theme>/ s|<name>.*</name>|<name>labwc-dark</name>|" "$labwc_rc_xml"
        fi
        # Save system theme state to file
        echo "dark" >"$system_theme"
        ;;
    *)
        ;;
    esac

    # Update data monitor colors    
    python3 "$HOME/.config/waybar/scripts/data_monitor/data_monitor.py" --recolor
}
