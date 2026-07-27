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

## A dash is a fling, not a sprint. The body is thrown along the dash and the
## legs are left behind it: hips swung back past where any stride would take
## them, knees folded so the heels trail, chest out over the top. These are
## quoted for a dash straight ahead — a backwards one is the same numbers
## negated, so the legs end up out in front, and a sideways one rolls the pair
## below about Z instead of pitching.
const DASH_TRAIL := 0.85
const DASH_KNEE := -0.75
const DASH_LEAN := 0.55
const DASH_SIDE_TRAIL := 0.55
const DASH_SIDE_LEAN := 0.35
## The two legs trail by different amounts, or the pair reads as one slab
## swinging off the hips.
const DASH_STAGGER := 0.22
## What is left of the ankle's keep-the-sole-flat correction at full dash. A foot
## in flight points where its shin points; a sole held level under a leg swung
## out behind the hips is a boot walking on air.
const DASH_ANKLE_FOLLOW := 0.2
## How fast the pose arrives. Quicker than the slide's, because `Player.DASH_TIME`
## is a third of a second and anything slower would be an ease in, an ease out,
## and no dash in between.
const DASH_BLEND_RATE := 10.0

## Metres of ground per full two-step cycle, and the ceiling on how many cycles a
## second the legs will run at. Sprint speeds in this game are frankly inhuman;
## without the cap the legs blur.
const STRIDE_LENGTH := 2.4
const STRIDE_MAX_RATE := 2.6
## Peak hip swing, and the vertical bob that comes with it.
const STEP_SWING := 0.55
const STEP_KNEE_BEND := 1.6
const STEP_BOB := 0.035

## How the hand rig sits on the end of a forearm with nothing to hold. The rig is
## built with its fingers along -Z and its own forearm along +Z, so a quarter turn
## back about X points the fingers down the arm and leaves the palm facing the body,
## which is how a hand hangs. Also what both hands do on a ledge.
const HAND_HANG_EULER := Vector3(-PI * 0.5, 0.0, 0.0)

## The carry pose is authored as *where the weapon goes*, in the chest's own frame,
## and the arms that reach it are solved — see `_solve_arm`. The other way round is
## what this file used to do, and joint angles picked by hand multiply out to
## whatever heading and roll they multiply out to: the pistol came out canted twenty
## degrees off the vertical, which is nothing like the upright hold the player sees
## in front of the camera.
##
## Neither number is decoration. -Z is where the player faces, so the weapon is
## upright and level with a few degrees of muzzle-down, which reads as carried
## rather than aimed; and it sits out on the shooting side and clear in front of the
## chest, because a weapon tucked against a 0.21 half-chest is one the camera behind
## the player cannot see past its owner.
const CARRY_WEAPON_POS := Vector3(0.22, 0.03, -0.22)
const CARRY_WEAPON_EULER := Vector3(-0.14, 0.0, 0.0)
## Rotation of each arm about its own shoulder-to-wrist line — the one thing a wrist
## position does not pin down. It swings the elbow without moving the hand, which is
## the difference between an elbow tucked into the ribs and one out in the air.
const CARRY_SWIVEL_TRIGGER := 0.0
const CARRY_SWIVEL_SUPPORT := 0.0
## Grip strength, matching the pair in front of the camera: the shooting hand closes
## hard on a grip post, the support hand rests on something wider.
const HOLD_CURL_TRIGGER := 1.30
const HOLD_CURL_SUPPORT := 1.05
## How far the off hand may slide back along the weapon, towards the receiver, to
## get within reach of the arm that has to hold it. A carbine's foregrip sits most of
## a metre out from the shoulder reaching for it, which is further than an arm goes;
## a real shooter's answer is to hold it further back, so it is this one's too.
## Capped against the barrel's own length, so a short weapon cannot end up with a
## hand slid off the back of it.
const SUPPORT_SLIDE_MAX := 0.36
const SUPPORT_SLIDE_STEP := 0.01

## Empty hands: a generic braced carry, for the editor build and for the frames
## before a weapon is equipped. There is no `GameState` in the editor to have
## equipped one, and nothing to solve an arm against if there were.
const EMPTY_SHOULDER := 0.58
const EMPTY_YAW := 0.22
const EMPTY_ROLL := 0.12
const EMPTY_ELBOW := 1.40
const EMPTY_CURL := 1.15

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
## The weapon in the right fist: `WeaponController`'s geometry built a second time
## and parented to the hand, because the view model is a child of the camera and
## follows that rather than the body. Rebuilt on every weapon switch.
var _weapon_model: Node3D
## The carry pose, solved: shoulder orientation, elbow bend, wrist orientation and
## grip, per side, each in the frame its own joint lives in. Constant for a given
## weapon — the target is fixed in the chest's frame and arms do not change length —
## so this is worked out on a weapon switch rather than every frame.
var _carry_shoulder: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
var _carry_elbow: Array[float] = [0.0, 0.0]
var _carry_wrist: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
var _carry_curl: Array[float] = [0.0, 0.0]
var _stride_phase: float = 0.0
## Forward lean of the chest, as posed. Kept so the head can undo it.
var _lean: float = 0.0
## Eased rather than read raw: a slide starts and stops on a single frame, and a
## body that changed pose that fast would pop.
var _slide: float = 0.0
## Same easing for the dash, plus the heading it was struck for, held in the
## body's own frame. Latched rather than read live, because the pose outlives the
## dash by the few frames it takes to ease out and the player has cleared the
## direction by then.
var _dash: float = 0.0
var _dash_forward: float = 0.0
var _dash_side: float = 0.0


func _ready() -> void:
	_accent = HandRig.make_material(HandRig.ACCENT_COLOR, true)
	_build()
	_apply_visibility()
	_solve_carry(null)
	if Engine.is_editor_hint():
		# Nothing below this line exists in the editor: no player, no autoloads, no
		# frame loop. One standing pose and the viewport has something to look at.
		_pose_arms(0.0)
		return

	_player = _find_player()
	Events.weapon_equipped.connect(_on_weapon_equipped)
	# The rig equips in its own _ready, which has already run and emitted by the
	# time this one does — and the player's `weapons` reference is an @onready
	# that is not assigned yet either. So the first colour is hunted down rather
	# than awaited or read off the player.
	var rig := _find_weapons()
	if rig != null and rig.current() != null:
		_on_weapon_equipped(rig.current())


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


## The weapon in the body's fist, or null before one is equipped. Exposed for the
## dev tools: where it points and whether anything can see it are consequences of
## five arm angles and a grip transform, and nothing else in the game would notice
## those drifting.
func weapon_model() -> Node3D:
	return _weapon_model


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
	var mode := _shadow_mode()
	for mesh in _hidden_up_close:
		mesh.cast_shadow = mode
	for glove in _hands:
		glove.set_shadow_mode(mode)
	_apply_weapon_visibility()


## How everything the first-person camera sits inside or behind is drawn.
func _shadow_mode() -> GeometryInstance3D.ShadowCastingSetting:
	# The editor is never inside this head, and a shadows-only torso in a viewport
	# with no shadow to catch it is an invisible one. Show all of it there.
	var up_close := first_person and not Engine.is_editor_hint()
	return GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if up_close \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## The weapon in the fist follows the arm holding it: out of the first-person frame,
## because the view model is the one the player is meant to see from in there and
## two rifles a foot apart is worse than either. Kept separate from the lists above
## because it is rebuilt on every weapon switch and they are built once.
func _apply_weapon_visibility() -> void:
	if _weapon_model == null:
		return
	var mode := _shadow_mode()
	for mesh: Node in _weapon_model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = mode


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
		_build_weapon(instance.data)


## Puts the equipped weapon in the right fist. The pose is not authored here: it is
## `WeaponController`'s grip anchor run backwards, so this hand holds the weapon
## exactly where the pair on the screen hold it and a weapon switch moves it for
## the same reason theirs moves.
##
## The weapon rides the hand rather than the other way round, which is why the arm
## has to be solved for it and not the reverse — see `_solve_carry`.
func _build_weapon(data: WeaponData) -> void:
	if _weapon_model != null:
		_weapon_model.queue_free()
		_weapon_model = null
	if _hands.size() <= SIDE_RIGHT:
		return
	_weapon_model = WeaponController.build_model(data, true)
	_hands[SIDE_RIGHT].add_child(_weapon_model)
	_weapon_model.transform = WeaponController.model_in_grip_frame(data)
	_apply_weapon_visibility()
	_solve_carry(data)


# --- Carry pose -------------------------------------------------------------

## Works out where both arms go for the weapon they are about to hold, or for empty
## hands when there is none.
##
## The weapon is placed first, at `CARRY_WEAPON_POS` in the chest's frame, and each
## hand is sent to the part of it that hand holds — the same two anchors `ViewHands`
## puts the first-person pair on. That ordering is the point: the thing that has to
## look right is the weapon, so the weapon is what gets authored.
func _solve_carry(data: WeaponData) -> void:
	if _shoulders.size() <= SIDE_RIGHT:
		return
	if data == null:
		for side in [SIDE_LEFT, SIDE_RIGHT]:
			_carry_shoulder[side] = Basis.from_euler(Vector3(EMPTY_SHOULDER,
					_mirror(side) * EMPTY_YAW, _mirror(side) * EMPTY_ROLL))
			_carry_elbow[side] = EMPTY_ELBOW
			_carry_wrist[side] = Basis.from_euler(HAND_HANG_EULER)
			_carry_curl[side] = EMPTY_CURL
		return

	var weapon := Transform3D(Basis.from_euler(CARRY_WEAPON_EULER), CARRY_WEAPON_POS)
	_solve_arm(SIDE_RIGHT, weapon * WeaponController.wrist_in_model_frame(
			data, WeaponController.HAND_RIGHT), CARRY_SWIVEL_TRIGGER)
	_solve_arm(SIDE_LEFT, _support_target(data, weapon), CARRY_SWIVEL_SUPPORT)
	_carry_curl[SIDE_RIGHT] = HOLD_CURL_TRIGGER
	_carry_curl[SIDE_LEFT] = HOLD_CURL_SUPPORT


## Where the off hand goes: the weapon's own support anchor, slid back along the
## weapon towards the receiver until the arm can actually reach it. Sliding rather
## than stretching matters — an arm at full extension still misses by however far it
## was short, and a hand hanging a few centimetres off a foregrip reads worse than a
## hand holding a foregrip further back than it might have.
func _support_target(data: WeaponData, weapon: Transform3D) -> Transform3D:
	var wrist := WeaponController.wrist_in_model_frame(data, WeaponController.HAND_LEFT)
	var shoulder := _shoulders[SIDE_LEFT].position
	var reach := UPPER_ARM_LENGTH + FOREARM_LENGTH - 0.02
	var limit := minf(SUPPORT_SLIDE_MAX, data.barrel_size.z * 0.8)
	var slide := 0.0
	var target := weapon * wrist
	while slide < limit and target.origin.distance_to(shoulder) > reach:
		slide += SUPPORT_SLIDE_STEP
		# +Z runs back down the weapon towards the receiver, because -Z is the way
		# the barrel points and the way the fingers reach.
		target = weapon * Transform3D(wrist.basis, wrist.origin + Vector3(0.0, 0.0, slide))
	return target


## Two-bone IK. Sets the shoulder orientation and elbow bend that land this side's
## wrist on `target`, and gives the wrist itself whatever is left over.
##
## `target` is in the chest's frame, which is the frame the shoulders hang in. There
## are four joint angles between chest and wrist — three at the shoulder, one at the
## elbow — against a target with six numbers in it, so the wrist takes up the
## difference. That is what a wrist is for, and it is why the old fixed one could not
## hold a weapon anywhere in particular: with the hand welded to the forearm, every
## angle that brought the muzzle round also dragged the gun in behind the chest.
##
## `swivel` is the one degree of freedom a wrist position leaves free: a rotation of
## the whole arm about the shoulder-to-wrist line, which moves the elbow and nothing
## else. An unreachable target is not an error — the arm goes as straight as it goes
## and points at it, which is why the off hand is slid into reach before it gets here
## rather than after.
func _solve_arm(side: int, target: Transform3D, swivel: float) -> void:
	var to_wrist := target.origin - _shoulders[side].position
	var span := to_wrist.length()
	if span < 0.001:
		return
	# Law of cosines on the two bones. `bend` is 0 for a straight arm and opens the
	# elbow forward, which is the only way a real one goes.
	var bend := acos(clampf((clampf(span, absf(UPPER_ARM_LENGTH - FOREARM_LENGTH) + 0.01,
			UPPER_ARM_LENGTH + FOREARM_LENGTH - 0.01) ** 2.0
			- UPPER_ARM_LENGTH ** 2.0 - FOREARM_LENGTH ** 2.0)
			/ (2.0 * UPPER_ARM_LENGTH * FOREARM_LENGTH), -1.0, 1.0))
	# Where that elbow puts the wrist with the shoulder left unturned: straight down
	# the upper arm, then round the bend. Rotating this onto the target is the
	# shoulder's whole job.
	var folded := Vector3(0.0, -UPPER_ARM_LENGTH - FOREARM_LENGTH * cos(bend),
			-FOREARM_LENGTH * sin(bend))
	var aim := to_wrist.normalized()
	var basis := Basis(aim, swivel) * Basis(Quaternion(folded.normalized(), aim))
	_carry_shoulder[side] = basis
	_carry_elbow[side] = bend
	_carry_wrist[side] = (basis * Basis.from_euler(Vector3(bend, 0.0, 0.0))).inverse() \
			* target.basis


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
	# Freed along with the hand it was parented to, just above.
	_weapon_model = null

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

	# No forearm stub on this one — there is a real arm above it. Hung, as the
	# neutral pose, until `_pose_arms` turns it to whatever the carry solve wants.
	var glove_rig := HandRig.build(mirror, glove, _accent, false)
	glove_rig.name = "Hand"
	glove_rig.position = Vector3(0.0, -FOREARM_LENGTH, 0.0)
	glove_rig.rotation = HAND_HANG_EULER
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
	_tick_dash(delta)
	# Only ground contact walks the cycle on; in the air the legs hold whatever
	# step they left with rather than pedalling.
	var pace := clampf(planar / GameState.stat("move_speed"), 0.0, 1.4)
	if grounded and not _player.is_sliding():
		_stride_phase = wrapf(_stride_phase
				+ minf(planar / STRIDE_LENGTH, STRIDE_MAX_RATE) * TAU * delta, 0.0, TAU)
	else:
		pace = 0.0
	# A dash on the ground is carrying the player far faster than any run, so the
	# stride is what it would otherwise be read as. Scale it out and the fling
	# below has the legs to itself; the cycle keeps turning underneath, so the
	# walk is back in step by the time the pose has eased off.
	pace *= 1.0 - _dash

	_pose_legs(grounded, pace)
	_pose_arms(_player.hands.grab_weight() if _player.hands != null else 0.0)
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

	# The dash goes on top of whatever the stance already is rather than
	# replacing it, so dashing out of a crouch is still crouched.
	var dash_thigh := -DASH_TRAIL * _dash_forward * _dash
	var dash_knee := DASH_KNEE * _dash
	var dash_roll := -DASH_SIDE_TRAIL * _dash_side * _dash
	lean += DASH_LEAN * _dash_forward * _dash

	# Deliberately built from the stance angles alone, with the dash left out of
	# it. This is the no-IK trick that keeps the soles on the ground — bend the
	# knees and the hips come down to meet them — and legs swung out behind the
	# body are exactly the case it does not describe. Feed the fling in here and
	# the hips drop half a metre to keep boots that have left the ground on it.
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
	# A sideways dash tilts rather than pitches, and both ends tilt the same way:
	# the chest goes over into the dash while the feet come out from under it,
	# which is one body leaning off its own contact patch. Same negation as the
	# line above — the legs hang and the spine stands.
	_spine.rotation.z = -DASH_SIDE_LEAN * _dash_side * _dash

	for side in [SIDE_LEFT, SIDE_RIGHT]:
		var step := _step(side)
		# The trailing leg is the one that has to fold, or the foot ploughs
		# through the ground behind it.
		var trail := maxf(0.0, -step)
		var hip_pitch := thigh + step * STEP_SWING * pace \
				+ dash_thigh + _mirror(side) * DASH_STAGGER * _dash
		var knee_bend := knee + dash_knee - trail * STEP_KNEE_BEND * STEP_SWING * pace
		_hip_joints[side].rotation = Vector3(hip_pitch, 0.0, dash_roll)
		_knees[side].rotation.x = knee_bend
		# Cancels everything above it so the sole stays flat to the world — until
		# a dash takes the foot off the world, at which point most of the
		# correction goes with it and the toes trail in line with the shin.
		_ankles[side].rotation.x = -(hip_pitch + knee_bend) \
				* lerpf(1.0, DASH_ANKLE_FOLLOW, _dash)


## Blends the dash pose in and out, and holds the heading it is struck for in the
## body's own frame — forward positive down -Z, right positive down +X — so a
## dash taken half sideways poses as half of each and a dash backwards poses as
## the forward one inverted. Turning mid-dash re-reads it, since the direction is
## world-space and the body under it is not.
func _tick_dash(delta: float) -> void:
	var dashing := _player.is_dashing()
	_dash = move_toward(_dash, 1.0 if dashing else 0.0, delta * DASH_BLEND_RATE)
	if not dashing:
		return
	var heading := _player.dash_direction()
	var frame := _player.global_transform.basis
	_dash_forward = -frame.z.dot(heading)
	_dash_side = frame.x.dot(heading)


## Arms hold the solved carry pose, and go up when the hands take a ledge. `grab` is
## passed in rather than read off the player, because this is also the one pose the
## editor build can strike.
##
## The arms deliberately do not swing with the stride. They are holding a weapon in
## a pose worked out for one place in the chest's frame, so an arm that pumped would
## be an arm sliding along the gun in its hands — and the first-person pair have
## never pumped either, being nailed to the view model. The two are the same hold
## seen from two places, and only the chest they hang off is allowed to bob.
func _pose_arms(grab: float) -> void:
	var mantle_shoulder := Basis.from_euler(Vector3(MANTLE_SHOULDER, 0.0, 0.0))
	var mantle_wrist := Basis.from_euler(HAND_HANG_EULER)
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		_shoulders[side].basis = _carry_shoulder[side].slerp(mantle_shoulder, grab)
		_elbows[side].rotation.x = lerpf(_carry_elbow[side], MANTLE_ELBOW, grab)
		_hands[side].basis = _carry_wrist[side].slerp(mantle_wrist, grab)
		_hands[side].set_curl(lerpf(_carry_curl[side], MANTLE_CURL, grab))

	# A mantle takes both hands, and the view model stows for it. The body's copy
	# has nowhere to be either — left in the fist it would be swung overhead still
	# gripped, through the ledge the hand is holding.
	if _weapon_model != null:
		_weapon_model.visible = grab < 0.5


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
