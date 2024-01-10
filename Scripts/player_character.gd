extends CharacterBody3D
## Credits:
# Special thanks to Majikayo Games for original solution to stair_step_down
# (https://youtu.be/-WjM1uksPIk)
#
# Special thanks to Myria666 for their paper on Quake movement mechanics (used for stair_step_up)
# (https://github.com/myria666/qMovementDoc)

## Notes:
# 0. We use a cylinder collider to ensure we're either on a step or not on a step.
#	If you wish to use a capsule collider, you may need to add a [ShapeCast3D] to the bottom of
#	the player and make sure it's not colliding when you call stair_step_down().
#
# 1. [PlayerCollisionSupport] gives us 0.05m of clearance off the ground so we don't snag on bad
#	bad colliders or the ledges of steps. It also helps the cylinder behave more like a capsule
#	while keeping the benefits of a cylinder.
#
# 2. The [PlayerBottom] Node is used to grab the lowest Y value of the player.
#	I'm unsure if there is another way to do it, but you can't just use self.global_position.y
#	as it seems to return the center of the player.
#
# 3. To adjust the step-up/down height, just change the MAX_STEP_UP/MAX_STEP_DOWN values below.
#
# 4. This uses Jolt Physics as the default Godot Physics has a few bugs:
#	4.1: On the stairsteps with boxes blocking you from climbing onto them (in front of steep stairs),
#		you can go up but not down the third set of stairs, but with Jolt Physics you can.
#	4.2: Walking into some objects may push the player downward by a small amount which causes
#		jittering and causes the floor to be detected as a step.
#	Note that this still works with default Godot Physics, although it feels a lot better
#	in Jolt Physics.

#region ANNOTATIONS ################################################################################
@export_category("Player Settings")
@export var PLAYER_SPEED := 10.0		# Player's movement speed.
@export var JUMP_VELOCITY := 6.0		# Player's jump velocity.

@export var MAX_STEP_UP := 0.5			# Maximum height in meters the player can step up.
@export var MAX_STEP_DOWN := -0.5		# Maximum height in meters the player can step down.

@export var MOUSE_SENSITIVITY := 0.4	# Mouse movement sensitivity
@export var CAMERA_SMOOTHING := 18.0		# Amount of camera smoothing

@export_category("Debug Settings")
@export var STEP_DOWN_DEBUG := false
@export var STEP_UP_DEBUG := false

## Node References
@onready var CAMERA_NECK = $CameraNeck
@onready var CAMERA_HEAD = $CameraNeck/CameraHead
@onready var PLAYER_CAMERA = $CameraNeck/CameraHead/PlayerCamera

@onready var PLAYER_BOTTOM = $PlayerBottom

@onready var COL_RAY = $CollisionRay	# Collision raycasts
@onready var COL_RAY_DIST := 0.5		# Base horizontal distance of [CollisionRays]

@onready var PLAYER_HEIGHT = $PlayerCollision.shape.height		# Used to initialize [CollisionRays] position

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

	# Adjust collision rays
	_adjust_collision_ray()

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

# Function: Adjust Collision Ray to correct Y position and length
func _adjust_collision_ray():
	COL_RAY.target_position.y = -(MAX_STEP_UP)
	COL_RAY.position.y = -PLAYER_HEIGHT / 2.0 + MAX_STEP_UP - 0.05

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
	stair_step_up(delta)

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

		body_test_params.from = self.global_transform			# We get the player's current global_transform
		body_test_params.motion = Vector3(0, MAX_STEP_DOWN, 0)	# We project the player downward

		if PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result):
			# Enters if a collision is detected by body_test_motion
			# Get distance to step and move player downward by that much
			position.y += body_test_result.get_travel().y
			apply_floor_snap()
			is_grounded = true
			_debug_stair_step_down("SSD_APPLIED", body_test_result.get_travel().y)					## DEBUG

# Function: Handle walking up stairs
func stair_step_up(delta):
	if wish_dir == Vector3.ZERO:
		return

	_debug_stair_step_up("SSU_ENTER", null)															## DEBUG

	# Initialize body test variables
	var body_test_params = PhysicsTestMotionParameters3D.new()
	var body_test_result = PhysicsTestMotionResult3D.new()

	var distance = (velocity * horizontal) * delta		# We store horizontal movement per frame
	body_test_params.from = self.global_transform		# Self as origin point
	body_test_params.motion = distance					# Go forward by current distance

	# Pre-check: Are we colliding?
	if !PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result):
		_debug_stair_step_up("SSU_EXIT", null)														## DEBUG

		# If we don't collide, return
		return

	# Start step checking
	var step_collisions := 0							# Store the number of step collisions
	var step_height := 0.0								# Height of step
	var player_coordy = PLAYER_BOTTOM.global_position.y	# Lowest Y coordinate of player
	_debug_stair_step_up("SSU_PLAYER", player_coordy)												## DEBUG

	# Run a collision ray sweep
	## Note:
	# This works by taking a single collision ray (COL_RAY) and sweeping it from -60 to 60 when a
	# step is detected in front of the player. You can manually adjust the angle_increment and
	# range of the loop to increase/decrease step collision precision, although I found that this
	# is good. May scale poorly if given to 100 enemies.
	var angle_increment = 20
	for i in range(7, 0, -1):
		@warning_ignore("integer_division")	# I love Godot
		var angle = angle_increment * floor(i / 2) * (-1 if i % 2 == 1 else 1)
		## Note:
		# With this current implementation, the angles checked will be as follows:
		# 1. -60
		# 2.  60
		# 3. -40
		# 4.  40
		# 5. -20
		# 6.  20
		# 7.   0

		# Adjust horizontal COL_RAY position based on angle
		var colray_pos = wish_dir * COL_RAY_DIST + distance
		colray_pos = colray_pos.rotated(Vector3.UP, deg_to_rad(angle))
		_debug_stair_step_up("SSU_COLRAY_ANGLE", angle)												## DEBUG

		COL_RAY.global_position.x = self.global_position.x + colray_pos.x
		COL_RAY.global_position.z = self.global_position.z + colray_pos.z
		_debug_stair_step_up("SSU_COLRAY", colray_pos)												## DEBUG

		# Update COL_RAY and check for collision
		COL_RAY.force_raycast_update()
		if COL_RAY.is_colliding():
			# If a collision ray collides, we check for step height
			var collision_coordy = COL_RAY.get_collision_point().y
			var difference = collision_coordy - player_coordy
			_debug_stair_step_up("SSU_COL_COORDS", COL_RAY)											## DEBUG

			# Also check for slope
			var collision_normal = COL_RAY.get_collision_normal().y
			_debug_stair_step_up("SSU_COL_NORMAL", collision_normal)								## DEBUG

			# If 1: The step difference is within the margin
			# And 2: Slope is walkable (Based on 45° [0.707], must manually change here)
			if (0.0 <= difference and difference <= MAX_STEP_UP) and (0.707 <= collision_normal):
				# If we can step onto the step, save it
				if abs(difference) > abs(step_height):
					step_height = difference
					step_collisions += 1
					_debug_stair_step_up("SSU_NEW_HEIGHT", difference)								## DEBUG

	# Ensure we aren't colliding with a ceiling when applying height
	body_test_params.from = self.global_transform		# Self as origin point
	body_test_params.motion = step_height * vertical	# Translate up by step_height

	if PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result):
		# Make sure its a ceiling collision
		for i in range(body_test_result.get_collision_count()):
			if body_test_result.get_collision_normal(i).y <= -0.9:	# Ceiling Y normal will be -1, but we should
																	# account for potential normal inaccuracies.
				_debug_stair_step_up("SSU_CEILING_COLLISION", null)									## DEBUG
				return

	# Push player up by highest step we found
	# or exit if we didn't hit a step
	if step_collisions != 0:
		position.y += step_height
		_debug_stair_step_up("SSU_APPLIED", step_height)											## DEBUG

	else:
		_debug_stair_step_up("SSU_EXIT", null)														## DEBUG

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
		"SSU_EXIT":
			print("SSU: Exited with no collisions")
		"SSU_PLAYER":
			print("SSU: Collision ahead, checking for step...")
			print("SSU: Player coordinates = ", value)
		"SSU_COLRAY_ANGLE":
			print("SSU: COL_RAY ANGLE = ", value)
		"SSU_COLRAY":
			print("SSU: COL_RAY POSITION = ", self.global_position + value)
		"SSU_COL_COORDS":
			print("SSU: Collision detected")
			print("SSU: Collision coordinates = ", value.get_collision_point().y)
		"SSU_COL_NORMAL":
			print("SSU: Collision normal = ", value)
		"SSU_CEILING_COLLISION":
			print("SSU: Ceiling is blocking step-up")
		"SSU_NEW_HEIGHT":
			print("SSU: New height saved = ", value)
		"SSU_APPLIED":
			print("SSU: Applied new height = ", value)

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
	_adjust_collision_ray()

# Button: Change MAX_STEP_UP/MAX_STEP_DOWN to 1/-1
func _on_step_1_pressed():
	MAX_STEP_UP = 1
	MAX_STEP_DOWN = -1
	_adjust_collision_ray()

# Button: Change MAX_STEP_UP/MAX_STEP_DOWN to 2/-2
func _on_step_2_pressed():
	MAX_STEP_UP = 2
	MAX_STEP_DOWN = -2
	_adjust_collision_ray()

# Button: Change MAX_STEP_UP/MAX_STEP_DOWN to 4/-4
func _on_step_4_pressed():
	MAX_STEP_UP = 4
	MAX_STEP_DOWN = -4
	_adjust_collision_ray()

# Button: Change MAX_STEP_UP/MAX_STEP_DOWN to 100/-100
func _on_step_100_pressed():
	MAX_STEP_UP = 100
	MAX_STEP_DOWN = -100
	_adjust_collision_ray()

#endregion
