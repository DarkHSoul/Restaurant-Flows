extends CanvasLayer
class_name FPSDisplay

## FPS counter display - shows in top-right corner

@onready var fps_label: Label = $MarginContainer/FPSLabel

var _is_fps_visible: bool = true

func _ready() -> void:
	# Start visible by default
	visible = _is_fps_visible

	# Set process mode to always run even when paused
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if visible and fps_label:
		var fps := Engine.get_frames_per_second()
		fps_label.text = "FPS: %d" % fps

		# Color code based on performance
		if fps >= 55:
			fps_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))  # Green
		elif fps >= 30:
			fps_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))  # Yellow
		else:
			fps_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))  # Red

func toggle_visibility() -> void:
	"""Toggle FPS display on/off."""
	_is_fps_visible = !_is_fps_visible
	visible = _is_fps_visible

func show_fps() -> void:
	"""Show FPS display."""
	_is_fps_visible = true
	visible = true

func hide_fps() -> void:
	"""Hide FPS display."""
	_is_fps_visible = false
	visible = false
