class_name PveView
extends Node3D
## What you see of PvE in the world: monster telegraphs and hits, slam shockwaves, gate glows,
## loot pickups with beams, and traps. Presentation only: it listens to the EventBus and reads
## (never writes) game state.

const LOOT_COLORS := {
	LootEntry.Kind.WEAPON: Color(1.0, 0.75, 0.2),
	LootEntry.Kind.HEALTH: Color(0.3, 1.0, 0.45),
	LootEntry.Kind.TRAP: Color(0.9, 0.35, 0.9),
	LootEntry.Kind.XP: Color(0.4, 0.75, 1.0),
}
const TELEGRAPH_COLORS := {
	&"melee": Color(1.0, 0.8, 0.3),
	&"spit": Color(0.6, 1.0, 0.4),
	&"slam": Color(1.0, 0.35, 0.2),
	&"charge": Color(1.0, 0.2, 0.2),
}

@export var game: Game

var _loot_nodes: Dictionary = {}
var _trap_nodes: Dictionary = {}
var _time := 0.0


func _ready() -> void:
	var events := game.events
	events.monster_telegraph.connect(_on_telegraph)
	events.monster_attack.connect(_on_attack)
	events.damage_dealt.connect(_on_damage)
	events.monster_killed.connect(_on_monster_killed)
	events.gate_pulse.connect(_on_gate_pulse)
	events.loot_dropped.connect(_on_loot_dropped)
	events.loot_removed.connect(_on_loot_removed)
	events.trap_placed.connect(_on_trap_placed)
	events.trap_armed.connect(_on_trap_armed)
	events.trap_triggered.connect(_on_trap_triggered)


func _process(delta: float) -> void:
	_time += delta
	for id: int in _loot_nodes:
		var node: Node3D = _loot_nodes[id]
		if is_instance_valid(node):
			node.rotation.y = _time * 1.8
			node.position.y = node.get_meta("base_y") + sin(_time * 3.0 + id) * 0.08


# ---- monsters ---------------------------------------------------------------------------

func _on_telegraph(monster_id: int, ability: StringName, seconds: float) -> void:
	var body := game.monsters.get_body(monster_id)
	if body != null:
		body.glow(TELEGRAPH_COLORS.get(ability, Color.WHITE), seconds)
		if ability == &"charge":
			_spawn_charge_line(body, seconds)


func _spawn_charge_line(body: Monster, seconds: float) -> void:
	var player := _nearest_player(body.global_position)
	if player == null:
		return
	var from := body.global_position + Vector3(0.0, 0.05, 0.0)
	var to := player.global_position + Vector3(0.0, 0.05, 0.0)
	to = from + (to - from).normalized() * minf(from.distance_to(to) + 4.0, 22.0)
	_spawn_ground_line(from, to, 1.2, Color(1.0, 0.15, 0.1, 0.5), seconds + 0.2)


func _nearest_player(position: Vector3) -> Player:
	var best: Player = null
	var best_distance := INF
	for id in game.registry.ids():
		var player := game.get_player(id)
		if player == null or game.registry.get_record(id).kind == PlayerRegistry.Kind.DUMMY:
			continue
		var distance := position.distance_squared_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _on_attack(monster_id: int, ability: StringName, position: Vector3, radius: float) -> void:
	if ability == &"slam" and radius > 0.0:
		_spawn_shockwave(position, radius)
	elif ability == &"melee" or ability == &"charge":
		var body := game.monsters.get_body(monster_id)
		if body != null:
			body.flash(Color(1.0, 0.9, 0.5), 0.1)


func _on_damage(target_id: int, _source: int, _amount: float, _position: Vector3, _weapon: StringName) -> void:
	if target_id < MonsterSystem.FIRST_ID:
		return
	var body := game.monsters.get_body(target_id)
	if body != null:
		body.flash()


func _on_monster_killed(monster_id: int, _killer: int, position: Vector3, def_id: StringName) -> void:
	var def := game.monster_defs.get_def(def_id)
	var color := def.color if def != null else Color.WHITE
	var big := def != null and def.is_boss
	_spawn_burst(position + Vector3(0.0, 0.9, 0.0), color, 40 if big else 16, 5.0 if big else 3.0)
	if big:
		_spawn_shockwave(position, 7.0)


func _on_gate_pulse(owner_id: int, gate_index: int, seconds: float) -> void:
	var zone := game.zones.get_zone(owner_id)
	if zone != null:
		zone.pulse_gate(gate_index, maxf(seconds, 0.3))


func _spawn_shockwave(position: Vector3, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.08
	ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.45, 0.2, 0.55)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.35, 0.1)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = position + Vector3(0.0, 0.1, 0.0)
	ring.scale = Vector3(0.3, 1.0, 0.3)
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.4)
	tween.chain().tween_callback(ring.queue_free)


func _spawn_ground_line(from: Vector3, to: Vector3, width: float, color: Color, seconds: float) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var strip := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.03, length)
	strip.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip.material_override = material
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(strip)
	strip.look_at_from_position((from + to) * 0.5, to)
	var tween := strip.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(strip.queue_free)


func _spawn_burst(at: Vector3, color: Color, amount: int, speed: float) -> void:
	var burst := CPUParticles3D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.amount = amount
	burst.lifetime = 0.7
	burst.explosiveness = 1.0
	burst.direction = Vector3.UP
	burst.spread = 180.0
	burst.initial_velocity_min = speed * 0.4
	burst.initial_velocity_max = speed
	burst.gravity = Vector3(0.0, -9.8, 0.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	burst.mesh = mesh
	add_child(burst)
	burst.global_position = at
	burst.emitting = true
	get_tree().create_timer(1.0).timeout.connect(burst.queue_free)


# ---- loot ---------------------------------------------------------------------------------------

func _on_loot_dropped(drop_id: int, kind: int, label: String, position: Vector3) -> void:
	var color: Color = LOOT_COLORS.get(kind, Color.WHITE)
	var holder := Node3D.new()
	holder.set_meta("base_y", position.y)
	var gem := MeshInstance3D.new()
	var mesh: Mesh
	match kind:
		LootEntry.Kind.WEAPON:
			var box := BoxMesh.new()
			box.size = Vector3(0.42, 0.42, 0.42)
			mesh = box
		LootEntry.Kind.HEALTH:
			var cross := BoxMesh.new()
			cross.size = Vector3(0.5, 0.2, 0.2)
			mesh = cross
		LootEntry.Kind.TRAP:
			var prism := PrismMesh.new()
			prism.size = Vector3(0.5, 0.4, 0.5)
			mesh = prism
		_:
			var sphere := SphereMesh.new()
			sphere.radius = 0.2
			sphere.height = 0.4
			mesh = sphere
	gem.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.4
	gem.material_override = material
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(gem)
	if kind == LootEntry.Kind.HEALTH:
		var upright := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(0.2, 0.5, 0.2)
		upright.mesh = bar
		upright.material_override = material
		holder.add_child(upright)
	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.06, 6.0, 0.06)
	beam.mesh = beam_mesh
	var beam_material := StandardMaterial3D.new()
	beam_material.albedo_color = Color(color.r, color.g, color.b, 0.35)
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = beam_material
	beam.position.y = 3.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(beam)
	var text := Label3D.new()
	text.text = label
	text.font_size = 32
	text.pixel_size = 0.004
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.position = Vector3(0.0, 0.7, 0.0)
	text.outline_size = 8
	text.modulate = color.lightened(0.4)
	holder.add_child(text)
	add_child(holder)
	holder.global_position = position
	_loot_nodes[drop_id] = holder


func _on_loot_removed(drop_id: int) -> void:
	var node: Node3D = _loot_nodes.get(drop_id)
	_loot_nodes.erase(drop_id)
	if node != null and is_instance_valid(node):
		_spawn_burst(node.global_position, Color(1.0, 1.0, 0.8), 8, 2.0)
		node.queue_free()


# ---- traps ---------------------------------------------------------------------------------------

func _on_trap_placed(trap_id: int, _owner: int, position: Vector3) -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = LootSystem.TRAP_RADIUS * 0.45
	mesh.bottom_radius = LootSystem.TRAP_RADIUS * 0.45
	mesh.height = 0.05
	disc.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.6, 0.65, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.8, 0.7, 0.2)
	material.emission_energy_multiplier = 0.4
	disc.material_override = material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	disc.global_position = position + Vector3(0.0, 0.04, 0.0)
	_trap_nodes[trap_id] = disc


func _on_trap_armed(trap_id: int) -> void:
	var disc: MeshInstance3D = _trap_nodes.get(trap_id)
	if disc == null:
		return
	var material := disc.material_override as StandardMaterial3D
	material.emission = Color(1.0, 0.2, 0.15)
	material.emission_energy_multiplier = 1.6
	material.albedo_color.a = 0.35


func _on_trap_triggered(trap_id: int, _victim: int, position: Vector3) -> void:
	var disc: MeshInstance3D = _trap_nodes.get(trap_id)
	_trap_nodes.erase(trap_id)
	if disc != null:
		disc.queue_free()
	_spawn_burst(position + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.5, 0.2), 24, 5.0)
	_spawn_shockwave(position, LootSystem.TRAP_RADIUS * 1.2)
