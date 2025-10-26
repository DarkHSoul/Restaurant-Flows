# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Restaurant Flows** is a 3D restaurant management game built with **Godot 4.5**. Players cook food, serve customers, and manage a restaurant in first-person 3D. The game uses Godot's Forward Plus renderer and features customer AI with pathfinding, a cooking system with timers, and progression mechanics.

## Development Commands

### Running the Project
- Use the Godot MCP tools available in this environment:
  - `mcp__godot__run_project` - Run the game (main scene: `res://src/main/scenes/Main3D.tscn`)
  - `mcp__godot__launch_editor` - Launch Godot editor for visual editing
  - `mcp__godot__get_debug_output` - View runtime errors and debug output
  - `mcp__godot__stop_project` - Stop the running game
  - **IMPORTANT**: When you add something or fix the game, always run and debug the game to ensure it opens correctly and fix any issues before proceeding.

### Project Info & Debugging
- `mcp__godot__get_project_info` - Get project metadata and configuration
- `mcp__godot__get_godot_version` - Check installed Godot version (should be 4.5)
- `mcp__godot__get_debug_output` - Monitor runtime errors in real-time during development

### Testing & Debugging
- Use debug spawn keys:
  - **F7** - Spawn test customer (spawns at entrance, assigns table automatically)
  - **F6** - Spawn waiter (spawns at designated spawn point)
  - **F10** - Spawn chef (changed from F8 to avoid conflict with Godot editor stop)
- Toggle shop UI with **Tab** key to test economy system
- Use **ESC** for pause menu functionality testing
- Press **H** to toggle tutorial overlay (shows controls and tips)
- Monitor customer satisfaction with emotion labels above customers (😊, 🤔, 😠, 📝, 🍽️, ⏰, 😤, 😋, 😃, 😞)
- View customer orders with order emoji labels below emotion (🍕, 🍔, 🍝, 🥗, 🍲)
- Use `mcp__godot__get_debug_output` to track cooking timer issues and order validation errors
- Hold **E** on customers to take orders (requires 1.5s hold, shows progress bar)

## Architecture

### Core Game Loop
The game operates through a signal-driven event system:
1. **GameManager** (singleton) controls game state and level progression
2. **CustomerSpawner** spawns customers at intervals, assigns tables directly on spawn, manages active orders
3. **Customer** entities use state machines (ENTERING → WAITING_FOR_WAITER → ORDERING → WAITING_FOR_FOOD → EATING → LEAVING)
4. **Waiter** NPCs automatically detect customers, take orders, and deliver food to tables
5. **WaiterSpawner** manages waiter creation and assignment to customers
6. **ChefAI** NPCs automatically detect pending orders, cook food, and place on serving counter
7. **ChefSpawner** manages chef creation and assignment to orders
8. **OrderManager** (singleton) handles menu, pricing, order completion, and reputation
9. **EconomyManager** (singleton) manages money, expenses, upgrades, and financial tracking
10. **Player** can actively participate: pick up ingredients, cook food, place on serving counter alongside AI chefs
11. **CookingStation** base class handles food placement, cooking timers, and state changes
12. **TrashBin** allows disposal of incorrect or burnt food items
13. **ServingCounter** acts as intermediary between kitchen and dining area for food pickup

### Key Signals Architecture
- **Customer signals**: `order_placed`, `order_received`, `left_restaurant`, `satisfaction_changed`, `reached_table`, `started_eating`
- **Waiter signals**: `order_taken`, `food_delivered`, `state_changed`
- **Chef signals**: `order_started`, `food_cooked`, `food_delivered_to_counter`
- **Station signals**: `food_placed`, `food_removed`, `cooking_started`, `cooking_finished`
- **GameManager signals**: `game_started`, `level_completed`, `game_over`
- **OrderManager signals**: `order_completed`, `money_earned`, `order_cancelled`
- **EconomyManager signals**: `money_changed`, `expense_paid`, `upgrade_purchased`, `daily_report_ready`, `bankruptcy`
- **ChefSpawner signals**: `chef_spawned`, `chef_assigned_to_order`
- **WaiterSpawner signals**: `waiter_spawned`, `waiter_assigned`, `all_orders_taken`

### Physics Layers (Godot 3D)
- Layer 1: Environment (static collision)
- Layer 2: Player
- Layer 3: Customers (NavigationAgent3D pathfinding)
- Layer 4: Interactables (stations, tables)
- Layer 5: Food items

### Input Actions (project.godot)
- WASD: movement (move_forward, move_backward, move_left, move_right)
- Shift: sprint
- E: interact (hold for customer orders, instant for stations/doors)
- Left Click: pickup/drop food items
- ESC: pause (ui_cancel)
- Tab: toggle shop UI (toggle_orders)
- H: toggle tutorial help overlay
- F7: manual debug spawn customer (via _input in CustomerSpawner)
- F6: manual debug spawn waiter
- F10: manual debug spawn chef

### Player Interaction System
The player can actively help in the restaurant by cooking and preparing food:

**Picking Up Food:**
- Look at food items (they highlight when in range)
- **Left Click** to pick up food
- Food items have proper collision layers (Layer 6) for raycast detection
- Player can hold one item at a time in their hands

**Cooking Workflow:**
1. **Pick up raw ingredient** from storage/spawn area
2. **Approach cooking station** (Oven, Stove, or Prep Counter)
3. **Press E** to place food on station
   - Stations check for active orders before accepting food
   - Manual stations require another **E press** to start cooking
   - Auto-cook stations start cooking immediately
4. **Wait for cooking** - visual feedback shows cooking progress
5. **Press E again** to pick up cooked food
6. **Place cooked food on Serving Counter** for waiters to deliver

**Station Types:**
- **Oven** (Pizza, 20s): auto_cook = true
- **Stove** (Burger, Pasta, Soup): auto_cook = true
- **Prep Counter** (Salad): auto_cook = false (requires manual activation)
- **Serving Counter**: Accepts only cooked food, no cooking happens here

**Player vs AI Chefs:**
- Player and AI chefs work in parallel
- Both can place food on stations and pick up cooked food
- Order validation system prevents duplicate cooking
- Chefs bypass order validation (they've already claimed the order)
- Player must have active customer orders to place food

**Hold-to-Interact System:**
- Player can manually take orders from customers
- Hold **E** key for 1.5 seconds while looking at a customer
- Circular progress bar shows interaction progress (InteractionProgressBar UI)
- Progress decays 2x speed when released (prevents accidental interactions)
- Only customers in WAITING_FOR_WAITER state can have orders taken
- Completing interaction triggers Customer.interact() and places order
- Other interactions (stations, doors) use instant interaction

**Tutorial System:**
- Press **H** to toggle tutorial overlay at any time
- Shows comprehensive control list and gameplay tips
- Auto-fades after 15 seconds on first launch
- Can be re-shown anytime with H key
- Displays in top-left corner with semi-transparent background

## Code Patterns

### State Machines
Customer and Waiter AI use explicit state enums and match statements:

**Customer States** (CustomerAI.gd):
```gdscript
enum State {
    ENTERING,            # 0: Moving to assigned table
    WAITING_FOR_WAITER,  # 1: Seated, waiting for waiter
    ORDERING,            # 2: Waiter taking order
    WAITING_FOR_FOOD,    # 3: Order placed, waiting for food delivery
    EATING,              # 4: Received food, eating
    LEAVING              # 5: Finished, leaving restaurant
}
func _set_state(new_state: State) -> void:
    state_changed.emit(self, _state)
```

**Waiter States** (WaiterAI.gd):
```gdscript
enum State {
    IDLE,              # Standing idle, looking for customers or food
    MOVING_TO_TABLE,   # Walking to customer's table
    TAKING_ORDER,      # Taking order from customer at table
    MOVING_TO_COUNTER, # Walking to serving counter to pick up food
    WAITING_FOR_FOOD,  # Waiting at counter for food to be ready
    DELIVERING_FOOD    # Walking to customer's table with food
}
```

**Chef States** (ChefAI.gd):
```gdscript
enum State {
    IDLE,              # Standing idle, looking for orders
    MOVING_TO_STATION, # Walking to cooking station
    COOKING,           # Cooking food at station
    MOVING_TO_COUNTER, # Walking to serving counter with cooked food
    PLACING_FOOD       # Placing food on serving counter
}
```

### Class Names and Typing
All core classes use `class_name` for type safety:
- `class_name GameManager extends Node`
- `class_name Customer extends CharacterBody3D` (CustomerAI.gd)
- `class_name Waiter extends CharacterBody3D` (WaiterAI.gd)
- `class_name Chef extends CharacterBody3D` (ChefAI.gd)
- `class_name CookingStation extends StaticBody3D`
- `class_name FoodItem extends RigidBody3D`
- `class_name Table extends StaticBody3D`
- `class_name ServingCounter extends StaticBody3D`
- `class_name TrashBin extends StaticBody3D`

### Inheritance Pattern
CookingStation is a base class extended by Oven, Stove, PrepCounter. Override `_can_accept_food(food: FoodItem) -> bool` for station-specific food type filtering.

### Navigation
Customers use `NavigationAgent3D` for pathfinding. The agent's `velocity_computed` signal drives movement with collision avoidance.

### Singleton Pattern
GameManager, OrderManager, and EconomyManager are accessed globally:
```gdscript
static var instance: GameManager
func _ready() -> void:
    if instance and instance != self:
        queue_free()
```

### Order Validation System
Cooking stations check for active orders before accepting food:
- Stations call `_has_active_order_for_food()` to validate placement
- Only allows cooking if there are pending orders for that food type
- Prevents waste and ensures efficient kitchen workflow
- CustomerSpawner maintains `active_orders` list for order tracking
- Stations belong to "cooking_stations" group for system-wide order validation

### UI System Architecture
The UI system uses a layered approach with real-time data binding:
- **GameHUD**: Main game interface with money display and profit indicators
- **ShopUI**: Tab-toggleable upgrade shop with economy integration
- **DailyReportUI**: End-of-day financial summary with revenue breakdown
- **OrderBoard**: Active order tracking display showing pending customer orders
- **EconomyStatsUI**: Real-time economic statistics and performance metrics
- **InteractionProgressBar**: Circular progress bar for hold-to-interact actions (1.5s fill time, decays when released)
- **TutorialOverlay**: H-key toggleable help overlay showing controls and tips (auto-hides after 15s)
- **CookingProgressBar**: 3D Label3D progress bars above cooking stations (shows visual bar + percentage)
  - Displays while food is cooking on stations
  - Color-coded: Yellow (0-30%), Orange (30-70%), Green (70-100%)
  - Format: [████████░░] 80%
  - Billboard-enabled, always faces camera
- All UI components connect to singleton managers via signals for real-time updates
- UI responds to economy events (money changes, expenses, upgrades)

### Audio and Particle Systems
The game features integrated audio feedback and visual particle effects:

**AudioManager (Singleton)**:
- Global audio manager at `src/systems/scripts/AudioManager.gd`
- Manages sound effects with pooled AudioStreamPlayer instances
- Supports both 2D and 3D positioned audio
- Audio settings: Master (100%), Music (70%), SFX (80%)
- Sound files location: `assets/audio/sfx/` (supports .wav, .ogg, .mp3)
- Max 16 simultaneous sound effects via player pool

**Sound Effects Implemented** (⚠️ Audio code ready, files need to be added to `assets/audio/sfx/`):
- **order_ding** - Plays when customer order is taken (3D positioned)
- **customer_happy** - Plays when satisfaction >70% and increases (3D positioned)
- **customer_neutral** - Plays when satisfaction 30-60% and decreases (3D positioned)
- **customer_angry** - Plays when satisfaction <30% and decreases (3D positioned)
- **cooking_oven** - Looping sound for oven cooking (pizza)
- **cooking_sizzle** - Looping sound for stove cooking (burger, pasta, soup)
- **cooking_chop** - Looping sound for prep counter (salad)
- **cooking_generic** - Fallback looping cooking sound
- See `assets/audio/AUDIO_SETUP.md` for audio file requirements and sources

**Particle Effects**:
- **Steam Particles** (CookingStation):
  - GPUParticles3D system on all cooking stations
  - Activates when cooking starts, deactivates when cooking stops
  - White/blue-tinted steam rising from food position
  - 20 particles, 2-second lifetime, sphere emission

- **Satisfaction Stars** (Customer):
  - GPUParticles3D system on each customer
  - One-shot burst effect when satisfaction increases >5 points and >70%
  - 8 yellow/gold star particles with upward burst
  - 1.5-second lifetime with gravity and fade-out

**Audio Integration**:
- Sounds trigger on significant game events (orders, satisfaction changes, cooking)
- 3D positioned sounds use inverse distance attenuation
- Cooking sounds loop seamlessly during cooking process
- All audio is non-blocking and managed by AudioManager singleton

**Adding New Audio**:
1. Place audio files in `assets/audio/sfx/` (supports .wav, .ogg, .mp3)
2. Call `AudioManager.instance.play_sfx(sound_name)` for 2D sounds
3. Call `AudioManager.instance.play_sfx_3d(sound_name, position)` for 3D sounds
4. For looping sounds, use AudioStreamPlayer3D directly and set loop mode
5. See `assets/audio/AUDIO_SETUP.md` for complete audio setup guide and free sound resources

**Audio Status**:
- ✅ AudioManager singleton implemented and working
- ✅ All audio hooks integrated into game systems
- ✅ 3D spatial audio with distance attenuation
- ⚠️ Audio files need to be added (game will show warnings but continue working)

## File Organization

### Script-Scene Separation
- **Scenes** (.tscn): `/src/{category}/scenes/`
- **Scripts** (.gd): `/src/{category}/scripts/`

Example: Player3D.tscn → PlayerController.gd

### Categories
- `src/characters/` - Player, Customer, Waiter, and Chef scenes/scripts
  - `scripts/customers/` - CustomerAI.gd (main AI), Customer.gd (redirect for compatibility)
  - `scripts/player/` - PlayerController.gd
  - `scripts/waiter/` - WaiterAI.gd
  - `scripts/chef/` - ChefAI.gd
- `src/environment/` - Tables, cooking stations, counters, and restaurant props
  - CookingStation, Stove, Oven, PrepCounter, Table, Door, TrashBin, ServingCounter
- `src/systems/` - Game systems (GameManager, OrderManager, CustomerSpawner, WaiterSpawner, ChefSpawner, FoodItem)
- `src/ui/` - HUD, menus, and UI components
  - GameHUD, ShopUI, OrderBoard, DailyReportUI, EconomyStatsUI, InteractionProgressBar, TutorialOverlay
- `src/main/` - Main scene entry point (Main3D.tscn)
- `assets/audio/` - Audio files and documentation
  - `sfx/` - Sound effect files (.wav, .ogg, .mp3)
  - `AUDIO_SETUP.md` - Audio requirements and setup guide

## Important Constants

### Menu System (OrderManager.gd)
Menu items defined in `MENU` const with: `name`, `price`, `cooking_time`, `requires_prep`, `station_type`, `icon`
- Pizza: $15, 20s cooking, requires prep, oven
- Burger: $12, 12s cooking, requires prep, stove
- Pasta: $14, 15s cooking, requires prep, stove
- Salad: $8, no cooking, requires prep, prep counter
- Soup: $10, 18s cooking, no prep, stove

### Economy System (EconomyManager.gd)
- **Starting money**: $500
- **Daily expenses**: Rent $50, Utilities $20, Staff $30 (Level 1)
- **Ingredient costs**: Pizza $3, Burger $2.5, Pasta $2, Salad $1.5, Soup $1.8
- **Level scaling**: Rent +$10/level, Utilities +$5/level, Staff +$8/level

### Cooking States (FoodItem.gd expected states)
- 0: RAW
- 1: COOKING
- 2: COOKED (perfect)
- 3: BURNT

### Timing Parameters
- **Customer patience**: 120 seconds default (CustomerAI.gd:32)
- **Order delay**: 5 seconds before customer orders (CustomerAI.gd:33)
- **Eating duration**: 2.0 seconds (CustomerAI.gd:34) - quick eat and leave
- **Level time limit**: 300 seconds (5 min), decreases by 20s per level (GameManager.gd:24)
- **Pizza cooking time**: 20 seconds
- **Burger cooking time**: 12 seconds
- **Pasta cooking time**: 15 seconds
- **Soup cooking time**: 18 seconds
- **Customer spawn intervals**: Vary by level, modified by upgrades

## Adding New Content

### New Food Item
1. Create scene inheriting FoodItem (RigidBody3D)
2. Set `food_type` export var
3. Add to OrderManager.MENU dictionary with price, cooking_time, station_type
4. Add ingredient cost to EconomyManager.INGREDIENT_COSTS
5. Place spawner in storage area of Main3D.tscn

### New Cooking Station
1. Extend CookingStation class
2. Override `_can_accept_food(food: FoodItem) -> bool` for food filtering
3. Set `station_type`, `can_cook`, `max_items`, `auto_cook` export vars
4. Create scene with required child nodes: Visual (MeshInstance3D), FoodPosition (Marker3D), CookingLight (OmniLight3D)

### New Economy Upgrade
1. Add upgrade definition to EconomyManager.UPGRADES dictionary
2. Include cost, type, and effect properties
3. Handle upgrade logic in `_apply_upgrade_effects()` method
4. Add UI representation in ShopUI.gd
5. Example upgrade types: faster_cooking, more_tables, better_ingredients, hire_waiter, larger_kitchen

### Adjusting Game Difficulty
- **Customer spawn rate**: CustomerSpawner.spawn_interval_min/max (modified by GameManager._setup_next_level:132-133)
- **Customer patience**: Customer.patience export var
- **Level duration**: GameManager.level_time_limit
- **Reputation requirements**: GameManager._complete_level checks reputation >= 50.0
- **Economy scaling**: Costs increase automatically per level in EconomyManager._increase_difficulty_costs()

## Common Gotchas

### Scene References
Main scene must be set in project.godot: `run/main_scene="res://src/main/scenes/Main3D.tscn"`

### NavigationAgent3D Setup
Customer and Waiter movement requires NavigationRegion3D in the main scene. NavigationAgent3D must have `velocity_computed` signal connected for proper pathfinding.

### Food State Checking
OrderManager.complete_order expects food_state int (0-3). Ensure FoodItem exposes current state.

### Table Assignment
Tables must implement: `get_customer_position()`, `sit_customer(customer)`, `release_table()`

### Collision Layers
When adding interactables, set `collision_layer = 0b10000` (layer 4) for player detection.

### Economy System Integration
- Always check EconomyManager.instance.can_afford() before purchases
- Use EconomyManager.instance.add_money(amount, "order") for revenue
- Ingredient costs are automatically deducted when orders are taken

### Order Validation
- Cooking stations will reject food if no active orders exist for that food type
- Check CustomerSpawner.get_active_orders() for debugging order flow
- Food placement requires valid customer orders in the system

### Singleton Dependencies
- GameManager creates EconomyManager and OrderManager in _ready()
- OrderManager needs EconomyManager reference for pricing and costs
- CustomerSpawner and WaiterSpawner reference GameManager for spawning
- Always check singleton instances exist before accessing: `if GameManager.instance:`
- Singletons use static `instance` variable for global access

### Customer/Waiter File Redirects
- `Customer.gd` is a redirect file that extends `CustomerAI.gd` for backwards compatibility
- Always edit `CustomerAI.gd` for customer logic changes
- `WaiterAI.gd` is the main waiter implementation file

### Waiter System Integration
- Waiters are spawned by WaiterSpawner in the main scene
- Waiters automatically detect customers waiting at tables (State.WAITING_FOR_WAITER)
- Waiters take orders from customers and mark them as State.WAITING_FOR_FOOD
- Waiters check serving counter for ready food matching customer orders
- Waiters deliver food directly to customer tables
- Waiters mark orders as "in delivery" to prevent duplicate cooking
- Waiter count can be upgraded through EconomyManager

### Chef System Integration
- Chefs are spawned by ChefSpawner in the main scene
- Chefs automatically detect active orders from CustomerSpawner.get_active_orders()
- Chefs use counter-based duplicate prevention (compare food on counter vs pending orders)
- Chefs assign themselves to customers to prevent race conditions
- Chefs navigate to appropriate cooking stations based on food type
- Chefs create FoodItem instances, place on stations, and wait for cooking completion
- Chefs deliver cooked food to ServingCounter for waiter pickup
- Chef count can be upgraded through EconomyManager

### Customer Visual Feedback System
- Customers display two Label3D emoji indicators:
  - **Emotion Label** (Position: 0, 2.5, 0): Shows customer emotional state
    - 😊 High satisfaction (>80%) while waiting
    - 🤔 Medium satisfaction (>50%) while waiting
    - 😠 Low satisfaction while waiting
    - 📝 Taking order (ORDERING state)
    - 🍽️ High satisfaction (>70%) waiting for food
    - ⏰ Medium satisfaction (>40%) waiting for food
    - 😤 Low satisfaction waiting for food
    - 😋 Eating food (EATING state)
    - 😃 Leaving satisfied
    - 😞 Leaving unsatisfied
  - **Order Label** (Position: 0, 2.0, 0): Shows ordered food type
    - Displays during State.WAITING_FOR_FOOD (after order placed)
    - Hidden when food is received (State.EATING)
    - Shows order emoji: 🍕 (pizza), 🍔 (burger), 🍝 (pasta), 🥗 (salad), 🍲 (soup)
- SpeechBubble node exists in scene but is kept hidden (visible = false)
- Labels are created dynamically in CustomerAI._ready()

### Order Flow and Delivery Tracking
- **Order Lifecycle**:
  1. Customer spawns and is assigned a table immediately (CustomerSpawner)
  2. Customer moves to table (State.ENTERING)
  3. Customer waits for waiter (State.WAITING_FOR_WAITER)
  4. Waiter takes order (State.ORDERING → State.WAITING_FOR_FOOD)
  5. Order appears in CustomerSpawner.get_active_orders()
  6. Chef picks up order, cooks food, places on counter
  7. Waiter picks up food and marks order as "in delivery" (Customer._food_in_delivery = true)
  8. CustomerSpawner filters out orders in delivery to prevent duplicate cooking
  9. Waiter delivers food to customer (State.EATING)
  10. Customer eats and leaves

- **Duplicate Prevention System**:
  - Chefs use `_count_food_on_counter()` and `_count_pending_orders()` to decide if cooking is needed
  - Only cook if `food_on_counter < pending_orders`
  - Supports multiple customers ordering the same food type
  - Chef assignment prevents multiple chefs from cooking the same order
  - Waiter delivery tracking prevents cooking during food transit

## Godot-Specific Notes

### Export Variables
Use `@export_group("GroupName")` to organize inspector properties:
- CustomerAI.gd: Movement, Behavior, Appearance groups
- EconomyManager.gd: Daily Expenses group
- CustomerSpawner.gd: Spawning, Counter groups

### Signal Documentation
Document signals with `##` doc comments above signal declaration.
Connect signals using the pattern: `signal_name.connect(_method_name)`

### Onready Variables
Use `@onready` for node references that must wait for scene ready:
```gdscript
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: MeshInstance3D = $Visual
@onready var _food_position: Marker3D = $FoodPosition
```

### Type Hints
Always use typed GDScript for better error detection:
```gdscript
var _placed_foods: Array[FoodItem] = []
func place_food(food: FoodItem, player: Node3D = null) -> bool:
```

### Node Groups
- `cooking_stations`: All cooking stations for chef navigation and cooking
- `tables`: Restaurant tables for customer seating
- `waiters`: Waiter NPCs for order taking and food delivery
- `chefs`: Chef NPCs for automated cooking
- `customers`: Customer entities for order tracking
- `hud`: Main HUD for displaying game information
- `customer_spawner`: CustomerSpawner for accessing active orders
- Use `add_to_group("group_name")` for system-wide node access
- Access groups via `get_tree().get_nodes_in_group("group_name")`

### Process Modes
- GameManager uses `Node.PROCESS_MODE_ALWAYS` for pause menu functionality
- UI components should handle pause states appropriately

## Known Issues & Warnings

### Non-Critical Warnings (Safe to Ignore)
These warnings appear in debug output but don't affect gameplay:
- `AudioManager._sound_cache` declared but never used (reserved for future optimization)
- `CustomerAI.old_satisfaction` unused local variable (line 792)
- `Table.gd` integer division warning (line 206) - intentional behavior
- `CookingStation._process(delta)` unused parameter (line 62)
- `Door.interact(player)` unused parameter (line 64)
- `PlayerController.gd` ternary operator type compatibility (lines 260, 277, 398) - works correctly
- `GameHUD.gd` integer division warning (line 74) - intentional behavior
- `TutorialOverlay.is_visible` shadows CanvasItem method (line 21) - local var, no conflict
- `OrderBoard.order_selected` signal unused (line 6) - reserved for future feature
- `OrderBoard._orders_container` unused variable (line 25) - reserved for future feature

### Active Warnings to Fix
- **CustomerSpawner**: "No order counter found!" warning
  - Order counter UI node missing from Main3D scene
  - Functionality works without it, but UI element should be added

### Missing Features (Documented for Future Implementation)
- **Main Menu**: Game starts directly in Main3D scene (needs start screen)
- **Pause Menu UI**: ESC works but needs full pause UI with buttons
- **Save/Load System**: No progress persistence between sessions
- **Audio Files**: AudioManager ready but sound files need to be added to `assets/audio/sfx/`
- **Speech Bubbles**: Exist in CustomerAI but disabled (line 60-61), emoji labels used instead

### Debug Output Spam
- Chef AI checks for orders every frame (frequent "[DEBUG SPAWNER] Checking 0 active customers" messages)
- This is intentional for responsive AI but can be reduced if performance becomes an issue
