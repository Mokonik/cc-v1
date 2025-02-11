extends CharacterBody2D


const SPEED = 130.0
const JUMP_VELOCITY = -300
const ACCELERATION = 5
const FRICTION = 10
# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = 800
@onready var animated_sprite = $AnimatedSprite2D
 
enum state {IDLE, RUNNING, JUMPING, ROLLING}
var player_state = state.IDLE



func animation_player():
	match(player_state):
		state.IDLE:
			animated_sprite.play("idle")
		state.RUNNING:
			animated_sprite.play("run")
		state.ROLLING:
			animated_sprite.play("roll")
		state.JUMPING:
			animated_sprite.play("in_the_air")

func get_input():
	var direction = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	if direction != 0:
		velocity.x = move_toward(velocity.x, direction * SPEED, ACCELERATION)
	else:
		velocity.x = move_toward(velocity.x, 0, FRICTION)
		
func _physics_process(delta):
	if not is_on_floor():
		velocity.y += gravity * delta
	get_input()
	print(velocity)
	if velocity.x == 0 and player_state != state.ROLLING:
		player_state = state.IDLE
	elif velocity.x != 0 and Input.is_action_just_pressed("shift") and is_on_floor():
		player_state = state.ROLLING
		velocity.x *= 2.5
	elif velocity.x !=0 and is_on_floor() and player_state != state.ROLLING:
		player_state = state.RUNNING
	elif not is_on_floor():
		player_state = state.JUMPING
	
	
	
	if is_on_floor() and player_state != state.ROLLING and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY
		player_state = state.JUMPING
	
	if velocity.x > 0:
		animated_sprite.flip_h = false
	elif velocity.x < 0:
		animated_sprite.flip_h = true
	
	animation_player()

#func move_player(direction, distance):
		#velocity.x = SPEED * direction * distance
#func basic_controlls():
	#if Input.is_action_just_pressed("jump") and is_on_floor():
		#velocity.y = JUMP_VELOCITY
	#var direction = Input.get_axis("move_left", "move_right")
	#if direction > 0:
		#animated_sprite.play("run")
		#animated_sprite.flip_h = false
	#elif direction < 0:
		#animated_sprite.play("run")
		#animated_sprite.flip_h = true
	#elif direction == 0:
		#animated_sprite.play("idle")
	#if not is_on_floor():
		#animated_sprite.play("in_the_air")
	#move_player(direction, 1)
#
##rolling test
#func roll():
	#var timer = 60
	#animated_sprite.play("roll")
	#while timer > 0:
		#move_player(1, 5)
		#timer -= 1
#
#func _physics_process(delta):
	## Add the gravity.
	#if not is_on_floor():
		#velocity.y += gravity * delta
	#basic_controlls()
	#
	## testing rolling
	#if Input.is_action_just_pressed("shift"):
		#var timer = 60
		#animated_sprite.play("roll")
		#while timer > 0:
			#move_player(1, 5)
			#timer -= 1
	#
	#if velocity.x == 0:
		#
	
	move_and_slide()
	


func _on_animated_sprite_2d_animation_finished():
	player_state = state.IDLE
