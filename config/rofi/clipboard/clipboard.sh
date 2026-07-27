#!/bin/bash

#####################################
## author @Harsh-bin Github #########
#####################################

# Configuration
config_dir="$HOME/.config/rofi/clipboard"
clip_theme="$config_dir/clipboard.rasi"
clip_img_theme="$config_dir/clipboard_img.rasi"
confirm_theme="$config_dir/confirmation.rasi"
# Database files
text_db="$config_dir/text.db"
img_db="$config_dir/image.db"

# Functions
image_history() {
  img_choice=$(${config_dir}/cliphist_rofi_img | rofi -dmenu -theme "$clip_img_theme")
  if [[ -n "$img_choice" ]]; then
    tmp_img="/tmp/clipboard.png"
    echo "$img_choice" | cliphist -db-path "$img_db" decode >"$tmp_img"

    options="Copy Image\nOpen Image\nExport"
    choice=$(echo -e "$options" | rofi -dmenu \
      -mesg $'<big><b>Clipboard</b></big>\nWhat would you like to do?' \
      -theme "$confirm_theme")

    case "$choice" in
    "Copy Image")
      wl-copy <"$tmp_img"
      notify-send "Clipboard Manager" "Image copied to clipboard" --icon="$tmp_img"
      sleep 1
      rm "$tmp_img"
      ;;
    "Open Image")
      # Extract background color for feh window
      labwc_theme="$HOME/.config/labwc/themerc-override"
      bg_color=$(awk '/^window.active.title.bg.color:/ {print $2}' "$labwc_theme")
      # Open the image
      if command -v feh >/dev/null 2>&1; then
        feh --image-bg "${bg_color:-#000000}" --scale-down "$tmp_img"
      else
        xdg-open "$tmp_img"
      fi
      sleep 1
      rm "$tmp_img"
      ;;
    "Export")
      export_dir="$HOME/Pictures/clipboard"
      mkdir -p "$export_dir"
      file_path="$export_dir/$(date +%s).png"
      mv "$tmp_img" "$file_path"
      notify-send "Clipboard Manager" "Image Exported\nPath: ${file_path/$HOME/\~}" --icon="$file_path"
      ;;
    *)
      notify-send "Clipboard Manager" "canceled"
      rm "$tmp_img"
      ;;
    esac
  fi
}

wipe_clipboard() {
  options="Everything\nAll Text\nAll Images"
  # Show the menu
  choice=$(echo -e "$options" | rofi -dmenu \
    -mesg $'<big><b>Wipe Clipboard</b></big>\nWhat would you like to clear?' \
    -theme "$confirm_theme")

  case "$choice" in
  "Everything")
    cliphist -db-path "$text_db" wipe
    cliphist -db-path "$img_db" wipe
    wl-copy -c
    notify-send "Clipboard Manager" "Full clipboard history wiped"
    ;;
  "All Text")
    cliphist -db-path "$text_db" wipe
    notify-send "Clipboard Manager" "All text entries deleted"
    ;;
  "All Images")
    cliphist -db-path "$img_db" wipe
    notify-send "Clipboard Manager" "All image entries deleted"
    ;;
  *)
    notify-send "Clipboard Manager" "Wipe canceled"
    ;;
  esac
}

delete_images() {
  # Opens the same cliphist_rofi_img list but with multi-select enabled
  img_selections=$(${config_dir}/cliphist_rofi_img | rofi -dmenu -multi-select \
    -theme-str 'element-text { enabled: true; font: "sans 10"; padding: 5px; }' \
    -theme "$clip_img_theme")

  if [[ -n "$img_selections" ]]; then
    confirmation=$(echo -e "Yes\nNo" |
      rofi -dmenu \
        -mesg $'<big><b>Delete Images Confirmation</b></big>\nAre you sure you want to delete selected images?' \
        -theme "$confirm_theme")

    if [[ $confirmation == "Yes" ]]; then
      # Delete selected images from image database
      echo "$img_selections" | cliphist -db-path "$img_db" delete
      notify-send "Clipboard Manager" "Selected images deleted"
    else
      notify-send "Clipboard Manager" "Image deletion canceled"
    fi
  fi
}

delete_items() {
  # Run rofi with -multi-select and added "Delete Image History" option at the top
  selections=$(
    {
      printf '\t\uf03e  Delete Image History\n'
      cliphist -db-path "$text_db" list
    } | rofi -dmenu -multi-select -display-columns 2 \
      -theme-str 'entry{placeholder: " Search\t[Shift + Enter for multiple selection]";}' \
      -theme "$clip_theme"
  )

  # If nothing else was selected, exit the function
  if [[ -z "$selections" ]]; then
    return
  fi

  if [[ -n "$selections" ]]; then
    # Check if "Delete Image History" was one of the selected items
    if [[ "$selections" == *"Delete Image History"* ]]; then
      selection_count=$(echo "$selections" | grep -c .)
      if [[ "$selection_count" -eq 1 ]]; then
        # Only one item selected and it is the delete option
        delete_images
        return
      else
        # Multiple items selected; remove "Delete Image History"
        selections=$(echo "$selections" | grep -v "Delete Image History")
      fi
    fi

    # Process standard text/clipboard items
    confirmation=$(echo -e "Yes\nNo" |
      rofi -dmenu \
        -mesg $'<big><b>Delete Items Confirmation</b></big>\nAre you sure you want to delete selected items?' \
        -theme "$confirm_theme")

    if [[ $confirmation == "Yes" ]]; then
      # Delete selected items
      echo "$selections" | cliphist -db-path "$text_db" delete
      notify-send "Clipboard Manager" "Selected items deleted"
    else
      notify-send "Clipboard Manager" "Deletion canceled"
    fi
  fi
}

handle_text_selection() {
  local selection="$1"
  cliphist -db-path "$text_db" decode "$selection" | wl-copy
  wtype -M ctrl -M shift -P v -s 500 -p v -m shift -m ctrl
  notify-send "Clipboard Manager" "Text copied to clipboard"
}

# Generates clipboard main menu
clipboard=$(
  {
    printf '\t\uf03e  Image History\n'
    printf '\t\uf2ed  Batch Delete\n'
    printf '\t\uf1f8  Wipe Clipboard\n'
    cliphist -db-path "$text_db" list
  } | rofi -dmenu -display-columns 2 -theme "$clip_theme"
)

# Handle Selection
if [[ $clipboard == *"Image History"* ]]; then
  image_history
  exit
elif [[ $clipboard == *"Batch Delete"* ]]; then
  delete_items
  exit
elif [[ $clipboard == *"Wipe Clipboard"* ]]; then
  wipe_clipboard
  exit
elif [[ -n $clipboard ]]; then
  handle_text_selection "$clipboard"
else
  exit
fi
