class_name BotPveModel
extends RefCounted
## What a bot's PvE phase would have produced, without running it. A bot does not fight
## monsters in a real zone; this turns its skill, the difficulty, any modifiers and any sabotage
## into a PveResult (kills, boss, deaths, XP, Sabotage Points, loot) using the same wave
## schedule, monster values and scoring formula a human faces. It is deliberately simple and
## seeded: it stands in for a friend, it does not try to be realistic.
##
## Model: the phase offers a pool of "threat" built from the real wave schedule. A bot clears
## a share of it that rises with skill and falls with difficulty, modifiers and sabotage. Deaths
## come from the threat it did not manage to clear. The boss falls only if the bot is strong
## enough and survives long enough (see boss_chance).

const SKILL_BY_LEVEL: Array[float] = [0.35, 0.60, 0.85]
## A bot of skill 1.0 clears this share of a difficulty-1 phase at best.
const MAX_CLEAR_SHARE := 0.95
const NOISE := 0.08
const BOSS_SKILL_FLOOR := 0.45
const DEATH_PER_UNCLEARED_SHARE := 4.0
const XP_FROM_LOOT_BONUS := 0.0

## Effects that make the phase harder or easier for this bot. Defaults are neutral.
class Effects extends RefCounted:
	## Multiplies how many monsters arrive and how tough they are (a "double spawns" modifier is 2.0).
	var threat_mult := 1.0
	## Added on top of the difficulty (sabotage from rivals raises it).
	var extra_difficulty := 0.0
	## Perk strength: 1.0 is none, 1.15 means the bot kills 15% faster.
	var power_mult := 1.0


static func skill_for_level(level: int) -> float:
	return SKILL_BY_LEVEL[clampi(level, 0, SKILL_BY_LEVEL.size() - 1)]


## The total score-value of every monster in the wave schedule of a phase, before the boss.
static func wave_threat(config: PveConfig, monsters: MonsterCatalog, seed_value: int, player_id: int) -> Dictionary:
	var counts := {}
	var wave := 0
	var elapsed := 0.0
	while elapsed < config.phase_seconds:
		wave += 1
		var size := roundi((config.base_wave_size + config.wave_growth * (wave - 1)) * config.difficulty)
		size = mini(size, config.alive_cap)
		for i in size:
			var type_id := _type_for(config, wave, i, seed_value, player_id)
			counts[type_id] = counts.get(type_id, 0) + 1
		elapsed += config.wave_interval
	return {"counts": counts, "waves": wave}


static func simulate(skill: float, config: PveConfig, monsters: MonsterCatalog, seed_value: int, player_id: int,
		effects: Effects = null) -> PveResult:
	if effects == null:
		effects = Effects.new()
	var result := PveResult.new()
	result.player_id = player_id
	var difficulty := maxf(config.difficulty + effects.extra_difficulty, 0.25)
	result.difficulty = difficulty
	var run_config := config.duplicate() as PveConfig
	run_config.difficulty = difficulty
	var threat := wave_threat(run_config, monsters, seed_value, player_id)
	var counts: Dictionary = threat.counts

	var noise := 1.0 + (_roll(seed_value, player_id, 1) - 0.5) * 2.0 * NOISE
	var strength := skill * effects.power_mult * noise
	var load_factor := difficulty * effects.threat_mult
	var clear_share := clampf(MAX_CLEAR_SHARE * strength / maxf(load_factor, 0.25), 0.0, MAX_CLEAR_SHARE)

	var total_value := 0
	for type_id: StringName in counts:
		var def := monsters.get_def(type_id)
		var cleared := roundi(float(counts[type_id]) * clear_share)
		for i in cleared:
			result.add_kill(type_id)
		total_value += def.score_value * int(counts[type_id])
		result.xp += def.xp * cleared
		result.sabotage_points += def.sabotage_points * cleared
	var uncleared_share := 1.0 - clear_share
	result.deaths = int(floor(uncleared_share * DEATH_PER_UNCLEARED_SHARE * minf(load_factor, 2.0) * (0.6 + _roll(seed_value, player_id, 2) * 0.8)))
	result.waves_survived = threat.waves if result.deaths < 3 else maxi(threat.waves - result.deaths, 0)
	result.duration_seconds = run_config.phase_seconds

	if run_config.boss_enabled and _boss_defeated(strength, load_factor, result.deaths, seed_value, player_id):
		var boss := monsters.get_def(run_config.boss_id)
		result.boss_defeated = true
		result.add_kill(run_config.boss_id)
		result.xp += boss.xp
		result.sabotage_points += boss.sabotage_points
		result.boss_time_seconds = clampf(boss.max_hp / (30.0 * strength) + 20.0, 20.0, run_config.boss_time_limit)
		result.reason = &"boss_defeated"
	else:
		result.reason = &"boss_timeout" if run_config.boss_enabled else &"time_up"
	_roll_weapon_loot(result, clear_share, seed_value, player_id)
	result.score = PveScoring.score(result, monsters)
	return result


## A stronger phase means more and better gear: each weapon is found with a chance that rises
## with how much the bot cleared, and a chance of a second copy (a tier-up).
static func _roll_weapon_loot(result: PveResult, clear_share: float, seed_value: int, player_id: int) -> void:
	var weapons: Array[StringName] = [&"sword", &"bow", &"orb", &"pistol"]
	for i in weapons.size():
		var chance := clampf(0.12 + 0.7 * clear_share, 0.0, 0.9) * (0.75 if weapons[i] == &"orb" else 1.0)
		if _roll(seed_value, player_id, 200 + i) < chance:
			result.weapon_loot.append(weapons[i])
			result.loot.append(String(weapons[i]).capitalize())
			if _roll(seed_value, player_id, 300 + i) < chance * 0.5:
				result.weapon_loot.append(weapons[i])
				result.loot.append(String(weapons[i]).capitalize())


## Chance the boss falls, as a deterministic yes/no from the seed.
static func boss_chance(strength: float, load_factor: float, deaths: int) -> float:
	var margin := strength / maxf(load_factor, 0.25) - BOSS_SKILL_FLOOR
	return clampf(margin * 2.2 - 0.12 * deaths, 0.0, 0.97)


static func _boss_defeated(strength: float, load_factor: float, deaths: int, seed_value: int, player_id: int) -> bool:
	return _roll(seed_value, player_id, 3) < boss_chance(strength, load_factor, deaths)


## Same type-mix rule the real director uses, reproduced here so bots face the same waves.
static func _type_for(config: PveConfig, wave: int, index: int, seed_value: int, player_id: int) -> StringName:
	var weights := {&"grunt": PveDirector.GRUNT_WEIGHT}
	if wave >= config.spitter_from_wave:
		weights[&"spitter"] = PveDirector.SPITTER_WEIGHT
	if wave >= config.brute_from_wave:
		weights[&"brute"] = PveDirector.BRUTE_WEIGHT
	var total := 0.0
	for id: StringName in weights:
		total += weights[id]
	var target := _roll(seed_value, player_id, 100 + wave * 40 + index) * total
	for id: StringName in [&"grunt", &"spitter", &"brute"]:
		if not weights.has(id):
			continue
		target -= weights[id]
		if target < 0.0:
			return id
	return &"grunt"


static func _roll(seed_value: int, player_id: int, salt: int) -> float:
	return float(hash([seed_value, player_id, salt, 77]) & 0xFFFFFF) / float(0x1000000)
