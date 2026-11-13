class_name TrafficCar
extends AnimatableBody3D
## A car that drives itself around the road grid. It keeps to the right-hand
## lane, picks a new direction at every intersection, and stops for the player,
## people, parked cars and other traffic in front of it.

const LENGTH := 4.0
const LANE_OFFSET := 1.5        ## metres to the right of the road's centre line
const CORNER := 5.0             ## distance from an intersection where turns begin and end
const CRUISE_SPEED := 8.0       ## m/s, about 30 km/h
const TURN_SPEED := 4.0
const ACCELERATION := 3.0
const BRAKING := 9.0
const LOOK_AHEAD := 9.0
const LANE_WIDTH := 3.2
const IMPATIENCE := 5.0         ## seconds stuck behind traffic before nudging through
const TOO_FAR := 330.0          ## beyond this distance from the camera the car is moved closer
const RESPAWN_NEAR := 140.0
const RESPAWN_FAR := 280.0

var speed := 0.0

var _city: Node3D
var _from: Vector2i
var _to: Vector2i
var _next: Vector2i
var _turning := false
var _a := Vector3.ZERO          # start of the current stretch
var _b := Vector3.ZERO          # end of the current stretch
var _control := Vector3.ZERO    # bend point while turning
var _length := 1.0
var _travelled := 0.0
var _stuck := 0.0
var _is_blocked := false
var _tick := 0
var _wheels: Array[Node3D] = []
var _wheel_radius := 0.45
var _rng := RandomNumberGenerator.new()


## Builds the car and puts it on the road from intersection `from` towards `to`.
func setup(model_path: String, city: Node3D, from: Vector2i, to: Vector2i,
		fraction: float, random_seed: int) -> void:
	_city = city
	_from = from
	_to = to
	_rng.seed = random_seed
	sync_to_physics = false
	add_to_group("traffic")

	var model: Node3D = (load(model_path) as PackedScene).instantiate()
	var body := model.get_node("body") as MeshInstance3D
	var box: AABB = body.transform * body.mesh.get_aabb()
	var s := LENGTH / box.size.z
	model.scale = Vector3.ONE * s
	add_child(model)
	for child in model.get_children():
		if child.name.begins_with("wheel-") and child is MeshInstance3D:
			_wheels.append(child)
			_wheel_radius = (child as MeshInstance3D).mesh.get_aabb().size.y / 2.0 * s

	var shape := CollisionShape3D.new()
	var solid := BoxShape3D.new()
	solid.size = box.size * s
	shape.shape = solid
	shape.position = box.get_center() * s
	add_child(shape)

	_tick = random_seed % 240
	_begin_straight()
	_travelled = _length * fraction
	_apply_pose()


## Traffic only exists around the player: a car left far behind is put back
## on a road nearer by, out of plain sight.
func _keep_near_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or global_position.distance_to(camera.global_position) < TOO_FAR:
		return
	var road: Array = _city.random_road_near(camera.global_position, RESPAWN_NEAR, RESPAWN_FAR, _rng)
	if road.is_empty():
		return
	_from = road[0]
	_to = road[1]
	_begin_straight()
	_travelled = _length * _rng.randf_range(0.1, 0.8)
	speed = CRUISE_SPEED


func _physics_process(delta: float) -> void:
	_tick += 1
	if _tick % 240 == 0:
		_keep_near_camera()
	if _tick % 6 == 0:
		_is_blocked = _blocked(delta * 6.0)
	var limit := CRUISE_SPEED
	if _turning and (_b - _a).normalized().dot((_control - _a).normalized()) < 0.99:
		limit = TURN_SPEED
	elif not _turning and _length - _travelled < 7.0:
		limit = TURN_SPEED + 1.5
	if _is_blocked:
		limit = 0.0
	speed = move_toward(speed, limit, (ACCELERATION if limit > speed else BRAKING) * delta)

	_travelled += speed * delta
	if _travelled >= _length:
		var extra := _travelled - _length
		if _turning:
			_from = _to
			_to = _next
			_begin_straight()
		else:
			_begin_turn()
		_travelled = extra
	_apply_pose()
	for wheel in _wheels:
		wheel.rotate_object_local(Vector3.RIGHT, speed * delta / _wheel_radius)


func _right_of(direction: Vector3) -> Vector3:
	return Vector3(-direction.z, 0.0, direction.x)


func _begin_straight() -> void:
	var start: Vector3 = _city.node_position(_from)
	var end: Vector3 = _city.node_position(_to)
	var direction := (end - start).normalized()
	var lane := _right_of(direction) * LANE_OFFSET
	_a = start + direction * CORNER + lane
	_b = end - direction * CORNER + lane
	_length = _a.distance_to(_b)
	_turning = false


func _begin_turn() -> void:
	var centre: Vector3 = _city.node_position(_to)
	var direction: Vector3 = (centre - _city.node_position(_from)).normalized()
	# Anywhere except straight back the way we came.
	var options: Array[Vector2i] = _city.neighbours(_to)
	options.erase(_from)
	_next = options[_rng.randi() % options.size()]
	var out: Vector3 = (_city.node_position(_next) - centre).normalized()
	_a = _b
	_b = centre + out * CORNER + _right_of(out) * LANE_OFFSET
	if out.dot(direction) > 0.9:
		_control = (_a + _b) / 2.0
	else:
		_control = centre + (_right_of(direction) + _right_of(out)) * LANE_OFFSET
	_length = maxf((_a.distance_to(_control) + _control.distance_to(_b)) * 0.9, 0.5)
	_turning = true


func _apply_pose() -> void:
	var u := clampf(_travelled / _length, 0.0, 1.0)
	var pos: Vector3
	var heading: Vector3
	if _turning:
		pos = _a.lerp(_control, u).lerp(_control.lerp(_b, u), u)
		heading = (_control - _a).lerp(_b - _control, u)
	else:
		pos = _a.lerp(_b, u)
		heading = _b - _a
	pos.y = _city.road_y
	position = pos      # the city node sits at the origin, so this is the world position
	if heading.length() > 0.01:
		rotation.y = atan2(heading.x, heading.z)     # the model's front is +Z


## True when something is in the way just ahead.
func _blocked(delta: float) -> bool:
	var forward := global_basis.z
	var ignore_traffic := _stuck > IMPATIENCE
	var blocked := false
	for group in ["player", "people", "cars", "traffic"]:
		if group == "traffic" and ignore_traffic:
			continue
		for node in get_tree().get_nodes_in_group(group):
			if node == self or not (node as Node3D).is_visible_in_tree():
				continue
			var offset: Vector3 = (node as Node3D).global_position - global_position
			offset.y = 0.0
			# Only things in this car's own lane count, not people on the pavement.
			var ahead := forward.dot(offset)
			var sideways := (offset - forward * ahead).length()
			if ahead > 0.5 and ahead < LOOK_AHEAD and sideways < LANE_WIDTH / 2.0:
				blocked = true
	if blocked:
		_stuck += delta
	elif _stuck > IMPATIENCE + 2.0 or not ignore_traffic:
		_stuck = 0.0
	else:
		_stuck += delta
	return blocked
