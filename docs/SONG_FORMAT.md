# Musirail song format

## Installed directory

Musirail scans each immediate subdirectory of `user://songs`. A playable song
must contain valid `metadata.json`, `chart.json`, and audio files. Paths in
metadata must be plain filenames; absolute paths and nested paths are rejected.

Example metadata:

```json
{
  "title": "Example Track",
  "artist": "Example Artist",
  "audio": "audio.ogg",
  "chart": "chart.json",
  "cover": "cover.png",
  "license": "CC-BY-4.0",
  "license_url": "https://creativecommons.org/licenses/by/4.0/"
}
```

Supported audio extensions are OGG, MP3, and WAV. Supported covers are PNG,
JPG/JPEG, and WEBP. A cover and license file are optional.

Charts currently use schema version 4 and store one or more difficulty maps.
The in-app recorder creates compatible charts. The offline generator under
`songs/tools/` can create Easy, Normal, and Hard charts from an audio file.

## Shared package

Package version 2 uses the `.musirail` extension and contains only flat files:

```text
manifest.json
metadata.json
chart.json
audio.<supported extension>
cover.<supported extension>  (optional)
LICENSE.txt                  (optional)
```

Example manifest:

```json
{
  "format": "musirail-track",
  "version": 2,
  "metadata": "metadata.json",
  "chart": "chart.json",
  "audio": {"kind": "bundled", "file": "audio.ogg"},
  "cover": {"kind": "bundled", "file": "cover.png"},
  "license": "LICENSE.txt"
}
```

Exports include the real metadata, chart, audio, cover, and optional license;
they never reference files embedded in the application. Imports also accept
legacy package version 1 created by earlier Musirail builds.

For safety, imports reject directory traversal, unsupported extensions,
unknown chart versions, empty difficulty maps, and packages larger than the
configured 300 MiB limit.
