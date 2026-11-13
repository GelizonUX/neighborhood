extends CharacterBody3D
## The player. On foot: WASD to move, Shift to run, Space to jump.
## E gets into the nearest car and out again; while driving, W/S accelerate
## and reverse, A/D steer and Space brakes. The camera lives in camera_rig.gd.

const WALK_SPEED := 3.0
const RUN_SPEED := 6.5
const JUMP_VELOCITY := 4.5
const ACCELERATION := 14.0
const TURN_SPEED := 10.0
const PUSH_FORCE := 2.0
const ENTER_DISTANCE := 3.6       ## how close to a car's centre you must be
const MAX_EXIT_SPEED := 3.0       ## m/s; the car must be nearly stopped to get out

const CHARACTER_MODEL := "res://assets/kenney/characters/character-male-a.glb"
const CHARACTER_HEIGHT := 1.75    ## metres
const MODEL_HEIGHT := 0.7         ## height of the Kenney mini character before scaling
const FEET_OFFSET := -0.9         ## the collision capsule is 1.8 m tall, centred on the player

@export var camera_rig_path: NodePath

@onready var rig: Node3D = get_node(camera_rig_path)
@onready var body: Node3D = $Body
@onready var collider: CollisionShape3D = $CollisionShape3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var car: Car = null               ## the car being driven, or null when on foot

var _animations: AnimationPlayer
var _current_clip := ""


func _ready() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("run", KEY_SHIFT)
	_add_key_action("interact", KEY_E)
	_load_character()
	rig.view_changed.connect(_on_view_changed)
	rig.follow(self, rig.FOOT_VIEWS, false)


func _add_key_action(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _load_character() -> void:
	if not ResourceLoader.exists(CHARACTER_MODEL):
		return
	var model: Node3D = (load(CHARACTER_MODEL) as PackedScene).instantiate()
	model.scale = Vector3.ONE * (CHARACTER_HEIGHT / MODEL_HEIGHT)
	model.position.y = FEET_OFFSET
	model.rotation.y = PI          # the model faces +Z, Body faces -Z
	body.add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_animations = players[0]
	for clip in ["idle", "walk", "sprint"]:
		if _animations.has_animation(clip):
			_animations.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_play("idle")


func _play(clip: String) -> void:
	if _animations == null or clip == _current_clip or not _animations.has_animation(clip):
		return
	_current_clip = clip
	_animations.play(clip, 0.15)


func _on_view_changed(_view_name: String) -> void:
	# Looking through the character's eyes, the model would block the view.
	body.visible = car == null and not rig.is_first_person()
	if car:
		car.set_body_visible(not rig.is_first_person())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if car:
			exit_car()
		else:
			var nearest := nearest_car()
			if nearest:
				enter_car(nearest)


## The closest car within reach, or null.
func nearest_car() -> Car:
	var best: Car = null
	var best_distance := ENTER_DISTANCE
	for node in get_tree().get_nodes_in_group("cars"):
		var distance := global_position.distance_to((node as Car).global_position)
		if distance < best_distance:
			best = node
			best_distance = distance
	return best


func enter_car(target: Car) -> void:
	car = target
	car.driver = self
	velocity = Vector3.ZERO
	collider.disabled = true
	body.visible = false
	rig.follow(car, rig.CAR_VIEWS, true)


func exit_car() -> void:
	if car == null or car.linear_velocity.length() > MAX_EXIT_SPEED:
		return
	var left_car := car
	car.set_body_visible(true)
	car.throttle = 0.0
	car.steer_input = 0.0
	car.handbrake = false
	car.driver = null
	car = null
	# Step out on the driver's side, facing the way the car points.
	global_position = left_car.global_position + left_car.global_basis.x.normalized() * 2.0 \
		+ Vector3.UP * 1.0
	body.rotation.y = rig.yaw
	collider.disabled = false
	rig.follow(self, rig.FOOT_VIEWS, false)


func _physics_process(delta: float) -> void:
	if car:
		car.throttle = Input.get_axis("move_back", "move_forward")
		car.steer_input = Input.get_axis("move_right", "move_left")
		car.handbrake = Input.is_action_pressed("jump")
		global_position = car.global_position + Vector3.UP * 1.0
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	# Move relative to where the camera is looking.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, rig.yaw)
	var running := Input.is_action_pressed("run")
	var target := direction * (RUN_SPEED if running else WALK_SPEED)

	velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)

	if rig.is_first_person():
		body.rotation.y = rig.yaw
	elif direction.length() > 0.1:
		var facing := atan2(-direction.x, -direction.z)
		body.rotation.y = lerp_angle(body.rotation.y, facing, TURN_SPEED * delta)

	move_and_slide()
	_update_animation()

	# Push loose physics objects we walk into.
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var other := collision.get_collider() as RigidBody3D
		if other and not other is VehicleBody3D:
			other.apply_central_impulse(-collision.get_normal() * PUSH_FORCE * delta * 60.0)


func _update_animation() -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor():
		_play("jump" if velocity.y > 0.0 else "fall")
	elif ground_speed > (WALK_SPEED + RUN_SPEED) * 0.5:
		_play("sprint")
	elif ground_speed > 0.3:
		_play("walk")
	else:
		_play("idle")
