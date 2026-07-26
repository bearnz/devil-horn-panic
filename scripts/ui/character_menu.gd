class_name CharacterMenu
extends CanvasLayer
## Pause-time progression screen: skill lines, perk tree and the weapon bench.
##
## Rows are generated from `GameState`'s libraries rather than authored in the
## scene, so dropping a .tres into res://resources/perks is enough to make it
## appear here. Reached with the menu key, or by interacting with a workbench
## (which opens straight onto the bench tab).

const TAB_SKILLS := 0
const TAB_PERKS := 1
const TAB_BENCH := 2

const DIM := Color(0.68, 0.70, 0.76)
const GOOD := Color(0.55, 0.95, 0.60)
const BAD := Color(0.95, 0.45, 0.40)
const ACCENT := Color(1.0, 0.72, 0.35)

var player: Player

var _bench_index: int = 0

@onready var _tabs: TabContainer = %Tabs
@onready var _skill_list: VBoxContainer = %SkillList
@onready var _perk_list: VBoxContainer = %PerkList
@onready var _bench_list: VBoxContainer = %BenchList
@onready var _summary: Label = %SummaryLabel
@onready var _close_button: Button = %CloseButton
@onready var _reset_button: Button = %ResetButton


func _ready() -> void:
	add_to_group("character_menu")
	visible = false
	_close_button.pressed.connect(close)
	_reset_button.pressed.connect(_on_reset_pressed)
	Events.stats_changed.connect(func() -> void:
		if visible:
			refresh())


func setup(new_player: Player) -> void:
	player = new_player


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if visible:
			close()
		elif not _pause_menu_visible():
			open(_tabs.current_tab)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _pause_menu_visible() -> bool:
	var menus := get_tree().get_nodes_in_group("pause_menu")
	return not menus.is_empty() and (menus[0] as CanvasLayer).visible


func open(tab: int = TAB_SKILLS) -> void:
	_tabs.current_tab = clampi(tab, 0, _tabs.get_tab_count() - 1)
	visible = true
	get_tree().paused = true
	if is_instance_valid(player):
		player.set_control_active(false)
	refresh()


func close() -> void:
	visible = false
	get_tree().paused = false
	if is_instance_valid(player):
		player.set_control_active(true)


func refresh() -> void:
	_summary.text = "LV %d    XP %d / %d    Perk points %d    Skill points %d    Scrap %d" % [
		GameState.level, GameState.xp, GameState.xp_to_next(),
		GameState.perk_points, GameState.skill_points, GameState.scrap,
	]
	_build_skills()
	_build_perks()
	_build_bench()


# --- Skills tab -------------------------------------------------------------

func _build_skills() -> void:
	_clear(_skill_list)
	_skill_list.add_child(_label(
			"Spend skill points to raise a line. Higher ranks unlock deeper perks.", 16, DIM))

	for line_id: String in GameState.SKILL_LINES:
		var info: Dictionary = GameState.SKILL_LINES[line_id]
		var rank := GameState.skill_rank(line_id)

		var button := Button.new()
		button.text = "+1  (%d left)" % GameState.skill_points
		button.disabled = GameState.skill_points <= 0
		button.pressed.connect(func() -> void:
			if GameState.spend_skill_point(line_id):
				refresh())

		_skill_list.add_child(_card([
			_row([_label("%s — rank %d" % [info["name"], rank], 20, ACCENT), _spacer(), button]),
			_label(String(info["blurb"]), 14, DIM),
			_label("Per rank: %s" % _describe_line(info), 14, Color(0.75, 0.85, 1.0)),
		]))


func _describe_line(info: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in info["flat"]:
		parts.append("%s %+.2f" % [_pretty(key), float(info["flat"][key])])
	for key: String in info["mult"]:
		parts.append("%s %+.0f%%" % [_pretty(key), float(info["mult"][key]) * 100.0])
	return ", ".join(parts)


# --- Perks tab --------------------------------------------------------------

func _build_perks() -> void:
	_clear(_perk_list)
	_perk_list.add_child(_label("Perk points: %d" % GameState.perk_points, 16, DIM))

	for line_id: String in GameState.SKILL_LINES:
		var perks := GameState.perks_in_line(line_id)
		if perks.is_empty():
			continue
		var line_name: String = GameState.SKILL_LINES[line_id]["name"]
		_perk_list.add_child(_label("%s  (rank %d)" % [line_name, GameState.skill_rank(line_id)],
				22, ACCENT))
		for perk in perks:
			_perk_list.add_child(_perk_card(perk))


func _perk_card(perk: PerkData) -> Control:
	var rank := GameState.perk_rank(perk.id)
	var reason := GameState.perk_block_reason(perk)

	var action: Control
	if reason.is_empty():
		var button := Button.new()
		button.text = "Buy  (%d pt%s)" % [perk.cost, "" if perk.cost == 1 else "s"]
		button.pressed.connect(func() -> void:
			if GameState.unlock_perk(perk.id):
				refresh())
		action = button
	else:
		action = _inline_label(reason, 14, GOOD if reason == "Maxed" else BAD)

	var rows: Array = [
		_row([
			_label("%s  %d/%d" % [perk.display_name, rank, perk.max_rank], 18,
					GOOD if rank > 0 else Color.WHITE),
			_spacer(),
			action,
		]),
		_label(perk.description, 14, DIM),
	]
	var effects := perk.summarize()
	if not effects.is_empty():
		rows.append(_label(effects, 14, Color(0.75, 0.85, 1.0)))
	return _card(rows)


# --- Bench tab --------------------------------------------------------------

func _build_bench() -> void:
	_clear(_bench_list)
	if GameState.loadout.is_empty():
		_bench_list.add_child(_label("No weapons carried.", 16, DIM))
		return

	_bench_list.add_child(_label(
			"Scrap: %d — upgrades are permanent and take one slot." % GameState.scrap, 16, DIM))

	var picker := HBoxContainer.new()
	for index in GameState.loadout.size():
		var inst := GameState.loadout[index]
		var button := Button.new()
		button.text = inst.data.display_name
		button.toggle_mode = true
		button.button_pressed = index == _bench_index
		button.pressed.connect(func() -> void:
			_bench_index = index
			refresh())
		picker.add_child(button)
	_bench_list.add_child(picker)

	_bench_index = clampi(_bench_index, 0, GameState.loadout.size() - 1)
	var inst := GameState.loadout[_bench_index]

	var rows: Array = [
		_label(inst.data.display_name, 22, ACCENT),
		_label(inst.data.description, 14, DIM),
		_label(_weapon_stat_lines(inst), 15, Color.WHITE),
		_label("Slots used: %d / %d" % [inst.installed.size(), inst.data.upgrade_slots], 15,
				GOOD if inst.free_slots() > 0 else BAD),
	]
	if not inst.installed.is_empty():
		var installed: PackedStringArray = []
		for upgrade in inst.installed:
			installed.append(upgrade.display_name)
		rows.append(_label("Installed: %s" % ", ".join(installed), 14, Color(0.75, 0.85, 1.0)))
	_bench_list.add_child(_card(rows))

	var available := GameState.available_upgrades(inst)
	if available.is_empty():
		_bench_list.add_child(_label("Nothing else fits this weapon.", 15, DIM))
	for upgrade in available:
		_bench_list.add_child(_upgrade_card(inst, upgrade))

	var for_sale := GameState.purchasable_weapons()
	if for_sale.is_empty():
		return
	_bench_list.add_child(_label("Available hardware", 22, ACCENT))
	for data in for_sale:
		_bench_list.add_child(_weapon_sale_card(data))


func _weapon_sale_card(data: WeaponData) -> Control:
	var button := Button.new()
	button.text = "Buy  (%d scrap)" % data.scrap_cost
	button.disabled = GameState.scrap < data.scrap_cost
	button.pressed.connect(func() -> void:
		var error := GameState.buy_weapon(data.id)
		if not error.is_empty():
			Events.notice.emit(error)
		refresh())

	return _card([
		_row([_label(data.display_name, 18, Color.WHITE), _spacer(), button]),
		_label(data.description, 14, DIM),
		_label("Damage %.0f    Rate %.1f/s    Mag %d    %d upgrade slots" % [
			data.damage, data.fire_rate, data.mag_size, data.upgrade_slots], 14,
			Color(0.75, 0.85, 1.0)),
	])


func _weapon_stat_lines(inst: WeaponInstance) -> String:
	var dps := inst.damage() * inst.stat("fire_rate") * inst.pellets()
	var lines: PackedStringArray = [
		"Damage %.1f x%d    Rate %.1f/s    Burst DPS %.0f" % [
			inst.damage(), inst.pellets(), inst.stat("fire_rate"), dps],
		"Mag %d    Reserve %d/%d    Reload %.2fs" % [
			inst.mag_size(), inst.reserve, inst.reserve_max(), inst.reload_duration()],
		"Spread %.2f deg    Crit %.0f%% x%.1f" % [
			inst.stat("spread_deg"), inst.crit_chance() * 100.0, inst.crit_mult()],
	]
	if inst.stat("blast_radius") > 0.0:
		lines.append("Blast radius %.1f m" % inst.stat("blast_radius"))
	return "\n".join(lines)


func _upgrade_card(inst: WeaponInstance, upgrade: WeaponUpgrade) -> Control:
	var button := Button.new()
	button.text = "Install  (%d scrap)" % upgrade.cost
	button.disabled = GameState.scrap < upgrade.cost or inst.free_slots() <= 0
	button.pressed.connect(func() -> void:
		var error := GameState.install_upgrade(inst, upgrade.id)
		if not error.is_empty():
			Events.notice.emit(error)
		refresh())

	return _card([
		_row([
			_label("%s  (T%d)" % [upgrade.display_name, upgrade.tier], 18, Color.WHITE),
			_spacer(),
			button,
		]),
		_label(upgrade.description, 14, DIM),
		_label(upgrade.summarize(), 14, Color(0.75, 0.85, 1.0)),
	])


# --- Row building -----------------------------------------------------------

func _on_reset_pressed() -> void:
	GameState.reset_progress()
	_bench_index = 0
	refresh()


## Detach immediately as well as queueing the free, otherwise the old rows are
## still drawn for the rest of the frame we rebuild in.
func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _card(rows: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.04)
	style.border_color = Color(1.0, 1.0, 1.0, 0.10)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	for row: Control in rows:
		box.add_child(row)
	return panel


func _row(children: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	for child: Control in children:
		box.add_child(child)
	return box


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## Label for the trailing end of a row. Must not autowrap or expand, otherwise
## the spacer squeezes it to one character per line.
func _inline_label(text: String, font_size: int, colour: Color) -> Label:
	var label := _label(text, font_size, colour)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_END
	return label


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _pretty(key: String) -> String:
	return key.replace("_", " ").capitalize()
