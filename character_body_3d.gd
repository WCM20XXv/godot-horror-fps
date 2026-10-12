extends CharacterBody3D

signal battery_changed(percent: float)
signal flashlight_toggled(is_on: bool)

@export_group("Movement Speeds")
@export var walk_speed: float = 6.0
@export var sprint_speed: float = 12.0
@export var crouch_speed: float = 2.5
@export var jump_velocity: float = 13.0
@export var jump_gravity_multiplier: float = 3.3 # multiplies player gravity on the way up
@export var fall_gravity_multiplier: float = 5.0 # multiplies player gravity on the way down
@export var mouse_sensitivity: float = 0.003

@export_group("Stamina Settings")
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 25.0
@export var stamina_regen_rate: float = 15.0
@export var exhaustion_recovery_percent: float = 0.25

@export_group("Flashlight")
@export var max_battery: float = 100.0
@export var battery_drain_rate: float = 0.8 # battery lost per second while the light is on
@export var battery_recharge_rate: float = 0.0 # battery gained per second while off (0 = no recharge)
@export var flicker_threshold: float = 0.2 # fraction of battery left where the light starts to flicker

@export_group("Lean")
@export var lean_distance: float = 0.45 # how far the camera slides sideways, in meters
@export var lean_angle_degrees: float = 12.0 # how much the camera rolls at full lean
@export var lean_speed: float = 10.0

# Heights & Smooth Transitions
const STANDING_HEIGHT = 2.0
const CROUCHING_HEIGHT = 1.2
const STANDING_HEAD_Y = 1.6
const CROUCHING_HEAD_Y = 0.9
const CROUCH_TRANSITION_SPEED = 10.0
const LEAN_WALL_MARGIN = 0.05 # gap kept between the body and a wall while leaning

# Internal Tracking (Starts with full stamina at game launch)
@onready var current_stamina: float = max_stamina
var is_exhausted: bool = false

# Flashlight and lean tracking (battery starts full)
@onready var current_battery: float = max_battery
var flashlight_on: bool = false
var flashlight_base_energy: float = 1.0
var lean_amount: float = 0.0
var _lean_hit := KinematicCollision3D.new()

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	flashlight_base_energy = flashlight.light_energy
	flashlight.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	if event.is_action_pressed("flashlight"):
		toggle_flashlight()

	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	# 1. Gravity (heavier on the way down than on the way up)
	if not is_on_floor():
		if velocity.y < 0:
			velocity += get_gravity() * fall_gravity_multiplier * delta
		else:
			velocity += get_gravity() * jump_gravity_multiplier * delta

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

	# 7. Collision Shape Resizing (keeps the feet on the ground while the height changes)
	if collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		var target_height: float = CROUCHING_HEIGHT if is_crouching else STANDING_HEIGHT
		capsule.height = lerp(capsule.height, target_height, delta * CROUCH_TRANSITION_SPEED)
		collision_shape.position.y = capsule.height * 0.5

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

	# 10. Lean (Q / E) and flashlight battery
	_update_lean(delta)
	_update_flashlight(delta)

	move_and_slide()

func toggle_flashlight() -> void:
	if flashlight_on:
		_set_flashlight(false)
	elif current_battery > 0.0:
		_set_flashlight(true)

func _set_flashlight(on: bool) -> void:
	flashlight_on = on
	flashlight.visible = on
	if on:
		flashlight.light_energy = flashlight_base_energy
	flashlight_toggled.emit(on)

func _update_flashlight(delta: float) -> void:
	var previous_battery := current_battery
	if flashlight_on:
		current_battery = move_toward(current_battery, 0.0, battery_drain_rate * delta)
		# Dim and flicker as the battery runs low
		var charge := current_battery / max_battery
		var brightness := 1.0
		if charge < flicker_threshold:
			brightness = clampf(charge / flicker_threshold, 0.15, 1.0)
			if randf() < 0.08:
				brightness *= randf_range(0.0, 0.4)
		flashlight.light_energy = flashlight_base_energy * brightness
		if current_battery <= 0.0:
			_set_flashlight(false)
	else:
		current_battery = move_toward(current_battery, max_battery, battery_recharge_rate * delta)

	if not is_equal_approx(previous_battery, current_battery):
		battery_changed.emit(current_battery / max_battery * 100.0)

func _update_lean(delta: float) -> void:
	# The camera slides and rolls instead of the whole body, so walking is unaffected
	var target := Input.get_axis("peak_left", "peak_right") * lean_distance
	if target != 0.0:
		# Stop the lean short of walls so the camera never pokes through them
		var sideways := global_transform.basis.x * target
		if test_move(global_transform, sideways, _lean_hit):
			var free_space := maxf(_lean_hit.get_travel().length() - LEAN_WALL_MARGIN, 0.0)
			target = signf(target) * minf(absf(target), free_space)
	lean_amount = lerpf(lean_amount, target, delta * lean_speed)
	camera.position.x = lean_amount
	camera.rotation.z = -(lean_amount / lean_distance) * deg_to_rad(lean_angle_degrees)
