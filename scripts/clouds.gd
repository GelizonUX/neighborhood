extends Node3D
## A few puffy clouds that drift across the sky.

const COUNT := 18
const SPREAD := 900.0
const DRIFT := 2.5      ## metres per second

var _material: StandardMaterial3D


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var material := StandardMaterial3D.new()
	_material = material
	material.albedo_color = Color(1, 1, 1)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var puff := SphereMesh.new()
	puff.radial_segments = 10
	puff.rings = 5
	puff.material = material
	for i in COUNT:
		var cloud := Node3D.new()
		cloud.position = Vector3(rng.randf_range(-SPREAD, SPREAD), rng.randf_range(110.0, 170.0),
			rng.randf_range(-SPREAD, SPREAD))
		for j in rng.randi_range(3, 5):
			var blob := MeshInstance3D.new()
			blob.mesh = puff
			blob.position = Vector3(rng.randf_range(-22.0, 22.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-10.0, 10.0))
			blob.scale = Vector3(rng.randf_range(22.0, 40.0), rng.randf_range(9.0, 14.0), rng.randf_range(16.0, 26.0))
			blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.add_child(blob)
		add_child(cloud)


func _process(delta: float) -> void:
	for cloud in get_children():
		cloud.position.x += DRIFT * delta
		if cloud.position.x > SPREAD:
			cloud.position.x = -SPREAD


## Called by the day cycle: clouds are white by day and dim at night.
func set_daylight(daylight: float) -> void:
	if _material:
		_material.albedo_color = Color(0.16, 0.18, 0.26).lerp(Color.WHITE, daylight)
