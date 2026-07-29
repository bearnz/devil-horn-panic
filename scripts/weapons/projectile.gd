extends Area3D
## Travelling shot used by both the launcher and ranged enemies.
##
## Call `launch()` right after instancing. `target_group` decides who it can
## hurt and is also used to build the collision mask, so the shooter is filtered
## out by physics rather than by bookkeeping.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

@export var speed: float = 45.0
@export var damage: float = 40.0
@export var blast_radius: float = 0.0
@export var gravity_scale: float = 0.35
@export var lifetime: float = 6.0
@export var target_group: String = "enemies"
@export var color: Color = Color(1.0, 0.5, 0.15)
## How hard this round lands, as a multiple of the ordinary mark — the far end of
## `WeaponController.heft_punch()`, carried along with the shot so a heavy weapon's
## shell arrives with the weight it was fired with. Presentation only: the damage
## and the radius it is dealt over are the arguments above.
##
## Defaulted, because enemies fire these too and they have no weapon data to have a
## heft on.
@export var punch: float = 1.0

var _velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _spent: bool = false

@onready var _mesh: MeshInstance3D = $Mesh


func launch(from: Vector3, direction: Vector3, shot_speed: float, shot_damage: float,
		radius: float, group: String, tint: Color, shot_punch: float = 1.0) -> void:
	global_position = from
	# Placed after being added to the tree, so without this the first rendered
	# frame draws it somewhere between the world origin and the muzzle.
	reset_physics_interpolation()
	speed = shot_speed
	damage = shot_damage
	blast_radius = radius
	target_group = group
	color = tint
	punch = shot_punch
	_velocity = direction.normalized() * speed
	collision_mask = LAYER_WORLD | (LAYER_PLAYER if group == "player" else LAYER_ENEMY)


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	_mesh.material_override = mat
	body_entered.connect(_on_body_entered)
	if _velocity.is_zero_approx():
		_velocity = -global_transform.basis.z * speed


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		_detonate(global_position, Vector3.UP, null)
		return
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 26.0))
	_velocity.y -= gravity * gravity_scale * delta
	global_position += _velocity * delta

	var direction := _velocity.normalized()
	# look_at() errors when the direction is parallel to the up vector.
	if absf(direction.dot(Vector3.UP)) < 0.99:
		look_at(global_position + direction, Vector3.UP)


func _on_body_entered(body: Node3D) -> void:
	# collision_mask already excludes the shooter, so anything we touch is a hit.
	_detonate(global_position, -_velocity.normalized(), body)


func _detonate(at: Vector3, normal: Vector3, direct_hit: Node3D) -> void:
	if _spent:
		return
	_spent = true
	set_physics_process(false)
	# FX must outlive us, so they are parented to whatever holds the projectile.
	var host := get_parent() as Node3D
	if host == null:
		queue_free()
		return

	if blast_radius > 0.0:
		CombatFX.explode(host, at, blast_radius, damage, target_group, punch)
	else:
		if direct_hit != null and direct_hit.has_method("apply_damage"):
			direct_hit.apply_damage(damage, false, at, _velocity.normalized())
		elif direct_hit != null:
			# Hit something that cannot be hurt, which means the level. The normal is
			# the shot's own heading reversed rather than the surface's — an Area3D
			# reports what it touched, not where — so a hole from a steeply angled
			# shot is a little skewed. It is a hole in a wall either side of that.
			CombatFX.bullet_hole(host, direct_hit, at, normal)
		CombatFX.impact(host, at, normal, color, 1.2 * punch)
	queue_free()
