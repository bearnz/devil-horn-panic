class_name HUD
extends CanvasLayer
## Combat HUD. Everything it shows arrives through `Events` or is polled from
## the player reference handed over by `main.gd`.

const MAX_NOTICES := 5

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

var _reload_total: float = 0.0
var _reload_left: float = 0.0


func _ready() -> void:
	Events.player_damaged.connect(_on_player_health)
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
	_on_player_health(0.0, player.health, player.max_health)


func _process(delta: float) -> void:
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
		return
	_ammo_label.text = "%d / %d" % [inst.ammo, inst.reserve]
	var slot := GameState.loadout.find(inst) + 1
	var suffix := "  [%d]" % slot if slot > 0 else ""
	_weapon_label.text = "%s%s" % [inst.data.display_name, suffix]
	if inst.installed.size() > 0:
		_weapon_label.text += "  +%d" % inst.installed.size()


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
