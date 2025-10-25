extends Node3D
class_name OrderBoard

## Order display board for kitchen staff to see active orders

signal order_selected(order_data: Dictionary)

## Board properties
@export var max_displayed_orders: int = 5
@export var order_spacing: float = 0.3

## Internal state
var _active_orders: Array[Dictionary] = []
var _order_labels: Array[Label3D] = []

@onready var _board_visual: MeshInstance3D = $Visual
@onready var _orders_container: Node3D = $OrdersContainer

func _ready() -> void:
	_create_order_labels()

func add_order(customer: Node, order_data: Dictionary) -> void:
	"""Add a new order to the board."""
	if _active_orders.size() >= max_displayed_orders:
		push_warning("OrderBoard: Maximum orders reached!")
		return

	var order_entry := {
		"customer": customer,
		"order": order_data,
		"table_number": customer.get("assigned_table_number") if customer else 0,
		"timestamp": Time.get_ticks_msec()
	}

	_active_orders.append(order_entry)
	_update_display()

func remove_order(customer: Node) -> void:
	"""Remove an order from the board when completed."""
	for i in range(_active_orders.size() - 1, -1, -1):
		if _active_orders[i].customer == customer:
			_active_orders.remove_at(i)
			break

	_update_display()

func get_active_orders() -> Array[Dictionary]:
	"""Get list of all active orders."""
	return _active_orders.duplicate()

## Private methods

func _create_order_labels() -> void:
	"""Create Label3D nodes for displaying orders."""
	for i in range(max_displayed_orders):
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 24
		label.outline_size = 4
		label.modulate = Color.BLACK
		label.visible = false

		_orders_container.add_child(label)
		label.position = Vector3(0, -i * order_spacing, 0.1)
		_order_labels.append(label)

func _update_display() -> void:
	"""Update the visual display of all orders."""
	# Hide all labels first
	for label in _order_labels:
		label.visible = false

	# Show active orders
	for i in range(_active_orders.size()):
		if i >= _order_labels.size():
			break

		var order_entry := _active_orders[i]
		var label := _order_labels[i]

		var order_text := _format_order(order_entry)
		label.text = order_text
		label.visible = true

func _format_order(order_entry: Dictionary) -> String:
	"""Format order data into readable text."""
	var order: Dictionary = order_entry.get("order", {})
	var table_num: int = order_entry.get("table_number", 0)

	var item_name: String = order.get("type", "Unknown")
	var time_elapsed: int = (Time.get_ticks_msec() - order_entry.get("timestamp", 0)) / 1000

	return "Table %d: %s (%ds)" % [table_num, item_name, time_elapsed]

func _on_order_completed(_customer: Node, _order: Dictionary) -> void:
	"""Called when an order is completed."""
	# Order completion is handled by CustomerSpawner
	pass
