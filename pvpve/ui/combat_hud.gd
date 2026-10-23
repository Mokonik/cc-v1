extends CanvasLayer
## The combat HUD: health, weapon and ammo, weapon slots, the action bar (reload, draw,
## cooldown), hit marker, kill feed, damage vignette and the respawn countdown.
## Presentation only: it reads combat state and listens to the EventBus.

const FEED_SECONDS := 4.5
const FEED_MAX := 5
const HIT_COLOR := Color(1.0, 1.0, 1.0)
const KILL_COLOR := Color(1.0, 0.25, 0.2)

@export var game: Game

var _health_fill: ColorRect
var _health_label: Label
var _weapon_label: Label
var _ammo_label: Label
var _slot_labels: Dictionary = {}
var _action_bar: ColorRect
var _action_fill: ColorRect
var _hit_marker: Control
var _hit_alpha := 0.0
var _hit_color := HIT_COLOR
var _feed: VBoxContainer
var _vignette: TextureRect
var _vignette_alpha := 0.0
var _death_overlay: ColorRect
var _death_label: Label
var _protect_label: Label
var _feed_entries: Array[Dictionary] = []


func _ready() -> void:
	_build_health()
	_build_weapon_panel()
	_build_action_bar()
	_build_hit_marker()
	_build_feed()
	_build_overlays()
	var events := game.events
	events.damage_dealt.connect(_on_damage_dealt)
	events.player_died.connect(_on_player_died)
	events.player_respawned.connect(func(pid: int) -> void:
		if pid == PlayerRegistry.HOST_ID:
			_vignette_alpha = 0.0)


func _process(delta: float) -> void:
	var vitals := game.combat.get_vitals(PlayerRegistry.HOST_ID)
	if vitals == null:
		return
	_update_health(vitals)
	_update_weapon(vitals)
	_update_overlays(vitals, delta)
	_update_feed(delta)
	_hit_alpha = maxf(_hit_alpha - delta * 4.0, 0.0)
	_hit_marker.modulate = Color(_hit_color.r, _hit_color.g, _hit_color.b, _hit_alpha)
	_hit_marker.queue_redraw()


# ---- updates ------------------------------------------------------------------------

func _update_health(vitals: Vitals) -> void:
	var fraction := clampf(vitals.hp / vitals.max_hp, 0.0, 1.0)
	_health_fill.size.x = 236.0 * fraction
	_health_fill.color = Color(0.9, 0.25, 0.2).lerp(Color(0.3, 0.85, 0.4), fraction)
	_health_label.text = "%d" % ceili(vitals.hp)


func _update_weapon(vitals: Vitals) -> void:
	var state := vitals.current()
	for slot: int in _slot_labels:
		var label: Label = _slot_labels[slot]
		var owned := vitals.weapons.has(slot)
		label.visible = owned
		label.modulate = Color(1.0, 0.9, 0.4) if slot == vitals.current_slot else Color(0.75, 0.75, 0.8, 0.8)
	if state == null:
		_weapon_label.text = ""
		_ammo_label.text = ""
		_action_bar.visible = false
		return
	var def := state.def
	var tick := game.combat.tick
	_weapon_label.text = def.display_name
	var progress := -1.0
	var ammo_text := ""
	if def.uses_ammo():
		ammo_text = "%d / %d" % [state.ammo, def.magazine]
	if state.is_reloading():
		var total := float(WeaponDef.seconds_to_ticks(def.reload_time))
		progress = 1.0 - float(state.reload_done_tick - tick) / total
		ammo_text = "RELOADING"
	elif state.is_drawing():
		progress = clampf(float(tick - state.draw_start_tick) / float(maxi(WeaponDef.seconds_to_ticks(def.draw_time), 1)), 0.0, 1.0)
		ammo_text = "DRAW"
	elif tick < state.next_fire_tick and def.fire_interval >= 1.0:
		var total := float(WeaponDef.seconds_to_ticks(def.fire_interval))
		progress = 1.0 - float(state.next_fire_tick - tick) / total
		ammo_text = "READY IN %.1f" % (float(state.next_fire_tick - tick) / Engine.physics_ticks_per_second)
	elif not def.uses_ammo():
		ammo_text = "READY"
	_ammo_label.text = ammo_text
	_action_bar.visible = progress >= 0.0
	if progress >= 0.0:
		_action_fill.size.x = _action_bar.size.x * clampf(progress, 0.0, 1.0)


func _update_overlays(vitals: Vitals, delta: float) -> void:
	_vignette_alpha = maxf(_vignette_alpha - delta * 1.6, 0.0)
	var low := clampf(1.0 - vitals.hp / (vitals.max_hp * 0.35), 0.0, 1.0) if vitals.alive else 0.0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	_vignette.modulate.a = clampf(_vignette_alpha + low * (0.25 + 0.2 * pulse), 0.0, 1.0)
	_death_overlay.visible = not vitals.alive
	if not vitals.alive:
		var remaining := maxf(float(vitals.respawn_tick - game.combat.tick) / Engine.physics_ticks_per_second, 0.0)
		_death_label.text = "YOU DIED\nRespawning in %.1f" % remaining
	_protect_label.visible = vitals.alive and game.combat.tick < vitals.protected_until_tick


func _update_feed(delta: float) -> void:
	for entry in _feed_entries:
		entry.age += delta
		var label: Label = entry.label
		label.modulate.a = clampf((FEED_SECONDS - entry.age) / 0.8, 0.0, 1.0)
	while not _feed_entries.is_empty() and _feed_entries[0].age >= FEED_SECONDS:
		_feed_entries[0].label.queue_free()
		_feed_entries.remove_at(0)


# ---- events --------------------------------------------------------------------------

func _on_damage_dealt(target_id: int, source_id: int, amount: float, _position: Vector3, _weapon: StringName) -> void:
	if source_id == PlayerRegistry.HOST_ID and target_id != source_id:
		_hit_alpha = 1.0
		_hit_color = HIT_COLOR
	if target_id == PlayerRegistry.HOST_ID:
		_vignette_alpha = clampf(_vignette_alpha + amount / 30.0, 0.35, 0.9)


func _on_player_died(victim_id: int, killer_id: int, weapon_id: StringName) -> void:
	if killer_id == PlayerRegistry.HOST_ID and victim_id != killer_id:
		_hit_alpha = 1.0
		_hit_color = KILL_COLOR
	var def := game.weapons.get_def(weapon_id)
	var weapon_name := def.display_name if def != null else str(weapon_id)
	var victim := _name_of(victim_id)
	var text := "%s died" % victim
	if killer_id != 0 and killer_id != victim_id:
		text = "%s  >  %s   [%s]" % [_name_of(killer_id), victim, weapon_name]
	_push_feed(text, killer_id == PlayerRegistry.HOST_ID or victim_id == PlayerRegistry.HOST_ID)


func _name_of(player_id: int) -> String:
	var record := game.registry.get_record(player_id)
	return record.display_name if record != null else "Player %d" % player_id


func _push_feed(text: String, involves_you: bool) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 5)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.5) if involves_you else Color(0.9, 0.9, 0.95))
	_feed.add_child(label)
	_feed_entries.append({"label": label, "age": 0.0})
	while _feed_entries.size() > FEED_MAX:
		_feed_entries[0].label.queue_free()
		_feed_entries.remove_at(0)


# ---- construction ------------------------------------------------------------------

func _anchored(control: Control, preset: int, offset := Vector2.ZERO) -> Control:
	add_child(control)
	control.set_anchors_and_offsets_preset(preset)
	control.position += offset
	return control


func _styled_label(font_size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 6)
	return label


func _build_health() -> void:
	var panel := Control.new()
	panel.custom_minimum_size = Vector2(260.0, 40.0)
	_anchored(panel, Control.PRESET_BOTTOM_LEFT, Vector2(24.0, -64.0))
	var back := ColorRect.new()
	back.color = Color(0.0, 0.0, 0.0, 0.55)
	back.size = Vector2(260.0, 30.0)
	panel.add_child(back)
	_health_fill = ColorRect.new()
	_health_fill.position = Vector2(12.0, 6.0)
	_health_fill.size = Vector2(236.0, 18.0)
	panel.add_child(_health_fill)
	_health_label = _styled_label(16)
	_health_label.position = Vector2(18.0, 0.0)
	panel.add_child(_health_label)


func _build_weapon_panel() -> void:
	var panel := VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_END
	_anchored(panel, Control.PRESET_BOTTOM_RIGHT, Vector2(-260.0, -110.0))
	panel.size = Vector2(236.0, 90.0)
	_weapon_label = _styled_label(26, Color(1.0, 0.95, 0.8))
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_weapon_label)
	_ammo_label = _styled_label(20)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_ammo_label)

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override(&"separation", 14)
	_anchored(slots, Control.PRESET_CENTER_BOTTOM, Vector2(-120.0, -48.0))
	for def in game.weapons.all():
		var label := _styled_label(15)
		label.text = "%d %s" % [def.slot, def.display_name]
		slots.add_child(label)
		_slot_labels[def.slot] = label


func _build_action_bar() -> void:
	_action_bar = ColorRect.new()
	_action_bar.color = Color(0.0, 0.0, 0.0, 0.5)
	_action_bar.size = Vector2(90.0, 5.0)
	_anchored(_action_bar, Control.PRESET_CENTER, Vector2(-45.0, 32.0))
	_action_bar.size = Vector2(90.0, 5.0)
	_action_fill = ColorRect.new()
	_action_fill.color = Color(1.0, 0.85, 0.35)
	_action_fill.size = Vector2(0.0, 5.0)
	_action_bar.add_child(_action_fill)


func _build_hit_marker() -> void:
	_hit_marker = Control.new()
	_hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchored(_hit_marker, Control.PRESET_CENTER)
	_hit_marker.draw.connect(func() -> void:
		var near := 7.0
		var far := 15.0
		for sign_x in [-1.0, 1.0]:
			for sign_y in [-1.0, 1.0]:
				_hit_marker.draw_line(Vector2(sign_x, sign_y) * near, Vector2(sign_x, sign_y) * far, Color.WHITE, 2.5))


func _build_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchored(_feed, Control.PRESET_TOP_RIGHT, Vector2(-420.0, 16.0))
	_feed.size = Vector2(400.0, 160.0)


func _build_overlays() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.8, 0.0, 0.0, 0.0))
	gradient.set_color(1, Color(0.8, 0.0, 0.0, 0.75))
	gradient.set_offset(0, 0.45)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = texture
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_anchored(_vignette, Control.PRESET_FULL_RECT)

	_death_overlay = ColorRect.new()
	_death_overlay.color = Color(0.0, 0.0, 0.0, 0.4)
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.visible = false
	_anchored(_death_overlay, Control.PRESET_FULL_RECT)
	_death_label = _styled_label(42, Color(1.0, 0.85, 0.8))
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_overlay.add_child(_death_label)
	_death_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_protect_label = _styled_label(16, Color(0.5, 0.85, 1.0))
	_protect_label.text = "SPAWN PROTECTION"
	_protect_label.visible = false
	_anchored(_protect_label, Control.PRESET_CENTER_TOP, Vector2(-80.0, 54.0))
