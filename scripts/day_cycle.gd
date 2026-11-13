extends Node
## The clock and the sky. One game minute passes every real second, so a full
## day takes 24 minutes. The sun rises at 6:00 and sets at 18:00, and the sky,
## sunlight and night-time moonlight follow it. Residents use `hour` to decide
## what to do (see population.gd).

const SECONDS_PER_HOUR := 60.0
const START_HOUR := 8.0

const DAY_TOP := Color(0.18, 0.45, 0.9)
const DAY_HORIZON := Color(0.62, 0.8, 0.97)
const DUSK_HORIZON := Color(0.98, 0.62, 0.38)
const NIGHT_TOP := Color(0.02, 0.03, 0.09)
const NIGHT_HORIZON := Color(0.07, 0.1, 0.2)
const DAY_AMBIENT := Color(0.8, 0.86, 0.95)
const NIGHT_AMBIENT := Color(0.3, 0.36, 0.6)

@export var environment_path: NodePath
@export var sun_path: NodePath

var hour := START_HOUR      ## 0.0 to 24.0
var day := 1
var daylight := 1.0         ## 0 at night, 1 in full daylight

@onready var _environment: Environment = (get_node(environment_path) as WorldEnvironment).environment
@onready var _sun: DirectionalLight3D = get_node(sun_path)

var _sky: ProceduralSkyMaterial
var _moon: DirectionalLight3D
var _sun_scale := 1.0
var _ambient_scale := 1.0
var _since_sky_update := 10.0


func _ready() -> void:
	_sky = _environment.sky.sky_material
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR

	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.6, 0.7, 1.0)
	_moon.rotation_degrees = Vector3(-55.0, 140.0, 0.0)
	_moon.shadow_enabled = false
	add_child(_moon)

	if OS.has_feature("web"):
		# Browsers use Godot's simpler renderer, which comes out paler, and a
		# single processor thread, so the look and physics rate are adjusted.
		_sun_scale = 0.7
		_ambient_scale = 0.95
		_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		_environment.adjustment_enabled = true
		_environment.adjustment_contrast = 1.03
		_environment.adjustment_saturation = 0.95
		Engine.physics_ticks_per_second = 60
	_apply()


func _process(delta: float) -> void:
	hour += delta / SECONDS_PER_HOUR
	if hour >= 24.0:
		hour -= 24.0
		day += 1
	_since_sky_update += delta
	if _since_sky_update > 0.5:
		_since_sky_update = 0.0
		_apply()


## "08:05"
func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]


func _apply() -> void:
	# The sun travels east to west between 6:00 and 18:00.
	var angle := (hour - 6.0) / 12.0 * PI
	var height := sin(angle)
	daylight = clampf(height * 3.0, 0.0, 1.0)

	var towards_sun := Vector3(cos(angle), maxf(height, -0.2) * 0.9, 0.45).normalized()
	_sun.look_at_from_position(towards_sun * 200.0, Vector3.ZERO)
	_sun.visible = daylight > 0.01
	_sun.light_energy = 1.3 * daylight * _sun_scale
	_sun.light_color = Color(1.0, 0.62, 0.4).lerp(Color.WHITE, smoothstep(0.0, 0.45, height))
	_moon.light_energy = 0.22 * (1.0 - daylight)
	_moon.visible = daylight < 0.99

	# Orange horizon around sunrise and sunset.
	var dusk := clampf(1.0 - absf(height) * 3.5, 0.0, 1.0) * clampf(height * 6.0 + 1.0, 0.0, 1.0)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, daylight).lerp(DUSK_HORIZON, dusk * 0.7)
	_sky.sky_top_color = NIGHT_TOP.lerp(DAY_TOP, daylight)
	_sky.sky_horizon_color = horizon
	_sky.ground_horizon_color = horizon
	_sky.ground_bottom_color = horizon
	_environment.ambient_light_color = NIGHT_AMBIENT.lerp(DAY_AMBIENT, daylight)
	_environment.ambient_light_energy = lerpf(0.45, 0.8, daylight) * _ambient_scale
	if _environment.fog_enabled:
		_environment.fog_light_color = horizon
	var clouds := get_node_or_null("../Clouds")
	if clouds and clouds.has_method("set_daylight"):
		clouds.set_daylight(daylight)
