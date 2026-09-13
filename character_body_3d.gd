extends CharacterBody3D



@export_group("Movement Speeds")
@export var walk_speed: float = 6.0
@export var sprint_speed: float = 12.0
@export var crouch_speed: float = 2.5
@export var jump_velocity: float = 13.0
@export var jump_gravity_multiplier: float = 3.3 # ascend speed
@export var fall_gravity_multiplier: float = 5.0 #multiplies player gravity on way down
@export var mouse_sensitivity: float = 0.003

@export_group("Stamina Settings")
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 25.0
@export var stamina_regen_rate: float = 15.0
@export var exhaustion_recovery_percent: float = 0.25

# Heights & Smooth Transitions
const STANDING_HEIGHT = 2.0
const CROUCHING_HEIGHT = 1.2
const STANDING_HEAD_Y = 1.6
const CROUCHING_HEAD_Y = 0.9
const CROUCH_TRANSITION_SPEED = 10.0

# Internal Tracking (Starts with full stamina at game launch)
@onready var current_stamina: float = max_stamina
var is_exhausted: bool = false

@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	# 1. Gravity
	if not is_on_floor():
		if velocity.y < 0:
			velocity += get_gravity() * jump_gravity_multiplier * delta
		else: 
			velocity += get_gravity() * fall_gravity_multiplier * delta

	# 2. Input Direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	# 3. State Checks
	var is_crouching: bool = Input.is_action_pressed("crouch") and is_on_floor()
	var is_moving_forward: bool = input_dir.y < 0.0
	var wants_to_sprint: bool = Input.is_action_pressed("sprint") and not is_crouching and is_on_floor() and is_moving_forward
	var is_sprinting: bool = wants_to_sprint and not is_exhausted and current_stamina > 0.0

	# 4. Stamina Drain / Regeneration Logic
	if is_sprinting:
		# Drains stamina while running forward/moving
		current_stamina = move_toward(current_stamina, 0.0, stamina_drain_rate * delta)
		if current_stamina <= 0.0:
			is_exhausted = true
	else:
		# Regenerates stamina when walking or standing still
		current_stamina = move_toward(current_stamina, max_stamina, stamina_regen_rate * delta)
		if current_stamina >= max_stamina * exhaustion_recovery_percent:
			is_exhausted = false

	# 5. Speed Selection
	var current_speed: float = walk_speed
	if is_crouching:
		current_speed = crouch_speed
	elif is_sprinting:
		current_speed = sprint_speed

	# 6. Smooth Camera Height Transition (Crouching)
	var target_head_y: float = CROUCHING_HEAD_Y if is_crouching else STANDING_HEAD_Y
	head.position.y = lerp(head.position.y, target_head_y, delta * CROUCH_TRANSITION_SPEED)

	# 7. Collision Shape Resizing
	if collision_shape.shape is CapsuleShape3D:
		var target_height: float = CROUCHING_HEIGHT if is_crouching else STANDING_HEIGHT
		collision_shape.shape.height = lerp(collision_shape.shape.height, target_height, delta * CROUCH_TRANSITION_SPEED)

	# 8. Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor() and not is_crouching:
		velocity.y = jump_velocity

	# 9. Velocity Application
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
