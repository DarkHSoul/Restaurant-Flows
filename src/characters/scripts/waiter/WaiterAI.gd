extends CharacterBody3D
class_name Waiter

## Signals
signal order_taken(waiter: Waiter, customer: Customer, order: Dictionary)
signal food_delivered(waiter: Waiter, customer: Customer)
signal state_changed(waiter: Waiter, new_state: State)

## Waiter states
enum State {
	IDLE,              # Standing idle, looking for work
	MOVING_TO_TABLE,   # Walking to table to take order from seated customer
	TAKING_ORDER,      # Taking order from customer at table
	MOVING_TO_COUNTER, # Walking to serving counter to pick up food
	WAITING_FOR_FOOD,  # Waiting at serving counter for chef to prepare food
	PICKING_UP_FOOD,   # Picking up prepared food from counter
	DELIVERING_FOOD,   # Walking to customer's table with food
	RETURNING          # Returning to idle position
}

## Movement parameters
@export_group("Movement")
@export var move_speed: float = 3.0
@export var acceleration: float = 8.0
@export var arrival_tolerance: float = 0.4

## Behavior parameters
@export_group("Behavior")
@export var check_interval: float = 1.0  # How often to check for work
@export var pickup_range: float = 2.0     # Range to detect food items
@export var food_check_interval: float = 2.0  # How often to check for food when waiting

## Visual customization
@export_group("Appearance")
@export var waiter_color: Color = Color(0.2, 0.6, 0.9)  # Blue uniform

## Internal state
var _state: State = State.IDLE
var _target_position: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _assigned_customer: Customer = null
var _current_order: Dictionary = {}
var _held_food: FoodItem = null
var _reserved_food: FoodItem = null  # Track which food we've reserved
var _check_timer: float = 0.0
var _food_wait_timer: float = 0.0
var _idle_position: Vector3 = Vector3.ZERO
var _counter_reference: Node3D = null
var _kitchen_position: Vector3 = Vector3.ZERO

## References
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: MeshInstance3D = $Visual
@onready var _held_item_position: Marker3D = $HeldItemPosition
var _status_label: Label3D = null

func _ready() -> void:
	# Setup navigation agent
	if _agent:
		_agent.velocity_computed.connect(_on_velocity_computed)
		_agent.target_reached.connect(_on_nav_target_reached)
		_agent.path_desired_distance = 0.5
		_agent.target_desired_distance = 0.5
		print("[WAITER INIT] NavigationAgent found and connected!")
		print("[WAITER INIT] Agent settings - max_speed: %.2f, radius: %.2f, avoidance: %s" % [
			_agent.max_speed,
			_agent.radius,
			_agent.avoidance_enabled
		])
	else:
		print("[WAITER INIT] ERROR: No NavigationAgent found!")

	# Set visual appearance
	if _visual and _visual.mesh:
		var material := StandardMaterial3D.new()
		material.albedo_color = waiter_color
		_visual.material_override = material

	# Create status label
	_create_status_label()

	# Store initial position as idle position
	_idle_position = global_position

	# Wait for navigation to be ready
	call_deferred("_navigation_setup")

	state_changed.emit(self, _state)

func _exit_tree() -> void:
	"""Clean up resources when waiter is removed from scene."""
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

	# Clean up held food if still exists
	if _held_food and is_instance_valid(_held_food):
		if _held_food.get_parent():
			_held_food.get_parent().remove_child(_held_food)
		_held_food.queue_free()
		_held_food = null

	# Clear references
	_assigned_customer = null
	_counter_reference = null

func _create_status_label() -> void:
	"""Create a Label3D to show waiter status."""
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

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	_update_state_behavior(delta)

	# Debug: Print state and position every 60 frames (approximately 1 second)
	# DISABLED - Too verbose
	# if Engine.get_physics_frames() % 60 == 0:
	# 	print("[WAITER DEBUG] State: %s | Position: %v | On Floor: %s | Has Target: %s" % [
	# 		State.keys()[_state],
	# 		global_position,
	# 		is_on_floor(),
	# 		_has_target
	# 	])

	match _state:
		State.IDLE, State.TAKING_ORDER:
			# Keep horizontal velocity at zero but allow gravity
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
		State.WAITING_FOR_FOOD:
			# Keep horizontal velocity at zero but check for food
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			_check_for_food_pickup()
		State.MOVING_TO_TABLE, State.MOVING_TO_COUNTER, State.DELIVERING_FOOD, State.RETURNING:
			_update_movement(delta)

func _update_state_behavior(delta: float) -> void:
	match _state:
		State.IDLE:
			_check_timer += delta
			if _check_timer >= check_interval:
				_check_timer = 0.0
				_look_for_work()

		State.WAITING_FOR_FOOD:
			# Check for food periodically while waiting
			_food_wait_timer += delta
			if _food_wait_timer >= food_check_interval:
				_food_wait_timer = 0.0
				# If we've been waiting too long (30 seconds), give up and look for other customers
				if _check_timer >= 30.0:
					print("[WAITER] Waited too long for food, abandoning order and looking for other customers")
					_assigned_customer = null
					_current_order = {}
					_set_state(State.IDLE)
				else:
					_check_timer += delta

func _navigation_setup() -> void:
	"""Called after navigation is ready."""
	await get_tree().physics_frame

	# Wait a bit more for navigation map to be fully ready
	await get_tree().create_timer(0.5).timeout

	if _agent:
		# Ensure agent is on the navigation map
		print("[WAITER] Navigation setup complete. Map RID: ", _agent.get_navigation_map())

func _look_for_work() -> void:
	"""Check if there are customers at tables waiting for service."""
	if _state != State.IDLE:
		return

	# Find serving counter reference
	_counter_reference = _find_serving_counter()

	# Priority 1: Check if there's ready food to deliver (someone already ordered and food is ready)
	var ready_food := _check_for_ready_food_to_deliver()
	if ready_food:
		print("[WAITER] Found ready food to deliver!")
		return

	# Priority 2: Look for customers waiting for waiter to take orders
	var customer := _find_customer_waiting_for_service()
	if customer:
		print("[WAITER] Found customer at table waiting for service! Moving to table...")
		_assigned_customer = customer
		_set_state(State.MOVING_TO_TABLE)

		# Get customer's table position
		var table := customer.get_assigned_table()
		if table:
			var table_pos := table.global_position + Vector3(1.5, 0, 0)  # Stand next to table
			table_pos.y = 0.0

			print("[WAITER] Moving to table ", table.table_number, " at position: %v" % table_pos)

			# Move to table immediately
			_move_to(table_pos)

			# Open doors in background (don't await - it breaks the state)
			_open_doors_to_target(table_pos)
		else:
			print("[WAITER] ERROR: Customer has no assigned table!")
			_set_state(State.IDLE)

func _check_for_ready_food_to_deliver() -> bool:
	"""Check if there's any ready food at the serving counter that needs delivery."""
	# Find serving counter
	var serving_counter: Node3D = _find_serving_counter()
	if not serving_counter:
		return false

	# Check if counter has any food on it
	if not serving_counter.has_method("get_placed_foods"):
		return false

	var foods: Array = serving_counter.get_placed_foods()
	if foods.is_empty():
		return false

	# Check if any customer is waiting for food (has placed order)
	var customers := get_tree().get_nodes_in_group("customers")
	for customer in customers:
		if customer is Customer and is_instance_valid(customer):
			# State 3 = WAITING_FOR_FOOD (customer has ordered and is waiting)
			if customer.get_state() == 3:
				var customer_order: Dictionary = customer.get_order()
				if customer_order.is_empty():
					continue

				# Check if there's food on serving counter matching this order
				for food in foods:
					if is_instance_valid(food) and food.has_method("get_food_data"):
						# Check if food is already reserved by another waiter
						if food.has_method("is_reserved") and food.is_reserved():
							var reserved_waiter = food.get_reserved_waiter()
							if reserved_waiter != self:
								continue  # Skip this food, another waiter reserved it

						var food_data: Dictionary = food.get_food_data()
						if food_data.get("type") == customer_order.get("type"):
							# Try to reserve this food for ourselves
							if food.has_method("reserve_for_waiter"):
								if not food.reserve_for_waiter(self):
									continue  # Failed to reserve, another waiter got it first

							# Found matching food and reserved it! Start delivery process
							print("[WAITER] Found ", food_data.get("type"), " for customer at table!")
							_assigned_customer = customer
							_current_order = customer_order
							_reserved_food = food  # Track the reserved food
							_set_state(State.MOVING_TO_COUNTER)

							# Move to serving counter
							var counter_pos := serving_counter.global_position + Vector3(1.0, 0, 0)
							counter_pos.y = 0.0
							_move_to(counter_pos)
							_open_doors_to_target(counter_pos)

							return true

	return false

func _find_customer_waiting_for_service() -> Customer:
	"""Find a customer at a table who is waiting for a waiter to take their order."""
	var customers := get_tree().get_nodes_in_group("customers")
	if customers.is_empty():
		# Fallback: search all Customer nodes
		var root := get_tree().current_scene
		customers = _find_all_customers(root)

	for customer in customers:
		if customer is Customer and is_instance_valid(customer):
			# Check if customer is waiting for waiter (State 1 = WAITING_FOR_WAITER)
			if customer.get_state() == 1:  # WAITING_FOR_WAITER
				# Check if another waiter is already assigned to this customer
				if customer.has_method("is_waiter_assigned") and customer.is_waiter_assigned():
					continue  # Skip this customer, another waiter is already serving them

				# Assign ourselves to this customer to prevent other waiters from taking them
				if customer.has_method("assign_waiter"):
					customer.assign_waiter(self)

				return customer

	return null

func _find_all_customers(node: Node) -> Array[Node]:
	"""Recursively find all Customer nodes."""
	var customers: Array[Node] = []
	if node is Customer:
		customers.append(node)
	for child in node.get_children():
		customers.append_array(_find_all_customers(child))
	return customers

func _find_serving_counter() -> Node3D:
	"""Find the serving counter in the scene."""
	var counters := get_tree().get_nodes_in_group("serving_counter")
	if counters.size() > 0:
		return counters[0]
	return null

func _find_order_counter() -> Node3D:
	"""DEPRECATED: Find the order counter in the scene."""
	var counters := get_tree().get_nodes_in_group("order_counter")
	if counters.size() > 0:
		return counters[0]
	return null

func _get_customer_at_counter(counter: Node3D) -> Customer:
	"""DEPRECATED: Get the customer currently at the counter."""
	if counter.has_method("get_current_customer"):
		return counter.get_current_customer()
	return null

func _take_customer_order() -> void:
	"""Take order from the customer at their table."""
	if not _assigned_customer or not is_instance_valid(_assigned_customer):
		_set_state(State.IDLE)
		return

	# Get the order from customer at table (await because it's a coroutine)
	var order := await _assigned_customer.take_order_at_table(self)
	if order.is_empty():
		_set_state(State.IDLE)
		return

	_current_order = order
	print("[WAITER] Took order from customer at table: ", _current_order.get("name", "Unknown"))

	# Emit signal
	order_taken.emit(self, _assigned_customer, _current_order)

	# Add order to HUD with table number
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("add_order_display"):
		var order_copy := _current_order.duplicate()
		order_copy["customer"] = _assigned_customer
		order_copy["table_number"] = _assigned_customer.get_assigned_table_number()
		hud.add_order_display(order_copy)

	# Clear waiter assignment from customer
	if _assigned_customer and _assigned_customer.has_method("clear_waiter_assignment"):
		_assigned_customer.clear_waiter_assignment()

	# Clear assignment and go back to IDLE to serve more customers
	# Don't wait at counter - let the waiter take more orders first!
	_assigned_customer = null
	_current_order = {}
	_set_state(State.IDLE)
	print("[WAITER] Order taken! Looking for more customers to serve...")

func _find_available_table() -> Node3D:
	"""Find an available table for the customer."""
	var tables := get_tree().get_nodes_in_group("table")
	for table in tables:
		if table.has_method("is_available") and table.is_available():
			return table
	return null

func _find_counter_position() -> void:
	"""Find the serving counter position to pick up food."""
	# Find a position near the serving counter where waiter can pick up food
	if _counter_reference:
		var wait_offset := _counter_reference.global_transform.basis * Vector3(0, 0, 1.5)
		_kitchen_position = _counter_reference.global_position + wait_offset
		_kitchen_position.y = 0.0
	else:
		# Fallback to idle position
		_kitchen_position = _idle_position
	print("[WAITER] Serving counter position set to: ", _kitchen_position)

func _check_for_food_pickup() -> void:
	"""Check for food items that match the current order nearby."""
	if _current_order.is_empty():
		return

	if _held_food:
		# Already holding food, deliver it
		_deliver_food_to_customer()
		return

	# First, check if food is on the serving counter (preferred method)
	var serving_counter := _find_serving_counter()
	if serving_counter and serving_counter.has_method("get_food_matching_order"):
		var counter_food: FoodItem = serving_counter.get_food_matching_order(_current_order)
		if counter_food and is_instance_valid(counter_food):
			print("[WAITER] Found matching food on counter!")
			# Pick up from counter
			if serving_counter.has_method("take_food"):
				serving_counter.take_food(counter_food)
			_pickup_food(counter_food)
			return

	# If not on counter, search for food items in range (fallback)
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = pickup_range
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 0b100000  # Layer 6: Food items

	var results := space_state.intersect_shape(query)

	for result in results:
		var collider = result.collider
		if collider and collider is FoodItem:
			var food_data: Dictionary = collider.get_food_data()
			if food_data.get("type") == _current_order.get("type"):
				# Check if food is cooked (state 2 = COOKED)
				if food_data.get("state", 0) == 2:
					_pickup_food(collider)
					return

func _pickup_food(food: FoodItem) -> void:
	"""Pick up a food item."""
	if not food or not is_instance_valid(food):
		return

	# Clear reservation since we're picking it up
	if food.has_method("unreserve"):
		food.unreserve()
	_reserved_food = null  # Clear our tracking

	_held_food = food
	print("[WAITER] Picked up food: ", _current_order.get("name", "Unknown"))

	# Mark customer's order as in delivery to prevent duplicate cooking
	if _assigned_customer and is_instance_valid(_assigned_customer):
		if _assigned_customer.has_method("set_food_in_delivery"):
			_assigned_customer.set_food_in_delivery(true)

	# Disable physics on food
	if food is RigidBody3D:
		food.freeze = true

	# Parent food to held item position
	if _held_item_position and food.get_parent():
		food.get_parent().remove_child(food)
		_held_item_position.add_child(food)
		food.position = Vector3.ZERO

	# Start delivering
	_deliver_food_to_customer()

func _deliver_food_to_customer() -> void:
	"""Deliver the held food to the customer's table."""
	if not _assigned_customer or not is_instance_valid(_assigned_customer):
		_set_state(State.IDLE)
		return

	var table := _assigned_customer.get_assigned_table()
	if not table:
		print("[WAITER] Customer has no table assigned!")
		_set_state(State.IDLE)
		return

	_set_state(State.DELIVERING_FOOD)

	# Move to table position
	var delivery_pos: Vector3
	if table.has_method("get_food_position"):
		delivery_pos = table.get_food_position()
	else:
		delivery_pos = table.global_position

	_move_to(delivery_pos)

func _place_food_at_table() -> void:
	"""Place the held food at the customer's table."""
	if not _held_food or not is_instance_valid(_held_food):
		_finish_delivery()
		return

	var table := _assigned_customer.get_assigned_table() if _assigned_customer else null
	if not table:
		_finish_delivery()
		return

	# Get food position on table
	var food_pos: Vector3
	if table.has_method("get_food_position"):
		food_pos = table.get_food_position()
	else:
		food_pos = table.global_position + Vector3(0, 1, 0)

	# Re-parent food to main scene
	if _held_item_position and _held_food.get_parent() == _held_item_position:
		_held_item_position.remove_child(_held_food)
		get_tree().root.add_child(_held_food)

	# Position food at table
	_held_food.global_position = food_pos

	# Re-enable physics
	if _held_food is RigidBody3D:
		_held_food.freeze = false

	print("[WAITER] Delivered food to customer at table")

	# Clear held food reference
	_held_food = null

	# Finish delivery
	_finish_delivery()

func _finish_delivery() -> void:
	"""Complete the delivery process."""
	food_delivered.emit(self, _assigned_customer)

	# Clear assignment
	_assigned_customer = null
	_current_order = {}

	# Don't return to idle position - go straight to IDLE state to look for more work
	_set_state(State.IDLE)
	print("[WAITER] Delivery complete! Looking for more customers to serve...")

func _update_movement(delta: float) -> void:
	"""Handle navigation movement."""
	if not _has_target:
		print("[WAITER MOVEMENT] No target, returning")
		return

	if not _agent:
		print("[WAITER MOVEMENT] No navigation agent!")
		return

	# Check for nearby doors and open them
	_check_and_open_nearby_doors()

	# Debug NavigationAgent state - DISABLED (too verbose)
	# if Engine.get_physics_frames() % 30 == 0:
	# 	print("[WAITER NAV STATE] is_navigation_finished: %s | is_target_reachable: %s | is_target_reached: %s" % [
	# 		_agent.is_navigation_finished(),
	# 		_agent.is_target_reachable(),
	# 		_agent.is_target_reached()
	# 	])

	# Check if we've reached the destination
	var distance_to_target := global_position.distance_to(_target_position)
	if distance_to_target < arrival_tolerance:
		print("[WAITER MOVEMENT] Reached target (distance: %.2f)" % distance_to_target)
		_finish_movement()
		return

	if _agent.is_navigation_finished():
		print("[WAITER MOVEMENT] Navigation finished")
		_finish_movement()
		return

	# Check if path is valid - but give navigation system time to compute
	# Don't check reachability immediately, give it a few frames
	if not _agent.is_target_reachable():
		# Only fail after we've been trying for a while
		# This prevents premature failures while navigation is computing
		if Engine.get_physics_frames() % 120 == 0:  # Check every 2 seconds
			print("[WAITER MOVEMENT] Target still unreachable after waiting! Target: %v | Current: %v" % [_target_position, global_position])
			print("[WAITER MOVEMENT] Attempting to re-open doors and recalculate path...")
			_open_doors_to_target(_target_position)
			# Try to reset the target to force recalculation
			if _agent:
				_agent.target_position = _target_position
		# Don't give up immediately, keep trying
		# return

	var next_position := _agent.get_next_path_position()
	var direction := (next_position - global_position).normalized()
	direction.y = 0.0

	var desired_velocity := direction * move_speed

	# Debug every 30 frames - DISABLED (too verbose)
	# if Engine.get_physics_frames() % 30 == 0:
	# 	print("[WAITER MOVEMENT] Next pos: %v | Dir: %v | Velocity: %v" % [
	# 		next_position,
	# 		direction,
	# 		desired_velocity
	# 	])

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
	"""Called when waiter reaches destination."""
	if not _has_target:
		return

	velocity = Vector3.ZERO
	_has_target = false

	match _state:
		State.MOVING_TO_TABLE:
			_set_state(State.TAKING_ORDER)
			_take_customer_order()

		State.MOVING_TO_COUNTER:
			_set_state(State.WAITING_FOR_FOOD)

		State.DELIVERING_FOOD:
			_place_food_at_table()

		State.RETURNING:
			_set_state(State.IDLE)

func _move_to(target_pos: Vector3) -> void:
	"""Direct the waiter to walk to a specific position."""
	_target_position = target_pos
	_target_position.y = global_position.y  # Keep same height
	_has_target = true

	print("[WAITER MOVE_TO] Setting target: %v | Distance: %.2f" % [
		_target_position,
		global_position.distance_to(_target_position)
	])

	if _agent:
		# Set target immediately, no need to wait for physics frame
		_agent.target_position = _target_position
		print("[WAITER MOVE_TO] NavigationAgent target set to: %v" % _agent.target_position)
		print("[WAITER MOVE_TO] Agent map: %s | Avoidance enabled: %s" % [
			_agent.get_navigation_map(),
			_agent.avoidance_enabled
		])

func _open_doors_to_target(target_pos: Vector3) -> void:
	"""Open all doors between waiter and target position."""
	var direction_to_target := (target_pos - global_position).normalized()

	# Search for all nearby doors
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 10.0  # Large radius to find all doors
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 0b10001  # Layers 1 and 5 (environment + interactables)

	var results := space_state.intersect_shape(query)

	for result in results:
		var collider = result.collider
		if collider and collider.has_meta("parent_door"):
			var door = collider.get_meta("parent_door")
			if door and door.has_method("open") and not door.is_open:
				var door_position: Vector3 = door.global_position
				var direction_to_door := (door_position - global_position).normalized()

				# Open doors that are in the direction of our target
				var dot := direction_to_target.dot(direction_to_door)
				if dot > 0.1:  # Door is in the general direction
					print("[WAITER] Pre-opening door: ", door.name, " (dot: %.2f)" % dot)
					door.open()

func _check_and_open_nearby_doors() -> void:
	"""Check for doors in the path and open them if closed."""
	if not _has_target:
		return

	# Calculate direction to target
	var direction_to_target := (_target_position - global_position).normalized()

	# Search for doors in front of the waiter
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.5  # Check nearby doors
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 0b10001  # Layers 1 and 5 (environment + interactables)

	var results := space_state.intersect_shape(query)

	for result in results:
		var collider = result.collider
		# Check if collider has a parent_door meta
		if collider and collider.has_meta("parent_door"):
			var door = collider.get_meta("parent_door")
			if door and door.has_method("open") and not door.is_open:
				# Only open doors that are in the path (between waiter and target)
				var door_position: Vector3 = door.global_position
				var direction_to_door := (door_position - global_position).normalized()

				# Check if door is in front of us (dot product > 0.5 means roughly same direction)
				var dot := direction_to_target.dot(direction_to_door)
				if dot > 0.3:  # Door is somewhat in the direction we're heading
					print("[WAITER] Opening door in path: ", door.name, " (dot: %.2f)" % dot)
					door.open()
					# Also try to find and open the opposite door (for double doors)
					_open_nearby_double_doors(door)

func _open_nearby_double_doors(opened_door: Node) -> void:
	"""Find and open doors near the opened door (for double door setups)."""
	if not opened_door:
		return

	# Find all Door nodes in the scene
	var all_doors := get_tree().get_nodes_in_group("doors")
	if all_doors.is_empty():
		# Fallback: search by class type
		var root := get_tree().current_scene
		all_doors = _find_all_doors(root)

	# Open doors that are very close to this one
	for door in all_doors:
		if door == opened_door or not is_instance_valid(door):
			continue
		if door.has_method("open") and not door.is_open:
			var distance: float = opened_door.global_position.distance_to(door.global_position)
			if distance < 2.0:  # Very close doors are likely part of double door
				print("[WAITER] Opening paired door: ", door.name)
				door.open()

func _find_all_doors(node: Node) -> Array[Node]:
	"""Recursively find all Door nodes."""
	var doors: Array[Node] = []
	if node is Door:
		doors.append(node)
	for child in node.get_children():
		doors.append_array(_find_all_doors(child))
	return doors

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	"""Handle NavigationAgent velocity computation."""
	# Preserve gravity (y component) while using navigation's horizontal velocity
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	# Keep the existing y velocity (gravity)
	move_and_slide()

func _on_nav_target_reached() -> void:
	"""Handle NavigationAgent target reached."""
	_finish_movement()

func _set_state(new_state: State) -> void:
	"""Change waiter state."""
	if _state == new_state:
		return

	_state = new_state
	state_changed.emit(self, _state)
	_update_status_display()

	# Reset timers when changing states
	if new_state == State.IDLE:
		_check_timer = 0.0
		_food_wait_timer = 0.0
		# Clear waiter assignment from customer when going idle (failure case)
		if _assigned_customer and _assigned_customer.has_method("clear_waiter_assignment"):
			_assigned_customer.clear_waiter_assignment()
		# Clear food reservation when going idle (failure case)
		if _reserved_food and is_instance_valid(_reserved_food) and _reserved_food.has_method("unreserve"):
			_reserved_food.unreserve()
			_reserved_food = null
	elif new_state == State.WAITING_FOR_FOOD:
		_food_wait_timer = 0.0
		_check_timer = 0.0

	print("[WAITER] State changed to: ", State.keys()[_state])

func _update_status_display() -> void:
	"""Update the status label text."""
	if not _status_label:
		return

	var status_text := ""
	match _state:
		State.IDLE:
			status_text = "💤"
		State.MOVING_TO_TABLE:
			status_text = "🚶"
		State.TAKING_ORDER:
			status_text = "📝"
		State.MOVING_TO_COUNTER:
			status_text = "🚶"
		State.WAITING_FOR_FOOD:
			status_text = "⏰"
		State.PICKING_UP_FOOD:
			status_text = "🍽️"
		State.DELIVERING_FOOD:
			status_text = "🏃"
		State.RETURNING:
			status_text = "🚶"

	_status_label.text = status_text

## Public methods

func get_state() -> State:
	"""Returns the waiter's current state."""
	return _state

func set_idle_position(pos: Vector3) -> void:
	"""Set the position where waiter should idle."""
	_idle_position = pos
