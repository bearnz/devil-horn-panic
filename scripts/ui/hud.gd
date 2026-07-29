class_name HUD
extends CanvasLayer
## Combat HUD. Everything it shows arrives through `Events` or is polled from
## the player reference handed over by `main.gd`.

const MAX_NOTICES := 5

## Ammo states the counter can be in, worst last. `ammo_alert()` reports it, which
## is the property worth testing — the colour is taste and the state is not.
const AMMO_OK := 0
const AMMO_LOW := 1
const AMMO_EMPTY := 2

## What counts as low: a fraction of the magazine, floored at one round so a
## four-round Hellmouth is not permanently shouting. The point of the cue is to
## answer "reload now or after this fight" before the trigger has already
## answered it, which is the one thing the plain number cannot do from the corner
## of an eye.
const LOW_AMMO_FRACTION := 0.3
const LOW_AMMO_COLOUR := Color(1.0, 0.72, 0.22)
const EMPTY_AMMO_COLOUR := Color(1.0, 0.34, 0.28)
## Pulses per second, and how far towards white the pulse takes it. One channel —
## brightness on a coloured label — because two would be the mistake the vignette
## and the damage marks are kept apart to avoid: the colour says how bad and the
## pulse is what makes it catch the eye, and neither is carrying its own message.
const AMMO_PULSE_RATE := 3.6
const AMMO_PULSE_DEPTH := 0.45

var player: Player

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _dash_bar: ProgressBar = %DashBar
@onready var _ammo_label: Label = %AmmoLabel
@onready var _weapon_label: Label = %WeaponLabel
@onready var _reload_bar: ProgressBar = %ReloadBar
@onready var _level_label: Label = %LevelLabel
@onready var _xp_bar: ProgressBar = %XPBar
@onready var _scrap_label: Label = %ScrapLabel
@onready var _wave_label: Label = %WaveLabel
@onready var _points_label: Label = %PointsLabel
@onready var _prompt_label: Label = %InteractPrompt
@onready var _notices: VBoxContainer = %NoticeList
@onready var _vignette: ColorRect = %Vignette
@onready var _crosshair: Crosshair = %Crosshair
@onready var _speed_lines: SpeedLines = %SpeedLines
@onready var _motion_blur: MotionBlur = %MotionBlur

var _reload_total: float = 0.0
var _reload_left: float = 0.0
## Latched off the last `ammo_changed` rather than polled, so the pulse below is
## the only thing this costs per frame.
var _ammo_alert: int = AMMO_OK
var _ammo_pulse: float = 0.0


func _ready() -> void:
	# Two handlers rather than one shared with `player_healed`: damage carries a
	# direction now and healing has nowhere to have come from, so the signatures
	# have parted. Both still fall through to the same bar refresh.
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_healed.connect(_on_player_health)
	Events.ammo_changed.connect(_on_ammo_changed)
	Events.weapon_equipped.connect(_on_ammo_changed)
	Events.reload_started.connect(_on_reload_started)
	Events.reload_finished.connect(_on_reload_finished)
	Events.xp_gained.connect(func(_amount: int) -> void: _refresh_progression())
	Events.level_up.connect(_on_level_up)
	Events.scrap_changed.connect(func(_total: int) -> void: _refresh_progression())
	Events.stats_changed.connect(_refresh_progression)
	Events.damage_dealt.connect(_on_damage_dealt)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_cleared.connect(func(index: int) -> void:
		_wave_label.text = "Wave %d cleared" % index)
	Events.notice.connect(push_notice)
	Events.player_died.connect(func() -> void: _flash_vignette(Color(0.7, 0.0, 0.0), 0.55))

	_refresh_progression()
	_on_ammo_changed(null)


func setup(new_player: Player) -> void:
	player = new_player
	_crosshair.player = new_player
	# Polls the player itself, like the crosshair: a dash starts and ends on the
	# physics loop and the streaks are drawn on the idle one, so a signal would only
	# be a slower way of finding out the same thing a frame later.
	_speed_lines.player = new_player
	# The blur takes its focus, its strength and its direction off the streaks
	# rather than off the player: they are two halves of one effect, and a second
	# reading of the dash is a second chance for them to disagree about where the
	# player is going.
	_motion_blur.wind = _speed_lines
	_on_player_health(0.0, player.health, player.max_health)


func _process(delta: float) -> void:
	_tick_ammo_alert(delta)
	if _reload_left > 0.0:
		_reload_left = maxf(0.0, _reload_left - delta)
		_reload_bar.value = 1.0 - _reload_left / maxf(0.01, _reload_total)
		_reload_bar.visible = _reload_left > 0.0

	if not is_instance_valid(player):
		return
	_prompt_label.text = player.interact_prompt()
	_prompt_label.visible = not _prompt_label.text.is_empty()
	_dash_bar.value = player.dash_ready_fraction()
	_dash_bar.visible = GameState.stat("dash_charges") > 0.0


# --- Player state -----------------------------------------------------------

func _on_player_health(amount: float, health: float, max_health: float) -> void:
	_health_bar.max_value = maxf(1.0, max_health)
	_health_bar.value = health
	_health_label.text = "%d / %d" % [round(health), round(max_health)]
	if amount > 0.0:
		_flash_vignette(Color(0.75, 0.05, 0.05), clampf(amount / 45.0, 0.12, 0.45))


## The direction is `DamageIndicator`'s business and it takes it off the bus
## itself, so nothing is forwarded here — the vignette goes on saying how hard
## and the marks say where from, which is the split that keeps either readable.
func _on_player_damaged(amount: float, health: float, max_health: float,
		_from: Vector3) -> void:
	_on_player_health(amount, health, max_health)


func _on_damage_dealt(_target: Node, _amount: float, is_crit: bool, _at: Vector3) -> void:
	_crosshair.show_hit(is_crit)


# --- Weapons ----------------------------------------------------------------

func _on_ammo_changed(instance: WeaponInstance) -> void:
	var inst: WeaponInstance = instance
	if inst == null and not GameState.loadout.is_empty():
		inst = GameState.loadout[clampi(GameState.equipped_index, 0, GameState.loadout.size() - 1)]
	if inst == null:
		_ammo_label.text = "—"
		_weapon_label.text = "Unarmed"
		_ammo_alert = AMMO_OK
		return
	_ammo_label.text = "%d / %d" % [inst.ammo, inst.reserve]
	_ammo_alert = _alert_for(inst)
	var slot := GameState.loadout.find(inst) + 1
	var suffix := "  [%d]" % slot if slot > 0 else ""
	_weapon_label.text = "%s%s" % [inst.data.display_name, suffix]
	if inst.installed.size() > 0:
		_weapon_label.text += "  +%d" % inst.installed.size()


## What the ammo counter is currently saying about itself: OK, low, or empty.
## Exposed because the state is the part worth holding — a threshold that quietly
## stops firing leaves a player finding out about an empty magazine from the
## trigger, which is exactly what this exists to get in front of.
func ammo_alert() -> int:
	return _ammo_alert


## What the counter is currently tinted, for the dev tools. Plain white is the
## no-warning case, and a state nothing draws is a cue nobody sees.
func ammo_label_tint() -> Color:
	return _ammo_label.modulate


## Empty is the magazine being empty, not the weapon being out of ammunition:
## reserve rounds are a reload away and the reload is automatic, so the moment
## worth marking is the one where the next trigger pull does not fire.
func _alert_for(inst: WeaponInstance) -> int:
	if inst.ammo <= 0:
		return AMMO_EMPTY
	if inst.ammo <= maxi(1, int(floor(inst.mag_size() * LOW_AMMO_FRACTION))):
		return AMMO_LOW
	return AMMO_OK


## Colours and pulses the counter. The clock only advances while there is
## something to say, so the label is not left mid-pulse by a reload — it comes
## back to plain white on the frame the state clears rather than wherever the sine
## had got to.
func _tick_ammo_alert(delta: float) -> void:
	if _ammo_alert == AMMO_OK:
		if _ammo_pulse != 0.0:
			_ammo_pulse = 0.0
			_ammo_label.modulate = Color.WHITE
		return
	_ammo_pulse = wrapf(_ammo_pulse + delta * AMMO_PULSE_RATE * TAU, 0.0, TAU)
	var colour := EMPTY_AMMO_COLOUR if _ammo_alert == AMMO_EMPTY else LOW_AMMO_COLOUR
	_ammo_label.modulate = colour.lerp(Color.WHITE,
			(0.5 + 0.5 * sin(_ammo_pulse)) * AMMO_PULSE_DEPTH)


func _on_reload_started(_instance: WeaponInstance, duration: float) -> void:
	_reload_total = duration
	_reload_left = duration
	_reload_bar.value = 0.0
	_reload_bar.visible = true


func _on_reload_finished(_instance: WeaponInstance) -> void:
	_reload_left = 0.0
	_reload_bar.visible = false


# --- Progression ------------------------------------------------------------

func _refresh_progression() -> void:
	_level_label.text = "LV %d" % GameState.level
	_xp_bar.max_value = GameState.xp_to_next()
	_xp_bar.value = GameState.xp
	_scrap_label.text = "%d Metal" % GameState.scrap
	_update_points_label()


## Names whichever categories have something to spend right now, rather than
## a single generic "unspent points" count — SP and PP are literal points, the
## bench is gated by Metal (and slots) instead, so it gets its own affordable
## count. Two or more at once collapse into one line to avoid a wall of text.
func _update_points_label() -> void:
	var categories: PackedStringArray = []
	if GameState.skill_points > 0:
		categories.append("%d SP available" % GameState.skill_points)
	if GameState.perk_points > 0:
		categories.append("%d PP available" % GameState.perk_points)
	var bench_count := GameState.affordable_bench_upgrade_count()
	if bench_count > 0:
		categories.append("%d bench upgrade%s available" % [
			bench_count, "" if bench_count == 1 else "s",
		])

	if categories.size() > 1:
		_points_label.text = "Multiple upgrades available — [%s]" % _key_hint("menu")
	elif categories.size() == 1:
		_points_label.text = "%s — [%s]" % [categories[0], _key_hint("menu")]
	_points_label.visible = categories.size() > 0


func _on_level_up(new_level: int) -> void:
	_refresh_progression()
	push_notice("Level %d — PP and SP earned" % new_level)
	_flash_vignette(Color(1.0, 0.75, 0.2), 0.3)


func _on_wave_started(index: int, count: int) -> void:
	_wave_label.text = "Wave %d — %d hostiles" % [index, count]


# --- Notices ----------------------------------------------------------------

func push_notice(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	_notices.add_child(label)
	while _notices.get_child_count() > MAX_NOTICES:
		_notices.get_child(0).free()

	var tween := label.create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)


func _flash_vignette(colour: Color, strength: float) -> void:
	_vignette.color = Color(colour.r, colour.g, colour.b, strength)
	var tween := _vignette.create_tween()
	tween.tween_property(_vignette, "color:a", 0.0, 0.35)


## First keyboard key bound to an action, for on-screen hints.
func _key_hint(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).as_text_keycode()
	return "?"
