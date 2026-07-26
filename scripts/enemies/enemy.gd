class_name Enemy
extends CharacterBody3D
## One script for every enemy archetype; behaviour is driven by exported values
## so a new variant is a new .tscn rather than a new class.
##
## Navigation is deliberately crude — chase the player on the horizontal plane
## and hop when blocked. Good enough for an arena; swap in NavigationAgent3D
## once levels get corridors.

enum State { IDLE, CHASE, ATTACK, DEAD }

@export var display_name: String = "Grunt"
@export var max_health: float = 60.0
@export var move_speed: float = 5.2
@export var acceleration: float = 22.0
@export var jump_velocity: float = 9.0

@export_group("Attack")
@export var damage: float = 14.0
@export var attack_range: float = 2.4
@export var attack_cooldown: float = 1.2
## Wind-up before the hit lands, so the player can react.
@export var attack_windup: float = 0.35
@export var ranged: bool = false
@export var projectile: PackedScene
@export var projectile_speed: float = 30.0
## Ranged enemies try to hold this distance instead of closing in.
@export var preferred_range: float = 14.0

@export_group("Senses")
## Both of these have to span the arena, or wave spawns land outside them and
## the enemy idles on its marker until the player walks over. The test arena is
## 92m square — 130m corner to corner.
@export var sight_range: float = 140.0
@export var lose_interest_range: float = 200.0

@export_group("Rewards")
@export var xp_reward: int = 18
@export var scrap_reward: int = 10

@export_group("Looks")
@export var body_color: Color = Color(0.62, 0.13, 0.16)

var health: float = 60.0
var state: State = State.IDLE

var _player: Node3D
var _attack_timer: float = 0.0
var _windup_left: float = -1.0
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 26.0))
var _material: StandardMaterial3D
var _flash: float = 0.0

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_material = StandardMaterial3D.new()
	_material.albedo_color = body_color
	_material.metallic = 0.2
	_material.roughness = 0.6
	_material.emission_enabled = true
	_material.emission = body_color
	_material.emission_energy_multiplier = 0.15
	_mesh.material_override = _material


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_tick_flash(delta)
	_attack_timer = maxf(0.0, _attack_timer - delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta

	_player = _acquire_player()
	if _player == null:
		_decelerate(delta)
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	var distance := flat.length()

	_resolve_windup(delta, distance)

	match state:
		State.IDLE:
			if distance <= sight_range:
				state = State.CHASE
			_decelerate(delta)
		State.CHASE:
			if distance > lose_interest_range:
				state = State.IDLE
			elif _attack_timer <= 0.0 and distance <= (preferred_range if ranged else attack_range):
				_begin_attack()
			else:
				_chase(delta, flat, distance)
		State.ATTACK:
			_decelerate(delta)
		State.DEAD:
			pass

	_face(flat)
	move_and_slide()


func _acquire_player() -> Node3D:
	if is_instance_valid(_player):
		return _player
	return get_tree().get_first_node_in_group("player") as Node3D


func _chase(delta: float, flat: Vector3, distance: float) -> void:
	var direction := flat.normalized()
	# Ranged enemies back off when the player gets too close.
	if ranged and distance < preferred_range * 0.6:
		direction = -direction
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(direction * move_speed, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# Hop when a ledge or wall is in the way and the player is above us.
	if is_on_wall() and is_on_floor():
		velocity.y = jump_velocity


func _decelerate(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(Vector3.ZERO, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _face(flat: Vector3) -> void:
	if flat.length() < 0.05:
		return
	var target_yaw := atan2(flat.x, flat.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 0.15)


# --- Attacking --------------------------------------------------------------

func _begin_attack() -> void:
	state = State.ATTACK
	_windup_left = attack_windup
	_flash = 0.6


func _resolve_windup(delta: float, distance: float) -> void:
	if _windup_left < 0.0:
		return
	_windup_left -= delta
	if _windup_left > 0.0:
		return
	_windup_left = -1.0
	_attack_timer = attack_cooldown
	state = State.CHASE
	if ranged:
		_shoot()
	elif distance <= attack_range * 1.3 and _player != null and _player.has_method("apply_damage"):
		var push := (_player.global_position - global_position).normalized()
		_player.apply_damage(damage, false, _player.global_position, push)


func _shoot() -> void:
	if projectile == null or _player == null:
		return
	var muzzle := global_position + Vector3.UP * 1.2
	var target := _player.global_position + Vector3.UP * 0.8
	var shot := projectile.instantiate() as Area3D
	if shot == null:
		return
	get_parent().add_child(shot)
	shot.launch(muzzle, (target - muzzle).normalized(), projectile_speed, damage, 0.0,
			"player", body_color.lightened(0.2))


# --- Damage -----------------------------------------------------------------

func apply_damage(amount: float, is_crit: bool = false, at: Vector3 = Vector3.ZERO,
		_direction: Vector3 = Vector3.ZERO) -> void:
	if state == State.DEAD or amount <= 0.0:
		return
	health -= amount
	_flash = 1.0
	if state == State.IDLE:
		state = State.CHASE
	Events.damage_dealt.emit(self, amount, is_crit,
			at if at != Vector3.ZERO else global_position)
	if health <= 0.0:
		_die()


func apply_knockback(impulse: Vector3) -> void:
	velocity += impulse
	if is_on_floor():
		velocity.y = maxf(velocity.y, 1.5)


func _tick_flash(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta * 4.0)
	_material.emission_energy_multiplier = 0.15 + _flash * 3.0


func _die() -> void:
	state = State.DEAD
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	remove_from_group("enemies")

	GameState.add_xp(xp_reward)
	GameState.add_scrap(scrap_reward)
	Events.enemy_killed.emit(self, xp_reward, scrap_reward)

	var host := get_parent() as Node3D
	if host != null:
		CombatFX.blast(host, global_position + Vector3.UP, 1.4, body_color.lightened(0.3))

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.2, 0.05, 1.2), 0.22).set_ease(Tween.EASE_OUT)
	tween.tween_callback(queue_free)
