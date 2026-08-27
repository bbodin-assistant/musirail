# Musirail

[![CI](https://github.com/bbodin/musirail/actions/workflows/ci.yml/badge.svg)](https://github.com/bbodin/musirail/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Musirail is an open-source rhythm game and touch-first track editor built with
Godot 4.7.1. It supports taps, holds, directional flicks, timed slides,
multi-touch play, scoring, calibration, local track creation, and portable
track sharing.

Downloadable Android APKs are available from the repository's
[Releases](https://github.com/bbodin/musirail/releases). Development builds are
also attached to successful CI runs as temporary artifacts.

## Music and user data

Musirail ships no commercial songs. On first launch, it creates its
app-managed `user://songs` directory and installs one short original CC0 demo,
`First Light`. The directory is separate from the APK and is removed when the
app is uninstalled. If the user deletes the demo, it stays deleted.

Every song is an ordinary subdirectory:

```text
user://songs/<song-id>/
├── metadata.json
├── chart.json
├── audio.ogg, audio.mp3, or audio.wav
├── cover.png, cover.jpg, or cover.webp  (optional)
└── LICENSE.txt                          (optional)
```

The library is rescanned from these files, so there is no built-in song
catalog. All songs—including the demo—can be copied, edited, shared, or
deleted. Android import and export use the system file picker.

A shared `.musirail` file is a ZIP-compatible archive containing the song's
metadata, chart, audio, cover, and optional license. See
[the song format](docs/SONG_FORMAT.md) for the schema and security rules.

Only import or share music and artwork that you are legally allowed to use.
User-provided songs are not licensed by or distributed with Musirail.

## Development

Requirements:

- Godot `4.7.1` with matching export templates
- Python 3.12+ for the optional chart generator and tests
- Android SDK/JDK configuration supported by Godot for APK exports

Open `project.godot` in Godot, or use the portable Make targets:

```bash
make check-public
make check-godot GODOT=/path/to/godot
make export-android-debug GODOT=/path/to/godot
```

For local Android development, `make launch` exports and installs the debug
APK, copies only the ignored `songs/song_*` workspaces to
`/sdcard/Download/Musirail`, and starts the app. These audio and cover files
are then available through Android's native file picker without being bundled
in the APK. Use `DEVICE=<adb-serial>`, `PRIVATE_SONGS_DIR=<host-directory>`, or
`DEVICE_SONGS_DIR=<android-directory>` to override the defaults.

The advanced offline chart generator has additional dependencies:

```bash
python -m venv .venv
.venv/bin/pip install -r songs/tools/utils/requirements.txt
PYTHONPATH=songs/tools .venv/bin/python -m unittest discover -s songs/tools/tests
.venv/bin/python songs/tools/ogg2json.py /path/to/song-directory
```

Rebuild the deterministic CC0 demo seed package with:

```bash
make demo-song PYTHON=.venv/bin/python
```

## Automated APKs

`.github/workflows/ci.yml` runs tests and creates a debug APK for pushes and
pull requests. `.github/workflows/release.yml` creates an attested, signed APK
and attaches it to a GitHub Release for tags such as `v0.1.0` once the signing
secrets are configured. See [the release guide](docs/RELEASING.md).

## Contributing and security

Contributions are welcome; read [CONTRIBUTING.md](CONTRIBUTING.md) first.
Please report vulnerabilities according to [SECURITY.md](SECURITY.md).

The source code is MIT-licensed. The demo song is CC0. Detailed asset and
engine notices are in [ASSET_LICENSES.md](ASSET_LICENSES.md) and
[THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).
