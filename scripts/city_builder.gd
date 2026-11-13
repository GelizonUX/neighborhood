extends Node3D
## Builds the whole city when the game starts: terrain with a river and ponds,
## a grid of roads with bridges, house blocks, shops, a downtown, parks, parked
## cars, traffic, boats and loose physics objects.
##
## The city is far too big to give every tree and house its own node, so
## identical models are collected and drawn in batches (one MultiMesh per model
## per map chunk), and their collision shapes are grouped per chunk as well.
## Change the constants below to reshape the city.

signal progress(fraction: float)
signal built

const TILE := 8.0               ## metres per road tile
const KIT_SCALE := 8.0          ## Kenney city kits are 1 unit per tile
const NATURE_SCALE := 5.0       ## Kenney nature kit is smaller; trees end up 6-9 m tall
const CHUNK := 96.0             ## size of a batching chunk, metres

const ROADS := "res://assets/kenney/roads/"
const SUBURBAN := "res://assets/kenney/suburban/"
const COMMERCIAL := "res://assets/kenney/commercial/"
const NATURE := "res://assets/kenney/nature/"
const CARS := "res://assets/kenney/cars/"

# --- Layout, measured in road tiles -----------------------------------------
const BLOCK_W := 7              ## block size between north-south roads
const BLOCK_D := 5              ## block size between east-west roads
const RIVER_D := 4              ## width of the river band
const ROAD_COLUMNS := 13        ## number of north-south roads
## What lies between the east-west roads, from north to south.
const BANDS := ["homes", "homes", "homes", "mixed", "mixed", "river",
	"mixed", "mixed", "homes", "homes", "homes"]
const DOWNTOWN_COLUMNS := [4, 5, 6, 7]  ## block columns that are downtown in "mixed" bands
const TOWER_COLUMNS := [5, 6]           ## the tallest part of downtown
## (block column, band) of each park; every park has a pond.
const PARK_BLOCKS := [Vector2i(2, 4), Vector2i(9, 6), Vector2i(5, 1), Vector2i(7, 9)]

# --- Terrain -----------------------------------------------------------------
const TERRAIN_MARGIN := 48.0    ## hilly countryside around the city, metres
const TERRAIN_CELL := 2.0
const RIVER_HALF_WIDTH := 6.5
const BANK_WIDTH := 4.0
const RIVER_DEPTH := 1.1
const WATER_LEVEL := -0.3
const POND_RADII := Vector2(16.0, 11.0)
const POND_DEPTH := 1.0
const GRASS := Color(0.45, 0.72, 0.33)
const SAND := Color(0.82, 0.74, 0.5)

# --- Contents ----------------------------------------------------------------
const FRONT_YARD := 6.0         ## pavement edge to the front wall of a house
const LOTS_PER_SIDE := 3
const TRAFFIC_CARS := 30
const PARKED_CAR_EVERY := 7     ## one driveway in this many has a car you can drive
const BOATS := 5

## How far away things stay visible, metres (0 = always).
const VIEW_ALWAYS := 0.0
const VIEW_TREES := 420.0
const VIEW_PROPS := 190.0

const HOUSES := ["a", "c", "e", "f", "g", "h", "i", "j", "k", "l", "m", "o", "p", "q", "r", "s", "t", "u"]
const SHOPS := ["building-a", "building-b", "building-c", "building-d", "building-e",
	"building-f", "building-g", "building-h", "building-i", "building-k", "building-l"]
const TOWERS := ["building-m", "building-skyscraper-a", "building-skyscraper-b",
	"building-skyscraper-c", "building-skyscraper-d", "building-skyscraper-e"]
const CAR_MODELS := ["sedan", "suv", "hatchback-sports", "van", "taxi", "sedan-sports",
	"truck", "suv-luxury", "police", "delivery"]
const PARK_TREES := ["tree_default", "tree_oak", "tree_detailed", "tree_fat", "tree_simple",
	"tree_tall", "tree_pineRoundA", "tree_pineTallA"]
const SHORE_PLANTS := ["rock_largeA", "rock_largeB", "rock_smallA", "plant_bush",
	"plant_bushLarge", "flower_redA", "flower_yellowA", "flower_purpleA", "grass_large"]

const NATURE_COLOURS := {
	"leafsGreen": Color(0.36, 0.7, 0.32),
	"leafsDark": Color(0.2, 0.5, 0.3),
	"grass": Color(0.4, 0.72, 0.32),
	"woodBark": Color(0.56, 0.4, 0.28),
	"woodBarkDark": Color(0.45, 0.32, 0.24),
	"dirt": Color(0.62, 0.56, 0.5),
}

enum Collide { NONE, BOX, POST, SURFACE }

var road_columns: Array[int] = []   ## tile x of each north-south road
var road_rows: Array[int] = []      ## tile z of each east-west road
var grid_size := Vector2i.ZERO
var city_half_x := 0.0              ## the city spans -city_half_x..city_half_x
var city_north := 0.0               ## and city_north..city_south along Z
var city_south := 0.0
var pond_centres: Array[Vector3] = []
var road_y := 0.08                  ## height of the asphalt
var pavement_y := 0.16              ## height of the pavement
var bridge_drop := 0.0              ## how far the bridge model is lowered so its deck meets the road
var is_built := false

## What each block is: Vector2i(column, band) -> "homes", "shops", "downtown", "park" or "river".
var blocks := {}
## Pavement spots in front of buildings, as [block, distance round the block's pavement].
var home_doors: Array = []
var work_doors: Array = []
var cars: Array[Node3D] = []        ## parked cars the player can drive
var traffic: Array[Node3D] = []
var house_count := 0
var building_count := 0
var tree_count := 0

var _rng := RandomNumberGenerator.new()
var _origin_tx := 0.0
var _origin_tz := 0.0
var _lot_index := 0
var _parts_cache := {}      # model path -> [[Mesh, Transform3D], ...]
var _bounds_cache := {}     # model path -> AABB (unscaled)
var _surface_cache := {}    # model path -> ConcavePolygonShape3D (scaled)
var _batches := {}          # [Mesh, chunk, shadows] -> {"xforms": [], "range": float}
var _chunk_shapes := {}     # chunk -> [[Shape3D, Transform3D], ...]


func _ready() -> void:
	_rng.seed = 2026
	_plan()
	_build.call_deferred()


func _build() -> void:
	await _step(0.02)
	_build_terrain()
	_build_water()
	await _step(0.15)
	_build_roads()
	await _step(0.3)
	for band in BANDS.size():
		for col in ROAD_COLUMNS - 1:
			var rect := block_rect(col, band)
			match blocks[Vector2i(col, band)]:
				"homes": _build_home_block(Vector2i(col, band), rect)
				"shops": _build_commercial_block(Vector2i(col, band), rect, 0.0)
				"downtown": _build_commercial_block(Vector2i(col, band), rect,
					0.75 if col in TOWER_COLUMNS else 0.3)
				"park": _build_park(rect)
				"river": _build_riverside(rect)
		await _step(0.3 + 0.5 * (band + 1.0) / BANDS.size())
	_scatter_countryside()
	await _step(0.85)
	_flush_batches()
	await _step(0.95)
	_spawn_traffic()
	_spawn_boats()
	is_built = true
	progress.emit(1.0)
	built.emit()


func _step(fraction: float) -> void:
	progress.emit(fraction)
	await get_tree().process_frame
	await get_tree().process_frame


# =============================================================================
# Layout
# =============================================================================

func _plan() -> void:
	for c in ROAD_COLUMNS:
		road_columns.append(c * (BLOCK_W + 1))
	var z := 0
	var river_first_row := 0
	for band in BANDS:
		road_rows.append(z)
		z += 1
		if band == "river":
			river_first_row = z
		z += RIVER_D if band == "river" else BLOCK_D
	road_rows.append(z)
	grid_size = Vector2i(road_columns[-1] + 1, z + 1)
	# The city is centred left to right, with the river along z = 0.
	_origin_tx = (grid_size.x - 1) / 2.0
	_origin_tz = river_first_row + (RIVER_D - 1) / 2.0
	city_half_x = grid_size.x * TILE / 2.0
	city_north = -(_origin_tz + 0.5) * TILE
	city_south = (grid_size.y - 0.5 - _origin_tz) * TILE

	for band in BANDS.size():
		for col in ROAD_COLUMNS - 1:
			blocks[Vector2i(col, band)] = _block_kind(col, band)
	for park in PARK_BLOCKS:
		pond_centres.append(_rect_centre(block_rect(park.x, park.y)))
	_measure_road()


func _block_kind(col: int, band: int) -> String:
	if BANDS[band] == "river":
		return "river"
	if Vector2i(col, band) in PARK_BLOCKS:
		return "park"
	if BANDS[band] == "mixed" and col in DOWNTOWN_COLUMNS:
		return "downtown"
	# A sprinkling of local shops among the houses.
	if (col * 3 + band * 5) % 7 == 0:
		return "shops"
	return "homes"


## World position of the centre of a road tile.
func tile_centre(tx: int, tz: int) -> Vector3:
	return Vector3((tx - _origin_tx) * TILE, 0.0, (tz - _origin_tz) * TILE)


## The land between four roads, as a rectangle in the X/Z plane.
func block_rect(col: int, band: int) -> Rect2:
	var x0 := tile_centre(road_columns[col], 0).x + TILE / 2.0
	var x1 := tile_centre(road_columns[col + 1], 0).x - TILE / 2.0
	var z0 := tile_centre(0, road_rows[band]).z + TILE / 2.0
	var z1 := tile_centre(0, road_rows[band + 1]).z - TILE / 2.0
	return Rect2(x0, z0, x1 - x0, z1 - z0)


## The loop people walk round a block: the middle of the pavement.
func pavement_loop(block: Vector2i) -> Rect2:
	return block_rect(block.x, block.y).grow(0.4)


func block_count() -> Vector2i:
	return Vector2i(ROAD_COLUMNS - 1, BANDS.size())


## Where the player starts: on the pavement of a house block beside downtown.
func spawn_point() -> Vector3:
	var rect := block_rect(DOWNTOWN_COLUMNS[0] - 1, BANDS.size() - 4)
	return Vector3(rect.position.x + 18.0, pavement_y + 1.0, rect.end.y + 0.4)


func _rect_centre(rect: Rect2) -> Vector3:
	var c := rect.get_center()
	return Vector3(c.x, 0.0, c.y)


func _is_road(tx: int, tz: int) -> bool:
	if tx < 0 or tz < 0 or tx >= grid_size.x or tz >= grid_size.y:
		return false
	return tx in road_columns or tz in road_rows


## Reads the asphalt and pavement heights from the road model itself.
func _measure_road() -> void:
	var top := 0.0
	var lane := 0.0
	for part in _parts(ROADS + "road-straight.glb"):
		for vertex in (part[0] as Mesh).get_faces():
			var v: Vector3 = (part[1] as Transform3D) * vertex
			top = maxf(top, v.y)
			if absf(v.z) < 0.15:
				lane = maxf(lane, v.y)
	pavement_y = top * KIT_SCALE
	road_y = lane * KIT_SCALE
	# The bridge runs north-south, so its deck is the surface along x = 0.
	var deck := 0.0
	for part in _parts(ROADS + "road-bridge.glb"):
		for vertex in (part[0] as Mesh).get_faces():
			var v: Vector3 = (part[1] as Transform3D) * vertex
			if absf(v.x) < 0.15:
				deck = maxf(deck, v.y)
	bridge_drop = road_y - deck * KIT_SCALE


# --- Road network, used by traffic -------------------------------------------

## Intersections are identified by (road column index, road row index).
func node_position(id: Vector2i) -> Vector3:
	return tile_centre(road_columns[id.x], road_rows[id.y])


func neighbours(id: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var other: Vector2i = id + step
		if other.x >= 0 and other.y >= 0 and other.x < road_columns.size() and other.y < road_rows.size():
			result.append(other)
	return result


## A random stretch of road [from, to] whose start is between `nearest` and
## `farthest` metres from `centre`. Used to keep traffic around the player.
func random_road_near(centre: Vector3, nearest: float, farthest: float, rng: RandomNumberGenerator) -> Array:
	for attempt in 40:
		var from := Vector2i(rng.randi() % road_columns.size(), rng.randi() % road_rows.size())
		var distance := node_position(from).distance_to(centre)
		if distance < nearest or distance > farthest:
			continue
		var options := neighbours(from)
		return [from, options[rng.randi() % options.size()]]
	return []


# =============================================================================
# Terrain and water
# =============================================================================

## The river's centre line wanders a little inside its band.
func river_z(x: float) -> float:
	return 2.5 * sin(x * 0.035) * (1.0 - smoothstep(city_half_x - 60.0, city_half_x, absf(x)))


## Height of the ground at any point: flat in the city, gentle hills outside,
## dipping into the river and the ponds.
func height_at(x: float, z: float) -> float:
	var h := 0.0
	var outside := maxf(maxf(absf(x) - city_half_x, maxf(city_north - z, z - city_south)), 0.0)
	if outside > 6.0:
		var rise := smoothstep(6.0, 28.0, outside)
		var settle := 1.0 - smoothstep(TERRAIN_MARGIN - 14.0, TERRAIN_MARGIN - 2.0, outside)
		h = rise * settle * (1.8 + 1.5 * sin(x * 0.045) * cos(z * 0.05) + 0.8 * sin(x * 0.11 + z * 0.07))
	var river := 1.0 - smoothstep(RIVER_HALF_WIDTH, RIVER_HALF_WIDTH + BANK_WIDTH, absf(z - river_z(x)))
	h = lerpf(h, -RIVER_DEPTH, river)
	for centre in pond_centres:
		var dx := (x - centre.x) / POND_RADII.x
		var dz := (z - centre.z) / POND_RADII.y
		if absf(dx) < 1.0 and absf(dz) < 1.0:
			h = lerpf(h, -POND_DEPTH, 1.0 - smoothstep(0.55, 1.0, sqrt(dx * dx + dz * dz)))
	return h


func _build_terrain() -> void:
	var hx := city_half_x
	var m := TERRAIN_MARGIN
	var river_half := RIVER_D * TILE / 2.0

	# Shaped ground only where it is not flat: the river, the ponds, the hills.
	_terrain_patch(Rect2(-hx, -river_half, hx * 2.0, river_half * 2.0))
	for park in PARK_BLOCKS:
		_terrain_patch(block_rect(park.x, park.y))
	_terrain_patch(Rect2(-hx - m, city_north - m, (hx + m) * 2.0, m))
	_terrain_patch(Rect2(-hx - m, city_south, (hx + m) * 2.0, m))
	_terrain_patch(Rect2(-hx - m, city_north, m, city_south - city_north))
	_terrain_patch(Rect2(hx, city_north, m, city_south - city_north))

	# Flat ground for the rest of the city, with holes for the ponds.
	var flats: Array[Rect2] = [
		Rect2(-hx, city_north, hx * 2.0, -river_half - city_north),
		Rect2(-hx, river_half, hx * 2.0, city_south - river_half),
	]
	for park in PARK_BLOCKS:
		flats = _subtract(flats, block_rect(park.x, park.y))
	for rect in flats:
		_flat_ground(rect, 0.0, GRASS)

	# Flat land out to the horizon, split so the river can keep flowing.
	var far := 2000.0
	var bank := RIVER_HALF_WIDTH + BANK_WIDTH
	var edge_x := hx + m
	_flat_ground(Rect2(-far, -far, far * 2.0, far + city_north - m), 0.0, GRASS)
	_flat_ground(Rect2(-far, city_south + m, far * 2.0, far - city_south - m), 0.0, GRASS)
	for x0 in [-far, edge_x]:
		_flat_ground(Rect2(x0, city_north - m, far - edge_x, -bank - city_north + m), 0.0, GRASS)
		_flat_ground(Rect2(x0, bank, far - edge_x, city_south + m - bank), 0.0, GRASS)
		_flat_ground(Rect2(x0, -bank, far - edge_x, bank * 2.0), -RIVER_DEPTH, SAND)


## The rectangles left over after cutting `hole` out of each rectangle in `rects`.
func _subtract(rects: Array[Rect2], hole: Rect2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for rect in rects:
		if not rect.intersects(hole):
			result.append(rect)
			continue
		var cut := rect.intersection(hole)
		if cut.position.y > rect.position.y:
			result.append(Rect2(rect.position.x, rect.position.y, rect.size.x, cut.position.y - rect.position.y))
		if cut.end.y < rect.end.y:
			result.append(Rect2(rect.position.x, cut.end.y, rect.size.x, rect.end.y - cut.end.y))
		if cut.position.x > rect.position.x:
			result.append(Rect2(rect.position.x, cut.position.y, cut.position.x - rect.position.x, cut.size.y))
		if cut.end.x < rect.end.x:
			result.append(Rect2(cut.end.x, cut.position.y, rect.end.x - cut.end.x, cut.size.y))
	return result


## A piece of shaped ground following height_at().
func _terrain_patch(rect: Rect2) -> void:
	var nx := int(round(rect.size.x / TERRAIN_CELL))
	var nz := int(round(rect.size.y / TERRAIN_CELL))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz + 1:
		for ix in nx + 1:
			var x := rect.position.x + ix * TERRAIN_CELL
			var z := rect.position.y + iz * TERRAIN_CELL
			var h := height_at(x, z)
			# Sandy where the ground dips to the water, darker on the hills.
			var colour := GRASS.lerp(SAND, smoothstep(-0.05, -0.35, h))
			colour = colour.lerp(GRASS.darkened(0.18), clampf(h / 4.0, 0.0, 1.0))
			surface.set_color(colour)
			surface.add_vertex(Vector3(x, h, z))
	for iz in nz:
		for ix in nx:
			var i := iz * (nx + 1) + ix
			surface.add_index(i)
			surface.add_index(i + 1)
			surface.add_index(i + nx + 1)
			surface.add_index(i + 1)
			surface.add_index(i + nx + 2)
			surface.add_index(i + nx + 1)
	surface.generate_normals()
	var mesh := surface.commit()

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	var body := StaticBody3D.new()
	body.position.y = -0.02
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


func _flat_ground(rect: Rect2, y: float, colour: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = rect.size
	plane.material = material
	var body := StaticBody3D.new()
	body.position = Vector3(rect.get_center().x, y - 0.02, rect.get_center().y)
	var visual := MeshInstance3D.new()
	visual.mesh = plane
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, 4.0, rect.size.y)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position.y = -2.0
	body.add_child(shape)
	add_child(body)


func _build_water() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
// Gently moving, see-through water.
uniform vec3 deep : source_color = vec3(0.10, 0.40, 0.74);
uniform vec3 shallow : source_color = vec3(0.42, 0.74, 0.95);
uniform float flow = 0.6;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz * 0.35;
	p.x -= TIME * flow;
	float ripples = sin(p.x * 1.3) * sin(p.y * 1.7 + TIME * 0.5) + sin((p.x + p.y) * 0.7 + TIME * 0.3);
	ALBEDO = mix(deep, shallow, smoothstep(-0.6, 1.6, ripples) * 0.6);
	ALPHA = 0.78;
	ROUGHNESS = 0.12;
	METALLIC = 0.1;
}
"""
	var river_material := ShaderMaterial.new()
	river_material.shader = shader
	var river := PlaneMesh.new()
	river.size = Vector2(4000.0, (RIVER_HALF_WIDTH + BANK_WIDTH + 3.0) * 2.0)
	river.material = river_material
	var river_node := MeshInstance3D.new()
	river_node.name = "River"
	river_node.mesh = river
	river_node.position.y = WATER_LEVEL
	river_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(river_node)

	var pond_material := ShaderMaterial.new()
	pond_material.shader = shader
	pond_material.set_shader_parameter("flow", 0.0)
	var pond := CylinderMesh.new()
	pond.top_radius = 1.0
	pond.bottom_radius = 1.0
	pond.height = 0.02
	pond.radial_segments = 40
	pond.material = pond_material
	for centre in pond_centres:
		var pond_node := MeshInstance3D.new()
		pond_node.mesh = pond
		pond_node.position = centre + Vector3(0.0, WATER_LEVEL, 0.0)
		pond_node.scale = Vector3(POND_RADII.x * 0.95, 1.0, POND_RADII.y * 0.95)
		pond_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pond_node)


# =============================================================================
# Roads
# =============================================================================

func _build_roads() -> void:
	var river_band := BANDS.find("river")
	var water_rows: Array[int] = []
	if river_band != -1:
		for i in range(1, RIVER_D - 1):
			water_rows.append(road_rows[river_band] + 1 + i)

	for tz in grid_size.y:
		for tx in grid_size.x:
			if not _is_road(tx, tz):
				continue
			# Which sides connect to more road: east, north, west, south.
			var open := [_is_road(tx + 1, tz), _is_road(tx, tz - 1), _is_road(tx - 1, tz), _is_road(tx, tz + 1)]
			var piece := "road-straight"
			var quarter_turns := 0
			match open.count(true):
				4:
					piece = "road-crossroad"
				3:
					piece = "road-intersection"      # closed to the north when unrotated
					quarter_turns = posmod(open.find(false) - 1, 4)
				2:
					if open[0] and open[2]:
						if (tx % (BLOCK_W + 1)) == (BLOCK_W + 1) / 2:
							piece = "road-crossing"      # a zebra crossing mid-block
					elif open[1] and open[3]:
						if tz in water_rows:
							piece = "road-bridge"        # runs north-south when unrotated
						else:
							quarter_turns = 1
					else:
						piece = "road-bend"              # joins west and south when unrotated
						for k in 4:
							if open[(2 + k) % 4] and open[(3 + k) % 4]:
								quarter_turns = k
			var pos := tile_centre(tx, tz)
			if piece == "road-bridge":
				pos.y = bridge_drop      # the model's deck is raised; sink it to road level
			_put(ROADS + piece + ".glb", pos, quarter_turns * 90.0,
				KIT_SCALE, Collide.SURFACE, VIEW_ALWAYS, piece == "road-bridge")


# =============================================================================
# Blocks
# =============================================================================

func _build_home_block(block: Vector2i, rect: Rect2) -> void:
	var lot_width := rect.size.x / LOTS_PER_SIDE
	for i in LOTS_PER_SIDE:
		var x := rect.position.x + lot_width * (i + 0.5)
		_build_lot(block, rect, x, 1.0, lot_width)
		_build_lot(block, rect, x, -1.0, lot_width)
	_street_lights(rect)


## Distance round a block's pavement loop to the point in front of `x`, on the
## north side (inward = +1) or the south side (inward = -1).
func _door(block: Vector2i, x: float, inward: float) -> Array:
	var loop := pavement_loop(block)
	if inward > 0.0:
		return [block, x - loop.position.x]
	return [block, loop.size.x + loop.size.y + (loop.end.x - x)]


## One house lot. `inward` is +1 for a lot on the north edge of the block
## (running towards +Z) and -1 for one on the south edge.
func _build_lot(block: Vector2i, rect: Rect2, x: float, inward: float, lot_width: float) -> void:
	_lot_index += 1
	var edge_z := rect.position.y if inward > 0.0 else rect.end.y
	var facing := 180.0 if inward > 0.0 else 0.0     # front door towards the road
	var house: String = SUBURBAN + "building-type-" + HOUSES[_rng.randi() % HOUSES.size()] + ".glb"
	var size := _model_bounds(house).size * KIT_SCALE
	var house_z := edge_z + inward * (FRONT_YARD + size.z / 2.0)
	_put(house, Vector3(x, 0.0, house_z), facing, KIT_SCALE, Collide.BOX)
	house_count += 1
	home_doors.append(_door(block, x, inward))

	# Garden path and driveway: one stretched piece each.
	_put(SUBURBAN + "path-long.glb", Vector3(x, 0.01, edge_z + inward * FRONT_YARD / 2.0), 0.0,
		Vector3(KIT_SCALE, KIT_SCALE, FRONT_YARD / 0.4), Collide.NONE, VIEW_PROPS, false)
	var drive_x := x + size.x / 2.0 + 2.1
	var drive_length := FRONT_YARD + 3.6
	_put(SUBURBAN + "driveway-long.glb", Vector3(drive_x, 0.01, edge_z + inward * drive_length / 2.0), 0.0,
		Vector3(KIT_SCALE, KIT_SCALE, drive_length / 0.4), Collide.NONE, VIEW_PROPS, false)
	if _lot_index % PARKED_CAR_EVERY == 0:
		_place_car(CAR_MODELS[_rng.randi() % CAR_MODELS.size()],
			Vector3(drive_x, 0.02, edge_z + inward * 5.5), facing + _rng.randf_range(-3.0, 3.0))

	# Planting and a bit of fence on the lot line.
	_garden_tree(Vector3(x - lot_width / 2.0 + 1.6, 0.0, edge_z + inward * 2.6))
	_garden_tree(Vector3(x + _rng.randf_range(-4.0, 4.0), 0.0, house_z + inward * (size.z / 2.0 + 3.0)))
	_put(SUBURBAN + "planter.glb", Vector3(x - 2.6, 0.0, edge_z + inward * (FRONT_YARD - 1.2)),
		facing, KIT_SCALE * 0.6, Collide.BOX, VIEW_PROPS)
	# A straight run of fence on the lot line, behind the driveways.
	_put(SUBURBAN + "fence.glb", Vector3(x - lot_width / 2.0, 0.0, edge_z + inward * (FRONT_YARD + 8.5)),
		90.0, Vector3(12.5, 4.8, 4.8), Collide.BOX, VIEW_PROPS)


func _garden_tree(pos: Vector3) -> void:
	if _rng.randf() < 0.5:
		var model := "tree-large.glb" if _rng.randf() < 0.6 else "tree-small.glb"
		_put(SUBURBAN + model, pos, _rng.randf_range(0.0, 360.0),
			KIT_SCALE * _rng.randf_range(0.85, 1.2), Collide.POST, VIEW_TREES)
		tree_count += 1
	else:
		_nature_tree(pos)


func _nature_tree(pos: Vector3, scale_range := Vector2(0.8, 1.15)) -> void:
	var model: String = PARK_TREES[_rng.randi() % PARK_TREES.size()]
	_put(NATURE + model + ".glb", pos, _rng.randf_range(0.0, 360.0),
		NATURE_SCALE * _rng.randf_range(scale_range.x, scale_range.y), Collide.POST, VIEW_TREES)
	tree_count += 1


## Shops or downtown: buildings along the north and south edges on paving.
## `tower_chance` is how likely each building is to be a tall one.
func _build_commercial_block(block: Vector2i, rect: Rect2, tower_chance: float) -> void:
	var lot_width := rect.size.x / LOTS_PER_SIDE
	for i in LOTS_PER_SIDE:
		var x := rect.position.x + lot_width * (i + 0.5)
		for inward in [1.0, -1.0]:
			var edge_z: float = rect.position.y if inward > 0.0 else rect.end.y
			var pool: Array = TOWERS if _rng.randf() < tower_chance else SHOPS
			var building: String = COMMERCIAL + pool[_rng.randi() % pool.size()] + ".glb"
			var size := _model_bounds(building).size * KIT_SCALE
			_put(building, Vector3(x, 0.0, edge_z + inward * (2.5 + size.z / 2.0)),
				180.0 if inward > 0.0 else 0.0, KIT_SCALE, Collide.BOX)
			building_count += 1
			work_doors.append(_door(block, x, inward))
			_put(SUBURBAN + "planter.glb", Vector3(x + size.x / 2.0 + 1.2, 0.0, edge_z + inward * 1.4),
				0.0, KIT_SCALE * 0.6, Collide.BOX, VIEW_PROPS)
	# Paved ground instead of lawn.
	var paving := StandardMaterial3D.new()
	paving.albedo_color = Color(0.72, 0.74, 0.8)
	paving.roughness = 0.9
	var plane := PlaneMesh.new()
	plane.size = rect.size
	plane.material = paving
	var plaza := MeshInstance3D.new()
	plaza.mesh = plane
	plaza.position = _rect_centre(rect) + Vector3(0.0, 0.03, 0.0)
	plaza.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plaza)
	# A tree or two in the middle, and a kerbside car you can drive.
	for i in 3:
		_nature_tree(Vector3(_rng.randf_range(rect.position.x + 6.0, rect.end.x - 6.0), 0.0,
			rect.get_center().y + _rng.randf_range(-1.5, 1.5)))
	if _rng.randf() < 0.6:
		_place_car(CAR_MODELS[_rng.randi() % CAR_MODELS.size()],
			Vector3(rect.end.x + 2.3, road_y, rect.get_center().y + _rng.randf_range(-8.0, 8.0)), 0.0)
	_spawn_street_props(rect)
	_street_lights(rect)


func _build_park(rect: Rect2) -> void:
	var centre := _rect_centre(rect)
	# Trees around the edge, keeping clear of the pond.
	for i in 46:
		var pos := Vector3(_rng.randf_range(rect.position.x + 2.0, rect.end.x - 2.0), 0.0,
			_rng.randf_range(rect.position.y + 2.0, rect.end.y - 2.0))
		if Vector2((pos.x - centre.x) / POND_RADII.x, (pos.z - centre.z) / POND_RADII.y).length() < 1.25:
			continue
		_nature_tree(pos, Vector2(0.9, 1.3))
	# Rocks, bushes and flowers on the shore; lilies and a canoe on the water.
	for i in 26:
		var angle := _rng.randf_range(0.0, TAU)
		var pos := centre + Vector3(cos(angle) * POND_RADII.x, 0.0, sin(angle) * POND_RADII.y) * _rng.randf_range(1.02, 1.2)
		pos.y = height_at(pos.x, pos.z)
		_put(NATURE + SHORE_PLANTS[_rng.randi() % SHORE_PLANTS.size()] + ".glb", pos,
			_rng.randf_range(0.0, 360.0), NATURE_SCALE * 0.7, Collide.NONE, VIEW_PROPS)
	for i in 9:
		var angle := _rng.randf_range(0.0, TAU)
		var spot := Vector3(cos(angle) * POND_RADII.x, 0.0, sin(angle) * POND_RADII.y) * _rng.randf_range(0.15, 0.6)
		_put(NATURE + ("lily_large.glb" if i % 2 == 0 else "lily_small.glb"),
			centre + spot + Vector3(0.0, WATER_LEVEL + 0.2, 0.0), _rng.randf_range(0.0, 360.0),
			NATURE_SCALE * 0.8, Collide.NONE, VIEW_PROPS, false)
	_put(NATURE + "canoe.glb", centre + Vector3(4.0, WATER_LEVEL + 0.15, -2.0), 35.0,
		NATURE_SCALE * 0.8, Collide.NONE, VIEW_PROPS)
	_put(NATURE + "statue_column.glb", Vector3(rect.position.x + 6.0, 0.0, rect.end.y - 6.0), 0.0,
		NATURE_SCALE * 0.6, Collide.POST, VIEW_PROPS)
	# Balls to kick around.
	for i in 3:
		_spawn_ball(centre + Vector3(_rng.randf_range(-24.0, 24.0), 0.6, POND_RADII.y + 5.0 + i))
	_street_lights(rect)


## The grassy strip either side of the river, between two bridges.
func _build_riverside(rect: Rect2) -> void:
	for i in 22:
		var x := _rng.randf_range(rect.position.x + 1.0, rect.end.x - 1.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := river_z(x) + side * _rng.randf_range(RIVER_HALF_WIDTH + BANK_WIDTH + 0.5, 15.0)
		var h := height_at(x, z)
		if h < -0.05:
			continue
		if i % 3 == 0:
			_put(NATURE + SHORE_PLANTS[_rng.randi() % 5] + ".glb", Vector3(x, h, z),
				_rng.randf_range(0.0, 360.0), NATURE_SCALE * 0.7, Collide.NONE, VIEW_PROPS)
		else:
			_nature_tree(Vector3(x, h, z))
	for i in 3:
		var x := _rng.randf_range(rect.position.x + 6.0, rect.end.x - 6.0)
		_put(NATURE + "lily_large.glb", Vector3(x, WATER_LEVEL + 0.2, river_z(x) + _rng.randf_range(-4.0, 4.0)),
			_rng.randf_range(0.0, 360.0), NATURE_SCALE * 0.8, Collide.NONE, VIEW_PROPS, false)


## Woods on the hills around the city.
func _scatter_countryside() -> void:
	var reach := TERRAIN_MARGIN - 3.0
	var placed := 0
	var tries := 0
	while placed < 420 and tries < 6000:
		tries += 1
		var x := _rng.randf_range(-city_half_x - reach, city_half_x + reach)
		var z := _rng.randf_range(city_north - reach, city_south + reach)
		if absf(x) < city_half_x + 5.0 and z > city_north - 5.0 and z < city_south + 5.0:
			continue
		var h := height_at(x, z)
		if h < -0.05:
			continue
		_nature_tree(Vector3(x, h, z), Vector2(0.9, 1.5))
		placed += 1


## Two lamps on the pavement along the north and south edges of a block.
func _street_lights(rect: Rect2) -> void:
	for x in [rect.position.x + 9.0, rect.end.x - 9.0]:
		_put(ROADS + "light-square.glb", Vector3(x, 0.0, rect.position.y - 0.5), 180.0,
			KIT_SCALE, Collide.POST, VIEW_PROPS)
		_put(ROADS + "light-square.glb", Vector3(x, 0.0, rect.end.y + 0.5), 0.0,
			KIT_SCALE, Collide.POST, VIEW_PROPS)


# =============================================================================
# Things that move
# =============================================================================

## A parked car the player can get into and drive (see car.gd).
func _place_car(car_name: String, pos: Vector3, yaw_degrees: float) -> void:
	var path := CARS + car_name + ".glb"
	if not ResourceLoader.exists(path):
		return
	var car := Car.new()
	car.setup(path)
	car.name = "Car_%s_%d" % [car_name.replace("-", "_"), cars.size()]
	car.position = pos + Vector3(0.0, 0.35, 0.0)
	car.rotation.y = deg_to_rad(yaw_degrees)
	add_child(car)
	cars.append(car)


## Cars that drive themselves around the road grid (see traffic_car.gd).
func _spawn_traffic() -> void:
	var start := spawn_point()
	for i in TRAFFIC_CARS:
		var road := random_road_near(start, 0.0, 320.0, _rng)
		if road.is_empty():
			continue
		var car := TrafficCar.new()
		car.setup(CARS + CAR_MODELS[_rng.randi() % CAR_MODELS.size()] + ".glb", self,
			road[0], road[1], _rng.randf_range(0.1, 0.8), _rng.randi())
		car.name = "Traffic_%d" % traffic.size()
		add_child(car)
		traffic.append(car)


## Canoes drifting down the river (see boat.gd).
func _spawn_boats() -> void:
	for i in BOATS:
		var boat := Boat.new()
		boat.setup(NATURE + "canoe.glb", self, _rng.randf_range(-city_half_x, city_half_x),
			_rng.randf_range(-3.0, 3.0), _rng.randf_range(1.2, 2.2))
		add_child(boat)


## Loose cones and boxes on a pavement: things to knock over.
func _spawn_street_props(rect: Rect2) -> void:
	for i in 3:
		var model := "cone.glb" if i < 2 else "box.glb"
		var path := CARS + model
		if not ResourceLoader.exists(path):
			continue
		var body := RigidBody3D.new()
		body.mass = 3.0 if i < 2 else 8.0
		var visual: Node3D = (load(path) as PackedScene).instantiate()
		var s := 1.6
		visual.scale = Vector3.ONE * s
		body.add_child(visual)
		var bounds := _model_bounds(path)
		var box := BoxShape3D.new()
		box.size = bounds.size * s
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = bounds.get_center() * s
		body.add_child(shape)
		body.position = Vector3(_rng.randf_range(rect.position.x + 4.0, rect.end.x - 4.0), 0.3,
			rect.end.y - _rng.randf_range(0.8, 2.0))
		add_child(body)


func _spawn_ball(pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.mass = 0.45
	var bounce := PhysicsMaterial.new()
	bounce.bounce = 0.6
	bounce.friction = 0.7
	body.physics_material_override = bounce
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color.from_hsv(_rng.randf(), 0.7, 0.95)
	sphere.material = paint
	var visual := MeshInstance3D.new()
	visual.mesh = sphere
	body.add_child(visual)
	var ball := SphereShape3D.new()
	ball.radius = 0.3
	var shape := CollisionShape3D.new()
	shape.shape = ball
	body.add_child(shape)
	body.position = pos
	add_child(body)


# =============================================================================
# Batching
# =============================================================================

## The meshes inside a model file, each with its position inside the model.
func _parts(path: String) -> Array:
	if not _parts_cache.has(path):
		var parts := []
		var root: Node = (load(path) as PackedScene).instantiate()
		_collect_parts(root, Transform3D.IDENTITY, parts, true)
		root.free()
		var bounds = null
		for part in parts:
			var box: AABB = (part[1] as Transform3D) * (part[0] as Mesh).get_aabb()
			bounds = box if bounds == null else (bounds as AABB).merge(box)
		_parts_cache[path] = parts
		_bounds_cache[path] = bounds if bounds != null else AABB()
		if path.begins_with(NATURE):
			_recolour(parts)
	return _parts_cache[path]


## The nature kit's greens come out turquoise next to the city kits, so its
## materials are repainted to match the lawns.
func _recolour(parts: Array) -> void:
	for part in parts:
		var mesh: Mesh = part[0]
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i) as BaseMaterial3D
			if material and NATURE_COLOURS.has(material.resource_name):
				material.albedo_color = NATURE_COLOURS[material.resource_name]


func _collect_parts(node: Node, xform: Transform3D, parts: Array, is_root := false) -> void:
	if node is Node3D and not is_root:
		xform = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		parts.append([(node as MeshInstance3D).mesh, xform])
	for child in node.get_children():
		_collect_parts(child, xform, parts)


## Size of a model before scaling.
func _model_bounds(path: String) -> AABB:
	_parts(path)
	return _bounds_cache[path]


## Adds a model to the city. `model_scale` is a number or a Vector3.
func _put(path: String, pos: Vector3, yaw_degrees := 0.0, model_scale: Variant = KIT_SCALE,
		collide := Collide.NONE, view_range := VIEW_ALWAYS, shadows := true) -> void:
	if not ResourceLoader.exists(path):
		push_warning("Missing model: " + path)
		return
	var s: Vector3 = model_scale if model_scale is Vector3 else Vector3.ONE * float(model_scale)
	var turn := Basis(Vector3.UP, deg_to_rad(yaw_degrees))
	var xform := Transform3D(turn * Basis.from_scale(s), pos)
	var chunk := Vector2i(floori(pos.x / CHUNK), floori(pos.z / CHUNK))
	for part in _parts(path):
		var key := [part[0], chunk, shadows]
		if not _batches.has(key):
			_batches[key] = {"xforms": [], "range": view_range}
		_batches[key]["xforms"].append(xform * (part[1] as Transform3D))

	if collide == Collide.NONE:
		return
	if not _chunk_shapes.has(chunk):
		_chunk_shapes[chunk] = []
	var bounds := _model_bounds(path)
	match collide:
		Collide.BOX:
			var box := BoxShape3D.new()
			box.size = bounds.size * s
			_chunk_shapes[chunk].append([box, Transform3D(turn, pos + turn * (bounds.get_center() * s))])
		Collide.POST:
			var post := CylinderShape3D.new()
			post.radius = 0.28
			post.height = bounds.size.y * s.y
			_chunk_shapes[chunk].append([post, Transform3D(Basis.IDENTITY, pos + Vector3.UP * post.height / 2.0)])
		Collide.SURFACE:
			_chunk_shapes[chunk].append([_surface_shape(path, s), Transform3D(turn, pos)])


## The exact shape of a model (used for roads), already scaled, shared by
## every copy of that model.
func _surface_shape(path: String, s: Vector3) -> ConcavePolygonShape3D:
	if not _surface_cache.has(path):
		var faces := PackedVector3Array()
		for part in _parts(path):
			for vertex in (part[0] as Mesh).get_faces():
				faces.append(((part[1] as Transform3D) * vertex) * s)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		_surface_cache[path] = shape
	return _surface_cache[path]


## Turns everything collected by _put() into batched meshes and collision.
func _flush_batches() -> void:
	for key in _batches:
		var chunk: Vector2i = key[1]
		var centre := Vector3((chunk.x + 0.5) * CHUNK, 0.0, (chunk.y + 0.5) * CHUNK)
		var xforms: Array = _batches[key]["xforms"]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = key[0]
		multimesh.instance_count = xforms.size()
		for i in xforms.size():
			var xform: Transform3D = xforms[i]
			multimesh.set_instance_transform(i, Transform3D(xform.basis, xform.origin - centre))
		var node := MultiMeshInstance3D.new()
		node.multimesh = multimesh
		node.position = centre
		node.visibility_range_end = _batches[key]["range"]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if key[2] \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	_batches.clear()

	for chunk in _chunk_shapes:
		var body := StaticBody3D.new()
		body.name = "Solid_%d_%d" % [chunk.x, chunk.y]
		for entry in _chunk_shapes[chunk]:
			var shape := CollisionShape3D.new()
			shape.shape = entry[0]
			shape.transform = entry[1]
			body.add_child(shape)
		add_child(body)
	_chunk_shapes.clear()
