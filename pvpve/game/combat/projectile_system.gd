class_name ProjectileSystem
extends RefCounted
## Steps projectiles and reports what they hit. It knows nothing about damage: CombatSystem
## turns the returned impacts into health changes. Collision is a segment raycast per tick
## (continuous), so fast arrows cannot tunnel through players or walls.

class Impact extends RefCounted:
	## PLAYER means any combatant (a player or a monster) was hit.
	enum Kind { PLAYER, WORLD, EXPIRED }
	var projectile: Projectile
	var kind := Kind.EXPIRED
	var position := Vector3.ZERO
	var target_id := 0

var _items: Array[Projectile] = []
var _next_id := 1


func spawn(def: WeaponDef, owner_id: int, position: Vector3, velocity: Vector3, power: float, tick: int) -> Projectile:
	var projectile := Projectile.new()
	projectile.id = _next_id
	_next_id += 1
	projectile.def = def
	projectile.owner_id = owner_id
	projectile.position = position
	projectile.velocity = velocity
	projectile.power = power
	projectile.spawn_tick = tick
	_items.append(projectile)
	return projectile


func count() -> int:
	return _items.size()


func get_projectile(id: int) -> Projectile:
	for projectile in _items:
		if projectile.id == id:
			return projectile
	return null


func all() -> Array[Projectile]:
	return _items


func clear() -> void:
	_items.clear()


## owner_rid: Callable(owner_id) -> RID of that player's body (invalid RID if gone), so a
## projectile never hits whoever fired it.
func step(tick: int, space: PhysicsDirectSpaceState3D, owner_rid: Callable, dt: float) -> Array[Impact]:
	var impacts: Array[Impact] = []
	var remaining: Array[Projectile] = []
	for projectile in _items:
		projectile.velocity.y -= projectile.def.projectile_gravity * dt
		var from := projectile.position
		var to := from + projectile.velocity * dt
		var exclude: Array[RID] = []
		var rid: RID = owner_rid.call(projectile.owner_id)
		if rid.is_valid():
			exclude.append(rid)
		var query := PhysicsRayQueryParameters3D.create(from, to, projectile.mask, exclude)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var impact := Impact.new()
			impact.projectile = projectile
			impact.position = hit.position
			if hit.collider is Combatant:
				impact.kind = Impact.Kind.PLAYER
				impact.target_id = (hit.collider as Combatant).entity_id
			else:
				impact.kind = Impact.Kind.WORLD
			impacts.append(impact)
			continue
		projectile.position = to
		if tick - projectile.spawn_tick >= WeaponDef.seconds_to_ticks(projectile.def.projectile_lifetime):
			var expired := Impact.new()
			expired.projectile = projectile
			expired.kind = Impact.Kind.EXPIRED
			expired.position = to
			impacts.append(expired)
			continue
		remaining.append(projectile)
	_items = remaining
	return impacts
