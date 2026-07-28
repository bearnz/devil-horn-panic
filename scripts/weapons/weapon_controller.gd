class_name WeaponController
extends Node3D
## Handles everything held in the player's hands: firing, reloading, switching,
## aiming down sights, recoil and the procedural view model.
##
## Must be a child of the player's Camera3D so it inherits the look transform.
## Weapons themselves are data (`WeaponInstance`) owned by `GameState`, so this
## node is purely presentation + input.
##
## The view model also carries two markers naming the parts of the weapon that get
## held; `ViewHands` puts a hand on each. They are rebuilt with the model, so a
## weapon switch moves the hands without either node coordinating with the other.

## World (layer 1) + enemies (layer 3). Deliberately excludes the player.
const HIT_MASK := 0b101
const MAX_PIERCE := 3

## Hand slots, in the order `hand_anchor()` indexes them. Named by side rather
## than by role because the geometry is what mirrors, and `ViewHands` is what
## reads them.
const HAND_LEFT := 0
const HAND_RIGHT := 1

const HIP_REST := Vector3(0.27, -0.29, -0.72)
const AIM_REST := Vector3(0.0, -0.13, -0.55)
## Where the weapon goes while both hands are busy holding a ledge: down and out
## of frame, rather than floating along unheld.
const STOW_OFFSET := Vector3(0.10, -0.46, 0.14)
const STOW_TILT := Vector3(1.15, 0.0, -0.70)
## Where a weapon goes to be put away or come back from: down and outboard onto
## the right hip, which is where this game keeps everything it is not holding.
## Further under the bottom edge of the frame than the mantle stow, because this
## is the offset the geometry is swapped behind — a weapon still showing a corner
## of itself when it changes into another one is the whole thing this avoids.
const HOLSTER_OFFSET := Vector3(0.16, -0.86, 0.18)
## Muzzle down and turned outwards, which is a weapon being pocketed rather than
## one merely lowered. The pitch is negative because the barrel runs down the
## model's -Z: a positive rotation about X would bring the muzzle *up*.
const HOLSTER_TILT := Vector3(-1.25, -0.40, 0.55)
## Seconds to put the old weapon away, and to bring the new one up. The draw is
## the slower half on purpose — stowing is a discard, drawing is the beat the
## player is actually watching — and the pair of them is what the trigger is dead
## for.
const HOLSTER_TIME := 0.14
const DRAW_TIME := 0.22

# --- Carry motion -----------------------------------------------------------
## The first-person half of what `PlayerBody`'s carry motion does to the arms: the
## weapon answers to what its owner is doing. Same shapes, same reasoning, at the
## scale something a hand's length from the lens wants — see the block of notes in
## that file. The walk bob further down predates all of this and stays as it is.

## Breathing, and the only motion a standing player has. Without it a held weapon
## reads as pasted onto the lens rather than carried.
const IDLE_RATE := 1.7
const IDLE_RISE := 0.006
const IDLE_DRIFT := 0.004
const IDLE_PITCH := 0.022

## Vertical inertia, off the player's own vertical velocity: down as the body is
## thrown up out from under the weapon, up as it drops away underneath it. Metres
## per metre per second, clamped, and faded out on the ground where the reading is
## nothing but the floor snap.
const AIR_LAG := 0.006
const AIR_LAG_MAX := 0.05
## Radians of muzzle pitch per metre of that lag.
const AIR_PITCH := 1.1
const AIR_BLEND_RATE := 8.0

## A dash leaves the weapon trailing the body flung out from under it; a slide tucks
## it in and points it up, clear of knees that have come up in front of it. Both
## quoted in the *camera's* frame, so looking around mid-dash re-reads which way the
## lag falls instead of dragging a fixed offset around the screen.
const DASH_LAG := 0.07
const DASH_SIDE_LAG := 0.05
const DASH_DROP := 0.035
const DASH_PITCH := 0.16
const SLIDE_TUCK := 0.05
const SLIDE_RISE := 0.03
const SLIDE_PITCH := -0.18
## How fast the dash and slide offsets ease in and out. Both states start and stop
## on a single frame, and a weapon that changed pose that fast would pop.
const STATE_BLEND_RATE := 9.0

## Stages of a switch. LOWER runs until the old weapon is under the frame, the
## geometry is rebuilt at the bottom of it, and RAISE brings the new one back up.
const SWAP_NONE := 0
const SWAP_LOWER := 1
const SWAP_RAISE := 2
## Hip-fire yaw. Angling the muzzle slightly outwards shows the weapon's profile
## instead of its back plate, which is what makes a blocky model read as a gun.
const HIP_YAW := -0.15
## How the shooting hand is turned about the grip it holds. A constant rather than
## a literal in the anchor because the body's weapon is placed by inverting it.
const GRIP_ANCHOR_EULER := Vector3(0.80, 0.34, -0.16)
const AIM_FOV_MULT := 0.74
const AIM_SPREAD_MULT := 0.42
## How much of the movement motion survives aiming down sights, and how fast the two
## blend. Sights are the game promising that the muzzle is where the crosshair is,
## and every offset in this file is a small lie about where the weapon is — harmless
## at the hip, where the weapon is scenery in the corner of the frame, and the entire
## picture once the player is looking down the barrel of it.
##
## Two multipliers rather than one, and the split is between an oscillation and a
## pose. Breathing, the walk bob, look sway and vertical inertia are what "the gun
## sways" means, and they go nearly all the way out — nearly, because a weapon that
## goes *perfectly* still reads as a HUD element rather than as something being held.
## The dash and slide offsets are not sway; they are where the weapon is carried
## while the body is doing something, and on the body they are what holds it clear of
## knees that have come up in front of it. Those are damped rather than deleted.
##
## Recoil is deliberately not on this list. It is the weapon answering a shot, not
## the player's movement, and it is already cut by `_recoil` while aiming.
const AIM_SWAY_MULT := 0.15
const AIM_STANCE_MULT := 0.5
const AIM_BLEND_RATE := 12.0
## Most of a shot's cooldown that is allowed to carry past zero, so the next one
## can start early by however much this one overran. A frame at the lowest rate
## worth playing at, which covers the overshoot at every rate above it and is
## still a third of the shortest fire interval in the game — so a frame long
## enough to bank the whole allowance cannot come back as two shots at once.
const MAX_CARRY := 1.0 / 30.0

## Set false while a menu is open so clicks on buttons do not also fire.
var enabled: bool = true
var aiming: bool = false

var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _reload_total: float = 0.0
var _kick: Vector3 = Vector3.ZERO
var _kick_rot: Vector3 = Vector3.ZERO
var _sway: Vector2 = Vector2.ZERO
var _bob_time: float = 0.0
## Breathing clock, vertical inertia, and the two stances that need easing. The
## dash heading is held in the *camera's* frame and re-read every frame it runs,
## so turning mid-dash swings the lag round with the view.
var _idle_time: float = 0.0
var _air_lag: float = 0.0
## 0 hip-fire, 1 down the sights, eased. `aiming` itself flips on a single frame and
## the motion it scales is a sine that is somewhere in the middle of its swing when
## it does, so stepping the scale would snap the weapon by whatever the sine happened
## to be worth at that instant.
var _aim: float = 0.0
var _dash: float = 0.0
var _dash_forward: float = 0.0
var _dash_side: float = 0.0
var _slide: float = 0.0
## The carry motion as of this frame, offset and euler — a pair rather than a
## transform because the pose it is added to is built as a pair, and rolling these
## through a Basis and back out again would only be a way to lose a sign.
var _motion: Vector3 = Vector3.ZERO
var _motion_rot: Vector3 = Vector3.ZERO
## 0 held, 1 fully out of frame. Driven by the player mantling.
var _stow: float = 0.0
## 0 in hand, 1 down at the hip. Driven by a weapon switch, and unlike everything
## else here it runs to a clock rather than easing towards a target — see
## `_tick_swap`.
var _holster: float = 0.0
var _swap_phase: int = SWAP_NONE
## The loadout index a switch in flight is heading for, or -1 when none is.
var _pending_index: int = -1
## The held pose as smoothed, before the holster is laid over the top of it. Kept
## apart from the node's own transform because the holster is applied *after* the
## smoothing rather than through it, and a lerp cannot be both the input and the
## output of the same frame.
var _held_pos: Vector3 = HIP_REST
var _held_rot: Vector3 = Vector3.ZERO

var _camera: Camera3D
var _player: CharacterBody3D
var _view_root: Node3D
var _muzzle: Marker3D
## Wrist poses for the weapon currently built, indexed by HAND_LEFT/HAND_RIGHT.
## Rebuilt with the view model, so switching weapons moves the hands with it.
var _hand_anchors: Array[Marker3D] = [null, null]


func _ready() -> void:
	_camera = get_parent() as Camera3D
	if _camera == null:
		push_error("WeaponController must be a child of a Camera3D")
	_player = _find_player()
	equip(GameState.equipped_index)


func _find_player() -> CharacterBody3D:
	var node: Node = get_parent()
	while node != null:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


# --- Public API -------------------------------------------------------------

func current() -> WeaponInstance:
	if GameState.loadout.is_empty():
		return null
	var index := clampi(GameState.equipped_index, 0, GameState.loadout.size() - 1)
	return GameState.loadout[index]


## Switches weapons by putting the current one away and taking the next one out:
## the weapon in hand drops to the right hip, the geometry is rebuilt down there
## where none of it is in shot, and the new one comes back up the same way.
##
## Nothing about this is instant, and that is the point of it. `current()` keeps
## reporting the old weapon until the new one is actually in hand, so the HUD's
## ammo, the hands, the body's copy in the fist and what a trigger pull would fire
## all change over on the single frame the player sees the swap happen. The one
## exception is the first weapon of a run: there is nothing to put away, so it is
## drawn from the hip without the lowering half.
func equip(index: int) -> void:
	if GameState.loadout.is_empty():
		return
	index = clampi(index, 0, GameState.loadout.size() - 1)
	if _view_root == null:
		_apply_equip(index)
		_holster = 1.0
		_swap_phase = SWAP_RAISE
		return
	if index == target_index():
		return
	_pending_index = index
	_swap_phase = SWAP_LOWER


## The weapon a switch in flight is heading for, or the equipped one when nothing
## is. What `cycle` steps from: read `GameState.equipped_index` instead and tapping
## next twice inside one swap advances once and then back to where it started.
func target_index() -> int:
	return _pending_index if _pending_index >= 0 else GameState.equipped_index


## Whether a switch is in flight. The trigger is dead for the duration — the old
## weapon has been put away and the new one is not up yet.
func is_swapping() -> bool:
	return _swap_phase != SWAP_NONE


## How far the weapon is down at the hip, 0 in hand to 1 clear of the frame, eased.
## `PlayerBody` reads this so the weapon in the fist makes the same trip the one in
## front of the camera does, and the two arrive at the hip together.
func swap_amount() -> float:
	return smoothstep(0.0, 1.0, _holster)


## Puts the new weapon in hand. Called at the bottom of a switch, with the old one
## already under the frame, or straight away when there was nothing to put away.
func _apply_equip(index: int) -> void:
	GameState.equipped_index = index
	_pending_index = -1
	_reload_left = 0.0
	_cooldown = maxf(_cooldown, 0.25)
	_build_view_model(current().data)
	Events.weapon_equipped.emit(current())
	Events.ammo_changed.emit(current())


func cycle(step: int) -> void:
	if GameState.loadout.size() < 2:
		return
	var count := GameState.loadout.size()
	equip(wrapi(target_index() + step, 0, count))


## Pulls the trigger if the weapon is ready, ignoring input state. Returns true
## when the shot was taken (or spent on an empty magazine). Used by the input
## path and by anything scripted that needs to shoot.
func try_fire() -> bool:
	var inst := current()
	if inst == null or _reload_left > 0.0 or _cooldown > 0.0 or _is_mantling() \
			or is_swapping():
		return false
	_fire(inst)
	return true


func start_reload() -> void:
	var inst := current()
	if inst == null or _reload_left > 0.0 or is_swapping() or not inst.can_reload():
		return
	_reload_total = inst.reload_duration()
	_reload_left = _reload_total
	Events.reload_started.emit(inst, _reload_total)


func is_reloading() -> bool:
	return _reload_left > 0.0


## Extra look-sway fed in by the player's mouse look.
func add_look_sway(relative: Vector2) -> void:
	_sway += relative * 0.0006
	_sway = _sway.limit_length(0.05)


## The weapon's geometry as built, in front of the camera. Exposed for the dev
## tools, which need to ask where it actually is on the screen — by reference and
## not by node name, because a rebuilt model shares the tree with the one it is
## replacing until the end of the frame and Godot renames the newcomer to keep the
## two apart.
func view_model() -> Node3D:
	return _view_root


## Where each wrist goes on the weapon as built. Null until a view model exists.
func hand_anchor(side: int) -> Marker3D:
	if side < 0 or side >= _hand_anchors.size():
		return null
	return _hand_anchors[side]


## 0 at rest, ~1 just after a shot, decaying with the kick. Read off the same
## kick the view model rides so the hands and the weapon can never disagree about
## having fired.
func recoil_strength() -> float:
	return clampf(absf(_kick_rot.x) * 3.5 + maxf(_kick.z, 0.0) * 4.0, 0.0, 1.2)


## How far the weapon has been put away, 0 held to 1 out of frame.
func stow_amount() -> float:
	return _stow


## How far down the sights the weapon is, 0 hip-fire to 1 aiming, eased. `PlayerBody`
## reads this to steady the copy in the fist by exactly as much, so the weapon the
## arena sees and the weapon the player sees hold equally still.
func aim_amount() -> float:
	return smoothstep(0.0, 1.0, _aim)


## Duck-typed rather than typing `_player` as Player: everything else this node
## asks of the body it hangs under is optional too.
func _is_mantling() -> bool:
	return _player != null and _player.has_method("is_mantling") and _player.is_mantling()


func _is_dashing() -> bool:
	return _player != null and _player.has_method("is_dashing") and _player.is_dashing()


func _is_sliding() -> bool:
	return _player != null and _player.has_method("is_sliding") and _player.is_sliding()


# --- Frame loop -------------------------------------------------------------

func _process(delta: float) -> void:
	# Floored below zero rather than at it, so the sliver by which a cooldown
	# overran the frame it expired on survives to be paid back by the next shot.
	# Clamped at zero instead — with `_fire` assigning the interval outright — and
	# every shot rounds up to a whole frame, which puts the fire rate on the frame
	# rate: the Shredder's 11/s measured 9.96 at 60fps against 11.00 at 240.
	# MAX_CARRY bounds the debt to well under the shortest interval in the game,
	# so a hitch cannot bank enough credit to come back as a burst.
	_cooldown = maxf(_cooldown - delta, -MAX_CARRY)
	_tick_reload(delta)
	# Ahead of the animation, so the frame a switch hands over is a frame the new
	# weapon is placed on rather than one it spends at the origin.
	_tick_swap(delta)
	# A mantle takes both hands, so it takes the trigger with them.
	if enabled and not _is_mantling():
		_handle_input()
	else:
		aiming = false
	# Advanced up here rather than down inside the animation, because the pose is
	# assembled in several passes and every one of them wants the same reading — and
	# because `PlayerBody` reads it off this node on its own frame loop.
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, delta * AIM_BLEND_RATE)
	_animate_view_model(delta)


func _tick_reload(delta: float) -> void:
	if _reload_left <= 0.0:
		return
	_reload_left -= delta
	if _reload_left <= 0.0:
		_reload_left = 0.0
		var inst := current()
		if inst != null:
			inst.do_reload()
			Events.reload_finished.emit(inst)
			Events.ammo_changed.emit(inst)


## Runs a switch: down, swap, up. The rebuild lands exactly on `_holster` reaching
## 1, which is the one moment none of the weapon is in shot.
##
## Driven off a clock rather than eased towards a target, which is the difference
## between this and every other offset in the file. An ease has no moment it is
## finished — it is merely close — and "close to the hip" is a weapon whose last
## centimetre of receiver is still showing above the bottom edge when it turns into
## a different one.
func _tick_swap(delta: float) -> void:
	if _swap_phase == SWAP_LOWER:
		_holster = move_toward(_holster, 1.0, delta / HOLSTER_TIME)
		if _holster >= 1.0:
			_apply_equip(_pending_index)
			_swap_phase = SWAP_RAISE
	elif _swap_phase == SWAP_RAISE:
		_holster = move_toward(_holster, 0.0, delta / DRAW_TIME)
		if _holster <= 0.0:
			_swap_phase = SWAP_NONE


## Advances the breathing clock and the three readings the carry motion is built
## from, then works out this frame's offset. `_motion` and `_motion_rot` are what
## `_animate_view_model` adds to the rest pose.
##
## The dash heading is taken in the camera's frame and re-read while it runs, which
## is what makes a mid-dash turn swing the lag round with the view instead of
## dragging a fixed offset across the screen.
func _tick_carry_motion(delta: float) -> void:
	_idle_time = wrapf(_idle_time + delta * IDLE_RATE, 0.0, TAU)
	_slide = move_toward(_slide, 1.0 if _is_sliding() else 0.0, delta * STATE_BLEND_RATE)
	var dashing := _is_dashing()
	_dash = move_toward(_dash, 1.0 if dashing else 0.0, delta * STATE_BLEND_RATE)
	if dashing and _camera != null:
		var heading: Vector3 = _player.dash_direction()
		var frame := _camera.global_transform.basis
		_dash_forward = -frame.z.dot(heading)
		_dash_side = frame.x.dot(heading)

	var want := 0.0
	if _player != null and not _player.is_on_floor():
		want = clampf(-_player.velocity.y * AIR_LAG, -AIR_LAG_MAX, AIR_LAG_MAX)
	_air_lag = lerpf(_air_lag, want, clampf(delta * AIR_BLEND_RATE, 0.0, 1.0))

	# Aiming steadies the whole block, the sway harder than the stance — see
	# AIM_SWAY_MULT. Applied to each term as it is added rather than to the total,
	# because the two halves are damped by different amounts and the sum has no way
	# of telling them apart afterwards.
	var aim := aim_amount()
	var sway_scale := lerpf(1.0, AIM_SWAY_MULT, aim)
	var stance_scale := lerpf(1.0, AIM_STANCE_MULT, aim)

	# Breathing, and only while there is nothing louder — a dash or a slide with a
	# slow sine still running underneath it is two animations fighting.
	var quiet := clampf(1.0 - _slide - _dash, 0.0, 1.0) * sway_scale
	_motion = Vector3(sin(_idle_time * 0.5) * IDLE_DRIFT, sin(_idle_time) * IDLE_RISE, 0.0) \
			* quiet
	_motion_rot = Vector3(sin(_idle_time) * IDLE_PITCH * quiet, 0.0, 0.0)

	# Vertical inertia: down as the body is thrown up, up as it drops away.
	_motion.y += _air_lag * sway_scale
	_motion_rot.x += _air_lag * AIR_PITCH * sway_scale

	# +Z is back, so a dash forward lags positive and one backwards lags forward.
	if _dash > 0.0:
		_motion += Vector3(-DASH_SIDE_LAG * _dash_side, -DASH_DROP,
				DASH_LAG * _dash_forward) * _dash * stance_scale
		_motion_rot.x += DASH_PITCH * _dash_forward * _dash * stance_scale

	_motion += Vector3(0.0, SLIDE_RISE, SLIDE_TUCK) * _slide * stance_scale
	_motion_rot.x += SLIDE_PITCH * _slide * stance_scale


func _handle_input() -> void:
	var inst := current()
	if inst == null:
		return

	# Sights are dropped for the switch: the rest pose the holster is authored
	# against is the hip one, and a weapon pulled to the eye on its way to the
	# pocket goes there by a route no hand takes.
	aiming = Input.is_action_pressed("aim") and not is_swapping()

	if Input.is_action_just_pressed("reload"):
		start_reload()
	if Input.is_action_just_pressed("weapon_next"):
		cycle(1)
	if Input.is_action_just_pressed("weapon_prev"):
		cycle(-1)
	for slot in range(mini(3, GameState.loadout.size())):
		if Input.is_action_just_pressed("weapon_%d" % (slot + 1)):
			equip(slot)

	var wants_fire := (Input.is_action_pressed("fire") if inst.data.automatic
			else Input.is_action_just_pressed("fire"))
	if wants_fire:
		try_fire()


# --- Firing -----------------------------------------------------------------

func _fire(inst: WeaponInstance) -> void:
	if inst.ammo <= 0:
		_cooldown = 0.25
		if inst.can_reload():
			start_reload()
		else:
			Events.notice.emit("Out of ammo")
		return

	inst.ammo -= 1
	# Added to whatever is left rather than assigned, and what is left is at most
	# zero — see the carry in _process.
	_cooldown += inst.fire_interval()

	var origin := _aim_origin()
	var forward := _aim_direction()
	var spread := inst.stat("spread_deg") * (AIM_SPREAD_MULT if aiming else 1.0)
	for _pellet in range(inst.pellets()):
		var direction := _apply_spread(forward, spread)
		if inst.data.projectile != null:
			_spawn_projectile(inst, direction)
		else:
			_hitscan(inst, origin, direction)

	_recoil(inst)
	CombatFX.impact(self, _muzzle.global_position, -_camera.global_transform.basis.z,
			inst.data.view_color, 0.7)
	Events.ammo_changed.emit(inst)
	if inst.ammo == 0 and inst.can_reload():
		start_reload()


func _aim_origin() -> Vector3:
	return _camera.project_ray_origin(_screen_centre())


func _aim_direction() -> Vector3:
	return _camera.project_ray_normal(_screen_centre())


func _screen_centre() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5


func _apply_spread(direction: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.0:
		return direction
	var basis := _camera.global_transform.basis
	var amount := deg_to_rad(spread_deg)
	return (direction
			.rotated(basis.y, randf_range(-amount, amount))
			.rotated(basis.x, randf_range(-amount, amount))
			.normalized())


func _hitscan(inst: WeaponInstance, origin: Vector3, direction: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var distance := inst.stat("max_range")
	var far_end := origin + direction * distance
	var exclude: Array[RID] = []
	if _player != null:
		exclude.append(_player.get_rid())

	var from := origin
	var tracer_end := far_end
	var pierces := MAX_PIERCE if inst.has_flag("pierce") else 1

	while pierces > 0:
		var query := PhysicsRayQueryParameters3D.create(from, far_end, HIT_MASK, exclude)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit["collider"]
		var point: Vector3 = hit["position"]
		tracer_end = point
		_resolve_hit(inst, collider, point, hit["normal"], direction)

		# Bullets stop at level geometry; only bodies can be pierced.
		if not (collider is Node and (collider as Node).is_in_group("enemies")):
			break
		pierces -= 1
		if collider is CollisionObject3D:
			exclude.append((collider as CollisionObject3D).get_rid())
		from = point + direction * 0.05

	CombatFX.tracer(_fx_host(), _muzzle.global_position, tracer_end, inst.data.view_color)


func _resolve_hit(inst: WeaponInstance, collider: Object, point: Vector3, normal: Vector3,
		direction: Vector3) -> void:
	var host := _fx_host()
	var is_crit := randf() < inst.crit_chance()
	var damage := inst.damage() * (inst.crit_mult() if is_crit else 1.0)

	if inst.has_flag("explosive"):
		var radius: float = maxf(2.0, inst.stat("blast_radius"))
		CombatFX.explode(host, point, radius, damage * 0.6, "enemies")

	if collider != null and collider.has_method("apply_damage"):
		collider.apply_damage(damage, is_crit, point, direction)
		if collider is Node3D:
			_apply_knockback(collider as Node3D, direction, inst.stat("impact_force"))
		CombatFX.impact(host, point, normal, Color(1.0, 0.85, 0.35), 1.3 if is_crit else 1.0)
	else:
		CombatFX.impact(host, point, normal, Color(0.85, 0.8, 0.75), 0.8)


func _apply_knockback(target: Node3D, direction: Vector3, force: float) -> void:
	if force > 0.0 and target.has_method("apply_knockback"):
		target.apply_knockback(direction * force)


func _spawn_projectile(inst: WeaponInstance, direction: Vector3) -> void:
	var shot := inst.data.projectile.instantiate() as Area3D
	if shot == null:
		push_warning("Weapon %s: projectile scene is not an Area3D" % inst.data.id)
		return
	_fx_host().add_child(shot)
	shot.launch(_muzzle.global_position, direction, inst.stat("projectile_speed"),
			inst.damage(), inst.stat("blast_radius"), "enemies", inst.data.view_color)


func _recoil(inst: WeaponInstance) -> void:
	var amount := inst.stat("recoil") * (0.6 if aiming else 1.0)
	if _player != null and _player.has_method("add_recoil"):
		_player.add_recoil(amount)
	_kick += Vector3(randf_range(-0.01, 0.01), 0.012, 0.055) * (1.0 + amount)
	_kick_rot += Vector3(-0.09 * (1.0 + amount * 0.5), randf_range(-0.02, 0.02), 0.0)


## FX are parented into the world so they do not ride along with the camera.
func _fx_host() -> Node3D:
	if _player != null and _player.get_parent() is Node3D:
		return _player.get_parent()
	return get_tree().current_scene as Node3D


# --- View model -------------------------------------------------------------

## The weapon's geometry on its own, built from the authored sizes, as a node that
## can be parented anywhere.
##
## Two callers want it. This one hangs it in front of the camera; `PlayerBody`
## puts a second copy in the fist of the humanoid the camera is standing inside,
## because the view model is a child of the camera and would follow it rather than
## the body. Static, because that second caller has no controller and no business
## having one — a weapon on a body is scenery, not something that can be fired.
##
## `cast_shadows` is the whole difference between the two. The view model is a
## hand's length from the lens and is not really there; the body's copy is what
## the arena sees, and is what puts a rifle in the player's shadow.
static func build_model(data: WeaponData, cast_shadows: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "WeaponModel"

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = data.view_color.darkened(0.3)
	body_mat.metallic = 0.7
	body_mat.roughness = 0.35
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = data.view_color
	accent_mat.emission_enabled = true
	accent_mat.emission = data.view_color
	accent_mat.emission_energy_multiplier = 0.6

	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_box(root, data.body_size, Vector3.ZERO, body_mat, shadow)
	_add_box(root, data.barrel_size,
			Vector3(0.0, data.body_size.y * 0.18, barrel_offset_z(data)), accent_mat, shadow)
	# Grip hangs off the underside of the receiver's rear, not through it.
	_add_box(root, data.grip_size,
			Vector3(0.0, grip_offset_y(data), data.body_size.z * 0.28), body_mat, shadow)
	return root


## Where the barrel starts and where the grip hangs, both derived from the body
## box. Shared because the muzzle, the hand anchors and the boxes themselves all
## have to agree about them, and three copies of the same arithmetic is three
## chances for a weapon to fire out of its own receiver.
static func barrel_offset_z(data: WeaponData) -> float:
	return -(data.body_size.z * 0.5 + data.barrel_size.z * 0.5)


static func grip_offset_y(data: WeaponData) -> float:
	return -(data.body_size.y * 0.5 + data.grip_size.y * 0.4)


## Where a wrist goes to hold this weapon, in the weapon model's own frame: the
## anchor's pose with the palm's length taken back off it, which is exactly what
## `ViewHands` does to a live anchor. Static so `PlayerBody` can put a pair of real
## hands on the same two parts without a controller to ask — the hands you look at
## and the hands your shadow has hold the same gun in the same places or the
## illusion is off by however much they disagree.
static func wrist_in_model_frame(data: WeaponData, side: int) -> Transform3D:
	return anchor_transform(data, side) \
			* Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, HandRig.KNUCKLE_REACH))


## Where the weapon sits in the frame of the hand that holds it.
##
## `ViewHands` solves this the other way round — the view model is the thing that
## is placed and the hands are moved onto it — but a body already has hands on the
## ends of real arms, so there the weapon is what has to be put somewhere. Same
## grip either way, run backwards.
static func model_in_grip_frame(data: WeaponData) -> Transform3D:
	return wrist_in_model_frame(data, HAND_RIGHT).affine_inverse()


func _build_view_model(data: WeaponData) -> void:
	if _view_root != null:
		# Out of the tree before it is queued, not merely queued: a freeing node is
		# still a child until the end of the frame, so the replacement would be
		# renamed around it and would render alongside it for a frame.
		remove_child(_view_root)
		_view_root.queue_free()
	_view_root = build_model(data, false)
	_view_root.name = "ViewModel"
	add_child(_view_root)

	var barrel_z := barrel_offset_z(data)
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0.0, data.body_size.y * 0.18, barrel_z - data.barrel_size.z * 0.5)
	_view_root.add_child(_muzzle)

	_build_hand_anchors(data)


## Markers on the built model, one per hand, so `ViewHands` can copy them without
## knowing any of the arithmetic below. The poses themselves are static and shared:
## the body's copy of this weapon is placed by inverting the right-hand one, and its
## off hand is sent to the left-hand one, so the two pairs of hands cannot drift.
func _build_hand_anchors(data: WeaponData) -> void:
	for side in [HAND_LEFT, HAND_RIGHT]:
		var marker := Marker3D.new()
		marker.name = "GripAnchor" if side == HAND_RIGHT else "SupportAnchor"
		marker.transform = anchor_transform(data, side)
		_view_root.add_child(marker)
		_hand_anchors[side] = marker


## What each hand holds, derived from the same authored sizes the boxes are built
## from — so a new weapon gets plausible hands without authoring any.
##
## An anchor marks the point the knuckles close around, *not* where the wrist
## goes: -Z is the way the fingers reach and +Z the way the forearm runs, and
## `wrist_in_model_frame()` sets the wrist back along that by the length of a palm.
## This file therefore only has to know where a weapon is held, which is the half of
## the problem it can actually answer.
##
## Both forearms are angled steeply down and outwards so they leave frame at the
## bottom corners instead of standing up through the middle of it.
## A hand rig is a straight line — forearm, palm, fingers — so pointing the fingers
## at what they hold necessarily points the forearm away from it. That works out:
## a fist closing up and forward onto a grip post has its forearm coming from below
## and behind, which is where an arm actually is.
static func anchor_transform(data: WeaponData, side: int) -> Transform3D:
	# Low on the grip, so the fist sits clear under the receiver instead of behind
	# it where nothing of it can be seen.
	if side == HAND_RIGHT:
		return Transform3D(Basis.from_euler(GRIP_ANCHOR_EULER),
				Vector3(0.004, grip_offset_y(data) - data.grip_size.y * 0.20,
						data.body_size.z * 0.28))
	if data.support_grip == WeaponData.SupportGrip.CUPPED:
		# Pistol: the off hand wraps the shooting hand from outboard and below.
		return Transform3D(Basis.from_euler(Vector3(0.74, -0.95, 0.30)),
				Vector3(-data.grip_size.x * 0.62,
						grip_offset_y(data) - data.grip_size.y * 0.34,
						data.body_size.z * 0.28 + 0.008))
	# A barrel runs the way the fingers would otherwise point, so this hand is
	# turned side-on to reach *across* it: fingers over the top from the left,
	# forearm dropping away to the left, which is also the side facing the camera.
	return Transform3D(Basis.from_euler(Vector3(0.70, -1.50, 0.0)),
			Vector3(-data.barrel_size.x * 0.30,
					data.body_size.y * 0.18 - data.barrel_size.y * 0.15,
					barrel_offset_z(data) + data.barrel_size.z * 0.14))


static func _add_box(root: Node3D, size: Vector3, offset: Vector3, material: Material,
		shadow: GeometryInstance3D.ShadowCastingSetting) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = offset
	mesh.cast_shadow = shadow
	root.add_child(mesh)


func _animate_view_model(delta: float) -> void:
	if _view_root == null:
		return
	var inst := current()
	var rest := (AIM_REST if aiming else HIP_REST)
	if inst != null:
		rest += inst.data.view_offset

	# Everything below that is a wobble rather than a rest pose is damped by this
	# while the player is aiming. Eased off `_aim`, so the term is scaled down over
	# the same fraction of a second the weapon takes to come up to the eye instead of
	# stepping on the frame the button went down.
	var sway_scale := lerpf(1.0, AIM_SWAY_MULT, aim_amount())

	# Walk bob, scaled by horizontal speed and killed in the air.
	var bob := Vector3.ZERO
	if _player != null:
		var planar := Vector2(_player.velocity.x, _player.velocity.z).length()
		var grounded: bool = _player.is_on_floor()
		if grounded and planar > 0.5:
			_bob_time += delta * clampf(planar, 2.0, 14.0)
			var strength := clampf(planar / 12.0, 0.0, 1.0) * sway_scale
			bob = Vector3(cos(_bob_time * 0.6) * 0.012, absf(sin(_bob_time * 1.2)) * -0.010, 0.0) * strength

	# Reload dips the weapon out of frame and back.
	var reload_offset := Vector3.ZERO
	var reload_tilt := 0.0
	if _reload_left > 0.0 and _reload_total > 0.0:
		var phase := sin((1.0 - _reload_left / _reload_total) * PI)
		reload_offset = Vector3(0.0, -0.16 * phase, 0.06 * phase)
		reload_tilt = -0.5 * phase

	# Mantling puts the weapon away and takes it back out. Stowing is quicker than
	# drawing so it is clear of frame before the hands reach the ledge.
	var stow_target := 1.0 if _is_mantling() else 0.0
	_stow = move_toward(_stow, stow_target, delta * (9.0 if stow_target > 0.0 else 5.0))

	_tick_carry_motion(delta)

	_kick = _kick.lerp(Vector3.ZERO, clampf(delta * 11.0, 0.0, 1.0))
	_kick_rot = _kick_rot.lerp(Vector3.ZERO, clampf(delta * 9.0, 0.0, 1.0))
	_sway = _sway.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))

	# Look sway is the loudest of the lot down the sights: it is driven by the mouse,
	# so it fires on exactly the input the player is making to keep the crosshair on
	# something. Damped here rather than at the source, because `add_look_sway` also
	# has to keep feeding the accumulator while aiming — kill it there and letting go
	# of the trigger finger snaps the weapon back into a sway it never built up.
	var sway := _sway * sway_scale

	var target_pos := rest + bob + reload_offset + Vector3(-sway.x, sway.y, 0.0) + _kick \
			+ STOW_OFFSET * _stow + _motion
	var target_rot := Vector3(
		_kick_rot.x + reload_tilt,
		_kick_rot.y - sway.x * 4.0 + (0.0 if aiming else HIP_YAW),
		_kick_rot.z + sway.x * 2.0) + STOW_TILT * _stow + _motion_rot

	_held_pos = _held_pos.lerp(target_pos, clampf(delta * 18.0, 0.0, 1.0))
	_held_rot = _held_rot.lerp(target_rot, clampf(delta * 16.0, 0.0, 1.0))
	# The trip to the hip goes on top of the smoothed pose rather than through it,
	# so it runs to `_tick_swap`'s clock and arrives when that says it has. Smoothing
	# it as well would leave the weapon short of the hip on the frame it is rebuilt,
	# and a rebuild in shot is the one thing this animation exists to hide. It also
	# survives the rebuild, since these two carry the held pose across it — the new
	# weapon comes up from wherever the old one was put down.
	var down := swap_amount()
	_view_root.position = _held_pos + HOLSTER_OFFSET * down
	_view_root.rotation = _held_rot + HOLSTER_TILT * down
