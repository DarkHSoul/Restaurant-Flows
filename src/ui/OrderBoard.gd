extends Node3D
class_name OrderBoard

## Order display board for kitchen staff to see active orders

signal order_selected(order_data: Dictionary)

## Board properties
@export var max_displayed_orders: int = 5
@export var order_spacing: float = 0.3

## Internal state
var _active_orders: Array[Dictionary] = []
var _order_labels: Array[Label] = []
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.5  # Update every 0.5 seconds

var _customer_spawner: CustomerSpawner = null

# SubViewport UI elements
var _viewport: SubViewport = null
var _ui_container: VBoxContainer = null

@onready var _board_visual: MeshInstance3D = $Visual
@onready var _orders_container: Node3D = $OrdersContainer

func _ready() -> void:
	_create_viewport_ui()
	_create_order_labels()

	# Find CustomerSpawner
	await get_tree().process_frame
	_customer_spawner = get_tree().get_first_node_in_group("customer_spawner") as CustomerSpawner

	if not _customer_spawner:
		push_warning("OrderBoard: CustomerSpawner not found!")

func _process(delta: float) -> void:
	# Periodically sync with CustomerSpawner's active orders
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_sync_with_spawner()
		_update_timer = 0.0

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

func _create_viewport_ui() -> void:
	"""Create SubViewport with 2D UI for the board."""
	# Create SubViewport with higher resolution
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(2048, 1536)  # Higher res for better text quality
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	# Create background panel for better visibility
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(2048, 1536)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.95)  # Dark semi-transparent background
	style.border_color = Color(0.8, 0.6, 0.2, 1)  # Gold border
	style.border_width_left = 8
	style.border_width_right = 8
	style.border_width_top = 8
	style.border_width_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	_viewport.add_child(panel)

	# Create margin container for proper padding
	var margin := MarginContainer.new()
	margin.custom_minimum_size = Vector2(2048, 1536)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	_viewport.add_child(margin)

	# Create UI container inside margin
	_ui_container = VBoxContainer.new()
	_ui_container.custom_minimum_size = Vector2(1928, 1416)  # Viewport size minus margins
	_ui_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ui_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui_container.add_theme_constant_override("separation", 30)
	margin.add_child(_ui_container)

	# Create header label
	var header := Label.new()
	header.text = "ACTIVE ORDERS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.clip_text = false
	header.custom_minimum_size = Vector2(1928, 200)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_font_size_override("font_size", 120)
	header.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 1))  # Gold color
	header.add_theme_color_override("font_outline_color", Color.BLACK)
	header.add_theme_constant_override("outline_size", 12)
	_ui_container.add_child(header)

	# Apply viewport texture to board
	var viewport_texture := _viewport.get_texture()
	var material := StandardMaterial3D.new()
	material.albedo_texture = viewport_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_board_visual.material_override = material

func _create_order_labels() -> void:
	"""Create 2D Label nodes for displaying orders in the viewport."""
	if not _ui_container:
		return

	for i in range(max_displayed_orders):
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 90)  # Much larger font
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 10)
		label.visible = false

		_ui_container.add_child(label)
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
	var icon: String = order.get("icon", "🍽️")
	var status: String = order.get("status", "pending")

	# Get status emoji and text
	var status_text: String = ""
	match status:
		"pending":
			status_text = "📋 Pending"
		"cooking":
			status_text = "🍳 Cooking"
		"ready":
			status_text = "✅ Ready"
		"delivering":
			status_text = "🚶 Delivering"
		_:
			status_text = "📋 Pending"

	return "%s Table %d: %s - %s" % [icon, table_num, item_name.capitalize(), status_text]

func _sync_with_spawner() -> void:
	"""Sync active orders with CustomerSpawner."""
	if not _customer_spawner:
		return

	# Get current orders from spawner
	var spawner_orders := _customer_spawner.get_active_orders()

	# Clear current orders
	_active_orders.clear()

	# Add each order from spawner
	for order in spawner_orders:
		var customer = order.get("customer")
		var table_number = 0
		if customer and customer.has_method("get_assigned_table_number"):
			table_number = customer.get_assigned_table_number()

		var order_entry := {
			"customer": customer,
			"order": order,
			"table_number": table_number,
			"timestamp": Time.get_ticks_msec()  # We don't have original timestamp, use current
		}
		_active_orders.append(order_entry)

	# Update visual display
	_update_display()

func _on_order_completed(_customer: Node, _order: Dictionary) -> void:
	"""Called when an order is completed."""
	# Order completion is handled by CustomerSpawner
	pass
