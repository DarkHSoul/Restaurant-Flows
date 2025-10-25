# Economy System Documentation

## Overview

The Restaurant Flows economy system provides a comprehensive financial management layer for the game, featuring money tracking, expenses, upgrades, and progression mechanics.

## Core Components

### 1. EconomyManager (Singleton)
**Location:** `src/systems/scripts/EconomyManager.gd`

The central manager for all economic activities in the game.

#### Key Features:
- **Money Management**: Track current money, revenue, and expenses
- **Ingredient Costs**: Automatic deduction when orders are prepared
- **Daily Expenses**: Rent, utilities, staff, and maintenance costs
- **Upgrade System**: 10 different upgrades to improve restaurant performance
- **Financial Reports**: Detailed daily and session-wide statistics

#### Starting Conditions:
- Starting money: **$500**
- Base rent: **$50/day**
- Base utilities: **$20/day**
- Base staff cost: **$30/day**

### 2. Integration Points

#### OrderManager Integration
- Automatically charges ingredient costs when orders are placed
- Applies price multipliers from upgrades
- Tracks revenue from completed orders
- Calculates profit per order (revenue - ingredient cost)

#### GameManager Integration
- Creates EconomyManager singleton on game start
- Applies spawn rate multipliers from upgrades to customer spawner
- Increases difficulty costs each level
- Resets economy when starting new game

#### GameHUD Integration
- Displays current money with profit indicator
- Shows today's profit in green (positive) or red (negative)
- Real-time updates during gameplay

## Ingredient Costs

Each food item has associated ingredient costs:

| Item | Cost |
|------|------|
| Pizza | $3.00 |
| Burger | $2.50 |
| Pasta | $2.00 |
| Salad | $1.50 |
| Soup | $1.80 |

**Note:** Costs are automatically deducted when orders are taken, before cooking begins.

## Upgrade System

### Available Upgrades

#### Station Upgrades
1. **Faster Oven** - $200
   - Reduces oven cooking time by 25%

2. **Faster Stove** - $200
   - Reduces stove cooking time by 25%

3. **Better Prep Station** - $150
   - Can prepare 2 items simultaneously

#### Capacity Upgrades
4. **Extra Oven** - $300
   - Adds another oven to the kitchen

5. **Extra Stove** - $300
   - Adds another stove to the kitchen

6. **Larger Restaurant** - $500
   - Increases table capacity by 2

#### Business Upgrades
7. **Premium Ingredients** - $400
   - Increases all food prices by 50%

8. **Marketing Campaign** - $250
   - Increases customer spawn rate by 30%

#### Cost Reduction Upgrades
9. **Efficient Kitchen** - $350
   - Reduces ingredient costs by 25%

10. **Solar Panels** - $600
    - Reduces utilities cost by 50%

### Using Upgrades

#### In Code:
```gdscript
# Purchase an upgrade
if EconomyManager.instance.purchase_upgrade("faster_oven"):
    print("Upgrade purchased!")

# Check if owned
if EconomyManager.instance.has_upgrade("premium_ingredients"):
    print("Using premium ingredients!")

# Get multipliers
var speed_mult = EconomyManager.instance.active_multipliers.cooking_speed
var price_mult = EconomyManager.instance.active_multipliers.price
```

#### In UI:
- Press **Tab** to open the Shop UI
- Browse available upgrades
- Click "Buy" on affordable upgrades
- Press **ESC** or click "Close" to exit

## Financial Tracking

### Daily Stats
- **Revenue Today**: Total money earned from orders
- **Expenses Today**: Total costs (ingredients + daily expenses)
- **Profit Today**: Revenue - Expenses
- **Orders Today**: Number of completed orders

### Session Stats
- **Total Revenue**: All-time earnings
- **Total Expenses**: All-time costs
- **Current Money**: Available cash
- **Game Day**: Current day number

### Accessing Stats

```gdscript
var stats = EconomyManager.instance.get_stats()
print("Money: $", stats.money)
print("Profit Today: $", stats.profit_today)
print("Orders: ", stats.orders_today)
```

## Daily Expenses

Expenses automatically increase with level progression:

```gdscript
# Base costs (Level 1)
Rent: $50
Utilities: $20
Staff: $30
Total: $100/day

# Level scaling
Rent: base_rent + (level × $10)
Utilities: base_utilities + (level × $5)
Staff: base_staff + (level × $8)
Maintenance: level × $3

# Example: Level 5
Rent: $50 + (5 × $10) = $100
Utilities: $20 + (5 × $5) = $45
Staff: $30 + (5 × $8) = $70
Maintenance: 5 × $3 = $15
Total: $230/day
```

## Profit Calculation

### Per Order:
```
Revenue = (base_price × quality × price_multiplier) + speed_bonus
Ingredient_Cost = base_cost × ingredient_cost_multiplier
Profit = Revenue - Ingredient_Cost
```

### Example:
```
Pizza Order (Perfect quality, fast service):
Base Price: $15
Quality: 1.0 (perfect)
Price Multiplier: 1.5 (premium ingredients)
Speed Bonus: $3 (served quickly)

Revenue: ($15 × 1.0 × 1.5) + $3 = $25.50
Ingredient Cost: $3 × 0.75 (efficient kitchen) = $2.25
Profit: $25.50 - $2.25 = $23.25
```

## UI Components

### 1. ShopUI
**Location:** `src/ui/ShopUI.gd` and `ShopUI.tscn`

- Toggle with **Tab** key
- Shows available upgrades
- Displays current money
- Color-coded affordability (green = can buy, gray = too expensive)

### 2. GameHUD Enhancements
**Location:** `src/ui/GameHUD.gd`

- Money display with profit indicator
- Green (+$X) for positive profit
- Red (+$X) for negative profit
- Real-time updates

### 3. DailyReportUI
**Location:** `src/ui/DailyReportUI.gd` and `DailyReportUI.tscn`

- Shows at end of each level/day
- Revenue breakdown
- Expense breakdown
- Net profit/loss
- Average order value

### 4. EconomyStatsUI
**Location:** `src/ui/EconomyStatsUI.gd`

- Real-time financial dashboard
- Day counter
- Revenue, expenses, profit tracking
- Orders completed today

## Signals

### EconomyManager Signals:

```gdscript
signal money_changed(new_amount: float, change: float)
# Emitted whenever money changes (positive or negative)

signal expense_paid(expense_type: String, amount: float)
# Emitted when an expense is paid

signal upgrade_purchased(upgrade_id: String, cost: float)
# Emitted when an upgrade is bought

signal daily_report_ready(report: Dictionary)
# Emitted at end of day with financial summary

signal bankruptcy()
# Emitted when player cannot afford daily expenses
```

### Usage Example:
```gdscript
func _ready():
    EconomyManager.instance.money_changed.connect(_on_money_changed)

func _on_money_changed(new_amount: float, change: float):
    if change > 0:
        print("Earned $", change)
    else:
        print("Spent $", abs(change))
```

## Game Balance

### Recommended Strategy:
1. **Early Game (Days 1-3)**
   - Focus on completing orders efficiently
   - Save money for first upgrades
   - Target: Faster Oven or Stove ($200)

2. **Mid Game (Days 4-7)**
   - Purchase Efficient Kitchen to reduce costs
   - Consider Premium Ingredients for higher revenue
   - Expand capacity with Extra stations

3. **Late Game (Day 8+)**
   - Solar Panels for long-term cost reduction
   - Larger Restaurant for more customers
   - Marketing Campaign for maximum throughput

### Break-Even Analysis:
- Minimum orders per day to break even (Level 1): ~10-12 orders
- Average profit per order: $8-15 (depending on item and quality)
- Daily expense burden increases ~$50 per level

## API Reference

### Key Methods:

```gdscript
# Money Management
EconomyManager.instance.add_money(amount: float, source: String)
EconomyManager.instance.subtract_money(amount: float, reason: String) -> bool
EconomyManager.instance.can_afford(amount: float) -> bool

# Pricing
EconomyManager.instance.get_modified_price(base_price: float) -> float
EconomyManager.instance.get_ingredient_cost(item_type: String) -> float
EconomyManager.instance.charge_ingredient_cost(item_type: String) -> float

# Upgrades
EconomyManager.instance.purchase_upgrade(upgrade_id: String) -> bool
EconomyManager.instance.has_upgrade(upgrade_id: String) -> bool
EconomyManager.instance.get_available_upgrades() -> Array[Dictionary]

# Reports
EconomyManager.instance.get_stats() -> Dictionary
EconomyManager.instance.get_daily_report() -> Dictionary
EconomyManager.instance.pay_daily_expenses() -> Dictionary

# Lifecycle
EconomyManager.instance.start_new_day()
EconomyManager.instance._reset_economy()
```

## Future Enhancements

Potential additions to the economy system:
- [ ] Loans and debt system
- [ ] Staff hiring/firing mechanics
- [ ] Seasonal price variations
- [ ] Special events (happy hour, etc.)
- [ ] Investment opportunities
- [ ] Franchise expansion
- [ ] Ingredient quality tiers
- [ ] Bulk purchasing discounts
- [ ] Dynamic pricing based on demand

## Troubleshooting

### Common Issues:

1. **Money not updating in UI**
   - Ensure GameHUD is connected to EconomyManager
   - Check that money_changed signal is being emitted

2. **Upgrades not working**
   - Verify multipliers are being applied correctly
   - Check that upgrade effects match expected types

3. **Negative profit**
   - Review ingredient costs vs. selling prices
   - Consider purchasing cost-reduction upgrades
   - Improve order quality to increase revenue

4. **Bankruptcy on level up**
   - Save enough money before completing levels
   - Daily expenses increase with each level
   - Aim for $200+ reserve before progression
