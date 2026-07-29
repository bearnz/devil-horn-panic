class_name DamageIndicator
extends Control
## Wedges round the crosshair pointing at whatever is hurting the player. Drawn
## rather than textured, like the reticle and the wind, so it needs no art.
##
## The vignette already says the player has been hit and roughly how hard. What
## it cannot say is *where from*, and in an arena where the fight surrounds you
## that is the only part worth acting on — a red frame tells you to move, and
## this tells you which way. The split is deliberate and matches the one that
## keeps the damage numbers and the vignette from being read as one another:
## severity is the vignette's channel and stays there, so this one is a uniform
## mark whose only variable is a bearing. Two channels saying the same thing is
## redundancy rather than information.
##
## **A mark stores the world direction it came from and works out its place on
## the ring every frame.** That is the load-bearing decision in the file. Latch a
## screen angle instead and the mark stays where it was drawn while the player
## turns to look — which is exactly backwards, since the entire job of the thing
## is to be pointed at, and the moment the player acts on it, it lies. Stored the
## way it is, turning to face an attacker walks its wedge round to the top of the
## ring and it goes out under the crosshair, which is the effect telling you that
## you have found what it was pointing at.
##
## Fed by `Events.player_damaged`, whose `from` is already flattened to the
## horizontal by the player — see the note on the signal.

## Where the band sits and how thick it is, both as fractions of the frame's
## shorter side. Fractions for the same reason everything in `SpeedLines` is:
## fifteen pixels at 720p is a mark and fifteen at 4K is a scratch.
##
## Far enough out to be seen without looking straight at it, which is the whole
## point — a mark you have to study is a mark you read after the hit that mattered
## rather than during it — and near enough in that it is still part of the reticle
## rather than furniture at the edge of the frame.
const RADIUS := 0.155
const THICKNESS := 0.024

## Pixels of the middle of the frame no mark may reach into, and the same budget
## the wind is held to for the same reason: the crosshair's arms reach about
## twenty from centre and its hit marks about the same, and a HUD element growing
## out of the reticle is the HUD reporting something it did not mean. Enforced by
## pushing the whole ring out rather than by clipping a wedge, so the guarantee is
## one number instead of a special case per mark. On a frame too small to hold
## both — a headless run renders into 64 pixels square — the reticle wins and the
## marks are simply pushed off the edge.
const CENTRE_CLEAR := 46.0

## How wide a wedge is, and how many segments it is drawn from. Wide enough to be
## a direction rather than a tick, narrow enough that two attackers a quarter turn
## apart are two marks.
const ARC_DEGREES := 46.0
const ARC_STEPS := 10

## How long a mark lasts. About as long as it takes to turn and look, which is
## the only thing it is asking for — hold it longer and a mark outlives the enemy
## that put it there, which is a HUD pointing at an empty corner.
const LIFETIME := 1.15

## Hits whose world directions are within this of one another land on the mark
## already up rather than adding a second. Same reasoning as the damage numbers'
## merge, and the same case: a grunt in melee swings every `attack_cooldown`, and
## a mark per swing is a stack of identical wedges lighting up in place, which is
## a texture rather than a warning. A quarter turn, so two enemies on the same
## flank read as one flank and two on opposite sides never merge.
const MERGE_ANGLE := deg_to_rad(45.0)

## A thickness spike when a mark is made or refreshed, decayed at this rate. What
## it is for is the *refresh*: without it a mark being re-hit is a wedge whose
## alpha quietly stops falling, and a warning that arrives by not fading is no
## warning at all. Same argument as `DamageNumbers.PUNCH_GAIN`.
const PUNCH_GAIN := 0.8
const PUNCH_DECAY := 5.0

## The vignette's red, because they answer the same hit and reading them as two
## separate events is the one thing that would make either harder to parse.
const COLOUR := Color(0.85, 0.12, 0.12)
const MAX_ALPHA := 0.8

## Dark edge, as a fraction of the frame's shorter side, and the same trick the
## damage numbers' outline is: it is what lets one colour survive a frame holding
## both a pale floor and a wall in shadow. It matters more here than there, since
## the mark has to be red to belong to the hit and this arena is red rock under a
## red sky — the one background red has nothing to be seen against. It widens the
## band both ways, so it is part of what the clearance is measured to — see
## `half_ink`.
const OUTLINE := 0.0045
const OUTLINE_COLOUR := Color(0.06, 0.0, 0.0)

## Same reasoning as `DamageNumbers.LIMIT`: merging already bounds this to about
## one per flank, and what the cap is actually here for is a blast catching the
## player between several things at once.
const LIMIT := 8


## One mark. `direction` is world space and never becomes a screen angle until
## the frame it is drawn on — see the note at the top.
class Mark extends RefCounted:
	var direction: Vector3
	var age: float = 0.0
	var punch: float = 0.0


var _marks: Array[Mark] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.player_damaged.connect(_on_player_damaged)
	# A mark that survives a respawn points at where the player was killed from,
	# in a world they are no longer standing in. Cleared on the way back rather
	# than on death, so the one that finished them is still up while they die.
	Events.player_respawned.connect(clear)


func _on_player_damaged(_amount: float, _health: float, _max_health: float,
		from: Vector3) -> void:
	if from.is_zero_approx():
		return
	var mark := _merged(from)
	if mark == null:
		while _marks.size() >= LIMIT:
			_marks.pop_front()
		mark = Mark.new()
		_marks.append(mark)
	# Re-aimed on every hit rather than kept at the first bearing, which is what
	# walks a mark round as an enemy circles instead of leaving it pointing at the
	# corner they opened from.
	mark.direction = from
	mark.age = 0.0
	mark.punch = 1.0


func _process(delta: float) -> void:
	if _marks.is_empty():
		visible = false
		return
	visible = true
	for index in range(_marks.size() - 1, -1, -1):
		var mark := _marks[index]
		mark.age += delta
		mark.punch = maxf(0.0, mark.punch - delta * PUNCH_DECAY)
		if mark.age >= LIFETIME:
			_marks.remove_at(index)
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var centre := size * 0.5
	var radius := radius_at(size)
	var shorter := minf(size.x, size.y)
	var thickness := THICKNESS * shorter
	for mark in _marks:
		var colour := COLOUR
		# Squared, as the damage numbers fade: a mark at half alpha is still
		# perfectly legible, so a linear fade spends most of its length looking
		# like nothing is happening and then blinks out at the end.
		var fade := 1.0 - mark.age / LIFETIME
		colour.a = MAX_ALPHA * fade * fade
		var bearing := bearing_of(mark.direction, camera)
		var band := thickness * (1.0 + mark.punch * PUNCH_GAIN)
		var edge := OUTLINE_COLOUR
		# Faded with the mark it edges, or the outline outlives it and the last
		# thing on screen is a dark sliver nothing put there.
		edge.a = colour.a
		draw_colored_polygon(_wedge(centre, bearing, radius,
				band + OUTLINE * shorter * 2.0), edge)
		draw_colored_polygon(_wedge(centre, bearing, radius, band), colour)


## Where a world direction lands on the ring, in screen angles: ahead is the top,
## behind is the bottom, and the player's right is the right. Taken off whichever
## camera is rendering rather than off `Player.rotation`, so the chase camera gets
## the bearings it sees rather than the ones the head sees.
##
## Flattened, because the mark is a bearing and elevation has nowhere to go on a
## ring. The camera's own forward is what gets flattened here — `from` arrived
## flat — and it degenerates only at a pitch the camera's ±1.45 clamp cannot
## reach; `basis.y` is the forward-most axis left at the bottom of that swing, so
## it is what the guard falls back on.
static func bearing_of(direction: Vector3, camera: Camera3D) -> float:
	var basis := camera.global_transform.basis
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if forward.length_squared() < 0.0001:
		forward = Vector3(basis.y.x, 0.0, basis.y.z)
	forward = forward.normalized()
	# The right-hand axis of a yaw-only frame whose -Z is `forward`.
	var right := Vector3(-forward.z, 0.0, forward.x)
	# Screen Y runs down, so "ahead" has to come out as -PI/2 rather than +PI/2 —
	# hence the negated forward component.
	return atan2(-forward.dot(direction), right.dot(direction))


## Half the fattest a mark's ink ever gets on a frame this size: the band at full
## punch, plus the outline that widens it further. Everything below is quoted
## against this rather than against the resting thickness, which is the lesson
## `SpeedLines` learned the moment its streaks stopped being a pixel wide — the
## distance that matters is the one to the *edge* of the ink and not to its
## centre line, and a mark is at its fattest on exactly the frame it appears.
static func half_ink(frame: Vector2) -> float:
	var shorter := minf(frame.x, frame.y)
	return THICKNESS * shorter * (1.0 + PUNCH_GAIN) * 0.5 + OUTLINE * shorter


## The middle of the band on a frame this size, pushed out far enough that the
## inner edge clears the reticle. The dev tools need the `_at` form for the same
## reason `SpeedLines` exposes one: a headless run renders into 64 pixels square,
## so the frame the geometry has to be right on is not the frame it is tested in.
static func radius_at(frame: Vector2) -> float:
	return maxf(RADIUS * minf(frame.x, frame.y), CENTRE_CLEAR + half_ink(frame))


## Pixels between the middle of the frame and the nearest ink a mark can put down.
## Kept at or above `CENTRE_CLEAR` by construction, and asserted by the smoke test
## — the failure it guards is a warning light growing out of the crosshair, which
## is not something a still frame makes obvious.
static func centre_clearance_at(frame: Vector2) -> float:
	return radius_at(frame) - half_ink(frame)


## The four-sided arc band one mark is drawn as, tapered to nothing at both ends.
## The taper is what makes it read as aimed at one bearing: a slab of ring with
## square ends is a mark that could be pointing anywhere along itself.
func _wedge(centre: Vector2, bearing: float, radius: float,
		thickness: float) -> PackedVector2Array:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var half_arc := deg_to_rad(ARC_DEGREES) * 0.5
	for step in ARC_STEPS + 1:
		var along := float(step) / float(ARC_STEPS)
		var angle := bearing + lerpf(-half_arc, half_arc, along)
		var reach := Vector2(cos(angle), sin(angle))
		var half := thickness * 0.5 * sin(along * PI)
		outer.append(centre + reach * (radius + half))
		inner.append(centre + reach * (radius - half))
	inner.reverse()
	outer.append_array(inner)
	return outer


## The mark a hit from this direction belongs on, or null for a new one.
func _merged(from: Vector3) -> Mark:
	for mark in _marks:
		if mark.direction.angle_to(from) <= MERGE_ANGLE:
			return mark
	return null


## How many marks are up. The dev tools read this rather than counting anything
## drawn, since a wedge leaves nothing behind to count.
func live_count() -> int:
	return _marks.size()


## Where a mark currently sits on the ring, in screen angles, for the dev tools —
## which have no other way to ask the one question that matters here, namely
## whether turning to face an attacker swings its mark round to the top.
func bearing_at(index: int) -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null or index < 0 or index >= _marks.size():
		return 0.0
	return bearing_of(_marks[index].direction, camera)


func clear() -> void:
	_marks.clear()
	queue_redraw()
