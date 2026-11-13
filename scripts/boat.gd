class_name Boat
extends Node3D
## A canoe drifting down the river, following its bends.

var _city: Node3D
var _lane := 0.0        # offset across the river from its centre line
var _speed := 1.5
var _time := 0.0


func setup(model_path: String, city: Node3D, start_x: float, lane: float, speed: float) -> void:
	_city = city
	_lane = lane
	_speed = speed
	var model: Node3D = (load(model_path) as PackedScene).instantiate()
	model.scale = Vector3.ONE * 4.0
	model.rotation.y = PI / 2.0     # the canoe's long side follows the river
	add_child(model)
	position.x = start_x
	_time = start_x


func _process(delta: float) -> void:
	_time += delta
	position.x += _speed * delta
	if position.x > _city.city_half_x + 40.0:
		position.x = -_city.city_half_x - 40.0
	position.z = _city.river_z(position.x) + _lane
	position.y = _city.WATER_LEVEL + 0.12 + sin(_time * 1.7) * 0.04
	rotation.z = sin(_time * 1.1) * 0.04
