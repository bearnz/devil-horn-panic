class_name Crosshair
extends Control
## Drawn rather than textured, so it can react to movement and register hits
## without any art assets.

@export var base_gap: float = 5.0
@export var arm_length: float = 7.0
@export var thickness: float = 2.0

var player: Player

var _gap_bonus: float = 0.0
var _hit_flash: float = 0.0
var _hit_was_crit: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_hit(is_crit: bool) -> void:
	_hit_flash = 1.0
	_hit_was_crit = is_crit


func _process(delta: float) -> void:
	# The reticle opens up as the player picks up speed and closes when aiming.
	var target := 0.0
	if is_instance_valid(player):
		var planar := Vector2(player.velocity.x, player.velocity.z).length()
		target = clampf(planar / 14.0, 0.0, 1.0) * 6.0
		if not player.is_on_floor():
			target += 2.0
		if player.weapons != null and player.weapons.aiming:
			target *= 0.35
	_gap_bonus = lerpf(_gap_bonus, target, clampf(delta * 8.0, 0.0, 1.0))
	_hit_flash = maxf(0.0, _hit_flash - delta * 3.2)
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var colour := Color(1.0, 1.0, 1.0, 0.85)
	var gap := base_gap + _gap_bonus

	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(centre + direction * gap, centre + direction * (gap + arm_length), colour, thickness)
	draw_rect(Rect2(centre - Vector2.ONE, Vector2(2.0, 2.0)), colour)

	if _hit_flash > 0.0:
		var hit_colour := Color(1.0, 0.45, 0.15) if _hit_was_crit else Color(1.0, 1.0, 1.0)
		hit_colour.a = _hit_flash
		var outer := 11.0 + (3.0 if _hit_was_crit else 0.0)
		var inner := 4.0
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_line(centre + corner * outer, centre + corner * inner, hit_colour, 2.0)
