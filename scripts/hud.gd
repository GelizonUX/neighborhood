extends CanvasLayer
## On-screen hints: the controls for what you are doing right now, the camera
## view in use, and the speed while driving.

@export var player_path: NodePath

@onready var player: Node = get_node(player_path)
@onready var label: Label = $Label


func _process(_delta: float) -> void:
	var view: String = player.rig.current_view()["name"]
	if player.car:
		var kmh := absf(player.car.forward_speed()) * 3.6
		label.text = "%d km/h\nW/S drive · A/D steer · Space brake · E get out · V camera: %s\nLook: drag the mouse or use the arrow keys" % [kmh, view]
	else:
		var hint := "WASD move · Shift run · Space jump · V camera: %s\nLook: drag the mouse or use the arrow keys" % view
		if player.nearest_car():
			hint = "Press E to drive\n" + hint
		label.text = hint
