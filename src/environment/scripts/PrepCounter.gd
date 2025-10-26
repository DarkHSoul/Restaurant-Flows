extends CookingStation
class_name PrepCounter

## Preparation Counter - for soup, pasta, salad preparation

## Food scenes to spawn
const SOUP_SCENE := preload("res://src/systems/scenes/FoodSoup.tscn")
const PASTA_SCENE := preload("res://src/systems/scenes/FoodPasta.tscn")
const SALAD_SCENE := preload("res://src/systems/scenes/FoodSalad.tscn")

func _ready() -> void:
	super._ready()
	station_type = StationType.PREP_COUNTER
	station_name = "Prep Counter"
	can_cook = true
	max_items = 3
	auto_cook = false

func interact(player: Node3D) -> void:
	"""Override interact to spawn food items and start cooking."""
	# Clean up freed food items first
	_placed_foods = _placed_foods.filter(func(f): return is_instance_valid(f))

	# Check if player is holding something
	var player_holding_food := false
	if player.has_method("get_held_item"):
		var held_item = player.get_held_item()
		player_holding_food = held_item != null and held_item is FoodItem

	# If there's already food on the station, only allow pickup (not spawning new food)
	if _placed_foods.size() > 0:
		var food: FoodItem = _placed_foods[0]
		if is_instance_valid(food):
			# Check if food is still cooking
			var food_state = food.get_cooking_state() if food.has_method("get_cooking_state") else 0

			if food_state == 1:  # CookingState.COOKING
				# Still cooking, block all interaction
				return
			else:
				# Not cooking - allow pickup
				if not player_holding_food and player.has_method("pickup_item"):
					remove_food(food)
					player.pickup_item(food)
				return

	# Station is empty - allow spawning new food only if there's an order
	if not player_holding_food:
		if _has_soup_order():
			_spawn_and_cook_soup()
		elif _has_pasta_order():
			_spawn_and_cook_pasta()
		elif _has_salad_order():
			_spawn_and_cook_salad()
		else:
			print("No customers want soup, pasta, or salad!")
	elif player_holding_food:
		# Player holding food, try to place it
		super.interact(player)

func _spawn_and_cook_soup() -> void:
	"""Spawn a raw soup on the prep counter and start cooking."""
	var soup := SOUP_SCENE.instantiate() as FoodItem
	if not soup:
		return

	# Add to scene
	get_tree().current_scene.add_child(soup)

	# Place on prep counter
	place_food(soup, null)

	# Start cooking immediately
	start_cooking()

func _spawn_and_cook_pasta() -> void:
	"""Spawn raw pasta on the prep counter and start cooking."""
	var pasta := PASTA_SCENE.instantiate() as FoodItem
	if not pasta:
		return

	# Add to scene
	get_tree().current_scene.add_child(pasta)

	# Place on prep counter
	place_food(pasta, null)

	# Start cooking immediately
	start_cooking()

func _spawn_and_cook_salad() -> void:
	"""Spawn salad on the prep counter - salad doesn't need cooking, just prep."""
	var salad := SALAD_SCENE.instantiate() as FoodItem
	if not salad:
		return

	# Add to scene
	get_tree().current_scene.add_child(salad)

	# Salad is instantly "cooked" (prepared) since it doesn't require actual cooking
	# Set the state directly to COOKED
	if salad.has_method("set_cooked"):
		salad.set_cooked()

	# Place on prep counter
	place_food(salad, null)

	print("[PREP_COUNTER] Salad prepared and ready to serve!")

func _can_accept_food(food: FoodItem) -> bool:
	# Accept soup, pasta, salad
	return food.food_type in [FoodItem.FoodType.SOUP, FoodItem.FoodType.PASTA, FoodItem.FoodType.SALAD]

func _has_soup_order() -> bool:
	"""Check if any customer has ordered soup."""
	# Find CustomerSpawner in the scene
	var customer_spawner: Node = get_tree().root.find_child("CustomerSpawner", true, false)
	if not customer_spawner:
		return true  # Allow cooking if we can't find spawner

	# Check if spawner has method
	if not customer_spawner.has_method("get_active_orders"):
		return true

	# Get all active orders
	var active_orders: Array = customer_spawner.get_active_orders()

	# Check if any order contains soup
	for order in active_orders:
		if order.get("type") == "soup":
			return true

	return false

func _has_pasta_order() -> bool:
	"""Check if any customer has ordered pasta."""
	# Find CustomerSpawner in the scene
	var customer_spawner: Node = get_tree().root.find_child("CustomerSpawner", true, false)
	if not customer_spawner:
		return true  # Allow cooking if we can't find spawner

	# Check if spawner has method
	if not customer_spawner.has_method("get_active_orders"):
		return true

	# Get all active orders
	var active_orders: Array = customer_spawner.get_active_orders()

	# Check if any order contains pasta
	for order in active_orders:
		if order.get("type") == "pasta":
			return true

	return false

func _has_salad_order() -> bool:
	"""Check if any customer has ordered salad."""
	# Find CustomerSpawner in the scene
	var customer_spawner: Node = get_tree().root.find_child("CustomerSpawner", true, false)
	if not customer_spawner:
		return true  # Allow cooking if we can't find spawner

	# Check if spawner has method
	if not customer_spawner.has_method("get_active_orders"):
		return true

	# Get all active orders
	var active_orders: Array = customer_spawner.get_active_orders()

	# Check if any order contains salad
	for order in active_orders:
		if order.get("type") == "salad":
			return true

	return false
