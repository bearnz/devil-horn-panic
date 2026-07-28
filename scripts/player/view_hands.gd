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

## The hands themselves are `HandRig` — geometry, materials and finger curl all
## live there, because `PlayerBody` puts the same pair on the end of the player's
## real arms. What is left in this file is where a first-person hand goes and what
## it is doing, which is the part a body has no use for.
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
## Indexed by WeaponController.HAND_LEFT / HAND_RIGHT.
var _hands: Array[HandRig] = []
## Shared by both cuffs. Tinted with the equipped weapon's colour, which is the
## only place the hands admit to knowing what they are holding.
var _accent: StandardMaterial3D
var _grab_applied: float = 0.0
## Where each hand was last actually put, in world space. See `hand_position()`.
var _placed: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


func _ready() -> void:
	_player = _find_player()
	_weapons = _find_weapons()
	_accent = HandRig.make_material(HandRig.ACCENT_COLOR, true)
	var glove := HandRig.make_material(HandRig.GLOVE_COLOR, false)
	for side in [WeaponController.HAND_LEFT, WeaponController.HAND_RIGHT]:
		_build_hand(side, glove)

	Events.weapon_equipped.connect(_on_weapon_equipped)
	# The controller equips in its own _ready, which runs before this one when it
	# sits earlier in the tree — so the first colour is pulled rather than awaited.
	if _weapons != null and _weapons.current() != null:
		_apply_accent(_weapons.current().data.view_color)


## How much of the ledge-grab pose the hands are in, 0 to 1 — the weight actually
## applied on the last frame rather than a fresh reading of the mantle. Those two
## differ by however many physics steps have run since, which is exactly the sort
## of thing that makes an animation look right and a test disagree.
func grab_weight() -> float:
	return _grab_applied


## Where a wrist was put, in world space, as of the last pose. ZERO before the rig
## is built.
##
## Deliberately the recorded placement rather than a live `global_position`: poses
## are set on the idle loop and the body moves on the physics one, so anything
## reading between the two gets this node's new transform combined with a wrist
## offset built for the old one — a hand that is nailed to a ledge appears to
## slide off it. This is the value that was drawn.
func hand_position(side: int) -> Vector3:
	if side < 0 or side >= _placed.size():
		return Vector3.ZERO
	return _placed[side]


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

## One hand, with the forearm stub kept: there is no arm behind a view-model hand
## for it to be the end of.
func _build_hand(side: int, glove: StandardMaterial3D) -> void:
	var mirror := 1.0 if side == WeaponController.HAND_RIGHT else -1.0
	var hand := HandRig.build(mirror, glove, _accent)
	hand.name = "HandRight" if side == WeaponController.HAND_RIGHT else "HandLeft"
	# View-model geometry: it renders, but nothing should see it in a shadow map.
	# The body's copy of this rig is the one that casts the player's shadow.
	hand.set_shadow_mode(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	add_child(hand)
	_hands.append(hand)


# --- Frame loop -------------------------------------------------------------

func _process(_delta: float) -> void:
	if _hands.size() < 2:
		return
	var recoil := 0.0
	if _weapons != null:
		recoil = _weapons.recoil_strength()
	var grab := _grab_weight()
	_grab_applied = grab

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
		_hands[side].transform = pose
		_placed[side] = _hands[side].global_position
		_hands[side].set_curl(curl)


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
			* Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, HandRig.KNUCKLE_REACH))


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
