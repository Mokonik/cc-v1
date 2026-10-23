class_name MovementConfig
extends Resource
## All first-person movement and camera-feel tuning in one place.
## Edit player/default_movement.tres in the inspector (or in a running game via the
## remote tree) to retune; nothing else needs to change.

@export_group("Speed")
## Top speed while walking, in m/s.
@export_range(1.0, 20.0, 0.1) var walk_speed := 6.0
## Top speed while sprinting forward, in m/s.
@export_range(1.0, 30.0, 0.1) var sprint_speed := 9.0

@export_group("Ground")
## How quickly speed builds toward the wish speed (higher = snappier).
@export_range(1.0, 60.0, 0.5) var ground_accel := 12.0
## How quickly speed bleeds off when on the ground.
@export_range(0.0, 30.0, 0.5) var ground_friction := 8.0
## Friction acts as if you were at least this fast, so slow slides still stop promptly.
@export_range(0.1, 6.0, 0.1) var stop_speed := 2.0

@export_group("Air")
## Air steering strength. Low values keep momentum, high values feel floaty/controllable.
@export_range(0.0, 30.0, 0.5) var air_accel := 3.0
## Gravity in m/s^2 while rising.
@export_range(5.0, 60.0, 0.5) var gravity := 20.0
## Gravity is multiplied by this while falling, which makes jumps feel weighty.
@export_range(1.0, 3.0, 0.05) var fall_gravity_multiplier := 1.5

@export_group("Jump")
## Apex height of a fully held jump, in meters.
@export_range(0.3, 3.0, 0.05) var jump_height := 1.2
## Releasing jump while rising multiplies upward speed by this (1 = no variable height).
@export_range(0.1, 1.0, 0.05) var jump_cut := 0.5
## Grace period after leaving a ledge during which a jump still works.
@export_range(0.0, 0.3, 0.01) var coyote_time := 0.12
## A jump pressed this long before landing still fires on touchdown.
@export_range(0.0, 0.3, 0.01) var jump_buffer_time := 0.12

@export_group("Camera")
## Highest/lowest look angle in radians (just under straight up/down).
@export_range(0.5, 1.57, 0.01) var max_pitch := 1.5
## Look smoothing rate. 0 = raw mouse; ~25-40 adds a hint of weight.
@export_range(0.0, 80.0, 1.0) var look_smoothing := 0.0
## Extra FOV (degrees) at full sprint.
@export_range(0.0, 30.0, 0.5) var sprint_fov_kick := 8.0
@export_range(1.0, 30.0, 0.5) var fov_smoothing := 10.0
## Sideways camera roll (degrees) at full strafe speed.
@export_range(0.0, 6.0, 0.1) var strafe_tilt_deg := 1.5
@export_range(1.0, 30.0, 0.5) var tilt_smoothing := 12.0

@export_group("Head bob and landing")
## Meters of bob travel per radian of step phase; higher = faster steps.
@export_range(0.0, 3.0, 0.05) var bob_frequency := 1.6
## Bob height in meters at full speed.
@export_range(0.0, 0.1, 0.002) var bob_amplitude := 0.035
@export_range(1.0, 20.0, 0.5) var bob_blend_speed := 8.0
## Camera dip in meters per m/s of landing speed, capped by land_dip_max.
@export_range(0.0, 0.1, 0.002) var land_dip_per_speed := 0.012
@export_range(0.0, 0.5, 0.01) var land_dip_max := 0.18
@export_range(1.0, 30.0, 0.5) var land_recover := 9.0


## Upward launch speed that yields jump_height at the current rising gravity.
func jump_velocity() -> float:
	return sqrt(2.0 * gravity * jump_height)
