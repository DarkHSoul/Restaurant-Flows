extends StaticBody3D
class_name CookingStation

## Base class for all cooking stations (oven, stove, prep counter, etc.)

## Signals
signal food_placed(station: CookingStation, food: FoodItem)
signal food_removed(station: CookingStation, food: FoodItem)
signal cooking_started(station: CookingStation)
signal cooking_finished(station: CookingStation)

## Station types
enum StationType {
	OVEN,
	STOVE,
	PREP_COUNTER,
	SERVING_COUNTER,
	SINK
}

## Station properties
@export var station_type: StationType = StationType.OVEN
@export var station_name: String = "Oven"
@export var can_cook: bool = true
@export var max_items: int = 1
@export var auto_cook: bool = true
@export var cooking_time: float = 5.0  # Default cooking time in seconds

## Visual feedback
@export var highlight_color: Color = Color.YELLOW
@export var active_color: Color = Color.ORANGE

## Internal state
var _placed_foods: Array[FoodItem] = []
var _is_highlighted: bool = false
var _is_cooking: bool = false
var _interaction_area: Area3D = null
var _cooking_timer: float = 0.0
var _progress_bar: Control = null

@onready var _visual: MeshInstance3D = $Visual
@onready var _food_position: Marker3D = $FoodPosition
@onready var _light: OmniLight3D = $CookingLight

func _ready() -> void:
	collision_layer = 0b10000  # Layer 4: Interactables
	collision_mask = 0

	# Add to cooking_stations group for order validation
	add_to_group("cooking_stations")

	if _light:
		_light.visible = false

	_setup_interaction_area()
	_setup_progress_bar()

func _process(delta: float) -> void:
	if _is_cooking:
		_cooking_timer += delta
		var progress: float = min(_cooking_timer / cooking_time, 1.0)
		_update_progress_bar(progress)

		if progress >= 1.0:
			_finish_cooking()

## Public interface

func can_interact() -> bool:
	return true

func interact(player: Node3D) -> void:
	"""Called when player presses interact key."""

	# Clean up freed food items
	_placed_foods = _placed_foods.filter(func(f): return is_instance_valid(f))

	if player.has_method("get_held_item"):
		var held_item = player.get_held_item()

		if held_item and held_item is FoodItem:
			# Player is holding food - try to place it
			place_food(held_item, player)
		elif _placed_foods.size() > 0:
			# Player is not holding anything, there's food on the station
			var food: FoodItem = _placed_foods[0]

			# If food is placed but not cooking yet, start cooking (manual cooking stations)
			if not _is_cooking and can_cook and not auto_cook:
				start_cooking()
			else:
				# Pick up the food (either finished cooking, or doesn't need cooking)
				if is_instance_valid(food) and player.has_method("pickup_item"):
					remove_food(food)
					player.pickup_item(food)

func highlight(enabled: bool) -> void:
	"""Highlight station when player looks at it."""
	_is_highlighted = enabled
	_update_visual()

func place_food(food: FoodItem, player: Node3D = null) -> bool:
	"""Place food item on this station."""
	print("[STATION] place_food() called. food: ", food, " | player: ", player)

	if _placed_foods.size() >= max_items:
		print("[STATION] Cannot place - max items reached: ", _placed_foods.size(), "/", max_items)
		return false

	if not _can_accept_food(food):
		print("[STATION] Cannot place - station cannot accept this food type")
		return false

	# Check if there's an active order for this food type
	# Skip validation if placed by Chef (Chef already validated the order)
	var is_chef: bool = player != null and player.is_in_group("chefs")
	print("[STATION] is_chef: ", is_chef, " | player in chefs group: ", player != null and player.is_in_group("chefs"))
	if not is_chef and not _has_active_order_for_food(food):
		print("[STATION] Cannot place - no active order for this food (and placer is not a chef)")
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

	food_placed.emit(self, food)

	# Auto start cooking if enabled OR if placed by Chef
	print("[STATION] Food placed! auto_cook: ", auto_cook, " | can_cook: ", can_cook, " | is_chef: ", is_chef, " | About to try start_cooking...")
	if can_cook and (auto_cook or is_chef):
		print("[STATION] Calling start_cooking() from place_food...")
		start_cooking()
	else:
		print("[STATION] NOT calling start_cooking - auto_cook: ", auto_cook, " | can_cook: ", can_cook, " | is_chef: ", is_chef)

	return true

func remove_food(food: FoodItem) -> bool:
	"""Remove food from station."""
	if not food in _placed_foods:
		return false

	_placed_foods.erase(food)

	# Clear station reference on the food
	if food.has_method("set"):
		food._current_station = null

	# Unfreeze food
	if food is RigidBody3D:
		food.freeze = false

	food_removed.emit(self, food)

	# Stop cooking if no more food
	if _placed_foods.is_empty():
		stop_cooking()

	return true

func start_cooking() -> bool:
	"""Start cooking process."""
	print("[STATION] start_cooking() called. can_cook: ", can_cook, " | foods: ", _placed_foods.size(), " | is_cooking: ", _is_cooking)

	if not can_cook or _placed_foods.is_empty() or _is_cooking:
		print("[STATION] Cannot start cooking - failed precondition")
		return false

	# Clean up any freed food items
	_placed_foods = _placed_foods.filter(func(f): return is_instance_valid(f))

	if _placed_foods.is_empty():
		print("[STATION] No valid foods after filter")
		return false

	_is_cooking = true
	_cooking_timer = 0.0
	print("[STATION] Starting cooking process...")

	# Start cooking all placed foods
	for food in _placed_foods:
		if is_instance_valid(food) and food.has_method("start_cooking"):
			print("[STATION] Calling start_cooking on food...")
			var success = food.start_cooking(self)
			print("[STATION] start_cooking returned: ", success)

	if _light:
		_light.visible = true

	if _progress_bar:
		_progress_bar.visible = true

	cooking_started.emit(self)
	_update_visual()

	return true

func stop_cooking() -> void:
	"""Stop cooking process."""
	if not _is_cooking:
		return

	_is_cooking = false
	_cooking_timer = 0.0

	# Stop cooking all foods (check validity first)
	for food in _placed_foods:
		if is_instance_valid(food) and food.has_method("stop_cooking"):
			food.stop_cooking()

	if _light:
		_light.visible = false

	if _progress_bar:
		_progress_bar.visible = false

	cooking_finished.emit(self)
	_update_visual()

func _finish_cooking() -> void:
	"""Called when cooking is complete."""
	stop_cooking()

	# Mark all foods as cooked (check validity first)
	for food in _placed_foods:
		if is_instance_valid(food) and food.has_method("set_cooked"):
			food.set_cooked()

func get_placed_foods() -> Array[FoodItem]:
	return _placed_foods.duplicate()

func is_cooking() -> bool:
	return _is_cooking

func is_available() -> bool:
	return _placed_foods.size() < max_items

func get_station_type() -> String:
	"""Returns station type as string for matching with OrderManager menu."""
	match station_type:
		StationType.OVEN:
			return "oven"
		StationType.STOVE:
			return "stove"
		StationType.PREP_COUNTER:
			return "prep"
		StationType.SERVING_COUNTER:
			return "serving"
		StationType.SINK:
			return "sink"
		_:
			return "unknown"

## Private methods

func _can_accept_food(_food: FoodItem) -> bool:
	"""Check if this station can accept this type of food."""
	# Override in subclasses for specific rules
	return true

func _has_active_order_for_food(food: FoodItem) -> bool:
	"""Check if there's an active order that needs this food type."""
	if not food or not food.has_method("get_food_data"):
		return false

	var food_data := food.get_food_data()
	var food_type: String = food_data.get("type", "")

	if food_type.is_empty():
		return false

	# Find the CustomerSpawner to check active orders
	var spawner: Node = get_tree().get_first_node_in_group("customer_spawner")
	if not spawner or not spawner.has_method("get_active_orders"):
		print("[STATION] Warning: CustomerSpawner not found, allowing food placement")
		return true  # Allow if we can't check (backwards compatibility)

	var active_orders: Array = spawner.get_active_orders()

	# Count how many orders need this food type
	var orders_needing_food: int = 0
	for order in active_orders:
		if order.get("type", "") == food_type:
			orders_needing_food += 1

	# Count how many of this food type are already being cooked in ALL stations
	var foods_being_cooked: int = 0
	var all_stations := get_tree().get_nodes_in_group("cooking_stations")
	for station in all_stations:
		if station and station.has_method("get_placed_foods"):
			var placed: Array[FoodItem] = station.get_placed_foods()
			for placed_food in placed:
				if is_instance_valid(placed_food) and placed_food.has_method("get_food_data"):
					var placed_data := placed_food.get_food_data()
					if placed_data.get("type", "") == food_type:
						foods_being_cooked += 1

	# Allow placement only if there are more orders than foods being cooked
	return foods_being_cooked < orders_needing_food

func _setup_interaction_area() -> void:
	"""Setup area for detecting when player is near."""
	_interaction_area = Area3D.new()
	add_child(_interaction_area)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	shape.shape = sphere
	_interaction_area.add_child(shape)

	_interaction_area.collision_layer = 0
	_interaction_area.collision_mask = 0b00010  # Layer 2: Player

func _update_visual() -> void:
	"""Update visual appearance based on state."""
	if not _visual:
		return

	var base_material := _visual.get_active_material(0)
	if not base_material:
		base_material = StandardMaterial3D.new()

	var material := base_material.duplicate() as StandardMaterial3D

	if _is_cooking:
		material.emission_enabled = true
		material.emission = active_color
		material.emission_energy = 0.5
	elif _is_highlighted:
		material.emission_enabled = true
		material.emission = highlight_color
		material.emission_energy = 0.3
	else:
		material.emission_enabled = false

	_visual.material_override = material

func _setup_progress_bar() -> void:
	"""Create and setup the progress bar."""
	var progress_scene := load("res://src/ui/CookingProgressBar.tscn")
	if not progress_scene:
		return

	_progress_bar = progress_scene.instantiate() as Control
	if not _progress_bar:
		return

	# Add to station as SubViewport for 3D world space
	var viewport := SubViewport.new()
	viewport.size = Vector2i(200, 30)
	viewport.transparent_bg = true
	add_child(viewport)
	viewport.add_child(_progress_bar)

	# Create sprite to show viewport
	var sprite := Sprite3D.new()
	sprite.texture = viewport.get_texture()
	sprite.pixel_size = 0.005
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.position = Vector3(0, 1.5, 0)
	add_child(sprite)

	_progress_bar.visible = false

func _update_progress_bar(progress: float) -> void:
	"""Update the progress bar value."""
	if not _progress_bar:
		return

	var progress_bar_node := _progress_bar.get_node("MarginContainer/ProgressBar") as ProgressBar
	if progress_bar_node:
		progress_bar_node.value = progress
