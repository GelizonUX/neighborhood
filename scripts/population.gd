extends Node
## Everyone who lives in the city, and their daily routine.
##
## Each house has a resident with a home door, and either a job at a nearby
## shop or office or a favourite park. Through the day they commute, take a
## lunchtime walk, come home, stroll in the evening and stay in at night. They
## walk the pavements block by block and cross at the corners.
##
## Hundreds of people are tracked, but only those near the camera are given a
## body, so the city stays cheap to run.

const WALK_SPEED := 1.4
const SHOW_DISTANCE := 115.0
const HIDE_DISTANCE := 135.0
const MAX_BODIES := 70
const SLICES := 20              ## people without a body are updated in turns
const COMMUTE_RANGE := 190.0    ## how far someone will walk to work, metres
const HEIGHT := 1.75
const MODEL_HEIGHT := 0.7       ## height of the Kenney mini character before scaling
const CHARACTERS := "res://assets/kenney/characters/character-"
const MODELS := ["male-b", "male-c", "male-d", "male-e", "male-f",
	"female-b", "female-c", "female-d", "female-e", "female-f"]

@export var city_path: NodePath
@export var clock_path: NodePath

class Resident:
	var model := ""
	var speed := 1.4
	var home: Array             # [block, distance round the block's pavement]
	var plan: Array = []        # [[hour, [actions]], ...] for one day
	var plan_index := 0
	var queue: Array = []       # actions still to do
	var block := Vector2i.ZERO  # where they are standing when not walking
	var along := 0.0
	var path := PackedVector2Array()
	var segment := 0
	var segment_done := 0.0
	var walking := false
	var indoors := true
	var enter_at_end := false
	var position := Vector2.ZERO
	var facing := Vector2(0, 1)
	var last_update := 0.0
	var body: Node3D = null
	var animations: AnimationPlayer = null
	var clip := ""

var residents: Array[Resident] = []
var bodies := 0             ## how many people currently have a visible body
var outdoors := 0           ## how many people are out of their houses

@onready var _city: Node3D = get_node(city_path)
@onready var _clock: Node = get_node(clock_path)

var _rng := RandomNumberGenerator.new()
var _scenes := {}
var _frame := 0
var _time := 0.0
var _last_hour := 0.0


func _ready() -> void:
	set_process(false)
	_rng.seed = 99
	if not _city.is_built:
		await _city.built
	_create_residents()
	_last_hour = _clock.hour
	set_process(true)


func _create_residents() -> void:
	var parks: Array[Vector2i] = []
	for block in _city.blocks:
		if _city.blocks[block] == "park":
			parks.append(block)
	for door in _city.home_doors:
		var person := Resident.new()
		person.model = MODELS[_rng.randi() % MODELS.size()]
		person.speed = WALK_SPEED * _rng.randf_range(0.85, 1.2)
		person.home = door
		person.block = door[0]
		person.along = door[1]
		person.position = _loop_point(person.block, person.along)
		person.plan = _make_plan(person, parks)
		residents.append(person)


## One day in the life. Hours are on the 24-hour clock.
func _make_plan(person: Resident, parks: Array[Vector2i]) -> Array:
	var home_block: Vector2i = person.home[0]
	var here := person.position
	var plan := []
	var evening_walk := [17.8 + _rng.randf() * 2.5, [["lap", home_block], ["go", person.home, true]]]

	# Three in ten spend the day out and about rather than at work.
	if _rng.randf() < 0.3:
		var park := _nearest_block(parks, here)
		var outing := [["lap", home_block]]
		if park != Vector2i(-1, -1):
			outing = [["go", [park, _rng.randf_range(0.0, 150.0)], false], ["lap", park], ["lap", park]]
		plan.append([8.0 + _rng.randf() * 3.0, outing])
		plan.append([13.0 + _rng.randf() * 3.0, [["go", person.home, true]]])
		plan.append(evening_walk)
		return plan

	var work := _nearby_workplace(here)
	if work.is_empty():
		# Works from home: a morning and an evening walk round the block.
		plan.append([7.5 + _rng.randf() * 2.0, [["lap", home_block], ["go", person.home, true]]])
		plan.append(evening_walk)
		return plan
	plan.append([7.0 + _rng.randf() * 2.2, [["go", work, true]]])
	plan.append([11.8 + _rng.randf() * 1.4, [["lap", work[0]], ["go", work, true]]])
	plan.append([16.5 + _rng.randf() * 1.6, [["go", person.home, true]]])
	if _rng.randf() < 0.5:
		plan.append([19.0 + _rng.randf() * 1.5, [["lap", home_block], ["go", person.home, true]]])
	return plan


func _nearby_workplace(from: Vector2) -> Array:
	var best: Array = []
	for attempt in 12:
		var door: Array = _city.work_doors[_rng.randi() % _city.work_doors.size()]
		if _loop_point(door[0], door[1]).distance_to(from) < COMMUTE_RANGE:
			best = door
			break
	return best


func _nearest_block(candidates: Array[Vector2i], from: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := 260.0
	for block in candidates:
		var distance: float = _city.pavement_loop(block).get_center().distance_to(from)
		if distance < best_distance:
			best = block
			best_distance = distance
	return best


# =============================================================================
# Every frame
# =============================================================================

func _process(delta: float) -> void:
	_time += delta
	_frame += 1
	var hour: float = _clock.hour
	var new_day := hour < _last_hour
	_last_hour = hour
	var camera := get_viewport().get_camera_3d()
	var eye := Vector2.ZERO
	if camera:
		eye = Vector2(camera.global_position.x, camera.global_position.z)

	var count_outdoors := 0
	for i in residents.size():
		var person := residents[i]
		if new_day:
			person.plan_index = 0
		if not person.indoors:
			count_outdoors += 1
		# People with a body move every frame; the rest take turns.
		if person.body == null and i % SLICES != _frame % SLICES:
			continue
		var step := _time - person.last_update
		person.last_update = _time
		_update(person, step, hour)
		_update_body(person, eye)
	outdoors = count_outdoors


func _update(person: Resident, delta: float, hour: float) -> void:
	# Anything in today's plan that is now due gets added to the to-do list.
	while person.plan_index < person.plan.size() and hour >= person.plan[person.plan_index][0]:
		person.queue.append_array(person.plan[person.plan_index][1])
		person.plan_index += 1
	if not person.walking:
		if person.queue.is_empty():
			return
		_begin(person, person.queue.pop_front())
	_walk(person, delta)


func _begin(person: Resident, action: Array) -> void:
	person.indoors = false
	person.enter_at_end = false
	if action[0] == "go":
		var target: Array = action[1]
		person.path = _route(person.block, person.along, target[0], target[1])
		person.block = target[0]
		person.along = target[1]
		person.enter_at_end = action[2]
	else:
		# A lap of a block: get there if need be, then all the way round.
		var block: Vector2i = action[1]
		var start_along := person.along if block == person.block else 0.0
		var points := _route(person.block, person.along, block, start_along)
		var loop: Rect2 = _city.pavement_loop(block)
		var perimeter := _perimeter(loop)
		var ahead: Array[float] = []
		for corner in _corners(loop):
			var gap := fposmod(corner - start_along, perimeter)
			if gap > 0.01:
				ahead.append(gap)
		ahead.sort()
		for gap in ahead:
			points.append(_loop_point(block, start_along + gap))
		points.append(_loop_point(block, start_along))
		person.path = points
		person.block = block
		person.along = start_along
	person.segment = 0
	person.segment_done = 0.0
	person.walking = person.path.size() > 1
	if not person.walking and person.enter_at_end:
		person.indoors = true


func _walk(person: Resident, delta: float) -> void:
	var remaining := person.speed * delta
	while person.walking and remaining > 0.0:
		var from := person.path[person.segment]
		var to := person.path[person.segment + 1]
		var length := from.distance_to(to)
		var left := length - person.segment_done
		if length > 0.01:
			person.facing = (to - from) / length
		if remaining < left:
			person.segment_done += remaining
			person.position = from.lerp(to, person.segment_done / length)
			return
		remaining -= left
		person.segment += 1
		person.segment_done = 0.0
		person.position = to
		if person.segment >= person.path.size() - 1:
			person.walking = false
			if person.enter_at_end and person.queue.is_empty():
				person.indoors = true


## Gives a body to people near the camera and takes it away when they leave.
func _update_body(person: Resident, eye: Vector2) -> void:
	var distance := person.position.distance_to(eye)
	if person.body == null:
		if person.indoors or distance > SHOW_DISTANCE or bodies >= MAX_BODIES:
			return
		var path := CHARACTERS + person.model + ".glb"
		if not _scenes.has(path):
			_scenes[path] = load(path)
		var body := Node3D.new()
		var model: Node3D = (_scenes[path] as PackedScene).instantiate()
		model.scale = Vector3.ONE * (HEIGHT / MODEL_HEIGHT)
		body.add_child(model)
		body.add_to_group("people")
		add_child(body)
		person.body = body
		person.clip = ""
		var players := model.find_children("*", "AnimationPlayer", true, false)
		person.animations = players[0] if not players.is_empty() else null
		if person.animations:
			for clip in ["idle", "walk"]:
				if person.animations.has_animation(clip):
					person.animations.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		bodies += 1
	elif person.indoors or distance > HIDE_DISTANCE:
		person.body.queue_free()
		person.body = null
		person.animations = null
		bodies -= 1
		return

	person.body.position = Vector3(person.position.x, _city.pavement_y, person.position.y)
	person.body.rotation.y = atan2(person.facing.x, person.facing.y)     # the model's front is +Z
	var clip := "walk" if person.walking else "idle"
	if person.animations and clip != person.clip and person.animations.has_animation(clip):
		person.clip = clip
		person.animations.play(clip, 0.2)


# =============================================================================
# Finding the way along the pavements
# =============================================================================

func _perimeter(loop: Rect2) -> float:
	return (loop.size.x + loop.size.y) * 2.0


## Distances round the loop of its four corners, clockwise from the north-west.
func _corners(loop: Rect2) -> Array[float]:
	return [0.0, loop.size.x, loop.size.x + loop.size.y, loop.size.x * 2.0 + loop.size.y]


## The point `along` metres round a block's pavement, clockwise from its
## north-west corner.
func _loop_point(block: Vector2i, along: float) -> Vector2:
	var loop: Rect2 = _city.pavement_loop(block)
	var w := loop.size.x
	var d := loop.size.y
	var s := fposmod(along, _perimeter(loop))
	if s <= w:
		return Vector2(loop.position.x + s, loop.position.y)
	if s <= w + d:
		return Vector2(loop.end.x, loop.position.y + s - w)
	if s <= w * 2.0 + d:
		return Vector2(loop.end.x - (s - w - d), loop.end.y)
	return Vector2(loop.position.x, loop.end.y - (s - w * 2.0 - d))


func _loop_distance(loop: Rect2, from: float, to: float) -> float:
	var forward := fposmod(to - from, _perimeter(loop))
	return minf(forward, _perimeter(loop) - forward)


## Adds the points for walking round a block's pavement from `from` to `to`
## the shorter way, turning at each corner passed.
func _walk_loop(points: PackedVector2Array, block: Vector2i, from: float, to: float) -> void:
	var loop: Rect2 = _city.pavement_loop(block)
	var perimeter := _perimeter(loop)
	var forward := fposmod(to - from, perimeter)
	var direction := 1.0 if forward <= perimeter - forward else -1.0
	var remaining := forward if direction > 0.0 else perimeter - forward
	var current := from
	while remaining > 0.01:
		var step := remaining
		for corner in _corners(loop):
			var gap := fposmod((corner - current) * direction, perimeter)
			if gap > 0.01 and gap < step:
				step = gap
		current = fposmod(current + direction * step, perimeter)
		remaining -= step
		points.append(_loop_point(block, current))


## A walking route from one pavement spot to another: round each block to a
## corner, across the road to the next block, and so on.
func _route(from_block: Vector2i, from_along: float, to_block: Vector2i, to_along: float) -> PackedVector2Array:
	var points := PackedVector2Array([_loop_point(from_block, from_along)])
	var block := from_block
	var along := from_along
	var limits: Vector2i = _city.block_count()
	var guard := 0
	while block != to_block and guard < 64:
		guard += 1
		var loop: Rect2 = _city.pavement_loop(block)
		var w := loop.size.x
		var d := loop.size.y
		var gap := to_block - block
		var next := block
		# Each option: [distance round this block to leave from, corner to arrive at next]
		var options: Array
		if gap.x != 0 and (gap.y == 0 or absi(gap.x) >= absi(gap.y)):
			next.x += signi(gap.x)
			options = [[w, "nw"], [w + d, "sw"]] if gap.x > 0 else [[0.0, "ne"], [w * 2.0 + d, "se"]]
		else:
			next.y += signi(gap.y)
			options = [[w * 2.0 + d, "nw"], [w + d, "ne"]] if gap.y > 0 else [[0.0, "sw"], [w, "se"]]
		if next.x < 0 or next.y < 0 or next.x >= limits.x or next.y >= limits.y:
			break
		var choice: Array = options[0]
		if _loop_distance(loop, along, options[1][0]) < _loop_distance(loop, along, options[0][0]):
			choice = options[1]
		_walk_loop(points, block, along, choice[0])

		var next_loop: Rect2 = _city.pavement_loop(next)
		var arrive := 0.0
		match choice[1]:
			"ne": arrive = next_loop.size.x
			"se": arrive = next_loop.size.x + next_loop.size.y
			"sw": arrive = next_loop.size.x * 2.0 + next_loop.size.y
		block = next
		along = arrive
		points.append(_loop_point(block, along))
	_walk_loop(points, block, along, to_along)
	return points
