# Guards the rules that keep the game network-ready while it is built solo.
# Run with: pvpve/tools/godot.sh --headless --script res://tests/test_architecture.gd
extends SceneTree

## Scripts allowed to read raw input: the local input source, UI, dev tools and tests.
const INPUT_ALLOWED_PREFIXES := [
	"res://player/local_input_source.gd",
	"res://ui/",
	"res://tools/",
	"res://tests/",
]
## Gameplay code must not reach into siblings through relative node paths.
const GAMEPLAY_DIRS := ["res://player/", "res://bots/", "res://game/"]

var _failures := 0


func _initialize() -> void:
	var input_regex := RegEx.create_from_string("\\bInput\\.")
	var relative_path_regex := RegEx.create_from_string("(get_node\\(\\s*\\^?\"\\.\\./|\\$\"?\\.\\./)")
	var scripts := _find_scripts("res://")
	print("checking %d scripts" % scripts.size())
	for path in scripts:
		var code := _strip_comments(FileAccess.get_file_as_string(path))
		if not _starts_with_any(path, INPUT_ALLOWED_PREFIXES) and input_regex.search(code) != null:
			_fail("%s reads Input directly; route it through an InputSource" % path)
		if _starts_with_any(path, GAMEPLAY_DIRS) and relative_path_regex.search(code) != null:
			_fail("%s reaches into the scene tree with a relative path; use ids or injected references" % path)
	if _failures == 0:
		print("  ok   architecture rules hold")
	print("architecture tests: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL ", message)


func _starts_with_any(path: String, prefixes: Array) -> bool:
	for prefix: String in prefixes:
		if path.begins_with(prefix):
			return true
	return false


func _find_scripts(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			found.append(dir_path.path_join(file_name))
	for sub_dir in dir.get_directories():
		if sub_dir.begins_with(".") or sub_dir == "addons":
			continue
		found.append_array(_find_scripts(dir_path.path_join(sub_dir)))
	return found


func _strip_comments(code: String) -> String:
	var lines := PackedStringArray()
	for line in code.split("\n"):
		var hash_index := line.find("#")
		lines.append(line if hash_index < 0 else line.substr(0, hash_index))
	return "\n".join(lines)
