class_name BotInputSource
extends InputSource
## Drives a Player like a human would: it only produces PlayerCommands.
## Adds what BotBrain deliberately does not know about: navigation and line-of-sight.

const REPATH_SECONDS := 0.2

## Returns the living opponents of a given player id (supplied by Game, which owns who is
## playing). A callable rather than a Game reference keeps bots independent of the authority layer.
var get_opponents: Callable
var profile: BotProfile
var rng_seed := 0

## Inspection hooks for tests and debug overlays.
var target_id := 0
var last_command := PlayerCommand.new()

var _brain: BotBrain
var _agent: NavigationAgent3D
var _repath_timer := 0.0
var _waypoint := Vector3.ZERO
var _pending_view := Vector2.ZERO
var _has_pending_view := false


func set_view(yaw: float, pitch: float) -> void:
	if _brain != null:
		_brain.set_view(yaw, pitch)
	else:
		_pending_view = Vector2(yaw, pitch)
		_has_pending_view = true


func poll(delta: float) -> PlayerCommand:
	var me := get_parent() as Player
	if me == null or not get_opponents.is_valid():
		return PlayerCommand.new()
	if _brain == null:
		_setup(me)

	var target := _pick_target(me)
	var has_los := false
	if target != null:
		target_id = target.player_id
		has_los = _has_line_of_sight(me, target)
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_repath_timer = REPATH_SECONDS
			_agent.target_position = target.global_position
		_waypoint = _next_waypoint(target)
	else:
		target_id = 0
	last_command = _brain.think(delta, me, target, _waypoint, has_los)
	return last_command


func _setup(me: Player) -> void:
	if profile == null:
		profile = BotPresets.make(1)
	_brain = BotBrain.new(profile, rng_seed)
	if _has_pending_view:
		_brain.set_view(_pending_view.x, _pending_view.y)
	else:
		_brain.set_view(me.rotation.y, 0.0)
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 1.0
	_agent.radius = 0.5
	_agent.height = 1.8
	_agent.avoidance_enabled = false
	me.add_child(_agent)


func _pick_target(me: Player) -> Player:
	var best: Player = null
	var best_distance := INF
	for other: Player in get_opponents.call(me.player_id):
		var distance := me.global_position.distance_squared_to(other.global_position)
		if distance < best_distance:
			best_distance = distance
			best = other
	return best


## Next navmesh point toward the target, or the target itself while no path exists
## (for example during the first frames before the navigation map has synced).
func _next_waypoint(target: Player) -> Vector3:
	var next := _agent.get_next_path_position()
	if _agent.get_current_navigation_path().size() > 1:
		return next
	return target.global_position


func _has_line_of_sight(me: Player, target: Player) -> bool:
	var from := me.global_position + Vector3(0.0, Player.EYE_HEIGHT, 0.0)
	var to := target.global_position + Vector3(0.0, Player.EYE_HEIGHT, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [me.get_rid(), target.get_rid()]
	return me.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
