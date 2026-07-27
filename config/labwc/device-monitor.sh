#!/bin/bash

AUDIO_FILE="$HOME/.config/labwc/sound/device-added.wav"

echo "Starting hardware monitor... (Press Ctrl+C to stop)"

while read -r line; do
    # Check if the line contains a 'UDEV' character.
    # Actual events look like: UDEV  [350.433478] remove   /devices/...
    # New: Check if line contains '/backlight/' and stops playing sound
    if [[ "$line" == "UDEV"* ]] && [[ "$line" != *"/backlight/"* ]]; then
        # wait 0.5s to absorb rapid-fire signals and prevents playing sound multiple times
        while read -t 0.5 -r _; do :; done
        # Play sound
        aplay "$AUDIO_FILE" 2>/dev/null
    fi
done < <(udevadm monitor) # Use process substitution to read udevadm output without spawning a second bash process