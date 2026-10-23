class_name MonsterSystem
extends RefCounted
## Owns every monster: spawning, thinking, moving, attacking and removal. Monsters are
## combatants like players (ids from FIRST_ID so they never collide with player ids), so all
## damage goes through CombatSystem. Each tick it asks a MonsterBrain what to do and
## applies the answer.

const FIRST_ID := 1000
const SEPARATION_RADIUS := 1.5
const REPATH_TICKS := 15
const SPAWN_SUMMON_RING := 3.5
const MELEE_REACH_SLACK := 1.3
const AIM_HEIGHT := 1.1

class Record extends RefCounted:
	var id := 0
	var def: MonsterDef
	var node: Monster
	var brain: MonsterBrain
	var agent: NavigationAgent3D
	## The player whose PvE zone this monster belongs to; 0 means it hunts the nearest player.
	var owner_id := 0
	var damage_mult := 1.0
	var wave := 1
	var dead := false

## monster id -> Record
var records: Dictionary = {}

var _events: EventBus
var _combat: CombatSystem
var _catalog: MonsterCatalog
var _root: Node3D
## Callable() -> Array[Player]: living players a monster may hunt.
var _list_players: Callable
## Callable(id) -> Player or null.
var _get_player: Callable
## Callable(owner_id) -> ModifierAggregate: world modifiers that apply to that zone's monsters.
var get_modifier: Callable
var _neutral := ModifierAggregate.new()
var _seed := 1
var _next_id := FIRST_ID
var _removals: Array[int] = []


func setup(events: EventBus, combat: CombatSystem, catalog: MonsterCatalog, root: Node3D,
		list_players: Callable, get_player: Callable) -> void:
	_events = events
	_combat = combat
	_catalog = catalog
	_root = root
	_list_players = list_players
	_get_player = get_player


func set_seed(value: int) -> void:
	_seed = value


func catalog() -> MonsterCatalog:
	return _catalog


func count() -> int:
	var total := 0
	for id: int in records:
		if not records[id].dead:
			total += 1
	return total


func count_owned_by(owner_id: int) -> int:
	var total := 0
	for id: int in records:
		var record: Record = records[id]
		if not record.dead and record.owner_id == owner_id:
			total += 1
	return total


func get_body(id: int) -> Monster:
	var record: Record = records.get(id)
	return record.node if record != null and is_instance_valid(record.node) else null


func get_record(id: int) -> Record:
	return records.get(id)


## Spawns a monster and returns its id, or 0 if the monster type is unknown.
func spawn(def_id: StringName, position: Vector3, owner_id := 0, hp_mult := 1.0, damage_mult := 1.0, wave := 1) -> int:
	var def := _catalog.get_def(def_id)
	if def == null:
		return 0
	var record := Record.new()
	record.id = _next_id
	_next_id += 1
	record.def = def
	record.owner_id = owner_id
	record.damage_mult = damage_mult
	record.wave = wave

	record.node = Monster.new()
	record.node.entity_id = record.id
	record.node.setup(def)
	_root.add_child(record.node)
	record.node.global_position = position

	record.agent = NavigationAgent3D.new()
	record.agent.path_desired_distance = 0.7
	record.agent.target_desired_distance = 1.0
	record.agent.radius = maxf(def.radius, 0.4)
	record.agent.height = def.height
	record.agent.avoidance_enabled = false
	record.node.add_child(record.agent)

	record.brain = MonsterBrain.new(def, record.id)
	record.brain.start(_combat.tick, _seed)
	_combat.register_monster(record.id, def.id, def.max_hp * hp_mult)
	records[record.id] = record
	_events.monster_spawned.emit(record.id, def.id, position)
	return record.id


## Called when a monster dies: it stops acting at once and is cleaned up at the end of the tick.
func mark_dead(monster_id: int) -> void:
	var record: Record = records.get(monster_id)
	if record != null and not record.dead:
		record.dead = true
		_removals.append(monster_id)


func clear_all() -> int:
	var removed := 0
	for id: int in records.keys():
		var record: Record = records[id]
		if is_instance_valid(record.node):
			record.node.queue_free()
		_combat.unregister(id)
		removed += 1
	records.clear()
	_removals.clear()
	return removed


## Removes (and frees) every monster that belongs to a player's zone.
func clear_owned_by(owner_id: int) -> int:
	var removed := 0
	for id: int in records.keys():
		var record: Record = records[id]
		if record.owner_id != owner_id:
			continue
		if is_instance_valid(record.node):
			record.node.queue_free()
		_combat.unregister(id)
		records.erase(id)
		removed += 1
	return removed


func step(tick: int) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	var ids: Array = records.keys()
	ids.sort()
	for id: int in ids:
		var record: Record = records.get(id)
		if record == null or record.dead or not is_instance_valid(record.node):
			continue
		var vitals := _combat.get_vitals(id)
		if vitals == null or not vitals.alive:
			continue
		_think(record, vitals, tick, dt)
	_purge()


func _purge() -> void:
	for id in _removals:
		var record: Record = records.get(id)
		if record != null:
			records.erase(id)
		_combat.unregister(id)
	_removals.clear()


func _think(record: Record, vitals: Vitals, tick: int, dt: float) -> void:
	var node := record.node
	var def := record.def
	var target := _pick_target(record)
	var has_target := target != null
	var target_pos := target.global_position if has_target else node.global_position
	var has_los := false
	if has_target:
		has_los = _line_of_sight(node, target)
		if (tick + record.id) % REPATH_TICKS == 0:
			record.agent.target_position = target_pos
	var waypoint := target_pos
	if has_target and record.agent.get_current_navigation_path().size() > 1:
		waypoint = record.agent.get_next_path_position()

	var modifiers: ModifierAggregate = get_modifier.call(record.owner_id) if get_modifier.is_valid() else _neutral
	record.brain.range_mult = modifiers.range_mult
	var command := record.brain.think(tick, node.global_position, node.rotation.y, target_pos, has_target,
		has_los, waypoint, _separation(record), vitals.hp / vitals.max_hp, node.hit_wall)
	node.face(command.yaw, dt)
	node.simulate(command.move * command.speed * modifiers.speed_mult, dt)

	if command.telegraph != &"":
		_events.monster_telegraph.emit(record.id, command.telegraph, command.telegraph_seconds)
	if command.strike != &"" and has_target:
		_strike(record, command.strike, target)
	if command.summon:
		_summon(record)


## The player a monster hunts: the zone owner, or the nearest living player in sight.
func _pick_target(record: Record) -> Player:
	if record.owner_id != 0:
		var owner: Player = _get_player.call(record.owner_id)
		return owner if owner != null and _combat.is_alive(record.owner_id) else null
	var best: Player = null
	var best_distance := record.def.sight_range * record.def.sight_range
	for candidate: Player in _list_players.call():
		var distance := record.node.global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func _line_of_sight(node: Monster, target: Player) -> bool:
	var space := node.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(node.eye_position(), target.chest_position(), CombatLayers.WORLD)
	return space.intersect_ray(query).is_empty()


## Pushes a monster away from close neighbors so a pack spreads out instead of stacking.
func _separation(record: Record) -> Vector3:
	var push := Vector3.ZERO
	var here := record.node.global_position
	var reach := SEPARATION_RADIUS * maxf(record.def.radius / 0.4, 1.0)
	for other_id: int in records:
		if other_id == record.id:
			continue
		var other: Record = records[other_id]
		if other.dead or not is_instance_valid(other.node):
			continue
		var offset := here - other.node.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < reach:
			if distance < 0.001:
				offset = Vector3(1.0, 0.0, 0.0) * (1.0 if record.id % 2 == 0 else -1.0)
				distance = 0.001
			push += offset / distance * (reach - distance) / reach
	return push


func _strike(record: Record, ability: StringName, target: Player) -> void:
	var node := record.node
	var def := record.def
	var here := node.global_position
	var flat_distance := Vector2(target.global_position.x - here.x, target.global_position.z - here.z).length()
	match ability:
		&"melee":
			_events.monster_attack.emit(record.id, ability, here, 0.0)
			if flat_distance - target.body_radius() <= def.melee_range * MELEE_REACH_SLACK:
				_combat.apply_damage(target.entity_id, def.melee_damage * record.damage_mult, record.id, def.id, target.chest_position())
		&"slam":
			_events.monster_attack.emit(record.id, ability, here, def.slam_radius)
			_combat.area_damage(record.id, here, def.slam_radius, def.slam_damage * record.damage_mult, def.id)
		&"charge":
			_events.monster_attack.emit(record.id, ability, here, 0.0)
			_combat.apply_damage(target.entity_id, def.charge_damage * record.damage_mult, record.id, def.id, target.chest_position())
		&"spit":
			_events.monster_attack.emit(record.id, ability, here, 0.0)
			_spit(record, target)


## Fires the monster's projectile(s) at the target, fanned out when there are several.
func _spit(record: Record, target: Player) -> void:
	var def := record.def
	var origin := record.node.eye_position()
	var aim := target.global_position + Vector3(0.0, AIM_HEIGHT, 0.0) - origin
	var base_yaw := atan2(-aim.x, -aim.z)
	var pitch := atan2(aim.y, Vector2(aim.x, aim.z).length())
	var count := def.spit_count
	for i in count:
		var offset := 0.0
		if count > 1:
			offset = deg_to_rad(def.spit_spread_deg) * (float(i) / float(count - 1) - 0.5) * 2.0
		var direction := Player.direction_from(base_yaw + offset, pitch)
		_combat.launch_projectile(record.id, def.spit, origin + direction * 0.8, direction, def.spit.damage * record.damage_mult)


func _summon(record: Record) -> void:
	var def := record.def
	if def.summon_id == &"" or not _catalog.has(def.summon_id):
		return
	var center := record.node.global_position
	for i in def.summon_count:
		var angle := TAU * float(i) / float(def.summon_count)
		var spot := center + Vector3(cos(angle), 0.0, sin(angle)) * (def.radius + SPAWN_SUMMON_RING)
		spawn(def.summon_id, spot, record.owner_id, 1.0, record.damage_mult, record.wave)
