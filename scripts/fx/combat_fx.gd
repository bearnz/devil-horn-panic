class_name CombatFX
extends RefCounted
## Throwaway combat visuals built from primitives so the project needs no art
## assets yet. Every effect owns its material (the alpha is animated per
## instance) and frees itself when its tween finishes.
##
## Damage targets are duck-typed: anything with
## `apply_damage(amount, is_crit, at, direction)` can be hurt.

static func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_receive_shadows = true
	return mat


static func _spawn(host: Node3D, mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(node)
	node.global_position = at
	# Physics interpolation is on, and a node that was added at the origin and
	# moved a frame later interpolates between the two: an impact spark would
	# streak in from world zero on the frame it appeared.
	node.reset_physics_interpolation()
	return node


## Thin glowing line from muzzle to impact point.
static func tracer(host: Node3D, from: Vector3, to: Vector3, color: Color) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, length)
	var node := _spawn(host, box, _emissive(color, 3.0), (from + to) * 0.5)

	# look_at() errors out when the aim direction is parallel to the up vector,
	# which happens on perfectly vertical shots.
	var direction := (to - from).normalized()
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	node.look_at(to, up)

	var tween := node.create_tween()
	tween.tween_property(node, "material_override:albedo_color:a", 0.0, 0.07)
	tween.parallel().tween_property(node, "scale", Vector3(0.25, 0.25, 1.0), 0.07)
	tween.tween_callback(node.queue_free)


## Expanding flash at an impact point.
static func impact(host: Node3D, at: Vector3, normal: Vector3, color: Color, size: float = 1.0) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.08 * size
	sphere.height = 0.16 * size
	sphere.radial_segments = 8
	sphere.rings = 4
	var node := _spawn(host, sphere, _emissive(color, 4.0), at + normal * 0.05)

	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE * (2.6 * size), 0.16).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(node, "material_override:albedo_color:a", 0.0, 0.16)
	tween.tween_callback(node.queue_free)


## Bigger, slower flash for explosions.
static func blast(host: Node3D, at: Vector3, radius: float, color: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius * 0.35
	sphere.height = radius * 0.7
	var node := _spawn(host, sphere, _emissive(color, 5.0), at)

	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE * 3.0, 0.35).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(node, "material_override:albedo_color:a", 0.0, 0.35)
	tween.tween_callback(node.queue_free)


## Radial damage against one group. Returns how many targets it hurt.
static func explode(host: Node3D, at: Vector3, radius: float, damage: float, group: String) -> int:
	blast(host, at, radius, Color(1.0, 0.55, 0.15))
	var hits := 0
	for node in host.get_tree().get_nodes_in_group(group):
		var target := node as Node3D
		if target == null or not target.has_method("apply_damage"):
			continue
		var distance := target.global_position.distance_to(at)
		if distance > radius:
			continue
		# Full damage at the centre, 35% at the rim.
		var falloff := lerpf(1.0, 0.35, clampf(distance / radius, 0.0, 1.0))
		var direction := (target.global_position - at).normalized()
		target.apply_damage(damage * falloff, false, target.global_position, direction)
		hits += 1
	return hits
