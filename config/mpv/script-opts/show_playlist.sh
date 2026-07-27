#!/bin/sh

mpv_socket="/tmp/modern_labwc_mpv.sock"
rofi_tube_socket="/tmp/rofi_tube.sock"
rofi_tube_dir="$HOME/.config/rofi/rofi-tube"
choose_theme="$rofi_tube_dir/horizontal_menu.rasi"

hide_osc() {
    socket=$1
    if [ -S "$socket" ]; then
        echo '{ "command": ["script-message-to", "modernz", "osc-hide"] }' | socat - "$socket" >/dev/null 2>&1
    fi
}

show_osc_playlist() {
    socket=$1
    if [ -S "$socket" ]; then
        echo '{ "command": ["script-message-to", "modernz", "menu-toggle", "playlist" ] }' | socat - "$socket" >/dev/null 2>&1
    fi
}

# Check specifically if the rofi-tube instance of MPV is active
is_rofi_tube_active() {
    [ -S "$rofi_tube_socket" ] && pgrep -f "input-ipc-server=$rofi_tube_socket" >/dev/null 2>&1
}

# Matches mpv processes but EXCLUDES the one containing the rofi-tube socket
is_standard_mpv_active() {
    [ -S "$mpv_socket" ] && pgrep -a "mpv" | grep -v "$rofi_tube_socket" >/dev/null 2>&1
}

choose_playlist() {
    options=$(echo -e "Rofi Tube\nPlayer" | rofi -dmenu \
        -mesg $'<big><b>Playlist</b></big>\nWhich playlist would you like to see?' \
        -theme "$choose_theme")

    case "$options" in
    *"Tube")
        hide_osc "$mpv_socket"
        hide_osc "$rofi_tube_socket"
        "$rofi_tube_dir/rofi-tube.sh" --show-playlist
        ;;
    "Player")
        hide_osc "$mpv_socket"
        show_osc_playlist "$mpv_socket"
        ;;
    esac
}

# MAIN LOGIC
RT_ACTIVE=$(is_rofi_tube_active && echo "true" || echo "false")
STD_ACTIVE=$(is_standard_mpv_active && echo "true" || echo "false")

if [ "$RT_ACTIVE" = "true" ] && [ "$STD_ACTIVE" = "true" ]; then
    # Both are running: Let the user choose
    choose_playlist
elif [ "$RT_ACTIVE" = "true" ]; then
    # Only Rofi Tube is running
    hide_osc "$rofi_tube_socket"
    "$rofi_tube_dir/rofi-tube.sh" --show-playlist
elif [ "$STD_ACTIVE" = "true" ]; then
    # Only Standard Player is running
    hide_osc "$mpv_socket"
    show_osc_playlist "$mpv_socket"
else
    echo "No relevant mpv processes running."
fi
