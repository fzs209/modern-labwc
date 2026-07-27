#!/bin/bash

waybar_config_dir="$HOME/.config/waybar"
style_file="$waybar_config_dir/style.css"
modernz_conf="$HOME/.config/mpv/script-opts/modernz.conf"

# --- COLOR EXTRACTION LOGIC ---

# Default Fallbacks
bg_color="#121318"
fg_color="#e3e1e9"
primary_color="#b7c4ff"

# Find the active color file from style.css
imported_file=$(sed -n 's/.*@import "colors\/\(.*\)";.*/\1/p' "$style_file" | head -n 1)

if [ -n "$imported_file" ]; then
    full_color_path="$waybar_config_dir/colors/$imported_file"
    if [ -f "$full_color_path" ]; then
        extracted_bg_color=$(grep "@define-color bar_bg" "$full_color_path" | awk '{print $3}' | tr -d ';')
        extracted_fg_color=$(grep "@define-color bar_fg" "$full_color_path" | awk '{print $3}' | tr -d ';')
        extracted_icon_color=$(grep "@define-color primary" "$full_color_path" | awk '{print $3}' | tr -d ';')
        if [ -n "$extracted_bg_color" ]; then bg_color="$extracted_bg_color"; fi
        if [ -n "$extracted_fg_color" ]; then fg_color="$extracted_fg_color"; fi
        if [ -n "$extracted_icon_color" ]; then primary_color="$extracted_icon_color"; fi
    fi
else
    notify-send "Warning failed to extract colors using fallback!"
fi

# function to darker the hex
shade_hex() {
    local hex="${1#"#"}"
    local adjust="${2:-10}"

    # Extract RGB
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    local sign="${adjust:0:1}"
    local percent

    if [[ "$sign" == "+" || "$sign" == "-" ]]; then
        percent="${adjust:1}"
    else
        sign="+"
        percent="$adjust"
    fi

    if [[ "$sign" == "+" ]]; then
        # Darker
        r=$((r - (r * percent / 100)))
        g=$((g - (g * percent / 100)))
        b=$((b - (b * percent / 100)))
    else
        # Lighter
        r=$((r + ((255 - r) * percent / 100)))
        g=$((g + ((255 - g) * percent / 100)))
        b=$((b + ((255 - b) * percent / 100)))
    fi

    # Clamp
    ((r < 0)) && r=0
    ((r > 255)) && r=255
    ((g < 0)) && g=0
    ((g > 255)) && g=255
    ((b < 0)) && b=0
    ((b > 255)) && b=255

    printf "#%02x%02x%02x\n" "$r" "$g" "$b"
}

dark_primary1=$(shade_hex "$primary_color" +10)
light_primary1=$(shade_hex "$primary_color" -15)
light_primary2=$(shade_hex "$primary_color" -10)

if [ -f "$modernz_conf" ]; then
    sed -i \
        -e "s/^\s*osc_color\s*=.*/osc_color=${bg_color}/" \
        -e "s/^\s*menu_bg_color\s*=.*/menu_bg_color=${bg_color}/" \
        -e "s/^\s*menu_fg_color\s*=.*/menu_fg_color=${fg_color}/" \
        -e "s/^\s*menu_sel_color\s*=.*/menu_sel_color=${primary_color}/" \
        -e "s/^\s*menu_sel_bg_color\s*=.*/menu_sel_bg_color=${light_primary1}/" \
        -e "s/^\s*menu_sel_fg_color\s*=.*/menu_sel_fg_color=${bg_color}/" \
        -e "s/^\s*tooltip_text_color\s*=.*/tooltip_text_color=${fg_color}/" \
        -e "s/^\s*seekbarfg_color\s*=.*/seekbarfg_color=${primary_color}/" \
        -e "s/^\s*seekbarbg_color\s*=.*/seekbarbg_color=${light_primary1}/" \
        -e "s/^\s*seekbar_cache_color\s*=.*/seekbar_cache_color=${light_primary2}/" \
        -e "s/^\s*time_color\s*=.*/time_color=${fg_color}/" \
        -e "s/^\s*thumbnail_border_color\s*=.*/thumbnail_border_color=${dark_primary1}/" \
        -e "s/^\s*thumbnail_border_outline\s*=.*/thumbnail_border_outline=${dark_primary1}/" \
        -e "s/^\s*playpause_color\s*=.*/playpause_color=${fg_color}/" \
        -e "s/^\s*middle_buttons_color\s*=.*/middle_buttons_color=${fg_color}/" \
        -e "s/^\s*side_buttons_color\s*=.*/side_buttons_color=${fg_color}/" \
        -e "s/^\s*hover_effect_color\s*=.*/hover_effect_color=${primary_color}/" \
        "$modernz_conf"
else
    echo "File not found! $modernz_conf"
fi
