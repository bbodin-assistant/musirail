#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "${script_directory}/.." && pwd)"

adb_binary="${MUSIRAIL_ADB:-adb}"
device_serial="${MUSIRAIL_DEVICE:-}"
source_directory="${MUSIRAIL_PRIVATE_SONGS_DIR:-${project_directory}/songs}"
destination_directory="${MUSIRAIL_DEVICE_SONGS_DIR:-/sdcard/Download/Musirail}"

if [[ ! -d "${source_directory}" ]]; then
  echo "Private song directory does not exist: ${source_directory}" >&2
  exit 1
fi

adb_command=("${adb_binary}")
if [[ -n "${device_serial}" ]]; then
  adb_command+=(-s "${device_serial}")
fi

shopt -s nullglob
song_directories=("${source_directory}"/song_*)
shopt -u nullglob

private_song_count=0
for song_directory in "${song_directories[@]}"; do
  if [[ -d "${song_directory}" ]]; then
    private_song_count=$((private_song_count + 1))
  fi
done

if ((private_song_count == 0)); then
  echo "No private song_* directories found in ${source_directory}; skipping copy."
  exit 0
fi

"${adb_command[@]}" shell mkdir -p "${destination_directory}"

for song_directory in "${song_directories[@]}"; do
  if [[ ! -d "${song_directory}" ]]; then
    continue
  fi
  echo "Copying $(basename "${song_directory}") to ${destination_directory}"
  "${adb_command[@]}" push "${song_directory}" "${destination_directory}/"
done

echo "Copied ${private_song_count} private song directories to ${destination_directory}."
