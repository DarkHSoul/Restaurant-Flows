extends Node
class_name FallingFoodManager

## Manages falling food emojis in the background for menu ambiance

@export var food_count: int = 6
@export var fall_speed_min: float = 60.0
@export var fall_speed_max: float = 120.0
@export var rotation_speed_min: float = 10.0
@export var rotation_speed_max: float = 30.0
@export var food_alpha: float = 0.15

var food_emojis: Array[String] = ["🍕", "🍔", "🍝", "🥗", "🍲", "🍰", "🍜", "🥘"]
var food_labels: Array[Label] = []
var food_velocities: Array[float] = []
var food_rotations: Array[float] = []

func set_visible(is_visible: bool) -> void:
	"""Show or hide all food labels."""
	for label in food_labels:
		label.visible = is_visible

func _ready() -> void:
	# Create food label pool
	for i in range(food_count):
		var label = Label.new()
		label.add_theme_font_size_override("font_size", 64)
		label.modulate.a = food_alpha
		label.text = food_emojis[randi() % food_emojis.size()]

		# Random starting position
		_reset_food_position(label, i)

		add_child(label)
		food_labels.append(label)

		# Random fall speed and rotation
		food_velocities.append(randf_range(fall_speed_min, fall_speed_max))
		food_rotations.append(randf_range(rotation_speed_min, rotation_speed_max) * (1 if randf() > 0.5 else -1))

func _process(delta: float) -> void:
	# Don't process if parent is not visible
	if not get_parent() or not get_parent().visible:
		return

	var screen_size = get_tree().root.get_viewport().get_visible_rect().size

	for i in range(food_labels.size()):
		var label = food_labels[i]

		# Move down
		label.position.y += food_velocities[i] * delta

		# Rotate
		label.rotation_degrees += food_rotations[i] * delta

		# Reset if off screen
		if label.position.y > screen_size.y + 100:
			_reset_food_position(label, i)

func _reset_food_position(label: Label, index: int) -> void:
	"""Reset food item to top of screen with random X position."""
	var screen_size = get_tree().root.get_viewport().get_visible_rect().size

	label.position.x = randf_range(0, screen_size.x)
	label.position.y = randf_range(-200, -50)  # Start above screen
	label.rotation_degrees = randf_range(0, 360)

	# Randomize emoji
	label.text = food_emojis[randi() % food_emojis.size()]

	# Slightly randomize velocity for variety (only if index is valid)
	if index < food_velocities.size():
		food_velocities[index] = randf_range(fall_speed_min, fall_speed_max)
