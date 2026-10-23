# Pure-logic tests for the match rules: ledger, twist scoring, wager settlement, config.
# No scene tree is needed, so these run instantly.
# Run with: pvpve/tools/godot.sh --headless --script res://tests/test_match_rules.gd
extends SceneTree

var _failures := 0


func _initialize() -> void:
	_test_config()
	_test_ledger()
	_test_ranking_and_leader()
	_test_pvp_points_and_kinds()
	_test_classification()
	_test_normal_kill()
	_test_skill_kill()
	_test_showstopper()
	_test_scoring_conserves_points()
	_test_scorer_events()
	_test_wager_stakes()
	_test_wager_payouts()
	_test_wager_settlement()
	print("match rules tests: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _config() -> MatchConfig:
	return load("res://content/match_config.tres")


# ---- config ------------------------------------------------------------------------------------

func _test_config() -> void:
	print("config")
	var config := _config()
	_check(config.cycles == 3 and config.pve_seconds == 240.0 and config.pvp_seconds == 120.0, "defaults: 3 cycles, 240 s PvE, 120 s PvP")
	_check(config.kill_points == 10 and config.leader_bounty == 25 and config.skill_bonus == 25, "kill 10, bounty 25, skill bonus 25")
	_check(is_equal_approx(config.skill_steal_fraction, 0.5) and is_equal_approx(config.skill_min_arrow_distance, 18.0), "skill kills steal half; arrows count from 18 m")
	_check(config.showstopper_standings_cap == 150 and is_equal_approx(config.showstopper_standings_fraction, 0.15), "showstopper takes 15% capped at 150")
	_check(config.stake_options == PackedFloat32Array([0.0, 0.25, 0.5]), "stakes are 0, 25 and 50%")
	_check(config.final_points == PackedInt32Array([400, 200, 100, 0]), "final points 400/200/100/0")
	_check(is_equal_approx(config.leader_difficulty_bonus, 0.35), "the leader's PvE is 0.35 harder")
	var fast := MatchPresets.fast()
	_check(fast.pve_seconds < config.pve_seconds and fast.pvp_seconds < config.pvp_seconds and fast.final_seconds < config.final_seconds, "the fast preset has shorter phases")
	_check(fast.cycles == config.cycles and fast.kill_points == config.kill_points, "but the same cycles and scoring")
	_check(config.stake_for(200, 0) == 0 and config.stake_for(200, 1) == 50 and config.stake_for(200, 2) == 100, "stake_for converts an option to points")


# ---- ledger ---------------------------------------------------------------------------------------

func _test_ledger() -> void:
	print("ledger")
	var standings := Standings.new()
	standings.register(1)
	standings.register(2)
	_check(standings.total(1) == 0 and standings.entries.is_empty(), "everyone starts at zero")
	standings.add(1, 1, &"pve", 120, "phase")
	standings.add(1, 1, &"kill", 10)
	standings.add(2, 1, &"pve", 90)
	_check(standings.total(1) == 130 and standings.total(2) == 90, "totals add up")
	standings.add(2, 1, &"kill", 0)
	_check(standings.entries.size() == 3, "a zero entry is not recorded")
	standings.add(3, 1, &"pve", 5)
	_check(standings.player_ids() == [1, 2, 3] and standings.total(3) == 5, "adding for an unknown player registers them")
	standings.add(1, 2, &"pve", 50)
	_check(standings.sum_kinds(1, [&"pve"]) == 170 and standings.sum_kinds(1, [&"pve"], 2) == 50 and standings.sum_kinds(1, [&"pve"], 1) == 120, "sums can be limited to kinds and a cycle")
	_check(standings.sum_kind(&"pve") == 120 + 90 + 5 + 50 and standings.sum_all() == standings.total(1) + standings.total(2) + standings.total(3), "sums across players")
	var mine := standings.entries_for(1)
	_check(mine.size() == 3 and mine[0].note == "phase" and mine[0].cycle == 1 and mine[0].kind == &"pve", "entries keep their cycle, kind and note, oldest first")
	standings.unregister(3)
	_check(not standings.player_ids().has(3), "players can leave the standings")
	standings.clear()
	_check(standings.entries.is_empty() and standings.total(1) == 0, "clear empties the ledger")


func _test_ranking_and_leader() -> void:
	print("ranking")
	var standings := Standings.new()
	_check(standings.leader() == 0 and standings.ranking().is_empty(), "no one registered means no leader")
	for id in [1, 2, 3, 4]:
		standings.register(id)
	standings.add(1, 1, &"pve", 100)
	standings.add(2, 1, &"pve", 300)
	standings.add(3, 1, &"pve", 200)
	_check(standings.ranking() == [2, 3, 1, 4], "ranked by total, highest first")
	_check(standings.leader() == 2 and standings.rank_of(2) == 1 and standings.rank_of(4) == 4, "leader and ranks")
	standings.add(1, 1, &"kill", 250)
	_check(standings.ranking() == [1, 2, 3, 4] and standings.leader() == 1, "points from kills move the ranking")
	standings.add(2, 1, &"kill", 50)
	_check(standings.ranking() == [2, 1, 3, 4], "a 350-350 tie goes to the player with more PvE points")
	var tie := Standings.new()
	for id in [1, 2, 3]:
		tie.register(id)
	tie.add(1, 1, &"kill", 100)
	tie.add(2, 1, &"pve", 100)
	tie.add(3, 1, &"pve", 100)
	_check(tie.ranking() == [2, 3, 1], "a tie goes to the higher PvE score, then the lower id")


func _test_pvp_points_and_kinds() -> void:
	print("pvp points")
	var standings := Standings.new()
	standings.add(1, 1, &"pve", 500)
	standings.add(1, 1, &"kill", 10)
	standings.add(1, 1, &"skill", 25)
	standings.add(1, 1, &"wager", -50)
	standings.add(1, 2, &"kill", 10)
	_check(standings.pvp_points(1, 1) == 35, "PvP points count kills and skill bonuses but not PvE or wagers (35)")
	_check(standings.pvp_points(1, 2) == 10 and standings.pvp_points(1, 3) == 0, "and are per cycle")
	standings.add(1, 1, &"steal", -20)
	standings.add(1, 1, &"reset", -5)
	standings.add(1, 1, &"flip", -3)
	_check(standings.pvp_points(1, 1) == 7, "steals, resets and flips count as PvP points (35 - 28 = 7)")


# ---- classification -----------------------------------------------------------------------------------

func _test_classification() -> void:
	print("classification")
	var config := _config()
	var C := PvpRules.KillClass
	_check(PvpRules.classify(config, &"pistol", 10.0, false, false, true, false) == C.NORMAL, "a plain pistol kill is normal")
	_check(PvpRules.classify(config, &"sword", 2.0, false, false, true, false) == C.SKILL, "a sword kill is a skill kill")
	_check(PvpRules.classify(config, &"bow", 20.0, false, true, true, false) == C.SKILL, "a full-power arrow from 20 m is a skill kill")
	_check(PvpRules.classify(config, &"bow", 18.0, false, true, true, false) == C.SKILL, "exactly 18 m counts")
	_check(PvpRules.classify(config, &"bow", 17.9, false, true, true, false) == C.NORMAL, "17.9 m does not")
	_check(PvpRules.classify(config, &"bow", 30.0, false, false, true, false) == C.NORMAL, "a weak arrow from far away is normal")
	_check(PvpRules.classify(config, &"orb", 30.0, false, false, true, false) == C.NORMAL, "a direct orb kill from far away is normal")
	_check(PvpRules.classify(config, &"orb", 5.0, false, false, false, false) == C.NORMAL, "a splash kill is normal")
	_check(PvpRules.classify(config, &"pistol", 10.0, true, false, true, false) == C.SKILL, "any kill on an airborne victim is a skill kill")
	_check(PvpRules.classify(config, &"orb", 5.0, true, false, false, false) == C.SKILL, "including a splash kill on an airborne victim")
	_check(PvpRules.classify(config, &"sword", 2.0, false, false, true, true) == C.SHOWSTOPPER, "a skill kill on the marked leader is a showstopper")
	_check(PvpRules.classify(config, &"pistol", 10.0, false, false, true, true) == C.NORMAL, "but a plain kill on the leader is only normal")
	_check(PvpRules.classify(config, &"pistol", 10.0, true, false, true, true) == C.SHOWSTOPPER, "and an airborne kill on the leader is a showstopper")


# ---- scoring --------------------------------------------------------------------------------------------------

func _stand(players: Array[int], pve: Array[int]) -> Standings:
	var standings := Standings.new()
	for i in players.size():
		standings.add(players[i], 1, &"pve", pve[i])
	return standings


func _test_normal_kill() -> void:
	print("normal kill")
	var config := _config()
	var standings := _stand([1, 2], [100, 100])
	var moved := PvpRules.score_kill(config, standings, 1, 1, 2, PvpRules.KillClass.NORMAL, false)
	_check(standings.total(1) == 110 and standings.total(2) == 100, "the killer gains 10 and the victim loses nothing")
	_check(moved.killer_gain == 10 and moved.victim_loss == 0, "and the result reports it")
	var bounty := PvpRules.score_kill(config, standings, 1, 1, 2, PvpRules.KillClass.NORMAL, true)
	_check(standings.total(1) == 110 + 10 + 25 and bounty.killer_gain == 35, "killing the marked leader adds the 25 bounty")
	_check(standings.sum_kind(&"bounty") == 25 and standings.sum_kind(&"kill") == 20, "recorded as separate entries")


func _test_skill_kill() -> void:
	print("skill kill")
	var config := _config()
	var standings := _stand([1, 2], [100, 100])
	standings.add(2, 1, &"kill", 40)
	standings.add(2, 1, &"skill", 20)
	standings.add(2, 1, &"pve", 0)
	# The victim has 60 PvP points this match.
	var moved := PvpRules.score_kill(config, standings, 1, 1, 2, PvpRules.KillClass.SKILL, false)
	_check(standings.pvp_points(2, 1) == 30 and standings.total(2) == 100 + 60 - 30, "the victim loses half of their 60 PvP points (30)")
	_check(standings.total(1) == 100 + 10 + 25 + 30, "the killer gains kill 10, skill bonus 25 and the 30 stolen")
	_check(moved.killer_gain == 65 and moved.victim_loss == 30, "reported as +65 and -30")
	_check(standings.sum_kind(&"steal") == 0, "the steal is zero-sum")

	var broke := _stand([1, 2], [100, 100])
	PvpRules.score_kill(config, broke, 1, 1, 2, PvpRules.KillClass.SKILL, false)
	_check(broke.total(2) == 100 and broke.sum_kind(&"steal") == 0, "a victim with no PvP points loses nothing")
	var negative := _stand([1, 2], [100, 100])
	negative.add(2, 1, &"steal", -40)
	PvpRules.score_kill(config, negative, 1, 1, 2, PvpRules.KillClass.SKILL, false)
	_check(negative.total(2) == 60, "a victim whose PvP points are negative loses nothing more")
	var odd := _stand([1, 2], [0, 0])
	odd.add(2, 1, &"kill", 15)
	PvpRules.score_kill(config, odd, 1, 1, 2, PvpRules.KillClass.SKILL, false)
	_check(odd.total(2) == 15 - 7, "the stolen share is rounded down (7 of 15)")


func _test_showstopper() -> void:
	print("showstopper")
	var config := _config()
	var standings := _stand([1, 2], [100, 1000])
	standings.add(2, 1, &"kill", 80)
	standings.add(2, 1, &"skill", 20)
	# Victim: 1000 PvE + 100 PvP this match = 1100 standings.
	var moved := PvpRules.score_kill(config, standings, 1, 1, 2, PvpRules.KillClass.SHOWSTOPPER, true)
	var victim_total := standings.total(2)
	# wiped 100, flip min(floor(1100*0.15)=165, cap 150)=150 -> 1100 - 100 - 150 = 850
	_check(victim_total == 850, "the victim's PvP points are wiped (100) and 150 comes off their standings (cap): %d" % victim_total)
	# killer: 100 + kill 10 + bounty 25 + skill 25 + steal floor(100*0.5)=50 + flip floor(150*0.5)=75
	_check(standings.total(1) == 100 + 10 + 25 + 25 + 50 + 75, "the killer collects kill, bounty, skill bonus, half the wiped points and half the slice: %d" % standings.total(1))
	_check(moved.killer_gain == 185 and moved.victim_loss == 250, "reported as +185 and -250")
	# 1200 combined before; +60 minted (kill, bounty, skill); 125 destroyed (50 of the wiped points, 75 of the slice).
	_check(standings.total(1) + standings.total(2) == 1200 + 60 - 125, "the table flip destroys exactly 125 points: the half of each pot the killer does not collect")

	var small := _stand([1, 2], [0, 200])
	PvpRules.score_kill(config, small, 1, 1, 2, PvpRules.KillClass.SHOWSTOPPER, true)
	_check(small.total(2) == 200 - 30, "below the cap the slice is 15% of standings (30 of 200)")
	var broke := _stand([1, 2], [0, 0])
	PvpRules.score_kill(config, broke, 1, 1, 2, PvpRules.KillClass.SHOWSTOPPER, true)
	_check(broke.total(2) == 0 and broke.total(1) == 10 + 25 + 25, "a victim with nothing loses nothing, the killer still gets the fixed bonuses")
	var negative := _stand([1, 2], [0, 0])
	negative.add(2, 1, &"wager", -100)
	PvpRules.score_kill(config, negative, 1, 1, 2, PvpRules.KillClass.SHOWSTOPPER, true)
	_check(negative.total(2) == -100, "a negative total is never cut further")


func _random_kills(standings: Standings, kinds: Array, seed_value: int) -> void:
	var config := _config()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 80:
		var killer := rng.randi_range(1, 3)
		var victim := rng.randi_range(1, 3)
		if killer == victim:
			continue
		var kill_class: PvpRules.KillClass = kinds[rng.randi_range(0, kinds.size() - 1)]
		PvpRules.score_kill(config, standings, 1, killer, victim, kill_class, victim == 2)


func _test_scoring_conserves_points() -> void:
	print("conservation")
	var C := PvpRules.KillClass
	var plain := _stand([1, 2, 3], [200, 300, 100])
	var before := plain.sum_all()
	_random_kills(plain, [C.NORMAL, C.SKILL], 42)
	var minted := plain.sum_kind(&"kill") + plain.sum_kind(&"bounty") + plain.sum_kind(&"skill")
	_check(plain.sum_kind(&"steal") == 0, "over 80 random normal and skill kills, steals net to exactly zero")
	_check(plain.sum_all() == before + minted and minted > 0, "and the only change to the total is the minted kill, bounty and skill points (%d)" % minted)
	_check(plain.sum_kind(&"reset") == 0 and plain.sum_kind(&"flip") == 0, "with no showstoppers nothing is destroyed")

	var wild := _stand([1, 2, 3], [200, 300, 100])
	var wild_before := wild.sum_all()
	_random_kills(wild, [C.NORMAL, C.SKILL, C.SHOWSTOPPER], 7)
	var wild_minted := wild.sum_kind(&"kill") + wild.sum_kind(&"bounty") + wild.sum_kind(&"skill")
	var destroyed := -(wild.sum_kind(&"steal") + wild.sum_kind(&"reset") + wild.sum_kind(&"flip"))
	_check(wild.sum_all() == wild_before + wild_minted - destroyed, "with showstoppers, total = start + minted - destroyed, exactly")
	_check(destroyed >= 0 and wild.sum_kind(&"reset") <= 0 and wild.sum_kind(&"flip") <= 0, "and what is destroyed is never negative (%d)" % destroyed)
	_check(wild.sum_kind(&"steal") + wild.sum_kind(&"reset") <= 0, "a showstopper steals no more than it wipes")


func _test_scorer_events() -> void:
	print("scorer")
	var config := _config()
	var events := EventBus.new()
	var standings := Standings.new()
	for id in [1, 2]:
		standings.register(id)
	standings.add(1, 1, &"pve", 100)
	standings.add(2, 1, &"pve", 500)
	var state := {"cycle": 1, "marked": 2}
	var scorer := PvpScorer.new()
	scorer.setup(events, standings, config, func() -> int: return state.cycle, func() -> int: return state.marked)
	var scored: Array[Dictionary] = []
	events.pvp_kill_scored.connect(func(killer: int, victim: int, kill_class: int, gain: int, loss: int) -> void:
		scored.append({"killer": killer, "victim": victim, "class": kill_class, "gain": gain, "loss": loss}))
	var changed := {"count": 0}
	events.standings_changed.connect(func() -> void: changed.count += 1)

	events.kill_detail.emit(2, 1, &"pistol", 10.0, false, false, true)
	_check(scored.is_empty() and standings.total(1) == 100, "nothing is scored while PvP is off")
	scorer.enabled = true
	events.kill_detail.emit(2, 1, &"pistol", 10.0, false, false, true)
	_check(scored.size() == 1 and scored[0].class == PvpRules.KillClass.NORMAL and scored[0].gain == 35 and changed.count == 1, "a normal kill on the marked leader scores kill plus bounty")
	events.kill_detail.emit(2, 1, &"sword", 2.0, false, false, true)
	_check(scored[1].class == PvpRules.KillClass.SHOWSTOPPER, "a sword kill on the marked leader is a showstopper")
	state.marked = 0
	events.kill_detail.emit(1, 2, &"sword", 2.0, false, false, true)
	_check(scored[2].class == PvpRules.KillClass.SKILL, "with no mark the same kill is an ordinary skill kill")
	var count := scored.size()
	events.kill_detail.emit(1, 1, &"pistol", 0.0, false, false, true)
	events.kill_detail.emit(1, 0, &"storm", 0.0, false, false, true)
	events.kill_detail.emit(1, 9, &"pistol", 5.0, false, false, true)
	events.kill_detail.emit(9, 2, &"pistol", 5.0, false, false, true)
	_check(scored.size() == count, "suicides, environment deaths and non-members are ignored")
	state.cycle = 2
	events.kill_detail.emit(2, 1, &"pistol", 10.0, false, false, true)
	_check(standings.entries[standings.entries.size() - 1].cycle == 2, "entries are written to the current cycle")


# ---- wager -------------------------------------------------------------------------------------------------------

func _test_wager_stakes() -> void:
	print("wager stakes")
	var options := PackedFloat32Array([0.0, 0.25, 0.5])
	_check(WagerRules.stake_amount(400, 0, options) == 0 and WagerRules.stake_amount(400, 1, options) == 100 and WagerRules.stake_amount(400, 2, options) == 200, "stakes are 0, 25 and 50% of the total")
	_check(WagerRules.stake_amount(10, 1, options) == 2, "stakes round down (2 of 10)")
	_check(WagerRules.stake_amount(-50, 2, options) == 0, "you cannot stake points you do not have")
	_check(WagerRules.stake_amount(100, 7, options) == 0 and WagerRules.stake_amount(100, -1, options) == 0, "an invalid option stakes nothing")


func _test_wager_payouts() -> void:
	print("wager payouts")
	for count in [1, 2, 3, 4]:
		var shares := WagerRules.payout_shares(count)
		var sum := 0.0
		for share in shares:
			sum += share
		_check(shares.size() == count and is_equal_approx(sum, 1.0), "%d players: %d shares that add up to 100%%" % [count, count])
	_check(WagerRules.payout_shares(4) == [0.5, 0.3, 0.15, 0.05] and WagerRules.payout_shares(3) == [0.55, 0.30, 0.15] and WagerRules.payout_shares(2) == [0.7, 0.3], "the 4, 3 and 2 player tables")
	_check(WagerRules.payout_shares(9).size() == 4, "more than four players uses the four-player table")


func _test_wager_settlement() -> void:
	print("wager settlement")
	var net := WagerRules.settle({1: 100, 2: 100, 3: 0, 4: 100}, [2, 1, 4, 3] as Array[int])
	# pot 300: 150, 90, 45, 15
	_check(net[2] == 150 - 100 and net[1] == 90 - 100 and net[4] == 45 - 100 and net[3] == 15, "a four-player pot is paid 50/30/15/5 by placement")
	var sum := 0
	for id in net:
		sum += net[id]
	_check(sum == 0, "settlement is exactly zero-sum")

	var odd := WagerRules.settle({1: 7, 2: 3}, [1, 2] as Array[int])
	# pot 10: 7 and 3.
	_check(odd[1] == 0 and odd[2] == 0, "two players: 70/30 of a 10 pot")
	var rounding := WagerRules.settle({1: 11, 2: 0, 3: 0}, [3, 1, 2] as Array[int])
	# pot 11: floor(6.05)=6, floor(3.3)=3, floor(1.65)=1 -> paid 10, 1 left over to 1st
	var rounding_sum := 0
	for id in rounding:
		rounding_sum += rounding[id]
	_check(rounding[3] == 7 and rounding[1] == 3 - 11 and rounding[2] == 1, "the rounding leftover goes to first place (%s)" % [rounding])
	_check(rounding_sum == 0, "and it is still zero-sum")

	var nobody := WagerRules.settle({1: 0, 2: 0}, [1, 2] as Array[int])
	_check(nobody[1] == 0 and nobody[2] == 0, "an empty pot changes nothing")
	var winner_takes_back := WagerRules.settle({1: 50}, [1] as Array[int])
	_check(winner_takes_back[1] == 0, "a lone player gets their stake back")
	var keeps := WagerRules.settle({1: 0, 2: 200}, [1, 2] as Array[int])
	_check(keeps[1] == 140 and keeps[2] == 200 * 3 / 10 - 200, "staking nothing keeps your points and can still collect the pot")
	var big_loser := WagerRules.settle({1: 200, 2: 200, 3: 200}, [2, 3, 1] as Array[int])
	_check(big_loser[1] == 90 - 200 and big_loser[2] == 330 - 200 and big_loser[3] == 180 - 200, "a last-place all-in bettor loses most of the stake (%s)" % [big_loser])
