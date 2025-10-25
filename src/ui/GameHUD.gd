extends CanvasLayer
class_name GameHUD

## In-game HUD showing money, time, orders, etc.

@onready var money_label: Label = $MarginContainer/VBoxContainer/TopBar/MoneyLabel
@onready var time_label: Label = $MarginContainer/VBoxContainer/TopBar/TimeLabel
@onready var reputation_bar: ProgressBar = $MarginContainer/VBoxContainer/TopBar/ReputationBar
@onready var shop_button: Button = $MarginContainer/VBoxContainer/TopBar/ShopButton
@onready var orders_panel: PanelContainer = $MarginContainer/VBoxContainer/OrdersPanel
@onready var orders_panel_content: VBoxContainer = $MarginContainer/VBoxContainer/OrdersPanel/VBoxContainer
@onready var orders_container: VBoxContainer = $MarginContainer/VBoxContainer/OrdersPanel/VBoxContainer/ScrollContainer/OrdersList
@onready var orders_label: Label = $MarginContainer/VBoxContainer/OrdersPanel/VBoxContainer/HeaderBar/Label
@onready var toggle_button: Button = $MarginContainer/VBoxContainer/OrdersPanel/VBoxContainer/HeaderBar/ToggleButton
@onready var held_item_label: Label = $MarginContainer/VBoxContainer/BottomBar/HeldItemLabel

var orders_visible: bool = false

var game_manager: GameManager
var order_manager: OrderManager
var economy_manager: EconomyManager
var player: PlayerController
var shop_ui: ShopUI

func _ready() -> void:
	# Find managers
	game_manager = GameManager.instance
	if game_manager:
		order_manager = game_manager.order_manager
		economy_manager = game_manager.economy_manager

	# Find player
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	shop_ui = get_tree().get_first_node_in_group("shop_ui") as ShopUI

	# Connect toggle button
	if toggle_button:
		toggle_button.pressed.connect(_on_toggle_button_pressed)

	if shop_button:
		shop_button.pressed.connect(_on_shop_button_pressed)
		if not shop_ui:
			push_warning("ShopUI node not found; shop button will retry to locate it when pressed.")

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

func add_order_display(order: Dictionary) -> void:
	"""Add an order to the display."""
	if not orders_container:
		return

	var order_panel := PanelContainer.new()
	order_panel.name = "Order_%s" % order.get("customer", {}).get_instance_id()

	var order_label := Label.new()
	order_label.text = "  %s  %s  (Table #%d)" % [
		order.get("icon", "🍽️"),
		order.get("type", "Unknown").capitalize(),
		order.get("table_number", 0)
	]
	order_label.add_theme_font_size_override("font_size", 24)
	order_label.add_theme_color_override("font_color", Color(1, 1, 1))

	order_panel.add_child(order_label)
	orders_container.add_child(order_panel)

func remove_order_display(order: Dictionary) -> void:
	"""Remove an order from the display."""
	if not orders_container:
		return

	var order_name := "Order_%s" % order.get("customer", {}).get_instance_id()
	var order_node := orders_container.get_node_or_null(order_name)

	if order_node:
		order_node.queue_free()

func _toggle_orders_panel() -> void:
	"""Toggle the orders panel visibility."""
	_set_orders_visibility(not orders_visible)

func _on_toggle_button_pressed() -> void:
	"""Called when toggle button is pressed."""
	_toggle_orders_panel()

func _on_shop_button_pressed() -> void:
	"""Called when the shop button is pressed."""
	if not shop_ui:
		shop_ui = get_tree().get_first_node_in_group("shop_ui") as ShopUI
		if not shop_ui:
			push_warning("ShopUI node still missing; cannot open shop.")
			return

	if shop_ui:
		shop_ui.show_shop()

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
