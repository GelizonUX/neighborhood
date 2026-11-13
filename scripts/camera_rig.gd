extends Node3D
## The game camera. Follows a target (the player on foot, or the car being
## driven). V switches between views and the wheel zooms. Look around by moving
## the mouse after a click, by dragging with a button held, or with the arrow keys.

signal view_changed(view_name: String)

const MOUSE_SENSITIVITY := 0.003
const KEY_LOOK_SPEED := 2.2   ## radians per second with the arrow keys

## distance: how far behind the target the camera sits (0 = through the eyes)
## height:   metres above the target's origin
## side:     shoulder offset to the right
## forward:  metres ahead of the target's origin (used for the driver seat)
## pitch:    starting up/down angle in degrees
const FOOT_VIEWS := [
	{"name": "Third person", "distance": 5.0, "height": 0.7, "pitch": -15.0},
	{"name": "First person", "distance": 0.0, "height": 0.68, "pitch": 0.0, "first_person": true},
	{"name": "Over the shoulder", "distance": 2.2, "height": 0.6, "side": 0.6, "pitch": -8.0},
	{"name": "Bird's eye", "distance": 22.0, "height": 0.7, "pitch": -60.0},
]
const CAR_VIEWS := [
	{"name": "Chase", "distance": 7.5, "height": 1.5, "pitch": -14.0},
	{"name": "Driver seat", "distance": 0.0, "height": 1.35, "forward": 0.2, "pitch": -4.0, "first_person": true},
	{"name": "Bird's eye", "distance": 28.0, "height": 1.0, "pitch": -60.0},
]

var target: Node3D
var views: Array = FOOT_VIEWS
var view_index := 0
## Direction the camera looks, around the vertical axis. The player walks relative to this.
var yaw := 0.0
var pitch := 0.0
var zoom := 1.0

var _follow_heading := false   # true while driving: the camera turns with the car
var _heading_yaw := 0.0
var _look_offset := 0.0

@onready var arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	_add_key_action("camera", KEY_V)
	_add_key_action("look_left", KEY_LEFT)
	_add_key_action("look_right", KEY_RIGHT)
	_add_key_action("look_up", KEY_UP)
	_add_key_action("look_down", KEY_DOWN)


func _add_key_action(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


## Start following `node` using one of the view lists above.
func follow(node: Node3D, view_list: Array, follow_heading: bool) -> void:
	target = node
	views = view_list
	_follow_heading = follow_heading
	_look_offset = 0.0
	if follow_heading:
		_heading_yaw = _yaw_of(node)
	arm.clear_excluded_objects()
	if node is CollisionObject3D:
		arm.add_excluded_object((node as CollisionObject3D).get_rid())
	set_view(0)


func set_view(index: int) -> void:
	view_index = wrapi(index, 0, views.size())
	zoom = 1.0
	pitch = deg_to_rad(current_view().get("pitch", 0.0))
	view_changed.emit(current_view()["name"])
	_update()


func current_view() -> Dictionary:
	return views[view_index]


func is_first_person() -> bool:
	return current_view().get("first_person", false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera"):
		set_view(view_index + 1)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 0.1, 0.4, 2.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 0.1, 0.4, 2.5)
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion:
		# Look around with the mouse when it is captured, or while a button is
		# held and dragged (the fallback where a browser refuses to capture it).
		var dragging: bool = event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT) != 0
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or dragging:
			_look(-event.relative.x * MOUSE_SENSITIVITY, -event.relative.y * MOUSE_SENSITIVITY)


## Turns the camera by the given angles (radians).
func _look(yaw_change: float, pitch_change: float) -> void:
	if _follow_heading:
		_look_offset += yaw_change
	else:
		yaw += yaw_change
	pitch = clampf(pitch + pitch_change,
		deg_to_rad(-80.0), deg_to_rad(60.0 if is_first_person() else 20.0))


func _process(delta: float) -> void:
	if target == null:
		return
	# Arrow keys also look around.
	var turn := Input.get_axis("look_right", "look_left")
	var tilt := Input.get_axis("look_down", "look_up")
	if turn != 0.0 or tilt != 0.0:
		_look(turn * KEY_LOOK_SPEED * delta, tilt * KEY_LOOK_SPEED * 0.6 * delta)
	if _follow_heading:
		var wanted := _yaw_of(target)
		if is_first_person():
			_heading_yaw = wanted
		else:
			_heading_yaw = lerp_angle(_heading_yaw, wanted, 1.0 - exp(-5.0 * delta))
		yaw = _heading_yaw + _look_offset
	_update()


func _update() -> void:
	if target == null:
		return
	var view := current_view()
	var forward: float = view.get("forward", 0.0)
	global_position = target.global_position + Vector3.UP * view["height"] \
		+ target.global_basis.z.normalized() * forward
	rotation = Vector3(pitch, yaw, 0.0)
	arm.spring_length = view["distance"] * zoom
	arm.position.x = view.get("side", 0.0)


## The yaw that makes the camera look the way `node` is facing (its +Z, the
## front of the Kenney car models).
func _yaw_of(node: Node3D) -> float:
	var front := node.global_basis.z
	return atan2(-front.x, -front.z)
