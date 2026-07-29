class_name DamageNumbers
extends Node3D
## Floating damage numbers over whatever the player is shooting.
##
## Fed by `Events.damage_dealt`, which only enemies emit — so a number is damage
## the player *dealt*. Damage taken is the vignette's job and is a different
## signal (`player_damaged`), which is what keeps the two from ever being
## confused for one another on screen.
##
## The decision worth knowing about is that numbers are merged **per target**
## rather than spawned per hit. The Shredder fires eleven times a second, so a
## label per shot is eleven "8"s a second climbing off one grunt, and a screen of
## them is a texture — something the eye takes in once and then stops reading,
## which is the same failure `SpeedLines` is few-and-fat to avoid. Hits on the
## same target inside `MERGE_WINDOW` therefore land on the number already up
## there: it counts up, punches on every hit, and only lets go and floats away
## once the shooting stops. Sustained fire produces about two numbers a second
## instead of eleven, and what each one finally reads is total damage into that
## target — which is the number the player wanted in the first place.
##
## Targets are keyed by instance id and never held as a reference. Each hit
## re-anchors the number to where it landed instead, which follows an enemy being
## knocked backwards for free and leaves nothing to dangle when one dies halfway
## through its own count.
##
## Everything here is driven from `_process`, so the node opts out of physics
## interpolation the way the dev capture rig's camera does: positions are written
## every rendered frame and there is nothing for the interpolator to smooth
## between. Without it every number is drawn lagging a tick behind the enemy it
## is anchored to.

## How long a number goes on accepting hits before it lets go and floats off.
## Long enough to swallow a burst, short enough that a held trigger still
## produces a visible beat rather than one digit ticking up forever.
const MERGE_WINDOW := 0.45
## And how long the float itself lasts once it has let go.
const RELEASE_TIME := 0.7

## Metres per second, while counting and once released. A held number barely
## climbs on purpose: one drifting away from the enemy it belongs to is a number
## the player has to go and find before they can read it.
const RISE_HELD := 0.35
const RISE_RELEASED := 1.6
## Sideways drift on release, measured along the *camera's* right rather than a
## world axis — from half the angles a fight can be watched from, a world axis
## reads as depth and the number appears to go nowhere. Consecutive numbers off
## one target alternate sides so they separate instead of stacking.
const DRIFT_RELEASED := 0.5

## Spawned this far above the hit point, which is what keeps a number clear of
## the impact flash the same hit just put there.
const SPAWN_LIFT := 0.35

## Same reasoning as `CombatFX.DECAL_LIMIT`, and far less likely to bite, since
## merging already bounds this to roughly one per live enemy. What it is actually
## here for is an explosion, which empties damage into every target in a radius on
## a single frame and is the one thing that can spawn a dozen at once.
const LIMIT := 24

## `fixed_size` is on, so these two are apparent size rather than world size: the
## pair works out at roughly a twentieth of the frame's height at any range, and
## because that is a fraction of the frame rather than a count of pixels it holds
## at 4K as well as at 720p.
const FONT_SIZE := 64
const PIXEL_SIZE := 0.0011
## Dark edge, in the same font's pixels. Numbers are drawn over a pale sky and a
## dark arena in the same frame, and the outline is the only reason they survive
## both — the same trick the HUD's notices use. Sized against the worst pairing
## rather than the average one, which is a crit: `COLOUR_CRIT` is orange and the
## grunts are red, so the outline is doing all of the work in the one case the
## colour is supposed to be shouting.
const OUTLINE_SIZE := 18

## Distant numbers shrink, but only this far. Some falloff is worth having as a
## depth cue; past it a number stops being readable, and an unreadable number is
## a smudge laid over a fight. Tuned off `shot_damage_numbers.png`, whose far
## target is out at forty metres for exactly this reason — at 0.62 it was a
## fifteen-pixel smear at 720p and the depth cue had eaten the number.
const FAR_DISTANCE := 45.0
const FAR_SCALE := 0.72

## Crits take the crosshair's own crit colour, so the reticle flash and the number
## that lands with it are visibly the same event rather than two notifications.
const COLOUR_HIT := Color(1.0, 0.88, 0.55)
const COLOUR_CRIT := Color(1.0, 0.45, 0.15)
const CRIT_SCALE := 1.35

## A scale spike on every hit that lands on a number already up. This is what
## makes a held trigger feel like it is connecting: without it a merged number is
## a digit quietly changing value, which is *less* feedback than the eleven
## separate labels it replaced rather than more.
const PUNCH_GAIN := 0.45
const PUNCH_DECAY := 6.0


## One number on screen. A plain record — the node owns all the behaviour, so
## there is one place to read the lifecycle rather than one per label.
class Entry extends RefCounted:
	var key: int = 0
	var label: Label3D
	var anchor: Vector3
	var total: float = 0.0
	var crit: bool = false
	## Time left in the merge window. Above zero it is still accepting hits.
	var held: float = 0.0
	## Time since it let go.
	var age: float = 0.0
	var rise: float = 0.0
	var punch: float = 0.0
	var drift: float = 1.0


var _live: Array[Entry] = []
var _spawned: int = 0


func _ready() -> void:
	# Written from `_process`, so there is nothing to interpolate and everything
	# to lose by trying — see the note at the top.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Events.damage_dealt.connect(_on_damage_dealt)


func _on_damage_dealt(target: Node, amount: float, is_crit: bool, at: Vector3) -> void:
	if amount <= 0.0:
		return
	var key := target.get_instance_id() if target != null else 0
	var entry := _held(key)
	if entry == null:
		entry = _make(key)
	entry.anchor = at + Vector3.UP * SPAWN_LIFT
	entry.total += amount
	entry.crit = entry.crit or is_crit
	entry.held = MERGE_WINDOW
	entry.punch = 1.0
	# Floored at 1: a hit that rounds to "0" reads as a weapon that did nothing,
	# which is a worse lie than the rounding.
	entry.label.text = "%d" % maxi(1, int(round(entry.total)))


func _process(delta: float) -> void:
	if _live.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	var right := camera.global_transform.basis.x if camera != null else Vector3.RIGHT
	var eye := camera.global_position if camera != null else Vector3.ZERO

	# Backwards, because released numbers are removed from this array as they go.
	for index in range(_live.size() - 1, -1, -1):
		var entry := _live[index]
		entry.punch = maxf(0.0, entry.punch - delta * PUNCH_DECAY)

		var alpha := 1.0
		if entry.held > 0.0:
			entry.held -= delta
			entry.rise += RISE_HELD * delta
		else:
			entry.age += delta
			if entry.age >= RELEASE_TIME:
				entry.label.queue_free()
				_live.remove_at(index)
				continue
			entry.rise += RISE_RELEASED * delta
			# Squared rather than linear: a number at half alpha is still perfectly
			# legible, so a linear fade spends most of its length looking like
			# nothing is happening and then blinks out at the end.
			alpha = 1.0 - entry.age / RELEASE_TIME
			alpha *= alpha

		var slide := entry.drift * DRIFT_RELEASED * clampf(entry.age / RELEASE_TIME, 0.0, 1.0)
		entry.label.global_position = entry.anchor + Vector3.UP * entry.rise + right * slide

		var colour := COLOUR_CRIT if entry.crit else COLOUR_HIT
		colour.a = alpha
		entry.label.modulate = colour
		entry.label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85 * alpha)
		entry.label.scale = Vector3.ONE * _scale_of(entry, eye)


## Apparent size: the distance falloff, the crit bump and the per-hit punch, all
## multiplied together. `fixed_size` means this is a screen-space multiplier
## rather than a world one, so it is the whole story about how big a number looks.
func _scale_of(entry: Entry, eye: Vector3) -> float:
	var distance := entry.label.global_position.distance_to(eye)
	var falloff := lerpf(1.0, FAR_SCALE, clampf(distance / FAR_DISTANCE, 0.0, 1.0))
	var crit := CRIT_SCALE if entry.crit else 1.0
	return falloff * crit * (1.0 + entry.punch * PUNCH_GAIN)


## The number currently accepting hits for this target, if there is one. Searched
## from the back: a target shot again after an earlier number let go has two on
## screen, and the live one is always the newer.
func _held(key: int) -> Entry:
	for index in range(_live.size() - 1, -1, -1):
		var entry := _live[index]
		if entry.key == key and entry.held > 0.0:
			return entry
	return null


func _make(key: int) -> Entry:
	# Oldest out first, as with bullet holes. No fade on the way out — a number is
	# a transient anyway, and one being evicted is already the least interesting
	# thing on a screen busy enough to hit the cap.
	while _live.size() >= LIMIT:
		var oldest := _live.pop_front() as Entry
		oldest.label.queue_free()

	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Constant apparent size, so a number is as readable across the arena as it is
	# point blank, and the distance cue is `FAR_SCALE`'s to give deliberately
	# rather than the perspective divide's to take.
	label.fixed_size = true
	label.font_size = FONT_SIZE
	label.pixel_size = PIXEL_SIZE
	label.outline_size = OUTLINE_SIZE
	# Drawn over the enemy rather than through it. A number anchored on a hit point
	# is *inside* the body that was hit, so depth-testing buries every number the
	# player is closest to — which is every number that matters.
	label.no_depth_test = true
	label.shaded = false
	add_child(label)

	var entry := Entry.new()
	entry.key = key
	entry.label = label
	# Alternating rather than random, so two numbers off one target always part
	# instead of sometimes picking the same side and sometimes drifting nowhere.
	entry.drift = 1.0 if _spawned % 2 == 0 else -1.0
	_spawned += 1
	_live.append(entry)
	return entry


## How many numbers are on screen. The dev tools read this rather than counting
## children, which would also catch the ones queued for deletion this frame.
func live_count() -> int:
	return _live.size()


## Drops everything on screen at once. Nothing in a fight needs it — numbers
## expire on their own — but a dev tool starting a fresh measurement does, and
## freeing the labels from outside would leave `_live` holding records that point
## at nothing for `_process` to walk into.
func clear() -> void:
	for entry in _live:
		entry.label.queue_free()
	_live.clear()
