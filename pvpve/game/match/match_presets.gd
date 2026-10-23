class_name MatchPresets
extends RefCounted
## Ready-made match settings. Kept apart from MatchConfig because a script that builds
## instances of itself from a static function is reported as leaked at exit.


## Short phases for tests and for trying the loop quickly with `match fast`.
static func fast() -> MatchConfig:
	var config := MatchConfig.new()
	config.pve_seconds = 20.0
	config.pve_results_seconds = 2.0
	config.wager_seconds = 3.0
	config.pvp_countdown_seconds = 2.0
	config.pvp_seconds = 25.0
	config.pvp_results_seconds = 3.0
	config.final_seconds = 30.0
	config.victory_seconds = 3.0
	return config
