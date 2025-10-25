extends StaticBody3D
class_name WindowCounter

## Window counter where customers place orders from the dining area

## Signals
signal customer_arrived_at_counter(customer: Customer)
signal order_taken_at_counter(customer: Customer, order: Dictionary)
signal customer_left_counter(customer: Customer)

## Counter properties
@export_group("Queue Settings")
@export var queue_spacing: float = 1.5  # Space between customers in line (increased to prevent collision)
@export var max_queue_size: int = 10
@export var queue_direction: Vector3 = Vector3(0, 0, 1)  # Direction line extends

## Visual feedback
@export_group("Visual")
@export var counter_color: Color = Color(0.4, 0.25, 0.15)
@export var highlight_color: Color = Color.YELLOW

## Internal state
var _queued_customers: Array[Customer] = []
var _customer_at_counter: Customer = null
var _is_highlighted: bool = false

@onready var _visual: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null

func _ready() -> void:
	collision_layer = 0b10000  # Layer 4: Interactables
	collision_mask = 0

## Public interface

func can_interact() -> bool:
	"""Check if player can interact with counter."""
	return _customer_at_counter != null and _customer_at_counter.has_method("get_order")

func interact(player: Node3D) -> void:
	"""Player takes order from customer at counter."""
	if not _customer_at_counter:
		return

	# Take the customer's order
	var order: Dictionary = {}
	if _customer_at_counter.has_method("take_order_at_counter"):
		order = _customer_at_counter.take_order_at_counter()

	if not order.is_empty():
		# Emit signal
		order_taken_at_counter.emit(_customer_at_counter, order)

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

	# If counter is empty and queue is empty, send customer directly to counter
	if not _customer_at_counter and _queued_customers.is_empty():
		print("[QUEUE] Counter is empty, sending customer directly to counter")
		_customer_at_counter = customer

		# Connect to know when they arrive at counter
		if not customer.destination_reached.is_connected(_on_customer_reached_counter):
			customer.destination_reached.connect(_on_customer_reached_counter)

		# Move directly to counter position
		customer.move_to(get_order_position(), &"counter")
		return true

	# Otherwise, add to queue
	_queued_customers.append(customer)

	# Customer walks to their position in queue
	var queue_index := _queued_customers.size() - 1
	var queue_pos := get_queue_position(queue_index)
	print("[QUEUE] Adding customer to queue at index %d, position: %v" % [queue_index, queue_pos])
	customer.move_to(queue_pos, &"queue_line")

	# Connect to customer's destination_reached signal to know when they arrive
	if not customer.destination_reached.is_connected(_on_customer_reached_queue_position):
		customer.destination_reached.connect(_on_customer_reached_queue_position)

	return true

func get_queue_position(index: int) -> Vector3:
	"""Get world position for a specific queue index."""
	# Queue forms on the dining area side (customer side) of the counter
	# Counter is at the dividing wall between kitchen (west/negative X) and dining (east/positive X)
	# Customers should queue on the EAST/dining side (+X in world space)
	# The counter's local Z axis points in world +X direction
	var world_queue_dir := global_transform.basis * queue_direction.normalized()  # Queue extends along Z
	# Start queue further from counter to prevent collision with customer at counter (2.5 units instead of 1.5)
	var customer_side_offset := global_transform.basis * Vector3(0, 0, 2.5)  # Local +Z = World +X (dining side)
	var base_position := global_position + customer_side_offset
	return base_position + (world_queue_dir * queue_spacing * index)

func get_order_position() -> Vector3:
	"""Get the position where customer stands to order."""
	# Customer stands on the dining area side (east/+X in world) of counter
	# Counter's local +Z points to world +X (dining area)
	var offset := global_transform.basis * Vector3(0, 0, 1.0)  # Local +Z = World +X
	return global_position + offset

func get_queue_count() -> int:
	"""Get number of customers in queue (not including one at counter)."""
	return _queued_customers.size()

func is_queue_full() -> bool:
	"""Check if queue has reached max capacity."""
	return _queued_customers.size() >= max_queue_size

func get_current_customer() -> Customer:
	"""Get the customer currently at the counter."""
	return _customer_at_counter

## Private methods

func _advance_queue() -> void:
	"""Move next customer in queue to counter position."""
	print("[QUEUE] Advancing queue. Current queue size: %d" % _queued_customers.size())

	if _queued_customers.is_empty():
		_customer_at_counter = null
		print("[QUEUE] Queue is empty, no customer at counter")
		return

	# Get first customer in queue
	_customer_at_counter = _queued_customers.pop_front()
	print("[QUEUE] Moving customer from queue to counter. Remaining in queue: %d" % _queued_customers.size())

	# Move them to counter - they'll transition to ORDERING when they arrive
	if _customer_at_counter and is_instance_valid(_customer_at_counter):
		# Disconnect from queue position signal to avoid conflicts
		if _customer_at_counter.destination_reached.is_connected(_on_customer_reached_queue_position):
			_customer_at_counter.destination_reached.disconnect(_on_customer_reached_queue_position)

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
	print("[QUEUE] Updating %d customer positions" % _queued_customers.size())
	for i in range(_queued_customers.size()):
		var customer := _queued_customers[i]
		if customer and is_instance_valid(customer):
			var new_pos := get_queue_position(i)
			print("[QUEUE]   Customer %d moving to position: %v" % [i, new_pos])
			# Force customer to move to their new queue position
			customer.move_to(new_pos, &"queue_line")

func _update_visual() -> void:
	"""Update visual appearance based on state."""
	if not _visual:
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = counter_color
	material.metallic = 0.0
	material.roughness = 0.7

	if _is_highlighted:
		material.emission_enabled = true
		material.emission = highlight_color
		material.emission_energy = 0.3

	_visual.material_override = material

func _on_customer_reached_queue_position(customer: Customer, label: StringName) -> void:
	"""Called when a customer reaches their position in the queue."""
	# Only care about queue arrivals
	if label != &"queue_line":
		return

	print("[QUEUE] Customer reached queue position. Customer at counter: %s, Queue size: %d" % [str(_customer_at_counter != null), _queued_customers.size()])

	# If they're first in queue and no one at counter, advance them
	if not _customer_at_counter and _queued_customers.size() > 0 and _queued_customers[0] == customer:
		print("[QUEUE] First customer in queue, advancing to counter")
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
