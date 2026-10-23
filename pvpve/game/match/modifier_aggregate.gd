class_name ModifierAggregate
extends RefCounted
## The combined effect of the active world modifiers, as plain numbers for the rest of the game
## to read. The neutral aggregate (nothing active) changes nothing.

var count_mult := 1.0
var hp_mult := 1.0
var damage_mult := 1.0
var speed_mult := 1.0
var range_mult := 1.0
var xp_mult := 1.0
var loot_chance_bonus := 0.0
var gravity_mult := 1.0
var volatile_damage := 0.0
var volatile_radius := 0.0
var fog_density := 0.0
## Ids of the modifiers folded in, for display.
var active_ids: Array[StringName] = []


func add(def: ModifierDef) -> void:
	count_mult *= def.count_mult
	hp_mult *= def.hp_mult
	damage_mult *= def.damage_mult
	speed_mult *= def.speed_mult
	range_mult *= def.range_mult
	xp_mult *= def.xp_mult
	loot_chance_bonus += def.loot_chance_bonus
	gravity_mult *= def.gravity_mult
	volatile_damage += def.volatile_damage
	volatile_radius = maxf(volatile_radius, def.volatile_radius)
	fog_density = maxf(fog_density, def.fog_density)
	active_ids.append(def.id)


func is_neutral() -> bool:
	return active_ids.is_empty()


## How much harder (or easier) the modifiers make a PvE phase for a modeled bot: more monsters
## and tougher ones raise the threat, damage raises it a little less, easy fog and low gravity lower it.
func threat_mult() -> float:
	var threat := count_mult * (1.0 + (hp_mult - 1.0) * 0.6) * (1.0 + (damage_mult - 1.0) * 0.4)
	if volatile_damage > 0.0:
		threat *= 1.1
	if range_mult < 1.0:
		threat *= 0.92
	if gravity_mult < 1.0:
		threat *= 0.95
	return threat


func bot_effects() -> BotPveModel.Effects:
	var effects := BotPveModel.Effects.new()
	effects.threat_mult = threat_mult()
	return effects
