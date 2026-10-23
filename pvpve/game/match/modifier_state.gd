class_name ModifierState
extends RefCounted
## Which world modifier is active, who picked it, and who it applies to. The rest of the game asks
## aggregate_for(player_id) and never looks at modifier ids directly.

var modifier_id: StringName = &""
var picker_id := 0
var scope := MatchConfig.ModifierScope.EVERYONE

var _catalog: ModifierCatalog
var _neutral := ModifierAggregate.new()
var _active: ModifierAggregate = _neutral


func _init(catalog: ModifierCatalog) -> void:
	_catalog = catalog


func is_active() -> bool:
	return modifier_id != &""


## Activates a modifier (or clears it with an empty id). Returns false for an unknown id.
func set_active(id: StringName, by_player: int, p_scope := MatchConfig.ModifierScope.EVERYONE) -> bool:
	if id == &"":
		clear()
		return true
	var def := _catalog.get_def(id)
	if def == null:
		return false
	modifier_id = id
	picker_id = by_player
	scope = p_scope
	_active = ModifierAggregate.new()
	_active.add(def)
	return true


func clear() -> void:
	modifier_id = &""
	picker_id = 0
	_active = _neutral


## What applies to this player: everyone, or everyone except the picker.
func aggregate_for(player_id: int) -> ModifierAggregate:
	if not is_active():
		return _neutral
	if scope == MatchConfig.ModifierScope.OPPONENTS and player_id == picker_id:
		return _neutral
	return _active
