extends StaticBody3D
class_name Table

## Restaurant table where customers sit and eat

## Signals
signal customer_seated(table: Table, customer: Customer)
signal customer_left(table: Table, customer: Customer)
signal order_taken(table: Table, order: Dictionary)
signal food_served(table: Table, food: FoodItem)

## Table properties
@export var table_number: int = 1
@export var max_customers: int = 1
@export var max_food_items: int = 4
@export var has_taken_order: bool = false

## Visual feedback
@export var occupied_color: Color = Color.RED
@export var available_color: Color = Color.GREEN
@export var highlight_color: Color = Color.YELLOW

## Internal state
var _seated_customers: Array[Customer] = []
var _current_order: Dictionary = {}
var _placed_foods: Array[FoodItem] = []
var _is_highlighted: bool = false
var _error_label: Label3D = null

@onready var _visual: MeshInstance3D = $Visual
@onready var _customer_seat_position: Marker3D = $CustomerSeatPosition
@onready var _food_positions: Array[Marker3D] = []
@onready var _order_indicator: MeshInstance3D = $OrderIndicator

func _ready() -> void:
	collision_layer = 0b10000  # Layer 4: Interactables
	collision_mask = 0

	if _order_indicator:
		_order_indicator.visible = false

	# Collect all FoodPosition markers
	_collect_food_positions()

	# Create error message label
	_create_error_label()

	_update_visual()

func _collect_food_positions() -> void:
	"""Find all FoodPosition markers in the scene."""
	_food_positions.clear()
	for child in get_children():
		if child is Marker3D and child.name.begins_with("FoodPosition"):
			_food_positions.append(child)

	# If no positions found, create default one
	if _food_positions.is_empty() and has_node("FoodPosition"):
		_food_positions.append($FoodPosition)

## Public interface

func can_interact() -> bool:
	"""Table is only interactable if customer is waiting for food and table has space for more items."""
	if _seated_customers.is_empty():
		return false

	if not has_taken_order:
		return false

	# Check if table can accept more food
	return _placed_foods.size() < max_food_items

func interact(player: Node3D) -> void:
	"""Handle player interaction with table."""
	if not player:
		return

	# Only accept food items when customer is waiting
	if player.has_method("get_held_item"):
		var held_item = player.get_held_item()

		if held_item and held_item is FoodItem:
			place_food(held_item, player)
			return

func highlight(enabled: bool) -> void:
	"""Highlight table when player looks at it."""
	_is_highlighted = enabled
	_update_visual()

func sit_customer(customer: Customer) -> bool:
	"""Seat a customer at this table."""
	# Check if table is physically full (don't use is_available() which checks has_taken_order)
	print("[DEBUG TABLE] Table ", table_number, " sit_customer() called. Seated: ", _seated_customers.size(), "/", max_customers, " | has_taken_order: ", has_taken_order)
	if _seated_customers.size() >= max_customers:
		push_warning("Table %d: Cannot seat customer, table is full! Seated: %d/%d" % [table_number, _seated_customers.size(), max_customers])
		return false

	# Extra safety: check if customer is already seated at this table
	if customer in _seated_customers:
		push_warning("Table %d: Customer already seated at this table!" % table_number)
		return false

	print("[DEBUG TABLE] Table ", table_number, " seating customer successfully. Seated count: ", _seated_customers.size(), "/", max_customers)
	_seated_customers.append(customer)

	# Position customer at seat
	if _customer_seat_position:
		customer.global_position = _customer_seat_position.global_position
		# Face the table
		customer.rotation.y = _customer_seat_position.rotation.y

	customer_seated.emit(self, customer)
	_update_visual()

	return true

func release_table() -> void:
	"""Customer leaves the table."""
	if _seated_customers.is_empty():
		return

	var customer: Customer = _seated_customers.pop_back()
	customer_left.emit(self, customer)

	# Clean up any food left on table
	for food in _placed_foods:
		if is_instance_valid(food):
			food.queue_free()

	_placed_foods.clear()

	# Only reset order state if table is now completely empty
	if _seated_customers.is_empty():
		has_taken_order = false
		_current_order.clear()

		if _order_indicator:
			_order_indicator.visible = false
	else:
		# Table still has customers - warn about this unexpected state
		push_warning("Table %d: Customer left but %d customer(s) still seated!" % [table_number, _seated_customers.size()])

	_update_visual()

func take_order() -> Dictionary:
	"""Take the order from seated customers."""
	if has_taken_order or _seated_customers.is_empty():
		return {}

	var customer := _seated_customers[0]
	if customer and customer.has_method("get_order"):
		_current_order = customer.get_order()
		has_taken_order = true

		if _order_indicator:
			_order_indicator.visible = true

		order_taken.emit(self, _current_order)
		return _current_order.duplicate()

	return {}

func place_food(food: FoodItem, player: Node3D) -> bool:
	"""Place food item on the table."""
	if not can_interact():
		_show_error_message("Cannot serve here!")
		return false

	if _seated_customers.is_empty():
		_show_error_message("No customer here!")
		return false

	# Check if table has space
	if _placed_foods.size() >= max_food_items:
		_show_error_message("Table is full!")
		return false

	# VALIDATE FOOD TYPE - Check if this food matches the customer's order
	if not _current_order.is_empty():
		var food_data: Dictionary = food.get_food_data()
		var food_type: String = food_data.get("type", "")
		var ordered_type: String = _current_order.get("type", "")

		if food_type != ordered_type:
			# WRONG FOOD TYPE - Show error and DO NOT drop the food
			var order_name: String = _current_order.get("name", ordered_type.capitalize())
			_show_error_message("Wrong order! Customer wants " + order_name)
			return false

	# Drop food from player
	if player.has_method("drop_item"):
		player.drop_item()

	# Get next available food position
	var position_index := _placed_foods.size()
	var food_position: Vector3 = global_position + Vector3(0.5, 1.0, 0)

	if position_index < _food_positions.size():
		food_position = _food_positions[position_index].global_position
	else:
		# Arrange in a grid pattern if no positions defined
		var offset_x := (position_index % 2) * 0.4 - 0.2
		var offset_z := (position_index / 2) * 0.4 - 0.2
		food_position = global_position + Vector3(offset_x, 1.0, offset_z)

	# Position food on table
	food.global_position = food_position

	# Add to placed foods
	_placed_foods.append(food)
	food_served.emit(self, food)

	return true

func get_customer_position() -> Vector3:
	"""Get the position where customer should stand/sit."""
	if _customer_seat_position:
		return _customer_seat_position.global_position
	return global_position

func get_current_order() -> Dictionary:
	"""Get the current order."""
	return _current_order.duplicate()

func is_available() -> bool:
	"""Check if table has space for customers and isn't already assigned."""
	# Table is unavailable if it's full OR if someone is walking to it (has_taken_order = true)
	if _seated_customers.size() >= max_customers:
		return false
	if has_taken_order and _seated_customers.is_empty():
		# Someone is assigned to this table but hasn't arrived yet
		return false
	return true

func is_occupied() -> bool:
	"""Check if table has customers."""
	return not _seated_customers.is_empty()

func get_seated_customers() -> Array[Customer]:
	"""Get list of seated customers."""
	return _seated_customers.duplicate()

func get_table_number() -> int:
	"""Get the table number."""
	return table_number

## Private methods

func _create_error_label() -> void:
	"""Create a Label3D to show error messages."""
	_error_label = Label3D.new()
	_error_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_error_label.font_size = 80
	_error_label.outline_size = 12
	_error_label.modulate = Color.RED
	_error_label.outline_modulate = Color.BLACK
	_error_label.visible = false
	_error_label.pixel_size = 0.005
	_error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Make error text always render on top
	_error_label.no_depth_test = true
	_error_label.render_priority = 20  # Higher than interaction prompts
	add_child(_error_label)

func _show_error_message(message: String) -> void:
	"""Display an error message above the table."""
	if not _error_label:
		return

	_error_label.text = message
	_error_label.position = Vector3(0, 1.5, 0)
	_error_label.visible = true

	# Auto-hide after 2 seconds
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if _error_label:
			_error_label.visible = false
	)

func _update_visual() -> void:
	"""Update visual appearance based on state."""
	if not _visual:
		return

	var material := StandardMaterial3D.new()

	if _is_highlighted:
		material.emission_enabled = true
		material.emission = highlight_color
		material.emission_energy = 0.4
	elif is_occupied():
		material.albedo_color = occupied_color.lerp(Color.WHITE, 0.7)
	else:
		material.albedo_color = available_color.lerp(Color.WHITE, 0.7)

	_visual.material_override = material
