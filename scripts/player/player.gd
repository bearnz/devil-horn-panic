class_name Player
extends CharacterBody3D
## First-person platformer controller.
##
## Movement is momentum based: ground acceleration overshoots the walk cap and
## then bleeds off, so slides and dashes carry speed instead of being clamped
## away. Double jump, wall jump and dash are all gated behind perk flags from
## `GameState`, which is what makes the perk tree feel like it changes traversal.

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.05
const EYE_STAND := 1.62
const EYE_CROUCH := 0.88

const GROUND_ACCEL := 62.0
const GROUND_FRICTION := 36.0
const AIR_ACCEL := 26.0
const AIR_FRICTION := 2.0
const SLIDE_FRICTION := 5.5
const SLIDE_MIN_SPEED := 5.0
const SLIDE_BOOST := 3.2
const CROUCH_SPEED_MULT := 0.45

const COYOTE_TIME := 0.11
const JUMP_BUFFER := 0.14
const WALL_SLIDE_GRAVITY := 0.35
const WALL_JUMP_PUSH := 8.5
const WALL_JUMP_LIFT := 0.92
const DASH_SPEED := 24.0
const DASH_TIME := 0.14

const KILL_HEIGHT := -30.0
const REGEN_DELAY := 3.5

@export var mouse_sensitivity: float = 0.0022
@export_range(0.2, 3.0) var respawn_delay: float = 1.1

var health: float = 100.0
var max_health: float = 100.0
var spawn_transform: Transform3D
var is_dead: bool = false

var _pitch: float = 0.0
var _recoil_pitch: float = 0.0
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _air_jumps_left: int = 0
var _dash_charges: float = 0.0
var _dash_time_left: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _is_crouching: bool = false
var _is_sliding: bool = false
var _time_since_damage: float = 99.0
var _control_active: bool = true
var _was_on_floor: bool = true
## Capturing the mouse warps the cursor to the window centre, which arrives as
## one large relative motion and would snap the view on start and on unpause.
## The warp event can turn up several frames late (it waits on window focus), so
## a fixed number of events is dropped rather than a time window.
var _look_skips: int = 0

var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 26.0))

@onready var _pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var weapons: WeaponController = $CameraPivot/Camera3D/WeaponRig
@onready var _collider: CollisionShape3D = $Collider
@onready var _interact_ray: RayCast3D = $CameraPivot/Camera3D/InteractRay
@onready var _capsule: CapsuleShape3D = _collider.shape as CapsuleShape3D


func _ready() -> void:
	add_to_group("player")
	spawn_transform = global_transform
	mouse_sensitivity = Settings.mouse_sensitivity
	max_health = GameState.stat("max_health")
	health = max_health
	_dash_charges = GameState.stat("dash_charges")
	Events.stats_changed.connect(_on_stats_changed)
	set_control_active(true)


func _on_stats_changed() -> void:
	var new_max := GameState.stat("max_health")
	if new_max > max_health:
		# Perks that raise max health top you up by the difference.
		health += new_max - max_health
	max_health = new_max
	health = clampf(health, 0.0, max_health)
	_dash_charges = minf(_dash_charges, GameState.stat("dash_charges"))
	Events.player_healed.emit(0.0, health, max_health)


## Toggled by menus: releases the mouse and stops the weapon from firing.
func set_control_active(active: bool) -> void:
	_control_active = active
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE
	if active:
		_look_skips = 2
	if weapons != null:
		weapons.enabled = active


func _unhandled_input(event: InputEvent) -> void:
	if not _control_active or is_dead:
		return
	if event is InputEventMouseMotion:
		if _look_skips > 0:
			_look_skips -= 1
			return
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.45, 1.45)
		weapons.add_look_sway(motion.relative)
	elif event.is_action_pressed("interact"):
		_try_interact()


func _physics_process(delta: float) -> void:
	_time_since_damage += delta
	_tick_camera(delta)
	_tick_dash_charges(delta)
	_tick_regen(delta)

	if is_dead:
		velocity = velocity.move_toward(Vector3.ZERO, 40.0 * delta)
		move_and_slide()
		return

	var grounded := is_on_floor()
	_coyote = COYOTE_TIME if grounded else maxf(0.0, _coyote - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if _control_active and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER

	if grounded and not _was_on_floor:
		_on_landed()
	_was_on_floor = grounded

	_update_stance(delta, grounded)
	_apply_gravity(delta, grounded)
	_apply_movement(delta, grounded)
	_try_jump(grounded)
	if _control_active and Input.is_action_just_pressed("dash"):
		_try_dash()

	move_and_slide()

	if global_position.y < KILL_HEIGHT:
		_die("Fell into the pit")


# --- Movement ---------------------------------------------------------------

func _input_direction() -> Vector3:
	if not _control_active:
		return Vector3.ZERO
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return (global_transform.basis * Vector3(axis.x, 0.0, axis.y)).normalized()


func _apply_gravity(delta: float, grounded: bool) -> void:
	if _dash_time_left > 0.0:
		velocity.y = 0.0
		return
	if grounded:
		return
	var scale := 1.0
	# Hugging a wall while falling slows the descent, which sets up wall jumps.
	if GameState.has_flag("wall_jump") and is_on_wall_only() and velocity.y < 0.0:
		if _input_direction().dot(-get_wall_normal()) > 0.25:
			scale = WALL_SLIDE_GRAVITY
	velocity.y -= _gravity * scale * delta


func _apply_movement(delta: float, grounded: bool) -> void:
	if _dash_time_left > 0.0:
		_dash_time_left -= delta
		velocity.x = _dash_direction.x * DASH_SPEED
		velocity.z = _dash_direction.z * DASH_SPEED
		return

	var wish := _input_direction()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target_speed := GameState.stat("move_speed")
	if _is_crouching and not _is_sliding:
		target_speed *= CROUCH_SPEED_MULT
	elif grounded and _control_active and Input.is_action_pressed("sprint") and wish.length() > 0.1:
		target_speed *= GameState.stat("sprint_mult")

	if _is_sliding:
		# Slides only steer, never accelerate, and bleed speed until they stop.
		horizontal += wish * 6.0 * delta
		horizontal = horizontal.move_toward(Vector3.ZERO, SLIDE_FRICTION * delta)
	elif wish.length() > 0.1:
		var accel := GROUND_ACCEL if grounded else AIR_ACCEL
		horizontal += wish * accel * delta
		var cap := target_speed if grounded else maxf(horizontal.length(), target_speed)
		if horizontal.length() > cap:
			# Overshoot is bled off rather than clipped, so momentum survives.
			var friction := GROUND_FRICTION if grounded else AIR_FRICTION
			horizontal = horizontal.move_toward(horizontal.normalized() * cap, friction * delta)
	else:
		var friction := GROUND_FRICTION if grounded else AIR_FRICTION
		horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _try_jump(grounded: bool) -> void:
	if _jump_buffer <= 0.0:
		return
	var jump_velocity := GameState.stat("jump_velocity")

	if grounded or _coyote > 0.0:
		_end_slide()
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		return

	if GameState.has_flag("wall_jump") and is_on_wall_only():
		var normal := get_wall_normal()
		velocity.y = jump_velocity * WALL_JUMP_LIFT
		velocity.x += normal.x * WALL_JUMP_PUSH
		velocity.z += normal.z * WALL_JUMP_PUSH
		_jump_buffer = 0.0
		# Wall jumps refund an air jump so chains stay readable.
		_air_jumps_left = GameState.stat_int("air_jumps")
		return

	if _air_jumps_left > 0 and GameState.has_flag("double_jump"):
		_air_jumps_left -= 1
		velocity.y = jump_velocity * 0.92
		_jump_buffer = 0.0


func _try_dash() -> void:
	if not GameState.has_flag("dash") or _dash_charges < 1.0:
		return
	var direction := _input_direction()
	if direction.length() < 0.1:
		direction = -global_transform.basis.z
	direction.y = 0.0
	_dash_direction = direction.normalized()
	_dash_charges -= 1.0
	_dash_time_left = DASH_TIME
	_end_slide()


func _tick_dash_charges(delta: float) -> void:
	var maximum := GameState.stat("dash_charges")
	if maximum <= 0.0 or _dash_charges >= maximum:
		return
	var cooldown := maxf(0.2, GameState.stat("dash_cooldown"))
	_dash_charges = minf(maximum, _dash_charges + delta / cooldown)


func dash_ready_fraction() -> float:
	var maximum := GameState.stat("dash_charges")
	if maximum <= 0.0:
		return 0.0
	return clampf(_dash_charges / maximum, 0.0, 1.0)


func _on_landed() -> void:
	_air_jumps_left = GameState.stat_int("air_jumps")
	_recoil_pitch += 0.035 * clampf(absf(velocity.y) / 20.0, 0.0, 1.0)


# --- Stance -----------------------------------------------------------------

func _update_stance(delta: float, grounded: bool) -> void:
	var wants_crouch := _control_active and Input.is_action_pressed("crouch")
	var planar := Vector2(velocity.x, velocity.z).length()

	if wants_crouch and grounded and not _is_sliding and planar > SLIDE_MIN_SPEED:
		_start_slide()
	elif _is_sliding and (not wants_crouch or planar < 2.0 or not grounded):
		_end_slide()

	var crouching := wants_crouch or _is_sliding
	if not crouching and _is_crouching and not _has_headroom():
		crouching = true  # Blocked by ceiling, stay down.
	_is_crouching = crouching

	var target_height := CROUCH_HEIGHT if _is_crouching else STAND_HEIGHT
	var target_eye := EYE_CROUCH if _is_crouching else EYE_STAND
	var blend := clampf(delta * 12.0, 0.0, 1.0)
	_capsule.height = lerpf(_capsule.height, target_height, blend)
	_collider.position.y = _capsule.height * 0.5
	_pivot.position.y = lerpf(_pivot.position.y, target_eye, blend)


func _start_slide() -> void:
	_is_sliding = true
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() > 0.1:
		horizontal += horizontal.normalized() * SLIDE_BOOST
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _end_slide() -> void:
	_is_sliding = false


func _has_headroom() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * (CROUCH_HEIGHT * 0.5)
	var to := global_position + Vector3.UP * (STAND_HEIGHT + 0.05)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return space.intersect_ray(query).is_empty()


func is_sliding() -> bool:
	return _is_sliding


# --- Camera -----------------------------------------------------------------

func add_recoil(degrees: float) -> void:
	_recoil_pitch += deg_to_rad(degrees)


func _tick_camera(delta: float) -> void:
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, clampf(delta * 7.0, 0.0, 1.0))
	_pivot.rotation.x = clampf(_pitch + _recoil_pitch, -1.55, 1.55)

	# Roll the camera slightly when strafing or sliding.
	var lateral := global_transform.basis.x.dot(Vector3(velocity.x, 0.0, velocity.z))
	var target_roll := -lateral * 0.006 + (0.12 if _is_sliding else 0.0)
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, clampf(delta * 6.0, 0.0, 1.0))

	var target_fov := Settings.fov
	if weapons != null and weapons.aiming:
		target_fov *= WeaponController.AIM_FOV_MULT
	elif _control_active and Input.is_action_pressed("sprint") and is_on_floor():
		target_fov += 6.0
	camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 8.0, 0.0, 1.0))


# --- Health -----------------------------------------------------------------

func apply_damage(amount: float, _is_crit: bool = false, _at: Vector3 = Vector3.ZERO,
		direction: Vector3 = Vector3.ZERO) -> void:
	if is_dead or amount <= 0.0:
		return
	var mitigated := maxf(1.0, amount - GameState.stat("armour"))
	health = maxf(0.0, health - mitigated)
	_time_since_damage = 0.0
	_recoil_pitch += deg_to_rad(1.5)
	if direction != Vector3.ZERO:
		apply_knockback(direction * 2.0)
	Events.player_damaged.emit(mitigated, health, max_health)
	if health <= 0.0:
		_die("Killed")


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	var before := health
	health = minf(max_health, health + amount)
	Events.player_healed.emit(health - before, health, max_health)


func apply_knockback(impulse: Vector3) -> void:
	velocity += impulse


func _tick_regen(delta: float) -> void:
	if is_dead or not GameState.has_flag("regen") or _time_since_damage < REGEN_DELAY:
		return
	var rate := GameState.stat("health_regen")
	if rate > 0.0 and health < max_health:
		heal(rate * delta)


func _die(reason: String) -> void:
	if is_dead:
		return
	is_dead = true
	_end_slide()
	set_control_active(false)
	Events.notice.emit("%s — respawning" % reason)
	Events.player_died.emit()
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()


func _respawn() -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	_pitch = 0.0
	_recoil_pitch = 0.0
	health = max_health
	_air_jumps_left = GameState.stat_int("air_jumps")
	is_dead = false
	set_control_active(true)
	Events.player_respawned.emit()


# --- Interaction ------------------------------------------------------------

## Prompt for whatever is under the crosshair, or "" when nothing is in reach.
func interact_prompt() -> String:
	var target := _interact_target()
	if target == null:
		return ""
	if target.has_method("interact_prompt"):
		return String(target.interact_prompt())
	return "Interact"


func _interact_target() -> Node:
	if not _interact_ray.is_colliding():
		return null
	var collider := _interact_ray.get_collider()
	if collider is Node and (collider as Node).has_method("interact"):
		return collider
	return null


func _try_interact() -> void:
	var target := _interact_target()
	if target != null:
		target.interact(self)
