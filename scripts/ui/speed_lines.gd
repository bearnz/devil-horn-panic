class_name SpeedLines
extends Control
## Wind tearing past the camera while the player dashes. Drawn rather than
## textured, like the crosshair, so it needs no art.
##
## A dash is 0.32s of the player being thrown along a line, and until this went in
## the only things that said so were the weapon lagging back and the legs streaming
## out behind — both of which are at the bottom of the frame, and neither of which
## is where the player is looking. This is the same information across the whole
## screen: streaks radiating out of the point being travelled towards, which is what
## optical flow does when you are moved and is the reason the effect reads as thrust
## rather than as a filter.
##
## Everything here is quoted as a fraction of the frame rather than in pixels, apart
## from the one clearance that protects the reticle — the crosshair is authored in
## pixels too, so a clearance from it is a pixel measurement or it is nothing.

## How far out the streaks live, as a fraction of the way from the focus to the edge
## of the frame. They start beyond the inner one and run out past the outer one,
## which is off the edge — a streak is meant to leave the screen rather than stop on
## it.
const INNER := 0.36
const OUTER := 1.30
## Length of a streak as a fraction of that same reach, before it is scaled by how
## far along its run it is. Long enough that the longest of them are a third of the
## way from the focus to the corner: below about 0.2 a streak is a tick mark, and a
## screen full of tick marks reads as noise on the lens rather than as air going
## past. The top end is bounded by the run itself — a streak that outgrows the
## distance it travels stops being drawn *along* its path and becomes a static
## spoke that merely fades.
const LENGTH_MIN := 0.24
const LENGTH_MAX := 0.60
## Runs a streak completes per second, and the spread of per-streak rates around it.
## Anything close to uniform reads as a spinning wheel rather than as wind.
const STREAM_RATE := 1.5
const RATE_MIN := 0.75
const RATE_MAX := 1.45
## Few enough that each one is a thing the player sees go past rather than part of
## a field. This trades directly against the two lengths above: seventy-odd short
## thin streaks are a texture, and a texture is something the eye takes in whole and
## then ignores, which is how the first cut managed to be busy and unnoticeable at
## the same time. Thirty fat ones cross the frame individually.
const STREAK_COUNT := 30

## How far the focus is allowed off the middle of the frame, as a fraction of the
## shorter side, before the clearance below overrides it.
const FOCUS_SHIFT := 0.22
## Pixels of the middle of the screen no streak may start inside. The crosshair's
## arms reach about fourteen from centre and its hit marks a little further, and a
## streak striking out of the reticle is the HUD reporting a hit that never landed.
const CENTRE_CLEAR := 46.0

## Up in about a twentieth of a second, out over a third of one. Asymmetric on
## purpose: a dash is short enough that a symmetric fade would still be rising when
## it ended, and the trailing half is what carries the sense of having been thrown
## somewhere rather than merely of having arrived.
const RISE_RATE := 18.0
const FALL_RATE := 3.0

## Thickness of a streak at the middle of its run, as a fraction of the frame's
## shorter side, scaled by the same roll that sets its length — so the long ones are
## also the heavy ones and the field has a foreground. A fraction rather than pixels
## because this is now big enough to notice being wrong: three pixels at 720p is a
## line and three at 4K is a scratch.
const WIDTH_MIN := 0.0055
const WIDTH_MAX := 0.0115

const COLOUR := Color(0.72, 0.88, 1.0)
## Peak alpha of a streak at the middle of its run. High enough to be felt on a
## bright wall, low enough that the arena is never hidden behind it — this fires
## while the player is moving fastest and most likely to be shot at. It is the one
## number that did *not* go up with the size: fewer, fatter streaks already cover
## more of the frame, and the brief was louder wind rather than a paler picture.
const MAX_ALPHA := 0.62

var player: Player

## Angle, phase offset, rate multiplier, length fraction — one Vector4 per streak,
## rolled once from a fixed seed. Fixed because these are the *same* streaks every
## frame: re-rolling them per redraw is static rather than motion, and re-rolling
## them per dash makes every dash look subtly different for no reason anyone can
## name.
var _streaks: Array[Vector4] = []
var _time: float = 0.0
var _intensity: float = 0.0
## Where the streaks radiate from, and whether they radiate at all. Both are read
## off the dash while it runs and then *left alone*, because `dash_direction()`
## returns zero the moment the dash ends and the effect outlives it by a third of a
## second — the same latching the weapon's dash lag needs, for the same reason.
var _focus: Vector2 = Vector2.ZERO
## A dash backwards has its vanishing point behind the player, so what the screen
## shows is flow *converging* on the middle of the frame instead of leaving it.
var _inward: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_focus = size * 0.5

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED
	for i in STREAK_COUNT:
		# Angles are jittered around an even fan rather than drawn at random: pure
		# random leaves gaps and clumps that read as a pattern, which is the one
		# thing this must not have.
		var angle := TAU * (float(i) + rng.randf_range(-0.4, 0.4)) / float(STREAK_COUNT)
		_streaks.append(Vector4(angle, rng.randf(),
				rng.randf_range(RATE_MIN, RATE_MAX),
				rng.randf_range(LENGTH_MIN, LENGTH_MAX)))


func _process(delta: float) -> void:
	var dashing := is_instance_valid(player) and player.is_dashing()
	if dashing:
		_read_heading()
	_intensity = move_toward(_intensity, 1.0 if dashing else 0.0,
			delta * (RISE_RATE if dashing else FALL_RATE))
	if _intensity <= 0.0:
		visible = false
		return
	visible = true
	_time += delta
	queue_redraw()


## 0 at rest, 1 mid-dash, eased. Exposed for the dev tools, which have no other way
## to ask whether the screen is doing anything.
func intensity() -> float:
	return _intensity


## The point on screen the streaks radiate out of.
func focus() -> Vector2:
	return _focus


## True while the flow runs *into* that point rather than out of it, which is a
## dash backwards. Latched with the focus, and read by `MotionBlur` so the smear
## and the streaks can never disagree about which way the world is going.
func inward() -> bool:
	return _inward


## Pixels between the middle of the frame and the nearest point any streak can be
## drawn at, as currently drawn. Kept positive by construction — see `focus_at` —
## and asserted by the smoke test, because the failure it guards against is a HUD
## effect striking out of the crosshair rather than anything that looks wrong on
## its own.
func centre_clearance() -> float:
	return centre_clearance_at(size)


## The same question about a frame of a stated size. The dev tools need this one:
## a headless run renders into 64 pixels square, where the budget below is zero and
## the focus can never leave the middle — so the frame the geometry has to be right
## on is not the frame the tests are run in.
func centre_clearance_at(frame: Vector2) -> float:
	return _inner_radius(frame) - focus_at(frame).distance_to(frame * 0.5)


## Distance from the focus to the nearest *ink*, on a frame this size. The inner
## ring is where a streak's centre line starts; half of the fattest one reaches
## further in than that, which was rounding error while the lines were a pixel wide
## and is not any more. One function so the bound `focus_at` spends and the
## clearance the smoke test reads can never be computed from different ideas of
## where the field begins.
func _inner_radius(frame: Vector2) -> float:
	return (INNER - WIDTH_MAX) * minf(frame.x, frame.y) * 0.5


## Where the streaks would radiate from on a frame this size, given the dash the
## player is in right now: the point being travelled towards, in the frame of
## whichever camera is actually rendering — so the chase camera gets the flow it
## sees rather than the flow the head sees.
func focus_at(frame: Vector2) -> Vector2:
	var centre := frame * 0.5
	if not is_instance_valid(player):
		return centre
	var heading := player.dash_direction()
	var camera := get_viewport().get_camera_3d()
	if heading.is_zero_approx() or camera == null:
		return centre
	# Screen Y runs down, so the vertical component is negated. A flat dash still has
	# one: look at the floor and the way forward is down the screen.
	var basis := camera.global_transform.basis
	var shift := Vector2(basis.x.dot(heading), -basis.y.dot(heading)) \
			* minf(frame.x, frame.y) * FOCUS_SHIFT
	# The reticle wins. Bounding the offset here rather than clipping the streaks
	# later is what keeps the guarantee a single number instead of a special case per
	# line, and it is the shorter half-size that bounds it because the inner ring is
	# an ellipse the shape of the frame and its short axis is the tight one. On a
	# frame small enough that the ring is inside the clearance the budget is zero and
	# the focus simply stays put: less wind, still a readable crosshair.
	return centre + shift.limit_length(maxf(0.0, _inner_radius(frame) - CENTRE_CLEAR))


## Latches this frame's focus and which way the flow runs. Re-read every frame of
## the dash rather than taken once at the start, which is what makes turning
## mid-dash swing the streaks round with the view instead of dragging a fixed
## pattern across the screen.
func _read_heading() -> void:
	var heading := player.dash_direction()
	var camera := get_viewport().get_camera_3d()
	if heading.is_zero_approx() or camera == null:
		return
	_inward = -camera.global_transform.basis.z.dot(heading) < 0.0
	_focus = focus_at(size)


func _draw() -> void:
	if _intensity <= 0.0:
		return
	var half := size * 0.5
	for streak in _streaks:
		# Where the frame's edge is in this streak's direction. An ellipse the shape
		# of the viewport rather than a circle, so the streaks reach the sides and the
		# top at the same point in their run and the field does not read as a disc
		# pasted over a widescreen frame.
		var reach := Vector2(cos(streak.x) * half.x, sin(streak.x) * half.y)
		var phase := fposmod(streak.y + _time * STREAM_RATE * streak.z, 1.0)
		# Squared, so a streak accelerates as it goes: the giveaway of a fake is
		# lines sliding outward at a constant rate, which is a screen wipe. Reversed
		# for a backwards dash, where flow converges and slows as it approaches the
		# point ahead.
		var travel := (1.0 - phase * phase) if _inward else (phase * phase)
		var near := lerpf(INNER, OUTER, travel)
		var length := streak.w * (0.4 + 0.6 * travel) * _intensity

		var colour := COLOUR
		# Sine over the run, so a streak is invisible at both ends of it and nothing
		# is ever seen appearing or being recycled.
		colour.a = sin(phase * PI) * MAX_ALPHA * _intensity
		var heft := (streak.w - LENGTH_MIN) / (LENGTH_MAX - LENGTH_MIN)
		draw_line(_focus + reach * near, _focus + reach * (near + length), colour,
				lerpf(WIDTH_MIN, WIDTH_MAX, heft) * minf(size.x, size.y))
