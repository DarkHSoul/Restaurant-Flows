extends Node
class_name EconomyManager

## Comprehensive economy system for the restaurant game
## Handles money, expenses, upgrades, and financial tracking

## Signals
signal money_changed(new_amount: float, change: float)
signal expense_paid(expense_type: String, amount: float)
signal upgrade_purchased(upgrade_id: String, cost: float)
signal daily_report_ready(report: Dictionary)
signal bankruptcy()

## Current financial state
var current_money: float = 500.0  # Starting money
var total_revenue: float = 0.0
var total_expenses: float = 0.0
var daily_profit: float = 0.0

## Expense tracking
@export_group("Daily Expenses")
@export var base_rent: float = 50.0
@export var base_utilities: float = 20.0
@export var base_staff_cost: float = 30.0

var rent_cost: float = 50.0
var utilities_cost: float = 20.0
var staff_cost: float = 30.0
var maintenance_cost: float = 0.0

## Ingredient costs (per order)
const INGREDIENT_COSTS := {
	"pizza": 3.0,
	"burger": 2.5,
	"pasta": 2.0,
	"salad": 1.5,
	"soup": 1.8
}

## Upgrade system
const UPGRADES := {
	"faster_oven": {
		"name": "Faster Oven",
		"description": "Reduces oven cooking time by 25%",
		"cost": 200.0,
		"type": "station",
		"station_type": "oven",
		"effect": {"cooking_speed": 1.25}
	},
	"faster_stove": {
		"name": "Faster Stove",
		"description": "Reduces stove cooking time by 25%",
		"cost": 200.0,
		"type": "station",
		"station_type": "stove",
		"effect": {"cooking_speed": 1.25}
	},
	"better_prep_station": {
		"name": "Better Prep Station",
		"description": "Can prepare 2 items at once",
		"cost": 150.0,
		"type": "station",
		"station_type": "prep",
		"effect": {"max_items": 2}
	},
	"extra_oven": {
		"name": "Extra Oven",
		"description": "Adds another oven to the kitchen",
		"cost": 300.0,
		"type": "new_station",
		"station_type": "oven",
		"prefab": "res://src/environment/scenes/Oven.tscn"
	},
	"extra_stove": {
		"name": "Extra Stove",
		"description": "Adds another stove to the kitchen",
		"cost": 300.0,
		"type": "new_station",
		"station_type": "stove",
		"prefab": "res://src/environment/scenes/Stove.tscn"
	},
	"larger_restaurant": {
		"name": "Larger Restaurant",
		"description": "Increases table capacity by 2",
		"cost": 500.0,
		"type": "capacity",
		"effect": {"tables": 2}
	},
	"premium_ingredients": {
		"name": "Premium Ingredients",
		"description": "Increases food prices by 50%",
		"cost": 400.0,
		"type": "pricing",
		"effect": {"price_multiplier": 1.5}
	},
	"marketing_campaign": {
		"name": "Marketing Campaign",
		"description": "Increases customer spawn rate by 30%",
		"cost": 250.0,
		"type": "customer",
		"effect": {"spawn_rate": 1.3}
	},
	"efficient_kitchen": {
		"name": "Efficient Kitchen",
		"description": "Reduces all ingredient costs by 25%",
		"cost": 350.0,
		"type": "cost_reduction",
		"effect": {"ingredient_cost_multiplier": 0.75}
	},
	"solar_panels": {
		"name": "Solar Panels",
		"description": "Reduces utilities cost by 50%",
		"cost": 600.0,
		"type": "cost_reduction",
		"effect": {"utilities_multiplier": 0.5}
	}
}

## Owned upgrades
var owned_upgrades: Array[String] = []
var active_multipliers := {
	"price": 1.0,
	"ingredient_cost": 1.0,
	"cooking_speed": 1.0,
	"spawn_rate": 1.0,
	"utilities": 1.0
}

## Daily tracking
var game_day: int = 1
var orders_today: int = 0
var revenue_today: float = 0.0
var expenses_today: float = 0.0

## Singleton
static var instance: EconomyManager

func _ready() -> void:
	if instance and instance != self:
		queue_free()
		return

	instance = self
	_reset_economy()

## Public Interface

func add_money(amount: float, source: String = "unknown") -> void:
	"""Add money to the player's balance."""
	current_money += amount
	total_revenue += amount
	revenue_today += amount
	daily_profit += amount

	money_changed.emit(current_money, amount)

	# Track as revenue
	if source == "order":
		orders_today += 1

func subtract_money(amount: float, reason: String = "expense") -> bool:
	"""Subtract money from the player's balance. Returns false if insufficient funds."""
	if current_money < amount:
		return false

	current_money -= amount
	total_expenses += amount
	expenses_today += amount
	daily_profit -= amount

	money_changed.emit(current_money, -amount)
	expense_paid.emit(reason, amount)

	return true

func charge_ingredient_cost(item_type: String) -> float:
	"""Charge the cost of ingredients for an order."""
	var base_cost: float = INGREDIENT_COSTS.get(item_type, 2.0)
	var final_cost: float = base_cost * active_multipliers.ingredient_cost

	subtract_money(final_cost, "ingredients")
	return final_cost

func get_modified_price(base_price: float) -> float:
	"""Get the modified price based on upgrades."""
	return base_price * active_multipliers.price

func pay_daily_expenses() -> Dictionary:
	"""Pay daily operating expenses. Returns expense breakdown."""
	var expenses := {
		"rent": rent_cost,
		"utilities": utilities_cost * active_multipliers.utilities,
		"staff": staff_cost,
		"maintenance": maintenance_cost,
		"total": 0.0,
		"success": true
	}

	expenses.total = expenses.rent + expenses.utilities + expenses.staff + expenses.maintenance

	# Try to pay expenses
	if subtract_money(expenses.total, "daily_expenses"):
		expenses.success = true
	else:
		expenses.success = false
		# Bankruptcy!
		bankruptcy.emit()

	return expenses

func can_afford(amount: float) -> bool:
	"""Check if player can afford something."""
	return current_money >= amount

func purchase_upgrade(upgrade_id: String) -> bool:
	"""Purchase an upgrade. Returns true if successful."""
	if upgrade_id in owned_upgrades:
		return false  # Already owned

	var upgrade: Dictionary = UPGRADES.get(upgrade_id, {})
	if upgrade.is_empty():
		return false

	var cost: float = upgrade.get("cost", 0.0)
	if not can_afford(cost):
		return false

	if not subtract_money(cost, "upgrade"):
		return false

	# Apply upgrade
	owned_upgrades.append(upgrade_id)
	_apply_upgrade_effects(upgrade_id, upgrade)

	upgrade_purchased.emit(upgrade_id, cost)
	return true

func has_upgrade(upgrade_id: String) -> bool:
	"""Check if player owns an upgrade."""
	return upgrade_id in owned_upgrades

func get_available_upgrades() -> Array[Dictionary]:
	"""Get list of available (not owned) upgrades."""
	var available: Array[Dictionary] = []

	for upgrade_id in UPGRADES.keys():
		if upgrade_id not in owned_upgrades:
			var upgrade: Dictionary = UPGRADES[upgrade_id].duplicate()
			upgrade["id"] = upgrade_id
			available.append(upgrade)

	return available

func get_daily_report() -> Dictionary:
	"""Generate a daily financial report."""
	var report := {
		"day": game_day,
		"revenue": revenue_today,
		"expenses": expenses_today,
		"profit": revenue_today - expenses_today,
		"orders_completed": orders_today,
		"average_order_value": revenue_today / max(orders_today, 1),
		"current_money": current_money
	}

	return report

func start_new_day() -> void:
	"""Reset daily tracking and increment day counter."""
	game_day += 1
	revenue_today = 0.0
	expenses_today = 0.0
	orders_today = 0

	# Pay daily expenses
	var _expenses := pay_daily_expenses()

	# Emit daily report
	var report := get_daily_report()
	daily_report_ready.emit(report)

func get_stats() -> Dictionary:
	"""Get comprehensive economy stats."""
	return {
		"money": current_money,
		"total_revenue": total_revenue,
		"total_expenses": total_expenses,
		"daily_profit": daily_profit,
		"game_day": game_day,
		"owned_upgrades": owned_upgrades.size(),
		"revenue_today": revenue_today,
		"expenses_today": expenses_today,
		"orders_today": orders_today,
		"multipliers": active_multipliers.duplicate()
	}

func get_ingredient_cost(item_type: String) -> float:
	"""Get the cost of ingredients for an item type."""
	var base_cost: float = INGREDIENT_COSTS.get(item_type, 2.0)
	return base_cost * active_multipliers.ingredient_cost

## Private Methods

func _reset_economy() -> void:
	"""Reset economy to starting state."""
	current_money = 500.0
	total_revenue = 0.0
	total_expenses = 0.0
	daily_profit = 0.0
	game_day = 1
	orders_today = 0
	revenue_today = 0.0
	expenses_today = 0.0
	owned_upgrades.clear()

	# Reset costs
	rent_cost = base_rent
	utilities_cost = base_utilities
	staff_cost = base_staff_cost
	maintenance_cost = 0.0

	# Reset multipliers
	active_multipliers = {
		"price": 1.0,
		"ingredient_cost": 1.0,
		"cooking_speed": 1.0,
		"spawn_rate": 1.0,
		"utilities": 1.0
	}

func _apply_upgrade_effects(_upgrade_id: String, upgrade: Dictionary) -> void:
	"""Apply the effects of an upgrade."""
	var effect: Dictionary = upgrade.get("effect", {})

	# Apply multipliers
	if "price_multiplier" in effect:
		active_multipliers.price *= effect.price_multiplier

	if "ingredient_cost_multiplier" in effect:
		active_multipliers.ingredient_cost *= effect.ingredient_cost_multiplier

	if "cooking_speed" in effect:
		active_multipliers.cooking_speed *= effect.cooking_speed

	if "spawn_rate" in effect:
		active_multipliers.spawn_rate *= effect.spawn_rate

	if "utilities_multiplier" in effect:
		active_multipliers.utilities *= effect.utilities_multiplier

func _increase_difficulty_costs(level: int) -> void:
	"""Increase costs based on level progression."""
	rent_cost = base_rent + (level * 10.0)
	utilities_cost = base_utilities + (level * 5.0)
	staff_cost = base_staff_cost + (level * 8.0)
	maintenance_cost = level * 3.0
