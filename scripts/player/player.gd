class_name Player
extends CharacterBody3D
## First-person platformer controller.
##
## Movement is momentum based: ground acceleration overshoots the walk cap and
## then bleeds off, so slides and dashes carry speed instead of being clamped
## away. Double jump, wall jump and dash are all gated behind perk flags from
## `GameState`, which is what makes the perk tree feel like it changes traversal.
## Mantling is the exception — ungated and always available, but it still asks
## for intent: a jump press, or being properly airborne. Running into a lip does
## not climb it.

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.05
const EYE_STAND := 1.62
const EYE_CROUCH := 0.88
## How far in front of the body's centre line the eye sits. Eyes are in the front
## of a head, not the middle of a torso, and the difference is the whole
## first-person view of your own legs: on the centre line you look straight down
## *through* them and see two boxes edge-on, and from here you look down over the
## front of them and see knees, boots and the floor past your toes.
##
## Applied to the pivot in code rather than in the scene so this constant is the
## one place it is stated. Well inside the 0.4 capsule, so the camera is no nearer
## a wall than the body already was.
const EYE_FORWARD := 0.18

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
const DASH_TIME := 0.32

## Mantling. Deliberately ungated: a lip you are visibly hanging off should read
## as a lip, not a wall, so this is baseline rather than another perk flag. The
## traversal that *is* gated (the shaft, the sky course) sits well above
## MANTLE_MAX_HEIGHT and stays gated. See `_wants_mantle()` for what has to be
## true before any of this geometry is probed at all.
const MANTLE_MIN_HEIGHT := 0.45
const MANTLE_MAX_HEIGHT := 2.1
## How far ahead the lip is probed — and, because the down-probe doubles as the
## landing spot, how far past the edge you end up. Capsule radius is 0.4, so this
## clears the face by 0.55.
const MANTLE_REACH := 0.95
## How far under the lip the face is probed for. Measured down from the lip
## rather than up from the feet, so the probe lands on the face whether you are
## level with it or hanging halfway down it.
const MANTLE_FACE_DROP := 0.2
## Flattest surface still counted as a ledge top rather than a slope, kept a
## little inside the body's floor_max_angle (50°, cos 0.64).
const MANTLE_MIN_NORMAL := 0.7
## Duration of the tallest mantle; short ones scale down from here so hopping a
## crate does not take as long as hauling yourself over head height.
const MANTLE_TIME := 0.36
## Three beats inside that one duration, as fractions of it: the hands take the
## ledge while the body hangs, the body climbs, and only then is it carried in
## over the lip. The hang is what makes the grab visible at all — the eye sits
## 1.62 above the feet, so without it the camera has cleared the lip before the
## hands have landed on it, and the animation plays out below the frame.
const MANTLE_HANG := 0.28
const MANTLE_RISE_END := 0.85
const MANTLE_PULL_START := 0.5
## How far under the lip the hang puts the feet. The eye rides 1.62 above them, so
## this leaves it just over the edge — looking down at the hands rather than at the
## floor beyond them.
const MANTLE_HANG_FEET_BELOW := 1.35
## Ceiling on the dip that gets you there, scaled by how tall the climb is: a
## knee-high step barely dips, which is what stops it dunking you through a floor
## you are standing on.
const MANTLE_HANG_DIP := 0.55
## Look-down over the hang, easing out as the body climbs. Additive like recoil,
## so mouse look keeps working through it. Worth 17°, which sounds like a lot until
## you notice that grabbing a ledge is something people look at.
const MANTLE_LOOK_DOWN := 0.30
## Speed handed over on exit, as a multiple of move_speed — enough to walk off
## the lip rather than stop dead on it.
const MANTLE_EXIT_MULT := 0.55

## Ceiling on player-driven running, as a multiple of the current move_speed —
## a multiple rather than a number so speed perks raise it with them. Air
## control had no ceiling at all before this: a held direction accelerated
## indefinitely for as long as you stayed airborne.
## Momentum from a slide, a pad, a wall jump or a knockback may still exceed it,
## and bleeds back down at MOMENTUM_DECAY instead of being clipped.
const MAX_SPEED_MULT := 1.8
## How fast speed carried *above* that ceiling bleeds back down to it, in m/s².
## This is what `SLIDE_BOOST` is worth once the crouch key comes up: stand out of
## a slide and you keep running faster than a standing start could ever have got
## you, for a second and a half, and then settle. Deliberately nowhere near
## GROUND_FRICTION — at 36 m/s² the whole boost is gone within a tenth of a second
## of standing up, which makes sliding pointless the moment it ends.
const MOMENTUM_DECAY := 2.2
## Terminal velocities. The rise cap sits above the strongest jump pad (20), so
## it only ever catches something that has gone wrong.
const MAX_RISE_SPEED := 22.0
const MAX_FALL_SPEED := 34.0

## Camera roll, in radians, and both are the *whole* tilt rather than a
## coefficient on velocity: STRAFE_ROLL is what a flat-out sideways run is worth
## and SLIDE_ROLL is what a slide adds on top, so the horizon can never go over
## further than their sum (4.5°). Quoting them as angles is the point — the old
## per-m/s coefficient grew with whatever speed the player happened to be
## carrying, and turning hard out of a slide could lay the view right over.
const STRAFE_ROLL := 0.028
const SLIDE_ROLL := 0.05

## Degrees of FOV opened up at full dash, on top of whatever the player has set.
## Widening the lens is the one camera cue that says *speed* rather than
## *movement* — everything at the edge of the frame is suddenly further away and
## travelling outwards faster than the middle, which is the same optical flow the
## wind on the HUD draws by hand. Nine is about the smallest that is felt at all;
## much more and the arena bulges, which reads as a lens rather than as thrust.
const DASH_FOV_PUNCH := 9.0
## Up in a fifteenth of a second, out over four tenths — the same asymmetry, and
## for the same reason, as the wind it arrives with: a dash is over in 0.32s, so a
## symmetric ease would still be opening when it ended and the trailing half is
## what sells having been thrown somewhere.
const DASH_FOV_RISE := 15.0
const DASH_FOV_FALL := 2.6
## What is left of the punch while aiming down sights. Sights are a promise about
## where the muzzle is pointing, and a FOV that moves under a held sight picture
## breaks it — but zero would make dashing while aimed feel like the dash stopped
## working, so this keeps a quarter of it. Same reasoning as the weapon's own
## AIM_SWAY_MULT, one number further out.
const DASH_FOV_AIM_MULT := 0.25

## The jolt when a dash lets go. `_end_dash` hands back the speed it was lending
## in a single frame — 14 m/s of it at base — and until this went in the only
## sign of that was the number on the velocity: the view simply stopped, which is
## the one part of a dash that read as scripted rather than physical.
##
## Both are quoted as the **peak angle the camera actually reaches**, in radians,
## rather than as an impulse: an impulse into a spring is a number you cannot read
## off the screen. Pitch is the head carrying on forward as the body is arrested,
## roll is the same thing sideways.
const DASH_SHUNT_PITCH := 0.045
const DASH_SHUNT_ROLL := 0.030
## Dash boost the peaks above are quoted at, so a perk that lends more speed
## shunts harder when it takes it back. Capped in `_end_dash`, since the alternative
## is a stat sheet deciding how far the horizon tips.
const DASH_SHUNT_REFERENCE := 14.0
## The spring the kick is delivered through: undamped frequency in rad/s, and a
## damping ratio under 1 so it overshoots once on the way back. That overshoot is
## the whole effect — a critically damped return is a camera easing to a stop,
## which is what it was already doing. At these numbers it is over inside half a
## second.
const SHUNT_FREQUENCY := 13.4
const SHUNT_DAMPING := 0.52
## Peak of that spring's impulse response as a fraction of v0/ω, which is what lets
## the two constants above be quoted as angles. Fixed by the damping ratio alone:
## exp(-ζ/√(1-ζ²) · atan(√(1-ζ²)/ζ)) = 0.536 at ζ = 0.52. Change the damping and
## this changes with it.
const SHUNT_PEAK_GAIN := 0.536

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
## The camera's own copy of the roll and the FOV, kept here rather than read back
## off the camera because both now have a transient added on top of them: read the
## node and the ease would be chasing its own output. Same reason the weapon swap
## applies the trip to the hip on top of its pose smoothing instead of through it.
var _roll: float = 0.0
var _fov: float = 0.0
## How much of the dash FOV punch is currently open, 0 to 1.
var _dash_fov: float = 0.0
## Pitch and roll of the end-of-dash shunt, in radians, and the spring velocity
## carrying them. Additive on top of look, recoil and strafe roll, like every other
## transient the camera has.
var _shunt: Vector2 = Vector2.ZERO
var _shunt_velocity: Vector2 = Vector2.ZERO
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _air_jumps_left: int = 0
var _dash_charges: float = 0.0
var _dash_time_left: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
## Horizontal speed the dash started from. The dash runs at this plus the
## "dash_boost" stat and drops back to it on exit, so a dash is a loan of speed
## rather than a speed of its own — it can never brake you, however fast you
## arrive.
var _dash_entry_speed: float = 0.0
## Vertical speed handed back when the dash ends. Only ever >= 0: a climb is
## carried through the dash, a fall is not.
var _dash_exit_vy: float = 0.0
## Mantle state. A mantle is a scripted move: while it runs the body is driven by
## position rather than velocity, so gravity, input and move_and_slide are all
## skipped for its duration.
var _mantle_time_left: float = 0.0
var _mantle_duration: float = MANTLE_TIME
var _mantle_start: Vector3 = Vector3.ZERO
var _mantle_target: Vector3 = Vector3.ZERO
var _mantle_direction: Vector3 = Vector3.ZERO
## The edge itself, in world space, and the way the face under it points. Only
## `ViewHands` cares: it is where the hands are pinned while the body climbs.
var _mantle_grab: Vector3 = Vector3.ZERO
var _mantle_grab_normal: Vector3 = Vector3.BACK
## Feet height the hang settles at before the climb starts.
var _mantle_hang_y: float = 0.0
var _mantle_pitch: float = 0.0
var _is_crouching: bool = false
var _is_sliding: bool = false
## Which camera is current. A review tool rather than a game mode — see
## `set_third_person()`.
var third_person: bool = false
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
## Must stay after WeaponRig in the scene: the hands copy anchors the rig moves in
## its own _process, and node order is what decides which runs first.
@onready var hands: ViewHands = $CameraPivot/Camera3D/ViewHands
## The humanoid the camera is standing inside: what the arena sees, and what you
## find when you look down. Poses itself off this node's stance and velocity, so
## nothing here has to drive it.
@onready var body: PlayerBody = $Body
## The chase camera and the arm that keeps it out of walls. Rides the same pivot
## as the first-person one, so it inherits every bit of look, crouch and mantle
## motion for free and only differs by being pulled back along it.
@onready var third_person_camera: Camera3D = $CameraPivot/ThirdPersonArm/Camera3D
@onready var _collider: CollisionShape3D = $Collider
@onready var _interact_ray: RayCast3D = $CameraPivot/Camera3D/InteractRay
@onready var _capsule: CapsuleShape3D = _collider.shape as CapsuleShape3D
## Standing body, slightly undersized, reused to test whether a mantle has
## somewhere legal to put you down. Built once rather than per probe.
@onready var _mantle_fit: CapsuleShape3D = _make_mantle_fit_shape()


func _ready() -> void:
	add_to_group("player")
	# Only the height of this is touched again (by the stance), so the forward
	# offset is set once here and rides along with every crouch and mantle.
	_pivot.position.z = -EYE_FORWARD
	# The camera's own copy of its FOV starts where the camera does, or the first
	# second of every level is spent easing open from nothing.
	_fov = Settings.fov
	camera.fov = _fov
	spawn_transform = global_transform
	mouse_sensitivity = Settings.mouse_sensitivity
	max_health = GameState.stat("max_health")
	health = max_health
	_dash_charges = GameState.stat("dash_charges")
	Events.stats_changed.connect(_on_stats_changed)
	set_third_person(Settings.third_person)
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


## Switches between the first-person camera and the chase camera behind it.
##
## This is a review tool, not a game mode: the body, the stances and the dash
## pose are all built to be seen from a camera that is inside the head, and the
## only way to watch them from outside is the dev capture rig's throwaway camera,
## one still frame at a time. This is the moving version of that.
##
## Two things go with the swap. The whole body comes back — the head, chest and
## arms are shadows-only while the camera is inside them — and the view model and
## its hands are hidden, because they live in front of the *other* camera and from
## back here they are a rifle floating through the player's skull.
##
## What it does not move is where a shot starts: that is still the head. Shots stay
## on the crosshair anyway, because `WeaponController.aim_direction()` resolves what
## the crosshair is over and aims at the *point* rather than down the chase camera's
## direction — the two differ by the shoulder the camera is offset over, which is a
## hand's width of miss at touching distance and nothing at all across the arena.
##
## The interact ray is the one thing still fired down the pivot, so a workbench
## reachable from back here may want the crosshair a little right of it.
func set_third_person(enabled: bool) -> void:
	third_person = enabled
	if enabled:
		third_person_camera.make_current()
	else:
		camera.make_current()
	body.first_person = not enabled
	weapons.visible = not enabled
	hands.visible = not enabled


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
	elif event.is_action_pressed("third_person"):
		# Persisted like every other preference, so a review session survives a
		# restart. The pause menu's checkbox is the same switch.
		Settings.third_person = not third_person
		Settings.save_settings()
		set_third_person(Settings.third_person)


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

	# A mantle owns the body outright: it drives position directly, so everything
	# below — gravity, movement, jumping, move_and_slide — sits this one out.
	if _mantle_time_left <= 0.0 and _wants_mantle(grounded):
		_try_mantle()
	if _mantle_time_left > 0.0:
		_tick_mantle(delta)
		return

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
		# A dash holds its height: no gravity, no residual rise or fall. What
		# happens afterwards is decided in _end_dash().
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
	velocity.y = clampf(velocity.y, -MAX_FALL_SPEED, MAX_RISE_SPEED)


func _apply_movement(delta: float, grounded: bool) -> void:
	if _dash_time_left > 0.0:
		_dash_time_left -= delta
		# Read the boost every frame rather than at launch, so a perk bought
		# mid-dash lands on the same terms as every other stat.
		var boosted := _dash_entry_speed + GameState.stat("dash_boost")
		velocity.x = _dash_direction.x * boosted
		velocity.z = _dash_direction.z * boosted
		if _dash_time_left <= 0.0:
			_end_dash()
		return

	var wish := _input_direction()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target_speed := GameState.stat("move_speed")
	if _is_crouching and not _is_sliding:
		target_speed *= CROUCH_SPEED_MULT

	if _is_sliding:
		# Slides only steer, never accelerate, and bleed speed until they stop.
		horizontal += wish * 6.0 * delta
		horizontal = horizontal.move_toward(Vector3.ZERO, SLIDE_FRICTION * delta)
	elif wish.length() > 0.1:
		var accel := GROUND_ACCEL if grounded else AIR_ACCEL
		var friction := GROUND_FRICTION if grounded else AIR_FRICTION
		var speed_before := horizontal.length()
		horizontal += wish * accel * delta
		# In the air the soft cap is whatever you already carry, so momentum
		# survives; on the ground it is the walk speed.
		var cap := target_speed if grounded else maxf(speed_before, target_speed)
		if horizontal.length() > cap:
			# Overshoot is bled off rather than clipped, so momentum survives.
			horizontal = horizontal.move_toward(horizontal.normalized() * cap, friction * delta)
		# The bleed above is deliberately gentler than the acceleration, so on
		# its own input just outruns it — this is the hard ceiling that stops
		# running from ever reaching DASH_SPEED. Anything arriving with more than
		# that already — a slide's boost, a jump pad, a knockback — keeps it and
		# gives it back at MOMENTUM_DECAY instead of being clipped down on the
		# spot. That decay is the whole reason a slide is worth anything: the
		# boost outlives the crouch key, and running is what spends it.
		var ceiling := GameState.stat("move_speed") * MAX_SPEED_MULT
		horizontal = horizontal.limit_length(maxf(ceiling, speed_before - MOMENTUM_DECAY * delta))
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
	# A rising dash resumes its climb on exit; a falling one starts its fall
	# over, so dashing out of a drop always reads as a save rather than a
	# plummet that only got faster sideways.
	_dash_exit_vy = maxf(velocity.y, 0.0)
	_dash_entry_speed = Vector2(velocity.x, velocity.z).length()
	_dash_charges -= 1.0
	_dash_time_left = DASH_TIME
	_end_slide()


## Hands back the speed the dash was borrowing. The boost drops away and the
## entry speed is returned along the direction dashed, so you keep the new
## heading but not the pace; vertical follows the rule set at launch.
func _end_dash() -> void:
	_dash_time_left = 0.0
	_kick_shunt()
	velocity.x = _dash_direction.x * _dash_entry_speed
	velocity.z = _dash_direction.z * _dash_entry_speed
	velocity.y = _dash_exit_vy
	_dash_exit_vy = 0.0
	_dash_entry_speed = 0.0


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


func is_dashing() -> bool:
	return _dash_time_left > 0.0


## World-space heading of the dash in progress: flat, normalised, and zero when
## there is no dash — so animation code can read it unconditionally, but has to
## latch it if it wants to ease a pose out after the dash itself has ended.
func dash_direction() -> Vector3:
	if _dash_time_left <= 0.0:
		return Vector3.ZERO
	return _dash_direction


## How far the dash's FOV punch is open, 0 to 1 — like the wind on the HUD, it
## outlives the dash that raised it. Read by the dev tools, which have no other way
## to tell a lens that is opening from one that has stopped.
func dash_fov_amount() -> float:
	return _dash_fov


## The end-of-dash kick the camera is currently carrying: pitch in x, roll in y,
## both radians, both zero at rest. Additive on top of everything else the camera
## is doing, so this is the only place it can be read on its own.
func camera_shunt() -> Vector2:
	return _shunt


# --- Mantling ---------------------------------------------------------------

func is_mantling() -> bool:
	return _mantle_time_left > 0.0


## How far through the pull-up, 0 to 1. Zero when not mantling, so animation code
## can read it unconditionally.
func mantle_phase() -> float:
	if _mantle_time_left <= 0.0 or _mantle_duration <= 0.0:
		return 0.0
	return clampf(1.0 - _mantle_time_left / _mantle_duration, 0.0, 1.0)


## The ledge edge being climbed, in world space. Stays put while the body rises,
## which is what lets the hands stay planted on it.
func mantle_grab_point() -> Vector3:
	return _mantle_grab


## Horizontal, pointing out of the ledge face towards the player.
func mantle_grab_normal() -> Vector3:
	return _mantle_grab_normal


## Whether a mantle is even wanted this frame, before any geometry is probed.
##
## A jump press is intent outright, grounded or not — walk up to a lip, press
## jump, climb it. Without one you have to be genuinely airborne, and coyote time
## is exactly the window in which "off the floor" means a step edge or a stride
## rather than a jump. Gating on it is what stops running into a wall or scuffing
## a ledge from hauling you up: those never outlast COYOTE_TIME on the ground.
func _wants_mantle(grounded: bool) -> bool:
	if _jump_buffer > 0.0:
		return true
	return not grounded and _coyote <= 0.0


func _make_mantle_fit_shape() -> CapsuleShape3D:
	var shape := CapsuleShape3D.new()
	# Undersized on both axes so brushing the lip or the surface you are standing
	# on does not read as "there is no room here".
	shape.radius = _capsule.radius * 0.9
	shape.height = STAND_HEIGHT - 0.1
	return shape


## Looks for a ledge in front of the held direction and starts a mantle if one is
## there. Four probes: clear air at full mantle height (or this is a wall, not a
## lip), a downward cast onto the lip itself, a forward cast just under it for
## the face, and a standing-capsule fit at the landing spot — so a mantle can
## only ever end somewhere you could have walked to.
func _try_mantle() -> bool:
	var wish := _input_direction()
	if wish.length() < 0.1:
		return false
	var forward := Vector3(wish.x, 0.0, wish.z).normalized()

	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid()]
	var feet := global_position

	var overhead := feet + Vector3.UP * (MANTLE_MAX_HEIGHT + 0.15)
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(
			overhead, overhead + forward * MANTLE_REACH, 1, exclude)).is_empty():
		return false

	# Bounded to the mantle window at both ends, so a lip that is too low to be
	# worth climbing or too high to reach simply produces no hit.
	var probe := feet + forward * MANTLE_REACH
	var lip := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			probe + Vector3.UP * (MANTLE_MAX_HEIGHT + 0.15),
			probe + Vector3.UP * MANTLE_MIN_HEIGHT, 1, exclude))
	if lip.is_empty() or Vector3(lip["normal"]).y < MANTLE_MIN_NORMAL:
		return false
	var target: Vector3 = lip["position"]

	# Something has to actually connect you to that lip. Without this, a platform
	# floating across a gap reads exactly like a ledge you are standing under.
	var face := Vector3(feet.x, target.y - MANTLE_FACE_DROP, feet.z)
	var face_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			face, face + forward * MANTLE_REACH, 1, exclude))
	if face_hit.is_empty():
		return false

	if not _fits_standing(target):
		return false

	# The edge the hands take hold of: where the face was struck, raised to lip
	# height. Free — the probe above had to find that point anyway.
	var grab := Vector3(face_hit["position"])
	grab.y = target.y
	var grab_normal := Vector3(face_hit["normal"])
	grab_normal.y = 0.0
	if grab_normal.length() < 0.1:
		grab_normal = -forward
	_start_mantle(target, forward, grab, grab_normal.normalized())
	return true


func _fits_standing(feet: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _mantle_fit
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (STAND_HEIGHT * 0.5))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _start_mantle(target: Vector3, forward: Vector3, grab: Vector3, grab_normal: Vector3) -> void:
	# Mantling out of a dash is the good version of dashing into a wall, so the
	# dash is settled up rather than refused.
	if _dash_time_left > 0.0:
		_end_dash()
	_end_slide()
	# A buffered jump that bought this mantle is spent on it, or it would fire
	# again the moment the pull-up hands the body back.
	_jump_buffer = 0.0
	_mantle_start = global_position
	_mantle_target = target
	_mantle_direction = forward
	_mantle_grab = grab
	_mantle_grab_normal = grab_normal
	# Short climbs finish sooner. Without this a knee-high crate costs as much
	# air time as hauling yourself over head height.
	var reach := clampf((target.y - global_position.y) / MANTLE_MAX_HEIGHT, 0.0, 1.0)
	_mantle_duration = MANTLE_TIME * lerpf(0.5, 1.0, reach)
	_mantle_time_left = _mantle_duration
	_mantle_hang_y = _hang_height(target, reach)
	velocity = Vector3.ZERO


## Where the body catches the ledge before hauling itself up. Only ever below
## where the mantle started — a hang that lifted you first would eat the climb —
## and never below whatever you are standing on, because the jump-press branch can
## start a mantle from the ground.
func _hang_height(target: Vector3, reach: float) -> float:
	var hang := clampf(target.y - MANTLE_HANG_FEET_BELOW,
			global_position.y - MANTLE_HANG_DIP * reach, global_position.y)
	var space := get_world_3d().direct_space_state
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 0.1, Vector3(global_position.x, hang - 0.05,
			global_position.z), 1, [get_rid()]))
	if not ground.is_empty():
		hang = maxf(hang, Vector3(ground["position"]).y)
	return hang


## The hang comes first, then the climb, and the pull-in follows that — so you
## clear the lip before being carried over it instead of scraping the corner on
## the way past.
func _tick_mantle(delta: float) -> void:
	_mantle_time_left = maxf(0.0, _mantle_time_left - delta)
	velocity = Vector3.ZERO
	var t := 1.0 - _mantle_time_left / _mantle_duration
	var rise := smoothstep(0.0, 1.0,
			clampf((t - MANTLE_HANG) / (MANTLE_RISE_END - MANTLE_HANG), 0.0, 1.0))
	var pull := smoothstep(0.0, 1.0,
			clampf((t - MANTLE_PULL_START) / (1.0 - MANTLE_PULL_START), 0.0, 1.0))
	var catch := smoothstep(0.0, 1.0, clampf(t / MANTLE_HANG, 0.0, 1.0))
	var next := _mantle_start.lerp(_mantle_target, pull)
	next.y = lerpf(lerpf(_mantle_start.y, _mantle_hang_y, catch), _mantle_target.y, rise)
	global_position = next
	# The head follows the hands down and comes back up with the body.
	_mantle_pitch = -MANTLE_LOOK_DOWN * catch * (1.0 - rise)
	if _mantle_time_left <= 0.0:
		_end_mantle()


func _end_mantle() -> void:
	_mantle_time_left = 0.0
	_mantle_pitch = 0.0
	global_position = _mantle_target
	velocity = _mantle_direction * GameState.stat("move_speed") * MANTLE_EXIT_MULT
	_mantle_direction = Vector3.ZERO


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


## Kicks the slide off with `SLIDE_BOOST` on top of whatever you arrived at,
## which is the only way to be moving faster than the run ceiling under your own
## power. Nothing here has to protect it: the slide branch of `_apply_movement`
## has no ceiling, and standing up hands it to `MOMENTUM_DECAY`.
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


## How far into a crouch the body is, 0 to 1. Taken from the collider's real
## height rather than from the key, so it eases with the stance instead of
## snapping with the input — which is what makes it something an animation can
## be driven off.
func crouch_amount() -> float:
	return clampf(inverse_lerp(STAND_HEIGHT, CROUCH_HEIGHT, _capsule.height), 0.0, 1.0)


# --- Camera -----------------------------------------------------------------

func add_recoil(degrees: float) -> void:
	_recoil_pitch += deg_to_rad(degrees)


func _tick_camera(delta: float) -> void:
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, clampf(delta * 7.0, 0.0, 1.0))
	_tick_shunt(delta)
	_pivot.rotation.x = clampf(_pitch + _recoil_pitch + _mantle_pitch + _shunt.x,
			-1.55, 1.55)

	# Roll the camera slightly when strafing or sliding. Sideways speed is taken as
	# a fraction of the run ceiling rather than in m/s, so the tilt tops out at
	# STRAFE_ROLL no matter how much momentum is being carried — a slide boost, a
	# pad or a knockback can no longer lever the horizon further over.
	var lateral := global_transform.basis.x.dot(Vector3(velocity.x, 0.0, velocity.z))
	var ceiling := maxf(1.0, GameState.stat("move_speed") * MAX_SPEED_MULT)
	var target_roll := -clampf(lateral / ceiling, -1.0, 1.0) * STRAFE_ROLL
	if _is_sliding:
		target_roll += SLIDE_ROLL
	_roll = lerpf(_roll, target_roll, clampf(delta * 6.0, 0.0, 1.0))
	# A lerp only ever approaches its target, so on its own it leaves a sliver of
	# tilt on the horizon for as long as the player stands there. This closes the
	# last of it, which is the difference between "nearly level" and level.
	_roll = move_toward(_roll, target_roll, delta * 0.05)
	camera.rotation.z = _roll + _shunt.y

	var target_fov := Settings.fov
	var aim := 0.0
	if weapons != null:
		aim = weapons.aim_amount()
		if weapons.aiming:
			target_fov *= WeaponController.AIM_FOV_MULT
	_fov = lerpf(_fov, target_fov, clampf(delta * 8.0, 0.0, 1.0))
	# The punch rides on top of that ease rather than through it, so its own rise
	# and fall are the ones that get seen — put it in the target and the lerp above
	# flattens the asymmetry back out. Eased off by `aim_amount()` rather than by
	# `aiming`, which flips on one frame.
	var dashing := is_dashing()
	_dash_fov = move_toward(_dash_fov, 1.0 if dashing else 0.0,
			delta * (DASH_FOV_RISE if dashing else DASH_FOV_FALL))
	camera.fov = _fov + DASH_FOV_PUNCH * _dash_fov * lerpf(1.0, DASH_FOV_AIM_MULT, aim)
	# The chase camera follows the FOV preference and nothing else: no aim zoom,
	# no dash punch, no strafe roll. All three are cues for a camera in the head,
	# and on one three metres behind it they just make the subject hard to look at.
	third_person_camera.fov = Settings.fov


## Integrates the end-of-dash kick. A plain damped spring, stepped explicitly:
## `SHUNT_FREQUENCY` is well inside what a 60Hz tick integrates stably, and the
## alternative — a tween — would have to be cancelled and restarted every time a
## second dash ended inside the first one's ring-down.
func _tick_shunt(delta: float) -> void:
	if _shunt.is_zero_approx() and _shunt_velocity.is_zero_approx():
		return
	_shunt_velocity -= (_shunt * (SHUNT_FREQUENCY * SHUNT_FREQUENCY)
			+ _shunt_velocity * (2.0 * SHUNT_DAMPING * SHUNT_FREQUENCY)) * delta
	_shunt += _shunt_velocity * delta


## Kicks the camera along the direction a dash was just arrested from. Called with
## the heading still set, so it has to run before `_end_dash` clears anything.
##
## The pitch is the head carrying on forward while the body stops, which is a dip
## rather than a lift — hence both signs are negative, roll included: the existing
## strafe roll already leans the view the way a rightward run is going, and this
## leans it a little further before springing back.
func _kick_shunt() -> void:
	var strength := clampf(GameState.stat("dash_boost") / DASH_SHUNT_REFERENCE, 0.0, 1.5)
	if strength <= 0.0:
		return
	var facing := global_transform.basis
	var impulse := SHUNT_FREQUENCY / SHUNT_PEAK_GAIN * strength
	_shunt_velocity.x -= DASH_SHUNT_PITCH * (-facing.z).dot(_dash_direction) * impulse
	_shunt_velocity.y -= DASH_SHUNT_ROLL * facing.x.dot(_dash_direction) * impulse


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
	# A respawn is the one jump-cut in the game. Without this the camera flies
	# the whole distance back from wherever the body died, over one tick.
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	# Dying mid-dash freezes the timer (the movement code stops running while
	# dead), so clear it or the respawn inherits the leftover dash.
	_dash_time_left = 0.0
	_dash_exit_vy = 0.0
	_dash_entry_speed = 0.0
	# Same for a mantle: it drives position directly, so an unfinished one would
	# haul the respawned player back to the ledge they died on.
	_mantle_time_left = 0.0
	_mantle_pitch = 0.0
	_pitch = 0.0
	_recoil_pitch = 0.0
	# Camera transients too: dying mid-dash otherwise respawns you with the lens
	# still open and the horizon still swinging.
	_dash_fov = 0.0
	_shunt = Vector2.ZERO
	_shunt_velocity = Vector2.ZERO
	_roll = 0.0
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
