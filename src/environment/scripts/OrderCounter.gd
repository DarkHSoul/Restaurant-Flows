extends StaticBody3D
class_name OrderCounter

## Counter where customers line up and place orders

## Signals
signal customer_arrived_at_counter(customer: Customer)
signal order_taken_at_counter(customer: Customer, order: Dictionary)
signal customer_left_counter(customer: Customer)
signal food_placed(food: FoodItem)
signal food_picked_up(food: FoodItem)

## Counter properties
@export_group("Queue Settings")
@export var queue_spacing: float = 1.2  # Space between customers in line
@export var max_queue_size: int = 10
@export var queue_direction: Vector3 = Vector3(0, 0, 1)  # Direction line extends

## Visual feedback
@export_group("Visual")
@export var counter_color: Color = Color(0.7, 0.5, 0.3)
@export var highlight_color: Color = Color.YELLOW

## Internal state
var _queued_customers: Array[Customer] = []
var _customer_at_counter: Customer = null
var _is_highlighted: bool = false
var _placed_foods: Array[FoodItem] = []  # Food items placed on counter for waiters
var _max_food_items: int = 5

@onready var _visual: MeshInstance3D = $Visual
@onready var _order_position: Marker3D = $OrderPosition  # Where customer stands to order
@onready var _queue_start: Marker3D = $QueueStart  # Start of the queue line
@onready var _food_position: Marker3D = $FoodPosition if has_node("FoodPosition") else null

func _ready() -> void:
	collision_layer = 0b10000  # Layer 4: Interactables
	collision_mask = 0
	_update_visual()

	# Add to serving_counter group so waiters and chefs can find it
	add_to_group("serving_counter")

## Public interface

func can_interact() -> bool:
	"""Check if player can interact with counter."""
	# Can interact for order taking if customer is present
	if _customer_at_counter != null and _customer_at_counter.has_method("get_order"):
		print("[DEBUG COUNTER] can_interact() = true (customer at counter)")
		return true

	# Can also interact to place food (will check in interact() if player is holding food)
	print("[DEBUG COUNTER] can_interact() = true (food placement)")
	return true

func interact(player: Node3D) -> void:
	"""Player takes order from customer at counter OR places food on counter."""
	# First, check if player is holding food to place
	if player.has_method("get_held_item"):
		var held_item = player.get_held_item()
		if held_item and held_item is FoodItem:
			# Try to place food on counter
			if place_food(held_item, player):
				print("[COUNTER] Food placed on counter for waiter pickup")
				return

	# Otherwise, handle order taking
	if not _customer_at_counter:
		return

	# Take the customer's order
	var order: Dictionary = {}
	if _customer_at_counter.has_method("take_order_at_counter"):
		order = _customer_at_counter.take_order_at_counter()

	if not order.is_empty():
		# Emit signal
		order_taken_at_counter.emit(_customer_at_counter, order)

		# Customer will now need to be seated at a table
		# CustomerSpawner will handle this

		# Customer moves away from counter
		_release_customer()

		# Move next customer to counter
		_advance_queue()

func highlight(enabled: bool) -> void:
	"""Highlight counter when player looks at it."""
	_is_highlighted = enabled
	_update_visual()

func add_customer_to_queue(customer: Customer) -> bool:
	"""Add a customer to the queue."""
	if not customer or _queued_customers.size() >= max_queue_size:
		return false

	_queued_customers.append(customer)

	# Customer walks to their position in queue
	var queue_index := _queued_customers.size() - 1
	customer.move_to(get_queue_position(queue_index), &"queue_line")

	# Connect to customer's destination_reached signal to know when they arrive
	if not customer.destination_reached.is_connected(_on_customer_reached_queue_position):
		customer.destination_reached.connect(_on_customer_reached_queue_position)

	return true

func get_queue_position(index: int) -> Vector3:
	"""Get world position for a specific queue index."""
	if _queue_start:
		return _queue_start.global_position + (queue_direction.normalized() * queue_spacing * index)

	# Fallback to counter position
	return global_position + (queue_direction.normalized() * queue_spacing * (index + 1))

func get_order_position() -> Vector3:
	"""Get the position where customer stands to order."""
	if _order_position:
		return _order_position.global_position
	return global_position

func get_queue_count() -> int:
	"""Get number of customers in queue (not including one at counter)."""
	return _queued_customers.size()

func is_queue_full() -> bool:
	"""Check if queue has reached max capacity."""
	return _queued_customers.size() >= max_queue_size

## Private methods

func _advance_queue() -> void:
	"""Move next customer in queue to counter position."""
	if _queued_customers.is_empty():
		_customer_at_counter = null
		return

	# Get first customer in queue
	_customer_at_counter = _queued_customers.pop_front()

	# Move them to counter - they'll transition to ORDERING when they arrive
	if _customer_at_counter:
		_customer_at_counter.move_to(get_order_position(), &"counter")

		# Connect to know when they arrive at counter
		if not _customer_at_counter.destination_reached.is_connected(_on_customer_reached_counter):
			_customer_at_counter.destination_reached.connect(_on_customer_reached_counter)

	# Update remaining queue positions
	_update_queue_positions()

func _release_customer() -> void:
	"""Release customer from counter after order taken."""
	if _customer_at_counter:
		customer_left_counter.emit(_customer_at_counter)
		_customer_at_counter = null

func _update_queue_positions() -> void:
	"""Update all customers in queue to their proper positions."""
	for i in range(_queued_customers.size()):
		var customer := _queued_customers[i]
		if customer:
			customer.move_to(get_queue_position(i), &"queue_line")

func _update_visual() -> void:
	"""Update visual appearance based on state."""
	if not _visual:
		return

	var material := StandardMaterial3D.new()

	if _is_highlighted:
		material.emission_enabled = true
		material.emission = highlight_color
		material.emission_energy = 0.4
		material.albedo_color = counter_color
	else:
		material.albedo_color = counter_color

	_visual.material_override = material

func _on_customer_reached_queue_position(customer: Customer, label: StringName) -> void:
	"""Called when a customer reaches their position in the queue."""
	# Only care about queue arrivals
	if label != &"queue_line":
		return

	# If they're first in queue and no one at counter, advance them
	if not _customer_at_counter and _queued_customers.size() > 0 and _queued_customers[0] == customer:
		_advance_queue()

func _on_customer_reached_counter(customer: Customer, label: StringName) -> void:
	"""Called when a customer reaches the counter to order."""
	# Only care about counter arrivals
	if label != &"counter":
		return

	# Make sure this is the current counter customer
	if customer != _customer_at_counter:
		return

	# Notify customer they're at counter - this transitions them to ORDERING state
	if customer.has_method("arrive_at_counter"):
		customer.arrive_at_counter()

	customer_arrived_at_counter.emit(customer)

## Food placement/pickup methods (for chef and waiter)

func place_food(food: FoodItem, player_or_chef: Node3D = null) -> bool:
	"""Place a cooked food item on the counter for waiter pickup."""
	if _placed_foods.size() >= _max_food_items:
		print("[COUNTER] Counter is full! Cannot place more food.")
		return false

	# Check if food is cooked
	var food_data := food.get_food_data()
	var food_state = food_data.get("state", 0)

	if food_state != 2:  # Not COOKED (2 = COOKED)
		print("[COUNTER] Food must be cooked before placing on counter! Current state: ", food_state)
		return false

	# Drop from player/chef if they're holding it
	if player_or_chef and player_or_chef.has_method("drop_item"):
		player_or_chef.drop_item()

	# Add to placed foods array
	_placed_foods.append(food)

	# Position food on counter
	var pos_offset := Vector3((_placed_foods.size() - 1) * 0.5, 1.0, 0)
	if _food_position:
		food.global_position = _food_position.global_position + pos_offset
	else:
		food.global_position = global_position + Vector3(0, 1.0, 0) + pos_offset

	# Freeze the food so it doesn't fall
	if food.has_method("freeze"):
		food.freeze = true

	food_placed.emit(food)
	print("[COUNTER] Food placed on counter: ", food_data.get("type", "Unknown"))

	return true

func get_food_matching_order(order: Dictionary) -> FoodItem:
	"""Get a food item that matches a specific order (for waiter pickup)."""
	var order_type: String = order.get("type", "")

	print("[COUNTER] Waiter looking for food type: ", order_type)
	print("[COUNTER] Foods on counter: ", _placed_foods.size())

	for food in _placed_foods:
		if is_instance_valid(food):
			var food_data := food.get_food_data()
			var food_type: String = food_data.get("type", "")
			var food_state: int = food_data.get("state", 0)

			print("[COUNTER]   Checking food: ", food_type, " (state: ", food_state, ")")

			if food_type == order_type and food_state == 2:  # COOKED
				print("[COUNTER]   -> Match found!")
				return food

	print("[COUNTER]   -> No matching food found")
	return null

func has_food_for_order(order: Dictionary) -> bool:
	"""Check if there's food available for a specific order."""
	var food := get_food_matching_order(order)
	return food != null

func pickup_food(food: FoodItem, waiter: Node3D) -> bool:
	"""Waiter picks up food from counter."""
	if not food or not _placed_foods.has(food):
		return false

	# Remove from placed foods
	_placed_foods.erase(food)

	# Unfreeze the food
	if food.has_method("freeze"):
		food.freeze = false

	food_picked_up.emit(food)
	print("[COUNTER] Waiter picked up food from counter")

	return true

func get_counter_position() -> Vector3:
	"""Get position near counter for waiters/chefs to stand."""
	if _order_position:
		return _order_position.global_position
	return global_position
