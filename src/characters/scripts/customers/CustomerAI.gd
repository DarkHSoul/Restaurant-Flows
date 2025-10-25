extends CharacterBody3D
class_name Customer

## Signals
signal destination_reached(customer: Customer, label: StringName)
signal state_changed(customer: Customer, new_state: State)
signal order_placed(customer: Customer, order: Dictionary)
signal order_received(customer: Customer)
signal satisfaction_changed(customer: Customer, satisfaction: float)
signal left_restaurant(customer: Customer, was_satisfied: bool)

## Customer states
enum State {
	ENTERING,            # Walking from entrance to table (DIRECT TO TABLE)
	WAITING_FOR_WAITER,  # Seated at table, waiting for waiter to take order
	ORDERING,            # Waiter is taking order at table
	WAITING_FOR_FOOD,    # Seated at table, waiting for food
	EATING,              # Eating the food
	LEAVING,             # Walking to exit
	LEFT                 # Has left the restaurant
}

## Movement parameters
@export_group("Movement")
@export var move_speed: float = 2.2
@export var acceleration: float = 8.0
@export var arrival_tolerance: float = 0.3

## Behavior parameters
@export_group("Behavior")
@export var patience: float = 120.0  # Seconds before customer gets angry
@export var order_delay: float = 5.0  # Seconds before placing order
@export var eating_duration: float = 2.0  # Seconds to eat food (quick eat and leave)

## Visual customization
@export_group("Appearance")
@export var customer_color: Color = Color.WHITE

## Internal state
var _state: State = State.ENTERING
var _current_label: StringName = &""
var _target_position: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _assigned_table: Node3D = null
var _assigned_counter: Node3D = null
var _assigned_waiter: Node = null  # Track which waiter is serving this customer
var _assigned_chef: Node = null  # Track which chef is cooking this order
var _food_in_delivery: bool = false  # Track if food is currently being delivered by waiter
var _current_order: Dictionary = {}
var _satisfaction: float = 100.0
var _wait_timer: float = 0.0
var _action_timer: float = 0.0
var _order_placed: bool = false
var _exit_position: Vector3 = Vector3.ZERO

## References
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: MeshInstance3D = $Visual
@onready var _speech_bubble: Node3D = $SpeechBubble
var _emotion_label: Label3D = null
var _order_label: Label3D = null

func _ready() -> void:
	# Add to customers group for easy finding
	add_to_group("customers")

	if _agent:
		_agent.velocity_computed.connect(_on_velocity_computed)
		_agent.target_reached.connect(_on_nav_target_reached)
		_agent.path_desired_distance = 0.5
		_agent.target_desired_distance = 0.5

	if _visual and _visual.mesh:
		var material := StandardMaterial3D.new()
		material.albedo_color = customer_color
		_visual.material_override = material

	_hide_speech_bubble()
	state_changed.emit(self, _state)

	# Create emotion label
	_create_emotion_label()

	# Create order label
	_create_order_label()

	# Wait for navigation to be ready
	call_deferred("_navigation_setup")

func _exit_tree() -> void:
	"""Clean up resources when customer is removed from scene."""
	# Disconnect signals to prevent memory leaks
	if _agent:
		if _agent.velocity_computed.is_connected(_on_velocity_computed):
			_agent.velocity_computed.disconnect(_on_velocity_computed)
		if _agent.target_reached.is_connected(_on_nav_target_reached):
			_agent.target_reached.disconnect(_on_nav_target_reached)

	# Clean up labels
	if is_instance_valid(_emotion_label):
		_emotion_label.queue_free()
		_emotion_label = null

	if is_instance_valid(_order_label):
		_order_label.queue_free()
		_order_label = null

	# Release table reference
	if _assigned_table and is_instance_valid(_assigned_table) and _assigned_table.has_method("release_table"):
		_assigned_table.release_table()

	_assigned_table = null
	_assigned_counter = null

func _create_emotion_label() -> void:
	"""Create a Label3D to show customer emotions."""
	_emotion_label = Label3D.new()
	_emotion_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_emotion_label.font_size = 64
	_emotion_label.outline_size = 8
	_emotion_label.modulate = Color.WHITE
	_emotion_label.outline_modulate = Color.BLACK
	_emotion_label.pixel_size = 0.005
	_emotion_label.position = Vector3(0, 2.5, 0)  # Emotion on top
	add_child(_emotion_label)
	_update_emotion_display()

func _create_order_label() -> void:
	"""Create a Label3D to show the order."""
	_order_label = Label3D.new()
	_order_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_order_label.font_size = 80
	_order_label.outline_size = 10
	_order_label.modulate = Color.WHITE
	_order_label.outline_modulate = Color.BLACK
	_order_label.pixel_size = 0.006
	_order_label.position = Vector3(0, 2.0, 0)  # Order below emotion
	_order_label.visible = false
	add_child(_order_label)

func _physics_process(delta: float) -> void:
	_update_patience(delta)
	_update_state_behavior(delta)

	match _state:
		State.ENTERING, State.LEAVING:
			_update_movement(delta)
		State.WAITING_FOR_WAITER, State.ORDERING:
			# Customer is seated at table
			velocity = Vector3.ZERO
		State.WAITING_FOR_FOOD:
			_check_for_nearby_food()
			velocity = Vector3.ZERO
		_:
			velocity = Vector3.ZERO

func _update_patience(delta: float) -> void:
	if _state in [State.WAITING_FOR_FOOD, State.WAITING_FOR_WAITER, State.ORDERING]:
		_wait_timer += delta
		var patience_loss := (100.0 / patience) * delta
		_change_satisfaction(-patience_loss)

		# Leave if too impatient
		if _satisfaction <= 0:
			leave_restaurant(false)

func _update_state_behavior(delta: float) -> void:
	match _state:
		State.ORDERING:
			# Customer is at counter, waiting for player to take order
			# Order will be taken when player interacts with counter
			pass

		State.EATING:
			_action_timer += delta
			if _action_timer >= eating_duration:
				leave_restaurant(true)

func _check_position_drift() -> void:
	"""Check if customer has drifted from their target position and correct it."""
	# Only correct position if we're not already moving
	if _has_target:
		return

	# If we don't have a target position stored, nothing to correct
	if _target_position == Vector3.ZERO:
		return

	# Check horizontal distance only (ignore Y axis)
	var current_pos_2d := Vector2(global_position.x, global_position.z)
	var target_pos_2d := Vector2(_target_position.x, _target_position.z)
	var distance := current_pos_2d.distance_to(target_pos_2d)

	# If drifted more than 0.5 units, return to position
	if distance > 0.5:
		print("[CUSTOMER] Drifted %.2f units from position, correcting..." % distance)
		_has_target = true
		if _agent:
			await get_tree().physics_frame
			_agent.target_position = _target_position

func _update_movement(delta: float) -> void:
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
	# Prevent duplicate calls
	if not _has_target:
		return

	velocity = Vector3.ZERO
	_has_target = false

	destination_reached.emit(self, _current_label)

	match _state:
		State.ENTERING:
			# Arrived at table directly
			_arrive_at_table()

		State.LEAVING:
			_exit_restaurant()

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()

func _on_nav_target_reached() -> void:
	_finish_movement()

## Public methods

func assign_counter(counter: Node3D) -> void:
	"""Assign the order counter to this customer."""
	_assigned_counter = counter

func set_exit_position(exit_pos: Vector3) -> void:
	"""Set the exit position for when customer leaves."""
	_exit_position = exit_pos

func take_order_at_table(_waiter: Node3D) -> Dictionary:
	"""Waiter takes customer's order at table. Returns order data."""
	if _state != State.WAITING_FOR_WAITER or _order_placed:
		return {}

	# Generate order when waiter arrives
	_current_order = _generate_order()

	_set_state(State.ORDERING)
	_show_order_bubble()

	# Mark order as placed
	_order_placed = true
	_wait_timer = 0.0
	order_placed.emit(self, _current_order)

	print("[CUSTOMER] Order taken by waiter: ", _current_order.get("name", "Unknown"))

	# After a brief moment, hide bubble and wait for food
	await get_tree().create_timer(2.0).timeout
	_hide_speech_bubble()
	_set_state(State.WAITING_FOR_FOOD)

	return _current_order.duplicate()

# Legacy methods for backwards compatibility (no longer used in new flow)
func move_to_counter_queue() -> void:
	"""DEPRECATED: Customer moves from entrance to counter queue."""
	# No longer used - customers go directly to tables
	pass

func arrive_at_counter() -> void:
	"""DEPRECATED: Customer reaches front of line at counter."""
	# No longer used - customers go directly to tables
	pass

func take_order_at_counter() -> Dictionary:
	"""DEPRECATED: Player takes customer's order at counter. Returns order data."""
	# No longer used - waiters take orders at tables
	return {}

func assign_table(table: Node3D) -> void:
	"""Assign a table to this customer and start moving to it."""
	if not table:
		return

	_assigned_table = table

	# Reserve the table immediately by marking it
	# This prevents other customers from being assigned to the same table
	if table.has_method("set") and "has_taken_order" in table:
		table.has_taken_order = true

	if table.has_method("get_customer_position"):
		move_to(table.get_customer_position(), &"table")
	else:
		move_to(table.global_position, &"table")

func move_to(target_pos: Vector3, label: StringName = &"") -> void:
	"""Direct the customer to walk to a specific position."""
	_target_position = target_pos
	_target_position.y = global_position.y
	_current_label = label
	_has_target = true

	if _agent:
		# Wait for the navigation map to be ready on next physics frame
		await get_tree().physics_frame
		_agent.target_position = _target_position


func leave_restaurant(was_satisfied: bool) -> void:
	"""Make the customer leave the restaurant."""
	if _state == State.LEAVING or _state == State.LEFT:
		return

	# Release table
	if _assigned_table and _assigned_table.has_method("release_table"):
		_assigned_table.release_table()

	_set_state(State.LEAVING)
	left_restaurant.emit(self, was_satisfied)

	# If customer is furious (satisfaction <= 0), teleport away immediately
	if _satisfaction <= 0:
		_exit_restaurant()
	else:
		# Use configured exit position, or default to forward
		var exit_pos := _exit_position if _exit_position != Vector3.ZERO else global_position + Vector3(0, 0, 10)
		move_to(exit_pos, &"exit")

func get_order() -> Dictionary:
	"""Returns the customer's current order."""
	return _current_order.duplicate()

func get_satisfaction() -> float:
	"""Returns current satisfaction level (0-100)."""
	return _satisfaction

func get_assigned_table() -> Node3D:
	"""Returns the assigned table."""
	return _assigned_table

func get_assigned_table_number() -> int:
	"""Returns the table number of assigned table."""
	if _assigned_table and _assigned_table.has_method("get_table_number"):
		return _assigned_table.get_table_number()
	return 0

func get_state() -> State:
	"""Returns the customer's current state."""
	return _state

func assign_waiter(waiter: Node) -> void:
	"""Assign a waiter to this customer (prevents multiple waiters from taking same order)."""
	_assigned_waiter = waiter

func get_assigned_waiter() -> Node:
	"""Get the waiter currently assigned to this customer."""
	return _assigned_waiter

func is_waiter_assigned() -> bool:
	"""Check if a waiter is already assigned to this customer."""
	return _assigned_waiter != null and is_instance_valid(_assigned_waiter)

func clear_waiter_assignment() -> void:
	"""Clear waiter assignment (after order is taken or waiter gives up)."""
	_assigned_waiter = null

func assign_chef(chef: Node) -> void:
	"""Assign a chef to cook this customer's order."""
	_assigned_chef = chef

func get_assigned_chef() -> Node:
	"""Get the chef currently cooking for this customer."""
	return _assigned_chef

func is_chef_assigned() -> bool:
	"""Check if a chef is already cooking for this customer."""
	return _assigned_chef != null and is_instance_valid(_assigned_chef)

func clear_chef_assignment() -> void:
	"""Clear chef assignment (after food is cooked or chef gives up)."""
	_assigned_chef = null

func set_food_in_delivery(in_delivery: bool) -> void:
	"""Mark that food is being delivered by a waiter."""
	_food_in_delivery = in_delivery

func is_food_in_delivery() -> bool:
	"""Check if food is currently being delivered."""
	return _food_in_delivery

## Private methods

func _navigation_setup() -> void:
	"""Called after navigation is ready."""
	# Navigation is now ready, wait one frame then customers can start moving
	await get_tree().physics_frame

func _arrive_at_table() -> void:
	"""Called when customer reaches their table."""
	# Sit down animation could go here
	if _assigned_table and _assigned_table.has_method("sit_customer"):
		var seated_successfully: bool = _assigned_table.sit_customer(self)
		if not seated_successfully:
			# Table is full, customer gets angry and leaves
			print("[CUSTOMER] Table %d is full! Customer leaving angry." % _assigned_table.get_table_number())
			_change_satisfaction(-50.0)
			leave_restaurant(false)
			return

	# Clear the reservation flag now that customer has arrived
	# Waiter will set it again when taking the order
	if _assigned_table and "has_taken_order" in _assigned_table:
		_assigned_table.has_taken_order = false

	# Customer is now seated and waiting for waiter to take order
	_set_state(State.WAITING_FOR_WAITER)
	_action_timer = 0.0
	print("[CUSTOMER] Seated at table, waiting for waiter to take order")

func _check_for_nearby_food() -> void:
	"""Check for food items near the table and pick them up."""
	if not _assigned_table:
		return

	if _state != State.WAITING_FOR_FOOD:
		return

	# Define search radius
	var search_radius: float = 2.0
	var table_position := _assigned_table.global_position

	# Get all physics bodies in range
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = search_radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), table_position)
	query.collision_mask = 0b100000  # Layer 6: Food items

	var results := space_state.intersect_shape(query)

	for result in results:
		var collider = result.collider
		if collider and collider is FoodItem:
			# Check if this food matches our order
			var food_data: Dictionary = collider.get_food_data()
			if food_data.get("type") == _current_order.get("type"):
				_pickup_food(collider)
				break

func _pickup_food(food: FoodItem) -> void:
	"""Pick up the food item and start eating."""
	if _state != State.WAITING_FOR_FOOD:
		return

	# Clear delivery flag - food has arrived!
	_food_in_delivery = false

	# Get food data before consuming
	var food_data: Dictionary = food.get_food_data()
	var food_state: int = food_data.get("state", 0)  # 0=RAW, 1=COOKING, 2=COOKED, 3=BURNT

	# Calculate service time
	var service_time := _wait_timer

	# Complete the order through OrderManager
	var game_manager := GameManager.instance
	if game_manager and game_manager.order_manager:
		var result := game_manager.order_manager.complete_order(_current_order, food_state, service_time)

		# Update satisfaction based on order quality
		if result.get("success", false):
			_change_satisfaction(20.0)  # Happy bonus for correct order
		else:
			_change_satisfaction(-30.0)  # Poor quality penalty

		# Bonus for fast service
		if result.get("bonus", 0.0) > 0:
			_change_satisfaction(10.0)

	# Check if it's the correct order type
	if food_data.get("type") == _current_order.get("type"):
		_change_satisfaction(10.0)  # Additional bonus for correct type
	else:
		_change_satisfaction(-20.0)  # Wrong order penalty

	# Remove food from scene
	if is_instance_valid(food):
		food.queue_free()

	# Start eating
	_set_state(State.EATING)
	_action_timer = 0.0
	_hide_speech_bubble()

	# Hide order label when food is received
	if _order_label:
		_order_label.visible = false

	order_received.emit(self)

func _generate_order() -> Dictionary:
	"""Generate a random food order."""
	# Get order from OrderManager to ensure icons match
	var order_manager := GameManager.instance.order_manager if GameManager.instance else null

	if order_manager:
		var item_type: String = order_manager.get_random_menu_item()
		var menu_item: Dictionary = order_manager.get_menu_item(item_type)

		return {
			"type": item_type,
			"drink": ["water", "soda", "juice", "coffee"][randi() % 4],
			"customer": self,
			"icon": menu_item.get("icon", "🍽️"),
			"name": menu_item.get("name", item_type.capitalize())
		}
	else:
		# Fallback if no order manager
		var menu_items: Array[String] = ["pizza", "burger", "pasta", "salad", "soup"]
		var icons: Dictionary = {"pizza": "🍕", "burger": "🍔", "pasta": "🍝", "salad": "🥗", "soup": "🍲"}
		var item_type: String = menu_items[randi() % menu_items.size()]

		return {
			"type": item_type,
			"drink": ["water", "soda", "juice", "coffee"][randi() % 4],
			"customer": self,
			"icon": icons.get(item_type, "🍽️"),
			"name": item_type.capitalize()
		}

func _exit_restaurant() -> void:
	"""Final cleanup when customer exits."""
	_set_state(State.LEFT)
	queue_free()

func _change_satisfaction(delta: float) -> void:
	"""Change satisfaction level."""
	_satisfaction = clamp(_satisfaction + delta, 0.0, 100.0)
	satisfaction_changed.emit(self, _satisfaction)
	_update_visual_mood()
	_update_emotion_display()

func _update_visual_mood() -> void:
	"""Update customer appearance based on satisfaction."""
	if not _visual:
		return

	var mood_color: Color
	if _satisfaction > 70:
		mood_color = Color.GREEN
	elif _satisfaction > 40:
		mood_color = Color.YELLOW
	else:
		mood_color = Color.RED

	if _visual.material_override:
		_visual.material_override.albedo_color = customer_color.lerp(mood_color, 0.3)

func _update_emotion_display() -> void:
	"""Update the emotion emoji based on satisfaction and state."""
	if not _emotion_label:
		return

	var emotion := ""
	match _state:
		State.WAITING_FOR_WAITER:
			if _satisfaction > 80:
				emotion = "😊"
			elif _satisfaction > 50:
				emotion = "🤔"
			else:
				emotion = "😠"
		State.ORDERING:
			emotion = "📝"
		State.WAITING_FOR_FOOD:
			if _satisfaction > 70:
				emotion = "🍽️"
			elif _satisfaction > 40:
				emotion = "⏰"
			else:
				emotion = "😤"
		State.EATING:
			emotion = "😋"
		State.LEAVING:
			if _satisfaction > 70:
				emotion = "😃"
			else:
				emotion = "😞"
		_:
			emotion = ""

	_emotion_label.text = emotion

func _show_order_bubble() -> void:
	"""Display order in speech bubble."""
	# Keep speech bubble hidden - we use dynamic labels instead
	if _speech_bubble:
		_speech_bubble.visible = false

	# Show order icon in dynamic order label
	if _order_label and not _current_order.is_empty():
		var icon: String = _current_order.get("icon", "🍽️")
		_order_label.text = icon
		_order_label.visible = true

func _hide_speech_bubble() -> void:
	"""Hide speech bubble."""
	if _speech_bubble:
		_speech_bubble.visible = false

	# Keep order label visible - only hide when food is received

func _set_state(new_state: State) -> void:
	"""Change customer state."""
	if _state == new_state:
		return

	_state = new_state
	state_changed.emit(self, _state)
	_update_emotion_display()
