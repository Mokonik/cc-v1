class_name MatchView
extends Node3D
## What you see of the match in the world: the gold mark over whoever leads, the shrinking
## safe-area ring in the final, and the fog a world modifier brings. Presentation only: it
## reads game state and listens to the EventBus.

const RING_HEIGHT := 14.0
const MARK_HEIGHT := 2.5

@export var game: Game
## The scene's WorldEnvironment, whose fog this switches on and off.
@export var world_environment: WorldEnvironment

var _mark: MeshInstance3D
var _ring: MeshInstance3D
var _ring_radius := MatchDirector.FINAL_START_RADIUS
var _time := 0.0


func _ready() -> void:
	_mark = MeshInstance3D.new()
	var diamond := PrismMesh.new()
	diamond.size = Vector3(0.45, 0.6, 0.45)
	_mark.mesh = diamond
	_mark.material_override = _glow(Color(1.0, 0.82, 0.25))
	_mark.visible = false
	add_child(_mark)

	_ring = MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.height = RING_HEIGHT
	tube.top_radius = 1.0
	tube.bottom_radius = 1.0
	tube.cap_top = false
	tube.cap_bottom = false
	_ring.mesh = tube
	_ring.material_override = _glow(Color(0.35, 0.6, 1.0), 0.4)
	_ring.visible = false
	add_child(_ring)
	game.events.final_zone.connect(func(radius: float, _center: Vector3) -> void: _ring_radius = radius)


func _process(delta: float) -> void:
	_time += delta
	var director := game.match_director
	_update_mark(director)
	_ring.visible = director.phase == MatchDirector.FINAL
	if _ring.visible:
		_ring.scale = Vector3(_ring_radius, 1.0, _ring_radius)
		_ring.position = Vector3(0.0, RING_HEIGHT * 0.5, 0.0)
	_update_fog()


func _update_mark(director: MatchDirector) -> void:
	var player := game.get_player(director.marked_id) if director.marked_id != 0 and director.is_running() else null
	_mark.visible = player != null and game.combat.is_alive(director.marked_id) and player != game.get_human()
	if _mark.visible:
		_mark.global_position = player.global_position + Vector3(0.0, MARK_HEIGHT + sin(_time * 3.0) * 0.08, 0.0)
		_mark.rotation = Vector3(PI, _time * 2.0, 0.0)


func _update_fog() -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var modifier := game.modifiers.aggregate_for(PlayerRegistry.HOST_ID)
	var environment := world_environment.environment
	environment.fog_enabled = modifier.fog_density > 0.0
	environment.fog_density = modifier.fog_density
	environment.fog_light_color = Color(0.62, 0.66, 0.74)


func _glow(color: Color, alpha := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
