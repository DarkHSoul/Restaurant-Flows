extends Control
class_name HeldItemDisplay

## Displays the currently held item in the player's hands

@onready var item_label: Label = $MarginContainer/VBoxContainer/ItemLabel
@onready var item_state: Label = $MarginContainer/VBoxContainer/StateLabel
@onready var panel: PanelContainer = $MarginContainer

var current_item: Node3D = null

func _ready() -> void:
	# Initially hide the display
	visible = false

	# Find player and connect to signals
	await get_tree().process_frame
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if player.has_signal("item_picked_up"):
			player.item_picked_up.connect(_on_item_picked_up)
		if player.has_signal("item_dropped"):
			player.item_dropped.connect(_on_item_dropped)
		print("[HELD_ITEM_DISPLAY] Connected to player signals")

func _on_item_picked_up(item: Node3D) -> void:
	"""Show what item the player just picked up."""
	current_item = item
	_update_display()
	visible = true

func _on_item_dropped(_item: Node3D) -> void:
	"""Hide display when player drops item."""
	current_item = null
	visible = false

func _process(_delta: float) -> void:
	"""Update item state every frame."""
	if current_item and is_instance_valid(current_item):
		_update_display()

func _update_display() -> void:
	"""Update the display with current item info."""
	if not current_item or not is_instance_valid(current_item):
		visible = false
		return

	# Get food data if available
	if current_item.has_method("get_food_data"):
		var food_data: Dictionary = current_item.get_food_data()
		var food_name: String = food_data.get("name", "Item")
		var state: int = food_data.get("state", 0)

		item_label.text = "Holding: " + food_name

		# Show cooking state
		match state:
			0:  # RAW
				item_state.text = "🥩 Raw"
				item_state.modulate = Color(0.8, 0.6, 0.4)
			1:  # COOKING
				item_state.text = "🔥 Cooking"
				item_state.modulate = Color.ORANGE
			2:  # COOKED
				item_state.text = "✨ Cooked"
				item_state.modulate = Color.GOLD
			3:  # BURNT
				item_state.text = "💀 Burnt"
				item_state.modulate = Color.DARK_RED
			_:
				item_state.text = ""
	else:
		item_label.text = "Holding: " + current_item.name
		item_state.text = ""
