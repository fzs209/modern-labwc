#!/bin/bash

# Configuration
emoji_dir="$HOME/.config/rofi/emoji-picker"
emoji_file="$emoji_dir/rofi_emoji_list.txt"
theme_file="$emoji_dir/emoji-picker.rasi"

# Emoji source (GitHub gemoji database)
emoji_url="https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json"

# Download emoji list if missing
if [ ! -f "$emoji_file" ]; then
    mkdir -p "$emoji_dir"
    notify-send "Emoji Picker" "Downloading emoji list..."
    curl -sL "$emoji_url" |
        jq -r '.[] | select(.emoji) | "\(.emoji) \(.description)"' \
            >"$emoji_file"

    [ -s "$emoji_file" ] || {
        echo "Error: Failed to download emoji list." >&2
        rm -f "$emoji_file"
        exit 1
    }
fi

# For highlighting "." as text is set to transparent in rasi file
colors_shared="$HOME/.config/rofi/shared/colors.rasi"
colors_dir="$HOME/.config/rofi/colors"
# RGB → HEX helper
rgb_to_hex() {
    printf "#%02X%02X%02X\n" "$1" "$2" "$3"
}
# Extract imported file name
color_file=$(grep -oP '@import\s+"~/.config/rofi/colors/\K[^"]+' "$colors_shared")
full_path="$colors_dir/$color_file"
# Extract RGB from foreground line
line=$(grep -m1 'foreground:' "$full_path")
rgb=${line#*rgba(}
rgb=${rgb%%)*}
IFS=',' read -r r g b _ <<<"$rgb"
# Convert and output HEX
foregroun_color=$(rgb_to_hex "$r" "$g" "$b")

# Show rofi menu with multi-select
selected=$(rofi -dmenu -multi-select \
    -markup-rows \
    -ballot-selected-str "<span foreground='$foregroun_color'>.</span>" \
    -ballot-unselected-str "" \
    -i -theme "$theme_file" \
    -input "$emoji_file")

# Exit if nothing selected
[ -z "$selected" ] && exit 0

# Extract emojis in selection order and concatenate without spaces
emoji_string=$(echo "$selected" | awk '{print $1}' | tr -d '\n')
# Copy to clipboard
wl-copy <<<"$emoji_string"
notify-send -t 2000 "Emoji Copied!" "$emoji_string"

# Update recent list (preserve selection order)
tmp_file=$(mktemp)

# Remove all selected lines from file
echo "$selected" | while read -r line; do
    grep -Fxv "$line" "$emoji_file" >"${tmp_file}_filtered"
    mv "${tmp_file}_filtered" "$emoji_file"
done

# Rebuild with selected emojis at top (in chosen order)
{
    echo "$selected"
    cat "$emoji_file"
} >"$tmp_file"

mv "$tmp_file" "$emoji_file"
rm -f "${tmp_file}_filtered"
