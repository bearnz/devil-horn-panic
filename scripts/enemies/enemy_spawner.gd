extends Node3D
## Endless wave spawner. Child Marker3D nodes are the spawn points.
##
## Waves grow in size and mix archetypes; XP and scrap come from the enemies
## themselves, so the spawner only decides *what* shows up and *when*.

@export var enemy_scenes: Array[PackedScene] = []
## Wave 1 size; each wave adds `count_growth` more.
@export var base_count: int = 3
@export var count_growth: int = 2
@export var max_alive: int = 16
@export var first_wave_delay: float = 4.0
@export var between_waves: float = 7.0
@export var spawn_interval: float = 0.45
@export var auto_start: bool = true

var wave: int = 0
var _alive: int = 0
var _running: bool = false

@onready var _points: Array[Node] = _collect_points()


func _collect_points() -> Array[Node]:
	var out: Array[Node] = []
	for child in get_children():
		if child is Marker3D:
			out.append(child)
	return out


func _ready() -> void:
	add_to_group("enemy_spawner")
	Events.enemy_killed.connect(_on_enemy_killed)
	if auto_start and Settings.spawn_enemies_enabled:
		start()


func start() -> void:
	if _running:
		return
	if _points.is_empty():
		push_warning("EnemySpawner: no Marker3D spawn points, disabled")
		return
	if enemy_scenes.is_empty():
		push_warning("EnemySpawner: no enemy scenes assigned, disabled")
		return
	_running = true
	_run_waves()


func _run_waves() -> void:
	await get_tree().create_timer(first_wave_delay).timeout
	while _running and is_inside_tree():
		wave += 1
		var count := base_count + (wave - 1) * count_growth
		Events.wave_started.emit(wave, count)
		Events.notice.emit("Wave %d — %d hostiles" % [wave, count])

		for index in range(count):
			while _alive >= max_alive and _running:
				await get_tree().create_timer(0.5).timeout
			if not _running:
				return
			_spawn_one()
			await get_tree().create_timer(spawn_interval).timeout

		# Wait for the arena to be cleared before the next wave.
		while _alive > 0 and _running:
			await get_tree().create_timer(0.5).timeout
		if not _running:
			return
		Events.wave_cleared.emit(wave)
		Events.notice.emit("Wave %d cleared" % wave)
		await get_tree().create_timer(between_waves).timeout


func _spawn_one() -> void:
	# Later waves lean towards the tougher end of the archetype list.
	var pool_size := mini(enemy_scenes.size(), 1 + int(wave / 2))
	var scene: PackedScene = enemy_scenes[randi() % pool_size]
	if scene == null:
		return
	var enemy := scene.instantiate() as Node3D
	if enemy == null:
		return

	# Scaled before add_child(), because the enemy reads max_health in _ready().
	if "max_health" in enemy:
		enemy.max_health *= 1.0 + (wave - 1) * 0.12

	var point: Node3D = _points[randi() % _points.size()]
	get_parent().add_child(enemy)
	enemy.global_position = point.global_position
	_alive += 1


func _on_enemy_killed(_enemy: Node, _xp: int, _scrap: int) -> void:
	_alive = maxi(0, _alive - 1)


func stop() -> void:
	_running = false


func is_active() -> bool:
	return _running


## Toggled live from the pause menu's "Spawn enemies" setting.
func set_active(active: bool) -> void:
	if active:
		start()
		return
	stop()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	_alive = 0
