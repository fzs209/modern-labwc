#!/bin/bash

#####################################
## author @Harsh-bin Github #########
#####################################

# Configuration
#wall_dir="/usr/share/backgrounds/images"
#thumb_dir="$HOME/.cache/wallselect/thumbnails"
notify_id="string:x-canonical-private-synchronous:wallselect"

mkdir -p "$thumb_dir"
wall_list="$thumb_dir/wall_list.txt"

# Ensure clean state for the list
> "$wall_list"

# Enable nullglob: loops won't run if no files match
shopt -s nullglob

#####################################################
# cleanup of orphan thumbnails in thumb_dir folder ##
#####################################################
for thumb_file in "$thumb_dir"/*; do
    # Skip our temporary list file so it doesn't get deleted
    [[ "$thumb_file" == "$wall_list" ]] && continue

    filename="${thumb_file##*/}"
    source_file="$wall_dir/$filename"

    if [[ ! -e "$source_file" ]]; then
        echo "Deleting orphan: $filename"
        rm -f "$thumb_file"
    fi
done

###################################################
# Create a list of files that need processing #####
###################################################
files_to_process_vid=()
total_found=0

for file in "$wall_dir"/*; do
    # Skip directories
    [[ -d "$file" ]] && continue

    filename="${file##*/}"
    ext="${filename##*.}"
    output="$thumb_dir/$filename"

    # Case-insensitive extension check
    case "${ext,,}" in
    jpg | jpeg | png | webp | gif) 
        # If output doesn't exist or source is newer, add to list
        if [[ ! -e "$output" ]] || [[ "$file" -nt "$output" ]]; then
            # Appending [0] so ImageMagick grabs only the first frame of GIFs
            echo "${file}[0]" >> "$wall_list"
            ((total_found++))
            
            # Show live update (Throttled slightly to avoid D-Bus/Notification spam)
            if (( total_found % 3 == 1 )); then
                notify-send -h "$notify_id" -t 2000 "Scanning Wallpapers" "Generating list... Found: $total_found"
            fi
            printf "\r\033[KGenerating wallpaper list... Found: %d" "$total_found"
        fi
        ;;
    mkv | mp4 | webm)
        # Separating video logic for mpvpaper future use
        if [[ ! -e "$output" ]] || [[ "$file" -nt "$output" ]]; then
            files_to_process_vid+=("$file")
            ((total_found++))
            
            if (( total_found % 3 == 1 )); then
                notify-send -h "$notify_id" -t 2000 "Scanning Wallpapers" "Generating list... Found: $total_found"
            fi
            printf "\r\033[KGenerating wallpaper list... Found: %d" "$total_found"
        fi
        ;;
    *) continue ;; # Skip invalid extensions
    esac
done

# Print a newline to move off the gathering progress line
(( total_found > 0 )) && echo

#####################################
# Thumbnails generation #############
#####################################
img_count=0
[[ -f "$wall_list" ]] && img_count=$(wc -l < "$wall_list")
vid_count=${#files_to_process_vid[@]}
total_to_process=$((img_count + vid_count))

if ((total_to_process > 0)); then

    # Process Images
    if (( img_count > 0 )); then
        processed_count=0
        notify-send -h "$notify_id" -t 3000 "Thumbnails" "Processing $img_count images..."
        
        # Read from ImageMagick's verbose output using process substitution
        while read -r line; do
            # Mogrify's verbose mode outputs 2 lines per image (read & write).
            # We ONLY count the line containing the destination directory ($thumb_dir)
            if [[ "$line" == *"=>"* && "$line" == *"$thumb_dir"* ]]; then
                ((processed_count++))
                pct=$(( processed_count * 100 / img_count ))
                
                # Extract the base filename for display from the IM output string
                raw_path="${line%%=>*}"
                fname="${raw_path##*/}"
                fname="${fname%\[0\]}" # Strip out the [0] suffix
                
                # The -h "int:value:$pct" trigger generates progress bar
                notify-send -h "$notify_id" -h "int:value:$pct" -t 3000 \
                    "Generating Thumbnails: [${processed_count}/${img_count}]" \
                    "Processing: ${fname}"
                    
                printf "\r\033[K[%d/%d] Generating Thumbnails: %s (%d%%)" "$processed_count" "$img_count" "$fname" "$pct"
            fi
        done < <(magick mogrify -verbose -path "$thumb_dir" -thumbnail '256x>' -quality 80 @"$wall_list" 2>&1)
        
        echo # New line
        
        # Sync timestamps so -nt works next time without generating them again
        while read -r line; do
            src="${line%\[0\]}" # Remove [0] to get exact source path
            filename="${src##*/}"
            output="$thumb_dir/$filename"
            [[ -e "$src" && -e "$output" ]] && touch -r "$src" "$output"
        done < "$wall_list"
    fi

    # Process Videos
    if (( vid_count > 0 )); then
        max_jobs=8
        active_jobs=0
        vid_processed=0
        
        for file in "${files_to_process_vid[@]}"; do
            filename="${file##*/}"
            output="$thumb_dir/$filename"

            ((vid_processed++))
            pct=$(( vid_processed * 100 / vid_count ))
            
            notify-send -h "$notify_id" -h "int:value:$pct" -t 3000 \
                "Generating Video Thumbs: [${vid_processed}/${vid_count}]" \
                "Processing: ${filename}"
            printf "\r\033[K[%d/%d] Generating Video Thumbs: %s (%d%%)" "$vid_processed" "$vid_count" "$filename" "$pct"

            (
                ffmpegthumbnailer -i "$file" -o "$output" -s 256 2>/dev/null
                touch -r "$file" "$output"
            ) &

            ((active_jobs++))
            if ((active_jobs >= max_jobs)); then
                wait -n # Wait for the next available slot
                ((active_jobs--))
            fi
        done
        wait
        echo # New line
    fi
fi

# Cleanup
rm -f "$wall_list"

echo "Syncing complete...."