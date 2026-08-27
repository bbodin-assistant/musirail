extends Node

var failed: bool = false


func _ready() -> void:
	var songs: Array[Dictionary] = SongLibrary.get_all_songs()
	_check(songs.size() == 1, "A new library contains exactly one demo song.")
	if songs.is_empty():
		_finish()
		return

	var demo: Dictionary = songs[0]
	_check(str(demo.get("title", "")) == "First Light", "The CC0 demo is installed.")
	_check(SongLibrary.is_user_song(demo), "The demo lives in the user library.")

	var package_path: String = "user://roundtrip.musirail"
	var export_error: Error = SongLibrary.export_song_package(demo, package_path)
	_check(export_error == OK, "The demo can be exported.")
	_check_package_contents(package_path)

	var imported: Dictionary = SongLibrary.import_song_package(package_path)
	_check(not imported.is_empty(), "The exported package can be imported.")
	_check(
		str(imported.get("title", "")) == "First Light",
		"Imported metadata is preserved."
	)
	_check(SongLibrary.get_all_songs().size() == 2, "Importing makes a copy.")

	for song: Dictionary in SongLibrary.get_all_songs():
		_check(SongLibrary.delete_user_song(song), "Every song can be deleted.")
	_check(
		SongLibrary.get_all_songs().is_empty(),
		"Deleting every song leaves the existing library empty."
	)
	_finish()


func _check_package_contents(path: String) -> void:
	var reader: ZIPReader = ZIPReader.new()
	_check(reader.open(path) == OK, "The shared file is a readable archive.")
	if failed:
		return
	for required: String in [
		"manifest.json",
		"metadata.json",
		"chart.json",
		"audio.wav",
		"cover.png",
		"LICENSE.txt",
	]:
		_check(reader.file_exists(required), "Shared package contains " + required)
	var metadata: Variant = JSON.parse_string(
		reader.read_file("metadata.json").get_string_from_utf8()
	)
	_check(metadata is Dictionary, "Shared metadata is valid JSON.")
	if metadata is Dictionary:
		_check(metadata.get("license", "") == "CC0-1.0", "License metadata is shared.")
	reader.close()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
		return
	failed = true
	push_error("FAIL: " + message)


func _finish() -> void:
	if failed:
		get_tree().quit(1)
		return
	print("Song library round-trip test passed.")
	get_tree().quit(0)
