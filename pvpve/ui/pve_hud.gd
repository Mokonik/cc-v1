extends CanvasLayer
## HUD for the PvE phase and progression: phase timer and wave counter, the boss bar, XP and
## level, consumables and Sabotage Points, toasts, the level-up perk offer and the results
## screen. Presentation only: it reads game state and listens to the EventBus.

const TOAST_SECONDS := 3.2
const TOAST_MAX := 5
const RESULTS_SECONDS := 14.0
const XP_BAR_WIDTH := 260.0

@export var game: Game

var _phase_label: Label
var _info_label: Label
var _boss_panel: Control
var _boss_name: Label
var _boss_fill: ColorRect
var _boss_width := 560.0
var _level_label: Label
var _xp_fill: ColorRect
var _items_label: Label
var _toasts: VBoxContainer
var _toast_entries: Array[Dictionary] = []
var _offer_panel: PanelContainer
var _offer_label: Label
var _results_panel: PanelContainer
var _results_label: Label
var _results_timer := 0.0


func _ready() -> void:
	_build_top()
	_build_boss_bar()
	_build_progress()
	_build_toasts()
	_build_offer()
	_build_results()
	var events := game.events
	events.pve_phase.connect(_on_phase)
	events.pve_wave.connect(_on_wave)
	events.pve_finished.connect(_on_finished)
	events.level_up.connect(func(pid: int, level: int) -> void:
		if pid == PlayerRegistry.HOST_ID:
			_toast("LEVEL %d!  Choose a perk: Z, X or C" % level, Color(1.0, 0.9, 0.4)))
	events.perk_picked.connect(func(pid: int, perk_id: StringName) -> void:
		if pid == PlayerRegistry.HOST_ID:
			_toast("Perk: %s" % game.perk_defs.get_def(perk_id).display_name, Color(0.6, 1.0, 0.7)))
	events.loot_picked_up.connect(func(pid: int, _d: int, _k: int, label: String) -> void:
		if pid == PlayerRegistry.HOST_ID:
			_toast("+ %s" % label, Color(0.8, 0.95, 1.0)))
	events.weapon_tier_changed.connect(func(pid: int, weapon_id: StringName, tier: int) -> void:
		if pid == PlayerRegistry.HOST_ID:
			_toast("%s upgraded to tier %d" % [game.weapons.get_def(weapon_id).display_name, tier], Color(1.0, 0.8, 0.3)))
	events.weapon_given.connect(func(pid: int, weapon_id: StringName) -> void:
		if pid == PlayerRegistry.HOST_ID and weapon_id != WeaponCatalog.STARTER:
			var def := game.weapons.get_def(weapon_id)
			_toast("Unlocked %s (key %d)" % [def.display_name, def.slot], Color(1.0, 0.8, 0.3)))
	events.item_used.connect(func(pid: int, item: StringName, amount: float) -> void:
		if pid == PlayerRegistry.HOST_ID and item == &"health":
			_toast("Healed %d" % roundi(amount), Color(0.4, 1.0, 0.5)))
	events.trap_triggered.connect(func(_t: int, victim: int, _p: Vector3) -> void:
		if victim != PlayerRegistry.HOST_ID:
			_toast("Your trap caught someone!", Color(0.95, 0.5, 0.95)))


func _process(delta: float) -> void:
	var id := PlayerRegistry.HOST_ID
	_update_phase(id)
	_update_boss(id)
	_update_progress(id)
	_update_offer(id)
	_update_toasts(delta)
	if _results_timer > 0.0:
		_results_timer -= delta
		_results_panel.visible = _results_timer > 0.0


# ---- updates ---------------------------------------------------------------------------------

func _update_phase(id: int) -> void:
	var run := game.pve.get_run(id)
	if run == null:
		_phase_label.text = ""
		_info_label.text = ""
		return
	var seconds := game.pve.seconds_left(id)
	var name := String(game.pve.phase_name(run))
	var minutes := int(seconds) / 60
	var clock := "%d:%02d" % [minutes, int(seconds) % 60]
	match name:
		"countdown":
			_phase_label.text = "GET READY  %d" % ceili(seconds)
		"waves":
			_phase_label.text = "SURVIVE  %s" % clock
		"boss":
			_phase_label.text = "BOSS  %s" % clock
	_info_label.text = "Wave %d   |   %d monsters   |   %d kills   |   %d deaths" % [
		run.waves_started, game.monsters.count_owned_by(id), run.result.kill_count(), run.result.deaths]


func _update_boss(id: int) -> void:
	var run := game.pve.get_run(id)
	var boss_id := run.boss_monster_id if run != null else 0
	var vitals := game.combat.get_vitals(boss_id) if boss_id != 0 else null
	_boss_panel.visible = vitals != null and vitals.alive
	if not _boss_panel.visible:
		return
	var record := game.monsters.get_record(boss_id)
	var fraction := clampf(vitals.hp / vitals.max_hp, 0.0, 1.0)
	_boss_fill.size.x = (_boss_width - 4.0) * fraction
	var enraged := record != null and record.brain.enraged
	_boss_fill.color = Color(1.0, 0.25, 0.2) if enraged else Color(0.8, 0.3, 0.6)
	_boss_name.text = "%s%s" % [record.def.display_name.to_upper() if record != null else "BOSS", "  (ENRAGED)" if enraged else ""]


func _update_progress(id: int) -> void:
	var state := game.progression.get_state(id)
	var inventory := game.loot.get_inventory(id)
	if state == null:
		return
	_level_label.text = "LV %d" % state.level
	_xp_fill.size.x = (XP_BAR_WIDTH - 4.0) * clampf(float(state.xp_into_level()) / float(state.xp_needed()), 0.0, 1.0)
	_items_label.text = "F Health x%d     G Trap x%d     Sabotage %d" % [inventory.health_packs, inventory.traps, state.sabotage_points]


func _update_offer(id: int) -> void:
	var state := game.progression.get_state(id)
	_offer_panel.visible = state != null and state.has_pending_offer() and game.combat.is_alive(id)
	if not _offer_panel.visible:
		return
	var offer: Array = state.offers[0]
	var keys := ["Z", "X", "C"]
	var lines: Array[String] = ["LEVEL UP: choose a perk%s" % ("   (%d more waiting)" % (state.offers.size() - 1) if state.offers.size() > 1 else "")]
	for i in offer.size():
		var def := game.perk_defs.get_def(offer[i])
		lines.append("[%s]  %s  (%d/%d)  -  %s" % [keys[i], def.display_name, state.stacks_of(def.id), def.max_stacks, def.description])
	_offer_label.text = "\n".join(lines)


func _update_toasts(delta: float) -> void:
	for entry in _toast_entries:
		entry.age += delta
		var label: Label = entry.label
		label.modulate.a = clampf((TOAST_SECONDS - entry.age) / 0.6, 0.0, 1.0)
	while not _toast_entries.is_empty() and _toast_entries[0].age >= TOAST_SECONDS:
		_toast_entries[0].label.queue_free()
		_toast_entries.remove_at(0)


# ---- events -----------------------------------------------------------------------------------

func _on_phase(owner_id: int, phase_name: StringName, _seconds: float) -> void:
	if owner_id != PlayerRegistry.HOST_ID:
		return
	match phase_name:
		&"waves":
			_toast("The gates open. Survive!", Color(1.0, 0.7, 0.4))
		&"boss":
			_toast("The Warden approaches...", Color(0.9, 0.4, 0.9))


func _on_wave(owner_id: int, wave: int, count: int) -> void:
	if owner_id == PlayerRegistry.HOST_ID:
		_toast("Wave %d: %d monsters" % [wave, count], Color(1.0, 0.85, 0.6))


func _on_finished(owner_id: int, result: PveResult, reason: StringName) -> void:
	if owner_id != PlayerRegistry.HOST_ID:
		return
	var headline: String = {
		&"boss_defeated": "VICTORY",
		&"boss_timeout": "THE WARDEN SURVIVED",
		&"time_up": "TIME'S UP",
		&"stopped": "PHASE ENDED",
	}.get(reason, "PHASE OVER")
	var lines: Array[String] = [headline, ""]
	lines.append("Score        %d" % result.score)
	lines.append("Kills        %d" % result.kill_count())
	lines.append("Boss         %s" % ("defeated in %.0f s" % result.boss_time_seconds if result.boss_defeated else "standing"))
	lines.append("Deaths       %d" % result.deaths)
	lines.append("Waves        %d   (difficulty %.2f)" % [result.waves_survived, result.difficulty])
	lines.append("XP earned    %d" % result.xp)
	lines.append("Sabotage     +%d" % result.sabotage_points)
	if not result.loot.is_empty():
		lines.append("Loot         %s" % ", ".join(result.loot.slice(0, 6)))
	_results_label.text = "\n".join(lines)
	_results_panel.visible = true
	_results_timer = RESULTS_SECONDS


func _toast(text: String, color := Color.WHITE) -> void:
	var label := UiKit.label(20, color)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toasts.add_child(label)
	_toast_entries.append({"label": label, "age": 0.0})
	while _toast_entries.size() > TOAST_MAX:
		_toast_entries[0].label.queue_free()
		_toast_entries.remove_at(0)


# ---- construction ------------------------------------------------------------------------------

func _build_top() -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	UiKit.anchored(self, column, Control.PRESET_CENTER_TOP, Vector2(-300.0, 14.0))
	column.size = Vector2(600.0, 60.0)
	_phase_label = UiKit.label(34, Color(1.0, 0.92, 0.7))
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_phase_label)
	_info_label = UiKit.label(17)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_info_label)


func _build_boss_bar() -> void:
	_boss_panel = Control.new()
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.anchored(self, _boss_panel, Control.PRESET_CENTER_TOP, Vector2(-_boss_width * 0.5, 96.0))
	_boss_panel.visible = false
	_boss_name = UiKit.label(22, Color(1.0, 0.85, 0.9))
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.size = Vector2(_boss_width, 28.0)
	_boss_panel.add_child(_boss_name)
	var parts := UiKit.bar(Vector2(_boss_width, 22.0), Color(0.8, 0.3, 0.6))
	parts[0].position = Vector2(0.0, 32.0)
	_boss_panel.add_child(parts[0])
	_boss_fill = parts[1]


func _build_progress() -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.anchored(self, holder, Control.PRESET_BOTTOM_LEFT, Vector2(24.0, -128.0))
	_items_label = UiKit.label(16, Color(0.9, 0.95, 1.0))
	_items_label.position = Vector2(0.0, -26.0)
	holder.add_child(_items_label)
	var parts := UiKit.bar(Vector2(XP_BAR_WIDTH, 12.0), Color(0.4, 0.75, 1.0))
	holder.add_child(parts[0])
	_xp_fill = parts[1]
	_level_label = UiKit.label(15, Color(0.7, 0.88, 1.0))
	_level_label.position = Vector2(XP_BAR_WIDTH + 8.0, -6.0)
	holder.add_child(_level_label)


func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.anchored(self, _toasts, Control.PRESET_CENTER_BOTTOM, Vector2(-250.0, -260.0))
	_toasts.size = Vector2(500.0, 140.0)
	_toasts.alignment = BoxContainer.ALIGNMENT_END


func _build_offer() -> void:
	_offer_panel = UiKit.panel(Color(0.05, 0.06, 0.1, 0.9))
	UiKit.anchored(self, _offer_panel, Control.PRESET_CENTER, Vector2(-380.0, 70.0))
	_offer_panel.visible = false
	_offer_label = UiKit.label(19, Color(1.0, 0.97, 0.85))
	_offer_panel.add_child(_offer_label)


func _build_results() -> void:
	_results_panel = UiKit.panel(Color(0.04, 0.05, 0.08, 0.92))
	UiKit.anchored(self, _results_panel, Control.PRESET_CENTER, Vector2(-190.0, -260.0))
	_results_panel.visible = false
	_results_label = UiKit.label(22, Color(1.0, 0.96, 0.85))
	_results_panel.add_child(_results_label)
