#!/bin/bash

#####################################
## author @Harsh-bin Github #########
#####################################

# configuration
icon_dir="$HOME/.config/dunst/brightness-icon"

# Using same notification id as in volume_ctrl script
notify_id="string:x-canonical-private-synchronous:volume"

# check for dependencies
if ! command -v brightnessctl >/dev/null 2>&1; then
    echo "Install brightnessctl"
    exit 0
fi

# default to +5 if empty
input_arg=${1:-+5}

# Use a case statement to validate and extract in one go
case "$input_arg" in
+*)
    sign="+"
    step="${input_arg#+}"
    ;;
-*)
    sign="-"
    step="${input_arg#-}"
    ;;
*)
    echo "   $(basename "$0") +5   (Increase brightness by 5%)"
    echo "   $(basename "$0") -10  (Decrease brightness by 10%)"
    exit 1
    ;;
esac

# Validate that 'step' is actually a number
if ! [[ "$step" =~ ^[0-9]+$ ]]; then
    echo "Error: Step must be a number"
    exit 1
fi

brightnessctl set "${step}%${sign}" -q

# Get the current brightness of screen
IFS=, read -r _ _ _ value _ < <(brightnessctl -m)
brightness=${value%%%}

# Ensures 0% = level 1 and 100% = level 20
lvl=$(((brightness * 19 / 100) + 1))

# Safety check for the index
if [ "$lvl" -lt 1 ]; then lvl=1; fi
if [ "$lvl" -gt 20 ]; then lvl=20; fi

icon="$icon_dir/brightness_lvl_${lvl}.png"
text="Brightness: ${brightness}%"

# Send notification
notify-send -t 1500 -h $notify_id -u low -i "$icon" "$text" -h int:value:"$brightness"
