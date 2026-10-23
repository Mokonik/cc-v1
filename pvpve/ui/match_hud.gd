class_name MatchHud
extends CanvasLayer
## HUD for the match loop: phase banner and clock, the standings table, the PvE results, the
## wager menu, the modifier card picker, PvP callouts (skill kills and the table flip), the
## storm warning and the victory screen. Presentation only: it reads game state and listens
## to the EventBus. Menu keys are Z, X and C, routed by the match director.

const CALLOUT_SECONDS := 3.0
const FLASH_SECONDS := 0.9
const PHASE_NAMES := {
	&"pve": "PVE PHASE",
	&"pve_results": "PVE RESULTS",
	&"wager": "PLACE YOUR WAGER",
	&"pvp_countdown": "PVP STARTS",
	&"pvp": "PVP",
	&"pvp_results": "PVP RESULTS",
	&"final": "THE FINAL",
	&"victory": "CHAMPION",
}
const KEYS := ["Z", "X", "C"]
const GOLD := Color(1.0, 0.82, 0.25)

@export var game: Game

var _banner: Label
var _clock: Label
var _standings_panel: PanelContainer
var _standings_label: Label
var _menu_panel: PanelContainer
var _menu_label: Label
var _callouts: VBoxContainer
var _callout_entries: Array[Dictionary] = []
var _flash: ColorRect
var _flash_time := 0.0
var _storm_label: Label


func _ready() -> void:
	_build()
	var events := game.events
	events.pvp_kill_scored.connect(_on_kill_scored)
	events.mark_changed.connect(func(player_id: int) -> void:
		if player_id != 0:
			_callout("%s is MARKED: harder PvE, bounty in PvP" % _name_of(player_id), GOLD))
	events.modifier_chosen.connect(func(picker_id: int, modifier_id: StringName) -> void:
		_callout("%s chose %s for everyone's next PvE" % [_name_of(picker_id), game.modifier_defs.get_def(modifier_id).display_name], Color(0.7, 0.9, 1.0)))
	events.wager_settled.connect(func(net: Dictionary) -> void:
		var mine: int = net.get(PlayerRegistry.HOST_ID, 0)
		if mine != 0:
			_callout("Wager: %+d points" % mine, Color(0.6, 1.0, 0.7) if mine > 0 else Color(1.0, 0.55, 0.5)))
	events.match_phase.connect(func(phase: StringName, cycle: int, _seconds: float) -> void:
		if phase == MatchDirector.PVP_COUNTDOWN:
			_callout("Cycle %d: get to the arena!" % cycle, Color(1.0, 0.7, 0.4)))


func _process(delta: float) -> void:
	var director := game.match_director
	var active := director.is_running()
	_banner.visible = active
	_clock.visible = active
	_standings_panel.visible = active
	if not active:
		_menu_panel.visible = false
		_storm_label.visible = false
	else:
		_update_banner(director)
		_update_menu(director)
		_update_storm(director)
	_update_standings(director)
	_update_callouts(delta)
	if _flash_time > 0.0:
		_flash_time -= delta
		_flash.color.a = clampf(_flash_time / FLASH_SECONDS, 0.0, 1.0) * 0.55
	_flash.visible = _flash_time > 0.0


# ---- updates ---------------------------------------------------------------------------------

func _update_banner(director: MatchDirector) -> void:
	var cycle_text := "FINAL" if director.phase in [MatchDirector.FINAL, MatchDirector.VICTORY] \
			else "CYCLE %d / %d" % [mini(director.cycle, director.config.cycles), director.config.cycles]
	_banner.text = "%s   %s" % [cycle_text, PHASE_NAMES.get(director.phase, "")]
	if director.phase == MatchDirector.PVE and game.pve.is_running(PlayerRegistry.HOST_ID):
		_clock.text = ""
	else:
		var seconds := ceili(director.seconds_left())
		_clock.text = "%d:%02d" % [seconds / 60, seconds % 60]


func _update_standings(director: MatchDirector) -> void:
	var standings := director.standings
	if standings.player_ids().is_empty():
		return
	var lines: Array[String] = ["STANDINGS"]
	for id in standings.ranking():
		var line := "%d.  %-10s %5d" % [standings.rank_of(id), _name_of(id), standings.total(id)]
		if id == director.marked_id:
			line += "  ★"
		if id == PlayerRegistry.HOST_ID:
			line = "> " + line
		lines.append(line)
	_standings_label.text = "\n".join(lines)


func _update_menu(director: MatchDirector) -> void:
	var lines: Array[String] = []
	match director.phase:
		MatchDirector.PVE_RESULTS:
			lines = _pve_results_lines(director)
		MatchDirector.WAGER:
			lines = _wager_lines(director)
		MatchDirector.PVP_COUNTDOWN:
			lines = ["Weapons unlock in %d..." % ceili(director.seconds_left())]
		MatchDirector.PVP_RESULTS:
			lines = _pvp_results_lines(director)
		MatchDirector.VICTORY:
			lines = _victory_lines(director)
	_menu_panel.visible = not lines.is_empty()
	_menu_label.text = "\n".join(lines)


func _pve_results_lines(director: MatchDirector) -> Array[String]:
	var lines: Array[String] = ["PVE RESULTS  (cycle %d)" % director.cycle, ""]
	var results: Dictionary = director.pve_results.get(director.cycle, {})
	var ids: Array = results.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return results[a].score > results[b].score)
	for id: int in ids:
		var result: PveResult = results[id]
		lines.append("%-10s %5d   %d kills   %s" % [_name_of(id), result.score, result.kill_count(),
			"boss down" if result.boss_defeated else "boss standing"])
	return lines


func _wager_lines(director: MatchDirector) -> Array[String]:
	var total := director.standings.total(PlayerRegistry.HOST_ID)
	var lines: Array[String] = ["PLACE YOUR WAGER", "Stake standings points on how you place in PvP. The pot is paid out by placement.", ""]
	var chosen: int = director.wager_choices.get(PlayerRegistry.HOST_ID, 0)
	for i in director.config.stake_options.size():
		var stake := director.config.stake_for(total, i)
		var text := "[%s]  %s" % [KEYS[i], "Play it safe" if stake == 0 else "Stake %d points (%d%%)" % [stake, roundi(director.config.stake_options[i] * 100.0)]]
		lines.append(("> " if i == chosen else "   ") + text)
	lines.append("")
	lines.append("%d s left" % ceili(director.seconds_left()))
	return lines


func _pvp_results_lines(director: MatchDirector) -> Array[String]:
	var lines: Array[String] = ["PVP RESULTS", ""]
	var place := 1
	for id in director.pvp_placement:
		var wager: int = director.last_wager_net.get(id, 0)
		lines.append("%d.  %-10s %+4d PvP    wager %+d" % [place, _name_of(id), director.standings.pvp_points(id, director.cycle), wager])
		place += 1
	lines.append("")
	if not director.offer_cards.is_empty():
		if director.offer_picker == PlayerRegistry.HOST_ID:
			lines.append("YOU WON: choose a world modifier for everyone's next PvE")
			for i in director.offer_cards.size():
				var def := game.modifier_defs.get_def(director.offer_cards[i])
				lines.append("[%s]  %s  -  %s" % [KEYS[i], def.display_name, def.description])
		else:
			lines.append("%s is choosing a world modifier..." % _name_of(director.offer_picker))
	elif game.modifiers.is_active():
		lines.append("Next PvE: %s" % game.modifier_defs.get_def(game.modifiers.modifier_id).display_name)
	return lines


func _victory_lines(director: MatchDirector) -> Array[String]:
	var standings := director.standings
	var lines: Array[String] = ["%s WINS THE MATCH" % _name_of(director.champion_id).to_upper(), "",
		"%-10s %6s %6s %6s %6s %6s" % ["", "PvE", "PvP", "Wager", "Final", "Total"]]
	for id in standings.ranking():
		lines.append("%-10s %6d %6d %6d %6d %6d" % [_name_of(id), standings.sum_kinds(id, [&"pve"]),
			standings.sum_kinds(id, Standings.PVP_KINDS), standings.sum_kinds(id, [&"wager"]),
			standings.sum_kinds(id, [&"final"]), standings.total(id)])
	return lines


func _update_storm(director: MatchDirector) -> void:
	var player := game.get_player(PlayerRegistry.HOST_ID)
	var outside := false
	if director.phase == MatchDirector.FINAL and player != null and game.combat.is_alive(PlayerRegistry.HOST_ID):
		outside = Vector2(player.global_position.x, player.global_position.z).length() > director.safe_radius
		_storm_label.text = "OUTSIDE THE SAFE AREA!" if outside else "Safe area: %.0f m" % director.safe_radius
		_storm_label.add_theme_color_override(&"font_color", Color(1.0, 0.35, 0.3) if outside else Color(0.8, 0.9, 1.0))
	_storm_label.visible = director.phase == MatchDirector.FINAL and player != null


func _update_callouts(delta: float) -> void:
	for entry in _callout_entries:
		entry.age += delta
		var label: Label = entry.label
		label.modulate.a = clampf((CALLOUT_SECONDS - entry.age) / 0.7, 0.0, 1.0)
	while not _callout_entries.is_empty() and _callout_entries[0].age >= CALLOUT_SECONDS:
		_callout_entries[0].label.queue_free()
		_callout_entries.remove_at(0)


# ---- events -----------------------------------------------------------------------------------

func _on_kill_scored(killer_id: int, victim_id: int, kill_class: int, gain: int, loss: int) -> void:
	var mine := killer_id == PlayerRegistry.HOST_ID or victim_id == PlayerRegistry.HOST_ID
	match kill_class:
		PvpRules.KillClass.SHOWSTOPPER:
			_flash_time = FLASH_SECONDS
			_flash.color = Color(1.0, 0.85, 0.3, 0.55)
			_callout("TABLE FLIP!  %s took down %s  (%+d / %d)" % [_name_of(killer_id), _name_of(victim_id), gain, -loss], GOLD, 30)
		PvpRules.KillClass.SKILL:
			_callout("SKILL KILL  %s  %+d  (stole %d from %s)" % [_name_of(killer_id), gain, loss, _name_of(victim_id)], Color(1.0, 0.6, 0.3), 24)
		_:
			if mine:
				var who := "Kill" if killer_id == PlayerRegistry.HOST_ID else "Killed by %s" % _name_of(killer_id)
				_callout("%s  %+d" % [who, gain], Color(0.9, 0.95, 1.0))


func _callout(text: String, color := Color.WHITE, size := 20) -> void:
	var label := UiKit.label(size, color)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callouts.add_child(label)
	_callout_entries.append({"label": label, "age": 0.0})
	while _callout_entries.size() > 4:
		_callout_entries[0].label.queue_free()
		_callout_entries.remove_at(0)


func _name_of(player_id: int) -> String:
	var record := game.registry.get_record(player_id)
	return record.display_name if record != null else "Player %d" % player_id


# ---- construction ------------------------------------------------------------------------------

func _build() -> void:
	_banner = UiKit.label(24, Color(1.0, 0.92, 0.7))
	UiKit.anchored(self, _banner, Control.PRESET_TOP_LEFT, Vector2(24.0, 214.0))
	_clock = UiKit.label(30)
	UiKit.anchored(self, _clock, Control.PRESET_TOP_LEFT, Vector2(24.0, 244.0))

	_standings_panel = UiKit.panel(Color(0.04, 0.05, 0.08, 0.7))
	UiKit.anchored(self, _standings_panel, Control.PRESET_TOP_LEFT, Vector2(24.0, 296.0))
	_standings_label = UiKit.label(17, Color(0.95, 0.97, 1.0))
	_standings_panel.add_child(_standings_label)

	_menu_panel = UiKit.panel(Color(0.04, 0.05, 0.08, 0.93))
	UiKit.anchored(self, _menu_panel, Control.PRESET_CENTER, Vector2(-330.0, -90.0))
	_menu_panel.visible = false
	_menu_label = UiKit.label(21, Color(1.0, 0.97, 0.88))
	_menu_panel.add_child(_menu_label)

	_callouts = VBoxContainer.new()
	_callouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.anchored(self, _callouts, Control.PRESET_CENTER_TOP, Vector2(-380.0, 110.0))
	_callouts.size = Vector2(760.0, 140.0)

	_storm_label = UiKit.label(24)
	_storm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.anchored(self, _storm_label, Control.PRESET_CENTER_TOP, Vector2(-200.0, 80.0))
	_storm_label.size = Vector2(400.0, 30.0)
	_storm_label.visible = false

	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	UiKit.anchored(self, _flash, Control.PRESET_FULL_RECT)
