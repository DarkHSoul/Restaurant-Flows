extends StaticBody3D
class_name TrashBin

## Trash bin for disposing unwanted or wrong food items

## Visual feedback
@export var highlight_color: Color = Color.YELLOW
@export var disposal_sound: AudioStream = null

var _is_highlighted: bool = false

@onready var _visual: MeshInstance3D = $Visual

func _ready() -> void:
	collision_layer = 0b10000  # Layer 4: Interactables
	collision_mask = 0

func can_interact() -> bool:
	return true

func interact(player: Node3D) -> void:
	"""Dispose of food item player is holding."""
	if not player:
		return

	if player.has_method("get_held_item"):
		var held_item = player.get_held_item()

		if held_item and held_item is FoodItem:
			# Drop the food
			if player.has_method("drop_item"):
				player.drop_item()

			# Play disposal sound if available
			if disposal_sound:
				var audio_player := AudioStreamPlayer3D.new()
				add_child(audio_player)
				audio_player.stream = disposal_sound
				audio_player.play()
				# Clean up after playing
				audio_player.finished.connect(func(): audio_player.queue_free())

			# Destroy the food item
			if is_instance_valid(held_item):
				held_item.queue_free()

			print("[TRASH] Food item disposed")

func highlight(enabled: bool) -> void:
	"""Highlight trash bin when player looks at it."""
	_is_highlighted = enabled
	_update_visual()

## Private methods

func _update_visual() -> void:
	"""Update visual appearance based on state."""
	if not _visual:
		return

	var material := StandardMaterial3D.new()

	if _is_highlighted:
		material.emission_enabled = true
		material.emission = highlight_color
		material.emission_energy = 0.4
		material.albedo_color = Color.DARK_RED
	else:
		material.albedo_color = Color.DARK_GRAY

	_visual.material_override = material
