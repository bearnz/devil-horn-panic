class_name MotionBlur
extends BackBufferCopy
## Radial smear across the frame while the player dashes. The other half of the
## wind — `SpeedLines` draws what the air is doing, this does the same thing to
## what is behind it.
##
## Godot's Forward+ renderer has no motion blur, and per-object velocity buffers
## are not worth having for one 0.32s move, so this is the cheap honest version: a
## copy of the screen smeared back towards the point being travelled towards. That
## point is the dash's vanishing point, so the smear is zero in the middle of the
## frame and longest at the edges, which is exactly where a moving eye loses
## detail — and it is why this reads as speed rather than as the picture going
## soft.
##
## A `BackBufferCopy` rather than a plain `ColorRect` because a canvas shader can
## only read the screen through the back buffer, and the copy has to happen after
## the 3D scene has been drawn and before this reads it. Node order is what says
## so: this sits **first** in the HUD, so everything below it in the tree — the
## vignette, the streaks, the crosshair, the numbers — is drawn on top of the
## smear rather than into it. A blurred crosshair would be a bug that only ever
## showed up in screenshots.
##
## The copy is switched off outright when nothing is dashing. It is a full-frame
## read and there is no reason to pay for it while standing still.

## Longest smear, as the fraction of the way back to the focus that the last tap
## reaches. It scales with distance from the focus, so this is what the corners of
## the frame get and the middle gets almost none of it — about 40px in a 1280-wide
## frame, which is a smear you feel and do not catch.
const MAX_SMEAR := 0.042
## How the smear follows the wind. Squared-ish rather than linear, because the
## wind is deliberately slow to fade and a blur that lingers the same way stops
## reading as speed and starts reading as a dirty lens. It also holds the smear
## off the first frames of the ramp, where a dash is not yet fast enough to earn
## one.
const FOLLOW_EXPONENT := 2.2
## Fraction of the frame *height* around the middle that stays sharp, and the band
## over which the smear comes in past it. The crosshair is drawn on top of this
## and can never itself blur, but what the player is aiming *at* can — and a
## target that softens the moment you dash is the HUD taking away the one thing
## the dash was for.
const CLEAR_RADIUS := 0.11
const CLEAR_FALLOFF := 0.30

## The streaks. Read for the focus, the intensity and which way the flow runs, so
## the two halves of the effect can never disagree about where the player is going.
var wind: SpeedLines

var _screen: ColorRect
var _material := ShaderMaterial.new()

const SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
// Where the flow comes out of, in screen UV.
uniform vec2 focus = vec2(0.5);
// Fraction of the way back to the focus the last tap reaches, at this pixel.
uniform float strength = 0.0;
// +1 radiating out of the focus, -1 converging on it — a dash backwards.
uniform float direction = 1.0;
// Frame width over height, so the sharp middle is a circle in pixels rather than
// an ellipse in UV.
uniform float aspect = 1.777;
uniform float clear_radius = 0.11;
uniform float clear_falloff = 0.30;

const int TAPS = 6;

void fragment() {
	float from_centre = length((SCREEN_UV - vec2(0.5)) * vec2(aspect, 1.0));
	float gate = smoothstep(clear_radius, clear_radius + clear_falloff, from_centre);
	vec2 flow = (SCREEN_UV - focus) * strength * direction * gate;
	vec4 sum = texture(screen_tex, SCREEN_UV);
	for (int i = 1; i < TAPS; i++) {
		sum += texture(screen_tex, SCREEN_UV - flow * (float(i) / float(TAPS - 1)));
	}
	COLOR = sum / float(TAPS);
}
"""


func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material.shader = shader
	_material.set_shader_parameter("clear_radius", CLEAR_RADIUS)
	_material.set_shader_parameter("clear_falloff", CLEAR_FALLOFF)

	# Built here rather than in the scene for the same reason the view models are:
	# there is nothing to author. A child, because the back buffer has to be copied
	# before whatever reads it is drawn, and a child draws after its parent.
	_screen = ColorRect.new()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.material = _material
	add_child(_screen)

	copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	visible = false


func _process(_delta: float) -> void:
	var amount := 0.0
	if is_instance_valid(wind):
		amount = pow(clampf(wind.intensity(), 0.0, 1.0), FOLLOW_EXPONENT)
	if amount <= 0.0:
		if visible:
			visible = false
			copy_mode = BackBufferCopy.COPY_MODE_DISABLED
		return

	visible = true
	copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT

	var frame := get_viewport_rect().size
	frame = Vector2(maxf(1.0, frame.x), maxf(1.0, frame.y))
	_screen.position = Vector2.ZERO
	_screen.size = frame
	# The streaks' focus is in pixels on the same frame this covers, so this is a
	# straight divide — and it is the same latched value, so the smear and the
	# streaks come out of one point even on the frames after the dash has ended and
	# `dash_direction()` has gone quiet.
	_material.set_shader_parameter("focus", wind.focus() / frame)
	_material.set_shader_parameter("strength", MAX_SMEAR * amount)
	_material.set_shader_parameter("direction", -1.0 if wind.inward() else 1.0)
	_material.set_shader_parameter("aspect", frame.x / frame.y)


## How much smear is on the frame right now, 0 to 1. For the dev tools: a shader
## parameter is write-only from here, so this is the only thing that can say
## whether the screen is being blurred.
func amount() -> float:
	if not is_instance_valid(wind):
		return 0.0
	return pow(clampf(wind.intensity(), 0.0, 1.0), FOLLOW_EXPONENT)
