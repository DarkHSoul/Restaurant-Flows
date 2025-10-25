extends Node
class_name OrderManager

## Global order and menu management system

## Signals
signal order_completed(order: Dictionary, quality: float)
signal money_earned(amount: float)

## Menu definition
const MENU := {
	"pizza": {
		"name": "Pizza",
		"price": 15.0,
		"cooking_time": 20.0,
		"requires_prep": true,
		"station_type": "oven",
		"icon": "🍕"
	},
	"burger": {
		"name": "Burger",
		"price": 12.0,
		"cooking_time": 12.0,
		"requires_prep": true,
		"station_type": "stove",
		"icon": "🍔"
	},
	"pasta": {
		"name": "Pasta",
		"price": 14.0,
		"cooking_time": 15.0,
		"requires_prep": true,
		"station_type": "stove",
		"icon": "🍝"
	},
	"salad": {
		"name": "Salad",
		"price": 8.0,
		"cooking_time": 0.0,
		"requires_prep": true,
		"station_type": "prep",
		"icon": "🥗"
	},
	"soup": {
		"name": "Soup",
		"price": 10.0,
		"cooking_time": 18.0,
		"requires_prep": false,
		"station_type": "stove",
		"icon": "🍲"
	}
}

## Game state
var total_orders_completed: int = 0
var total_orders_failed: int = 0
var current_reputation: float = 100.0

## Reference to economy manager
var economy_manager: EconomyManager

func get_menu_item(item_type: String) -> Dictionary:
	"""Get menu item information."""
	if item_type in MENU:
		return MENU[item_type].duplicate()
	return {}

func get_random_menu_item() -> String:
	"""Get random menu item type."""
	var keys := MENU.keys()
	return keys[randi() % keys.size()]

func complete_order(order: Dictionary, food_state: int, service_time: float) -> Dictionary:
	"""Process a completed order and calculate rewards."""
	var result := {
		"success": false,
		"money": 0.0,
		"quality": 0.0,
		"bonus": 0.0,
		"ingredient_cost": 0.0,
		"profit": 0.0
	}

	var item_type: String = order.get("type", "")
	var menu_item: Dictionary = get_menu_item(item_type)

	if menu_item.is_empty():
		return result

	var base_price: float = menu_item.get("price", 10.0)

	# Apply economy manager price multiplier if available
	if economy_manager:
		base_price = economy_manager.get_modified_price(base_price)
		# Charge ingredient cost
		result.ingredient_cost = economy_manager.charge_ingredient_cost(item_type)

	var quality: float = 1.0

	# Check food state (0=RAW, 1=COOKING, 2=COOKED, 3=BURNT)
	if food_state == 2:  # COOKED
		quality = 1.0
		result.success = true
	elif food_state == 3:  # BURNT
		quality = 0.3
		current_reputation -= 5.0
	else:  # RAW or COOKING
		quality = 0.5
		current_reputation -= 3.0

	# Speed bonus
	var expected_time: float = menu_item.get("cooking_time", 15.0) + 20.0  # + service time
	if service_time < expected_time * 0.7:
		quality += 0.2
		result.bonus = base_price * 0.2

	# Calculate money
	result.money = base_price * quality + result.bonus
	result.quality = quality
	result.profit = result.money - result.ingredient_cost

	# Update stats
	if economy_manager:
		economy_manager.add_money(result.money, "order")

	if result.success:
		total_orders_completed += 1
		current_reputation = min(current_reputation + 2.0, 100.0)
	else:
		total_orders_failed += 1

	order_completed.emit(order, quality)
	money_earned.emit(result.money)

	return result

func get_stats() -> Dictionary:
	"""Get current game statistics."""
	var stats := {
		"orders_completed": total_orders_completed,
		"orders_failed": total_orders_failed,
		"reputation": current_reputation
	}

	# Include economy stats if available
	if economy_manager:
		var econ_stats := economy_manager.get_stats()
		stats["money"] = econ_stats.money
		stats["revenue_today"] = econ_stats.revenue_today
		stats["expenses_today"] = econ_stats.expenses_today
		stats["profit_today"] = econ_stats.revenue_today - econ_stats.expenses_today
	else:
		stats["money"] = 0.0

	return stats
