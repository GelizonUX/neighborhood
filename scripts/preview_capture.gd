extends Node
## Saves preview screenshots of the neighbourhood and quits. It also acts as a
## small self-test: it walks through every camera view on foot, then gets into
## the nearest car, drives it and records how far it went.
## Only runs when the game is started with:  -- --capture <folder>
## Normal play is unaffected.

## name: [camera position, point the camera looks at]
const FIXED_VIEWS := {
	"overview": [Vector3(-38, 34, 46), Vector3(2, 0, -2)],
	"street": [Vector3(-34, 2.2, 0.8), Vector3(10, 2.0, -1.0)],
}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--capture")
	if at == -1 or at + 1 >= args.size():
		return
	_capture.call_deferred(args[at + 1])


func _capture(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var player := get_node("../Player")
	var rig := get_node("../CameraRig")
	var report := {}
	await _wait(1.5)     # let the cars settle on their suspension

	# Every on-foot camera view.
	rig.yaw = deg_to_rad(-60.0)
	for i in rig.FOOT_VIEWS.size():
		rig.set_view(i)
		await _wait(0.3)
		await _save(folder.path_join("foot_%d_%s.png" % [i, _slug(rig.current_view()["name"])]))
	rig.set_view(0)

	# The character from the front.
	rig.yaw = deg_to_rad(150.0)
	rig.pitch = deg_to_rad(-5.0)
	rig.zoom = 0.55
	await _wait(0.3)
	await _save(folder.path_join("character_front.png"))
	rig.yaw = deg_to_rad(-60.0)
	rig.set_view(0)

	# Get into the nearest car and drive it.
	var car: Node3D = player.nearest_car()
	if car == null:
		# Not standing next to one: walk over to the closest car in the street.
		var closest: Node3D = null
		for node in get_tree().get_nodes_in_group("cars"):
			if closest == null or player.global_position.distance_to(node.global_position) \
					< player.global_position.distance_to(closest.global_position):
				closest = node
		car = closest
	if car:
		report["car"] = String(car.name)
		report["car_rest_height"] = car.global_position.y
		player.enter_car(car)
		player.set_physics_process(false)   # the test drives instead of the keyboard
		var start: Vector3 = car.global_position
		car.throttle = 1.0
		await _wait(2.0)
		await _save(folder.path_join("car_0_chase.png"))
		report["speed_after_2s_kmh"] = car.forward_speed() * 3.6
		car.steer_input = 1.0
		await _wait(1.0)
		rig.set_view(1)
		await _wait(0.2)
		await _save(folder.path_join("car_1_driver_seat.png"))
		car.steer_input = 0.0
		car.throttle = 0.0
		car.handbrake = true
		await _wait(2.5)
		report["distance_driven_m"] = start.distance_to(car.global_position)
		report["speed_after_braking_kmh"] = car.forward_speed() * 3.6
		report["upright"] = car.global_basis.y.dot(Vector3.UP)
		car.handbrake = false
		player.set_physics_process(true)
		player.exit_car()
		report["got_out"] = player.car == null
		await _wait(0.5)
		await _save(folder.path_join("after_exit.png"))

	# Fixed cameras for an overall look.
	var camera := Camera3D.new()
	camera.far = 800.0
	camera.fov = 55.0
	add_child(camera)
	camera.make_current()
	for view_name in FIXED_VIEWS:
		camera.global_position = FIXED_VIEWS[view_name][0]
		camera.look_at(FIXED_VIEWS[view_name][1])
		await _wait(0.3)
		await _save(folder.path_join(view_name + ".png"))

	report["fps"] = Engine.get_frames_per_second()
	var file := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	get_tree().quit()


func _slug(text: String) -> String:
	return text.to_lower().replace(" ", "_").replace("'", "")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
