class_name LootSystem
extends RefCounted
## Everything lying on the ground or hidden in it: loot drops, and traps. Spawns drops from
## monster deaths (seeded, so the same kill always drops the same thing), resolves pickups by
## proximity, applies weapon unlocks and tier-ups, and triggers traps. The only code that changes
## Inventory, LootDrop and Trap state.

const PICKUP_RADIUS := 1.6
const DROP_LIFETIME_SECONDS := 60.0
const TRAP_ARM_SECONDS := 1.0
const TRAP_RADIUS := 1.5
const TRAP_DAMAGE := 30.0
const TRAP_SLOW_FACTOR := 0.6
const TRAP_SLOW_SECONDS := 2.5
const BASE_LOOT_ROLL_SALT := 11

var drops: Dictionary = {}
var traps: Dictionary = {}
## player id -> Inventory
var inventories: Dictionary = {}

var _events: EventBus
var _combat: CombatSystem
var _progression: Progression
var _table: LootTable
var _monster_catalog: MonsterCatalog
## Callable(id) -> Combatant or null.
var _get_body: Callable
var _seed := 1
var _tick := 0
var _next_id := 1
var _next_trap_id := 1


func setup(events: EventBus, combat: CombatSystem, progression: Progression, monster_catalog: MonsterCatalog,
		get_body: Callable, table: LootTable) -> void:
	_events = events
	_combat = combat
	_progression = progression
	_monster_catalog = monster_catalog
	_get_body = get_body
	_table = table


func set_seed(value: int) -> void:
	_seed = value


func register(player_id: int) -> Inventory:
	var inventory := Inventory.new()
	inventories[player_id] = inventory
	return inventory


func unregister(player_id: int) -> void:
	inventories.erase(player_id)
	clear_owned_by(player_id)


func get_inventory(player_id: int) -> Inventory:
	return inventories.get(player_id)


# ---- drops --------------------------------------------------------------------------------

## Rolls the monster's loot at its death position. Returns the drop, or null if nothing dropped.
## owner_id is the zone owner (0 = anywhere); killer_id gets their Scavenger bonus.
func roll_drop(monster_id: int, def: MonsterDef, killer_id: int, owner_id: int, position: Vector3, wave: int, bonus := 0.0) -> LootDrop:
	var chance := def.loot_chance + bonus
	var killer := _combat.get_vitals(killer_id)
	if killer != null:
		chance += killer.stats.loot_chance_bonus
	var roll := _roll(monster_id, 1)
	if roll >= minf(chance, 1.0):
		return null
	var entry := _table.pick(_roll(monster_id, 2), wave)
	if entry == null:
		return null
	return spawn_drop(entry, position, owner_id)


func spawn_drop(entry: LootEntry, position: Vector3, owner_id := 0) -> LootDrop:
	var drop := LootDrop.new()
	drop.id = _next_id
	_next_id += 1
	drop.kind = entry.kind
	drop.weapon_id = entry.id
	drop.amount = entry.amount
	drop.position = position
	drop.spawn_tick = _tick
	drop.owner_id = owner_id
	drops[drop.id] = drop
	_events.loot_dropped.emit(drop.id, drop.kind, drop.label(), position)
	return drop


## Drops something specific (console and tests). kind_name: a weapon id, "health", "trap" or "xp".
func spawn_named(kind_name: StringName, position: Vector3, owner_id := 0) -> LootDrop:
	var entry := LootEntry.new()
	match kind_name:
		&"health":
			entry.kind = LootEntry.Kind.HEALTH
			entry.amount = int(Inventory.HEALTH_PACK_AMOUNT)
		&"trap":
			entry.kind = LootEntry.Kind.TRAP
		&"xp":
			entry.kind = LootEntry.Kind.XP
			entry.amount = 50
		_:
			entry.kind = LootEntry.Kind.WEAPON
			entry.id = kind_name
	return spawn_drop(entry, position, owner_id)


func clear_owned_by(owner_id: int) -> void:
	for id: int in drops.keys():
		if drops[id].owner_id == owner_id and owner_id != 0:
			_remove_drop(id)
	for id: int in traps.keys():
		if traps[id].owner_id == owner_id:
			traps.erase(id)


func clear_drops() -> int:
	var removed := drops.size()
	for id: int in drops.keys():
		_remove_drop(id)
	return removed


## Resets what a player carries (the start of a new cycle): consumables go, weapons go back to
## the starter pistol at tier 1.
func reset_loot(player_id: int) -> void:
	var inventory := get_inventory(player_id)
	if inventory != null:
		inventory.clear()
	_combat.reset_loadout(player_id)


# ---- per-tick -----------------------------------------------------------------------------

func step(tick: int) -> void:
	_tick = tick
	_expire_drops()
	_collect_pickups()
	_tick_traps()


func _expire_drops() -> void:
	var lifetime := WeaponDef.seconds_to_ticks(DROP_LIFETIME_SECONDS)
	for id: int in drops.keys():
		if _tick - drops[id].spawn_tick >= lifetime:
			_remove_drop(id)


func _collect_pickups() -> void:
	if drops.is_empty():
		return
	var player_ids: Array = inventories.keys()
	player_ids.sort()
	for drop_id: int in drops.keys():
		var drop: LootDrop = drops.get(drop_id)
		if drop == null:
			continue
		for player_id: int in player_ids:
			if drop.owner_id != 0 and drop.owner_id != player_id:
				continue
			if not _combat.is_alive(player_id):
				continue
			var body: Combatant = _get_body.call(player_id)
			if body == null:
				continue
			if body.global_position.distance_to(drop.position) > PICKUP_RADIUS:
				continue
			if _apply_pickup(player_id, drop):
				_remove_drop(drop_id)
				break


## Gives the drop to a player. Returns false if they cannot take it right now (full pack).
func _apply_pickup(player_id: int, drop: LootDrop) -> bool:
	var inventory := get_inventory(player_id)
	match drop.kind:
		LootEntry.Kind.HEALTH:
			if inventory.health_packs >= Inventory.MAX_HEALTH_PACKS:
				return false
			inventory.health_packs += 1
		LootEntry.Kind.TRAP:
			if inventory.traps >= Inventory.MAX_TRAPS:
				return false
			inventory.traps += 1
		LootEntry.Kind.XP:
			_progression.grant_xp(player_id, drop.amount)
		LootEntry.Kind.WEAPON:
			var result := _combat.grant_weapon_loot(player_id, drop.weapon_id)
			if result == &"":
				return false
	_events.loot_picked_up.emit(player_id, drop.id, drop.kind, drop.label())
	return true


func _remove_drop(drop_id: int) -> void:
	if drops.erase(drop_id):
		_events.loot_removed.emit(drop_id)


# ---- consumables ---------------------------------------------------------------------------

## Uses a health pack. Returns false if there is none or the player is already at full health.
func use_health_pack(player_id: int) -> bool:
	var inventory := get_inventory(player_id)
	var vitals := _combat.get_vitals(player_id)
	if inventory == null or vitals == null or not vitals.alive or inventory.health_packs <= 0:
		return false
	if vitals.hp >= vitals.max_hp - 0.001:
		return false
	inventory.health_packs -= 1
	var gained := _combat.heal(player_id, Inventory.HEALTH_PACK_AMOUNT)
	_events.item_used.emit(player_id, &"health", gained)
	return true


## Places a trap at the player's feet. Returns false if they have none or are not on the ground.
func place_trap(player_id: int) -> bool:
	var inventory := get_inventory(player_id)
	var body: Combatant = _get_body.call(player_id)
	if inventory == null or body == null or not _combat.is_alive(player_id) or inventory.traps <= 0:
		return false
	inventory.traps -= 1
	var trap := Trap.new()
	trap.id = _next_trap_id
	_next_trap_id += 1
	trap.owner_id = player_id
	trap.position = body.global_position
	trap.arm_tick = _tick + WeaponDef.seconds_to_ticks(TRAP_ARM_SECONDS)
	traps[trap.id] = trap
	_events.trap_placed.emit(trap.id, player_id, trap.position)
	_events.item_used.emit(player_id, &"trap", 0.0)
	return true


func _tick_traps() -> void:
	if traps.is_empty():
		return
	for trap_id: int in traps.keys():
		var trap: Trap = traps.get(trap_id)
		if trap == null:
			continue
		if _tick == trap.arm_tick:
			_events.trap_armed.emit(trap.id)
		if _tick < trap.arm_tick:
			continue
		var victim := _find_victim(trap)
		if victim == 0:
			continue
		traps.erase(trap_id)
		var body: Combatant = _get_body.call(victim)
		var at := body.chest_position() if body != null else trap.position
		_combat.apply_damage(victim, TRAP_DAMAGE, trap.owner_id, &"trap", at)
		_combat.apply_slow(victim, TRAP_SLOW_FACTOR, TRAP_SLOW_SECONDS)
		_events.trap_triggered.emit(trap.id, victim, trap.position)


## The nearest living non-owner, non-monster combatant within the trap's radius, or 0.
func _find_victim(trap: Trap) -> int:
	var best := 0
	var best_distance := TRAP_RADIUS
	var ids: Array = _combat.vitals.keys()
	ids.sort()
	for id: int in ids:
		var vitals: Vitals = _combat.vitals[id]
		if id == trap.owner_id or vitals.is_monster or not vitals.alive:
			continue
		var body: Combatant = _get_body.call(id)
		if body == null:
			continue
		var distance := Vector2(body.global_position.x - trap.position.x, body.global_position.z - trap.position.z).length()
		if distance <= best_distance and absf(body.global_position.y - trap.position.y) < 1.5:
			best_distance = distance
			best = id
	return best


func _roll(monster_id: int, salt: int) -> float:
	return float(hash([_seed, monster_id, salt, BASE_LOOT_ROLL_SALT]) & 0xFFFFFF) / float(0x1000000)
