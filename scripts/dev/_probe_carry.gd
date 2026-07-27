extends Node
## Throwaway: prints where the carry solve actually put each weapon and each hand.


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var player := main.get_node_or_null("Player") as Player
	var body := player.body

	for index in GameState.loadout.size():
		player.weapons.equip(index)
		await get_tree().create_timer(0.4).timeout
		var weapon := body.weapon_model()
		var data := GameState.loadout[index].data
		var aim := player.global_transform.basis.inverse() * -weapon.global_transform.basis.z
		var up := player.global_transform.basis.inverse() * weapon.global_transform.basis.y
		var at := player.to_local(weapon.global_position)
		print("--- %s" % data.id)
		print("  weapon at %+.3f %+.3f %+.3f" % [at.x, at.y, at.z])
		print("  aim      %+.3f %+.3f %+.3f" % [aim.x, aim.y, aim.z])
		print("  up       %+.3f %+.3f %+.3f" % [up.x, up.y, up.z])
		for side in [PlayerBody.SIDE_LEFT, PlayerBody.SIDE_RIGHT]:
			var hand := body.hand(side)
			var want: Transform3D = weapon.global_transform \
					* WeaponController.wrist_in_model_frame(data,
							WeaponController.HAND_LEFT if side == PlayerBody.SIDE_LEFT
							else WeaponController.HAND_RIGHT)
			var local := player.to_local(hand.global_position)
			print("  hand %d  at %+.3f %+.3f %+.3f  off anchor %.3f  elbow %.2f" % [
					side, local.x, local.y, local.z,
					hand.global_position.distance_to(want.origin),
					body._carry_elbow[side]])
	get_tree().quit()
