extends Control
class_name EconomyStatsUI

## UI panel showing detailed economy statistics

@onready var revenue_label: Label = $VBoxContainer/RevenueLabel
@onready var expenses_label: Label = $VBoxContainer/ExpensesLabel
@onready var profit_label: Label = $VBoxContainer/ProfitLabel
@onready var day_label: Label = $VBoxContainer/DayLabel
@onready var orders_label: Label = $VBoxContainer/OrdersLabel

var economy_manager: EconomyManager
var order_manager: OrderManager

func _ready() -> void:
	var game_manager := GameManager.instance
	if game_manager:
		economy_manager = game_manager.economy_manager
		order_manager = game_manager.order_manager

func _process(_delta: float) -> void:
	_update_stats()

func _update_stats() -> void:
	"""Update the stats display."""
	if not economy_manager:
		return

	var stats := economy_manager.get_stats()

	if day_label:
		day_label.text = "Day %d" % stats.game_day

	if revenue_label:
		revenue_label.text = "Revenue: $%.2f" % stats.revenue_today

	if expenses_label:
		expenses_label.text = "Expenses: $%.2f" % stats.expenses_today

	if profit_label:
		var profit: float = float(stats.revenue_today) - float(stats.expenses_today)
		var color := Color.GREEN if profit >= 0 else Color.RED
		profit_label.add_theme_color_override("font_color", color)
		profit_label.text = "Profit: $%.2f" % profit

	if orders_label:
		orders_label.text = "Orders: %d" % stats.orders_today
