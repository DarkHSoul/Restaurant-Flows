extends CanvasLayer
class_name GameHUD

## In-game HUD showing money, time, orders, etc.

@onready var money_label: RichTextLabel = $MarginContainer/VBoxContainer/TopBar/MoneyLabel
@onready var time_label: Label = $MarginContainer/VBoxContainer/TopBar/TimeLabel
@onready var reputation_bar: ProgressBar = $MarginContainer/VBoxContainer/TopBar/ReputationBar
@onready var orders_panel: PanelContainer = $MarginContainer/VBoxContainer/OrdersPanel
@onready var orders_panel_content: VBoxContainer = $MarginContainer/VBoxContainer/OrdersPanel/VBoxContainer
@onready var orders_container: VBoxContainer = $MarginContainer/VBoxContainer/OrdersPanel/VBoxContainer/ScrollContainer/OrdersList
@onready var orders_label: Label = $MarginContainer/VBoxContainer/OrdersPanel/VBoxContainer/HeaderBar/Label
@onready var toggle_button: Button = $MarginContainer/VBoxContainer/OrdersPanel/VBoxContainer/HeaderBar/ToggleButton
@onready var held_item_label: RichTextLabel = $MarginContainer/VBoxContainer/BottomBar/HeldItemLabel

var orders_visible: bool = false

var game_manager: GameManager
var order_manager: OrderManager
var economy_manager: EconomyManager
var player: PlayerController

func _ready() -> void:
	# Find managers
	game_manager = GameManager.instance
	if game_manager:
		order_manager = game_manager.order_manager
		economy_manager = game_manager.economy_manager

	# Find player
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

	# Connect toggle button
	if toggle_button:
		toggle_button.pressed.connect(_on_toggle_button_pressed)

	# Start with orders panel hidden
	_set_orders_visibility(false)

func _process(_delta: float) -> void:
	_update_hud()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_orders"):
		_toggle_orders_panel()

func _update_hud() -> void:
	"""Update all HUD elements."""
	if order_manager:
		var stats := order_manager.get_stats()

		# Money with profit indicator
		if money_label:
			var money: float = stats.get("money", 0.0)
			var profit_today: float = stats.get("profit_today", 0.0)
			var profit_color: String = ""

			if profit_today > 0:
				profit_color = "[color=green]"
			elif profit_today < 0:
				profit_color = "[color=red]"

			# Display current money and today's profit
			money_label.text = "$%.2f %s(+$%.2f)[/color]" % [money, profit_color, abs(profit_today)]

		# Reputation
		if reputation_bar:
			reputation_bar.value = stats.get("reputation", 100.0)

	# Time
	if game_manager and time_label:
		var remaining := game_manager.get_remaining_time()
		var minutes: int = int(remaining) / 60
		var seconds := int(remaining) % 60
		time_label.text = "%02d:%02d" % [minutes, seconds]

	# Held item
	if player and held_item_label:
		var held: Node3D = player.get_held_item()
		if held and held.has_method("get_food_data"):
			var data: Dictionary = held.get_food_data()
			held_item_label.text = "Holding: %s" % data.get("name", "Item")
		else:
			held_item_label.text = ""

	# Update order statuses
	_update_all_order_statuses()

func _update_all_order_statuses() -> void:
	"""Update status of all displayed orders."""
	if not orders_container:
		return

	# Get all active customers to update their order statuses
	var customers := get_tree().get_nodes_in_group("customers")
	for customer in customers:
		if is_instance_valid(customer) and customer.has_method("get_order"):
			var order: Dictionary = customer.get_order()
			if not order.is_empty() and order.has("status"):
				update_order_status(order, order.get("status", "pending"))

func add_order_display(order: Dictionary) -> void:
	"""Add an order to the display with enhanced visuals."""
	if not orders_container:
		return

	var order_panel := PanelContainer.new()
	order_panel.name = "Order_%s" % order.get("customer", {}).get_instance_id()

	# Add custom styling to the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.3, 0.6, 1.0, 1.0)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	order_panel.add_theme_stylebox_override("panel", style)

	# Create horizontal container for better layout
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	order_panel.add_child(hbox)

	# Order icon
	var icon_label := Label.new()
	icon_label.text = order.get("icon", "🍽️")
	icon_label.add_theme_font_size_override("font_size", 32)
	hbox.add_child(icon_label)

	# Order details (vertical)
	var vbox := VBoxContainer.new()
	hbox.add_child(vbox)

	# Food type
	var food_label := Label.new()
	food_label.text = order.get("type", "Unknown").capitalize()
	food_label.add_theme_font_size_override("font_size", 22)
	food_label.add_theme_color_override("font_color", Color(1, 1, 0.8))
	vbox.add_child(food_label)

	# Table number
	var table_label := Label.new()
	table_label.text = "Table #%d" % order.get("table_number", 0)
	table_label.add_theme_font_size_override("font_size", 16)
	table_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(table_label)

	# Status indicator (right side)
	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "📋 Pending"
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(status_label)

	orders_container.add_child(order_panel)

func remove_order_display(order: Dictionary) -> void:
	"""Remove an order from the display."""
	if not orders_container:
		return

	var order_name := "Order_%s" % order.get("customer", {}).get_instance_id()
	var order_node := orders_container.get_node_or_null(order_name)

	if order_node:
		order_node.queue_free()

func update_order_status(order: Dictionary, status: String) -> void:
	"""Update the status of an order display.
	Status can be: 'pending', 'cooking', 'ready', 'delivering'
	"""
	if not orders_container:
		return

	var order_name := "Order_%s" % order.get("customer", {}).get_instance_id()
	var order_node := orders_container.get_node_or_null(order_name)

	if not order_node:
		return

	# Find the status label
	var hbox = order_node.get_child(0) if order_node.get_child_count() > 0 else null
	if not hbox:
		return

	var status_label: Label = hbox.get_node_or_null("StatusLabel")
	if not status_label:
		return

	# Update status text and color
	match status:
		"pending":
			status_label.text = "📋 Pending"
			status_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
		"cooking":
			status_label.text = "🍳 Cooking"
			status_label.add_theme_color_override("font_color", Color(1, 0.6, 0.2))
		"ready":
			status_label.text = "✅ Ready"
			status_label.add_theme_color_override("font_color", Color(0.2, 1, 0.3))
		"delivering":
			status_label.text = "🚶 Delivering"
			status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))

func _toggle_orders_panel() -> void:
	"""Toggle the orders panel visibility."""
	_set_orders_visibility(not orders_visible)

func _on_toggle_button_pressed() -> void:
	"""Called when toggle button is pressed."""
	_toggle_orders_panel()

func _set_orders_visibility(show_orders: bool) -> void:
	"""Set the orders panel visibility."""
	orders_visible = show_orders

	# Hide/show the orders list container
	if orders_container:
		orders_container.visible = show_orders

	# Hide/show the "Active Orders:" label
	if orders_label:
		orders_label.visible = show_orders

	# Adjust panel size flags to collapse when hidden
	if orders_panel:
		if show_orders:
			orders_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		else:
			orders_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	if toggle_button:
		toggle_button.text = "Hide" if show_orders else "Show"
