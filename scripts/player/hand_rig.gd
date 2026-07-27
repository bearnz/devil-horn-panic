@tool
class_name HandRig
extends Node3D
## One gloved hand: an accent cuff, a palm, four two-jointed fingers and a thumb,
## all boxes, with an optional forearm stub behind the wrist.
##
## The rig *is* the wrist. Its own transform places the hand and everything under
## it is local, so a caller moves one node and the hand follows.
##
## Shared by `ViewHands`, which hangs one off each weapon anchor, and by
## `PlayerBody`, which puts one on the end of each arm. That sharing is the whole
## point: there is one hand in this game, and the pair you look down at and the
## pair your shadow has are both it.
##
## Sizes are a little under life — a 9cm palm, 17cm wrist to fingertip against a
## real 19cm — which is what lets the same numbers serve a 1.8m body *and* a view
## model whose weapons are deliberately undersized. Nothing here is scaled per
## caller; a hand that changed size between the two would give the game away the
## first time a shadow fell next to the screen.
##
## `@tool` only because `PlayerBody` is: a rig built for the editor viewport has to
## be allowed to run there. Nothing in here has a `_ready` or a frame loop, so the
## annotation costs nothing.

## Wrist-relative geometry, all in metres.
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

## The palette the player is dressed in, here rather than in either caller so the
## body and the view hands cannot drift apart. The accent is only a starting
## colour — both callers retint their trim with the equipped weapon.
const GLOVE_COLOR := Color(0.34, 0.31, 0.36)
const ACCENT_COLOR := Color(0.75, 0.16, 0.16)

## Per-finger curl multipliers, index to little. Nothing subtle — a stagger just
## stops four identical boxes reading as one slab.
const FINGER_CURL := [1.0, 1.06, 1.0, 0.9]

## The four knuckle pivots and the mid joint parented under each, so a single curl
## value bends a whole finger at two places.
var _knuckles: Array[Node3D] = []
var _mids: Array[Node3D] = []
var _thumb: Node3D
var _meshes: Array[MeshInstance3D] = []


## A hand, ready to be parented and posed. `mirror` is +1 for a right hand and -1
## for a left: the boxes are symmetrical, so mirroring is done by moving them
## rather than by scaling the rig negatively, which would invert every normal.
##
## `with_forearm` drops the stub for callers that have a real forearm to put the
## wrist on the end of.
static func build(mirror: float, glove: Material, accent: Material,
		with_forearm: bool = true) -> HandRig:
	var hand := HandRig.new()
	if with_forearm:
		hand._box(hand, FOREARM_SIZE, FOREARM_OFFSET, glove)
	hand._box(hand, CUFF_SIZE, CUFF_OFFSET, accent)
	hand._box(hand, PALM_SIZE, PALM_OFFSET, glove)

	for finger in 4:
		var knuckle := Node3D.new()
		knuckle.name = "Knuckle%d" % finger
		knuckle.position = Vector3(
				mirror * (finger * KNUCKLE_SPACING - KNUCKLE_SPACING * 1.5),
				-0.002, -KNUCKLE_REACH)
		hand.add_child(knuckle)
		hand._box(knuckle, FINGER_SIZE, Vector3(0.0, 0.0, -FINGER_SIZE.z * 0.5), glove)

		var mid := Node3D.new()
		mid.name = "Mid"
		mid.position = Vector3(0.0, 0.0, -FINGER_SIZE.z)
		knuckle.add_child(mid)
		hand._box(mid, FINGER_TIP_SIZE, Vector3(0.0, 0.0, -FINGER_TIP_SIZE.z * 0.5), glove)

		hand._knuckles.append(knuckle)
		hand._mids.append(mid)

	var thumb := Node3D.new()
	thumb.name = "Thumb"
	thumb.position = Vector3(mirror * -0.040, -0.010, -0.055)
	# Splayed outwards, away from the fingers it is opposing.
	thumb.rotation = Vector3(0.0, mirror * 0.5, 0.0)
	hand.add_child(thumb)
	hand._box(thumb, THUMB_SIZE, Vector3(0.0, 0.0, -THUMB_SIZE.z * 0.5), glove)
	hand._thumb = thumb
	return hand


## The look everything gloved or suited is built out of. Both materials carry a
## little emission: these surfaces are held palm-down under a sky-lit arena, so
## the faces pointing at the camera are the ones pointing away from every light,
## and without a floor under the shading they read as black holes.
static func make_material(color: Color, is_accent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5 if is_accent else 0.85
	material.metallic = 0.1
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.22 if is_accent else 0.14
	return material


## Curls the whole hand. Fingers bend towards the palm (-Y), which is a negative
## rotation about the knuckle's X, and the mid joint follows a little harder so
## the fingertip ends up pointing back at the wrist rather than straight down.
func set_curl(amount: float) -> void:
	for finger in _knuckles.size():
		var curl := amount * float(FINGER_CURL[finger])
		_knuckles[finger].rotation.x = -curl
		_mids[finger].rotation.x = -curl * 0.9
	if _thumb != null:
		_thumb.rotation.x = -amount * 0.45


## Applied to every box at once: a view-model hand renders but must stay out of
## the shadow map, and a body's hand is the other way round when the camera is
## inside its head.
func set_shadow_mode(mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	for mesh in _meshes:
		mesh.cast_shadow = mode


func _box(parent: Node3D, size: Vector3, offset: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = offset
	parent.add_child(mesh)
	_meshes.append(mesh)
