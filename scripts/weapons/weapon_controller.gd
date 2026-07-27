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
## Hip-fire yaw. Angling the muzzle slightly outwards shows the weapon's profile
## instead of its back plate, which is what makes a blocky model read as a gun.
const HIP_YAW := -0.15
## How the shooting hand is turned about the grip it holds. A constant rather than
## a literal in the anchor because the body's weapon is placed by inverting it.
const GRIP_ANCHOR_EULER := Vector3(0.80, 0.34, -0.16)
const AIM_FOV_MULT := 0.74
const AIM_SPREAD_MULT := 0.42
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
## 0 held, 1 fully out of frame. Driven by the player mantling.
var _stow: float = 0.0

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


func equip(index: int) -> void:
	if GameState.loadout.is_empty():
		return
	GameState.equipped_index = clampi(index, 0, GameState.loadout.size() - 1)
	_reload_left = 0.0
	_cooldown = maxf(_cooldown, 0.25)
	_kick_rot.x = -0.35
	_build_view_model(current().data)
	Events.weapon_equipped.emit(current())
	Events.ammo_changed.emit(current())


func cycle(step: int) -> void:
	if GameState.loadout.size() < 2:
		return
	var count := GameState.loadout.size()
	equip(wrapi(GameState.equipped_index + step, 0, count))


## Pulls the trigger if the weapon is ready, ignoring input state. Returns true
## when the shot was taken (or spent on an empty magazine). Used by the input
## path and by anything scripted that needs to shoot.
func try_fire() -> bool:
	var inst := current()
	if inst == null or _reload_left > 0.0 or _cooldown > 0.0 or _is_mantling():
		return false
	_fire(inst)
	return true


func start_reload() -> void:
	var inst := current()
	if inst == null or _reload_left > 0.0 or not inst.can_reload():
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


## Duck-typed rather than typing `_player` as Player: everything else this node
## asks of the body it hangs under is optional too.
func _is_mantling() -> bool:
	return _player != null and _player.has_method("is_mantling") and _player.is_mantling()


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
	# A mantle takes both hands, so it takes the trigger with them.
	if enabled and not _is_mantling():
		_handle_input()
	else:
		aiming = false
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


func _handle_input() -> void:
	var inst := current()
	if inst == null:
		return

	aiming = Input.is_action_pressed("aim")

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

	# Walk bob, scaled by horizontal speed and killed in the air.
	var bob := Vector3.ZERO
	if _player != null:
		var planar := Vector2(_player.velocity.x, _player.velocity.z).length()
		var grounded: bool = _player.is_on_floor()
		if grounded and planar > 0.5:
			_bob_time += delta * clampf(planar, 2.0, 14.0)
			var strength := clampf(planar / 12.0, 0.0, 1.0) * (0.35 if aiming else 1.0)
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

	_kick = _kick.lerp(Vector3.ZERO, clampf(delta * 11.0, 0.0, 1.0))
	_kick_rot = _kick_rot.lerp(Vector3.ZERO, clampf(delta * 9.0, 0.0, 1.0))
	_sway = _sway.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))

	var target_pos := rest + bob + reload_offset + Vector3(-_sway.x, _sway.y, 0.0) + _kick \
			+ STOW_OFFSET * _stow
	var target_rot := Vector3(
		_kick_rot.x + reload_tilt,
		_kick_rot.y - _sway.x * 4.0 + (0.0 if aiming else HIP_YAW),
		_kick_rot.z + _sway.x * 2.0) + STOW_TILT * _stow

	_view_root.position = _view_root.position.lerp(target_pos, clampf(delta * 18.0, 0.0, 1.0))
	_view_root.rotation = _view_root.rotation.lerp(target_rot, clampf(delta * 16.0, 0.0, 1.0))
