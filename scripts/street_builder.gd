extends Node3D
## Builds the starter street out of Kenney city-kit pieces when the game starts.
## Change the constants and lists below to reshape the neighbourhood.

## Kenney's city kits are modelled at 1 unit per road tile; one tile becomes 8 m.
const KIT_SCALE := 8.0
const TILE := 8.0
const SUBURBAN := "res://assets/kenney/suburban/"
const ROADS := "res://assets/kenney/roads/"
const CARS := "res://assets/kenney/cars/"

const ROAD_TILES := 10          ## straight tiles along the street (X axis)
const LOT_WIDTH := 20.0
const LOTS_PER_SIDE := 4
const FRONT_YARD := 6.0         ## pavement edge to the front wall of the house

## Houses used on each side of the street, left to right.
const NORTH_HOUSES := ["building-type-a", "building-type-f", "building-type-j", "building-type-s"]
const SOUTH_HOUSES := ["building-type-t", "building-type-c", "building-type-u", "building-type-g"]
const CAR_MODELS := ["sedan", "suv", "hatchback-sports", "van", "taxi", "sedan-sports", "truck", "suv-luxury"]

enum Collide { NONE, BOX, POST, SURFACE }

var _rng := RandomNumberGenerator.new()
## Things other scripts (camera previews, later gameplay) may want to find.
var houses: Array[Node3D] = []
var cars: Array[Node3D] = []
var trees: Array[Node3D] = []


func _ready() -> void:
	_rng.seed = 2026
	_build_ground()
	_build_road()
	for i in LOTS_PER_SIDE:
		var x := (i - (LOTS_PER_SIDE - 1) / 2.0) * LOT_WIDTH
		_build_lot(NORTH_HOUSES[i % NORTH_HOUSES.size()], x, -1.0, i)
		_build_lot(SOUTH_HOUSES[i % SOUTH_HOUSES.size()], x, 1.0, i + LOTS_PER_SIDE)
	_build_street_furniture()


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.72, 0.33)
	material.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000, 3000)
	plane.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	mesh.position.y = -0.02
	body.add_child(mesh)
	add_child(body)


func _build_road() -> void:
	var half := (ROAD_TILES - 1) / 2.0
	for i in ROAD_TILES:
		var x := (i - half) * TILE
		var piece := "road-crossing" if i == ROAD_TILES / 2 else "road-straight"
		_place(ROADS + piece + ".glb", Vector3(x, 0, 0), 0.0, KIT_SCALE, Collide.SURFACE)
	_place(ROADS + "road-end-round.glb", Vector3(-(half + 1) * TILE, 0, 0), 180.0, KIT_SCALE, Collide.SURFACE)
	_place(ROADS + "road-end-round.glb", Vector3((half + 1) * TILE, 0, 0), 0.0, KIT_SCALE, Collide.SURFACE)


## One house lot. `side` is -1 for the north side of the street, +1 for the south.
func _build_lot(house_name: String, x: float, side: float, index: int) -> void:
	var road_edge := TILE / 2.0
	var facing := 0.0 if side < 0.0 else 180.0   # front door towards the road

	var house := _place(SUBURBAN + house_name + ".glb", Vector3.ZERO, facing, KIT_SCALE, Collide.BOX)
	if house == null:
		return
	var size := _bounds(house).size * KIT_SCALE
	var house_z := side * (road_edge + FRONT_YARD + size.z / 2.0)
	house.position = Vector3(x, 0, house_z)
	houses.append(house)

	# Garden path from the pavement to the front of the house.
	var path_length := 0.4 * KIT_SCALE
	var z := road_edge + path_length / 2.0
	while z < road_edge + FRONT_YARD:
		_place(SUBURBAN + "path-long.glb", Vector3(x, 0.01, side * z), 0.0)
		z += path_length

	# Driveway beside the house, with a parked car on most lots.
	var drive_x := x + size.x / 2.0 + 2.2
	z = road_edge + path_length / 2.0
	for n in 3:
		_place(SUBURBAN + "driveway-long.glb", Vector3(drive_x, 0.01, side * z), 0.0)
		z += path_length
	if index % 4 != 3:
		var car_name: String = CAR_MODELS[index % CAR_MODELS.size()]
		var car := _place_car(car_name, Vector3(drive_x, 0.02, side * (road_edge + 5.5)),
			facing + _rng.randf_range(-3.0, 3.0))
		if car:
			cars.append(car)

	# Planting: two front-garden trees, one behind the house, planters by the door.
	var left := x - LOT_WIDTH / 2.0 + 2.0
	_tree(Vector3(left, 0, side * (road_edge + 2.5)))
	_tree(Vector3(left + 2.5, 0, side * (road_edge + FRONT_YARD + 3.0)))
	_tree(Vector3(x + _rng.randf_range(-4.0, 4.0), 0, house_z + side * (size.z / 2.0 + 4.0)))
	_place(SUBURBAN + "planter.glb", Vector3(x - 2.5, 0, side * (road_edge + FRONT_YARD - 1.2)),
		facing, KIT_SCALE * 0.6, Collide.BOX)

	# Fence along the left edge of the lot, behind the front garden.
	var fence_x := x - LOT_WIDTH / 2.0
	z = road_edge + FRONT_YARD + 2.0
	for n in 3:
		_place(SUBURBAN + "fence.glb", Vector3(fence_x, 0, side * z), 90.0, KIT_SCALE * 0.6, Collide.BOX)
		z += 0.48 * KIT_SCALE * 0.6


func _build_street_furniture() -> void:
	var kerb := TILE / 2.0 - 0.6
	for i in range(-2, 3):
		var x := i * LOT_WIDTH - LOT_WIDTH / 2.0
		var side := -1.0 if i % 2 == 0 else 1.0
		_place(ROADS + "light-square.glb", Vector3(x, 0, side * kerb), 90.0 + (90.0 * side),
			KIT_SCALE, Collide.POST)
	_place(ROADS + "road-sign-stop.glb", Vector3(4.6, 0, -kerb), 90.0, KIT_SCALE * 0.7, Collide.POST)
	_place(ROADS + "dumpster.glb", Vector3(-46.0, 0, 7.0), 20.0, KIT_SCALE * 0.6, Collide.BOX)

	# A couple of cars parked at the kerb.
	for entry in [["hatchback-sports", -14.0, 1.8, 90.0], ["suv", 22.0, -1.8, -90.0]]:
		var car := _place_car(entry[0], Vector3(entry[1], 0.02, entry[2]), entry[3])
		if car:
			cars.append(car)


func _tree(pos: Vector3) -> void:
	var model := "tree-large.glb" if _rng.randf() < 0.6 else "tree-small.glb"
	var tree := _place(SUBURBAN + model, pos, _rng.randf_range(0.0, 360.0),
		KIT_SCALE * _rng.randf_range(0.85, 1.2), Collide.POST)
	if tree:
		trees.append(tree)


## Cars are physics vehicles (see car.gd), so they can be driven.
func _place_car(car_name: String, pos: Vector3, yaw_degrees: float) -> Node3D:
	var path := CARS + car_name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var car := Car.new()
	car.setup(path)
	car.name = "Car_" + car_name.replace("-", "_") + "_" + str(cars.size())
	car.position = pos + Vector3(0.0, 0.35, 0.0)
	car.rotation.y = deg_to_rad(yaw_degrees)
	add_child(car)
	return car


func _place(path: String, pos: Vector3, yaw_degrees := 0.0, model_scale := KIT_SCALE,
		collide := Collide.NONE) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("Missing model: " + path)
		return null
	var node: Node3D = (load(path) as PackedScene).instantiate()
	node.position = pos
	node.rotation.y = deg_to_rad(yaw_degrees)
	node.scale = Vector3.ONE * model_scale
	add_child(node)
	if collide != Collide.NONE:
		_add_collision(node, collide)
	return node


## Adds a simple solid shape so the player cannot walk through the model.
func _add_collision(node: Node3D, kind: Collide) -> void:
	if kind == Collide.SURFACE:
		# Exact shape, so feet and wheels rest on the road and kerbs.
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).create_trimesh_collision()
		if node is MeshInstance3D:
			(node as MeshInstance3D).create_trimesh_collision()
		return
	var bounds := _bounds(node)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	if kind == Collide.POST:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.035
		cylinder.height = bounds.size.y
		shape.shape = cylinder
		shape.position = Vector3(0, bounds.size.y / 2.0, 0)
	else:
		var box := BoxShape3D.new()
		box.size = bounds.size
		shape.shape = box
		shape.position = bounds.get_center()
	body.add_child(shape)
	node.add_child(body)


## Size of a model in its own (unscaled) space.
func _bounds(node: Node3D) -> AABB:
	var result := [null]
	_collect_bounds(node, Transform3D.IDENTITY, result, true)
	return result[0] if result[0] != null else AABB()


func _collect_bounds(node: Node, xform: Transform3D, result: Array, is_root := false) -> void:
	if node is Node3D and not is_root:
		xform = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var box: AABB = xform * (node as MeshInstance3D).mesh.get_aabb()
		result[0] = box if result[0] == null else (result[0] as AABB).merge(box)
	for child in node.get_children():
		_collect_bounds(child, xform, result)
