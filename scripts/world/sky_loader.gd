class_name SkyLoader
extends WorldEnvironment
## A WorldEnvironment that always has *a* sky, and upgrades to the real one once
## it has loaded.
##
## The environment's own `sky` is the fallback: the procedural colour gradient,
## which is built from a handful of colours, costs nothing, and is on screen from
## the first frame. If `sky_path` names a sky, it is loaded a few frames later
## and swapped in. Anything that goes wrong on the way — no path set, path
## missing, file is not a Sky, loader error — leaves the gradient in place and
## says why. There is no state in which the level renders an empty background.
##
## Set `sky_path` to res://resources/sky/arena_panorama.tres once there is real
## art in it. Empty — the current state — is a supported configuration, not a
## misconfiguration: it is what "no skybox implemented yet" looks like.
##
## The load is synchronous, deferred by a few frames rather than threaded.
## `ResourceLoader.load_threaded_request()` never completes for any resource with
## an `ext_resource` dependency in this build — including plain level scenes —
## so the threaded path cannot be used or tested. Deferring still gets the
## gradient up first, which is the point; what it does not do is hide the hitch
## of decoding a large panorama. If threaded loading starts working, this is the
## only file that has to change.

## Used only if the scene left `environment.sky` empty, so a level authored with
## no sky at all still comes up with the gradient rather than nothing.
const FALLBACK_SKY := "res://resources/sky/arena_dusk.tres"

## Frames to wait before loading. Long enough that the level's own load and first
## render are done, short enough that nobody sees the placeholder and thinks it
## is the final look.
const LOAD_DELAY_FRAMES := 3

enum State {
	FALLBACK,  ## Showing the gradient because nothing else was asked for.
	LOADING,   ## Gradient on screen, real sky not fetched yet.
	LOADED,    ## Real sky swapped in.
	FAILED,    ## Asked for a real sky, did not get one, kept the gradient.
}

## Fires once the sky is settled, whichever way it went. `sky` is whatever is on
## screen at that point, so a listener never has to handle null.
signal sky_resolved(sky: Sky, state: State)

## The sky to load. Leave empty to stay on the gradient.
@export_file("*.tres") var sky_path: String = ""

var state: State = State.FALLBACK
## Kept so a failed load can put things back exactly as they were.
var fallback_sky: Sky = null

var _frames_waited: int = 0


func _ready() -> void:
	# A paused tree must not strand the load: the pause menu is reachable within
	# a frame or two of the level appearing.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

	if environment == null:
		push_error("SkyLoader: no Environment assigned, nothing to put a sky on")
		return

	_ensure_fallback()

	if sky_path.is_empty():
		# The expected case while there is no sky art. Not a warning.
		_resolve(State.FALLBACK)
		return

	state = State.LOADING
	set_process(true)


## Guarantees there is something to fall back *to*. A level scene normally ships
## with the gradient already assigned; this only covers one that did not.
func _ensure_fallback() -> void:
	if environment.sky == null:
		environment.sky = ResourceLoader.load(FALLBACK_SKY) as Sky
		if environment.sky == null:
			push_error("SkyLoader: fallback %s failed to load" % FALLBACK_SKY)
	fallback_sky = environment.sky


func _process(_delta: float) -> void:
	_frames_waited += 1
	if _frames_waited < LOAD_DELAY_FRAMES:
		return
	set_process(false)
	_load_now()


## Split out so the delay can be skipped — the smoke test drives this directly
## rather than counting frames.
func _load_now() -> void:
	if not ResourceLoader.exists(sky_path):
		push_warning("SkyLoader: %s does not exist, staying on the gradient" % sky_path)
		_resolve(State.FAILED)
		return
	# The cast is the point: a sky_path aimed at some other kind of .tres loads
	# happily and would otherwise blank the background.
	var sky := ResourceLoader.load(sky_path) as Sky
	if sky == null:
		push_warning("SkyLoader: %s did not load as a Sky, staying on the gradient" % sky_path)
		_resolve(State.FAILED)
		return
	environment.sky = sky
	_resolve(State.LOADED)


func _resolve(new_state: State) -> void:
	set_process(false)
	state = new_state
	if new_state != State.LOADED and environment != null:
		environment.sky = fallback_sky
	sky_resolved.emit(null if environment == null else environment.sky, state)


func is_loading() -> bool:
	return state == State.LOADING


## True while the gradient is what is actually on screen — either because no real
## sky was asked for, one has not arrived, or one failed.
func showing_fallback() -> bool:
	return state != State.LOADED
