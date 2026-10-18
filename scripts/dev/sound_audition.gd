extends Node
## Plays the candidate sound effects in `assets/audio/candidates/` so one can be
## picked per game event, and writes the picks out as JSON.
##
##   godot --path . res://scenes/dev/sound_audition.tscn
##
## Nothing in the game reads a sound yet. This is the step before that: 143
## candidates arrived from two CC0 libraries and the only way to choose between
## them is to hear them, in groups, against each other. It writes
## `assets/audio/picks.json` — event id to file name — which is what an audio
## system would later be built to consume.
##
## Two things it does that a file browser cannot, and they are the reason it
## exists rather than a folder of files being handed over.
##
## **It compares rather than plays.** `A` walks every candidate for the selected
## event with a gap between them, because a sound effect has no absolute quality
## — it is only ever better or worse than the other four, and judging them one
## Explorer double-click at a time means holding the last one in your head while
## the next loads.
##
## **It repeats at the rate the weapon actually fires.** The Shredder's
## `fire_rate` is 11/s, so its sound is heard for 90 milliseconds before the next
## one starts on top of it: a candidate that is lovely once is a wall of noise
## held down, and a tail longer than the interval is thirteen tails overlapping.
## `F` holds the trigger down at the real interval read off the weapon's own
## .tres, which is the only way that failure shows up before it is wired in. That
## needs voices that overlap, hence the pool — one `AudioStreamPlayer` restarted
## eleven times a second is a stutter, not a burst, and would make every
## candidate sound equally bad.

const CANDIDATE_DIR := "res://assets/audio/candidates"
const PICKS_PATH := "res://assets/audio/picks.json"

## Extensions Godot imports as audio. `.import` siblings and anything else in the
## folder are skipped.
const AUDIO_EXTENSIONS := ["ogg", "wav", "mp3"]

## Voices for the burst preview. The Shredder fires 11/s and its candidates run
## to about a second, so a shot has to survive roughly a dozen more starting on
## top of it.
const VOICES := 16

## Seconds between candidates when auditioning a whole event, on top of the
## length of the one playing. Long enough to tell two apart, short enough that
## the first is still in mind when the last arrives.
const COMPARE_GAP := 0.25

## Which weapon's fire rate drives the burst preview, per event. Read off the
## .tres rather than copied, so a weapon retuned in the editor is auditioned at
## its new rate without this file being touched.
const BURST_WEAPONS := {
	"10_fire_sidearm": "res://resources/weapons/sidearm.tres",
	"11_fire_shredder": "res://resources/weapons/shredder.tres",
	"12_fire_hellmouth": "res://resources/weapons/hellmouth.tres",
}

## Fallback interval for events with no weapon behind them, so `F` still does
## something on a footstep or an impact.
const DEFAULT_BURST_INTERVAL := 0.35

var _events: Array[String] = []
var _candidates: Dictionary = {}  # event -> Array[String] of file names
var _picks: Dictionary = {}  # event -> file name
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0

var _event_index := 0
var _candidate_index := 0

## Set while `A` is walking an event, so a second press stops it rather than
## starting a second walk over the top of the first.
var _comparing := false
var _burst_time := 0.0

@onready var _event_list := ItemList.new()
@onready var _candidate_list := ItemList.new()
@onready var _status := RichTextLabel.new()


func _ready() -> void:
	_scan()
	if _events.is_empty():
		push_error("sound_audition: nothing under %s" % CANDIDATE_DIR)
		get_tree().quit(1)
		return

	var total := 0
	for event: String in _events:
		total += (_candidates[event] as Array).size()
	print("sound_audition: %d events, %d candidates" % [_events.size(), total])

	_load_picks()
	_build_ui()
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)

	_refresh_events()
	_select_event(0)


# --- Scanning ----------------------------------------------------------------


## Every folder under the candidate directory is an event and every audio file in
## it is a candidate — same "content is data" arrangement as perks and levels, so
## dropping another candidate in means it shows up on the next run.
func _scan() -> void:
	var root := DirAccess.open(CANDIDATE_DIR)
	if root == null:
		return
	var names := root.get_directories()
	names.sort()
	for event: String in names:
		# A leading underscore marks a folder of things to listen to that are not
		# things to choose between — `_reference/` holds real automatic-weapon
		# bursts, which are what a Shredder candidate under `F` is being judged
		# *against* and would be nonsense to pick as its fire sound. Listed as an
		# event and they would sit in the count forever unpicked.
		if event.begins_with("_"):
			continue
		var files := _audio_files("%s/%s" % [CANDIDATE_DIR, event])
		if files.is_empty():
			continue
		_events.append(event)
		_candidates[event] = files


func _audio_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file: String in dir.get_files():
		# Running from source the folder also holds the .import sidecars Godot
		# writes, which are not playable and must not become rows.
		if file.ends_with(".import"):
			continue
		if AUDIO_EXTENSIONS.has(file.get_extension().to_lower()):
			found.append(file)
	found.sort()
	return found


# --- UI ----------------------------------------------------------------------


func _build_ui() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 12)
	root.add_theme_constant_override("margin_right", 12)
	root.add_theme_constant_override("margin_top", 12)
	root.add_theme_constant_override("margin_bottom", 12)
	add_child(root)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	root.add_child(rows)

	var help := Label.new()
	help.text = ("up/down candidate   left/right event   space play   " +
		"A compare all   F burst at fire rate   1-9 pick   S save   Esc quit")
	help.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	rows.add_child(help)

	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.split_offset = 320
	rows.add_child(columns)

	# Neither list may take focus. A focused ItemList eats the arrows and
	# ui_accept before `_unhandled_key_input` sees them, so clicking a row once
	# turned up/down into silent moves and space — "replay" — into a pick that
	# overwrote picks.json. Clicks still select and a double-click still picks.
	_event_list.focus_mode = Control.FOCUS_NONE
	_candidate_list.focus_mode = Control.FOCUS_NONE

	_event_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event_list.item_selected.connect(_select_event)
	columns.add_child(_event_list)

	_candidate_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_candidate_list.item_selected.connect(_select_candidate)
	_candidate_list.item_activated.connect(_pick_at)
	columns.add_child(_candidate_list)

	_status.fit_content = true
	_status.custom_minimum_size = Vector2(0, 56)
	_status.bbcode_enabled = true
	rows.add_child(_status)


func _refresh_events() -> void:
	var selected := _event_list.get_selected_items()
	_event_list.clear()
	for event: String in _events:
		# A tick beside an event is the whole progress report — with 35 of them
		# the question between sittings is only ever which are still open.
		var mark := "OK " if _picks.has(event) else "   "
		_event_list.add_item("%s%s" % [mark, event])
	if selected.size() > 0 and selected[0] < _event_list.item_count:
		_event_list.select(selected[0])


func _refresh_candidates() -> void:
	_candidate_list.clear()
	var event := _events[_event_index]
	var picked: String = String(_picks.get(event, ""))
	for file: String in _candidates[event]:
		var mark := " <- picked" if file == picked else ""
		_candidate_list.add_item("%s%s" % [file, mark])
	if _candidate_index < _candidate_list.item_count:
		_candidate_list.select(_candidate_index)


func _refresh_status() -> void:
	var event := _events[_event_index]
	var files: Array = _candidates[event]
	var done := _picks.size()
	_status.text = ("[b]%s[/b]   %d candidates   burst interval %.3fs\n" +
		"picked %d of %d events   ->  %s") % [
			event, files.size(), _burst_interval(event), done, _events.size(),
			String(_picks.get(event, "(nothing yet)")),
		]


# --- Selection ---------------------------------------------------------------


func _select_event(index: int) -> void:
	_event_index = clampi(index, 0, _events.size() - 1)
	_candidate_index = 0
	_comparing = false
	if _event_list.get_selected_items() != PackedInt32Array([_event_index]):
		_event_list.select(_event_index)
	_refresh_candidates()
	_refresh_status()


func _select_candidate(index: int) -> void:
	_candidate_index = index
	_refresh_status()


func _step_event(delta: int) -> void:
	_select_event(wrapi(_event_index + delta, 0, _events.size()))


func _step_candidate(delta: int) -> void:
	var count: int = (_candidates[_events[_event_index]] as Array).size()
	_candidate_index = wrapi(_candidate_index + delta, 0, count)
	_candidate_list.select(_candidate_index)
	_refresh_status()
	# Stepping is how a candidate is chosen, so stepping plays it — a review with
	# a play button between every comparison is a review nobody finishes.
	_play(_candidate_index)


# --- Playback ----------------------------------------------------------------


func _stream_at(index: int) -> AudioStream:
	var event := _events[_event_index]
	var files: Array = _candidates[event]
	if index < 0 or index >= files.size():
		return null
	return load("%s/%s/%s" % [CANDIDATE_DIR, event, String(files[index])]) as AudioStream


## Round-robin so a burst overlaps itself the way it would in game rather than
## cutting its own tail off.
func _play(index: int) -> void:
	var stream := _stream_at(index)
	if stream == null:
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.play()


func _stop_all() -> void:
	for voice: AudioStreamPlayer in _voices:
		voice.stop()


## Walk every candidate for this event back to back. The comparison is the point:
## these were curated to be different from each other, and "different" is only
## audible in sequence.
func _compare_all() -> void:
	if _comparing:
		_comparing = false
		return
	_comparing = true
	var event := _events[_event_index]
	var files: Array = _candidates[event]
	for i in files.size():
		if not _comparing or event != _events[_event_index]:
			break
		_candidate_index = i
		_candidate_list.select(i)
		_refresh_status()
		_play(i)
		var stream := _stream_at(i)
		var length := stream.get_length() if stream != null else 0.5
		await get_tree().create_timer(maxf(length, 0.1) + COMPARE_GAP).timeout
	_comparing = false


## The weapon's real fire interval where there is a weapon, so the burst is the
## one the player would hear. Read live off the .tres — a rate changed in the
## editor changes what this plays without this file knowing.
func _burst_interval(event: String) -> float:
	if not BURST_WEAPONS.has(event):
		return DEFAULT_BURST_INTERVAL
	var data := load(String(BURST_WEAPONS[event])) as WeaponData
	if data == null or data.fire_rate <= 0.0:
		return DEFAULT_BURST_INTERVAL
	return 1.0 / data.fire_rate


func _process(delta: float) -> void:
	if not Input.is_key_pressed(KEY_F):
		_burst_time = 0.0
		return
	_burst_time -= delta
	if _burst_time <= 0.0:
		_burst_time += _burst_interval(_events[_event_index])
		_play(_candidate_index)


# --- Picking and saving ------------------------------------------------------


func _pick_at(index: int) -> void:
	var event := _events[_event_index]
	var files: Array = _candidates[event]
	if index < 0 or index >= files.size():
		return
	_picks[event] = String(files[index])
	_candidate_index = index
	_refresh_events()
	_refresh_candidates()
	_refresh_status()
	_save_picks()


func _load_picks() -> void:
	if not FileAccess.file_exists(PICKS_PATH):
		return
	var file := FileAccess.open(PICKS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_picks = parsed


## Written on every pick rather than on exit, because the thing this tool is used
## for is a long sitting with headphones on and the way it ends is Alt+F4.
func _save_picks() -> void:
	var file := FileAccess.open(PICKS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("sound_audition: cannot write %s" % PICKS_PATH)
		return
	var ordered := {}
	for event: String in _events:
		if _picks.has(event):
			ordered[event] = _picks[event]
	file.store_string(JSON.stringify(ordered, "\t", false) + "\n")
	file.close()
	print("picks -> %s (%d of %d)" % [PICKS_PATH, ordered.size(), _events.size()])


# --- Input -------------------------------------------------------------------


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			_save_picks()
			get_tree().quit()
		KEY_DOWN:
			_step_candidate(1)
		KEY_UP:
			_step_candidate(-1)
		KEY_RIGHT:
			_step_event(1)
		KEY_LEFT:
			_step_event(-1)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_play(_candidate_index)
		KEY_A:
			_compare_all()
		KEY_S:
			_save_picks()
		KEY_BACKSPACE, KEY_DELETE:
			_picks.erase(_events[_event_index])
			_refresh_events()
			_refresh_candidates()
			_refresh_status()
			_save_picks()
		KEY_PERIOD:
			_stop_all()
		_:
			if key.keycode >= KEY_1 and key.keycode <= KEY_9:
				_pick_at(key.keycode - KEY_1)
	get_viewport().set_input_as_handled()
