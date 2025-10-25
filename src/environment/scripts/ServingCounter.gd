extends CookingStation
class_name ServingCounter

## Serving counter where chef places cooked food for waiters to pick up

## Additional signals specific to serving counter
signal food_taken(food: FoodItem)

func _ready() -> void:
	# Set station properties
	station_type = StationType.SERVING_COUNTER
	station_name = "Serving Counter"
	can_cook = false  # Serving counter doesn't cook, just holds food
	max_items = 5
	auto_cook = false

	# Call parent ready
	super._ready()

	# Add to serving_counter group for easy finding
	add_to_group("serving_counter")

	print("[SERVING_COUNTER] Ready! Max items: ", max_items)

	# Start cleanup timer to remove orphaned food
	var cleanup_timer := Timer.new()
	cleanup_timer.wait_time = 3.0  # Check every 3 seconds
	cleanup_timer.autostart = true
	cleanup_timer.timeout.connect(_cleanup_orphaned_food)
	add_child(cleanup_timer)

## Override parent methods to customize behavior

func _can_accept_food(_food: FoodItem) -> bool:
	"""Serving counter accepts all cooked food."""
	# Check if food is cooked (state 2 = COOKED)
	if _food and _food.has_method("get_food_data"):
		var food_data := _food.get_food_data()
		var state: int = food_data.get("state", 0)
		if state != 2:  # Not cooked
			print("[SERVING_COUNTER] Food must be cooked before placing on serving counter!")
			return false
	return true

func _has_active_order_for_food(_food: FoodItem) -> bool:
	"""Serving counter doesn't need order validation - accepts all cooked food."""
	return true

func place_food(food: FoodItem, player: Node3D = null) -> bool:
	"""Override place_food to skip order validation for serving counter."""
	# Check max items
	if _placed_foods.size() >= max_items:
		print("[SERVING_COUNTER] Cannot place food: max items reached (%d/%d)" % [_placed_foods.size(), max_items])
		return false

	# Check if station can accept this food type (cooked check happens here)
	if not _can_accept_food(food):
		print("[SERVING_COUNTER] Cannot place food: food must be cooked!")
		return false

	# Remove from player if held
	if player and player.has_method("_drop_item"):
		player._drop_item()

	_placed_foods.append(food)

	# Set the station reference on the food
	if food.has_method("set"):
		food._current_station = self

	# Position food on station
	if _food_position:
		food.global_position = _food_position.global_position
		food.global_rotation = Vector3.ZERO

	# Freeze food in place
	if food is RigidBody3D:
		food.freeze = true

	print("[SERVING_COUNTER] Food placed successfully! Total: ", _placed_foods.size())
	food_placed.emit(self, food)

	return true

func take_food(food: FoodItem) -> bool:
	"""Take a specific food item from the counter."""
	var success := remove_food(food)
	if success:
		print("[SERVING_COUNTER] Food taken from counter. Remaining: ", _placed_foods.size())
		food_taken.emit(food)
	return success

func get_food_matching_order(order: Dictionary) -> FoodItem:
	"""Find and return a food item that matches the given order."""
	var order_type: String = order.get("type", "")
	if order_type.is_empty():
		return null

	for food in _placed_foods:
		if is_instance_valid(food):
			var food_data := food.get_food_data()
			if food_data.get("type") == order_type:
				# Check if food is cooked (state 2 = COOKED)
				if food_data.get("state", 0) == 2:
					return food

	return null

func has_food_for_order(order: Dictionary) -> bool:
	"""Check if there's food on the counter matching the order."""
	return get_food_matching_order(order) != null

func _cleanup_orphaned_food() -> void:
	"""Remove food from counter that has no matching active orders."""
	# Get active orders from CustomerSpawner
	var customer_spawner = get_tree().get_first_node_in_group("customer_spawner")
	if not customer_spawner or not customer_spawner.has_method("get_active_orders"):
		return

	var active_orders: Array = customer_spawner.get_active_orders()

	# Build set of active order types for quick lookup
	var active_order_types: Dictionary = {}
	for order in active_orders:
		if order is Dictionary and order.has("type"):
			var order_type: String = order.get("type", "")
			if not order_type.is_empty():
				active_order_types[order_type] = true

	# Check each food item on counter
	var foods_to_remove: Array[FoodItem] = []
	for food in _placed_foods:
		if not is_instance_valid(food):
			foods_to_remove.append(food)
			continue

		if food.has_method("get_food_data"):
			var food_data := food.get_food_data()
			var food_type: String = food_data.get("type", "")

			# Check if this food type has an active order
			if not active_order_types.has(food_type):
				print("[SERVING_COUNTER] Orphaned food detected: ", food_type, " - no active order. Removing...")
				foods_to_remove.append(food)

	# Remove orphaned foods
	for food in foods_to_remove:
		if is_instance_valid(food):
			remove_food(food)
			food.queue_free()

	if foods_to_remove.size() > 0:
		print("[SERVING_COUNTER] Cleanup complete. Removed ", foods_to_remove.size(), " orphaned food items.")

# get_placed_foods() inherited from CookingStation
# get_food_count() can use _placed_foods.size()
# is_full() uses is_available() from parent (inverted logic)
# get_food_position() uses _food_position from parent
