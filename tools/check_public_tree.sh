#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

restricted_song_files="$(
  git ls-files 'songs/song_*' 'songs/catalog.json' |
    while IFS= read -r path; do
      if [[ -e "${path}" ]]; then
        printf '%s\n' "${path}"
      fi
    done
)"
if [[ -n "${restricted_song_files}" ]]; then
  echo "Commercial or built-in song files are tracked:" >&2
  echo "${restricted_song_files}" >&2
  exit 1
fi

signing_files="$(
  git ls-files '*.keystore' '*.jks' |
    while IFS= read -r path; do
      if [[ -e "${path}" ]]; then
        printf '%s\n' "${path}"
      fi
    done
)"
if [[ -n "${signing_files}" ]]; then
  echo "Android signing files must never be committed:" >&2
  echo "${signing_files}" >&2
  exit 1
fi

seed_package="assets/seed/first_light.musirail"
if [[ ! -f "${seed_package}" ]]; then
  echo "Missing CC0 demo seed package: ${seed_package}" >&2
  exit 1
fi
unzip -tqq "${seed_package}"

for required in manifest.json metadata.json chart.json audio.wav cover.png LICENSE.txt; do
  if ! unzip -Z1 "${seed_package}" | grep -Fxq "${required}"; then
    echo "Demo package is missing ${required}" >&2
    exit 1
  fi
done

echo "Public-tree checks passed."
