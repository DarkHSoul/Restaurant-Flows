extends CanvasLayer
class_name DailyReportUI

## Daily financial report shown at end of level/day

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var day_label: Label = $Panel/VBoxContainer/DayLabel
@onready var revenue_label: Label = $Panel/VBoxContainer/StatsContainer/RevenueLabel
@onready var expenses_label: Label = $Panel/VBoxContainer/StatsContainer/ExpensesLabel
@onready var profit_label: Label = $Panel/VBoxContainer/StatsContainer/ProfitLabel
@onready var orders_label: Label = $Panel/VBoxContainer/StatsContainer/OrdersLabel
@onready var avg_order_label: Label = $Panel/VBoxContainer/StatsContainer/AvgOrderLabel
@onready var expenses_breakdown: VBoxContainer = $Panel/VBoxContainer/ExpensesBreakdown
@onready var continue_button: Button = $Panel/VBoxContainer/ContinueButton

var economy_manager: EconomyManager

func _ready() -> void:
	var game_manager := GameManager.instance
	if game_manager:
		economy_manager = game_manager.economy_manager
		economy_manager.daily_report_ready.connect(_on_daily_report_ready)

	if continue_button:
		continue_button.pressed.connect(_on_continue_pressed)

	visible = false

func show_report(report: Dictionary) -> void:
	"""Display the daily report."""
	visible = true
	get_tree().paused = true

	if day_label:
		day_label.text = "Day %d Complete!" % report.get("day", 1)

	if revenue_label:
		revenue_label.text = "Total Revenue: $%.2f" % report.get("revenue", 0.0)

	if expenses_label:
		expenses_label.text = "Total Expenses: $%.2f" % report.get("expenses", 0.0)

	if profit_label:
		var profit: float = report.get("profit", 0.0)
		var color := Color.GREEN if profit >= 0 else Color.RED
		profit_label.add_theme_color_override("font_color", color)
		profit_label.text = "Net Profit: $%.2f" % profit

	if orders_label:
		orders_label.text = "Orders Completed: %d" % report.get("orders_completed", 0)

	if avg_order_label:
		avg_order_label.text = "Avg Order Value: $%.2f" % report.get("average_order_value", 0.0)

func _on_daily_report_ready(report: Dictionary) -> void:
	"""Called when economy manager emits daily report."""
	show_report(report)

func _on_continue_pressed() -> void:
	"""Called when continue button is pressed."""
	visible = false
	get_tree().paused = false
