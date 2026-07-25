extends Area3D
## Moves the player's respawn point. Fires once, then goes quiet.

@export var label: String = "Checkpoint"

var _claimed: bool = false

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _claimed or not body.is_in_group("player"):
		return
	_claimed = true
	# Respawn facing the way the player was travelling, not the pad's rotation.
	var respawn := body.global_transform
	respawn.origin = global_position + Vector3.UP * 0.1
	body.spawn_transform = respawn
	Events.notice.emit("%s reached" % label)
	CombatFX.blast(get_parent() as Node3D, global_position, 1.8, Color(0.35, 1.0, 0.6))

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 1.0, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 1.0, 0.6)
	mat.emission_energy_multiplier = 1.2
	_mesh.material_override = mat
