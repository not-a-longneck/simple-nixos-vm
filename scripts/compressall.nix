{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    ffmpeg
    bc
    imagemagick
    chafa
    trash-cli

    (pkgs.writeShellScriptBin "compressall" ''
      #!/bin/bash
      echo "Compress all script (Safe Trash & Stats Edition) 08/01-26"

      start_time=$(date +%s)
      current_folder_name=$(basename "''$PWD")
      old_files_dir="OLD - ''${current_folder_name}"

      # Find video and image files (removed exclusions so we can log skipped files accurately)
      mapfile -d "" video_files < <(find . -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.3gp" -o -iname "*.webm" -o -iname "*.flv" -o -iname "*.wmv" -o -iname "*.m4v" -o -iname "*.mpeg" -o -iname "*.mpg" -o -iname "*.divx" \) -print0)
      mapfile -d "" image_files < <(find . -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)

      files=("''${video_files[@]}" "''${image_files[@]}")
      total_files=''${#files[@]}
      
      if [ ''$total_files -eq 0 ]; then
        echo "No video or image files found."
        exit 1
      fi

      # Create the OLD folder immediately
      mkdir -p "''$old_files_dir"

      # Stat tracking variables
      current_file=0
      success_count=0
      skipped_count=0
      uncompressible_count=0
      total_bytes_saved=0
      file_status_log=()

      echo "Found ''${#video_files[@]} video(s) and ''${#image_files[@]} image(s)."

      show_progress_bar() {
        local duration=''$1
        local elapsed=''$2
        local progress=$((100 * elapsed / duration))
        local bar_width=50
        local filled=$((bar_width * progress / 100))
        local empty=$((bar_width - filled))
        printf "\r["
        [ ''$filled -gt 0 ] && printf "%0.s=" $(seq 1 ''$filled)
        [ ''$empty -gt 0 ] && printf "%0.s " $(seq 1 ''$empty)
        printf "] %3d%%" ''$progress
      }

      for input in "''${files[@]}"; do
        input_basename="''${input##*/}"
        basename_lower=$(echo "''$input_basename" | tr '[:upper:]' '[:lower:]')

        if [[ "''$basename_lower" == *"compressed"* ]] || [[ "''$basename_lower" == *"smaller"* ]] || [[ "''$basename_lower" == *"cannotcompress"* ]]; then
          echo "✓ Skipping: ''$input_basename"
          ((skipped_count++))
          file_status_log+=("➖ SKIPPED: ''$input_basename")
          continue
        fi

        ((current_file++))
        echo -e "\nProcessing file ''$current_file of ''$total_files: ''$input_basename"

        input_size=$(stat -c%s "''$input" 2>/dev/null || stat -f%z "''$input")
        extension="''${input##*.}"
        extension_lower=$(echo "''$extension" | tr '[:upper:]' '[:lower:]')

        # --- Video Processing ---
        if [[ "''$extension_lower" =~ ^(mp4|mov|avi|mkv|3gp|webm|flv|wmv|m4v|mpeg|mpg|divx)$ ]]; then
          duration=$(ffprobe -i "''$input" -show_entries format=duration -v quiet -of csv="p=0" 2>/dev/null | awk '{print int($1)}')
          [ -z "''$duration" ] || [ "''$duration" -eq 0 ] && duration=1
          
          if command -v chafa &> /dev/null; then
            thumbnail_time=$(echo "if (''$duration * 0.1 < 5) ''$duration * 0.1 else 5" | bc)
            ffmpeg -i "''$input" -ss "''$thumbnail_time" -vframes 1 -f image2pipe -vcodec png - 2>/dev/null | chafa --size 60x30 -
          fi

          output_file="''${input%.*}-smaller-crf28.mp4"
          ffmpeg -i "''$input" -vcodec libx265 -crf 28 "''$output_file" -progress pipe:1 2>&1 | while IFS= read -r line; do
            if [[ "''$line" == "out_time_ms="* ]]; then
              elapsed=$(echo "''$line" | cut -d= -f2 | awk '{print int( $1 / 1000000 )}' 2>/dev/null || echo 0)
              show_progress_bar ''$duration ''$elapsed
            fi
          done
          echo ""

        # --- Image Processing ---
        elif [[ "''$extension_lower" =~ ^(jpg|jpeg|png)$ ]]; then
          output_file="''${input%.*}-smaller.''${extension}"
          [ -x "$(command -v chafa)" ] && chafa --size 60x30 "''$input"
          convert "''$input" -resize '1080x1080>' -quality 85 -strip "''$output_file" 2>&1
        fi

        # --- Post-Compression Logic ---
        if [ -f "''$output_file" ] && [ -s "''$output_file" ]; then
          output_size=$(stat -c%s "''$output_file" 2>/dev/null || stat -f%z "''$output_file")
          if [ ''$output_size -ge ''$input_size ]; then
            rm "''$output_file"
            mv "''$input" "''${input%.*}-cannotcompress.''${extension}"
            ((uncompressible_count++))
            file_status_log+=("❌ UNCOMPRESSIBLE: ''$input_basename")
          else
            mv "''$input" "''$old_files_dir/"
            bytes_saved=$((input_size - output_size))
            total_bytes_saved=$((total_bytes_saved + bytes_saved))
            saved_mb=$(echo "scale=2; ''$bytes_saved / 1048576" | bc)
            ((success_count++))
            file_status_log+=("✅ COMPRESSED: ''$input_basename (Saved ''$saved_mb MB)")
            echo -e "\n✅ SUCCESS: Original moved to ''$old_files_dir"
          fi
        fi
      done

      # Final Trash Action
      if [ -d "''$old_files_dir" ] && [ "$(ls -A "''$old_files_dir" 2>/dev/null)" ]; then
        echo -e "\nCleaning up... moving ''$old_files_dir to Trash 🗑️"
        trash-put "''$old_files_dir"
      else
        rmdir "''$old_files_dir" 2>/dev/null # Remove if empty
      fi

      # Rename parent folder logic
      parent_dir=$(dirname "''$PWD")
      if [[ ! "''$current_folder_name" =~ \ -\ COMP$ ]]; then
        new_dir_name="''${current_folder_name} - COMP"
        cd "''$parent_dir" && mv "''$current_folder_name" "''$new_dir_name" 2>/dev/null && echo "Folder renamed to ''$new_dir_name"
      fi

      # Calculate Time Taken
      end_time=$(date +%s)
      elapsed_time=$((end_time - start_time))
      h=$(( elapsed_time / 3600 ))
      m=$(( (elapsed_time % 3600) / 60 ))
      s=$(( elapsed_time % 60 ))
      formatted_time=$(printf "%02d:%02d:%02d" ''$h ''$m ''$s)

      # Calculate Total MB Saved
      total_saved_mb=$(echo "scale=2; ''$total_bytes_saved / 1048576" | bc)

      # Print Stats
      echo -e "\n=================================================="
      echo "📊 COMPRESSION SUMMARY REPORT"
      echo "=================================================="
      echo "⏱️  Time taken:                 ''$formatted_time"
      echo "📁 Total files found:          ''$total_files"
      echo "➖ Skipped (already compressed): ''$skipped_count"
      echo "❌ Uncompressible (kept orig):   ''$uncompressible_count"
      echo "✅ Successfully compressed:      ''$success_count"
      echo "--------------------------------------------------"
      echo "💾 TOTAL SPACE SAVED:          ''$total_saved_mb MB"
      echo "=================================================="
      echo "📝 FILE LOG:"
      for log_entry in "''${file_status_log[@]}"; do
        echo "  ''$log_entry"
      done
      echo "=================================================="
    '')
  ];
}
