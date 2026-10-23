class_name InputSource
extends Node
## Produces a PlayerCommand every physics tick. Attach as a child of a Player.
## Implementations: LocalInputSource (keyboard and mouse), BotInputSource (AI),
## and later NetworkInputSource.


func poll(_delta: float) -> PlayerCommand:
	return PlayerCommand.new()


## True if this source drives the player whose camera the local screen shows.
func is_local_view() -> bool:
	return false


## Called when the view is set from outside (spawning, teleports) so the source adopts it.
func set_view(_yaw: float, _pitch: float) -> void:
	pass
