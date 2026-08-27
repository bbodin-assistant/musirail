extends Node

const USER_SONGS_DIRECTORY: String = "user://songs"
const USER_CATALOG_PATH: String = "user://songs/catalog.json"
const SEED_PACKAGE_PATH: String = "res://assets/seed/first_light.musirail"
const CATALOG_VERSION: int = 1
const CHART_VERSION: int = 4
const PACKAGE_VERSION: int = 2
const LEGACY_PACKAGE_VERSION: int = 1
const PACKAGE_MANIFEST: String = "manifest.json"
const PACKAGE_METADATA: String = "metadata.json"
const PACKAGE_CHART: String = "chart.json"
const PACKAGE_LICENSE: String = "LICENSE.txt"
const PACKAGE_TEMP_EXPORT: String = "user://shared_track.tmp"
const PACKAGE_TEMP_IMPORT: String = "user://imported_track.tmp"
const PACKAGE_MAX_BYTES: int = 300 * 1024 * 1024
const PACKAGE_DIFFICULTY_ORDER: Array[String] = [
	"easy",
	"normal",
	"hard",
	"expert",
	"master",
]

var last_package_error: String = ""
var last_delete_error: String = ""
var library_initialized: bool = false


func _ready() -> void:
	ensure_song_library()


func ensure_song_library() -> void:
	if library_initialized:
		return
	library_initialized = true
	var library_existed: bool = DirAccess.dir_exists_absolute(
		USER_SONGS_DIRECTORY
	)
	if not library_existed:
		var error: Error = DirAccess.make_dir_recursive_absolute(
			USER_SONGS_DIRECTORY
		)
		if error != OK:
			push_error("Unable to create the song library.")
			return
		var seeded_song: Dictionary = _install_song_package(SEED_PACKAGE_PATH)
		if seeded_song.is_empty():
			push_error("Unable to install the CC0 demo song: " + last_package_error)
	_rebuild_catalog()


func get_all_songs() -> Array[Dictionary]:
	ensure_song_library()
	return _rebuild_catalog()


func is_user_song(song: Dictionary) -> bool:
	return str(song.get("directory", "")).begins_with(
		USER_SONGS_DIRECTORY + "/"
	)


func delete_user_song(song: Dictionary) -> bool:
	last_delete_error = ""
	if not is_user_song(song):
		last_delete_error = "Only player-created tracks can be deleted."
		return false

	var song_directory: String = str(song.get("directory", ""))
	if song_directory.get_base_dir() != USER_SONGS_DIRECTORY:
		last_delete_error = "The track folder is outside the user song library."
		return false
	if not DirAccess.dir_exists_absolute(song_directory):
		last_delete_error = "The track is no longer in the user song list."
		return false
	if not _remove_flat_song_directory(song_directory):
		last_delete_error = (
			"The track was removed from the list, but some files remain."
		)
		return false
	_rebuild_catalog()
	return true


func export_song_package(song: Dictionary, destination: String) -> Error:
	last_package_error = ""
	if not is_user_song(song):
		return _package_failure(
			ERR_UNAUTHORIZED,
			"Only player-created tracks can be shared."
		)
	if destination.is_empty():
		return _package_failure(ERR_INVALID_PARAMETER, "No destination selected.")

	var chart_path: String = get_chart_path(song)
	var chart_bytes: PackedByteArray = _read_asset_bytes(chart_path)
	if chart_bytes.is_empty():
		return _package_failure(ERR_FILE_CANT_READ, "The chart cannot be read.")
	var metadata_path: String = _join_path(
		str(song.get("directory", "")),
		PACKAGE_METADATA
	)
	var metadata: Dictionary = _read_json_object(metadata_path)
	if metadata.is_empty():
		return _package_failure(ERR_FILE_CANT_READ, "The metadata cannot be read.")

	var packer: ZIPPacker = ZIPPacker.new()
	packer.compression_level = ZIPPacker.COMPRESSION_FAST
	var error: Error = packer.open(PACKAGE_TEMP_EXPORT)
	if error != OK:
		return _package_failure(error, "The track package cannot be created.")

	var audio_descriptor: Dictionary = _pack_song_asset(
		packer,
		get_audio_path(song),
		"audio"
	)
	if audio_descriptor.is_empty():
		packer.close()
		return _package_failure(ERR_FILE_CANT_READ, "The song audio cannot be shared.")

	var cover_descriptor: Dictionary = {}
	var cover_path: String = get_cover_path(song)
	if not cover_path.is_empty():
		cover_descriptor = _pack_song_asset(packer, cover_path, "cover")
		if cover_descriptor.is_empty():
			packer.close()
			return _package_failure(ERR_FILE_CANT_READ, "The cover cannot be shared.")

	error = _write_zip_entry(packer, PACKAGE_CHART, chart_bytes)
	if error != OK:
		packer.close()
		return _package_failure(error, "The chart cannot be added to the package.")
	error = _write_zip_entry(
		packer,
		PACKAGE_METADATA,
		(JSON.stringify(metadata, "  ") + "\n").to_utf8_buffer()
	)
	if error != OK:
		packer.close()
		return _package_failure(error, "The metadata cannot be added to the package.")

	var manifest: Dictionary = {
		"format": "musirail-track",
		"version": PACKAGE_VERSION,
		"metadata": PACKAGE_METADATA,
		"title": str(song.get("title", "Untitled Track")),
		"artist": str(song.get("artist", "")),
		"audio": audio_descriptor,
		"chart": PACKAGE_CHART,
		"difficulties": song.get("difficulties", []),
	}
	if not cover_descriptor.is_empty():
		manifest["cover"] = cover_descriptor
	var license_path: String = _join_path(
		str(song.get("directory", "")),
		PACKAGE_LICENSE
	)
	if FileAccess.file_exists(license_path):
		var license_bytes: PackedByteArray = _read_asset_bytes(license_path)
		if not license_bytes.is_empty():
			error = _write_zip_entry(packer, PACKAGE_LICENSE, license_bytes)
			if error != OK:
				packer.close()
				return _package_failure(
					error,
					"The song license cannot be added to the package."
				)
			manifest["license"] = PACKAGE_LICENSE
	error = _write_zip_entry(
		packer,
		PACKAGE_MANIFEST,
		(JSON.stringify(manifest, "  ") + "\n").to_utf8_buffer()
	)
	if error == OK:
		error = packer.close()
	else:
		packer.close()
	if error != OK:
		return _package_failure(error, "The track package cannot be finalized.")

	error = _copy_asset(PACKAGE_TEMP_EXPORT, destination)
	DirAccess.remove_absolute(PACKAGE_TEMP_EXPORT)
	if error != OK:
		return _package_failure(error, "The shared file cannot be saved.")
	return OK


func import_song_package(source: String) -> Dictionary:
	ensure_song_library()
	return _install_song_package(source)


func _install_song_package(source: String) -> Dictionary:
	last_package_error = ""
	var copy_error: Error = _copy_asset(
		source,
		PACKAGE_TEMP_IMPORT,
		PACKAGE_MAX_BYTES
	)
	if copy_error != OK:
		_package_failure(copy_error, "The selected track package cannot be read.")
		return {}

	var reader: ZIPReader = ZIPReader.new()
	var error: Error = reader.open(PACKAGE_TEMP_IMPORT)
	if error != OK:
		DirAccess.remove_absolute(PACKAGE_TEMP_IMPORT)
		_package_failure(error, "This is not a valid Musirail track package.")
		return {}

	var manifest: Dictionary = _read_package_json(reader, PACKAGE_MANIFEST)
	var chart: Dictionary = _read_package_json(reader, PACKAGE_CHART)
	var package_version: int = int(manifest.get("version", 0))
	if (
		str(manifest.get("format", "")) != "musirail-track"
		or package_version not in [LEGACY_PACKAGE_VERSION, PACKAGE_VERSION]
		or str(manifest.get("chart", "")) != PACKAGE_CHART
		or int(chart.get("version", 0)) != CHART_VERSION
		or not chart.get("difficulties", {}) is Dictionary
	):
		reader.close()
		DirAccess.remove_absolute(PACKAGE_TEMP_IMPORT)
		_package_failure(ERR_FILE_CORRUPT, "The package format is invalid or unsupported.")
		return {}
	var difficulties: Array[Dictionary] = _catalog_difficulties(chart)
	if difficulties.is_empty():
		reader.close()
		DirAccess.remove_absolute(PACKAGE_TEMP_IMPORT)
		_package_failure(ERR_FILE_CORRUPT, "The package contains no playable difficulty.")
		return {}

	var metadata: Dictionary = {}
	if package_version == PACKAGE_VERSION:
		if str(manifest.get("metadata", "")) != PACKAGE_METADATA:
			reader.close()
			DirAccess.remove_absolute(PACKAGE_TEMP_IMPORT)
			_package_failure(ERR_FILE_CORRUPT, "The package metadata is missing.")
			return {}
		metadata = _read_package_json(reader, PACKAGE_METADATA)
		if metadata.is_empty():
			reader.close()
			DirAccess.remove_absolute(PACKAGE_TEMP_IMPORT)
			_package_failure(ERR_FILE_CORRUPT, "The package metadata is invalid.")
			return {}
	else:
		metadata = {
			"title": str(manifest.get("title", "")),
			"artist": str(manifest.get("artist", "")),
		}

	var title: String = str(metadata.get("title", "")).strip_edges()
	if title.is_empty():
		title = "Imported Track"
	var song_id: String = _make_song_id(title)
	var song_directory: String = _join_path(USER_SONGS_DIRECTORY, song_id)
	var audio_result: Dictionary = _unpack_song_asset(
		reader,
		manifest.get("audio", {}),
		song_directory,
		"audio",
		["ogg", "mp3", "wav"]
	)
	if audio_result.is_empty():
		reader.close()
		DirAccess.remove_absolute(PACKAGE_TEMP_IMPORT)
		_package_failure(ERR_FILE_CORRUPT, "The package has no usable audio.")
		return {}

	var cover_result: Dictionary = {}
	if manifest.has("cover"):
		cover_result = _unpack_song_asset(
			reader,
			manifest["cover"],
			song_directory,
			"cover",
			["png", "jpg", "jpeg", "webp"]
		)
		if cover_result.is_empty():
			reader.close()
			DirAccess.remove_absolute(PACKAGE_TEMP_IMPORT)
			_package_failure(ERR_FILE_CORRUPT, "The package cover is invalid.")
			return {}

	var chart_bytes: PackedByteArray = reader.read_file(PACKAGE_CHART)
	var license_bytes: PackedByteArray = PackedByteArray()
	if (
		str(manifest.get("license", "")) == PACKAGE_LICENSE
		and reader.file_exists(PACKAGE_LICENSE)
	):
		license_bytes = reader.read_file(PACKAGE_LICENSE)
	reader.close()
	DirAccess.remove_absolute(PACKAGE_TEMP_IMPORT)
	if chart_bytes.is_empty():
		_package_failure(ERR_FILE_CORRUPT, "The package chart is empty.")
		return {}

	error = DirAccess.make_dir_recursive_absolute(song_directory)
	if error != OK:
		_package_failure(error, "The imported track directory cannot be created.")
		return {}
	if not _write_bytes(_join_path(song_directory, PACKAGE_CHART), chart_bytes):
		_package_failure(ERR_FILE_CANT_WRITE, "The imported chart cannot be saved.")
		return {}
	if not _save_unpacked_asset(song_directory, audio_result):
		_package_failure(ERR_FILE_CANT_WRITE, "The imported audio cannot be saved.")
		return {}
	if not cover_result.is_empty() and not _save_unpacked_asset(
		song_directory,
		cover_result
	):
		_package_failure(ERR_FILE_CANT_WRITE, "The imported cover cannot be saved.")
		return {}

	metadata["title"] = title
	metadata["artist"] = str(metadata.get("artist", manifest.get("artist", "")))
	metadata["audio"] = str(audio_result["catalog_path"])
	metadata["chart"] = PACKAGE_CHART
	var first_difficulty: Dictionary = difficulties[0]
	metadata["difficulty"] = str(
		metadata.get("difficulty", first_difficulty["label"])
	)
	metadata["stars"] = int(metadata.get("stars", first_difficulty["stars"]))
	if not cover_result.is_empty():
		metadata["cover"] = str(cover_result["catalog_path"])
	else:
		metadata.erase("cover")
	if not _write_json(_join_path(song_directory, "metadata.json"), metadata):
		_package_failure(ERR_FILE_CANT_WRITE, "The imported metadata cannot be saved.")
		return {}
	if not license_bytes.is_empty() and not _write_bytes(
		_join_path(song_directory, PACKAGE_LICENSE),
		license_bytes
	):
		_package_failure(ERR_FILE_CANT_WRITE, "The song license cannot be saved.")
		return {}

	var song: Dictionary = _song_from_directory(song_id)
	if song.is_empty():
		_package_failure(ERR_FILE_CORRUPT, "The installed song is not playable.")
		return {}
	_rebuild_catalog()
	return song


func is_song_playable(song: Dictionary) -> bool:
	var directory: String = str(song.get("directory", ""))
	var difficulties: Variant = song.get("difficulties", [])
	if directory.is_empty() or not difficulties is Array or difficulties.is_empty():
		return false
	return (
		asset_exists(get_audio_path(song))
		and asset_exists(get_chart_path(song))
	)


func asset_exists(path: String) -> bool:
	if path.is_empty():
		return false
	if path.begins_with("res://"):
		# Imported audio and textures are stored as Godot resources in an
		# exported PCK. FileAccess alone cannot see their original paths.
		return ResourceLoader.exists(path) or FileAccess.file_exists(path)
	return FileAccess.file_exists(path)


func get_audio_path(song: Dictionary) -> String:
	return _join_path(
		str(song.get("directory", "")),
		str(song.get("audio", "audio.ogg"))
	)


func get_chart_path(song: Dictionary) -> String:
	return _join_path(
		str(song.get("directory", "")),
		str(song.get("chart", "chart.json"))
	)


func get_cover_path(song: Dictionary) -> String:
	var cover_name: String = str(song.get("cover", ""))
	if cover_name.is_empty():
		return ""
	return _join_path(str(song.get("directory", "")), cover_name)


func load_audio(path: String) -> AudioStream:
	if path.begins_with("res://"):
		return load(path) as AudioStream

	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
		_:
			push_error("Unsupported audio format: " + path)
			return null


func load_cover(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		return load(path) as Texture2D
	var image: Image = Image.load_from_file(path)
	if image == null or image.is_empty():
		push_warning("Unable to load cover: " + path)
		return null
	return ImageTexture.create_from_image(image)


func save_recorded_song(
	draft: Dictionary,
	notes: Array[Dictionary],
	duration: float,
	existing_song: Dictionary = {}
) -> Dictionary:
	ensure_song_library()
	if notes.is_empty():
		push_error("A recorded chart must contain at least one note.")
		return {}

	var source_audio: String = str(draft.get("audio_path", ""))
	if not asset_exists(source_audio):
		push_error("Recorded song audio no longer exists: " + source_audio)
		return {}

	var replacing: bool = not existing_song.is_empty()
	var song_id: String = str(existing_song.get("id", ""))
	if song_id.is_empty():
		song_id = _make_song_id(str(draft.get("title", "track")))
	var song_directory: String = str(existing_song.get("directory", ""))
	if song_directory.is_empty():
		song_directory = _join_path(USER_SONGS_DIRECTORY, song_id)
	var error: Error = DirAccess.make_dir_recursive_absolute(song_directory)
	if error != OK:
		push_error("Unable to create user song directory: " + song_directory)
		return {}

	var audio_extension: String = source_audio.get_extension().to_lower()
	var audio_is_resource: bool = source_audio.begins_with("res://")
	var audio_name: String = (
		source_audio if audio_is_resource else "audio." + audio_extension
	)
	var audio_destination: String = _join_path(song_directory, audio_name)
	if (
		not replacing
		and not audio_is_resource
		and not _copy_file(source_audio, audio_destination)
	):
		return {}

	var cover_name: String = ""
	var source_cover: String = str(draft.get("cover_path", ""))
	if not source_cover.is_empty() and asset_exists(source_cover):
		var cover_is_resource: bool = source_cover.begins_with("res://")
		cover_name = (
			source_cover
			if cover_is_resource
			else "cover." + source_cover.get_extension().to_lower()
		)
		if (
			not replacing
			and not cover_is_resource
			and not _copy_file(
				source_cover,
				_join_path(song_directory, cover_name)
			)
		):
			return {}

	var difficulty: Dictionary = draft.get("difficulty", {})
	var difficulty_id: String = str(difficulty.get("id", "normal"))
	var difficulty_label: String = str(
		difficulty.get("label", difficulty_id.capitalize())
	)
	var stars: int = clampi(int(difficulty.get("stars", 3)), 1, 5)
	var sorted_notes: Array[Dictionary] = notes.duplicate(true)
	sorted_notes.sort_custom(_note_precedes)
	var chart: Dictionary = {
		"version": CHART_VERSION,
		"duration": maxf(duration, 0.0),
		"timing": {
			"bpm": 0.0,
			"first_beat": 0.0,
			"source": "manual_recording",
		},
		"generator": {
			"name": "musirail-track-editor",
			"source": audio_name,
		},
		"difficulties": {
			difficulty_id: {
				"label": difficulty_label,
				"stars": stars,
				"notes": sorted_notes,
			},
		},
	}
	var metadata: Dictionary = {
		"title": str(draft.get("title", "Untitled Track")),
		"artist": str(draft.get("artist", "")),
		"audio": audio_name,
		"chart": "chart.json",
		"difficulty": difficulty_label,
		"stars": stars,
	}
	if not cover_name.is_empty():
		metadata["cover"] = cover_name

	if not _write_json(_join_path(song_directory, "chart.json"), chart):
		return {}
	if not _write_json(_join_path(song_directory, "metadata.json"), metadata):
		return {}

	_rebuild_catalog()
	return _song_from_directory(song_id)


func _rebuild_catalog() -> Array[Dictionary]:
	var songs: Array[Dictionary] = []
	var directory: DirAccess = DirAccess.open(USER_SONGS_DIRECTORY)
	if directory == null:
		return songs
	directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while not entry_name.is_empty():
		if directory.current_is_dir() and not entry_name.begins_with("."):
			var song: Dictionary = _song_from_directory(entry_name)
			if not song.is_empty():
				songs.append(_ensure_maximum_scores(song))
		entry_name = directory.get_next()
	directory.list_dir_end()
	songs.sort_custom(_song_precedes)
	_write_json(USER_CATALOG_PATH, {
		"version": CATALOG_VERSION,
		"songs": songs,
	})
	return songs


func _song_from_directory(song_id: String) -> Dictionary:
	if song_id.is_empty() or song_id.get_file() != song_id:
		return {}
	var song_directory: String = _join_path(USER_SONGS_DIRECTORY, song_id)
	if not DirAccess.dir_exists_absolute(song_directory):
		return {}
	var metadata: Dictionary = _read_json_object(
		_join_path(song_directory, PACKAGE_METADATA)
	)
	if metadata.is_empty():
		return {}
	var audio_name: String = _safe_local_file_name(
		str(metadata.get("audio", "audio.ogg")),
		["ogg", "mp3", "wav"]
	)
	var chart_name: String = _safe_local_file_name(
		str(metadata.get("chart", PACKAGE_CHART)),
		["json"]
	)
	if audio_name.is_empty() or chart_name.is_empty():
		return {}
	var chart: Dictionary = _read_json_object(
		_join_path(song_directory, chart_name)
	)
	if int(chart.get("version", 0)) != CHART_VERSION:
		return {}
	var difficulties: Array[Dictionary] = _catalog_difficulties(chart)
	if difficulties.is_empty():
		return {}
	var song: Dictionary = {
		"id": song_id,
		"directory": song_directory,
		"title": str(metadata.get("title", song_id)),
		"artist": str(metadata.get("artist", "")),
		"audio": audio_name,
		"chart": chart_name,
		"difficulties": difficulties,
	}
	var cover_name: String = _safe_local_file_name(
		str(metadata.get("cover", "")),
		["png", "jpg", "jpeg", "webp"]
	)
	if not cover_name.is_empty():
		song["cover"] = cover_name
	if not is_song_playable(song):
		return {}
	return song


func _safe_local_file_name(value: String, extensions: Array) -> String:
	var file_name: String = value.strip_edges()
	if (
		file_name.is_empty()
		or file_name.get_file() != file_name
		or not extensions.has(file_name.get_extension().to_lower())
	):
		return ""
	return file_name


func _song_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_title: String = str(left.get("title", "")).to_lower()
	var right_title: String = str(right.get("title", "")).to_lower()
	if left_title == right_title:
		return str(left.get("id", "")) < str(right.get("id", ""))
	return left_title < right_title


func _read_json_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _write_json(path: String, value: Dictionary) -> bool:
	var directory: String = path.get_base_dir()
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		push_error("Unable to create directory: " + directory)
		return false
	var temporary_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write file: " + temporary_path)
		return false
	file.store_string(JSON.stringify(value, "  ") + "\n")
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(temporary_path, path) != OK:
		push_error("Unable to finalize file: " + path)
		return false
	return true


func _remove_flat_song_directory(path: String) -> bool:
	if (
		not path.begins_with(USER_SONGS_DIRECTORY + "/")
		or path.get_base_dir() != USER_SONGS_DIRECTORY
	):
		return false
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return not DirAccess.dir_exists_absolute(path)
	directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while not entry_name.is_empty():
		if directory.current_is_dir():
			directory.list_dir_end()
			return false
		if directory.remove(entry_name) != OK:
			directory.list_dir_end()
			return false
		entry_name = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(path) == OK


func _copy_file(source: String, destination: String) -> bool:
	var error: Error = DirAccess.copy_absolute(source, destination)
	if error != OK:
		push_error("Unable to copy %s to %s" % [source, destination])
		return false
	return true


func _pack_song_asset(
	packer: ZIPPacker,
	path: String,
	base_name: String
) -> Dictionary:
	var extension: String = path.get_extension().to_lower()
	if extension.is_empty():
		return {}
	var bytes: PackedByteArray = _read_asset_bytes(path)
	if bytes.is_empty():
		return {}
	var archive_path: String = "%s.%s" % [base_name, extension]
	if _write_zip_entry(packer, archive_path, bytes) != OK:
		return {}
	return {
		"kind": "bundled",
		"file": archive_path,
	}


func _unpack_song_asset(
	reader: ZIPReader,
	descriptor_value: Variant,
	song_directory: String,
	base_name: String,
	allowed_extensions: Array
) -> Dictionary:
	if not descriptor_value is Dictionary:
		return {}
	var descriptor: Dictionary = descriptor_value
	var kind: String = str(descriptor.get("kind", ""))
	if kind != "bundled":
		return {}
	var archive_path: String = str(descriptor.get("file", ""))
	var extension: String = archive_path.get_extension().to_lower()
	if (
		archive_path.get_file() != archive_path
		or not archive_path.begins_with(base_name + ".")
		or not allowed_extensions.has(extension)
		or not reader.file_exists(archive_path)
	):
		return {}
	var bytes: PackedByteArray = reader.read_file(archive_path)
	if bytes.is_empty() or bytes.size() > PACKAGE_MAX_BYTES:
		return {}
	var file_name: String = "%s.%s" % [base_name, extension]
	return {
		"kind": kind,
		"catalog_path": file_name,
		"destination": _join_path(song_directory, file_name),
		"bytes": bytes,
	}


func _save_unpacked_asset(
	_song_directory: String,
	asset: Dictionary
) -> bool:
	var bytes_value: Variant = asset.get("bytes", PackedByteArray())
	if not bytes_value is PackedByteArray:
		return false
	return _write_bytes(str(asset.get("destination", "")), bytes_value)


func _write_zip_entry(
	packer: ZIPPacker,
	path: String,
	bytes: PackedByteArray
) -> Error:
	var error: Error = packer.start_file(path)
	if error != OK:
		return error
	error = packer.write_file(bytes)
	var close_error: Error = packer.close_file()
	return error if error != OK else close_error


func _read_package_json(reader: ZIPReader, path: String) -> Dictionary:
	if not reader.file_exists(path):
		return {}
	var bytes: PackedByteArray = reader.read_file(path)
	if bytes.is_empty() or bytes.size() > 8 * 1024 * 1024:
		return {}
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _read_asset_bytes(path: String) -> PackedByteArray:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return bytes


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	if path.is_empty() or bytes.is_empty():
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	var error: Error = file.get_error()
	file.close()
	return error == OK


func _copy_asset(
	source: String,
	destination: String,
	maximum_bytes: int = 0
) -> Error:
	var source_file: FileAccess = FileAccess.open(source, FileAccess.READ)
	if source_file == null:
		return FileAccess.get_open_error()
	var length: int = source_file.get_length()
	if maximum_bytes > 0 and length > maximum_bytes:
		source_file.close()
		return ERR_FILE_CANT_READ
	var destination_file: FileAccess = FileAccess.open(
		destination,
		FileAccess.WRITE
	)
	if destination_file == null:
		source_file.close()
		return FileAccess.get_open_error()
	const COPY_CHUNK_BYTES: int = 1024 * 1024
	while source_file.get_position() < length:
		var remaining: int = length - source_file.get_position()
		destination_file.store_buffer(
			source_file.get_buffer(mini(COPY_CHUNK_BYTES, remaining))
		)
		if destination_file.get_error() != OK:
			var write_error: Error = destination_file.get_error()
			source_file.close()
			destination_file.close()
			return write_error
	source_file.close()
	destination_file.close()
	return OK


func _catalog_difficulties(chart: Dictionary) -> Array[Dictionary]:
	var difficulties_value: Variant = chart.get("difficulties", {})
	if not difficulties_value is Dictionary:
		return []
	var difficulty_map: Dictionary = difficulties_value
	var ids: Array[String] = []
	for difficulty_id: Variant in difficulty_map.keys():
		ids.append(str(difficulty_id))
	ids.sort_custom(_package_difficulty_precedes)
	var result: Array[Dictionary] = []
	for difficulty_id: String in ids:
		var difficulty_value: Variant = difficulty_map[difficulty_id]
		if not difficulty_value is Dictionary:
			continue
		var difficulty: Dictionary = difficulty_value
		var notes_value: Variant = difficulty.get("notes", [])
		if not notes_value is Array or notes_value.is_empty():
			continue
		result.append({
			"id": difficulty_id,
			"label": str(difficulty.get("label", difficulty_id.capitalize())),
			"stars": clampi(int(difficulty.get("stars", 1)), 1, 5),
			"note_count": notes_value.size(),
			"max_score": ScoreGrade.maximum_score_for_notes(notes_value),
		})
	return result


func _ensure_maximum_scores(song: Dictionary) -> Dictionary:
	var difficulties_value: Variant = song.get("difficulties", [])
	if not difficulties_value is Array:
		return song
	var difficulties: Array = difficulties_value
	var needs_maximum: bool = false
	for difficulty_value: Variant in difficulties:
		if (
			difficulty_value is Dictionary
			and int(difficulty_value.get("max_score", 0)) <= 0
		):
			needs_maximum = true
			break
	if not needs_maximum:
		return song

	var calculated: Array[Dictionary] = ChartManager.get_difficulties(
		get_chart_path(song)
	)
	var maximum_by_id: Dictionary = {}
	for difficulty: Dictionary in calculated:
		maximum_by_id[str(difficulty.get("id", ""))] = int(
			difficulty.get("max_score", 0)
		)
	var updated_difficulties: Array[Dictionary] = []
	for difficulty_value: Variant in difficulties:
		if not difficulty_value is Dictionary:
			continue
		var difficulty: Dictionary = difficulty_value.duplicate(true)
		var difficulty_id: String = str(difficulty.get("id", ""))
		if int(difficulty.get("max_score", 0)) <= 0:
			difficulty["max_score"] = int(
				maximum_by_id.get(difficulty_id, 0)
			)
		updated_difficulties.append(difficulty)
	var updated_song: Dictionary = song.duplicate(true)
	updated_song["difficulties"] = updated_difficulties
	return updated_song


func _package_difficulty_precedes(left: String, right: String) -> bool:
	var left_index: int = PACKAGE_DIFFICULTY_ORDER.find(left)
	var right_index: int = PACKAGE_DIFFICULTY_ORDER.find(right)
	if left_index < 0:
		left_index = PACKAGE_DIFFICULTY_ORDER.size()
	if right_index < 0:
		right_index = PACKAGE_DIFFICULTY_ORDER.size()
	return left < right if left_index == right_index else left_index < right_index


func _package_failure(error: Error, message: String) -> Error:
	last_package_error = message
	push_warning(message)
	return error


func _make_song_id(title: String) -> String:
	var safe_title: String = ""
	for character: String in title.to_lower():
		if character >= "a" and character <= "z":
			safe_title += character
		elif character >= "0" and character <= "9":
			safe_title += character
		elif not safe_title.ends_with("_"):
			safe_title += "_"
	safe_title = safe_title.trim_suffix("_").trim_prefix("_")
	if safe_title.is_empty():
		safe_title = "track"
	return "user_%s_%d_%d" % [
		safe_title,
		int(Time.get_unix_time_from_system()),
		Time.get_ticks_msec() % 1000000,
	]


func _note_precedes(left: Dictionary, right: Dictionary) -> bool:
	return _note_start_time(left) < _note_start_time(right)


func _note_start_time(note: Dictionary) -> float:
	if str(note.get("type", "")) == "slide":
		var path_value: Variant = note.get("path", [])
		if path_value is Array:
			var note_path: Array = path_value
			if note_path.is_empty():
				return 0.0
			var first_point: Variant = note_path[0]
			if first_point is Dictionary:
				return float(first_point.get("time", 0.0))
	return float(note.get("time", 0.0))


func _join_path(directory: String, file_name: String) -> String:
	if (
		file_name.begins_with("res://")
		or file_name.begins_with("user://")
		or file_name.is_absolute_path()
	):
		return file_name
	return directory.trim_suffix("/") + "/" + file_name.trim_prefix("/")
