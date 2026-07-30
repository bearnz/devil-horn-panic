class_name Projectile
extends Area3D
## Travelling shot used by both the launcher and ranged enemies.
##
## Call `launch()` right after instancing. `target_group` decides who it can
## hurt and is also used to build the collision mask, so the shooter is filtered
## out by physics rather than by bookkeeping.
##
## Two kinds, and the difference between them is one fact told twice: **a rocket is
## driven and a grenade is thrown.**
##
## A rocket has a motor, so it holds the line it was fired along and a contact fuse
## goes off against the first thing it touches: what you pointed at is what you hit,
## and there is nothing to lead. A grenade has nothing but gravity on it once it
## leaves the muzzle, so it arcs — and a clock rather than a contact fuse, so touching
## the world only stops it. It lands, bounces off it, settles, rolls down anything
## sloped and cooks off when the fuse runs out.
##
## A grenade's fuse is also *fuzzy* about bodies, which a rocket's has no need to be —
## see `GRENADE_PROXIMITY`.
##
## Everything else about them — the blast, the shove, who gets caught in it — is
## shared, which is why this is a field rather than two scripts.
##
## Sticky grenades are a deliberate gap. They would be a third kind that keeps the
## surface it hit instead of sliding along it, which is one branch in `_settle()`.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

## Kinds, mirroring `WeaponData.ProjectileKind` — an int rather than that enum so a
## spitter can fire one of these without a `WeaponData` to name the kind from.
const KIND_ROCKET := 0
const KIND_GRENADE := 1

## What fraction of the project's own gravity each kind flies under. This is the second
## half of what a kind decides, and it falls out of the same fact as the first: a rocket
## is under thrust for the whole of a flight that is over in a fraction of a second, so
## nothing pulls it off the line it was fired along; a grenade is a thrown object with
## nothing acting on it but gravity, so it arcs.
##
## Full gravity rather than a fraction of it, because a fudged one is the worst of both
## — visible enough to have to aim around and too shallow to aim *with*. At the
## Hellmouth's 34 m/s a shell drops about a metre and a half over twelve metres, which
## is a lob you can learn and lead, and the 4.5 m blast is what makes learning it
## forgiving. It is also why the shell noses over as it goes: `_point_along_travel()`
## follows the velocity, so the arc is visible on the round itself and not only in
## where it lands.
##
## Derived from the kind rather than authored per shell on purpose. An authored number
## here can contradict the kind it sits on, and "a rocket that arcs" and "a grenade that
## does not" are precisely the two things this field exists to keep apart.
const GRAVITY_ROCKET := 0.0
const GRAVITY_GRENADE := 1.0

## How much of the speed going into a surface comes back out of it, for a grenade.
## A shell that lands dead reads as sticky, which is the feature this one is explicitly
## not, so it bounces — and the *decay* of that bounce needs no number of its own,
## because a constant fraction of a falling speed is already a geometric series. Read it
## as heights rather than as speeds, since heights are what is watched and they go as the
## *square* of this: hops of 30, 13 and 6 cm over about two thirds of a second, from any
## arrival however hard, since the cap below is what the first hop is measured from rather
## than the speed the shell turned up with.
##
## It is high, and higher than a physical restitution would be, because a bounce here pays
## a fixed tax rather than a proportional one. Gravity is applied for the whole frame
## before the shell is moved, so it leaves the surface at the rebound *minus* 0.43 m/s,
## and the sweep stops it up to `SWEEP_SKIN` before it has really arrived. Neither matters
## at 4 m/s and both are most of the speed at 1.5, so the tail of the series is what pays:
## the measured height ratio is about 0.47, which is what a nominal 0.69 would give if the
## hops were free. Anything quoted here has to be read against that.
##
## The squaring is also why it is sensitive, and why the first cut of it read as abrupt at
## 0.55 — barely a fifth off the rebound is nearly half off the height, so the second hop
## was a twitch and there was no third. What stops it going higher still is that a shell
## keeps its sideways speed through a hop, so every extra bounce is more distance between
## where the shot was aimed and where it goes off.
const GRENADE_BOUNCE := 0.85
## Ceiling on that rebound, in m/s, and it is not optional. A fraction of the speed
## going in is fine for a lob and absurd for a shell fired at the ground from a metre
## away: most of 34 m/s is most of 34 m/s, which throws it eighteen metres back into the
## air, and it then spends its whole fuse hopping away from where it was aimed —
## barely touching the surface, so rolling resistance never gets a frame to act in.
## Quoted as the rebound rather than as a height, but a height is what it is for:
## gravity here is 26 m/s², so 4.0 is a hop of just over 30 cm and a third of a second
## in the air, which is a bounce that can be watched. Under it the series above is what
## happens; over it the shell is a bouncing ball.
const GRENADE_BOUNCE_MAX := 4.0
## The normal speed at which a grenade's arrival counts as an impact rather than as
## resting contact, in m/s. Nothing rebounds off one below it, which is what puts a floor
## under the series above: without it a shell is handed a sliver of rebound every frame
## for the whole fuse and jitters in place instead of lying still.
##
## It is also where the tail of the bounce is cut off, so it is low — a hop of a
## centimetre and a half. Resting contact is a single frame of gravity, 0.43 m/s, so
## there is room between the two and the jitter is still impossible.
const GRENADE_IMPACT_SPEED := 1.0
## How much of its *sideways* speed a grenade keeps through an arrival at
## `GRENADE_SKID_FULL` or worse, tapering to all of it for a graze.
##
## Without this a shell fired flat at the floor skated. Bouncing only takes away the
## speed going *into* a surface, and rolling resistance is 2.2 m/s² by necessity —
## which is thirteen seconds and the better part of two hundred metres to bleed off
## the 29 m/s a shell arrives with when it is fired at the ground from the hip. A
## grenade launcher whose shells cross the arena along the floor is an ice-hockey
## simulator, and a lob that skips four metres past where it was aimed is the same
## fault in miniature.
##
## Scaled by how hard the arrival was rather than applied flat, because a flat one
## compounds: the shell now bounces two or three times, and a fixed 0.2 taken at every
## one of them leaves less than a hundredth of the sideways speed by the third — a
## shell that stops dead where it first touched and then pogos in place. The slam is
## what should cost it; the taps afterwards are what carry it that last half metre and
## make the bounce read as travel rather than as a spring.
const GRENADE_SKID := 0.2
const GRENADE_SKID_FULL := 5.0
## What a shell that did not hit anything is worth against one that did — the whole of
## how a blast is scored, for both the damage and the shove.
##
## The alternative, and what this replaced, was a radial falloff: full value at the
## centre, a third of it at the rim. That is the right shape for an explosive *round*,
## where the blast is collateral on top of a hit that already landed, and the wrong one
## for a weapon that is nothing but its blast. A grenade launcher fired at a distant
## group is aimed at the ground, so every shot is scored on where the shell *finished* —
## and it finishes after an arc, a bounce and a roll, none of which the player can place
## to the metre. The gradient therefore taxed the part of the weapon nobody controls, and
## it did it worst exactly where the shell had bounced somewhere interesting: a hit for a
## third of its damage two seconds after it went in reads as the weapon not working.
##
## So: in reach or not in reach, and one flat step for having missed. A near miss is a
## fifteenth off, which is a real answer to "did you hit it" without being the difference
## between a kill and a shrug. The step is also what keeps the proximity fuse honest — it
## goes off *for* near misses, and this is what stops that slack being free.
##
## `CombatFX.RIM_FLAT` is the other half of it and the two have to move together: a flat
## blast with a gradient inside it is two answers to the same question.
const INDIRECT_SHARE := 0.85
## How far past its own skin a grenade's fuse notices a body, in metres.
##
## A rocket needs none of this: it goes off against whatever is behind the target, so a
## near miss is still an explosion roughly where the player was aiming. A grenade's near
## miss is nothing at all — the shell sails past, lands somewhere behind, and sits there
## for two seconds — and the arc means near misses are now the normal way to be wrong,
## since the shot has to be led. So the fuse is given a little slack: pass within about
## half a metre of a grunt's shoulder and it goes off, which takes a body's worth of
## width and makes it two.
##
## Slack rather than homing, which was the other way to fix it. A shell that steered
## itself towards a target would quietly undo the arc it was fired on — the lead the
## player just learned would stop being the lead that works, and the trajectory the last
## change exists to draw would be a suggestion. This changes when a shell goes off and
## never where it is going.
const GRENADE_PROXIMITY := 0.5
## Rolling resistance along the surface, m/s². The one number here with a real
## trade-off in it: it has to stay under `_gravity() * sin(θ)` for the shallowest slope
## a grenade ought to roll down, and every bit of it that buys that also buys a longer
## skid across flat ground. Against full gravity a shell rolls on anything steeper than
## about 5° and still skids a metre and a half on the level, which is as close to
## free as this number gets — under the old fifth-gravity flight the same value needed
## 14° before anything moved.
const GRENADE_ROLL_FRICTION := 2.2
## Tangential speed below which a grounded grenade is simply stopped. Without it
## friction only ever approaches rest and a shell creeps for the whole fuse.
const GRENADE_REST_SPEED := 0.35
## Slack added to the sweep's reach past the shell's own surface. A resting grenade
## re-finds the floor with a ray barely longer than its radius, and one that misses
## by a millimetre falls for a frame and lands again — which reads as a jitter.
const SWEEP_SKIN := 0.03

@export var speed: float = 45.0
@export var damage: float = 40.0
@export var blast_radius: float = 0.0
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
## How hard this round shoves what it lands on, in m/s — `impact_force` with the
## firing weapon's mass already folded in (`WeaponController.knockback_force`).
##
## Defaulted to nothing, and that default is the enemies': a shell that shoved the
## player would fight the movement the whole game is built on, and being pushed
## around by what hits them is already the player's own `apply_damage`.
@export var impact_force: float = 0.0
## `KIND_ROCKET` or `KIND_GRENADE`. Rocket by default, because that is what a
## projectile with no opinion should do — go off when it arrives.
@export var kind: int = KIND_ROCKET

var _velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _spent: bool = false
## Taken off the collision shape in `_ready`, so the scene stays the one place the
## shell's size is stated and the sweep reaches to its surface rather than its
## centre.
var _radius: float = 0.2
## The surface a grenade is currently resting or rolling on, or `ZERO` when it is in
## the air. Held so the ground probe can look along the surface's own normal — on a
## slope, straight down is further to the surface than the shell's radius, and a probe
## quoted in radii would miss on anything tilted.
var _ground_normal: Vector3 = Vector3.ZERO
## Whether a grenade's proximity fuse is still live. It is armed at the muzzle and
## disarmed by the first surface the shell touches, one way, because the slack exists to
## catch a shell going *past* a body and a shell that has landed already has a clock. Left
## armed, a grenade lying on the floor goes off when anything wanders near it — which is
## a proximity mine, a different weapon, and it would take the "denies ground for two
## seconds" half of this one away.
var _armed: bool = true
## The proximity query, built once and moved rather than rebuilt per frame. An object
## rather than a number, so this is not the derived-stat caching the project bans — the
## radius on it is read off the shell's own collider and cannot go stale.
var _proximity: PhysicsShapeQueryParameters3D = null

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _collider: CollisionShape3D = $Collider


## Everything a shot needs, in one call. The tail of it is defaulted for the
## enemies, who fire the same scene with none of a weapon's authored detail — and
## the signature is at about its limit: another pair of floats on the end and the
## call site stops being readable at a glance.
##
## `shot_fuse` is only read for a grenade, where it *replaces* the lifetime — the
## catch-all that stops a shot which never hits anything from living forever is the
## same clock as the fuse that makes a grenade go off, so there is one timer rather
## than two racing.
func launch(from: Vector3, direction: Vector3, shot_speed: float, shot_damage: float,
		radius: float, group: String, tint: Color, shot_punch: float = 1.0,
		shot_force: float = 0.0, shot_kind: int = KIND_ROCKET,
		shot_fuse: float = 0.0) -> void:
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
	impact_force = shot_force
	kind = shot_kind
	if kind == KIND_GRENADE and shot_fuse > 0.0:
		lifetime = shot_fuse
	_velocity = direction.normalized() * speed
	collision_mask = LAYER_WORLD | (LAYER_PLAYER if group == "player" else LAYER_ENEMY)


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	_mesh.material_override = mat
	# Kept alongside the sweep below rather than replaced by it, for the one case a
	# sweep cannot see: a shot that is *already* inside something on the frame it is
	# made, which is a muzzle pressed against a wall. `_spent` is what stops the two
	# paths detonating the same shell twice.
	body_entered.connect(_on_body_entered)
	var sphere := _collider.shape as SphereShape3D
	if sphere != null:
		_radius = sphere.radius
	if _velocity.is_zero_approx():
		_velocity = -global_transform.basis.z * speed


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		_detonate(global_position, Vector3.UP, null, false)
		return
	_velocity.y -= _gravity() * delta

	# Swept, not left to the Area3D's own monitoring, and this is the whole reason
	# anything a projectile hits ever happens.
	#
	# The level is CSG, and `CSGShape3D.use_collision` builds a *concave* trimesh.
	# GodotPhysics 3D will happily solve a body against one of those — which is why
	# the player has always been able to stand on the floor — but it does not report
	# them to area monitoring at all. So `body_entered` never fired for the world:
	# every shell in the game flew straight through the arena and fell for six
	# seconds until its lifetime ran out, a hundred and sixty metres under the floor.
	# It was invisible because nothing checked. The Hellmouth's blast could not land,
	# so the heaviest weapon in the game had no knockback, and spitters shot through
	# walls.
	#
	# A ray from where the shell was to where it is going answers all of that, needs
	# nothing from the broadphase, and closes the other hole in the old version for
	# free: a 34 m/s shell moves half a metre a tick, and overlap tests only ever see
	# where it *is*.
	var from := global_position
	var to := from + _velocity * delta

	# Checked ahead of the sweep, because a shell arriving at a body is the answer this
	# weapon wants even when there is a wall a hand's width behind it. See
	# `GRENADE_PROXIMITY` for why a grenade needs the slack and a rocket does not.
	if kind == KIND_GRENADE and _armed:
		var near := _body_slipping_past(to)
		if near != null:
			# Not a direct hit, by definition — the slack is the whole feature, and
			# `INDIRECT_SHARE` is what it costs.
			_detonate(to, -_velocity.normalized(), near, false)
			return

	var hit := _sweep(from, to)
	if hit.is_empty():
		global_position = to
		# Rolling along a surface is not moving *into* one, so the sweep above cannot
		# see the floor a settled grenade is already touching: it reaches along the
		# shell's own travel, and a shell crossing flat ground is travelling sideways.
		# Left at that, a rolling grenade is in contact perhaps one frame in ten —
		# which is enough to keep it out of the floor and nowhere near enough for
		# rolling resistance to bite, so it slides for the whole fuse and arrives
		# somewhere nobody aimed at. The probe is what makes contact continuous.
		#
		# Which is also why it is for a shell **in contact** and nothing else, and that
		# qualifier is the whole of the bounce. The probe reaches a few centimetres past
		# the shell's own skin, so pointed at one in the air it stops being a continuity
		# check and becomes an early-contact detector: on the frame after a rebound the
		# floor is still inside it and the rebound is cancelled outright, and on the way
		# back down it grabs the shell before it has arrived and quietly keeps the last
		# few centimetres of the fall. The first of those hid the bounce completely; the
		# second ate the tail of it, which is a whole 40% of the rebound at the speeds the
		# last hops happen at. So contact is a *state* here — `_ground_normal`, set by a
		# real arrival — and leaving the surface drops it and hands the shell back to the
		# sweep above, which is what finds an arrival at the speed it actually arrived.
		if kind == KIND_GRENADE and not _ground_normal.is_zero_approx():
			if _velocity.dot(_ground_normal) > GRENADE_REST_SPEED:
				_ground_normal = Vector3.ZERO
			else:
				var ground := _probe_ground()
				if not ground.is_empty():
					_settle(ground, delta)
					return
				_ground_normal = Vector3.ZERO
		_point_along_travel()
		return

	# The one place the two kinds part company. A rocket's fuse is the contact; a
	# grenade's is the clock, so arriving somewhere only stops it.
	#
	# "Somewhere" means the **environment**, though, and that qualifier is doing real
	# work. A grenade that shrugged off a body as well would be a launcher you cannot
	# hit anything moving with: a shell fired flat at a grunt twelve metres away
	# arrives at 33 m/s, and even after losing most of that to the impact it skips on
	# past and goes off somewhere behind the target. So a direct hit is still a direct
	# hit and only the level makes a shell drop — which also splits the weapon into two
	# honest uses, a hard shot that rewards aim and a lob that denies ground.
	# `apply_damage` is what tells a body from the level here, the same duck-type the
	# hitscan path uses.
	var collider := hit["collider"] as Node3D
	if kind == KIND_ROCKET or (collider != null and collider.has_method("apply_damage")):
		_detonate(hit["position"], hit["normal"], collider)
		return
	_settle(hit, delta)


## A grenade meeting a surface: put it on the surface, hand back a fraction of the speed
## it was going into it with, and rub off some of what is left along it.
##
## Those three lines are also the whole of the rolling, which is why there is no
## slope handling anywhere in this file. Gravity is added to the velocity every frame
## and the component into the surface is removed every frame, so what survives is the
## component *along* it — which is g·sinθ down the fall line, by construction and at
## whatever angle the surface happens to be. Flat ground leaves nothing and friction
## brings it to rest; a slope leaves a fraction that accumulates into a roll; rolling
## off an edge simply means the next sweep finds nothing and the shell is back in
## free fall with the speed it had. None of it needs to know the angle it is on.
##
## What it deliberately does not do is stick. A sticky grenade would keep the surface
## and stop here; that is the whole of the difference, and it is a separate feature.
func _settle(hit: Dictionary, delta: float) -> void:
	var normal := Vector3(hit["normal"])
	if normal.is_zero_approx():
		normal = Vector3.UP
	_ground_normal = normal
	# Touching anything is what takes the proximity fuse's slack away — see `_armed`.
	_armed = false
	# On the surface rather than in it, or the next sweep starts inside the geometry
	# and reports whatever it feels like.
	global_position = Vector3(hit["position"]) + normal * _radius

	# How hard it arrived, which is the one number both halves of an impact are scaled
	# from: what comes back out of the surface, and what is left travelling along it.
	var arrival := maxf(-_velocity.dot(normal), 0.0)
	if arrival > 0.0:
		# The speed going in is cancelled outright; what comes back out is a capped
		# fraction of it rather than a plain one — see `GRENADE_BOUNCE_MAX` — and only on
		# a real arrival, or resting contact is handed a sliver of rebound every frame.
		var rebound := 0.0
		if arrival > GRENADE_IMPACT_SPEED:
			rebound = minf(arrival * GRENADE_BOUNCE, GRENADE_BOUNCE_MAX)
		_velocity += normal * (arrival + rebound)

	# Friction on the tangential part alone. Applied to the whole velocity it would
	# also eat the bounce, which is a shell that lands differently depending on how
	# fast it happened to be travelling sideways.
	var along := _velocity - normal * _velocity.dot(normal)
	var lifted := _velocity - along
	# An arrival costs sideways speed as well as the speed going in, in proportion to how
	# hard it was. Rolling resistance is a per-second rate and cannot do this job — see
	# `GRENADE_SKID`.
	along *= lerpf(1.0, GRENADE_SKID, clampf(arrival / GRENADE_SKID_FULL, 0.0, 1.0))
	if along.length() <= GRENADE_REST_SPEED:
		along = Vector3.ZERO
	else:
		along = along.move_toward(Vector3.ZERO, GRENADE_ROLL_FRICTION * delta)
	_velocity = along + lifted


## The downward acceleration this shell flies under, m/s² — zero for a rocket, the
## project's own for a grenade. Asked for every frame rather than folded into a member
## at launch, for the same reason nothing else here caches a number it can derive.
func _gravity() -> float:
	var scale := GRAVITY_GRENADE if kind == KIND_GRENADE else GRAVITY_ROCKET
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 26.0)) * scale


## The body a grenade has just gone past close enough to go off beside, or null. A sphere
## query rather than a distance to anything's origin, because the answer wanted is "how far
## past this shell's skin is that thing's *surface*" and only the collider knows where its
## own surface is — an enemy's origin is between its feet, so measuring to it would make a
## shell over a grunt's head nearer than one at its chest.
##
## **Gone past** is the load-bearing word, and it is what makes a direct hit still possible.
## The slack reaches about a metre beyond a grunt, which at 34 m/s is two frames before
## contact — so a fuse that fired the moment the zone was entered would go off just short of
## every shell that was going to hit, and `INDIRECT_SHARE` would be the only outcome this
## weapon had. Triggering at the *closest approach* instead lets a shot that was on line
## arrive, and is where a real proximity fuse fires anyway; a miss goes off at the nearest
## point it ever got, which is also the best place for it.
##
## The world is left out of the mask on purpose: geometry is the sweep's business and a
## grenade is meant to touch it. Everything else on the mask is a body this shell was
## launched to hurt, so anything the query finds is a target by construction — the same
## trick `launch()` plays with the mask it builds, rather than any bookkeeping.
func _body_slipping_past(at: Vector3) -> Node3D:
	if _proximity == null:
		var sphere := SphereShape3D.new()
		sphere.radius = _radius + GRENADE_PROXIMITY
		_proximity = PhysicsShapeQueryParameters3D.new()
		_proximity.shape = sphere
		_proximity.collision_mask = collision_mask & ~LAYER_WORLD
		_proximity.collide_with_areas = false
	_proximity.transform = Transform3D(Basis(), at)
	var found := get_world_3d().direct_space_state.intersect_shape(_proximity, 1)
	if found.is_empty():
		return null
	var body := found[0].get("collider") as Node3D
	if body == null:
		return null
	var centre: Vector3 = body.global_position
	if body.has_method("body_centre"):
		centre = body.body_centre()
	# Still closing on it, so it may yet arrive — leave it alone and let the sweep have it.
	if _velocity.dot(centre - at) > 0.0:
		return null
	return body


## Whatever surface the shell is sitting on, looked for along that surface's own
## normal — which is exactly `_radius` away, whatever angle it is at, where straight
## down would be `_radius / cos θ` and would miss on anything steep. Falls back to
## down for the first frame after a landing, before there is a normal to remember.
func _probe_ground() -> Dictionary:
	var down := -_ground_normal if not _ground_normal.is_zero_approx() else Vector3.DOWN
	return get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(global_position,
			global_position + down * (_radius + SWEEP_SKIN * 2.0), collision_mask))


## Noses the shell along its own travel. Guarded on speed as well as on the up
## vector: a grenade at rest has no direction to point along, and normalising a zero
## velocity hands `look_at` a NaN.
func _point_along_travel() -> void:
	if _velocity.length_squared() < 0.01:
		return
	var direction := _velocity.normalized()
	if absf(direction.dot(Vector3.UP)) < 0.99:
		look_at(global_position + direction, Vector3.UP)


## The first thing in the way between two points, against the same mask the shell
## was launched with — so the shooter is filtered out by physics here exactly as it
## was for the overlap test, and no bookkeeping is needed.
##
## Reached out to the leading edge of the shell rather than to its centre, so it goes
## off against a surface instead of a frame inside one.
func _sweep(from: Vector3, to: Vector3) -> Dictionary:
	var reach := to - from
	if reach.length_squared() < 0.000001:
		return {}
	var far_end := to + reach.normalized() * (_radius + SWEEP_SKIN)
	return get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, far_end, collision_mask))


## The overlap fallback, and rockets only. A grenade has no contact fuse to trip, and
## the sweep is what stops it — so for one of these, being overlapped by something is
## not an event at all.
func _on_body_entered(body: Node3D) -> void:
	if kind != KIND_ROCKET:
		return
	# collision_mask already excludes the shooter, so anything we touch is a hit.
	_detonate(global_position, -_velocity.normalized(), body)


## `direct` is whether the shell went off *on* something that can be hurt, and it is
## passed rather than inferred from `hit` because two of the ways one of these can
## detonate hand over a perfectly good body that it nonetheless did not hit: the
## proximity fuse, which exists for near misses, and a fuse running out beside one.
func _detonate(at: Vector3, normal: Vector3, hit: Node3D, direct: bool = true) -> void:
	if _spent:
		return
	_spent = true
	set_physics_process(false)
	# FX must outlive us, so they are parented to whatever holds the projectile.
	var host := get_parent() as Node3D
	if host == null:
		queue_free()
		return

	var target := hit if hit != null and hit.has_method("apply_damage") else null
	var share := 1.0 if direct and target != null else INDIRECT_SHARE
	if blast_radius > 0.0:
		# `target_group` decides what this shell could *collide* with and is not passed
		# on: once it goes off, what it catches is everything within reach of it.
		#
		# `RIM_FLAT` and `share` are the two halves of one decision — see
		# `INDIRECT_SHARE`. The blast lands the same wherever in it you were standing,
		# and what it is worth was settled by whether the shell hit anything.
		CombatFX.explode(host, at, blast_radius, damage * share, punch,
				impact_force * share, CombatFX.RIM_FLAT)
	else:
		if target != null:
			target.apply_damage(damage * share, false, at, _velocity.normalized())
			# Same shove a hitscan round of the same weapon would land. Without this the
			# only weapon in the game whose round has a flight is the only one that
			# cannot push anything, which is backwards — it is the heaviest of the three.
			if impact_force > 0.0 and target.has_method("apply_knockback"):
				target.apply_knockback(_velocity.normalized() * impact_force * share)
		elif hit != null:
			# Hit something that cannot be hurt, which means the level. The normal is
			# the shot's own heading reversed rather than the surface's — an Area3D
			# reports what it touched, not where — so a hole from a steeply angled
			# shot is a little skewed. It is a hole in a wall either side of that.
			CombatFX.bullet_hole(host, hit, at, normal)
		CombatFX.impact(host, at, normal, color, 1.2 * punch)
	queue_free()
