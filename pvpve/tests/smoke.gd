# Headless smoke test: loads the main scene and fails if it cannot be instantiated.
# Run with: pvpve/tools/godot.sh --headless --script res://tests/smoke.gd
extends SceneTree


func _init() -> void:
	var scene: PackedScene = load("res://world/main.tscn")
	if scene == null:
		push_error("smoke: main scene failed to load")
		quit(1)
		return
	var root_node := scene.instantiate()
	if root_node == null:
		push_error("smoke: main scene failed to instantiate")
		quit(1)
		return
	root_node.free()
	print("smoke: OK")
	quit(0)
