extends WorldEnvironment
## Browsers use Godot's simpler "Compatibility" renderer, which comes out
## paler than the desktop one. This evens the two out when running on the web.


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.03
	environment.adjustment_saturation = 0.95
	(get_node("../Sun") as DirectionalLight3D).light_energy = 0.95
