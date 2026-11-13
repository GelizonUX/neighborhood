extends Node
## Saves preview screenshots of the city and quits. It also acts as a small
## self-test: it walks through every camera view on foot, gets into the
## nearest car and drives it, and writes what it measured to report.json.
## Only runs when the game is started with:  -- --capture <folder>
## Normal play is unaffected.


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
	var city := get_node("../City")
	var people := get_node("../Population")
	var clock := get_node("../DayCycle")
	var report := {}
	var started := Time.get_ticks_msec()
	if not city.is_built:
		await city.built
	report["build_seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	await _wait(3.0)     # let the cars settle and people set off

	# Every on-foot camera view.
	for i in rig.FOOT_VIEWS.size():
		rig.set_view(i)
		await _wait(0.3)
		await _save(folder.path_join("foot_%d_%s.png" % [i, _slug(rig.current_view()["name"])]))
	rig.set_view(0)
	report["fps_street"] = Engine.get_frames_per_second()
	report["people_outdoors_morning"] = people.outdoors
	report["people_with_bodies_morning"] = people.bodies

	# Get into the closest parked car and drive it.
	var car: Node3D = null
	for node in get_tree().get_nodes_in_group("cars"):
		if car == null or player.global_position.distance_to(node.global_position) \
				< player.global_position.distance_to(car.global_position):
			car = node
	if car:
		report["car"] = String(car.name)
		report["car_distance_m"] = player.global_position.distance_to(car.global_position)
		player.enter_car(car)
		player.set_physics_process(false)   # the test drives instead of the keyboard
		await _wait(0.6)
		var start: Vector3 = car.global_position
		car.throttle = 1.0
		await _wait(2.0)
		await _save(folder.path_join("car_0_chase.png"))
		report["speed_after_2s_kmh"] = car.forward_speed() * 3.6
		rig.set_view(1)
		await _wait(0.2)
		await _save(folder.path_join("car_1_driver_seat.png"))
		car.throttle = 0.0
		car.handbrake = true
		await _wait(2.5)
		report["distance_driven_m"] = start.distance_to(car.global_position)
		report["upright"] = car.global_basis.y.dot(Vector3.UP)
		car.handbrake = false
		player.set_physics_process(true)
		player.exit_car()
		report["got_out"] = player.car == null

	# Fixed cameras around the city.
	var camera := Camera3D.new()
	camera.far = 2500.0
	camera.fov = 55.0
	add_child(camera)
	camera.make_current()
	var pond: Vector3 = city.pond_centres[0]
	var views := {
		"city_overview": [Vector3(-420, 330, 520), Vector3(0, 0, 0)],
		"downtown": [Vector3(-150, 60, 150), Vector3(0, 20, -20)],
		"river": [Vector3(-60, 14, 26), Vector3(40, 0, 0)],
		"park": [pond + Vector3(-30, 16, 34), pond],
		"homes": [Vector3(-250, 30, 190), Vector3(-180, 0, 120)],
	}
	for view_name in views:
		camera.global_position = views[view_name][0]
		camera.look_at(views[view_name][1])
		await _wait(1.2)     # time for nearby people to appear
		await _save(folder.path_join(view_name + ".png"))
		report["fps_" + view_name] = Engine.get_frames_per_second()

	# Night, to check the sky and lighting.
	clock.hour = 21.5
	camera.global_position = views["downtown"][0]
	camera.look_at(views["downtown"][1])
	await _wait(1.5)
	await _save(folder.path_join("night.png"))
	clock.hour = 8.5

	report["houses"] = city.house_count
	report["buildings"] = city.building_count
	report["trees"] = city.tree_count
	report["parked_cars"] = city.cars.size()
	report["traffic_cars"] = city.traffic.size()
	report["residents"] = people.residents.size()
	report["nodes"] = get_tree().get_node_count()
	report["city_size_m"] = [city.city_half_x * 2.0, city.city_south - city.city_north]
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
