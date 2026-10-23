class_name PvpScorer
extends RefCounted
## Listens for kills and writes PvP points into the Standings ledger using PvpRules. It only
## scores while the match director says PvP is on, only for players who are in the match, and
## never for suicides, environment deaths or monsters.

var enabled := false

var _events: EventBus
var _standings: Standings
var _config: MatchConfig
## Callable() -> int: the current cycle number.
var _get_cycle: Callable
## Callable() -> int: the player who wears the mark (0 if nobody).
var _get_marked: Callable


func setup(events: EventBus, standings: Standings, config: MatchConfig, get_cycle: Callable, get_marked: Callable) -> void:
	_events = events
	_standings = standings
	_config = config
	_get_cycle = get_cycle
	_get_marked = get_marked
	_events.kill_detail.connect(_on_kill_detail)


func set_config(config: MatchConfig) -> void:
	_config = config


func _on_kill_detail(victim_id: int, killer_id: int, weapon_id: StringName, distance: float,
		airborne: bool, full_power: bool, direct: bool) -> void:
	if not enabled or killer_id == 0 or killer_id == victim_id:
		return
	var members := _standings.player_ids()
	if not members.has(victim_id) or not members.has(killer_id):
		return
	var marked: bool = _get_marked.call() == victim_id
	var kill_class := PvpRules.classify(_config, weapon_id, distance, airborne, full_power, direct, marked)
	var moved := PvpRules.score_kill(_config, _standings, _get_cycle.call(), killer_id, victim_id, kill_class, marked)
	_events.pvp_kill_scored.emit(killer_id, victim_id, kill_class, moved.killer_gain, moved.victim_loss)
	_events.standings_changed.emit()
