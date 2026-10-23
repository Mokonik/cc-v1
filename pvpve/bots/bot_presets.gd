class_name BotPresets
extends RefCounted
## Ready-made bot skill levels. Kept apart from BotProfile because a script that
## instantiates itself from a static function leaves a reference cycle at exit.


## 0 = easy, 1 = normal, 2 = hard.
static func make(level: int) -> BotProfile:
	var profile := BotProfile.new()
	profile.skill_level = clampi(level, 0, 2)
	match clampi(level, 0, 2):
		0:
			profile.display_name = "Rookie"
			profile.aim_speed_deg = 110.0
			profile.aim_error_deg = 6.0
			profile.reaction_time = 0.6
			profile.engage_distance = 9.0
			profile.min_distance = 4.0
		1:
			profile.display_name = "Regular"
		2:
			profile.display_name = "Veteran"
			profile.aim_speed_deg = 380.0
			profile.aim_error_deg = 1.0
			profile.reaction_time = 0.12
			profile.engage_distance = 14.0
			profile.min_distance = 7.0
			profile.strafe_interval = Vector2(0.5, 1.4)
	return profile
