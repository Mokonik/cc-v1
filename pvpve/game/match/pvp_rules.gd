class_name PvpRules
extends RefCounted
## How a PvP kill is scored, including the twist that lets one skillful kill flip the table.
## Pure logic over a Standings ledger and a MatchConfig, so every rule is unit-testable.
##
## Kill classes:
##   NORMAL       killer +kill_points (+leader_bounty if the victim wears the mark)
##   SKILL        a hard kill (sword, full-power arrow from far away, victim in the air): killer also
##                gets skill_bonus and steals a share of the victim's PvP points from this match
##   SHOWSTOPPER  a skill kill on the marked leader: the victim's PvP points this match are wiped,
##                the killer steals a share of them, and the victim also loses a slice of their
##                total standings, half of which the killer collects

enum KillClass { NORMAL, SKILL, SHOWSTOPPER }

const SWORD := &"sword"
const BOW := &"bow"


static func is_skill_kill(config: MatchConfig, weapon_id: StringName, distance: float, airborne: bool,
		full_power: bool, direct: bool) -> bool:
	if weapon_id == SWORD:
		return true
	if weapon_id == BOW and full_power and direct and distance >= config.skill_min_arrow_distance:
		return true
	return airborne


static func classify(config: MatchConfig, weapon_id: StringName, distance: float, airborne: bool,
		full_power: bool, direct: bool, victim_is_marked: bool) -> KillClass:
	if not is_skill_kill(config, weapon_id, distance, airborne, full_power, direct):
		return KillClass.NORMAL
	return KillClass.SHOWSTOPPER if victim_is_marked else KillClass.SKILL


## Writes the ledger entries for one kill and returns {"killer_gain", "victim_loss"} (both
## whole-number totals of what moved, for display). Amounts are all computed from the totals as
## they stand before this kill's own entries.
static func score_kill(config: MatchConfig, standings: Standings, cycle: int, killer_id: int, victim_id: int,
		kill_class: KillClass, victim_is_marked: bool) -> Dictionary:
	var killer_gain := 0
	var victim_loss := 0
	var victim_pvp := maxi(standings.pvp_points(victim_id, cycle), 0)
	var victim_total := standings.total(victim_id)

	standings.add(killer_id, cycle, &"kill", config.kill_points, "killed %d" % victim_id)
	killer_gain += config.kill_points
	if victim_is_marked:
		standings.add(killer_id, cycle, &"bounty", config.leader_bounty, "bounty on %d" % victim_id)
		killer_gain += config.leader_bounty

	if kill_class == KillClass.NORMAL:
		return {"killer_gain": killer_gain, "victim_loss": victim_loss}

	standings.add(killer_id, cycle, &"skill", config.skill_bonus, "skill kill on %d" % victim_id)
	killer_gain += config.skill_bonus
	var stolen := floori(float(victim_pvp) * config.skill_steal_fraction)

	if kill_class == KillClass.SKILL:
		standings.add(victim_id, cycle, &"steal", -stolen, "robbed by %d" % killer_id)
		standings.add(killer_id, cycle, &"steal", stolen, "stole from %d" % victim_id)
		killer_gain += stolen
		victim_loss += stolen
		return {"killer_gain": killer_gain, "victim_loss": victim_loss}

	# Showstopper: wipe the victim's PvP points, the killer still steals a share, then a slice of standings.
	standings.add(victim_id, cycle, &"reset", -victim_pvp, "wiped by %d" % killer_id)
	standings.add(killer_id, cycle, &"steal", stolen, "stole from %d" % victim_id)
	var slice := mini(floori(float(maxi(victim_total, 0)) * config.showstopper_standings_fraction), config.showstopper_standings_cap)
	var slice_to_killer := floori(float(slice) * config.showstopper_killer_share)
	standings.add(victim_id, cycle, &"flip", -slice, "table flipped by %d" % killer_id)
	standings.add(killer_id, cycle, &"flip", slice_to_killer, "table flip on %d" % victim_id)
	killer_gain += stolen + slice_to_killer
	victim_loss += victim_pvp + slice
	return {"killer_gain": killer_gain, "victim_loss": victim_loss}
