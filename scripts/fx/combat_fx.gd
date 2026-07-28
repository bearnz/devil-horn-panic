class_name CombatFX
extends RefCounted
## Throwaway combat visuals built from primitives so the project needs no art
## assets yet. Every effect owns its material (the alpha is animated per
## instance) and frees itself when its tween finishes.
##
## Damage targets are duck-typed: anything with
## `apply_damage(amount, is_crit, at, direction)` can be hurt.

## Bullet holes are the one thing in this file that is not a flash: they are meant
## to still be there when the player turns round. That makes them the only effect
## with no tween to free it, so the count is what has to be bounded instead — a
## held trigger puts eleven a second into a wall.
##
## Oldest out first, faded rather than vanished, because a hole blinking out of a
## wall reads as a glitch where the same hole dimming out over a quarter of a second
## reads as nothing at all.
const DECAL_LIMIT := 96
const DECAL_RETIRE := 0.25
## Across the surface, and how deep the projection box straddles it. The depth is
## generous next to the width so a hole on a slightly uneven face still lands; what
## stops it wrapping round a corner onto the wall behind is `normal_fade`.
const DECAL_SIZE := 0.13
const DECAL_DEPTH := 0.20

static var _decals: Array[Decal] = []
static var _hole_texture: Texture2D


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


## Places an effect and takes it out of physics interpolation. The orientation is an
## argument rather than something the caller applies afterwards, and that is not a
## style preference — see below.
static func _spawn(host: Node3D, mesh: Mesh, material: Material, at: Vector3,
		basis: Basis = Basis.IDENTITY) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(node)
	node.global_transform = Transform3D(basis, at)
	# Physics interpolation is on, and a node that was added at the origin and
	# moved a frame later interpolates between the two: an impact spark would
	# streak in from world zero on the frame it appeared.
	#
	# The reset has to come after the *entire* transform, rotation included, which
	# is why the basis arrives here instead of being applied by the caller with
	# look_at(). Turning one of these afterwards re-arms precisely the interpolation
	# this call just cancelled, and the effect is then drawn sweeping from the
	# orientation it was reset at to the one it was given, once per rendered frame
	# until the next physics tick catches up. On a tracer that is spectacular: the
	# box is as long as the shot and pivots about its own centre, so a 40m shot
	# swings its near end through an arc tens of metres wide and reads as several
	# tracers at once, fanning out of thin air behind the shooter. It was invisible
	# in first person, where that arc is mostly off the sides of the screen, and
	# obvious the moment anyone watched themselves shoot from the chase camera.
	node.reset_physics_interpolation()
	return node


## Thin glowing line from muzzle to impact point.
static func tracer(host: Node3D, from: Vector3, to: Vector3, color: Color) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, length)

	# Built as a basis and handed over with the position, rather than turned into
	# place afterwards — see `_spawn`. Still guarded the same way: looking down an
	# axis parallel to the up vector has no answer, and a perfectly vertical shot is
	# exactly that.
	var direction := (to - from).normalized()
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var node := _spawn(host, box, _emissive(color, 3.0), (from + to) * 0.5,
			Basis.looking_at(direction, up))

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


## A hole punched in whatever the shot landed on. Only the environment gets one —
## a body is not something a mark stays on, and an enemy dies and takes it with it.
##
## A `Decal` rather than a quad, because it projects onto the geometry inside its
## box instead of hovering in front of it: a quad placed on a hit normal z-fights
## the wall it is a millimetre off, and sticks out into the air at every corner and
## every rounded edge. The cost is that the box has to be aimed — a decal projects
## down its own -Y — which is what `_basis_on_surface` is for.
##
## Returns the decal so the dev tools can measure one.
static func bullet_hole(host: Node3D, collider: Object, at: Vector3, normal: Vector3) -> Decal:
	if host == null or not host.is_inside_tree():
		return null
	var decal := Decal.new()
	decal.texture_albedo = _hole()
	decal.size = Vector3(DECAL_SIZE, DECAL_DEPTH, DECAL_SIZE)
	# Fades the projection out as the surface turns away from the decal's own axis,
	# so a hole shot near an inside corner marks the wall it was fired at and not the
	# one at right angles to it, which is inside the same box.
	decal.normal_fade = 0.6
	decal.upper_fade = 0.3
	decal.lower_fade = 0.3
	# There is no lighting information in a black hole, so it is worth nothing at
	# fifty metres and worth a draw call the whole time.
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 30.0
	decal.distance_fade_length = 10.0

	# Parented to what was shot only when what was shot can move, so a platform
	# carries its own bullet holes. Static geometry goes on the FX host instead:
	# the level is CSG, and hanging a child off a CSG shape per bullet is an
	# invitation to a mesh rebuild in the middle of a firefight.
	var parent := host
	if collider is AnimatableBody3D or collider is RigidBody3D:
		parent = collider as Node3D
	parent.add_child(decal)
	# Rolled at random about the normal: the texture is a circle, but a burst into
	# one wall is a row of identical stamps without it, and the rim is not radially
	# even enough for that to go unnoticed.
	decal.global_transform = Transform3D(_basis_on_surface(normal, randf() * TAU), at)
	# Placed after being added, so the same rule as every other effect here applies —
	# see `_spawn`. A decal drawn gliding in from the world origin projects a hole
	# onto everything it passes through on the way.
	decal.reset_physics_interpolation()

	_decals.append(decal)
	_retire_decals()
	return decal


## Keeps the live count under DECAL_LIMIT, oldest first. Entries are checked for
## validity rather than trusted: this array is static, so it outlives the scene the
## decals were parented into and holds nothing but dangling references after a
## level change or a restart.
static func _retire_decals() -> void:
	var live: Array[Decal] = []
	for decal in _decals:
		if is_instance_valid(decal):
			live.append(decal)
	_decals = live
	while _decals.size() > DECAL_LIMIT:
		var oldest := _decals.pop_front() as Decal
		var tween := oldest.create_tween()
		tween.tween_property(oldest, "modulate:a", 0.0, DECAL_RETIRE)
		tween.tween_callback(oldest.queue_free)


## A frame with +Y along the surface normal, which is the axis a decal projects
## back down. The reference vector is swapped away from the poles for the same
## reason `tracer` swaps its up vector: a floor and a ceiling are exactly the case
## where the obvious cross product is zero.
static func _basis_on_surface(normal: Vector3, roll: float) -> Basis:
	var up := normal.normalized()
	if up.is_zero_approx():
		up = Vector3.UP
	var reference := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var right := reference.cross(up).normalized()
	return Basis(right, up, up.cross(right)).rotated(up, roll)


## The hole itself, drawn once and shared by every decal in the run: a dark core,
## a bruised rim around it, and nothing at all by the edge of the square, since a
## decal projects its whole texture and anything left in the corners is a box.
static func _hole() -> Texture2D:
	if _hole_texture != null:
		return _hole_texture
	var resolution := 32
	var centre := (resolution - 1) * 0.5
	var image := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	for y in resolution:
		for x in resolution:
			var distance := Vector2(x - centre, y - centre).length() / centre
			var shade := smoothstep(0.2, 0.75, distance) * 0.5
			image.set_pixel(x, y, Color(shade, shade * 0.95, shade * 0.9,
					1.0 - smoothstep(0.3, 1.0, distance)))
	_hole_texture = ImageTexture.create_from_image(image)
	return _hole_texture


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
