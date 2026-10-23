class_name PveScoring
extends RefCounted
## The one scoring formula for a PvE phase, shared by humans and bots so the match loop can
## compare them fairly. Points per kill come from each MonsterDef, then:
##   + a bonus for defeating the boss, + a little for every wave survived, - a penalty per death,
## and the total is scaled by difficulty so a harder phase is worth more.

const BOSS_BONUS := 100
const WAVE_BONUS := 15
const DEATH_PENALTY := 40


static func score(result: PveResult, monsters: MonsterCatalog) -> int:
	var points := 0
	for def_id: StringName in result.kills:
		var def := monsters.get_def(def_id)
		if def != null:
			points += def.score_value * int(result.kills[def_id])
	if result.boss_defeated:
		points += BOSS_BONUS
	points += WAVE_BONUS * result.waves_survived
	points -= DEATH_PENALTY * result.deaths
	return roundi(maxf(float(points), 0.0) * difficulty_factor(result.difficulty))


## Difficulty 1.0 is neutral; 2.0 is worth 50% more, 0.5 is worth 25% less.
static func difficulty_factor(difficulty: float) -> float:
	return 0.5 + 0.5 * difficulty
