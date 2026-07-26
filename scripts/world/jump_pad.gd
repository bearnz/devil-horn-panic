extends Area3D
## Launches whatever walks over it straight up (plus a little forward push).

@export var launch_speed: float = 18.0
## Extra push along the pad's -Z, for arcing jumps across gaps.
@export var forward_boost: float = 0.0
@export var cooldown: float = 0.35

var _ready_at: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _ready_at or not (body is CharacterBody3D):
		return
	_ready_at = now + cooldown

	var target := body as CharacterBody3D
	target.velocity.y = launch_speed
	if forward_boost > 0.0:
		var forward := -global_transform.basis.z
		target.velocity += Vector3(forward.x, 0.0, forward.z).normalized() * forward_boost

	CombatFX.blast(get_parent() as Node3D, global_position, 1.6, Color(0.4, 0.8, 1.0))
