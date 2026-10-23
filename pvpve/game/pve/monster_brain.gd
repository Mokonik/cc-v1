class_name MonsterBrain
extends RefCounted
## One monster's decisions, as a state machine. Pure logic like BotBrain: it is handed
## positions and a waypoint and returns a Command, and never touches the scene tree.
## Time is in ticks and there is no hidden randomness, so a monster is reproducible.
##
## States: IDLE (no target) -> CHASE -> WINDUP (telegraphing an attack) -> RECOVER, plus
## CHARGING and STUNNED for charge attacks. Which attacks a monster has comes from its
## MonsterDef numbers; the brain just uses whatever is switched on.

enum State { IDLE, CHASE, WINDUP, RECOVER, CHARGING, STUNNED }

const RECOVER_SECONDS := 0.35
const ENRAGE_SPEED := 1.3
const ENRAGE_INTERVAL := 0.75
const CHARGE_MIN_DISTANCE := 6.0
const CHARGE_MAX_DISTANCE := 20.0
const SPIT_MIN_DISTANCE := 3.0
## After a charge hits a target it stays stunned for this fraction of stun_time.
const CHARGE_HIT_STUN_FRACTION := 0.5

class Command extends RefCounted:
	## World-space direction to walk (unit length, or zero) and how fast.
	var move := Vector3.ZERO
	var speed := 0.0
	var yaw := 0.0
	## The attack that lands this tick: "melee", "spit", "slam" or "charge" (a charge touching its target).
	var strike: StringName = &""
	## Set on the tick a wind-up starts, for presentation and tests.
	var telegraph: StringName = &""
	var telegraph_seconds := 0.0
	## The boss wants its summons now.
	var summon := false

var def: MonsterDef
var monster_id := 0
var state := State.IDLE
var enraged := false
var summoned := false

var _state_until := 0
var _pending: StringName = &""
var _next_ready := {&"melee": 0, &"spit": 0, &"slam": 0, &"charge": 0}
var _charge_dir := Vector3.ZERO


func _init(p_def: MonsterDef, p_monster_id: int) -> void:
	def = p_def
	monster_id = p_monster_id


## Staggers the first attacks so a freshly spawned pack does not all strike on the same tick.
func start(tick: int, seed_value: int) -> void:
	var roll := float(hash([seed_value, monster_id]) & 0xFFFF) / 65536.0
	var delay := WeaponDef.seconds_to_ticks(0.5 + roll * 0.7)
	for ability: StringName in _next_ready:
		_next_ready[ability] = tick + delay


## One decision. blocked: the body hit a wall last tick. push: neighbor-avoidance direction.
func think(tick: int, pos: Vector3, yaw: float, target_pos: Vector3, has_target: bool, has_los: bool,
		waypoint: Vector3, push: Vector3, hp_fraction: float, blocked: bool) -> Command:
	var command := Command.new()
	command.yaw = yaw
	if def.enrage_fraction > 0.0 and hp_fraction <= def.enrage_fraction:
		enraged = true
	if def.summon_count > 0 and not summoned and hp_fraction <= def.summon_at_fraction:
		summoned = true
		command.summon = true
	var speed_mult := ENRAGE_SPEED if enraged else 1.0
	var interval_mult := ENRAGE_INTERVAL if enraged else 1.0

	if not has_target:
		state = State.IDLE
		return command

	var to_target := target_pos - pos
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var distance := flat.length()
	var toward := flat.normalized() if distance > 0.001 else Vector3.ZERO
	var face_yaw := atan2(-flat.x, -flat.z) if distance > 0.001 else yaw

	match state:
		State.STUNNED:
			if tick >= _state_until:
				state = State.CHASE
			return command
		State.RECOVER:
			command.yaw = face_yaw
			if tick >= _state_until:
				state = State.CHASE
			return command
		State.WINDUP:
			command.yaw = face_yaw
			if tick < _state_until:
				return command
			if _pending == &"charge":
				state = State.CHARGING
				_charge_dir = toward
				_state_until = tick + WeaponDef.seconds_to_ticks(def.charge_time)
			else:
				command.strike = _pending
				state = State.RECOVER
				_state_until = tick + WeaponDef.seconds_to_ticks(RECOVER_SECONDS)
			return command
		State.CHARGING:
			command.move = _charge_dir
			command.speed = def.charge_speed * speed_mult
			command.yaw = atan2(-_charge_dir.x, -_charge_dir.z)
			if distance <= def.radius + 0.9:
				command.strike = &"charge"
				command.move = Vector3.ZERO
				command.speed = 0.0
				state = State.STUNNED
				_state_until = tick + WeaponDef.seconds_to_ticks(def.stun_time * CHARGE_HIT_STUN_FRACTION)
			elif blocked or tick >= _state_until:
				command.move = Vector3.ZERO
				command.speed = 0.0
				state = State.STUNNED
				_state_until = tick + WeaponDef.seconds_to_ticks(def.stun_time)
			return command

	state = State.CHASE
	command.yaw = face_yaw

	var ability := _choose_ability(tick, distance, has_los)
	if ability != &"":
		_begin_windup(tick, ability, interval_mult, command)
		return command

	var direction := _movement(tick, distance, toward, pos, waypoint, has_los)
	direction += push
	if direction.length() > 1.0:
		direction = direction.normalized()
	command.move = direction
	command.speed = def.move_speed * speed_mult
	if direction.length_squared() > 0.01 and not has_los:
		command.yaw = atan2(-direction.x, -direction.z)
	return command


func _choose_ability(tick: int, distance: float, has_los: bool) -> StringName:
	if def.has_slam() and distance <= def.slam_radius * 0.85 and tick >= _next_ready[&"slam"]:
		return &"slam"
	if def.has_melee() and distance <= def.melee_range and tick >= _next_ready[&"melee"]:
		return &"melee"
	if def.has_charge() and has_los and distance >= CHARGE_MIN_DISTANCE and distance <= CHARGE_MAX_DISTANCE \
			and tick >= _next_ready[&"charge"]:
		return &"charge"
	if def.has_spit() and has_los and distance <= def.spit_range and distance >= SPIT_MIN_DISTANCE \
			and tick >= _next_ready[&"spit"]:
		return &"spit"
	return &""


func _begin_windup(tick: int, ability: StringName, interval_mult: float, command: Command) -> void:
	var windup := 0.0
	var interval := 0.0
	match ability:
		&"melee":
			windup = def.melee_windup
			interval = def.melee_interval
		&"spit":
			windup = def.spit_windup
			interval = def.spit_interval
		&"slam":
			windup = def.slam_windup
			interval = def.slam_cooldown
		&"charge":
			windup = def.charge_windup
			interval = def.charge_cooldown
	windup *= interval_mult
	state = State.WINDUP
	_pending = ability
	_state_until = tick + WeaponDef.seconds_to_ticks(windup)
	_next_ready[ability] = tick + WeaponDef.seconds_to_ticks(interval * interval_mult)
	command.telegraph = ability
	command.telegraph_seconds = windup


## Where to walk when not attacking: kite, close in, or hold position.
func _movement(tick: int, distance: float, toward: Vector3, pos: Vector3, waypoint: Vector3, has_los: bool) -> Vector3:
	if def.keep_distance > 0.0 and has_los:
		if distance < def.keep_distance * 0.75:
			return -toward
		if distance > def.keep_distance * 1.25:
			return _toward_waypoint(pos, waypoint, toward)
		var side := 1.0 if (int(tick / 100) + monster_id) % 2 == 0 else -1.0
		return toward.cross(Vector3.UP) * side * 0.6
	var hold := 0.0
	if def.has_melee():
		hold = def.melee_range * 0.8
	elif def.has_slam():
		hold = def.slam_radius * 0.6
	if distance <= hold:
		return Vector3.ZERO
	return _toward_waypoint(pos, waypoint, toward)


func _toward_waypoint(pos: Vector3, waypoint: Vector3, fallback: Vector3) -> Vector3:
	var step := Vector3(waypoint.x - pos.x, 0.0, waypoint.z - pos.z)
	return step.normalized() if step.length_squared() > 0.0001 else fallback
