extends CharacterBody3D
class_name Chef

## Signals
signal food_prepared(chef: Chef, food: FoodItem, order: Dictionary)
signal state_changed(chef: Chef, new_state: State)
signal order_started(chef: Chef, order: Dictionary)

## Chef states
enum State {
	IDLE,                  # Standing idle, waiting for orders
	MOVING_TO_STORAGE,     # Walking to storage to get ingredients
	PICKING_INGREDIENTS,   # Picking up food item from storage
	MOVING_TO_STATION,     # Walking to cooking station
	PLACING_FOOD,          # Placing food on station
	WAITING_FOR_COOKING,   # Waiting for food to finish cooking
	PICKING_COOKED_FOOD,   # Picking up cooked food
	MOVING_TO_COUNTER,     # Walking to serving counter
	PLACING_AT_COUNTER     # Placing food at serving counter
}

## Movement parameters
@export_group("Movement")
@export var move_speed: float = 2.5
@export var acceleration: float = 8.0
@export var arrival_tolerance: float = 0.4

## Behavior parameters
@export_group("Behavior")
@export var check_interval: float = 2.0  # How often to check for new orders
@export var retry_delay: float = 10.0    # How long to wait after failing to find ingredients
@export var pickup_range: float = 1.5     # Range to interact with items

## Visual customization
@export_group("Appearance")
@export var chef_color: Color = Color(0.95, 0.95, 0.95)  # White chef uniform

## Internal state
var _state: State = State.IDLE
var _target_position: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _current_order: Dictionary = {}
var _held_food: FoodItem = null
var _cooking_food: FoodItem = null  # Track the food we placed on station for cooking
var _assigned_customer: Node = null  # Track which customer we're cooking for
var _check_timer: float = 0.0
var _idle_position: Vector3 = Vector3.ZERO
var _serving_counter: Node3D = null
var _current_station: Node3D = null
var _storage_position: Vector3 = Vector3.ZERO

## References
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: MeshInstance3D = $Visual
@onready var _held_item_position: Marker3D = $HeldItemPosition
var _status_label: Label3D = null
var _progress_indicator: Node3D = null  # Circular progress UI for cooking actions

func _ready() -> void:
	print("[CHEF] Ready called!")

	# Add to chefs group for station recognition
	add_to_group("chefs")

	# Setup navigation agent
	if _agent:
		_agent.velocity_computed.connect(_on_velocity_computed)
		_agent.target_reached.connect(_on_nav_target_reached)
		_agent.path_desired_distance = 0.5
		_agent.target_desired_distance = 0.5
		print("[CHEF] NavigationAgent configured")
	else:
		print("[CHEF] ERROR: No NavigationAgent found!")

	# Set visual appearance
	if _visual and _visual.mesh:
		var material := StandardMaterial3D.new()
		material.albedo_color = chef_color
		_visual.material_override = material

	# Create status label
	_create_status_label()

	# Create progress indicator
	_create_progress_indicator()

	# Store initial position as idle position
	_idle_position = global_position

	# Wait for navigation to be ready
	call_deferred("_navigation_setup")

	state_changed.emit(self, _state)

func _exit_tree() -> void:
	"""Clean up resources when chef is removed from scene."""
	# CRITICAL: Cancel all active timers and coroutines first
	# This prevents hanging when window is closed
	set_process(false)
	set_physics_process(false)

	# Disconnect signals to prevent memory leaks
	if _agent:
		if _agent.velocity_computed.is_connected(_on_velocity_computed):
			_agent.velocity_computed.disconnect(_on_velocity_computed)
		if _agent.target_reached.is_connected(_on_nav_target_reached):
			_agent.target_reached.disconnect(_on_nav_target_reached)

	# Clean up status label
	if is_instance_valid(_status_label):
		_status_label.queue_free()
		_status_label = null

	# Clean up progress indicator
	if is_instance_valid(_progress_indicator):
		_progress_indicator.queue_free()
		_progress_indicator = null

	# Clean up held food if still exists
	if _held_food and is_instance_valid(_held_food):
		if _held_food.get_parent():
			_held_food.get_parent().remove_child(_held_food)
		_held_food.queue_free()
		_held_food = null

	# Clean up cooking food reference
	if _cooking_food and is_instance_valid(_cooking_food):
		_cooking_food = null

	# Clear chef assignment from customer
	if _assigned_customer and is_instance_valid(_assigned_customer) and _assigned_customer.has_method("clear_chef_assignment"):
		_assigned_customer.clear_chef_assignment()

	# Clear references
	_serving_counter = null
	_current_station = null
	_assigned_customer = null

func _create_status_label() -> void:
	"""Create a Label3D to show chef status."""
	_status_label = Label3D.new()
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.font_size = 48
	_status_label.outline_size = 8
	_status_label.modulate = Color.WHITE
	_status_label.outline_modulate = Color.BLACK
	_status_label.pixel_size = 0.005
	_status_label.position = Vector3(0, 2.2, 0)
	add_child(_status_label)
	_update_status_display()

func _create_progress_indicator() -> void:
	"""Create a 3D circular progress indicator for cooking actions."""
	# Create a Node3D container for the progress UI
	_progress_indicator = Node3D.new()
	_progress_indicator.name = "ProgressIndicator"
	add_child(_progress_indicator)

	# Position it at the same level as status label to surround the emoji
	_progress_indicator.position = Vector3(0, 2.2, 0)

	# Create a Sprite3D to display the circular progress
	var sprite := Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.004
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

	# Create a viewport to render the circular progress
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Create the circular progress control
	var progress_script := load("res://src/ui/CircularProgress.gd")
	var progress_control := Control.new()
	progress_control.set_script(progress_script)
	progress_control.size = Vector2(128, 128)
	progress_control.set("ring_color", Color(1.0, 0.5, 0.0, 0.9))  # Orange color for chef
	progress_control.set("background_color", Color(0.2, 0.2, 0.2, 0.6))
	progress_control.set("ring_thickness", 10.0)
	progress_control.set("ring_radius_offset", 8.0)
	progress_control.set("progress", 0.0)

	# Add to viewport
	viewport.add_child(progress_control)
	_progress_indicator.add_child(viewport)

	# Set viewport texture to sprite
	sprite.texture = viewport.get_texture()
	_progress_indicator.add_child(sprite)

	# Hide by default
	_progress_indicator.visible = false

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Only process AI when game is playing
	var game_manager = GameManager.instance
	if not game_manager or game_manager.current_state != GameManager.GameState.PLAYING:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_update_state_behavior(delta)

	match _state:
		State.IDLE, State.PICKING_INGREDIENTS, State.PLACING_FOOD, State.WAITING_FOR_COOKING, State.PICKING_COOKED_FOOD, State.PLACING_AT_COUNTER:
			# Keep horizontal velocity at zero but allow gravity
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
		State.MOVING_TO_STORAGE, State.MOVING_TO_STATION, State.MOVING_TO_COUNTER:
			_update_movement(delta)

func _update_state_behavior(delta: float) -> void:
	match _state:
		State.IDLE:
			_check_timer += delta
			if _check_timer >= check_interval:
				_check_timer = 0.0
				_look_for_orders()

		State.WAITING_FOR_COOKING:
			_check_if_cooking_finished()

func _navigation_setup() -> void:
	"""Called after navigation is ready."""
	await get_tree().physics_frame

	# CRITICAL: Check if node is still valid before continuing
	# This prevents crashes when window is closed during initialization
	if not is_inside_tree():
		return

	# Use safe timer that can be checked
	var timer := get_tree().create_timer(0.5)
	await timer.timeout

	# CRITICAL: Check again after timer to prevent crashes
	if not is_inside_tree():
		return

	print("[CHEF] Navigation setup complete")

	# Find serving counter
	_find_serving_counter()

func _look_for_orders() -> void:
	"""Check if there are pending orders to cook."""
	if _state != State.IDLE:
		return

	# Don't take new orders if we're still working on one
	if not _current_order.is_empty():
		return

	# Get orders from CustomerSpawner
	var spawner := _find_customer_spawner()
	if not spawner:
		return

	var active_orders: Array = []
	var orders_temp = spawner.get_active_orders()
	if orders_temp:
		active_orders = orders_temp

	if active_orders.is_empty():
		return

	# Find an order that doesn't have a chef assigned yet
	var selected_order: Dictionary = {}
	var selected_customer: Node = null

	# Get all customers to check chef assignments
	var customers := get_tree().get_nodes_in_group("customers")

	for order in active_orders:
		var order_type: String = order.get("type", "")
		var order_status: String = order.get("status", "pending")

		# Skip orders that are already being handled (cooking, ready, or delivering)
		# Only process "pending" orders to prevent duplicate cooking
		if order_status != "pending":
			# Disabled debug spam for performance
			# print("[CHEF DEBUG] Order '", order_type, "' is already ", order_status, ", skipping")
			continue

		# Check if we have enough food on counter for pending orders
		var food_on_counter: int = _count_food_on_counter(order_type)
		var pending_orders: int = _count_pending_orders(order_type)

		# Disabled debug spam for performance
		# print("[CHEF DEBUG] Food type '", order_type, "': ", food_on_counter, " on counter, ", pending_orders, " pending orders")

		# If we have enough food on counter, skip this food type
		if food_on_counter >= pending_orders:
			# Disabled debug spam for performance
			# print("[CHEF DEBUG] Enough '", order_type, "' on counter, skipping")
			continue

		var found_unassigned := false

		# Find the customer with this order
		for customer in customers:
			if customer and is_instance_valid(customer) and customer.has_method("get_order"):
				var customer_order: Dictionary = customer.get_order()
				if customer_order.get("type") == order_type:
					# Check if this customer already has a chef assigned
					if customer.has_method("is_chef_assigned") and customer.is_chef_assigned():
						continue  # Skip, another chef is already cooking for this customer

					# IMMEDIATELY try to assign ourselves to prevent race condition with other chefs
					var assignment_successful := false
					if customer.has_method("assign_chef"):
						assignment_successful = customer.assign_chef(self)

					# Only proceed if we successfully claimed this customer
					if not assignment_successful:
						print("[CHEF] Failed to assign to customer (another chef claimed them first)")
						continue

					# Found an unassigned order and successfully claimed it!
					selected_order = order
					selected_customer = customer
					found_unassigned = true
					print("[CHEF] Successfully claimed customer for order: ", order.get("type"))
					break

		if found_unassigned:
			break

	if selected_order.is_empty():
		return  # No unassigned orders found

	# Track the customer
	_assigned_customer = selected_customer

	_current_order = selected_order
	print("[CHEF] Starting order: ", _current_order.get("name", "Unknown"))
	order_started.emit(self, _current_order)

	# Find cooking station and go directly there
	var food_type: String = _current_order.get("type", "")
	_current_station = _find_cooking_station_for_food(food_type)
	if not _current_station:
		print("[CHEF] ERROR: No cooking station found for: ", food_type)
		_check_timer = -retry_delay
		_set_state(State.IDLE)
		# Clear chef assignment if we fail
		if selected_customer and selected_customer.has_method("clear_chef_assignment"):
			selected_customer.clear_chef_assignment()
		return

	# Move directly to station (skip storage)
	_set_state(State.MOVING_TO_STATION)
	print("[CHEF] Moving to station at: ", _current_station.global_position)
	_move_to(_current_station.global_position + Vector3(0, 0, 1.5))

func _find_customer_spawner() -> Node:
	"""Find the CustomerSpawner in the scene."""
	var spawners := get_tree().get_nodes_in_group("customer_spawner")
	if spawners.size() > 0:
		return spawners[0]

	# Fallback: search by type
	var root := get_tree().current_scene
	return _find_node_of_type(root, "CustomerSpawner")

func _find_node_of_type(node: Node, type_name: String) -> Node:
	"""Recursively find a node with a specific class name."""
	if node.get_class() == type_name or (node.get_script() and node.get_script().get_global_name() == type_name):
		return node

	for child in node.get_children():
		var result := _find_node_of_type(child, type_name)
		if result:
			return result

	return null

func _find_serving_counter() -> void:
	"""Find the serving counter in the scene."""
	var counters := get_tree().get_nodes_in_group("serving_counter")
	if counters.size() > 0:
		_serving_counter = counters[0]
		print("[CHEF] Found serving counter: ", _serving_counter.name)
	else:
		print("[CHEF] WARNING: No serving counter found!")

func _count_food_on_counter(food_type: String) -> int:
	"""Count how many foods of this type are on the serving counter."""
	if not _serving_counter or not _serving_counter.has_method("get_placed_foods"):
		return 0

	var foods_on_counter: Array = _serving_counter.get_placed_foods()
	var count: int = 0

	for food in foods_on_counter:
		if food and is_instance_valid(food) and food.has_method("get_food_data"):
			var food_data: Dictionary = food.get_food_data()
			if food_data.get("type") == food_type and food_data.get("is_edible"):
				count += 1

	return count

func _count_pending_orders(food_type: String) -> int:
	"""Count how many customers are waiting for this food type (no chef assigned yet)."""
	var customers := get_tree().get_nodes_in_group("customers")
	var count: int = 0

	for customer in customers:
		if customer and is_instance_valid(customer) and customer.has_method("get_order"):
			var customer_order: Dictionary = customer.get_order()
			if customer_order.get("type") == food_type:
				# Only count if no chef is assigned yet
				if not (customer.has_method("is_chef_assigned") and customer.is_chef_assigned()):
					# And food is not already on counter waiting for them
					count += 1

	return count

func _create_and_place_food() -> void:
	"""Create food item and place it on the station (like player does)."""
	print("[CHEF] Creating food at station")
	if _current_order.is_empty():
		print("[CHEF] ERROR: No current order!")
		_set_state(State.IDLE)
		return

	if not _current_station:
		print("[CHEF] ERROR: No current station!")
		_set_state(State.IDLE)
		return

	var food_type: String = _current_order.get("type", "")

	# Create food item (spawn from nothing, like player does)
	var food_item := _create_food_item(food_type)
	if not food_item:
		print("[CHEF] ERROR: Could not create food item for: ", food_type)
		_check_timer = -retry_delay
		_set_state(State.IDLE)
		return

	print("[CHEF] Created food item, placing on station...")

	# Add to scene
	get_tree().current_scene.add_child(food_item)
	food_item.global_position = _current_station.global_position + Vector3(0, 1.5, 0)

	# Try to place food on station
	if _current_station.has_method("place_food"):
		var success: bool = _current_station.place_food(food_item, self)
		if success:
			print("[CHEF] Food placed on station successfully, waiting for cooking...")
			# Track this food as the one we're cooking
			_cooking_food = food_item
			# Wait for cooking to finish
			_set_state(State.WAITING_FOR_COOKING)
		else:
			print("[CHEF] Failed to place food on station")
			food_item.queue_free()
			_set_state(State.IDLE)
	else:
		print("[CHEF] Station doesn't have place_food method")
		food_item.queue_free()
		_set_state(State.IDLE)

func _create_food_item(food_type: String) -> FoodItem:
	"""Create a new food item from scratch (like player does)."""
	# Load FoodItem script
	var FoodItemScript = load("res://src/systems/scripts/FoodItem.gd")
	if not FoodItemScript:
		print("[CHEF] ERROR: Could not load FoodItem script!")
		return null

	# Create new FoodItem instance
	var food_item = RigidBody3D.new()
	food_item.set_script(FoodItemScript)

	# Set food type based on order
	var food_enum_value = -1
	match food_type.to_lower():
		"pizza":
			food_enum_value = 0  # FoodType.PIZZA
			food_item.food_name = "Pizza"
			food_item.cooking_time = 20.0
			food_item.requires_prep = false  # Chef already "prepared" it
		"burger":
			food_enum_value = 1  # FoodType.BURGER
			food_item.food_name = "Burger"
			food_item.cooking_time = 12.0
			food_item.requires_prep = false  # Chef already "prepared" it
		"pasta":
			food_enum_value = 2  # FoodType.PASTA
			food_item.food_name = "Pasta"
			food_item.cooking_time = 15.0
			food_item.requires_prep = false  # Chef already "prepared" it
		"salad":
			food_enum_value = 3  # FoodType.SALAD
			food_item.food_name = "Salad"
			food_item.cooking_time = 0.0  # No cooking needed
			food_item.requires_prep = false  # Chef already "prepared" it
		"soup":
			food_enum_value = 4  # FoodType.SOUP
			food_item.food_name = "Soup"
			food_item.cooking_time = 18.0
			food_item.requires_prep = false  # Chef already "prepared" it
		_:
			print("[CHEF] ERROR: Unknown food type: ", food_type)
			food_item.queue_free()
			return null

	food_item.food_type = food_enum_value

	# Create visual mesh
	var visual = MeshInstance3D.new()
	visual.name = "Visual"
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.3, 0.2, 0.3)
	visual.mesh = mesh
	visual.position = Vector3(0, 0.1, 0)
	food_item.add_child(visual)

	# Create collision shape
	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.3, 0.2, 0.3)
	collision.shape = shape
	collision.position = Vector3(0, 0.1, 0)
	food_item.add_child(collision)

	# Create steam particles (optional, can be null)
	var particles = GPUParticles3D.new()
	particles.name = "SteamParticles"
	particles.emitting = false
	food_item.add_child(particles)

	print("[CHEF] Created ", food_type, " food item")
	return food_item

func _find_all_food_items(node: Node) -> Array[Node]:
	"""Recursively find all FoodItem nodes."""
	var items: Array[Node] = []

	if node is FoodItem:
		items.append(node)

	for child in node.get_children():
		items.append_array(_find_all_food_items(child))

	return items

func _find_cooking_station_for_food(food_type: String) -> Node3D:
	"""Find the appropriate cooking station for this food type."""
	# Get menu item to find required station
	var order_manager := GameManager.instance.order_manager if GameManager.instance else null
	if not order_manager:
		return null

	var menu_item := order_manager.get_menu_item(food_type)
	var station_type: String = menu_item.get("station_type", "")

	# Find stations
	var stations := get_tree().get_nodes_in_group("cooking_stations")
	for station in stations:
		if station.has_method("get_station_type"):
			if station.get_station_type() == station_type:
				return station

	return null

func _place_food_at_station() -> void:
	"""DEPRECATED: No longer used. Chef creates food directly at station."""
	_set_state(State.IDLE)

func _check_if_cooking_finished() -> void:
	"""Check if the food we placed on the station is done cooking."""
	# Check if we still have a valid cooking food reference
	if not _cooking_food or not is_instance_valid(_cooking_food):
		print("[CHEF] Cooking food is invalid or was removed, going idle")
		_set_state(State.IDLE)
		_show_progress_indicator(false)
		_cooking_food = null
		return

	# Check our specific food's cooking progress
	var food_data: Dictionary = _cooking_food.get_food_data()
	var food_state: int = food_data.get("state", 0)
	var cooking_progress: float = food_data.get("cooking_progress", 0.0)

	# Show progress indicator and update it
	_show_progress_indicator(true)
	_update_progress_indicator(cooking_progress)

	# Debug: Print state periodically
	if Engine.get_physics_frames() % 60 == 0:  # Every ~1 second
		print("[CHEF] Checking food state: ", food_state, " | Progress: ", cooking_progress, "% (waiting for 2=COOKED)")

	# State 2 = COOKED
	if food_state == 2:
		print("[CHEF] Food is cooked! Picking it up...")
		_show_progress_indicator(false)
		_pick_cooked_food(_cooking_food)
		_cooking_food = null  # Clear reference after picking up

func _pick_cooked_food(food: FoodItem) -> void:
	"""Pick up the cooked food from the station."""
	if not food or not is_instance_valid(food):
		_set_state(State.IDLE)
		return

	# Remove from station
	if _current_station.has_method("remove_food"):
		_current_station.remove_food(food)

	# Hold the food
	_held_food = food

	# Disable physics
	if food is RigidBody3D:
		food.freeze = true

	# Parent to held position
	if food.get_parent():
		food.get_parent().remove_child(food)
	_held_item_position.add_child(food)
	food.position = Vector3.ZERO

	# Move to serving counter
	_set_state(State.MOVING_TO_COUNTER)
	if _serving_counter:
		var counter_pos := _serving_counter.global_position + Vector3(0, 0, 1.0)
		_move_to(counter_pos)
	else:
		# Fallback to idle if no counter
		_set_state(State.IDLE)

func _place_food_at_counter() -> void:
	"""Place cooked food at the serving counter for waiters."""
	if not _held_food or not _serving_counter:
		_set_state(State.IDLE)
		return

	# Release food from held position and add back to scene
	if _held_item_position and _held_food.get_parent() == _held_item_position:
		_held_item_position.remove_child(_held_food)
		get_tree().current_scene.add_child(_held_food)

	# Use the serving counter's place_food method to properly place it
	if _serving_counter.has_method("place_food"):
		var success: bool = _serving_counter.place_food(_held_food, self)
		if success:
			print("[CHEF] Food placed on serving counter successfully!")
			# Emit signal
			food_prepared.emit(self, _held_food, _current_order)
		else:
			print("[CHEF] Failed to place food on serving counter - food is not cooked! Deleting raw food...")
			# If placement failed (food not cooked), delete the food item
			if is_instance_valid(_held_food):
				_held_food.queue_free()
	else:
		# If no place_food method exists, also delete the food
		print("[CHEF] Serving counter has no place_food method! Deleting food...")
		if is_instance_valid(_held_food):
			_held_food.queue_free()

	# Clear chef assignment from customer
	if _assigned_customer and is_instance_valid(_assigned_customer) and _assigned_customer.has_method("clear_chef_assignment"):
		_assigned_customer.clear_chef_assignment()

	# Clear state
	_held_food = null
	_current_station = null
	_current_order = {}
	_assigned_customer = null

	# Return to idle
	_set_state(State.IDLE)

func _update_movement(delta: float) -> void:
	"""Handle navigation movement."""
	if not _has_target:
		return

	if not _agent:
		return

	# Check if we've reached the destination
	var distance_to_target := global_position.distance_to(_target_position)
	if distance_to_target < arrival_tolerance:
		_finish_movement()
		return

	if _agent.is_navigation_finished():
		_finish_movement()
		return

	var next_position := _agent.get_next_path_position()
	var direction := (next_position - global_position).normalized()
	direction.y = 0.0

	var desired_velocity := direction * move_speed

	if _agent:
		_agent.set_velocity(desired_velocity)
	else:
		velocity = velocity.move_toward(desired_velocity, acceleration * delta)
		move_and_slide()

	# Rotate to face movement direction
	if direction.length() > 0.01:
		var target_rotation := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 10.0)

func _finish_movement() -> void:
	"""Called when chef reaches destination."""
	if not _has_target:
		return

	velocity = Vector3.ZERO
	_has_target = false

	print("[CHEF] Reached destination, state: ", State.keys()[_state])

	match _state:
		State.MOVING_TO_STORAGE:
			# No longer used, but keep for compatibility
			_set_state(State.IDLE)

		State.MOVING_TO_STATION:
			_set_state(State.PLACING_FOOD)
			_create_and_place_food()

		State.MOVING_TO_COUNTER:
			_set_state(State.PLACING_AT_COUNTER)
			_place_food_at_counter()

func _move_to(target_pos: Vector3) -> void:
	"""Direct the chef to walk to a specific position."""
	_target_position = target_pos
	_target_position.y = global_position.y  # Keep same height
	_has_target = true

	if _agent:
		_agent.target_position = _target_position

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	"""Handle NavigationAgent velocity computation."""
	# Preserve gravity (y component) while using navigation's horizontal velocity
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()

func _on_nav_target_reached() -> void:
	"""Handle NavigationAgent target reached."""
	_finish_movement()

func _set_state(new_state: State) -> void:
	"""Change chef state."""
	if _state == new_state:
		return

	# Clear customer assignment when going to IDLE (failure/completion case)
	if new_state == State.IDLE:
		if _assigned_customer and is_instance_valid(_assigned_customer) and _assigned_customer.has_method("clear_chef_assignment"):
			_assigned_customer.clear_chef_assignment()
		_assigned_customer = null

	_state = new_state
	state_changed.emit(self, _state)
	_update_status_display()

func _update_status_display() -> void:
	"""Update the status label text."""
	if not _status_label:
		return

	var status_text := ""
	match _state:
		State.IDLE:
			status_text = "💤"
		State.MOVING_TO_STORAGE:
			status_text = "🚶"
		State.PICKING_INGREDIENTS:
			status_text = "📦"
		State.MOVING_TO_STATION:
			status_text = "🚶"
		State.PLACING_FOOD:
			status_text = "🍳"
		State.WAITING_FOR_COOKING:
			status_text = "⏰"
		State.PICKING_COOKED_FOOD:
			status_text = "✅"
		State.MOVING_TO_COUNTER:
			status_text = "🚶"
		State.PLACING_AT_COUNTER:
			status_text = "🍽️"

	_status_label.text = status_text

## Public methods

func get_state() -> State:
	"""Returns the chef's current state."""
	return _state

func set_idle_position(pos: Vector3) -> void:
	"""Set the position where chef should idle."""
	_idle_position = pos

func set_storage_position(pos: Vector3) -> void:
	"""Set the storage area position."""
	_storage_position = pos

func _show_progress_indicator(show_progress: bool) -> void:
	"""Show or hide the circular progress indicator."""
	if _progress_indicator:
		_progress_indicator.visible = show_progress
		if not show_progress:
			# Reset progress when hiding
			_update_progress_indicator(0.0)

func _update_progress_indicator(progress: float) -> void:
	"""Update the progress indicator percentage (0-100)."""
	if not _progress_indicator:
		return

	# Find the viewport and its progress control child
	for child in _progress_indicator.get_children():
		if child is SubViewport:
			for viewport_child in child.get_children():
				if viewport_child is Control and "progress" in viewport_child:
					viewport_child.set("progress", progress)
					break
			break

## Save/Load Methods

func get_save_data() -> Dictionary:
	"""Get chef data for saving."""
	var data := {
		"position": global_position,
		"rotation_y": rotation.y,
		"state": _state,
		"idle_position": _idle_position,
		"storage_position": _storage_position,
		"target_position": _target_position,
		"has_target": _has_target,
		"current_order": _current_order,
		# Customer reference will be rebuilt by SaveManager
		"assigned_customer_id": _assigned_customer._save_id if _assigned_customer and is_instance_valid(_assigned_customer) else -1,
		# Food data (just the type, will be recreated)
		"held_food_type": _held_food.get_food_data().get("type") if _held_food and is_instance_valid(_held_food) else "",
		"cooking_food_type": _cooking_food.get_food_data().get("type") if _cooking_food and is_instance_valid(_cooking_food) else "",
		# Station reference (save station position to find it again)
		"current_station_pos": _current_station.global_position if _current_station and is_instance_valid(_current_station) else Vector3.ZERO,
	}
	return data

func apply_save_data(data: Dictionary) -> void:
	"""Apply loaded save data to chef."""
	# Position and rotation
	global_position = data.get("position", Vector3.ZERO)
	rotation.y = data.get("rotation_y", 0.0)

	# State
	_state = data.get("state", State.IDLE)
	_update_status_display()

	# Movement data
	_idle_position = data.get("idle_position", Vector3.ZERO)
	_storage_position = data.get("storage_position", Vector3.ZERO)
	_target_position = data.get("target_position", Vector3.ZERO)
	_has_target = data.get("has_target", false)

	# Order data
	_current_order = data.get("current_order", {})

	# Customer reference will be rebuilt by SaveManager after all entities are loaded
	set_meta("_saved_customer_id", data.get("assigned_customer_id", -1))

	# Food items (save manager will recreate if needed)
	var held_food_type: String = data.get("held_food_type", "")
	if held_food_type != "":
		set_meta("_saved_held_food_type", held_food_type)

	var cooking_food_type: String = data.get("cooking_food_type", "")
	if cooking_food_type != "":
		set_meta("_saved_cooking_food_type", cooking_food_type)

	# Station reference (will need to find closest station)
	var station_pos: Vector3 = data.get("current_station_pos", Vector3.ZERO)
	if station_pos != Vector3.ZERO:
		set_meta("_saved_station_pos", station_pos)

	# Resume navigation if was moving
	if _has_target and _agent:
		_agent.target_position = _target_position

	print("[CHEF] Restored from save - State: %s, Position: %v" % [State.keys()[_state], global_position])
