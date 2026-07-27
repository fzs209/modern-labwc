#!/bin/bash

# Pause all media players before sleep
playerctl --all-players pause &
# Lock and sleep after pausing all players
# Don't use sleep command here swaylidle will handle sleeping...

# Lock the session
"$HOME/.config/labwc/idle/lock_ctrl.sh" &

# Get the current brightness of screen
IFS=, read -r _ _ _ value _ < <(brightnessctl -m)
current_val=${value%%%}

if [[ "$current_val" -ge 0 ]] && ! pgrep -x "hyprlock" >/dev/null; then
   "$HOME/.config/labwc/idle/brightness_ctrl.sh" --fade-out &
elif [[ "$current_val" -gt 0 ]] && pgrep -x "hyprlock" >/dev/null; then
   "$HOME/.config/labwc/idle/brightness_ctrl.sh" --fade-out &
fi
exit 0
