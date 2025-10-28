extends Node
class_name FloatingSparkles

## Creates floating sparkle particles for magical ambiance

@export var sparkle_count: int = 15
@export var rise_speed_min: float = 20.0
@export var rise_speed_max: float = 40.0
@export var sway_amount: float = 30.0
@export var sparkle_alpha: float = 0.4

var sparkles: Array[String] = ["⭐", "✨", "💫", "🌟"]
var sparkle_labels: Array[Label] = []
var sparkle_velocities: Array[float] = []
var sparkle_sway_offsets: Array[float] = []
var sparkle_sway_speeds: Array[float] = []

func set_visible(is_visible: bool) -> void:
	"""Show or hide all sparkle labels."""
	for label in sparkle_labels:
		label.visible = is_visible

func _ready() -> void:
	# Create sparkle label pool
	for i in range(sparkle_count):
		var label = Label.new()
		label.add_theme_font_size_override("font_size", randi_range(24, 48))
		label.modulate.a = sparkle_alpha
		label.text = sparkles[randi() % sparkles.size()]

		# Random starting position
		_reset_sparkle_position(label, i)

		add_child(label)
		sparkle_labels.append(label)

		# Random rise speed and sway
		sparkle_velocities.append(randf_range(rise_speed_min, rise_speed_max))
		sparkle_sway_offsets.append(randf() * TAU)  # Random phase offset
		sparkle_sway_speeds.append(randf_range(0.5, 1.5))

func _process(delta: float) -> void:
	# Don't process if parent is not visible
	if not get_parent() or not get_parent().visible:
		return

	var screen_size = get_tree().root.get_viewport().get_visible_rect().size

	for i in range(sparkle_labels.size()):
		var label = sparkle_labels[i]

		# Move up
		label.position.y -= sparkle_velocities[i] * delta

		# Sway left/right
		sparkle_sway_offsets[i] += sparkle_sway_speeds[i] * delta
		var sway = sin(sparkle_sway_offsets[i]) * sway_amount
		label.position.x += sway * delta

		# Fade in/out at edges
		if label.position.y < 100:
			label.modulate.a = (label.position.y / 100.0) * sparkle_alpha
		elif label.position.y > screen_size.y - 100:
			label.modulate.a = ((screen_size.y - label.position.y) / 100.0) * sparkle_alpha
		else:
			label.modulate.a = sparkle_alpha

		# Reset if off screen (top)
		if label.position.y < -100:
			_reset_sparkle_position(label, i)

func _reset_sparkle_position(label: Label, index: int) -> void:
	"""Reset sparkle to bottom of screen with random X position."""
	var screen_size = get_tree().root.get_viewport().get_visible_rect().size

	label.position.x = randf_range(0, screen_size.x)
	label.position.y = screen_size.y + randf_range(50, 200)  # Start below screen

	# Randomize sparkle
	label.text = sparkles[randi() % sparkles.size()]
	label.add_theme_font_size_override("font_size", randi_range(24, 48))

	# Slightly randomize velocity for variety (only if index is valid)
	if index < sparkle_velocities.size():
		sparkle_velocities[index] = randf_range(rise_speed_min, rise_speed_max)
		sparkle_sway_offsets[index] = randf() * TAU
