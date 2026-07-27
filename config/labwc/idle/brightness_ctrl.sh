#!/bin/bash

# Fade out/in screen brightness smoothly

# Get the current brightness of screen
IFS=, read -r _ _ _ value _ < <(brightnessctl -m)
current_val=${value%%%}

# --- Function to control screen brightness ---
fade_out_screen() {
    if [ "$current_val" -eq "0" ]; then
        # Overrides the previously saved brightness
        brightnessctl -s
        return 0
    else
        brightnessctl -sq set 0% >/dev/null 2>&1 &
    fi
}

fade_in_screen() {
    brightnessctl -r >/dev/null 2>&1 &
}

case $1 in
"--fade-out")
    fade_out_screen
    ;;
"--fade-in")
    fade_in_screen
    ;;
*)
    echo "Usage: $0 --fade-out or --fade-in"
    exit 0
    ;;
esac
