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
##
## The depth is also the one number that decides how straight the arms are, and it
## was first cut far too short. `_solve_arm` puts the wrist wherever this says and
## folds the elbow by however much is left over, so a weapon carried 0.14 in front of
## the chest is two arms at about 60% extension — elbows back behind the ribs and the
## whole upper body reading as hunched around something clutched to it. Read this as
## an elbow angle rather than as a distance: every centimetre forward is arm coming
## out straight, and the useful band is roughly 70–85% of `UPPER_ARM_LENGTH +
## FOREARM_LENGTH`. Past that the solve runs out of arm, and an arm that has run out
## stops bending and starts *pointing* — a straight limb with the hand somewhere near
## the grip rather than on it.
##
## The position is in the chest's frame and the angles are not: the weapon is carried
## wherever the chest carries it, which is what brings it down with a crouch, but it
## stays level with the world while it goes. Leave the angles in the chest's frame
## too and a squat points the barrel at the floor and a slide points it at the sky —
## the chest pitches 40° forward for one and 26° back for the other.
##
## Z is the *back* of the receiver rather than its middle, and half the weapon's own
## length is added on when it is equipped: the receivers in this game run from 0.30
## to 0.46, so one fixed depth either carries the pistol at arm's length or carries
## the carbine through its owner's ribs.
const CARRY_WEAPON_POS := Vector3(0.22, 0.11, -0.21)
const CARRY_WEAPON_EULER := Vector3(-0.14, 0.0, 0.0)
## How much further out the weapon is pushed at a full look up or down, along the
## line it is now pointing.
##
## A weapon can be held in against the shoulder while it is level, and cannot while
## it is pointing at the sky or at your own boots — the arms have to come out to get
## it round. Without this the pose at the pitch clamp is the standing pose rotated
## bodily about the shoulders, which keeps the same elbow bend the whole way and
## reads as a body swivelling a weapon welded across its chest.
##
## Scaled by `sin(|pitch|)`, so it is nothing at the horizon, most of itself by 45°
## and all of it at the clamp. Small on purpose: this is spent straight out of the
## arm's remaining extension, and the arm that runs out stops holding the weapon and
## starts pointing at it.
const LOOK_REACH := 0.04
## The steepest look the carry is solved for, a shade past the camera's own clamp
## (`Player` holds the pitch inside ±1.45). Only `_support_grip` uses it, and only to
## ask where the weapon gets to at worst.
const LOOK_PROBE := 1.5
## Where the weapon is carried while a switch is in flight: down beside the right
## hip, muzzle at the floor. Same pocket the view model drops into, seen from the
## outside — `WeaponController.swap_amount()` is what blends between the two, so
## the weapon your shadow has and the one in front of your face go away together
## and come back together.
##
## Unlike the carry above, the receiver's own length is *not* folded into this one.
## It is quoted as the model's origin outright, because a weapon hanging nose-down
## runs along the body rather than out from it: the depth that matters up here is
## how far a long receiver reaches in front of the chest, and down there it is how
## far it reaches past the knee, which is nobody's problem.
const HOLSTER_WEAPON_POS := Vector3(0.27, -0.16, -0.06)
const HOLSTER_WEAPON_EULER := Vector3(-1.25, 0.0, 0.0)
# --- Carry motion -----------------------------------------------------------
## What the weapon does while its owner moves, quoted as offsets to the carry pose
## above and applied in the same two frames it is.
##
## The arms are not posed for any of this. The weapon moves and `_solve_arm` works
## out the arms that still hold it, which is the only version of "the arms react to
## the movement" that keeps both hands on the grip — swing a shoulder directly and
## the hand on the end of it slides along the gun it is supposed to be gripping. It
## is the same bargain the carry pose itself is struck on, run every frame instead
## of once.
##
## All of it is deliberately small, and *much* smaller than it looks written down.
## The arm solve is a lever working the wrong way: the weapon is carried close in to
## a shoulder barely half a metre from it, so a centimetre of weapon buys something
## like ten degrees of shoulder. The first cut of these numbers had the run at
## `RUN_BOB := 0.026` — under three centimetres, and visibly a soldier pumping his
## arms with a rifle bolted to them. Read every constant below as an angle at the
## shoulder rather than as a distance, and change them by ratios rather than by
## eye.

## Breathing, and the only motion a standing player has. Shouted down as soon as
## anything larger takes over, or a sprint is a stride with a slow sine added
## underneath it. All three components start at zero so the editor build, which
## never advances the clock, gets the pose exactly as authored.
## Slower than the first cut and slightly tighter, which is the same correction
## `WeaponController` carries and for the same reason: heaviness is the rate, not
## the distance, and inflating these made every weapon floatier rather than
## weightier. Scaled down further on a heavy weapon by `heft_swing()`.
const IDLE_RATE := 1.45
const IDLE_RISE := 0.0042
const IDLE_DRIFT := 0.0026
const IDLE_PITCH := 0.017

## The stride, taken off the same phase the legs run on. The bob is *counter* to the
## hips' — the chest this is quoted against is already rising and falling with the
## step, so a weapon that rose with it would be one welded to the ribs — and the
## sway is once per cycle against the bob's twice, because a body rolls once per two
## steps and drops onto each of them.
const RUN_BOB := 0.006
const RUN_SWAY := 0.0042
const RUN_PITCH := 0.032
const RUN_ROLL := 0.051

## A dash is the one move fast enough for a held mass to visibly lag behind its
## owner: the body is flung and the weapon is left trailing the direction of
## travel, dropped in against the chest.
const DASH_LAG := 0.045
const DASH_SIDE_LAG := 0.032
const DASH_DROP := 0.020
const DASH_CARRY_PITCH := 0.12

## A slide tucks it in against the body and points it up, clear of knees that have
## come up in front of it.
const SLIDE_TUCK := 0.038
const SLIDE_RISE := 0.018
const SLIDE_CARRY_PITCH := -0.16

## Vertical inertia, which is what a jump and a fall are actually made of: the
## weapon dips as the body is thrown up out from under it, and floats as the body
## drops away. Taken off the player's own vertical velocity rather than off a jump
## event, so one number covers the whole arc — the rise, the hang and the fall —
## and a fall the player never jumped into gets it too.
##
## Metres of offset per metre per second, clamped, and faded out on the ground where
## the reading is nothing but the floor snap.
const AIR_LAG := 0.0034
const AIR_LAG_MAX := 0.026
## Radians of muzzle pitch per metre of that lag.
const AIR_CARRY_PITCH := 2.6
const AIR_BLEND_RATE := 8.0

## The off hand while it is off the weapon: hanging just clear of the hip with the
## fingers loose. Not the empty-handed brace further down — that pose is two hands
## ready to catch something, and this is one hand waiting for the other to finish.
const SWAP_FREE_SHOULDER := 0.12
const SWAP_FREE_SPLAY := 0.12
const SWAP_FREE_ELBOW := 0.40
const SWAP_FREE_CURL := 0.35
## Which way each elbow is asked to point, in the chest's frame with +X the shooting
## side.
##
## It is a preference rather than a position. The wrist has already fixed how far off
## the shoulder-to-wrist line the elbow must sit — that is just the two bone lengths
## and the distance — and all this picks is which way round that circle it goes. Left
## to itself the solve takes the shortest turn from a hanging arm, which puts the
## elbow behind the back.
##
## Two of them rather than one mirrored, because the arms are not doing mirrored
## jobs. The shooting hand is on a grip directly below its own shoulder and its elbow
## goes down, out and a little back, which is where an elbow goes when its owner
## brings something up in front of their chest. The support hand is across the body
## on a weapon carried on the *other* side, and the same preference mirrored throws
## its elbow out past the ribs into a chicken wing — the one thing in this pose that
## still read as hunched once the weapon was far enough forward. A support elbow
## belongs under the weapon it is holding up, so this one is very nearly straight
## down.
##
## Quoted for the weapon carried level, and **swung with it** by `_solve_carry` — it
## is not a direction in the chest's frame, whatever it looks like written down here.
## That matters most at the pitch clamp. Held fixed, this direction and the
## shoulder-to-wrist line sweep towards each other as the player looks down, and the
## circle the elbow is being placed on shrinks to a point: within a few degrees of
## parallel the preference stops meaning anything, the elbow slides round to whatever
## is left and the arm turns inside out. It is worst exactly where it is most visible,
## because looking straight down is looking at your own arms. Swinging it costs
## nothing and is what a shoulder actually does — raise a weapon and the elbow rides
## up with it — so the pose at any pitch is the pose at the horizon, turned.
const ELBOW_POLE_TRIGGER := Vector3(0.30, -0.94, 0.10)
const ELBOW_POLE_SUPPORT := Vector3(-0.10, -0.97, 0.22)
## Grip strength, matching the pair in front of the camera: the shooting hand closes
## hard on a grip post, the support hand rests on something wider.
const HOLD_CURL_TRIGGER := 1.30
const HOLD_CURL_SUPPORT := 1.05
## How far the off hand may slide back along the weapon, towards the receiver, to
## get within reach of the arm that has to hold it. A carbine's foregrip sits most of
## a metre out from the shoulder reaching for it, which is further than an arm goes;
## a real shooter's answer is to hold it further back, so it is this one's too.
##
## A backstop rather than the working limit — `_support_grip` stops the hand a palm
## and a half short of the one on the grip, which is the real constraint and is the
## weapon's own length talking. This only catches a weapon long enough that the arm
## would be crossing the body to reach even the receiver, and there is no such weapon
## yet.
const SUPPORT_SLIDE_MAX := 0.55
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

## How much of the look pitch the chest takes, with the arms taking the rest.
##
## The weapon points wherever the player is looking either way — that part is not
## negotiable, and is what the whole of `_look_pitch` buys. What this splits is who
## does the work. Give the arms all of it and a full look up is two arms straight
## overhead on a torso standing bolt upright, which is a mannequin holding a rifle
## over its head; give the chest much more than this and looking down folds the body
## into a bow. A quarter is enough to read as a person leaning into the shot.
##
## It also quietly buys back some neck. The head is clamped at HEAD_PITCH_LIMIT and
## compensates for the chest's lean, so a chest that has already gone a quarter of
## the way is a skull turned a quarter less far past its own shoulders.
const LOOK_SPINE_SHARE := 0.25

const SIDE_LEFT := 0
const SIDE_RIGHT := 1

## Off by default the moment anything wants to see the whole model — a
## third-person camera, a dev capture. On, the parts the first-person camera sits
## inside are demoted to shadows-only.
@export var first_person: bool = true: set = set_first_person

var _player: Player
## The rig in front of the camera. Held for `swap_amount()` alone: how far through
## putting a weapon away it is, which this body has no other way of knowing and has
## to match exactly.
var _weapons: WeaponController
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
## Where each hand holds the equipped weapon, in the weapon's own frame: the two
## anchors `ViewHands` sends the first-person pair to, with the off hand slid back
## along the barrel far enough that the arm can reach it. Empty until something is
## equipped. Worked out on a weapon switch, because it is the weapon's own geometry
## talking and none of it changes with the pose.
var _grip: Array[Transform3D] = []
## `CARRY_WEAPON_POS` with the equipped weapon's own length folded into the depth.
var _carry_pos: Vector3 = CARRY_WEAPON_POS
## The carry pose, solved: shoulder orientation, elbow bend, wrist orientation and
## grip, per side, each in the frame its own joint lives in.
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
## Breathing clock, and how hard the legs are working this frame. `_pace` is held
## rather than passed because the legs are posed from `_process` and the arms are
## solved several calls down from it, and it is the same reading either way.
var _idle_time: float = 0.0
var _pace: float = 0.0
## Vertical inertia, eased. See `AIR_LAG`.
var _air_lag: float = 0.0
## How far through a weapon switch the arms are, 0 carrying to 1 at the hip. Copied
## straight off the controller rather than eased again here: the trip is already on
## a clock over there, and a second smoothing on top would have the body still
## lowering a weapon the player has already been handed a new one of.
var _swap: float = 0.0
## How far down the sights the player is, 0 to 1. Copied off the controller for the
## same reason `_swap` is: the steadying is already eased over there, and the body's
## weapon holding still by a different amount than the one in front of the camera is
## the two of them disagreeing about the same gun.
var _aim: float = 0.0
## Where the player is looking, forward-positive, in the body's own frame. Read once
## a frame and held because three separate poses want it — the chest, the arms and
## the head — and one of those is solved several calls down from `_process`. Zero in
## the editor, where there is no camera to read and the standing pose is the point.
var _look_pitch: float = 0.0


func _ready() -> void:
	_accent = HandRig.make_material(HandRig.ACCENT_COLOR, true)
	_build()
	_apply_visibility()
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
	_weapons = _find_weapons()
	if _weapons != null and _weapons.current() != null:
		_on_weapon_equipped(_weapons.current())


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
	_set_grip(data)


# --- Carry pose -------------------------------------------------------------

## Which part of the newly equipped weapon each hand takes hold of. The same two
## anchors `ViewHands` sends the first-person pair to, so the hands you look at and
## the hands your shadow has hold the same gun in the same places.
func _set_grip(data: WeaponData) -> void:
	_grip.clear()
	if data == null or _shoulders.size() <= SIDE_RIGHT:
		return
	_carry_pos = CARRY_WEAPON_POS - Vector3(0.0, 0.0, data.body_size.z * 0.5)
	_grip.append(_support_grip(data))
	_grip.append(WeaponController.wrist_in_model_frame(data, WeaponController.HAND_RIGHT))


## Where the off hand goes: the weapon's own support anchor, slid back along the
## weapon towards the receiver until the arm can actually reach it. Sliding rather
## than stretching matters — an arm at full extension still misses by however far it
## was short, and a hand hanging a few centimetres off a foregrip reads worse than a
## hand holding a foregrip further back than it might have.
##
## Measured against the carry pose standing upright, because how far the hand has to
## slide is the weapon's length talking and not the stance's — with one exception.
## The look is not a stance. It is spent at every pitch the player can turn the mouse
## to, and it moves the weapon: the swing is about the line between the shoulders, so
## a weapon carried on the right and swung to the sky is measurably further from the
## *left* shoulder than the same weapon held level. Solve this against the horizon
## alone and the off hand can just about reach while the player looks straight ahead
## and has quietly let go by the time the muzzle is up. So all three are tried and
## the worst one wins, which costs a centimetre or two of slide at rest and buys a
## hand that stays on the weapon everywhere.
func _support_grip(data: WeaponData) -> Transform3D:
	var poses: Array[Transform3D] = [_carry_at(0.0), _carry_at(LOOK_PROBE),
			_carry_at(-LOOK_PROBE)]
	var base := WeaponController.wrist_in_model_frame(data, WeaponController.HAND_LEFT)
	var shoulder := _shoulders[SIDE_LEFT].position
	var reach := UPPER_ARM_LENGTH + FOREARM_LENGTH - 0.02
	# How far back there is weapon to slide along, which is a question about the other
	# hand rather than about the barrel: the off hand may come back as far as it likes
	# so long as it stops short of the one on the grip. A palm and a half of clearance
	# between the two wrists, because they are attached to fists with width to them.
	# Quoting it this way is what lets a long receiver be held by the magazine well —
	# where a support hand goes on a real carbine — instead of the slide running out
	# on the barrel with the arm still short. On a pistol the two anchors are already
	# touching, so this comes out at zero and the hand does not slide at all, which is
	# right: a cupped off hand has nowhere to go.
	var limit := minf(SUPPORT_SLIDE_MAX, maxf(0.0,
			WeaponController.wrist_in_model_frame(data, WeaponController.HAND_RIGHT).origin.z
					- HandRig.PALM_SIZE.z * 1.5 - base.origin.z))
	var slide := 0.0
	var wrist := base
	while slide < limit and _worst_reach(poses, wrist, shoulder) > reach:
		slide += SUPPORT_SLIDE_STEP
		# +Z runs back down the weapon towards the receiver, because -Z is the way
		# the barrel points and the way the fingers reach.
		wrist.origin = base.origin + Vector3(0.0, 0.0, slide)
	return wrist


## The furthest this wrist ends up from that shoulder over a set of carry poses.
func _worst_reach(poses: Array[Transform3D], wrist: Transform3D,
		shoulder: Vector3) -> float:
	var worst := 0.0
	for pose in poses:
		worst = maxf(worst, (pose * wrist).origin.distance_to(shoulder))
	return worst


## Where the weapon is carried, in the chest's frame, for a given look pitch — with
## the body upright and standing still. `_solve_carry` puts the spine's lean and the
## movement offsets on top of this; `_support_grip` measures against it bare. One
## copy of the arithmetic, so that retuning the swing cannot leave the slide solved
## against a pose the weapon no longer takes.
func _carry_at(look: float) -> Transform3D:
	var swung := Basis.from_euler(Vector3(look * (1.0 - LOOK_SPINE_SHARE), 0.0, 0.0))
	var pivot := Vector3(0.0, SHOULDER_Y - CHEST_Y, 0.0)
	return Transform3D(Basis.from_euler(CARRY_WEAPON_EULER + Vector3(look, 0.0, 0.0)),
			pivot + swung * (_carry_pos - pivot
					+ Vector3(0.0, 0.0, -LOOK_REACH * sin(absf(look)))))


## Both arms, for wherever the weapon is being carried this frame — or a generic
## braced pose when there is nothing to hold, which is what the editor build gets and
## what stands in before the first weapon is equipped.
##
## The weapon is placed first and the hands are sent to it, which is the whole point:
## the thing that has to look right is the weapon, so the weapon is the thing that
## gets authored. It runs every frame rather than once per weapon because the carry
## angles are quoted in the player's frame and solved in the chest's, and the chest
## leans — an arm solved for last frame's lean is an arm holding the gun somewhere
## else. What is genuinely per-weapon is `_grip`, and that is not recomputed here.
func _solve_carry() -> void:
	if _shoulders.size() <= SIDE_RIGHT:
		return
	if _grip.size() <= SIDE_RIGHT:
		for side in [SIDE_LEFT, SIDE_RIGHT]:
			_carry_shoulder[side] = Basis.from_euler(Vector3(EMPTY_SHOULDER,
					_mirror(side) * EMPTY_YAW, _mirror(side) * EMPTY_ROLL))
			_carry_elbow[side] = EMPTY_ELBOW
			_carry_wrist[side] = Basis.from_euler(HAND_HANG_EULER)
			_carry_curl[side] = EMPTY_CURL
		return

	# `_spine` is the only joint between the player and the chest that turns, so
	# undoing it is what takes an angle quoted in the player's frame into the frame
	# the arms are solved in — and what keeps the barrel level through a crouch that
	# folds the chest 40° forward and a slide that tips it 26° back.
	# The motion offset turns the weapon in its own levelled frame and shifts it in
	# the chest's, matching the two frames the carry pose itself is quoted in — so a
	# stride bobs the muzzle without a crouch aiming it at the floor.
	var motion := _carry_motion()
	# And the weapon goes where the player is looking. The view model never needed
	# this — it is a child of the camera and pitches with it for free — so the body
	# was the only one of the two holding its gun flat at the horizon while the
	# crosshair sat on a rooftop. Invisible from inside the head; the entire picture
	# from the chase camera.
	#
	# The rotation takes the *whole* look angle, because the barrel has to end up
	# pointing along it and nothing else here is going to. The position is swung by
	# what is left after the chest's share (`LOOK_SPINE_SHARE`, spent back in
	# `_pose_legs`), since the chest carries the weapon with it when it leans and
	# counting that twice would over-swing the arms by a quarter. The rotation needs
	# no such split — the spine is divided straight back out of it on the next line.
	# About the line between the shoulders rather than in place. An arm raises a
	# weapon by turning at the shoulder, so the muzzle coming up brings the receiver
	# down with it; pitch it where it stands and the gun is on a hinge welded to the
	# ribs. The swing is applied in the chest's frame and the angle is quoted in the
	# player's, which costs nothing: both are rotations about X, and the only thing
	# between them that is not — the sideways lean of a dash — is a few degrees and
	# gone in a third of a second. All of that lives in `_carry_at`, because the
	# support hand's slide has to be solved against the same poses.
	var swung := Basis.from_euler(Vector3(_look_pitch * (1.0 - LOOK_SPINE_SHARE), 0.0, 0.0))
	var base := _carry_at(_look_pitch)
	var weapon := Transform3D(
			_spine.basis.inverse() * base.basis * motion.basis,
			base.origin + swung * motion.origin)
	# A switch moves the weapon and lets the arms follow, which is the same bargain
	# the carry itself is struck on: the thing that has to look right is where the
	# gun goes, so that is the thing that gets authored.
	if _swap > 0.0:
		weapon = weapon.interpolate_with(Transform3D(
				_spine.basis.inverse() * Basis.from_euler(HOLSTER_WEAPON_EULER),
				HOLSTER_WEAPON_POS), _swap)
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		# Each elbow's own preference, riding the same swing as the weapon — see
		# `ELBOW_POLE_TRIGGER`.
		var pole := ELBOW_POLE_TRIGGER if side == SIDE_RIGHT else ELBOW_POLE_SUPPORT
		_solve_arm(side, weapon * _grip[side], swung * pole)
	_carry_curl[SIDE_LEFT] = HOLD_CURL_SUPPORT
	_carry_curl[SIDE_RIGHT] = HOLD_CURL_TRIGGER
	if _swap > 0.0:
		_release_support(_swap)


## Advances the breathing clock and the vertical inertia. Split out of `_carry_motion`
## because that one is asked for a pose and this one has a frame's worth of state to
## move on, and `_solve_carry` runs from the editor's standing pose as well.
func _tick_carry_motion(delta: float, grounded: bool) -> void:
	_idle_time = wrapf(_idle_time + delta * IDLE_RATE, 0.0, TAU)
	var want := 0.0
	if not grounded:
		want = clampf(-_player.velocity.y * AIR_LAG, -AIR_LAG_MAX, AIR_LAG_MAX)
	_air_lag = lerpf(_air_lag, want, clampf(delta * AIR_BLEND_RATE, 0.0, 1.0))


## How far the weapon in hand is thrown about by what its owner is doing, off the
## controller's own accessor so the two rigs cannot disagree about how heavy the
## same gun is.
##
## Guarded rather than latched like `_aim` and `_swap`, because `_carry_motion()`
## is also reached from `_solve_carry()` in the editor build, where there is no
## controller to ask and the pose wanted is the authored one.
func _heft_swing() -> float:
	return 1.0 if _weapons == null else _weapons.heft_swing()


## Where the weapon sits this frame relative to where it is carried, and how it is
## turned: position in the chest's frame, rotation in the weapon's own.
##
## Both halves matter. A weapon that translates without turning reads as a prop
## sliding along a rail, and one that turns without translating reads as a hinge.
func _carry_motion() -> Transform3D:
	# Aiming steadies all of it, the oscillations harder than the stances. Both
	# multipliers are the view model's, deliberately: the arms are solved to hold a
	# weapon that has to be as still as the one the player is sighting along, and two
	# sets of numbers for one gun is two things to remember to change. See
	# `WeaponController.AIM_SWAY_MULT` for why the split exists at all.
	# And how heavy it is, off the controller's accessor rather than off
	# `WeaponData` directly — that one follows a weapon switch, so the arms get
	# heavier on the same frame the receiver in the fist changes shape. On the
	# oscillations only, matching the split the view model makes: a stride throws a
	# slab about more than it does a pistol, and neither is tucked further out of the
	# way of a knee than the other.
	var sway_scale := lerpf(1.0, WeaponController.AIM_SWAY_MULT, _aim) * _heft_swing()
	var stance_scale := lerpf(1.0, WeaponController.AIM_STANCE_MULT, _aim)

	# Breathing, and only while there is nothing louder. A sprint has a stride to
	# bob to and a dash has its own idea of where the weapon goes; either one with a
	# slow sine still running underneath it is two animations fighting.
	var quiet := clampf(1.0 - _pace - _slide - _dash, 0.0, 1.0) * sway_scale
	var offset := Vector3(sin(_idle_time * 0.5) * IDLE_DRIFT,
			sin(_idle_time) * IDLE_RISE, 0.0) * quiet
	var euler := Vector3(sin(_idle_time) * IDLE_PITCH * quiet, 0.0, 0.0)

	# The stride. Negated against the hips' own bob — see RUN_BOB.
	var stride := _pace * sway_scale
	offset += Vector3(sin(_stride_phase) * RUN_SWAY,
			-sin(_stride_phase * 2.0) * RUN_BOB, 0.0) * stride
	euler.x += cos(_stride_phase * 2.0) * RUN_PITCH * stride
	euler.z += sin(_stride_phase) * RUN_ROLL * stride

	# Vertical inertia: down as the body is thrown up, up as it drops away.
	offset.y += _air_lag * sway_scale
	euler.x += _air_lag * AIR_CARRY_PITCH * sway_scale

	# A dash leaves the weapon trailing the body that was flung out from under it.
	# +Z is back, so a forward dash lags positive and a backward one lags forward.
	if _dash > 0.0:
		offset += Vector3(-DASH_SIDE_LAG * _dash_side, -DASH_DROP,
				DASH_LAG * _dash_forward) * _dash * stance_scale
		euler.x += DASH_CARRY_PITCH * _dash_forward * _dash * stance_scale

	# A slide brings it in and points it up, out of the way of the knees.
	offset += Vector3(0.0, SLIDE_RISE, SLIDE_TUCK) * _slide * stance_scale
	euler.x += SLIDE_CARRY_PITCH * _slide * stance_scale
	return Transform3D(Basis.from_euler(euler), offset)


## The off hand comes off the weapon for the length of a switch and hangs at the
## side. It has to: the weapon is going to the *right* hip, and a left arm sent
## after it is reaching across the body for a point further off than the arm is
## long — which `_solve_arm` answers, correctly and unhelpfully, by straightening
## out and pointing at it. A hand stretched to full extension short of the thing it
## is holding reads worse than a hand that let go.
func _release_support(weight: float) -> void:
	var hang := Basis.from_euler(Vector3(SWAP_FREE_SHOULDER, 0.0,
			_mirror(SIDE_LEFT) * SWAP_FREE_SPLAY))
	_carry_shoulder[SIDE_LEFT] = _carry_shoulder[SIDE_LEFT].slerp(hang, weight)
	_carry_elbow[SIDE_LEFT] = lerpf(_carry_elbow[SIDE_LEFT], SWAP_FREE_ELBOW, weight)
	_carry_wrist[SIDE_LEFT] = _carry_wrist[SIDE_LEFT].slerp(
			Basis.from_euler(HAND_HANG_EULER), weight)
	_carry_curl[SIDE_LEFT] = lerpf(_carry_curl[SIDE_LEFT], SWAP_FREE_CURL, weight)


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
## The one degree of freedom a wrist position leaves free is a rotation of the whole
## arm about the shoulder-to-wrist line, which moves the elbow and nothing else;
## `pole` is what spends it — a direction in the same frame as `target`, already
## picked for this side. It arrives as an argument rather than being read off a
## constant here because it is not one: it differs per arm and it swings with the
## weapon, and a pole left standing still is an arm that turns inside out at the
## pitch clamp. See `ELBOW_POLE_TRIGGER` for both halves of that.
##
## An unreachable target is not an error — the arm goes as straight as it goes and
## points at it, which is why the off hand is slid into reach before it gets here
## rather than after.
func _solve_arm(side: int, target: Transform3D, pole: Vector3) -> void:
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
	var basis := Basis(Quaternion(folded.normalized(), aim))
	# Where that leaves the elbow against where it was asked to go, both flattened
	# onto the circle it is free to travel — the difference between the two is the
	# swivel, and applying it about the same line cannot move the wrist.
	var have := (basis * Vector3(0.0, -UPPER_ARM_LENGTH, 0.0)).slide(aim)
	var want := pole.slide(aim)
	if have.length() > 0.001 and want.length() > 0.001:
		basis = Basis(aim, have.signed_angle_to(want, aim)) * basis
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
	_grip.clear()

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
	_look_pitch = _camera_pitch()
	_slide = move_toward(_slide, 1.0 if _player.is_sliding() else 0.0, delta * 7.0)
	_tick_dash(delta)
	_swap = 0.0
	_aim = 0.0
	if _weapons != null:
		_swap = _weapons.swap_amount()
		_aim = _weapons.aim_amount()
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

	_pace = pace
	_tick_carry_motion(delta, grounded)
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

	# The chest's share of the look. Forward-positive like everything else here, so
	# looking *up* leans it back — hence the subtraction. The rest of the angle is
	# spent at the shoulders in `_solve_carry`, and the head undoes whatever lands
	# here, so it goes on pointing exactly where the camera does.
	lean -= _look_pitch * LOOK_SPINE_SHARE

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
## The arms do move with the stride, with the dash, the slide and the jump — but
## never *directly*. Every one of those goes through `_carry_motion()`, which moves
## the weapon, and the arms are whatever `_solve_arm` says still holds it. Pose a
## shoulder here instead and the hand on the end of it slides along the gun it is
## meant to be gripping, which is the one thing this whole arrangement exists to
## prevent. The first-person pair get the same treatment from the other end: they
## are nailed to the view model, and the view model has its own copy of the same
## offsets.
func _pose_arms(grab: float) -> void:
	_solve_carry()
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
## down bends the neck instead of spinning the skull.
func _pose_head() -> void:
	# Plus whatever the chest is leaning, since this hangs off it: a crouch folds
	# the torso forward and the head should keep looking where the player is,
	# not at its own knees. That now includes the chest's share of the look itself,
	# which cancels back out here — the skull ends up at the clamped look angle
	# either way, and simply has less neck to do it with.
	_head.rotation.x = clampf(_look_pitch, -HEAD_PITCH_LIMIT, HEAD_PITCH_LIMIT) + _lean


## Where the player is looking, forward-positive. Taken off the camera's own basis
## rather than off `Player._pitch`, so recoil and the mantle look-down carry through
## without this having to know about either — the weapon a shot has just kicked
## upwards is the weapon the camera is looking along.
func _camera_pitch() -> float:
	if _player == null or _player.camera == null:
		return 0.0
	return asin(clampf(-_player.camera.global_transform.basis.z.y, -1.0, 1.0))


## Where this side is in the walk cycle, -1 to 1. The two legs are half a cycle
## apart, which is what makes it a walk rather than a hop.
func _step(side: int) -> float:
	return sin(_stride_phase + (PI if side == SIDE_LEFT else 0.0))
