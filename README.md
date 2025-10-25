# Restaurant Flows 🍕🍔

A detailed 3D restaurant management game built with Godot 4.5

## Game Overview

Run your own restaurant! Cook delicious meals, serve customers, and grow your business.

### Features

- **First-Person 3D Gameplay** - Full camera control and movement
- **Realistic Cooking System** - Multiple cooking stations with timers and burn mechanics
- **Customer AI** - Smart pathfinding, ordering, patience, and satisfaction system
- **Order Management** - Track multiple orders simultaneously
- **Progression System** - Earn money, build reputation, unlock levels
- **Multiple Food Types** - Pizza, burgers, pasta, salad, soup, and more
- **Dynamic Difficulty** - Levels get progressively harder

## How to Play

### Controls

- **WASD** - Move
- **Mouse** - Look around
- **Shift** - Sprint
- **E** - Interact with stations/tables
- **Left Click** - Pickup/Drop food items
- **ESC** - Pause menu

### Gameplay Loop

1. **Customers arrive** and wait in queue
2. **Seat customers** at available tables (automatic)
3. **Take orders** by interacting with tables
4. **Prepare food**:
   - Pick up raw ingredients from storage
   - Use prep counter for preparation (if needed)
   - Cook on appropriate station (oven, stove)
   - Monitor cooking timers - don't let it burn!
5. **Serve food** by dropping it on customer's table
6. **Earn money** and reputation for good service
7. **Repeat** and handle multiple customers!

### Cooking Stations

- **Oven** - For baking pizzas (20s cooking time)
- **Stove** - For burgers, steaks, fries (12-15s cooking time)
- **Prep Counter** - For chopping and preparing ingredients

### Tips

- ⏰ **Speed matters** - Fast service = happy customers = bonus money
- 🔥 **Don't burn food** - Overcooked food reduces satisfaction
- 📋 **Track orders** - Check the HUD for active orders
- 💰 **Build reputation** - Keep reputation above 50% to advance
- 🏃 **Sprint** - Use Shift to move faster between stations

## Game Structure

### Core Systems

- **PlayerController** - Movement, interaction, item carrying
- **Customer AI** - State machine, pathfinding, orders, satisfaction
- **FoodItem** - Cooking states, timers, visual feedback
- **CookingStation** - Base class for all cooking equipment
- **Table** - Customer seating, order taking, food serving
- **CustomerSpawner** - Queue management, table assignment
- **OrderManager** - Menu, pricing, order completion
- **GameManager** - Game state, levels, progression

### Project Structure

```
Restaurant-Flows/
├── src/
│   ├── characters/
│   │   ├── scenes/
│   │   │   ├── Player.tscn
│   │   │   └── Customer.tscn
│   │   └── scripts/
│   │       ├── player/
│   │       │   └── PlayerController.gd
│   │       └── customers/
│   │           ├── CustomerAI.gd
│   │           └── Customer.gd
│   ├── environment/
│   │   ├── scenes/
│   │   │   ├── Table.tscn
│   │   │   ├── Oven.tscn
│   │   │   ├── Stove.tscn
│   │   │   └── PrepCounter.tscn
│   │   └── scripts/
│   │       ├── Table.gd
│   │       ├── CookingStation.gd
│   │       ├── Oven.gd
│   │       ├── Stove.gd
│   │       └── PrepCounter.gd
│   ├── systems/
│   │   ├── scenes/
│   │   │   ├── FoodPizza.tscn
│   │   │   └── FoodBurger.tscn
│   │   └── scripts/
│   │       ├── FoodItem.gd
│   │       ├── CustomerSpawner.gd
│   │       ├── OrderManager.gd
│   │       └── GameManager.gd
│   ├── ui/
│   │   ├── GameHUD.tscn
│   │   └── GameHUD.gd
│   └── main/
│       └── scenes/
│           └── Main3D.tscn
└── project.godot
```

## Customization

### Adding New Food Items

1. Create new scene inheriting from `FoodItem`
2. Set food type, cooking time, prep requirements
3. Add to menu in `OrderManager.gd`
4. Place in storage area

### Creating New Cooking Stations

1. Extend `CookingStation` class
2. Override `_can_accept_food()` for food type filtering
3. Set station properties (type, capacity, auto-cook)
4. Create scene and place in kitchen

### Adjusting Difficulty

Edit in `GameManager.gd`:
- `level_time_limit` - Time per level
- `spawn_interval_min/max` - Customer spawn rate
- Customer patience in `CustomerAI.gd`

## Development

Built with Godot 4.5

### Key Design Patterns

- **State Machines** - Customer AI behavior
- **Signals** - Event-driven communication
- **Inheritance** - CookingStation base class
- **Composition** - Modular food/station system
- **Singleton** - GameManager global access

## License

MIT License - See LICENSE file

## Credits

Created with Godot Engine


---

**Enjoy running your restaurant! 🍽️**
