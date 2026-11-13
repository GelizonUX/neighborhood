extends CanvasLayer
## On-screen text: the clock, the controls for what you are doing right now,
## the camera view in use, the speed while driving, and a progress message
## while the city is being built.

@export var player_path: NodePath
@export var city_path: NodePath
@export var clock_path: NodePath

@onready var player: Node = get_node(player_path)
@onready var city: Node = get_node(city_path)
@onready var clock: Node = get_node(clock_path)
@onready var label: Label = $Label
@onready var clock_label: Label = $Clock
@onready var loading: Label = $Loading


func _ready() -> void:
	city.progress.connect(func(fraction: float) -> void:
		loading.text = "Building the city… %d%%" % int(fraction * 100.0))
	city.built.connect(func() -> void: loading.hide())
	loading.visible = not city.is_built


func _process(_delta: float) -> void:
	clock_label.text = "Day %d  %s" % [clock.day, clock.clock_text()]
	if not city.is_built:
		label.text = ""
		return
	var view: String = player.rig.current_view()["name"]
	var look := "\nLook: drag the mouse or use the arrow keys"
	if player.car:
		var kmh := absf(player.car.forward_speed()) * 3.6
		label.text = "%d km/h\nW/S drive · A/D steer · Space brake · E get out · V camera: %s%s" % [kmh, view, look]
	else:
		var hint := "WASD move · Shift run · Space jump · V camera: %s%s" % [view, look]
		if player.nearest_car():
			hint = "Press E to drive\n" + hint
		label.text = hint
