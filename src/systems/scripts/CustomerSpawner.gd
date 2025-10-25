extends Node3D
class_name CustomerSpawner

## Manages customer spawning, queue, and table assignment

## Signals
signal customer_spawned(customer: Customer)
signal customer_seated(customer: Customer, table: Table)
signal customer_served(customer: Customer)
signal customer_left(customer: Customer, was_satisfied: bool)

## Spawning parameters
@export_group("Spawning")
@export var customer_scene: PackedScene
@export var spawn_interval_min: float = 10.0
@export var spawn_interval_max: float = 20.0
@export var max_customers: int = 5
@export var auto_spawn: bool = true

## Queue management
@export_group("Counter")
@export var order_counter: Node3D = null  # OrderCounter
@export var order_board: Node3D = null  # OrderBoard
@export var auto_seat: bool = true

## Exit
@export var exit_position: Vector3 = Vector3(0, 0, 10)

## References
var _tables: Array[Table] = []
var _customers_waiting_for_table: Array[Customer] = []  # Customers who ordered, waiting for table
var _active_customers: Array[Customer] = []
var _spawn_timer: float = 0.0
var _next_spawn_time: float = 0.0

@onready var _spawn_point: Marker3D = $SpawnPoint
@onready var _entrance_marker: Marker3D = $EntranceMarker

func _ready() -> void:
	# Add to group for easy finding
	add_to_group("customer_spawner")

	_find_tables()
	_find_order_counter()
	_next_spawn_time = randf_range(spawn_interval_min, spawn_interval_max)

	# Load default customer scene if not set
	if not customer_scene:
		customer_scene = load("res://src/characters/scenes/Customer.tscn")

	# Connect counter signals
	if order_counter and order_counter.has_signal("order_taken_at_counter"):
		order_counter.order_taken_at_counter.connect(_on_order_taken_at_counter)

func _process(delta: float) -> void:
	# Clean up invalid references periodically
	_clean_invalid_references()

	if auto_spawn:
		_update_spawning(delta)

	if auto_seat:
		_update_seating()

func _clean_invalid_references() -> void:
	"""Remove invalid customer references from arrays to prevent memory leaks."""
	# Clean active customers array
	_active_customers = _active_customers.filter(func(c): return is_instance_valid(c))

	# Clean waiting for table array
	_customers_waiting_for_table = _customers_waiting_for_table.filter(func(c): return is_instance_valid(c))

func _input(event: InputEvent) -> void:
	# Debug key: Press F7 to spawn a customer manually
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_F7 and key_event.pressed and not key_event.echo:
			print("[DEBUG] F7 key pressed, spawning customer...")
			spawn_customer()
			return

	if event.is_action_pressed("debug_spawn_customer"):
		print("[DEBUG] Manual customer spawn triggered via action")
		spawn_customer()

## Public interface

func spawn_customer() -> Customer:
	"""Manually spawn a customer."""
	print("[DEBUG] spawn_customer() called")

	if not customer_scene:
		push_error("CustomerSpawner: No customer scene set!")
		return null

	if _active_customers.size() >= max_customers:
		print("[DEBUG] Max customers reached (%d/%d)" % [_active_customers.size(), max_customers])
		return null

	# Instantiate customer
	var customer := customer_scene.instantiate() as Customer
	if not customer:
		push_error("CustomerSpawner: Failed to instantiate customer!")
		return null

	# Add to scene
	get_tree().current_scene.add_child(customer)

	# Position at spawn point
	if _spawn_point:
		customer.global_position = _spawn_point.global_position
	else:
		customer.global_position = global_position

	# Random appearance
	customer.customer_color = Color(randf(), randf(), randf())

	# Connect signals
	customer.order_placed.connect(_on_customer_order_placed)
	customer.order_received.connect(_on_customer_order_received)
	customer.left_restaurant.connect(_on_customer_left_restaurant)

	# Set exit position
	if customer.has_method("set_exit_position"):
		customer.set_exit_position(exit_position)

	_active_customers.append(customer)

	# NEW FLOW: Assign table immediately and customer goes directly to it
	var available_table := get_available_table()
	if available_table:
		customer.assign_table(available_table)
		print("[SPAWNER] Customer assigned to table ", available_table.table_number, " - going directly to sit")

		# Emit seated signal
		customer_seated.emit(customer, available_table)
	else:
		print("[SPAWNER] WARNING: No available table for customer! Customer will leave.")
		# No table available - customer leaves immediately (angry)
		customer.leave_restaurant(false)

	customer_spawned.emit(customer)
	return customer

func get_available_table() -> Table:
	"""Find an available table."""
	for table in _tables:
		if table and table.is_available():
			return table
	return null

func seat_customer(customer: Customer, table: Table) -> bool:
	"""Seat a specific customer at a specific table."""
	if not customer or not table:
		return false

	if not table.is_available():
		return false

	# Remove from waiting list
	_customers_waiting_for_table.erase(customer)

	# Assign table to customer (this starts movement)
	# Customer will call table.sit_customer() when they arrive
	customer.assign_table(table)

	customer_seated.emit(customer, table)

	# Now that table is assigned, add order to HUD with correct table number
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("add_order_display"):
		var order := customer.get_order()
		if not order.is_empty():
			order["customer"] = customer
			order["table_number"] = customer.get_assigned_table_number()
			hud.add_order_display(order)

	return true

func get_active_orders() -> Array[Dictionary]:
	"""Get all active customer orders from customers who have placed orders and are waiting for food."""
	var orders: Array[Dictionary] = []

	print("[DEBUG SPAWNER] Checking ", _active_customers.size(), " active customers for orders")
	for customer in _active_customers:
		if is_instance_valid(customer):
			# Check if customer is seated at a table
			var assigned_table := customer.get_assigned_table()
			if assigned_table != null:
				# Check if customer has placed an order and is waiting for food
				if customer.has_method("get_state"):
					var customer_state = customer.get_state()
					print("[DEBUG SPAWNER]   Customer at table ", customer.get_assigned_table_number(), " is in state: ", customer_state)
					# State 3 = WAITING_FOR_FOOD (from NEW CustomerAI.State enum: 0=ENTERING, 1=WAITING_FOR_WAITER, 2=ORDERING, 3=WAITING_FOR_FOOD)
					if customer_state == 3:  # WAITING_FOR_FOOD
						# Check if food is already in delivery - if so, skip this order
						var food_in_delivery := false
						if customer.has_method("is_food_in_delivery"):
							food_in_delivery = customer.is_food_in_delivery()

						if food_in_delivery:
							print("[DEBUG SPAWNER]     -> Order is in delivery, skipping")
							continue

						var order := customer.get_order()
						if not order.is_empty():
							orders.append(order)
							print("[DEBUG SPAWNER]     -> Found active order: ", order.get("type"))

	print("[DEBUG SPAWNER] get_active_orders() returning ", orders.size(), " orders")
	return orders

func get_waiting_count() -> int:
	"""Get number of customers waiting for table."""
	return _customers_waiting_for_table.size()

func get_active_count() -> int:
	"""Get total number of active customers."""
	return _active_customers.size()

## Private methods

func _find_tables() -> void:
	"""Find all tables in the scene."""
	_tables.clear()

	var root := get_tree().current_scene
	_tables = _find_nodes_of_type(root, Table)

func _find_order_counter() -> void:
	"""Find the order counter in the scene."""
	if order_counter:
		print("CustomerSpawner: Order counter already assigned: ", order_counter.name)
		return  # Already assigned in editor

	var root := get_tree().current_scene
	var counters := _find_nodes_of_type_generic(root, "OrderCounter")

	# Also check for WindowCounter
	if counters.size() == 0:
		counters = _find_nodes_of_type_generic(root, "WindowCounter")

	if counters.size() > 0:
		order_counter = counters[0]
		print("CustomerSpawner: Found order counter: ", order_counter.name)
	else:
		push_warning("CustomerSpawner: No order counter found!")

func _find_nodes_of_type(node: Node, type) -> Array[Table]:
	"""Recursively find all nodes of a specific type."""
	var results: Array[Table] = []

	if is_instance_of(node, type):
		results.append(node)

	for child in node.get_children():
		results.append_array(_find_nodes_of_type(child, type))

	return results

func _find_nodes_of_type_generic(node: Node, target_class: String) -> Array:
	"""Recursively find all nodes with a specific class name."""
	var results := []

	if node.get_class() == target_class or (node.get_script() and node.get_script().get_global_name() == target_class):
		results.append(node)

	for child in node.get_children():
		results.append_array(_find_nodes_of_type_generic(child, target_class))

	return results

func _update_spawning(delta: float) -> void:
	"""Update automatic customer spawning."""
	_spawn_timer += delta

	if _spawn_timer >= _next_spawn_time:
		spawn_customer()
		_spawn_timer = 0.0
		_next_spawn_time = randf_range(spawn_interval_min, spawn_interval_max)

func _update_seating() -> void:
	"""Automatically seat customers waiting for tables after ordering."""
	if _customers_waiting_for_table.is_empty():
		return

	# Try to seat ALL waiting customers, not just one per frame
	var customers_to_seat := _customers_waiting_for_table.duplicate()
	for customer in customers_to_seat:
		var table := get_available_table()
		if not table:
			print("[DEBUG SPAWNER] No available tables for customer")
			break  # No more tables available

		print("[DEBUG SPAWNER] Found available table ", table.table_number, " for customer")
		seat_customer(customer, table)


## Signal handlers

func _on_order_taken_at_counter(customer: Customer, order: Dictionary) -> void:
	"""Order was taken at counter, customer needs a table."""
	# Add customer to waiting list for table
	if customer and not _customers_waiting_for_table.has(customer):
		_customers_waiting_for_table.append(customer)

	# Add order to kitchen board
	if order_board and order_board.has_method("add_order"):
		order_board.add_order(customer, order)

func _on_customer_order_placed(customer: Customer, order: Dictionary) -> void:
	"""Customer has placed an order."""
	# Don't add to HUD yet - will be added when table is assigned in seat_customer()
	# This ensures the correct table number is shown
	pass

func _on_customer_order_received(customer: Customer) -> void:
	"""Customer received their food."""
	customer_served.emit(customer)

	# Remove order from HUD
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("remove_order_display"):
		var order := {"customer": customer}
		hud.remove_order_display(order)

func _on_customer_left_restaurant(customer: Customer, was_satisfied: bool) -> void:
	"""Customer has left the restaurant."""
	_active_customers.erase(customer)
	_customers_waiting_for_table.erase(customer)

	# Disconnect signals to prevent memory leaks
	if is_instance_valid(customer):
		if customer.order_placed.is_connected(_on_customer_order_placed):
			customer.order_placed.disconnect(_on_customer_order_placed)
		if customer.order_received.is_connected(_on_customer_order_received):
			customer.order_received.disconnect(_on_customer_order_received)
		if customer.left_restaurant.is_connected(_on_customer_left_restaurant):
			customer.left_restaurant.disconnect(_on_customer_left_restaurant)

	customer_left.emit(customer, was_satisfied)
