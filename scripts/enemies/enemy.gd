class_name Enemy
extends CharacterBody3D
## One script for every enemy archetype; behaviour is driven by exported values
## so a new variant is a new .tscn rather than a new class.
##
## Navigation is deliberately crude — chase the player on the horizontal plane
## and hop when blocked. Good enough for an arena; swap in NavigationAgent3D
## once levels get corridors.
##
## Chasing is flat but **striking is not**: `reach` below is the real distance to
## the player and `distance` is its horizontal shadow, and mixing them up means an
## enemy on the plaza can punch someone standing on a platform overhead.
##
## Enemies stop closing once they are inside their own attack range, cooldown or
## no. The chase does not otherwise stop at the player's skin, and a grunt that
## keeps shoving walks up the capsule and ends up standing on the player's head,
## riding them wherever they go and blocking their movement from up there.
## Holding station is the whole fix: an enemy that never touches the player can
## never climb one. Taking the player off their collision mask instead looks
## tempting and is much worse — enemies then overlap the player, and the player's
## own depenetration shoves them out through the floor.

enum State { IDLE, CHASE, ATTACK, DEAD }

## Being shot moves you. The impulse arrives in `apply_knockback` and is ridden out
## over the frames after it, layered on top of whatever the steering is doing rather
## than mixed into it — see `_move`.
##
## How fast a shove bleeds off, in m/s². Deliberately well under `acceleration`:
## the chase re-writes the horizontal velocity every frame at 22 m/s², so a shove
## living in `velocity` is spent inside a fifth of a second no matter how hard it
## was, which is why knockback was plumbed end to end and still read as nothing.
## At this rate a heavy weapon's shove lasts about half a second and a light one's
## about a tenth, which is the difference between throwing something and nudging it.
const KNOCKBACK_DECAY := 14.0
## Ceiling on the shove that can be stacked up at once, in m/s. Nothing about a
## single weapon needs this — the Shredder's eleven rounds a second settle around a
## metre per second — but a multi-pellet round shoves once per pellet and two blasts
## can land on the same body, and there is no reading of "grunt launched over the
## arena wall" that is not a bug.
const KNOCKBACK_MAX := 14.0
## A shove big enough to be worth leaving the ground for, and what it is worth when
## it is: a fraction of the impulse, capped. Sliding along the floor reads as ice,
## and popping up off every round from an automatic reads as a juggling act — so
## small hits stay planted and only a real hit lifts.
const KNOCKBACK_HOP_MIN := 2.5
const KNOCKBACK_HOP_SHARE := 0.35
const KNOCKBACK_HOP_MAX := 3.0

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
## The shove still being ridden out, horizontal and in m/s. Kept apart from
## `velocity` on purpose: that one belongs to the steering, and anything sharing it
## with the chase loses.
var _knockback: Vector3 = Vector3.ZERO

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _collider: CollisionShape3D = $Collider


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
		_move(delta)
		return

	var to_player := _player.global_position - global_position
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	var distance := flat.length()
	# Moving is flat and hitting is not. Chasing ignores height on purpose — see
	# the note at the top — but an arm is only as long as it is in every
	# direction, so anything about landing a blow measures the real gap. On the
	# flat distance a player up on a platform is standing among everything on the
	# floor below them, and gets punched from twenty metres down.
	var reach := to_player.length()

	_resolve_windup(delta, reach)

	match state:
		State.IDLE:
			if distance <= sight_range:
				state = State.CHASE
			_decelerate(delta)
		State.CHASE:
			if distance > lose_interest_range:
				state = State.IDLE
			elif _attack_timer <= 0.0 and reach <= (preferred_range if ranged else attack_range):
				_begin_attack()
			elif not ranged and reach <= attack_range:
				# Close enough to swing and waiting out the cooldown. Holding station
				# beats walking further in: the chase does not stop at the player's
				# skin, so a grunt on cooldown used to keep shoving until it climbed
				# the capsule and ended up riding on top of it.
				_decelerate(delta)
			else:
				_chase(delta, flat, distance)
		State.ATTACK:
			_decelerate(delta)
		State.DEAD:
			pass

	_face(flat)
	_move(delta)


## Rides out whatever shove is still on the body, then moves.
##
## The knockback is added for the move and taken straight back off, which is the
## whole trick and is worth being precise about. `velocity` is what the steering
## owns: `_chase` and `_decelerate` both read it back as "the speed I am currently
## doing" and accelerate from there at 22 m/s². Leave a shove in it and the chase
## spends its entire budget undoing the hit — a 3 m/s push is gone in an eighth of a
## second and the enemy never visibly moves, which is exactly how knockback managed
## to be wired end to end and still be invisible. Layered this way the two are
## independent: the enemy goes on trying to walk at you at full speed the whole time
## it is being shoved backwards, and the shove ends when it has decayed rather than
## when the chase has caught up with it.
##
## What is deliberately given up is `move_and_slide`'s horizontal clipping — an enemy
## walking into a wall keeps its steering speed instead of having it zeroed. Nothing
## reads that: the hop is off `is_on_wall()`, which is a collision result and not a
## velocity. The vertical is left alone entirely, so gravity and floor snapping are
## still the engine's.
func _move(delta: float) -> void:
	var steer_x := velocity.x
	var steer_z := velocity.z
	velocity.x += _knockback.x
	velocity.z += _knockback.z
	move_and_slide()
	velocity.x = steer_x
	velocity.z = steer_z
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)


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


## `reach` is the real distance to the player rather than its horizontal shadow:
## the wind-up is re-checked when it lands, so stepping out of range during it is
## a miss, and height counts as stepping out of range.
func _resolve_windup(delta: float, reach: float) -> void:
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
	elif reach <= attack_range * 1.3 and _player != null and _player.has_method("apply_damage"):
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

## The middle of this body in world space. An enemy's origin is between its feet, which
## is where it wants to be for standing on things and is the wrong point to measure a
## blast from — see `CombatFX._burn`. Read off the collider rather than written down, so
## the two archetypes' different heights need no second copy of the offset here.
func body_centre() -> Vector3:
	return _collider.global_position if _collider != null else global_position


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


## Shoved. Accumulates rather than assigns, so a burst stacks and a shotgun's
## pellets add up, and is bounded by `KNOCKBACK_MAX`.
##
## Flattened, for the same reason the player's damage bearing is: callers pass the
## direction the shot was travelling, and a round fired down at something standing
## below you would otherwise drive it into the floor — where the engine's
## depenetration answers by squeezing it back out sideways, which reads as a hit
## that teleported. What the vertical buys instead is a small hop, and only when
## the shove is big enough to have earned one.
func apply_knockback(impulse: Vector3) -> void:
	if state == State.DEAD:
		return
	var flat := Vector3(impulse.x, 0.0, impulse.z)
	if flat.is_zero_approx():
		return
	_knockback = (_knockback + flat).limit_length(KNOCKBACK_MAX)
	if is_on_floor() and flat.length() >= KNOCKBACK_HOP_MIN:
		velocity.y = maxf(velocity.y,
				minf(flat.length() * KNOCKBACK_HOP_SHARE, KNOCKBACK_HOP_MAX))


## How hard this body is currently being shoved, in m/s. Zero at rest. Read by the
## dev tools, which have no other way to tell a shove that was applied from one that
## the chase has already eaten.
func knockback_speed() -> float:
	return _knockback.length()


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
