class_name ViewHands
extends Node3D
## Procedural first-person hands: two gloved boxes-and-fingers rigs that hold
## whatever weapon is equipped and let go of it to climb a ledge.
##
## Two poses, blended every frame:
##
## **Hold** — each wrist copies a marker on the weapon's view model, so the hands
## inherit its rest pose, bob, sway and recoil kick without knowing anything about
## them. A weapon switch rebuilds those markers from the new `WeaponData` sizes
## and the hands follow, which is why they are not simply modelled per weapon.
##
## **Grab** — during a mantle the hands are pinned to a point in the *world*
## instead, so the ledge stays put while the camera climbs past it. That is the
## whole illusion, and it is also why these are not children of the view model:
## they have to be able to leave it.
##
## Poses are assigned rather than smoothed toward. The anchors are already
## smoothed by the weapon controller, and any lag on top would let the grab pose
## drift off the ledge it is supposed to be holding.
##
## Must sit under the camera as a sibling of the WeaponController, *after* it in
## the tree, so it reads anchors the controller has already moved this frame.

## Wrist-relative geometry, all in metres. Deliberately small: the view models
## are undersized (a receiver is 0.08–0.12 wide), so a real 9cm palm would swamp
## the gun it is meant to be holding.
const FOREARM_SIZE := Vector3(0.064, 0.064, 0.20)
const FOREARM_OFFSET := Vector3(0.0, 0.0, 0.11)
const CUFF_SIZE := Vector3(0.072, 0.072, 0.020)
const CUFF_OFFSET := Vector3(0.0, 0.0, 0.012)
const PALM_SIZE := Vector3(0.086, 0.050, 0.090)
const PALM_OFFSET := Vector3(0.0, -0.004, -0.050)
const FINGER_SIZE := Vector3(0.019, 0.023, 0.040)
const FINGER_TIP_SIZE := Vector3(0.018, 0.021, 0.034)
const THUMB_SIZE := Vector3(0.024, 0.026, 0.052)
## How far the knuckle line sits ahead of the wrist. Doubles as the offset a hand
## is set back from whatever it is holding: a weapon anchor marks the point the
## fingers close around, and the length of the palm is this file's business.
const KNUCKLE_REACH := 0.096
const KNUCKLE_SPACING := 0.021

## Per-finger curl multipliers, index to little. Nothing subtle — a stagger just
## stops four identical boxes reading as one slab.
const FINGER_CURL := [1.0, 1.06, 1.0, 0.9]
const HOLD_CURL_TRIGGER := 1.30
const HOLD_CURL_SUPPORT := 1.05
const GRAB_CURL := 1.05
## How much a shot straightens the wrists and tightens the grip on the way back.
const RECOIL_WRIST := -0.30
const RECOIL_CURL := 0.16

## Where the hands sit either side of the edge being held, how far back onto the
## player's side of the face, and how far under the lip — low enough that the
## fingers have to crest it, which is what makes the grip read as a grip.
const GRAB_SPREAD := 0.20
const GRAB_BACK := 0.05
const GRAB_DROP := 0.05
## Forearms drop steeply towards a body still hanging below the ledge. Steeply
## matters: a shallow angle points them at the camera, and a forearm aimed down the
## lens foreshortens into a pole running the height of the screen.
const GRAB_PITCH := 1.05
const GRAB_YAW := 0.22
## Fractions of the pull-up spent slapping onto the ledge and letting go of it.
## The release is well before the end: the eye passes the lip about halfway
## through the climb, and hands that hold on past that are hands behind your back.
const GRAB_REACH_IN := 0.15
const GRAB_RELEASE_AT := 0.50
const GRAB_RELEASE_END := 0.80

## Rest pose, used only when there is no weapon to hang a hand off.
const REST_OFFSET := Vector3(0.24, -0.34, -0.52)
const REST_PITCH := 0.5

var _player: Player
var _weapons: WeaponController
## All indexed by WeaponController.HAND_LEFT / HAND_RIGHT.
var _wrists: Array[Node3D] = []
## Per hand, the four knuckle pivots and the mid joint parented under each, so a
## single curl value bends a whole finger at two places.
var _knuckles: Array = []
var _mid_joints: Array = []
var _thumbs: Array[Node3D] = []
## Shared by both cuffs. Tinted with the equipped weapon's colour, which is the
## only place the hands admit to knowing what they are holding.
var _accent: StandardMaterial3D


func _ready() -> void:
	_player = _find_player()
	_weapons = _find_weapons()
	_accent = _make_material(Color(0.75, 0.16, 0.16), true)
	var glove := _make_material(Color(0.34, 0.31, 0.36), false)
	for side in [WeaponController.HAND_LEFT, WeaponController.HAND_RIGHT]:
		_build_hand(side, glove)

	Events.weapon_equipped.connect(_on_weapon_equipped)
	# The controller equips in its own _ready, which runs before this one when it
	# sits earlier in the tree — so the first colour is pulled rather than awaited.
	if _weapons != null and _weapons.current() != null:
		_apply_accent(_weapons.current().data.view_color)


func _find_player() -> Player:
	var node: Node = get_parent()
	while node != null:
		if node is Player:
			return node as Player
		node = node.get_parent()
	return null


## By type rather than by name, so renaming the rig node does not silently strand
## the hands in their fallback pose.
func _find_weapons() -> WeaponController:
	if get_parent() == null:
		return null
	for sibling in get_parent().get_children():
		if sibling is WeaponController:
			return sibling as WeaponController
	return null


func _on_weapon_equipped(instance: WeaponInstance) -> void:
	if instance != null:
		_apply_accent(instance.data.view_color)


func _apply_accent(color: Color) -> void:
	_accent.albedo_color = color.darkened(0.35)
	_accent.emission = color


# --- Rig --------------------------------------------------------------------

## One hand. `side` picks which way the thumb and the finger order mirror; the
## boxes are symmetrical, so mirroring is done by moving them rather than by
## scaling the hand negatively (which would invert every normal).
func _build_hand(side: int, glove: StandardMaterial3D) -> void:
	var mirror := 1.0 if side == WeaponController.HAND_RIGHT else -1.0
	var wrist := Node3D.new()
	wrist.name = "HandRight" if side == WeaponController.HAND_RIGHT else "HandLeft"
	add_child(wrist)

	_add_box(wrist, FOREARM_SIZE, FOREARM_OFFSET, glove)
	_add_box(wrist, CUFF_SIZE, CUFF_OFFSET, _accent)
	_add_box(wrist, PALM_SIZE, PALM_OFFSET, glove)

	var knuckles: Array[Node3D] = []
	var mids: Array[Node3D] = []
	for finger in 4:
		var knuckle := Node3D.new()
		knuckle.name = "Knuckle%d" % finger
		knuckle.position = Vector3(
			mirror * (finger * KNUCKLE_SPACING - KNUCKLE_SPACING * 1.5),
			-0.002, -KNUCKLE_REACH)
		wrist.add_child(knuckle)
		_add_box(knuckle, FINGER_SIZE, Vector3(0.0, 0.0, -FINGER_SIZE.z * 0.5), glove)

		var mid := Node3D.new()
		mid.name = "Mid"
		mid.position = Vector3(0.0, 0.0, -FINGER_SIZE.z)
		knuckle.add_child(mid)
		_add_box(mid, FINGER_TIP_SIZE, Vector3(0.0, 0.0, -FINGER_TIP_SIZE.z * 0.5), glove)

		knuckles.append(knuckle)
		mids.append(mid)
	_knuckles.append(knuckles)
	_mid_joints.append(mids)

	var thumb := Node3D.new()
	thumb.name = "Thumb"
	thumb.position = Vector3(mirror * -0.040, -0.010, -0.055)
	# Splayed outwards, away from the fingers it is opposing.
	thumb.rotation = Vector3(0.0, mirror * 0.5, 0.0)
	wrist.add_child(thumb)
	_add_box(thumb, THUMB_SIZE, Vector3(0.0, 0.0, -THUMB_SIZE.z * 0.5), glove)
	_thumbs.append(thumb)

	_wrists.append(wrist)


## Both materials carry a little emission. Hands are held palm-down under a
## sky-lit arena, so the surfaces facing the camera are the ones facing away from
## every light — without a floor under the shading they read as black holes.
func _make_material(color: Color, is_accent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5 if is_accent else 0.85
	material.metallic = 0.1
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.22 if is_accent else 0.14
	return material


func _add_box(parent: Node3D, size: Vector3, offset: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = offset
	# View-model geometry: it renders, but nothing should see it in a shadow map.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)


# --- Frame loop -------------------------------------------------------------

func _process(_delta: float) -> void:
	if _wrists.size() < 2:
		return
	var recoil := 0.0
	if _weapons != null:
		recoil = _weapons.recoil_strength()
	var grab := _grab_weight()

	for side in [WeaponController.HAND_LEFT, WeaponController.HAND_RIGHT]:
		var hold_curl := HOLD_CURL_TRIGGER if side == WeaponController.HAND_RIGHT \
				else HOLD_CURL_SUPPORT
		var pose := _hold_pose(side)
		var curl := hold_curl + recoil * RECOIL_CURL
		if grab > 0.0:
			pose = pose.interpolate_with(_grab_pose(side), grab)
			curl = lerpf(curl, GRAB_CURL, grab)
		# A shot flexes the wrist back on top of the kick the anchor already
		# carries, and does nothing at all to a hand that is holding a ledge.
		if recoil > 0.0 and grab < 1.0:
			var flex := recoil * RECOIL_WRIST * (1.0 - grab)
			pose = pose * Transform3D(Basis.from_euler(Vector3(flex, 0.0, 0.0)), Vector3.ZERO)
		_wrists[side].transform = pose
		_set_curl(side, curl)


## Eases in as the hands reach for the ledge and out again as they let go, so
## neither end of a mantle snaps.
func _grab_weight() -> float:
	if _player == null or not _player.is_mantling():
		return 0.0
	var phase := _player.mantle_phase()
	if phase < GRAB_REACH_IN:
		return smoothstep(0.0, 1.0, phase / GRAB_REACH_IN)
	if phase > GRAB_RELEASE_AT:
		var let_go := (phase - GRAB_RELEASE_AT) / (GRAB_RELEASE_END - GRAB_RELEASE_AT)
		return smoothstep(0.0, 1.0, 1.0 - clampf(let_go, 0.0, 1.0))
	return 1.0


## Wherever the weapon says this hand goes, expressed in this node's space. The
## anchor marks the part being held, so the wrist sits a palm's length back down
## the anchor's own +Z — which is what puts the knuckles on the grip rather than
## through it.
func _hold_pose(side: int) -> Transform3D:
	var anchor: Marker3D = null
	if _weapons != null:
		anchor = _weapons.hand_anchor(side)
	if anchor == null:
		var mirror := 1.0 if side == WeaponController.HAND_RIGHT else -1.0
		return Transform3D(Basis.from_euler(Vector3(REST_PITCH, 0.0, 0.0)),
				Vector3(REST_OFFSET.x * mirror, REST_OFFSET.y, REST_OFFSET.z))
	return global_transform.affine_inverse() * anchor.global_transform \
			* Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, KNUCKLE_REACH))


## Both hands on the ledge, built in world space and converted back — the point
## being that the result does not move when the camera does.
func _grab_pose(side: int) -> Transform3D:
	var edge := _player.mantle_grab_point()
	var normal := _player.mantle_grab_normal()
	var into := -normal
	var right := into.cross(Vector3.UP).normalized()
	var mirror := 1.0 if side == WeaponController.HAND_RIGHT else -1.0

	var origin := edge \
			+ right * (GRAB_SPREAD * mirror) \
			+ normal * GRAB_BACK \
			+ Vector3.DOWN * GRAB_DROP
	# Fingers reach along `into` and the forearm runs back the other way, pitched
	# down towards the body and turned slightly inwards.
	var basis := Basis(right, Vector3.UP, -into) \
			* Basis.from_euler(Vector3(GRAB_PITCH, -mirror * GRAB_YAW, 0.0))
	return global_transform.affine_inverse() * Transform3D(basis, origin)


## Curls a whole hand. Fingers bend towards the palm (-Y), which is a negative
## rotation about the knuckle's X, and the mid joint follows a little harder so
## the fingertip ends up pointing back at the wrist rather than straight down.
func _set_curl(side: int, curl: float) -> void:
	var knuckles: Array = _knuckles[side]
	var mids: Array = _mid_joints[side]
	for finger in knuckles.size():
		var amount := curl * float(FINGER_CURL[finger])
		(knuckles[finger] as Node3D).rotation.x = -amount
		(mids[finger] as Node3D).rotation.x = -amount * 0.9
	(_thumbs[side] as Node3D).rotation.x = -curl * 0.45
