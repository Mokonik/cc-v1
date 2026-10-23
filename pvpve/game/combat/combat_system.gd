class_name CombatSystem
extends RefCounted
## Authority-layer combat: weapons, damage, death and respawn. The only code that changes
## Vitals. Everything is keyed by player id and timed in fixed ticks, so a fight is
## reproducible from the seed and replicable later. It reads each player's last
## PlayerCommand and reports what happened through the EventBus.

const WORLD_MASK := 1
const PLAYER_MASK := 2
const RESPAWN_SECONDS := 3.0
const PROTECTION_SECONDS := 2.0
## Height of the point on a player that melee and splash aim at.
const CHEST_HEIGHT := 1.0
const BODY_CENTER_HEIGHT := 0.9
const BODY_RADIUS := 0.4
## Splash falls off to this fraction of its center damage at the edge of the radius.
const SPLASH_EDGE_FRACTION := 0.25
## Where a fired projectile starts, ahead of the eye, so it clears the shooter's own body.
const PROJECTILE_START_OFFSET := 0.5

var tick := 0
var seed_value := 1
## player id -> Vitals
var vitals: Dictionary = {}
var projectiles := ProjectileSystem.new()

var _events: EventBus
var _catalog: WeaponCatalog
var _get_player: Callable
var _get_space: Callable
var _choose_spawn: Callable


## get_player: Callable(id) -> Player or null.
## get_space: Callable() -> PhysicsDirectSpaceState3D.
## choose_spawn: Callable(id) -> GrayboxArena.Spawn where that player should (re)appear.
func setup(events: EventBus, catalog: WeaponCatalog, get_player: Callable, get_space: Callable, choose_spawn: Callable) -> void:
	_events = events
	_catalog = catalog
	_get_player = get_player
	_get_space = get_space
	_choose_spawn = choose_spawn


# ---- roster ---------------------------------------------------------------

func register(player_id: int, accepts_commands := true) -> Vitals:
	var v := Vitals.new()
	v.player_id = player_id
	v.accepts_commands = accepts_commands
	vitals[player_id] = v
	give_weapon(player_id, WeaponCatalog.STARTER)
	return v


func unregister(player_id: int) -> void:
	vitals.erase(player_id)


func get_vitals(player_id: int) -> Vitals:
	return vitals.get(player_id)


func is_alive(player_id: int) -> bool:
	var v := get_vitals(player_id)
	return v != null and v.alive


func give_weapon(player_id: int, weapon_id: StringName) -> bool:
	var v := get_vitals(player_id)
	var def := _catalog.get_def(weapon_id)
	if v == null or def == null:
		return false
	if v.weapons.has(def.slot):
		return true
	v.weapons[def.slot] = WeaponState.new(def)
	if v.current_slot == 0:
		v.current_slot = def.slot
		_events.weapon_changed.emit(player_id, def.id)
	_events.weapon_given.emit(player_id, def.id)
	return true


func select_slot(player_id: int, slot: int) -> bool:
	var v := get_vitals(player_id)
	if v == null or not v.alive or not v.weapons.has(slot) or v.current_slot == slot:
		return false
	var old := v.current()
	if old != null:
		old.cancel_actions()
	v.current_slot = slot
	_events.weapon_changed.emit(player_id, v.current().def.id)
	return true


func cycle_weapon(player_id: int, direction: int) -> bool:
	var v := get_vitals(player_id)
	if v == null:
		return false
	var slots := v.owned_slots()
	if slots.size() < 2:
		return false
	var index := slots.find(v.current_slot)
	var next := slots[posmod(index + direction, slots.size())]
	return select_slot(player_id, next)


# ---- health ---------------------------------------------------------------

## Applies damage and returns how much was actually dealt (0 if the target is dead,
## protected, in god mode or unknown).
func apply_damage(target_id: int, amount: float, source_id: int, weapon_id: StringName, position: Vector3) -> float:
	var v := get_vitals(target_id)
	if v == null or not v.alive or v.god or tick < v.protected_until_tick or amount <= 0.0:
		return 0.0
	var dealt := minf(amount, v.hp)
	v.hp -= dealt
	_events.damage_dealt.emit(target_id, source_id, dealt, position, weapon_id)
	if v.hp <= 0.0:
		_die(v, source_id, weapon_id)
	return dealt


func set_hp(player_id: int, hp: float) -> void:
	var v := get_vitals(player_id)
	if v != null and v.alive:
		v.hp = clampf(hp, 1.0, v.max_hp)


func kill(player_id: int, killer_id := 0, weapon_id: StringName = &"") -> void:
	var v := get_vitals(player_id)
	if v != null and v.alive:
		v.hp = 0.0
		_die(v, killer_id, weapon_id)


## Brings a dead player back immediately instead of waiting out the respawn timer.
func respawn_now(player_id: int) -> void:
	var v := get_vitals(player_id)
	if v != null and not v.alive:
		v.respawn_tick = tick


func _die(v: Vitals, killer_id: int, weapon_id: StringName) -> void:
	v.alive = false
	v.hp = 0.0
	v.deaths += 1
	v.protected_until_tick = 0
	v.respawn_tick = tick + WeaponDef.seconds_to_ticks(RESPAWN_SECONDS)
	for state: WeaponState in v.weapons.values():
		state.cancel_actions()
	if killer_id != v.player_id:
		var killer := get_vitals(killer_id)
		if killer != null:
			killer.kills += 1
	var player: Player = _get_player.call(v.player_id)
	if player != null:
		player.set_alive(false)
		player.set_protected(false)
	_events.player_died.emit(v.player_id, killer_id, weapon_id)


func _respawn(v: Vitals, player: Player) -> void:
	var spawn: GrayboxArena.Spawn = _choose_spawn.call(v.player_id)
	v.alive = true
	v.hp = v.max_hp
	v.protected_until_tick = tick + WeaponDef.seconds_to_ticks(PROTECTION_SECONDS)
	for state: WeaponState in v.weapons.values():
		state.reset()
	player.respawn_at(spawn.position, spawn.yaw)
	player.set_protected(true)
	_events.player_respawned.emit(v.player_id)


# ---- per-tick update --------------------------------------------------------

func step(current_tick: int) -> void:
	tick = current_tick
	var ids: Array = vitals.keys()
	ids.sort()
	for id: int in ids:
		var v: Vitals = vitals[id]
		var player: Player = _get_player.call(id)
		if player == null:
			continue
		if not v.alive:
			if tick >= v.respawn_tick:
				_respawn(v, player)
			continue
		if v.protected_until_tick > 0 and tick >= v.protected_until_tick:
			v.protected_until_tick = 0
			player.set_protected(false)
		if v.accepts_commands:
			_process_command(v, player, player.last_command)
		_finish_timers(v, player)
	_step_projectiles()


func _process_command(v: Vitals, player: Player, command: PlayerCommand) -> void:
	if command.weapon_slot != 0:
		select_slot(v.player_id, command.weapon_slot)
	elif command.weapon_cycle != 0:
		cycle_weapon(v.player_id, command.weapon_cycle)
	var state := v.current()
	if state == null:
		return
	if command.reload_pressed:
		_begin_reload(v, state)
	match state.def.kind:
		WeaponDef.Kind.HITSCAN:
			_tick_hitscan(v, player, state, command)
		WeaponDef.Kind.MELEE:
			_tick_melee(v, state, command)
		WeaponDef.Kind.PROJECTILE:
			_tick_draw(v, player, state, command)
		WeaponDef.Kind.ABILITY:
			_tick_ability(v, player, state, command)


func _finish_timers(v: Vitals, player: Player) -> void:
	var state := v.current()
	if state == null:
		return
	if state.is_reloading() and tick >= state.reload_done_tick:
		state.ammo = state.def.magazine
		state.reload_done_tick = -1
		_events.reload_finished.emit(v.player_id, state.def.id)
	if state.swing_hit_tick >= 0 and tick >= state.swing_hit_tick:
		state.swing_hit_tick = -1
		_resolve_swing(v, player, state)


func _begin_reload(v: Vitals, state: WeaponState) -> void:
	var def := state.def
	if not def.uses_ammo() or state.is_reloading() or state.ammo >= def.magazine:
		return
	state.reload_done_tick = tick + WeaponDef.seconds_to_ticks(def.reload_time)
	_events.reload_started.emit(v.player_id, def.id, def.reload_time)


# ---- weapon kinds -----------------------------------------------------------

func _tick_hitscan(v: Vitals, player: Player, state: WeaponState, command: PlayerCommand) -> void:
	if state.is_reloading() or not command.fire_held or tick < state.next_fire_tick:
		return
	if state.def.uses_ammo() and state.ammo <= 0:
		_begin_reload(v, state)
		return
	_fire_hitscan(v, player, state, command)


func _fire_hitscan(v: Vitals, player: Player, state: WeaponState, command: PlayerCommand) -> void:
	var def := state.def
	var direction := _apply_spread(Player.direction_from(command.yaw, command.pitch), def.spread_deg, v.player_id, state.shots_fired)
	state.shots_fired += 1
	state.next_fire_tick = tick + WeaponDef.seconds_to_ticks(def.fire_interval)
	if def.uses_ammo():
		state.ammo -= 1

	var origin := player.eye_position()
	var to := origin + direction * def.reach
	var hit := _raycast(origin, to, [player.get_rid()], WORLD_MASK | PLAYER_MASK)
	var end_point := to
	var target_id := 0
	if not hit.is_empty():
		end_point = hit.position
		if hit.collider is Player:
			target_id = (hit.collider as Player).player_id
	_events.weapon_fired.emit(v.player_id, def.id, origin, direction, end_point)
	if target_id != 0:
		apply_damage(target_id, def.damage, v.player_id, def.id, end_point)
	if def.uses_ammo() and state.ammo <= 0:
		_begin_reload(v, state)


func _tick_melee(v: Vitals, state: WeaponState, command: PlayerCommand) -> void:
	if not command.fire_held or tick < state.next_fire_tick:
		return
	var def := state.def
	state.next_fire_tick = tick + WeaponDef.seconds_to_ticks(def.fire_interval)
	state.swing_hit_tick = tick + WeaponDef.seconds_to_ticks(def.windup)
	_events.melee_swing.emit(v.player_id, def.id)


## Hits every living opponent inside the swing's reach and arc that is not behind a wall.
func _resolve_swing(v: Vitals, player: Player, state: WeaponState) -> void:
	var def := state.def
	var command := player.last_command
	var eye := player.eye_position()
	var forward := Player.direction_from(command.yaw, command.pitch)
	var half_arc := deg_to_rad(def.arc_deg * 0.5)
	var ids: Array = vitals.keys()
	ids.sort()
	for id: int in ids:
		if id == v.player_id or not is_alive(id):
			continue
		var other: Player = _get_player.call(id)
		if other == null:
			continue
		var chest := other.global_position + Vector3(0.0, CHEST_HEIGHT, 0.0)
		var to_chest := chest - eye
		if to_chest.length() - BODY_RADIUS > def.reach:
			continue
		if forward.angle_to(to_chest) > half_arc:
			continue
		if not _raycast(eye, chest, [player.get_rid(), other.get_rid()], WORLD_MASK).is_empty():
			continue
		apply_damage(id, def.damage, v.player_id, def.id, chest)


## Bow: hold to draw, release to loose. Power (and so damage and speed) grows with the draw.
func _tick_draw(v: Vitals, player: Player, state: WeaponState, command: PlayerCommand) -> void:
	var def := state.def
	if not state.is_drawing():
		if command.fire_held and tick >= state.next_fire_tick:
			state.draw_start_tick = tick
			_events.draw_started.emit(v.player_id, def.id, def.draw_time)
		return
	if command.fire_held:
		return
	var draw_ticks := maxi(WeaponDef.seconds_to_ticks(def.draw_time), 1)
	var power := clampf(float(tick - state.draw_start_tick) / float(draw_ticks), def.min_power, 1.0)
	state.draw_start_tick = -1
	state.next_fire_tick = tick + WeaponDef.seconds_to_ticks(def.fire_interval)
	_launch(v, player, state, command, power)


## Fire Orb and other cooldown abilities: instant cast, then wait out the cooldown.
func _tick_ability(v: Vitals, player: Player, state: WeaponState, command: PlayerCommand) -> void:
	if not command.fire_held or tick < state.next_fire_tick:
		return
	state.next_fire_tick = tick + WeaponDef.seconds_to_ticks(state.def.fire_interval)
	_launch(v, player, state, command, 1.0)


func _launch(v: Vitals, player: Player, state: WeaponState, command: PlayerCommand, power: float) -> void:
	var def := state.def
	state.shots_fired += 1
	var direction := Player.direction_from(command.yaw, command.pitch)
	var origin := player.eye_position() + direction * PROJECTILE_START_OFFSET
	var speed := def.projectile_speed
	if def.kind == WeaponDef.Kind.PROJECTILE:
		speed *= lerpf(0.4, 1.0, power)
	var projectile := projectiles.spawn(def, v.player_id, origin, direction * speed, power, tick)
	_events.weapon_fired.emit(v.player_id, def.id, origin, direction, origin)
	_events.projectile_spawned.emit(projectile.id, def.id, origin, projectile.velocity)


# ---- projectiles ------------------------------------------------------------

func _step_projectiles() -> void:
	if projectiles.count() == 0:
		return
	var dt := 1.0 / Engine.physics_ticks_per_second
	var impacts := projectiles.step(tick, _get_space.call(), _body_rid, dt)
	for impact in impacts:
		_resolve_impact(impact)


func _resolve_impact(impact: ProjectileSystem.Impact) -> void:
	var projectile := impact.projectile
	var def := projectile.def
	var hit_player := 0
	match impact.kind:
		ProjectileSystem.Impact.Kind.PLAYER:
			hit_player = impact.target_id
			apply_damage(hit_player, def.damage * projectile.power, projectile.owner_id, def.id, impact.position)
			if def.splash_radius > 0.0:
				_explode(projectile, impact.position, hit_player)
		ProjectileSystem.Impact.Kind.WORLD:
			if def.splash_radius > 0.0:
				_explode(projectile, impact.position, 0)
	_events.projectile_ended.emit(projectile.id, impact.position, hit_player)


## Splash damage around a point, falling off with distance. The owner is never hurt, and
## the player already hit directly is skipped so they are not damaged twice.
func _explode(projectile: Projectile, position: Vector3, skip_id: int) -> void:
	var def := projectile.def
	_events.explosion.emit(position, def.splash_radius, def.id)
	var ids: Array = vitals.keys()
	ids.sort()
	for id: int in ids:
		if id == projectile.owner_id or id == skip_id or not is_alive(id):
			continue
		var other: Player = _get_player.call(id)
		if other == null:
			continue
		var center := other.global_position + Vector3(0.0, BODY_CENTER_HEIGHT, 0.0)
		var distance := center.distance_to(position)
		if distance > def.splash_radius:
			continue
		var falloff := lerpf(1.0, SPLASH_EDGE_FRACTION, distance / def.splash_radius)
		apply_damage(id, def.splash_damage * falloff, projectile.owner_id, def.id, center)


func _body_rid(player_id: int) -> RID:
	var player: Player = _get_player.call(player_id)
	return player.get_rid() if player != null else RID()


# ---- helpers ----------------------------------------------------------------

func _raycast(from: Vector3, to: Vector3, exclude: Array[RID], mask: int) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = _get_space.call()
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask, exclude))


## Stateless pseudo-random float in [0, 1): the same shot always gets the same number.
func _rand01(shooter_id: int, shot_index: int, salt: int) -> float:
	return float(hash([seed_value, shooter_id, tick, shot_index, salt]) & 0xFFFFFF) / float(0x1000000)


func _apply_spread(direction: Vector3, spread_deg: float, shooter_id: int, shot_index: int) -> Vector3:
	if spread_deg <= 0.0:
		return direction
	var reference := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	var right := direction.cross(reference).normalized()
	var up := right.cross(direction)
	var radius := tan(deg_to_rad(spread_deg)) * sqrt(_rand01(shooter_id, shot_index, 1))
	var angle := TAU * _rand01(shooter_id, shot_index, 2)
	return (direction + (right * cos(angle) + up * sin(angle)) * radius).normalized()
