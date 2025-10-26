extends Control
class_name TutorialOverlay

## Shows helpful tutorial tips for player controls

@onready var tips_container: VBoxContainer = $MarginContainer/VBoxContainer

const TIPS = [
	"WASD - Move around your restaurant",
	"SHIFT - Sprint to move faster",
	"MOUSE - Look around",
	"E - Take customer orders (when highlighted)",
	"LEFT CLICK - Pick up/Drop food items",
	"E - Place food on cooking stations",
	"E - Pick up cooked food and deliver to counter",
	"F7 - Spawn a test customer",
	"TAB - Open shop for upgrades",
	"ESC - Pause menu / Release mouse"
]

var is_visible: bool = true

func _ready() -> void:
	_create_tip_labels()

	# Auto-hide after 15 seconds
	await get_tree().create_timer(15.0).timeout

	# Check if still in tree before fading
	if not is_inside_tree():
		return

	_fade_out()

func _input(event: InputEvent) -> void:
	# Press H to toggle help
	if event is InputEventKey:
		if event.keycode == KEY_H and event.pressed and not event.echo:
			_toggle_visibility()

func _create_tip_labels() -> void:
	"""Create labels for each tip."""
	for tip in TIPS:
		var label := Label.new()
		label.text = "• " + tip
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color.WHITE)
		tips_container.add_child(label)

	# Add toggle instruction
	var toggle_label := Label.new()
	toggle_label.text = "\n[Press H to toggle this help]"
	toggle_label.add_theme_font_size_override("font_size", 16)
	toggle_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	toggle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tips_container.add_child(toggle_label)

func _toggle_visibility() -> void:
	"""Toggle tutorial visibility."""
	is_visible = not is_visible
	if is_visible:
		_fade_in()
	else:
		_fade_out()

func _fade_out() -> void:
	"""Fade out the tutorial."""
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished
	visible = false

func _fade_in() -> void:
	"""Fade in the tutorial."""
	visible = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.5)
