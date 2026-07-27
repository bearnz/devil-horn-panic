@tool
class_name PlayerBody
extends Node3D
## The player's body: a procedural humanoid built out of boxes, cut to standard
## proportions and dressed in the same glove, cuff and trim materials as the hands
## you look at — because the hands on the end of its arms are literally those
## hands, the same `HandRig`.
##
## What it is for, in order:
##
## **A shadow.** The player throws one on every wall in the arena. A capsule's is
## a giveaway; a humanoid's sells the character before any camera ever sees it.
##
## **Something to look down at.** The legs render normally, so a glance at your
## feet finds legs. Everything from the hips up is switched to shadows-only, and
## the cut is there rather than higher for a reason worth keeping: the eye rides
## at 1.62 on the body's own centreline, so looking straight down it is the
## *pelvis* that fills the screen — a flat unlit plate that also hides the legs
## behind it, which is exactly backwards. `first_person = false` puts all of it
## back, which is what a third-person shot, a death cam or a dev capture wants.
##
## The rig is a joint hierarchy of `Node3D` pivots with a box hung off each, so
## posing is rotation rather than geometry. There is no IK: the hips are placed at
## whatever height the leg angles put them, which keeps the soles on flat ground
## by construction, and a swinging foot may still clip a slope. Feet that follow
## real ground want raycasts, and that is a job for the day levels stop being
## arenas.
##
## Poses run in `_process` for the same reason `ViewHands` does — see the note in
## that file about the idle loop and the physics one disagreeing.
##
## **It builds in the editor too.** `@tool` is what puts a body in the 3D viewport
## of `player.tscn` and of any scene the player is instanced into, so proportions
## and materials can be judged without launching the game. The editor path stops at
## geometry plus one standing pose: there is no player to read a stance off, and the
## autoloads this file talks to (`Events`, `GameState`) are not instantiated in the
## editor, so touching them there is a null. The boxes are added without an `owner`,
## which is what keeps them out of the saved .tscn — this node is empty on disk and
## always will be.

# --- Skeleton ---------------------------------------------------------------
# Heights above the feet, standing. Standard proportions for the 1.8m body
# `Player.STAND_HEIGHT` describes: hips at 0.53 of height, shoulders at 0.79, a
# head a touch over a seventh of it, and an arm span that comes back to the
# height. The eye height the camera actually uses, 1.62, lands just above the
# middle of this head — which is where eyes go, and a good sign the numbers are
# honest.
const ANKLE_Y := 0.09
const KNEE_Y := 0.51
const HIP_Y := 0.95
const SPINE_Y := 1.03
const CHEST_Y := 1.19
const SHOULDER_Y := 1.42
const NECK_Y := 1.46
const HEAD_Y := 1.54
const HEAD_TOP := 1.80

const THIGH_LENGTH := HIP_Y - KNEE_Y
const SHIN_LENGTH := KNEE_Y - ANKLE_Y
const UPPER_ARM_LENGTH := 0.30
const FOREARM_LENGTH := 0.26
## Half the gap between the two legs, and between the two shoulders.
const HIP_SPLIT := 0.11
const SHOULDER_SPLIT := 0.20

const HEAD_SIZE := Vector3(0.20, HEAD_TOP - HEAD_Y, 0.21)
const VISOR_SIZE := Vector3(0.17, 0.045, 0.215)
## Short and thick. A narrow neck at this scale reads as a head on a stick.
const NECK_SIZE := Vector3(0.13, 0.08, 0.12)
const CHEST_SIZE := Vector3(0.42, 0.28, 0.22)
const COLLAR_SIZE := Vector3(0.30, 0.04, 0.235)
const ABDOMEN_SIZE := Vector3(0.34, 0.16, 0.20)
const PELVIS_SIZE := Vector3(0.36, 0.16, 0.22)
const BELT_SIZE := Vector3(0.37, 0.05, 0.235)
const UPPER_ARM_SIZE := Vector3(0.11, 0.30, 0.12)
const FOREARM_SIZE := Vector3(0.10, 0.26, 0.10)
const THIGH_SIZE := Vector3(0.14, 0.44, 0.17)
const SHIN_SIZE := Vector3(0.13, 0.42, 0.14)
const FOOT_SIZE := Vector3(0.13, 0.09, 0.28)
## How far the foot sits ahead of the ankle it hangs off: a heel behind, most of
## the boot in front.
const FOOT_FORWARD := 0.06
## The body sits centred on the capsule it collides with, which is where a body
## belongs. Getting the eye out in front of the chest is `Player.EYE_FORWARD`'s
## job — moving the camera is the honest version of that, and it means the shadow
## is not thrown from a torso shoved backwards out of its own collider.
##
## Squatting is the exception: the hips slide back by this much at full crouch.
## That is what a squat does — the weight goes back over the heels, or you fall
## forward — and it is also the only way the eye ever gets in front of the knees.
## Swing the knees forward with the hips left where they are and the camera ends
## up directly above the middle of its own thighs, looking through them.
const CROUCH_SET_BACK := 0.18

## A shade under the glove, so gloves and boots read as separate pieces of kit
## against the suit rather than as one silhouette.
const SUIT_COLOR := Color(0.27, 0.25, 0.30)
const BOOT_COLOR := Color(0.21, 0.20, 0.24)

# --- Poses ------------------------------------------------------------------
## Full crouch: a squat, with the thighs at roughly 45° and the shins folded back
## under them. This is the pose the first-person camera actually looks at, and 45°
## is what makes it read as a pair of knees. Flatter thighs do get the hips lower —
## they are what a deep squat really does — but from above they are a shelf across
## the screen with no knee in them anywhere, which is the thing to avoid.
##
## Geometry worth knowing before retuning: with the thighs at 45° the hips cannot
## get much below 0.6 without the shins going horizontal, which is kneeling rather
## than squatting. Depth and knee angle trade against each other directly.
const CROUCH_THIGH := 0.80
const CROUCH_KNEE := -1.80
## A squat folds the chest forward over the knees — more than the old sit-down
## pose needed, and it is what buys back some of the height the shallower knees
## cost. Past about here it reads as a face-plant rather than a crouch.
const CROUCH_LEAN := 0.70
## Legs out in front, chest tipped back — a slide is feet first.
const SLIDE_THIGH := 1.25
const SLIDE_KNEE := -0.60
const SLIDE_LEAN := -0.45
## Airborne tuck, folded away again by a crouch that is already folded.
const AIR_THIGH := 0.30
const AIR_KNEE := -0.55

## Metres of ground per full two-step cycle, and the ceiling on how many cycles a
## second the legs will run at. Sprint speeds in this game are frankly inhuman;
## without the cap the legs blur.
const STRIDE_LENGTH := 2.4
const STRIDE_MAX_RATE := 2.6
## Peak hip swing, and the vertical bob that comes with it.
const STEP_SWING := 0.55
const STEP_KNEE_BEND := 1.6
const STEP_BOB := 0.035
## The trailing arm counter-swings, but only a little: these arms are holding
## something.
const ARM_SWING := 0.24

## Carry pose. Both arms come forward and bend, the off hand crossing further in,
## which is roughly where the view model would be if the body could see it. It
## cannot — the weapon lives in view space, in front of a camera inside this
## head — so this is a pose that reads as "holding a rifle" rather than a rig
## aimed at anything.
const CARRY_SHOULDER_TRIGGER := 0.40
const CARRY_SHOULDER_SUPPORT := 0.58
const CARRY_SHOULDER_YAW := 0.22
const CARRY_SHOULDER_ROLL := 0.12
## Well past a right angle: the elbows carry the weight, and a shallower bend
## leaves both hands clasped somewhere around the navel.
const CARRY_ELBOW := 1.40
const CARRY_CURL := 1.15
## Both arms overhead while the hands are on a ledge. The pair the player is
## watching are `ViewHands`; this is what the shadow does at the same moment.
const MANTLE_SHOULDER := 2.45
const MANTLE_ELBOW := 0.45
const MANTLE_CURL := 1.05

## How far the head will follow the camera before it stops, so a full look up or
## down bends the neck rather than snapping it round.
const HEAD_PITCH_LIMIT := 0.7

const SIDE_LEFT := 0
const SIDE_RIGHT := 1

## Off by default the moment anything wants to see the whole model — a
## third-person camera, a dev capture. On, the parts the first-person camera sits
## inside are demoted to shadows-only.
@export var first_person: bool = true: set = set_first_person

var _player: Player
var _hips: Node3D
var _spine: Node3D
var _chest: Node3D
var _head: Node3D
## All the per-side pivots, indexed by SIDE_LEFT / SIDE_RIGHT.
var _hip_joints: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _ankles: Array[Node3D] = []
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _hands: Array[HandRig] = []
## Everything the first-person camera is inside or behind.
var _hidden_up_close: Array[MeshInstance3D] = []
## Shared by every piece of trim, and retinted with the equipped weapon exactly
## as the cuffs on the view hands are.
var _accent: StandardMaterial3D
var _stride_phase: float = 0.0
## Forward lean of the chest, as posed. Kept so the head can undo it.
var _lean: float = 0.0
## Eased rather than read raw: a slide starts and stops on a single frame, and a
## body that changed pose that fast would pop.
var _slide: float = 0.0


func _ready() -> void:
	_accent = HandRig.make_material(HandRig.ACCENT_COLOR, true)
	_build()
	_apply_visibility()
	if Engine.is_editor_hint():
		# Nothing below this line exists in the editor: no player, no autoloads, no
		# frame loop. One standing pose and the viewport has something to look at.
		_pose_arms(0.0, 0.0)
		return

	_player = _find_player()
	Events.weapon_equipped.connect(_on_weapon_equipped)
	# The rig equips in its own _ready, which has already run and emitted by the
	# time this one does — and the player's `weapons` reference is an @onready
	# that is not assigned yet either. So the first colour is hunted down rather
	# than awaited or read off the player.
	var rig := _find_weapons()
	if rig != null and rig.current() != null:
		_apply_accent(rig.current().data.view_color)


## World height of the crown, as posed. Measured off the head pivot rather than
## returned from a constant, so a crouch that failed to fold the body shows up
## here instead of being asserted away.
func head_top() -> float:
	if _head == null:
		return 0.0
	return _head.global_position.y + HEAD_SIZE.y


## World height of the lower of the two soles. Level ground puts this on the
## floor; anything else means the legs have been posed out from under the body.
func sole_height() -> float:
	if _ankles.size() < 2:
		return 0.0
	return minf(_ankles[SIDE_LEFT].global_position.y,
			_ankles[SIDE_RIGHT].global_position.y) - FOOT_SIZE.y


func hand(side: int) -> HandRig:
	if side < 0 or side >= _hands.size():
		return null
	return _hands[side]


## Whether the camera is inside this body. See the class comment: on, the head,
## neck, chest and arms cast shadows but do not render.
func set_first_person(value: bool) -> void:
	first_person = value
	_apply_visibility()


func _apply_visibility() -> void:
	# The editor is never inside this head, and a shadows-only torso in a viewport
	# with no shadow to catch it is an invisible one. Show all of it there.
	var up_close := first_person and not Engine.is_editor_hint()
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if up_close \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for mesh in _hidden_up_close:
		mesh.cast_shadow = mode
	for glove in _hands:
		glove.set_shadow_mode(mode)


func _find_player() -> Player:
	var node: Node = get_parent()
	while node != null:
		if node is Player:
			return node as Player
		node = node.get_parent()
	return null


## By type, anywhere under the player — the rig lives several nodes down under the
## camera, and this node has no business knowing the shape of that branch.
func _find_weapons() -> WeaponController:
	if _player == null:
		return null
	for node in _player.find_children("*", "Node3D", true, false):
		if node is WeaponController:
			return node as WeaponController
	return null


func _on_weapon_equipped(instance: WeaponInstance) -> void:
	if instance != null:
		_apply_accent(instance.data.view_color)


func _apply_accent(color: Color) -> void:
	_accent.albedo_color = color.darkened(0.35)
	_accent.emission = color


# --- Rig --------------------------------------------------------------------

func _build() -> void:
	# Runs more than once in the editor — every script reload re-enters the tree —
	# so it starts by throwing away whatever the last one left behind.
	for child in get_children():
		child.free()
	_hip_joints.clear()
	_knees.clear()
	_ankles.clear()
	_shoulders.clear()
	_elbows.clear()
	_hands.clear()
	_hidden_up_close.clear()

	var suit := HandRig.make_material(SUIT_COLOR, false)
	# A shade more lift than the gloves get. The faces the player looks down on are
	# the front of the torso and the tops of the thighs, and both of those point
	# away from a sun that is somewhere above and behind the head.
	suit.emission_energy_multiplier = 0.20
	var glove := HandRig.make_material(HandRig.GLOVE_COLOR, false)
	var boot := HandRig.make_material(BOOT_COLOR, false)

	_hips = _joint(self, "Hips", Vector3(0.0, HIP_Y, 0.0))
	_box(_hips, "Pelvis", PELVIS_SIZE, Vector3.ZERO, suit, true)
	_box(_hips, "Belt", BELT_SIZE, Vector3(0.0, 0.055, 0.0), _accent, true)

	_spine = _joint(_hips, "Spine", Vector3(0.0, SPINE_Y - HIP_Y, 0.0))
	_box(_spine, "Abdomen", ABDOMEN_SIZE, Vector3(0.0, ABDOMEN_SIZE.y * 0.5, 0.0), suit, true)

	# From the chest up the camera is either inside the box or right behind it.
	_chest = _joint(_spine, "Chest", Vector3(0.0, CHEST_Y - SPINE_Y, 0.0))
	_box(_chest, "Torso", CHEST_SIZE, Vector3(0.0, CHEST_SIZE.y * 0.5, 0.0), suit, true)
	_box(_chest, "Collar", COLLAR_SIZE, Vector3(0.0, CHEST_SIZE.y - 0.02, 0.0), _accent, true)
	var neck := _joint(_chest, "Neck", Vector3(0.0, NECK_Y - CHEST_Y, 0.0))
	_box(neck, "NeckMesh", NECK_SIZE, Vector3(0.0, NECK_SIZE.y * 0.5, 0.0), suit, true)

	_head = _joint(_chest, "Head", Vector3(0.0, HEAD_Y - CHEST_Y, 0.0))
	_box(_head, "Skull", HEAD_SIZE, Vector3(0.0, HEAD_SIZE.y * 0.5, 0.0), suit, true)
	# A visor across the face, so the head has a front. Same trim as the cuffs,
	# proud of the skull by a millimetre to keep the two faces off each other.
	_box(_head, "Visor", VISOR_SIZE, Vector3(0.0, HEAD_SIZE.y * 0.45, -0.001), _accent, true)

	for side in [SIDE_LEFT, SIDE_RIGHT]:
		_build_arm(side, suit, glove)
		_build_leg(side, suit, boot)


func _build_arm(side: int, suit: Material, glove: Material) -> void:
	var mirror := _mirror(side)
	var shoulder := _joint(_chest, "Shoulder%s" % _side_name(side),
			Vector3(mirror * SHOULDER_SPLIT, SHOULDER_Y - CHEST_Y, 0.0))
	_box(shoulder, "UpperArm", UPPER_ARM_SIZE,
			Vector3(0.0, -UPPER_ARM_LENGTH * 0.5, 0.0), suit, true)

	var elbow := _joint(shoulder, "Elbow", Vector3(0.0, -UPPER_ARM_LENGTH, 0.0))
	_box(elbow, "Forearm", FOREARM_SIZE, Vector3(0.0, -FOREARM_LENGTH * 0.5, 0.0), suit, true)

	# No forearm stub on this one — there is a real arm above it. The rig is built
	# with its fingers along -Z and its own forearm along +Z, so a quarter turn
	# back about X points the fingers down the arm and leaves the palm facing the
	# body, which is how a hand hangs.
	var glove_rig := HandRig.build(mirror, glove, _accent, false)
	glove_rig.name = "Hand"
	glove_rig.position = Vector3(0.0, -FOREARM_LENGTH, 0.0)
	glove_rig.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	elbow.add_child(glove_rig)

	_shoulders.append(shoulder)
	_elbows.append(elbow)
	_hands.append(glove_rig)


func _build_leg(side: int, suit: Material, boot: Material) -> void:
	var hip := _joint(_hips, "Hip%s" % _side_name(side),
			Vector3(_mirror(side) * HIP_SPLIT, 0.0, 0.0))
	_box(hip, "Thigh", THIGH_SIZE, Vector3(0.0, -THIGH_LENGTH * 0.5, 0.0), suit, false)

	var knee := _joint(hip, "Knee", Vector3(0.0, -THIGH_LENGTH, 0.0))
	_box(knee, "Shin", SHIN_SIZE, Vector3(0.0, -SHIN_LENGTH * 0.5, 0.0), suit, false)
	# The one piece of trim that is here for the first-person camera rather than
	# for the silhouette. Looking straight down, the thighs are edge-on, unlit and
	# touching: without two bright marks in the middle of them the whole lower body
	# reads as one dark plate rather than as a pair of legs.
	_box(knee, "KneePad", Vector3(SHIN_SIZE.x + 0.012, 0.055, SHIN_SIZE.z + 0.012),
			Vector3(0.0, -0.035, 0.0), _accent, false)

	var ankle := _joint(knee, "Ankle", Vector3(0.0, -SHIN_LENGTH, 0.0))
	_box(ankle, "Foot", FOOT_SIZE, Vector3(0.0, -FOOT_SIZE.y * 0.5, -FOOT_FORWARD), boot, false)
	_box(ankle, "Toe", Vector3(FOOT_SIZE.x, 0.035, 0.05),
			Vector3(0.0, -FOOT_SIZE.y + 0.02, -FOOT_FORWARD - FOOT_SIZE.z * 0.5 + 0.025),
			_accent, false)

	_hip_joints.append(hip)
	_knees.append(knee)
	_ankles.append(ankle)


func _joint(parent: Node3D, joint_name: String, offset: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = joint_name
	node.position = offset
	parent.add_child(node)
	return node


func _box(parent: Node3D, box_name: String, size: Vector3, offset: Vector3,
		material: Material, up_close: bool) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = box_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = offset
	parent.add_child(mesh)
	if up_close:
		_hidden_up_close.append(mesh)


func _mirror(side: int) -> float:
	return 1.0 if side == SIDE_RIGHT else -1.0


func _side_name(side: int) -> String:
	return "Right" if side == SIDE_RIGHT else "Left"


# --- Frame loop -------------------------------------------------------------

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _player == null or _hips == null:
		return

	var grounded := _player.is_on_floor()
	var planar := Vector2(_player.velocity.x, _player.velocity.z).length()
	_slide = move_toward(_slide, 1.0 if _player.is_sliding() else 0.0, delta * 7.0)
	# Only ground contact walks the cycle on; in the air the legs hold whatever
	# step they left with rather than pedalling.
	var pace := clampf(planar / GameState.stat("move_speed"), 0.0, 1.4)
	if grounded and not _player.is_sliding():
		_stride_phase = wrapf(_stride_phase
				+ minf(planar / STRIDE_LENGTH, STRIDE_MAX_RATE) * TAU * delta, 0.0, TAU)
	else:
		pace = 0.0

	_pose_legs(grounded, pace)
	_pose_arms(pace, _player.hands.grab_weight() if _player.hands != null else 0.0)
	_pose_head()


## Legs, hips and spine together, because the height of the hips is a consequence
## of the leg angles rather than a number of its own — bend the knees and the body
## comes down with them, feet still on the floor.
func _pose_legs(grounded: bool, pace: float) -> void:
	var crouch := _player.crouch_amount()
	var thigh := CROUCH_THIGH * crouch
	var knee := CROUCH_KNEE * crouch
	var lean := CROUCH_LEAN * crouch
	if not grounded:
		thigh += AIR_THIGH * (1.0 - crouch)
		knee += AIR_KNEE * (1.0 - crouch)
	thigh = lerpf(thigh, SLIDE_THIGH, _slide)
	knee = lerpf(knee, SLIDE_KNEE, _slide)
	lean = lerpf(lean, SLIDE_LEAN, _slide)

	_hips.position.y = ANKLE_Y \
			+ THIGH_LENGTH * cos(thigh) + SHIN_LENGTH * cos(thigh + knee) \
			+ sin(_stride_phase * 2.0) * STEP_BOB * pace
	_hips.position.z = CROUCH_SET_BACK * crouch
	# Negated, and this is the one sign in the file worth stopping on: everything
	# below the hips hangs down its pivot's -Y, so a positive pitch swings it
	# forward, and everything above stands up +Y, where the same positive pitch
	# tips it back. Lean is quoted forward-positive at both ends.
	_lean = lean
	_spine.rotation.x = -lean

	for side in [SIDE_LEFT, SIDE_RIGHT]:
		var step := _step(side)
		# The trailing leg is the one that has to fold, or the foot ploughs
		# through the ground behind it.
		var trail := maxf(0.0, -step)
		var hip_pitch := thigh + step * STEP_SWING * pace
		var knee_bend := knee - trail * STEP_KNEE_BEND * STEP_SWING * pace
		_hip_joints[side].rotation.x = hip_pitch
		_knees[side].rotation.x = knee_bend
		# Cancels everything above it so the sole stays flat to the world.
		_ankles[side].rotation.x = -(hip_pitch + knee_bend)


## Arms hold the carry pose, counter-swing against the leg on the same side, and
## go up when the hands take a ledge. `grab` is passed in rather than read off the
## player, because this is also the one pose the editor build can strike.
func _pose_arms(pace: float, grab: float) -> void:
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		var mirror := _mirror(side)
		var carry := CARRY_SHOULDER_TRIGGER if side == SIDE_RIGHT else CARRY_SHOULDER_SUPPORT
		var pitch := carry - _step(side) * ARM_SWING * pace
		_shoulders[side].rotation = Vector3(
				lerpf(pitch, MANTLE_SHOULDER, grab),
				mirror * lerpf(CARRY_SHOULDER_YAW, 0.0, grab),
				mirror * CARRY_SHOULDER_ROLL)
		_elbows[side].rotation.x = lerpf(CARRY_ELBOW, MANTLE_ELBOW, grab)
		_hands[side].set_curl(lerpf(CARRY_CURL, MANTLE_CURL, grab))


## The head follows the camera it is wrapped around, clamped so a full look up or
## down bends the neck instead of spinning the skull. Read off the camera's own
## basis rather than the player's pitch, so recoil and the mantle look-down carry
## through without this having to know about either.
func _pose_head() -> void:
	if _player.camera == null:
		return
	var look := -_player.camera.global_transform.basis.z
	var pitch := asin(clampf(look.y, -1.0, 1.0))
	# Plus whatever the chest is leaning, since this hangs off it: a crouch folds
	# the torso forward and the head should keep looking where the player is,
	# not at its own knees.
	_head.rotation.x = clampf(pitch, -HEAD_PITCH_LIMIT, HEAD_PITCH_LIMIT) + _lean


## Where this side is in the walk cycle, -1 to 1. The two legs are half a cycle
## apart, which is what makes it a walk rather than a hop.
func _step(side: int) -> float:
	return sin(_stride_phase + (PI if side == SIDE_LEFT else 0.0))
