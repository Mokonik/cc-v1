class_name CombatView
extends Node3D
## Everything you see of combat in the world: the viewmodel, tracers, impact sparks, damage
## numbers, arrows and orbs in flight, explosions and health bars over other players.
## Presentation only: it listens to the EventBus and reads (never writes) combat state.

const BAR_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float fill = 1.0;
uniform vec4 color : source_color = vec4(0.3, 0.9, 0.4, 1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	bool inside = UV.x <= fill;
	bool border = UV.x < 0.02 || UV.x > 0.98 || UV.y < 0.12 || UV.y > 0.88;
	vec3 base = inside ? color.rgb : vec3(0.08, 0.08, 0.1);
	ALBEDO = border ? vec3(0.0) : base;
	ALPHA = 0.92;
}
"""

@export var game: Game

var _viewmodel: Viewmodel
var _bar_shader: Shader
var _bars: Dictionary = {}
var _projectile_nodes: Dictionary = {}


func _ready() -> void:
	_bar_shader = Shader.new()
	_bar_shader.code = BAR_SHADER_CODE
	var events := game.events
	events.player_spawned.connect(_on_player_spawned)
	events.player_removed.connect(_on_player_removed)
	events.weapon_changed.connect(_on_weapon_changed)
	events.weapon_fired.connect(_on_weapon_fired)
	events.melee_swing.connect(func(pid: int, _wid: StringName) -> void:
		if pid == PlayerRegistry.HOST_ID and _viewmodel != null:
			_viewmodel.swing())
	events.reload_started.connect(func(pid: int, _wid: StringName, _d: float) -> void:
		if pid == PlayerRegistry.HOST_ID and _viewmodel != null:
			_viewmodel.set_reloading(true))
	events.reload_finished.connect(func(pid: int, _wid: StringName) -> void:
		if pid == PlayerRegistry.HOST_ID and _viewmodel != null:
			_viewmodel.set_reloading(false))
	events.projectile_spawned.connect(_on_projectile_spawned)
	events.projectile_ended.connect(_on_projectile_ended)
	events.explosion.connect(_on_explosion)
	events.damage_dealt.connect(_on_damage_dealt)
	events.player_died.connect(_on_player_died)
	events.monster_spawned.connect(_on_monster_spawned)


func _process(_delta: float) -> void:
	_update_bars()
	_update_projectiles()
	_update_viewmodel_state()


# ---- players, viewmodel, bars ---------------------------------------------------

func _on_player_spawned(player_id: int) -> void:
	var player := game.get_player(player_id)
	if player == null:
		return
	if player_id == PlayerRegistry.HOST_ID:
		if _viewmodel != null:
			_viewmodel.queue_free()
		_viewmodel = Viewmodel.new()
		_viewmodel.player = player
		player.camera.add_child(_viewmodel)
		var vitals := game.combat.get_vitals(player_id)
		if vitals != null and vitals.current() != null:
			_viewmodel.show_weapon(vitals.current().def.id)
	else:
		_add_bar(player)


func _on_player_removed(player_id: int) -> void:
	_bars.erase(player_id)


func _on_weapon_changed(player_id: int, weapon_id: StringName) -> void:
	if player_id == PlayerRegistry.HOST_ID and _viewmodel != null:
		_viewmodel.show_weapon(weapon_id)


func _on_monster_spawned(monster_id: int, _def_id: StringName, _position: Vector3) -> void:
	var body := game.monsters.get_body(monster_id)
	if body != null:
		_add_bar(body, body.def.height + 0.55, body.def.is_boss)


func _add_bar(player: Combatant, height := 2.25, is_boss := false) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(0.0, height, 0.0)
	if is_boss:
		holder.scale = Vector3(2.4, 2.4, 2.4)
	var bar := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 0.11)
	bar.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = _bar_shader
	bar.material_override = material
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(bar)
	var label := Label3D.new()
	label.text = player.display_name
	label.font_size = 36
	label.pixel_size = 0.0035
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 0.2, 0.0)
	label.outline_size = 8
	holder.add_child(label)
	player.add_child(holder)
	_bars[player.entity_id] = {"holder": holder, "material": material}


func _update_bars() -> void:
	for id: int in _bars.keys():
		var entry: Dictionary = _bars[id]
		# The bar is a child of its combatant, so it is freed with it: check before typing it.
		if not is_instance_valid(entry.holder):
			_bars.erase(id)
			continue
		var holder: Node3D = entry.holder
		var vitals := game.combat.get_vitals(id)
		if vitals == null:
			continue
		holder.visible = vitals.alive
		var fraction := vitals.hp / vitals.max_hp
		var material: ShaderMaterial = entry.material
		material.set_shader_parameter("fill", fraction)
		material.set_shader_parameter("color", Color(0.9, 0.25, 0.2).lerp(Color(0.3, 0.9, 0.4), fraction))


func _update_viewmodel_state() -> void:
	if _viewmodel == null:
		return
	var vitals := game.combat.get_vitals(PlayerRegistry.HOST_ID)
	var state := vitals.current() if vitals != null else null
	if state == null:
		return
	if state.is_drawing():
		var draw_ticks := maxi(WeaponDef.seconds_to_ticks(state.def.draw_time), 1)
		_viewmodel.set_draw(float(game.combat.tick - state.draw_start_tick) / float(draw_ticks))
	else:
		_viewmodel.set_draw(0.0)
	_viewmodel.visible = vitals.alive


# ---- shots and hits ------------------------------------------------------------------

func _on_weapon_fired(player_id: int, weapon_id: StringName, origin: Vector3, direction: Vector3, end_point: Vector3) -> void:
	var def := game.weapons.get_def(weapon_id)
	if def == null:
		return
	var is_local := player_id == PlayerRegistry.HOST_ID
	if is_local:
		var player := game.get_player(player_id)
		if player != null:
			player.add_recoil(deg_to_rad(def.recoil_pitch_deg), deg_to_rad(randf_range(-1.0, 1.0) * def.recoil_yaw_deg))
		if _viewmodel != null:
			_viewmodel.fire(def.viewmodel_kick, def.kind == WeaponDef.Kind.HITSCAN)
	if def.kind != WeaponDef.Kind.HITSCAN:
		return
	var start := origin + direction * 0.6 + Vector3(0.0, -0.12, 0.0)
	if is_local and _viewmodel != null:
		start = _viewmodel.muzzle_global_position()
	_spawn_tracer(start, end_point)
	_spawn_sparks(end_point, Color(1.0, 0.85, 0.5), 8)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.2:
		return
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.012, length)
	tracer.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.9, 0.55, 0.9)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer.material_override = material
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tracer)
	tracer.look_at_from_position((from + to) * 0.5, to)
	var tween := tracer.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.09)
	tween.tween_callback(tracer.queue_free)


func _spawn_sparks(at: Vector3, color: Color, amount: int) -> void:
	var sparks := CPUParticles3D.new()
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = amount
	sparks.lifetime = 0.35
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 80.0
	sparks.initial_velocity_min = 1.5
	sparks.initial_velocity_max = 4.0
	sparks.gravity = Vector3(0.0, -9.8, 0.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	sparks.mesh = mesh
	add_child(sparks)
	sparks.global_position = at
	sparks.emitting = true
	get_tree().create_timer(0.6).timeout.connect(sparks.queue_free)


func _on_damage_dealt(target_id: int, source_id: int, amount: float, position: Vector3, weapon_id: StringName) -> void:
	var local_id := PlayerRegistry.HOST_ID
	if source_id == local_id and target_id != local_id:
		_spawn_damage_number(position, amount)
		var def := game.weapons.get_def(weapon_id)
		if def != null and def.kind == WeaponDef.Kind.MELEE and _viewmodel != null:
			_viewmodel.hit_stop(0.06)
		_spawn_sparks(position, Color(1.0, 0.35, 0.25), 6)
	if target_id == local_id:
		var player := game.get_player(local_id)
		if player != null:
			player.add_shake(clampf(amount / 40.0, 0.12, 0.6))


func _spawn_damage_number(position: Vector3, amount: float) -> void:
	var label := Label3D.new()
	label.text = "%d" % roundi(amount)
	label.font_size = 56
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 12
	label.modulate = Color(1.0, 0.95, 0.7).lerp(Color(1.0, 0.45, 0.2), clampf(amount / 35.0, 0.0, 1.0))
	add_child(label)
	label.global_position = position + Vector3(randf_range(-0.2, 0.2), 0.5, randf_range(-0.2, 0.2))
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 0.9, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)


func _on_player_died(victim_id: int, _killer_id: int, _weapon_id: StringName) -> void:
	var player := game.get_player(victim_id)
	if player != null:
		_spawn_sparks(player.global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.3, 0.25), 18)


# ---- projectiles and explosions -----------------------------------------------------

func _on_projectile_spawned(projectile_id: int, weapon_id: StringName, position: Vector3, _velocity: Vector3) -> void:
	var visual := Node3D.new()
	if weapon_id == &"spit" or weapon_id == &"boss_orb":
		var glob := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.16 if weapon_id == &"spit" else 0.3
		sphere.height = sphere.radius * 2.0
		glob.mesh = sphere
		var glob_material := StandardMaterial3D.new()
		var tint := Color(0.5, 1.0, 0.3) if weapon_id == &"spit" else Color(0.75, 0.3, 1.0)
		glob_material.albedo_color = tint
		glob_material.emission_enabled = true
		glob_material.emission = tint
		glob_material.emission_energy_multiplier = 2.0
		glob.material_override = glob_material
		glob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(glob)
		var glow := OmniLight3D.new()
		glow.light_color = tint
		glow.light_energy = 1.2
		glow.omni_range = 4.0
		visual.add_child(glow)
	elif weapon_id == &"orb":
		var mesh_instance := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.2
		sphere.height = 0.4
		mesh_instance.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.5, 0.1)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.4, 0.05)
		material.emission_energy_multiplier = 2.5
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(mesh_instance)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.2)
		light.light_energy = 2.0
		light.omni_range = 6.0
		visual.add_child(light)
		var trail := CPUParticles3D.new()
		trail.amount = 24
		trail.lifetime = 0.5
		trail.local_coords = false
		trail.gravity = Vector3.ZERO
		trail.initial_velocity_max = 0.4
		trail.scale_amount_min = 0.5
		var spark := SphereMesh.new()
		spark.radius = 0.06
		spark.height = 0.12
		var spark_material := StandardMaterial3D.new()
		spark_material.albedo_color = Color(1.0, 0.6, 0.15)
		spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		spark.material = spark_material
		trail.mesh = spark
		visual.add_child(trail)
	else:
		var shaft := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.02, 0.02, 0.75)
		shaft.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.85, 0.75, 0.55)
		shaft.material_override = material
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(shaft)
	add_child(visual)
	visual.global_position = position
	_projectile_nodes[projectile_id] = visual


func _update_projectiles() -> void:
	for id: int in _projectile_nodes:
		var visual: Node3D = _projectile_nodes[id]
		var projectile := game.combat.projectiles.get_projectile(id)
		if projectile == null or not is_instance_valid(visual):
			continue
		visual.global_position = projectile.position
		if projectile.velocity.length_squared() > 0.01:
			var up := Vector3.UP if absf(projectile.velocity.normalized().y) < 0.99 else Vector3.RIGHT
			visual.look_at(projectile.position + projectile.velocity, up)


func _on_projectile_ended(projectile_id: int, position: Vector3, hit_player_id: int) -> void:
	var visual: Node3D = _projectile_nodes.get(projectile_id)
	_projectile_nodes.erase(projectile_id)
	if visual != null:
		visual.queue_free()
	if hit_player_id != 0:
		_spawn_sparks(position, Color(1.0, 0.8, 0.5), 8)


func _on_explosion(position: Vector3, radius: float, _weapon_id: StringName) -> void:
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	ball.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.55, 0.15, 0.7)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.45, 0.1)
	material.emission_energy_multiplier = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = material
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.global_position = position
	ball.scale = Vector3.ONE * 0.3
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 6.0
	light.omni_range = radius * 2.0
	ball.add_child(light)
	var tween := ball.create_tween().set_parallel(true)
	tween.tween_property(ball, "scale", Vector3.ONE * radius * 0.6, 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.tween_property(light, "light_energy", 0.0, 0.35)
	tween.chain().tween_callback(ball.queue_free)
	_spawn_sparks(position, Color(1.0, 0.6, 0.2), 28)
