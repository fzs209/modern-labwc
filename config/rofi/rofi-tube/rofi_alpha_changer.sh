#!/bin/bash

src_config="$HOME/.config/rofi/shared/colors.rasi"
colors_dir="$HOME/.config/rofi/colors"
dest_dir="$HOME/.config/rofi/rofi-tube/colors"
playlist_file="$HOME/.config/rofi/rofi-tube/playlist-window.rasi"

declare -A alpha_map=(
	["background"]="0.75"
	["background-alt"]="0.60"
	["foreground"]="1.0"
	["selected"]="0.85"
	["hover"]="0.20"
	["active"]="1.0"
	["urgent"]="1.0"
)

# Extract current color filename from shared config
color_file=$(sed -nE 's|.*colors/([^"]+).*|\1|p' "$src_config")
src_file="$colors_dir/$color_file"
dest_file="$dest_dir/$color_file"
# Copy the color file
cp "$src_file" "$dest_file"

# Update alpha values
for key in "${!alpha_map[@]}"; do
	new_alpha="${alpha_map[$key]}"
	sed -i -E "s|^([[:space:]]*$key:[[:space:]]*rgba[[:space:]]*\([^,]+,[^,]+,[^,]+,[[:space:]]*)[0-9.]+[[:space:]]*%?([[:space:]]*\).*)|\1$new_alpha\2|" "$dest_file"
done

# Update playlist-window.rasi to import the new color file
sed -i -E \
	"s|^@import[[:space:]]+\"~/.config/rofi/rofi-tube/colors/.*\"|@import                          \"~/.config/rofi/rofi-tube/colors/$color_file\"|" \
	"$playlist_file"

echo "Success! Copied, updated alpha values, and set playlist-window to use '$color_file'"
