extends CharacterBody3D
## Credits:
# Special thanks to Majikayo Games for original solution to stair_step_down!
# (https://youtu.be/-WjM1uksPIk)
#
# Special thanks to Myria666 for their paper on Quake movement mechanics (used for stair_step_up)!
# (https://github.com/myria666/qMovementDoc)
#
# Special thanks to Andicraft for their help with implementation stair_step_up!
# (https://github.com/Andicraft)

## Notes:
# 0. All shape colliders are supported. Although, I would recommend Capsule colliders for enemies
#		as it works better with the Navigation Meshes. Its up to you what shape you want to use
#		for players.
#
# 1. To adjust the step-up/down height, just change the MAX_STEP_UP/MAX_STEP_DOWN values below.
#
# 2. This uses Jolt Physics as the default Godot Physics has a few bugs:
#	1: Small gaps that you should be able to fit through both ways will block you in Godot Physics.
#		You can see this demonstrated with the floating boxes in front of the big stairs.
#	2: Walking into some objects may push the player downward by a small amount which causes
#		jittering and causes the floor to be detected as a step.
#	TLDR: This still works with default Godot Physics, although it feels a lot better in Jolt Physics.

#region ANNOTATIONS ################################################################################
@export_category("Player Settings")
@export var PLAYER_SPEED := 10.0		# Player's movement speed.
@export var JUMP_VELOCITY := 6.0		# Player's jump velocity.

@export var MAX_STEP_UP := 0.5			# Maximum height in meters the player can step up.
@export var MAX_STEP_DOWN := -0.5		# Maximum height in meters the player can step down.

@export var MOUSE_SENSITIVITY := 0.4	# Mouse movement sensitivity.
@export var CAMERA_SMOOTHING := 18.0	# Amount of camera smoothing.

@export_category("Debug Settings")
@export var STEP_DOWN_DEBUG := false	# Enable these to get detailed info on the step down/up process.
@export var STEP_UP_DEBUG := false

## Node References
@onready var CAMERA_NECK = $CameraNeck
@onready var CAMERA_HEAD = $CameraNeck/CameraHead
@onready var PLAYER_CAMERA = $CameraNeck/CameraHead/PlayerCamera

@onready var DEBUG_MENU = $PlayerHUD/DebugMenu
@onready var MAX_STEP_UP_LABEL = $PlayerHUD/DebugMenu/Margins/VBox/MaxStepUpLabel
@onready var MAX_STEP_DOWN_LABEL = $PlayerHUD/DebugMenu/Margins/VBox/MaxStepDownLabel
#endregion

#region VARIABLES ##################################################################################
var is_grounded := true					# If player is grounded this frame
var was_grounded := true				# If player was grounded last frame

var wish_dir := Vector3.ZERO			# Player input (WASD) direction

var vertical := Vector3(0, 1, 0)		# Shortcut for converting vectors to vertical
var horizontal := Vector3(1, 0, 1)		# Shortcut for converting vectors to horizontal

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")		# Default Gravity
#endregion

#region IMPLEMENTATION #############################################################################
# Function: On scene load
func _ready():
	# Capture mouse on start
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Function: Handle defined inputs
func _input(event):
	# Handle ESC input
	if event.is_action_pressed("mouse_toggle"):
		_toggle_mouse_mode()

	# Handle Debug input
	if event.is_action_pressed("debug_toggle"):
		DEBUG_MENU.visible = !DEBUG_MENU.visible

	# Handle Mouse input
	if event is InputEventMouseMotion and (Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED):
		_camera_input(event)

# Function: Handle camera input
func _camera_input(event):
	var y_rotation = deg_to_rad(-event.relative.x * MOUSE_SENSITIVITY)
	rotate_y(y_rotation)
	CAMERA_HEAD.rotate_y(y_rotation)
	PLAYER_CAMERA.rotate_x(deg_to_rad(-event.relative.y * MOUSE_SENSITIVITY))
	PLAYER_CAMERA.rotation.x = clamp(PLAYER_CAMERA.rotation.x, deg_to_rad(-90), deg_to_rad(90))

# Function: Handle mouse mode toggling
func _toggle_mouse_mode():
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Function: Handle frame-based processes
func _process(_delta):
	_debug_update_debug()

# Function: Handle frame-based physics processes
func _physics_process(delta):
	# Update player state
	was_grounded = is_grounded

	if is_on_floor():
		is_grounded = true
	else:
		is_grounded = false

	# Get player input direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Handle Gravity
	if !is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump
	if Input.is_action_pressed("move_jump"):
		velocity.y = JUMP_VELOCITY

	# Handle WASD Movement
	velocity.x = wish_dir.x * PLAYER_SPEED
	velocity.z = wish_dir.z * PLAYER_SPEED

	# Stair step up
	stair_step_up()

	# Move
	move_and_slide()

	# Stair step down
	stair_step_down()

	# Smooth Camera
	smooth_camera_jitter(delta)

# Function: Handle walking down stairs
func stair_step_down():
	if is_grounded:
		return

	# If we're falling from a step
	if velocity.y <= 0 and was_grounded:
		_debug_stair_step_down("SSD_ENTER", null)													## DEBUG

		# Initialize body test variables
		var body_test_result = PhysicsTestMotionResult3D.new()
		var body_test_params = PhysicsTestMotionParameters3D.new()

		body_test_params.from = self.global_transform			## We get the player's current global_transform
		body_test_params.motion = Vector3(0, MAX_STEP_DOWN, 0)	## We project the player downward

		if PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result):
			# Enters if a collision is detected by body_test_motion
			# Get distance to step and move player downward by that much
			position.y += body_test_result.get_travel().y
			apply_floor_snap()
			is_grounded = true
			_debug_stair_step_down("SSD_APPLIED", body_test_result.get_travel().y)					## DEBUG

# Function: Handle walking up stairs
func stair_step_up():
	if wish_dir == Vector3.ZERO:
		return

	_debug_stair_step_up("SSU_ENTER", null)															## DEBUG

	# 0. Initialize testing variables
	var body_test_params = PhysicsTestMotionParameters3D.new()
	var body_test_result = PhysicsTestMotionResult3D.new()

	var test_transform = global_transform				## Storing current global_transform for testing
	var distance = wish_dir * 0.1						## Distance forward we want to check
	body_test_params.from = self.global_transform		## Self as origin point
	body_test_params.motion = distance					## Go forward by current distance

	print("SSU_0: Var init")#!
	_debug_stair_step_up("SSU_TEST_POS", test_transform)											## DEBUG

	# Pre-check: Are we colliding?
	if !PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result):
		_debug_stair_step_up("SSU_EXIT_1", null)													## DEBUG

		## If we don't collide, return
		return

	# 1. Move test_transform to collision location
	var remainder = body_test_result.get_remainder()							## Get remainder from collision
	test_transform = test_transform.translated(body_test_result.get_travel())	## Move test_transform by distance traveled before collision

	print("SSU_1: Move transform to collision location")#!
	_debug_stair_step_up("SSU_REMAINING", remainder)												## DEBUG
	_debug_stair_step_up("SSU_TEST_POS", test_transform)											## DEBUG

	# 2. Move test_transform up to ceiling (if any)
	var step_up = MAX_STEP_UP * vertical
	body_test_params.from = test_transform
	body_test_params.motion = step_up
	PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result)
	test_transform = test_transform.translated(body_test_result.get_travel())

	print("SSU_2: Move transform up to ceiling/step_height")#!
	_debug_stair_step_up("SSU_TEST_POS", test_transform)											## DEBUG

	# 3. Move test_transform forward by remaining distance
	body_test_params.from = test_transform
	body_test_params.motion = remainder
	PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result)
	test_transform = test_transform.translated(body_test_result.get_travel())

	print("SSU_3: Move transform forward by remaining")#!
	_debug_stair_step_up("SSU_TEST_POS", test_transform)											## DEBUG

	# 3.5 Project remaining along wall normal (if any)
	## So you can walk into wall and up a step
	if body_test_result.get_collision_count() != 0:
		print("Collided at step height")#!
		remainder = body_test_result.get_remainder().length()

		### Uh, there may be a better way to calculate this in Godot.
		var wall_normal = body_test_result.get_collision_normal()
		var dot_div_mag = wish_dir.dot(wall_normal) / (wall_normal * wall_normal).length()
		var projected_vector = (wish_dir - dot_div_mag * wall_normal).normalized()

		body_test_params.from = test_transform
		body_test_params.motion = remainder * projected_vector
		PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result)
		test_transform = test_transform.translated(body_test_result.get_travel())

		_debug_stair_step_up("SSU_TEST_POS", test_transform)										## DEBUG
		print("Projection done")#!

	# 4. Move test_transform down onto step
	body_test_params.from = test_transform
	body_test_params.motion = MAX_STEP_UP * -vertical

	# Return if no collision
	if !PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result):
		_debug_stair_step_up("SSU_EXIT_2", null)													## DEBUG

		return

	print("SSU_4: Move transform down onto step")#!
	test_transform = test_transform.translated(body_test_result.get_travel())
	_debug_stair_step_up("SSU_TEST_POS", test_transform)											## DEBUG

	# 5. Check floor normal for un-walkable slope
	var surface_normal = body_test_result.get_collision_normal()

	print("SSU_5: Check for un-walkable slope")#!
	if (surface_normal.angle_to(vertical) > floor_max_angle):
		_debug_stair_step_up("SSU_EXIT_3", null)													## DEBUG

		return

	_debug_stair_step_up("SSU_TEST_POS", test_transform)											## DEBUG

	# 6. Move player up
	var global_pos = global_position
	var step_up_dist = test_transform.origin.y - global_pos.y
	print("SSU_6: Move player up")#!
	_debug_stair_step_up("SSU_APPLIED", step_up_dist)												## DEBUG

	global_pos.y = test_transform.origin.y
	global_position = global_pos

# Function: Smooth camera jitter
func smooth_camera_jitter(delta):
	CAMERA_HEAD.global_position.x = CAMERA_NECK.global_position.x
	CAMERA_HEAD.global_position.y = lerpf(CAMERA_HEAD.global_position.y, CAMERA_NECK.global_position.y, CAMERA_SMOOTHING * delta)
	CAMERA_HEAD.global_position.z = CAMERA_NECK.global_position.z

	# Limit how far camera can lag behind its desired position
	CAMERA_HEAD.global_position.y = clampf(CAMERA_HEAD.global_position.y,
										-CAMERA_NECK.global_position.y - 1,
										CAMERA_NECK.global_position.y + 1)

## Debugging #######################################################################################

# Debug: Stair Step Down
func _debug_stair_step_down(param, value):
	if STEP_DOWN_DEBUG == false:
		return

	match param:
		"SSD_ENTER":
			print()
			print("Stair step down entered")
		"SSD_APPLIED":
			print("Stair step down applied, travel = ", value)

# Debug: Stair Step Up
func _debug_stair_step_up(param, value):
	if STEP_UP_DEBUG == false:
		return

	match param:
		"SSU_ENTER":
			print()
			print("SSU: Stair step up entered")
		"SSU_EXIT_1":
			print("SSU: Exited with no collisions")
		"SSU_TEST_POS":
			print("SSU: test_transform current position = ", value)
		"SSU_REMAINING":
			print("SSU: Remaining distance = ", value)
		"SSU_EXIT_2":
			print("SSU: Exited due to no step collision")
		"SSU_EXIT_3":
			print("SSU: Exited due to non-floor stepping")
		"SSU_APPLIED":
			print("SSU: Player moved up by ", value, " units")

# Debug: Update Debug Menu
func _debug_update_debug():
	MAX_STEP_UP_LABEL.text = "MAX STEP UP = " + str(MAX_STEP_UP)
	MAX_STEP_DOWN_LABEL.text = "MAX STEP DOWN = " + str(MAX_STEP_DOWN)

#endregion

#region SIGNALS ####################################################################################
# Button: Change MAX_STEP_UP/MAX_STEP_DOWN to 0.5/-0.5
func _on_step_0_5_pressed():
	MAX_STEP_UP = 0.5
	MAX_STEP_DOWN = -0.5

# Button: Change MAX_STEP_UP/MAX_STEP_DOWN to 1/-1
func _on_step_1_pressed():
	MAX_STEP_UP = 1
	MAX_STEP_DOWN = -1

# Button: Change MAX_STEP_UP/MAX_STEP_DOWN to 2/-2
func _on_step_2_pressed():
	MAX_STEP_UP = 2
	MAX_STEP_DOWN = -2

# Button: Change MAX_STEP_UP/MAX_STEP_DOWN to 4/-4
func _on_step_4_pressed():
	MAX_STEP_UP = 4
	MAX_STEP_DOWN = -4

# Button: Change MAX_STEP_UP/MAX_STEP_DOWN to 100/-100
func _on_step_100_pressed():
	MAX_STEP_UP = 100
	MAX_STEP_DOWN = -100

#endregion
