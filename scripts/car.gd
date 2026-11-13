class_name Car
extends VehicleBody3D
## A drivable car built from a Kenney car-kit model. The model's `body` and
## four `wheel-…` parts become a physics body on four sprung wheels.
## Whoever is driving sets `throttle`, `steer_input` and `handbrake`.

const LENGTH := 4.0             ## metres; the model is scaled to this
const ENGINE_FORCE := 2600.0    ## per driven wheel
const REVERSE_FORCE := 1500.0
const BRAKE_FORCE := 40.0
const PARKING_BRAKE := 12.0
const ROLLING_DRAG := 1.5
const MAX_STEER := 0.55         ## radians at walking pace
const MIN_STEER := 0.12         ## radians at top speed
const STEER_SPEED := 2.2
const TOP_SPEED := 30.0         ## m/s forwards (about 110 km/h)
const TOP_REVERSE := 7.0

const SLEEP_DISTANCE := 130.0   ## parked cars this far from the camera stop simulating
const HIDE_DISTANCE := 300.0    ## and this far away they are not drawn

const WHEEL_NAMES := ["wheel-front-left", "wheel-front-right", "wheel-back-left", "wheel-back-right"]

var throttle := 0.0      ## -1 (reverse) to 1 (forwards)
var steer_input := 0.0   ## -1 (right) to 1 (left)
var handbrake := false
var driver: Node = null

var _tick := 0


## Builds the car from a model file. Call before adding it to the scene.
func setup(model_path: String) -> void:
	var model: Node3D = (load(model_path) as PackedScene).instantiate()
	var body := model.get_node("body") as MeshInstance3D
	var body_box: AABB = body.transform * body.mesh.get_aabb()
	var s := LENGTH / body_box.size.z

	mass = 1100.0
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.3, 0.0)
	add_to_group("cars")

	# The body shell, kept clear of the ground so the wheels carry the car.
	var clearance := 0.3
	var box := BoxShape3D.new()
	box.size = Vector3(body_box.size.x * s * 0.92, body_box.size.y * s - clearance, body_box.size.z * s)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(body_box.get_center().x * s,
		body_box.position.y * s + clearance + box.size.y / 2.0, body_box.get_center().z * s)
	add_child(shape)

	for wheel_name in WHEEL_NAMES:
		var mesh := model.get_node_or_null(wheel_name) as MeshInstance3D
		if mesh == null:
			continue
		var centre: Vector3 = mesh.transform * mesh.mesh.get_aabb().get_center()
		var radius: float = mesh.mesh.get_aabb().size.y / 2.0 * s
		var wheel := VehicleWheel3D.new()
		wheel.name = wheel_name
		wheel.wheel_radius = radius
		wheel.wheel_rest_length = 0.12
		wheel.suspension_travel = 0.15
		wheel.suspension_stiffness = 55.0
		wheel.suspension_max_force = 30000.0
		wheel.damping_compression = 2.2
		wheel.damping_relaxation = 3.4
		wheel.wheel_friction_slip = 3.0
		wheel.wheel_roll_influence = 0.05
		wheel.use_as_steering = wheel_name.contains("front")
		wheel.use_as_traction = wheel_name.contains("back")
		wheel.position = centre * s + Vector3(0.0, 0.08, 0.0)
		add_child(wheel)
		# Move the wheel mesh under the physics wheel, centred on the axle.
		mesh.owner = null
		model.remove_child(mesh)
		mesh.transform = Transform3D(mesh.transform.basis.scaled(Vector3.ONE * s),
			-(mesh.transform.basis * mesh.mesh.get_aabb().get_center()) * s)
		wheel.add_child(mesh)

	model.scale = Vector3.ONE * s
	model.name = "Model"
	add_child(model)


## Hides the body shell (used for the driver-seat view, where it would block
## the camera). The wheels stay visible.
func set_body_visible(shown: bool) -> void:
	get_node("Model").visible = shown
	freeze = false


## Speed along the direction the car is pointing, in m/s (negative in reverse).
func forward_speed() -> float:
	return linear_velocity.dot(global_basis.z)


## A city full of parked cars would waste a lot of physics time, so an empty
## car far from the camera is frozen in place until the camera comes back.
func _update_sleep() -> void:
	var camera := get_viewport().get_camera_3d()
	var distance := 0.0 if camera == null else global_position.distance_to(camera.global_position)
	freeze = distance > SLEEP_DISTANCE and driver == null
	if driver != null:
		return      # the player's view decides what is shown while driving
	get_node("Model").visible = distance < HIDE_DISTANCE
	for child in get_children():
		if child is VehicleWheel3D:
			(child as VehicleWheel3D).visible = get_node("Model").visible


func _physics_process(delta: float) -> void:
	_tick += 1
	if _tick % 45 == 1:
		_update_sleep()
	if freeze:
		return
	var speed := forward_speed()
	if driver == null:
		engine_force = 0.0
		brake = PARKING_BRAKE
		steering = move_toward(steering, 0.0, STEER_SPEED * delta)
		return

	# Less steering lock the faster the car goes, so it stays controllable.
	var lock := lerpf(MAX_STEER, MIN_STEER, clampf(absf(speed) / TOP_SPEED, 0.0, 1.0))
	steering = move_toward(steering, steer_input * lock, STEER_SPEED * delta)

	engine_force = 0.0
	brake = ROLLING_DRAG
	if handbrake:
		brake = BRAKE_FORCE
	elif throttle > 0.0:
		if speed < -0.5:
			brake = BRAKE_FORCE * throttle
		else:
			engine_force = ENGINE_FORCE * throttle * clampf(1.0 - speed / TOP_SPEED, 0.0, 1.0)
			brake = 0.0
	elif throttle < 0.0:
		if speed > 0.5:
			brake = BRAKE_FORCE * -throttle
		else:
			engine_force = REVERSE_FORCE * throttle * clampf(1.0 + speed / TOP_REVERSE, 0.0, 1.0)
			brake = 0.0
