class_name ZoneManager
extends RefCounted
## Builds, tracks and tears down each player's private PvE zone, and moves players in and out.
## Zones are placed SPACING meters apart along +X (owner id times SPACING), far from the
## sandbox at the origin and from each other, so nothing leaks between them.

const SPACING := 300.0

var _root: Node3D
var _zones: Dictionary = {}
## owner id -> {"position": Vector3, "yaw": float}: where to put a player back.
var _return: Dictionary = {}


func setup(root: Node3D) -> void:
	_root = root


func zone_offset(owner_id: int) -> Vector3:
	return Vector3(SPACING * owner_id, 0.0, 0.0)


## The player's zone, building it on first use.
func ensure_zone(owner_id: int) -> PveZone:
	var zone: PveZone = _zones.get(owner_id)
	if zone != null and is_instance_valid(zone):
		return zone
	zone = PveZone.new()
	zone.name = "Zone%d" % owner_id
	zone.position = zone_offset(owner_id)
	_root.add_child(zone)
	_zones[owner_id] = zone
	return zone


func get_zone(owner_id: int) -> PveZone:
	var zone: PveZone = _zones.get(owner_id)
	return zone if zone != null and is_instance_valid(zone) else null


func is_inside(owner_id: int) -> bool:
	return _return.has(owner_id)


func zone_count() -> int:
	return _zones.size()


## Moves a player into their zone, remembering where they were.
func enter(player: Player, owner_id: int) -> PveZone:
	var zone := ensure_zone(owner_id)
	if not _return.has(owner_id):
		_return[owner_id] = {"position": player.global_position, "yaw": player.rotation.y}
	var start := zone.player_start()
	player.teleport_to(start.position, start.yaw)
	return zone


## Puts a player back where they entered from. Returns false if they were not in a zone.
func leave(player: Player, owner_id: int) -> bool:
	if not _return.has(owner_id):
		return false
	var back: Dictionary = _return[owner_id]
	_return.erase(owner_id)
	player.teleport_to(back.position, back.yaw)
	return true


func free_zone(owner_id: int) -> void:
	var zone := get_zone(owner_id)
	if zone != null:
		zone.queue_free()
	_zones.erase(owner_id)
	_return.erase(owner_id)
