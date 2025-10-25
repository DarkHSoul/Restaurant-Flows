extends CookingStation
class_name Oven

## Oven - for baking pizzas, etc.

## Pizza scene to spawn
const PIZZA_SCENE := preload("res://src/systems/scenes/FoodPizza.tscn")

func _ready() -> void:
	super._ready()
	station_type = StationType.OVEN
	station_name = "Oven"
	can_cook = true
	max_items = 2
	auto_cook = false  # Requires manual start

func interact(player: Node3D) -> void:
	"""Override interact to spawn pizza and start cooking."""
	# Clean up freed food items first
	_placed_foods = _placed_foods.filter(func(f): return is_instance_valid(f))

	# Check if player is holding something
	var player_holding_food := false
	if player.has_method("get_held_item"):
		var held_item = player.get_held_item()
		player_holding_food = held_item != null and held_item is FoodItem

	# If there's already food on the station, only allow pickup (not spawning new food)
	if _placed_foods.size() > 0:
		# If cooking, only allow pickup when finished
		if _is_cooking:
			if _cooking_timer >= cooking_time:
				# Cooking is done, allow pickup
				if not player_holding_food:
					var food: FoodItem = _placed_foods[0]
					if is_instance_valid(food) and player.has_method("pickup_item"):
						remove_food(food)
						player.pickup_item(food)
			# Still cooking, block all interaction
			return
		else:
			# Not cooking but has food - allow pickup only
			if not player_holding_food:
				var food: FoodItem = _placed_foods[0]
				if is_instance_valid(food) and player.has_method("pickup_item"):
					remove_food(food)
					player.pickup_item(food)
			return

	# Station is empty - allow spawning new food only if there's an order
	if not player_holding_food:
		if _has_pizza_order():
			_spawn_and_cook_pizza()
		else:
			print("No customers want pizza!")
	elif player_holding_food:
		# Player holding food, try to place it
		super.interact(player)

func _spawn_and_cook_pizza() -> void:
	"""Spawn a raw pizza on the oven and start cooking."""
	var pizza := PIZZA_SCENE.instantiate() as FoodItem
	if not pizza:
		return

	# Add to scene
	get_tree().current_scene.add_child(pizza)

	# Place on oven
	place_food(pizza, null)

	# Start cooking immediately
	start_cooking()

func _can_accept_food(food: FoodItem) -> bool:
	# Only accept pizzas and similar baked goods
	return food.food_type in [FoodItem.FoodType.PIZZA]

func _has_pizza_order() -> bool:
	"""Check if any customer has ordered pizza."""
	# Find CustomerSpawner in the scene
	var customer_spawner: Node = get_tree().root.find_child("CustomerSpawner", true, false)
	if not customer_spawner:
		return true  # Allow cooking if we can't find spawner

	# Check if spawner has method
	if not customer_spawner.has_method("get_active_orders"):
		return true

	# Get all active orders
	var active_orders: Array = customer_spawner.get_active_orders()

	print("[DEBUG OVEN] Active orders count: ", active_orders.size())
	for order in active_orders:
		print("[DEBUG OVEN] Order type: ", order.get("type", "unknown"))

	# Check if any order contains pizza
	for order in active_orders:
		if order.get("type") == "pizza":
			print("[DEBUG OVEN] Found pizza order!")
			return true

	print("[DEBUG OVEN] No pizza orders found")
	return false
