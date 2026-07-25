extends StaticBody3D
## Refills reserve ammo on every carried weapon and patches the player up.
## Recharges after a delay so the arena never runs completely dry.

@export var ammo_fraction: float = 0.5
@export var heal_amount: float = 25.0
@export var recharge_time: float = 20.0

var _spent: bool = false

@onready var _mesh: MeshInstance3D = $Mesh


func interact_prompt() -> String:
	return "Supply crate — restock" if not _spent else "Supply crate — empty"


func interact(player: Node) -> void:
	if _spent:
		Events.notice.emit("Crate is empty")
		return

	var restocked := 0
	for inst in GameState.loadout:
		restocked += inst.add_reserve(int(round(inst.reserve_max() * ammo_fraction)))
		Events.ammo_changed.emit(inst)
	if player.has_method("heal"):
		player.heal(heal_amount)

	_spent = true
	_set_tint(Color(0.18, 0.18, 0.2))
	Events.notice.emit("Restocked %d rounds" % restocked)

	await get_tree().create_timer(recharge_time).timeout
	_spent = false
	_set_tint(Color(0.9, 0.7, 0.2))
	Events.notice.emit("Supply crate recharged")


func _ready() -> void:
	_set_tint(Color(0.9, 0.7, 0.2))


func _set_tint(color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35
	mat.metallic = 0.4
	mat.roughness = 0.5
	_mesh.material_override = mat
