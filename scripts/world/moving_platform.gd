extends AnimatableBody3D
## Platform that ping-pongs between its start position and `travel`.
##
## AnimatableBody3D with sync_to_physics carries the player along, so this needs
## no special handling in the controller.

## Offset from the platform's authored position, in world space.
@export var travel: Vector3 = Vector3(0.0, 6.0, 0.0)
@export var duration: float = 3.0
@export var pause_at_ends: float = 0.6
@export var start_delay: float = 0.0

var _origin: Vector3


func _ready() -> void:
	_origin = position
	sync_to_physics = true
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout
	_loop()


func _loop() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(self, "position", _origin + travel, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(pause_at_ends)
	tween.tween_property(self, "position", _origin, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(pause_at_ends)
