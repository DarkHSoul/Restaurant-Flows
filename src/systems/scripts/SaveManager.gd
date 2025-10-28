## SaveManager - Singleton for handling game save/load operations
## Manages 5 save slots with metadata tracking and file I/O
extends Node

## Emitted when a save operation completes successfully
signal save_completed(slot_number: int)
## Emitted when a load operation completes successfully
signal load_completed(slot_number: int)
## Emitted when a save is deleted
signal save_deleted(slot_number: int)

const SAVE_VERSION := "1.0"
const TOTAL_SLOTS := 5
const SAVE_FILE_PREFIX := "user://save_slot_"
const SAVE_FILE_EXTENSION := ".sav"

## Singleton instance
static var instance: SaveManager = null

## Total play time in seconds (accumulates across sessions)
var total_play_time: float = 0.0
## Session start time for play time tracking
var _session_start_time: float = 0.0
## Most recently used save slot (for auto-save and Continue)
var _last_used_slot: int = -1
## Flag to indicate that a game was just loaded and should auto-start
var should_start_loaded_game: bool = false
## Flag to indicate that a new game should be started
var should_start_new_game: bool = false

## Flag to indicate that we are currently loading a save (prevents auto-spawning)
var is_loading_save: bool = false

## Loaded game data cache (used when loading before managers exist)
var _loaded_game_data: Dictionary = {}

func _ready() -> void:
	if instance and instance != self:
		queue_free()
		return
	instance = self
	_session_start_time = Time.get_ticks_msec() / 1000.0

func _process(delta: float) -> void:
	# Accumulate play time during active gameplay
	if GameManager.instance and GameManager.instance.current_state == GameManager.GameState.PLAYING:
		total_play_time += delta

## Save game state to specified slot
func save_game(slot_number: int) -> bool:
	if slot_number < 1 or slot_number > TOTAL_SLOTS:
		push_error("Invalid save slot: %d" % slot_number)
		return false

	var save_file := ConfigFile.new()

	# === METADATA ===
	save_file.set_value("metadata", "save_version", SAVE_VERSION)
	save_file.set_value("metadata", "save_date", Time.get_datetime_string_from_system())
	save_file.set_value("metadata", "play_time", total_play_time)
	save_file.set_value("metadata", "slot_name", _get_slot_custom_name(slot_number))

	# === GAME MANAGER ===
	if GameManager.instance:
		save_file.set_value("game", "current_level", GameManager.instance.current_level)
		save_file.set_value("game", "game_time", GameManager.instance.game_time)
		save_file.set_value("game", "level_time_limit", GameManager.instance.level_time_limit)

	# === ECONOMY MANAGER ===
	if EconomyManager.instance:
		save_file.set_value("economy", "current_money", EconomyManager.instance.current_money)
		save_file.set_value("economy", "total_revenue", EconomyManager.instance.total_revenue)
		save_file.set_value("economy", "total_expenses", EconomyManager.instance.total_expenses)
		save_file.set_value("economy", "daily_profit", EconomyManager.instance.daily_profit)
		save_file.set_value("economy", "rent_cost", EconomyManager.instance.rent_cost)
		save_file.set_value("economy", "utilities_cost", EconomyManager.instance.utilities_cost)
		save_file.set_value("economy", "staff_cost", EconomyManager.instance.staff_cost)
		save_file.set_value("economy", "maintenance_cost", EconomyManager.instance.maintenance_cost)
		save_file.set_value("economy", "game_day", EconomyManager.instance.game_day)
		save_file.set_value("economy", "orders_today", EconomyManager.instance.orders_today)
		save_file.set_value("economy", "revenue_today", EconomyManager.instance.revenue_today)
		save_file.set_value("economy", "expenses_today", EconomyManager.instance.expenses_today)

		# Save upgrades
		save_file.set_value("upgrades", "owned_upgrades", EconomyManager.instance.owned_upgrades)
		save_file.set_value("upgrades", "multiplier_price", EconomyManager.instance.active_multipliers.get("price", 1.0))
		save_file.set_value("upgrades", "multiplier_ingredient_cost", EconomyManager.instance.active_multipliers.get("ingredient_cost", 1.0))
		save_file.set_value("upgrades", "multiplier_cooking_speed", EconomyManager.instance.active_multipliers.get("cooking_speed", 1.0))
		save_file.set_value("upgrades", "multiplier_spawn_rate", EconomyManager.instance.active_multipliers.get("spawn_rate", 1.0))
		save_file.set_value("upgrades", "multiplier_utilities", EconomyManager.instance.active_multipliers.get("utilities", 1.0))

	# === ORDER MANAGER ===
	if GameManager.instance and GameManager.instance.order_manager:
		save_file.set_value("orders", "total_orders_completed", GameManager.instance.order_manager.total_orders_completed)
		save_file.set_value("orders", "total_orders_failed", GameManager.instance.order_manager.total_orders_failed)
		save_file.set_value("orders", "current_reputation", GameManager.instance.order_manager.current_reputation)

	# === SPAWNERS ===
	# Get spawner references from scene tree
	var customer_spawner = _get_customer_spawner()
	if customer_spawner:
		save_file.set_value("spawners", "spawn_interval_min", customer_spawner.spawn_interval_min)
		save_file.set_value("spawners", "spawn_interval_max", customer_spawner.spawn_interval_max)
		save_file.set_value("spawners", "max_customers", customer_spawner.max_customers)

	var waiter_spawner = _get_waiter_spawner()
	if waiter_spawner:
		save_file.set_value("spawners", "max_waiters", waiter_spawner.max_waiters)

	var chef_spawner = _get_chef_spawner()
	if chef_spawner:
		save_file.set_value("spawners", "max_chefs", chef_spawner.max_chefs)
		save_file.set_value("spawners", "initial_chef_count", chef_spawner.initial_chef_count)

	# === NEW: PLAYER STATE ===
	_save_player_state(save_file)

	# === NEW: CUSTOMERS ===
	_save_customers(save_file)

	# === NEW: TABLES ===
	_save_tables(save_file)

	# === NEW: NPC COUNTS ===
	_save_npc_counts(save_file)

	# === NEW: WAITERS ===
	_save_waiters(save_file)

	# === NEW: CHEFS ===
	_save_chefs(save_file)

	# Save to file
	var save_path := _get_save_path(slot_number)
	var error := save_file.save(save_path)

	if error != OK:
		push_error("Failed to save game to slot %d: %s" % [slot_number, error])
		return false

	_last_used_slot = slot_number
	print("[SaveManager] Game saved to slot %d" % slot_number)
	save_completed.emit(slot_number)
	return true

## Load game state from specified slot
func load_game(slot_number: int) -> bool:
	if slot_number < 1 or slot_number > TOTAL_SLOTS:
		push_error("Invalid save slot: %d" % slot_number)
		return false

	var save_path := _get_save_path(slot_number)
	if not FileAccess.file_exists(save_path):
		push_warning("No save file found in slot %d" % slot_number)
		return false

	# Note: is_loading_save should be set BEFORE calling this function (by LoadGameMenu)
	# This prevents race condition with spawner _ready() calls during scene change

	var save_file := ConfigFile.new()
	var error := save_file.load(save_path)

	if error != OK:
		push_error("Failed to load save file from slot %d: %s" % [slot_number, error])
		return false

	# Verify save version compatibility
	var version: String = save_file.get_value("metadata", "save_version", "")
	if version != SAVE_VERSION:
		push_warning("Save file version mismatch: %s vs %s" % [version, SAVE_VERSION])

	# === METADATA ===
	total_play_time = save_file.get_value("metadata", "play_time", 0.0)

	# Store ALL loaded data in cache for later application
	_loaded_game_data = {
		# Game data
		"current_level": save_file.get_value("game", "current_level", 1),
		"game_time": save_file.get_value("game", "game_time", 0.0),
		"level_time_limit": save_file.get_value("game", "level_time_limit", 300.0),

		# Economy data
		"current_money": save_file.get_value("economy", "current_money", 500.0),
		"total_revenue": save_file.get_value("economy", "total_revenue", 0.0),
		"total_expenses": save_file.get_value("economy", "total_expenses", 0.0),
		"daily_profit": save_file.get_value("economy", "daily_profit", 0.0),
		"rent_cost": save_file.get_value("economy", "rent_cost", 50.0),
		"utilities_cost": save_file.get_value("economy", "utilities_cost", 20.0),
		"staff_cost": save_file.get_value("economy", "staff_cost", 30.0),
		"maintenance_cost": save_file.get_value("economy", "maintenance_cost", 0.0),
		"game_day": save_file.get_value("economy", "game_day", 1),
		"orders_today": save_file.get_value("economy", "orders_today", 0),
		"revenue_today": save_file.get_value("economy", "revenue_today", 0.0),
		"expenses_today": save_file.get_value("economy", "expenses_today", 0.0),
		"owned_upgrades": save_file.get_value("economy", "owned_upgrades", []),

		# Order data
		"total_orders_completed": save_file.get_value("orders", "total_orders_completed", 0),
		"total_orders_failed": save_file.get_value("orders", "total_orders_failed", 0),
		"current_reputation": save_file.get_value("orders", "current_reputation", 100.0),

		# Spawner data
		"spawn_interval_min": save_file.get_value("spawners", "spawn_interval_min", 10.0),
		"spawn_interval_max": save_file.get_value("spawners", "spawn_interval_max", 20.0),
		"max_customers": save_file.get_value("spawners", "max_customers", 5),
		"max_waiters": save_file.get_value("spawners", "max_waiters", 2),
		"max_chefs": save_file.get_value("spawners", "max_chefs", 3),
		"initial_chef_count": save_file.get_value("spawners", "initial_chef_count", 1),

		# NEW: Player data
		"player_position": save_file.get_value("player", "position", Vector3.ZERO),
		"player_rotation_y": save_file.get_value("player", "rotation_y", 0.0),
		"player_camera_rotation": save_file.get_value("player", "camera_rotation", Vector2.ZERO),
		"player_held_food": save_file.get_value("player", "held_food", null),

		# NEW: Customer data
		"customer_count": save_file.get_value("customers", "count", 0),
		"customer_data": save_file.get_value("customers", "data", []),

		# NEW: Table data
		"table_count": save_file.get_value("tables", "count", 0),
		"table_data": save_file.get_value("tables", "data", []),

		# NEW: NPC counts
		"waiter_count": save_file.get_value("npcs", "waiter_count", 0),
		"chef_count": save_file.get_value("npcs", "chef_count", 0),

		# NEW: Waiter data
		"waiter_data": save_file.get_value("waiters", "data", []),

		# NEW: Chef data
		"chef_data": save_file.get_value("chefs", "data", []),
	}

	print("[SaveManager] Loaded game data - Level: %d, Time: %.1f, Money: $%.2f" %
		[_loaded_game_data.current_level, _loaded_game_data.game_time, _loaded_game_data.current_money])

	# Data will be applied by GameManager after scene loads
	# (Removed duplicate call that was causing double-loading)

	_last_used_slot = slot_number
	should_start_loaded_game = true  # Signal that game should auto-start
	should_start_new_game = false  # Ensure not starting a new game
	print("[SaveManager] Game loaded from slot %d" % slot_number)
	load_completed.emit(slot_number)
	return true

## Apply cached loaded game data to managers (called by GameManager after managers are created)
func apply_loaded_data() -> void:
	if _loaded_game_data.is_empty():
		return

	print("[SaveManager] Applying loaded data to managers...")

	# === GAME MANAGER ===
	if GameManager.instance:
		GameManager.instance.current_level = _loaded_game_data.get("current_level", 1)
		GameManager.instance.game_time = _loaded_game_data.get("game_time", 0.0)
		GameManager.instance.level_time_limit = _loaded_game_data.get("level_time_limit", 300.0)

	# === ECONOMY MANAGER ===
	if GameManager.instance and GameManager.instance.economy_manager:
		var econ = GameManager.instance.economy_manager
		econ.current_money = _loaded_game_data.get("current_money", 500.0)
		econ.total_revenue = _loaded_game_data.get("total_revenue", 0.0)
		econ.total_expenses = _loaded_game_data.get("total_expenses", 0.0)
		econ.daily_profit = _loaded_game_data.get("daily_profit", 0.0)
		econ.rent_cost = _loaded_game_data.get("rent_cost", 50.0)
		econ.utilities_cost = _loaded_game_data.get("utilities_cost", 20.0)
		econ.staff_cost = _loaded_game_data.get("staff_cost", 30.0)
		econ.maintenance_cost = _loaded_game_data.get("maintenance_cost", 0.0)
		econ.game_day = _loaded_game_data.get("game_day", 1)
		econ.orders_today = _loaded_game_data.get("orders_today", 0)
		econ.revenue_today = _loaded_game_data.get("revenue_today", 0.0)
		econ.expenses_today = _loaded_game_data.get("expenses_today", 0.0)

		# Handle typed array for owned_upgrades (Array[String])
		econ.owned_upgrades.clear()
		var loaded_upgrades = _loaded_game_data.get("owned_upgrades", [])
		for upgrade in loaded_upgrades:
			econ.owned_upgrades.append(upgrade)

	# === ORDER MANAGER ===
	if GameManager.instance and GameManager.instance.order_manager:
		var order_mgr = GameManager.instance.order_manager
		order_mgr.total_orders_completed = _loaded_game_data.get("total_orders_completed", 0)
		order_mgr.total_orders_failed = _loaded_game_data.get("total_orders_failed", 0)
		order_mgr.current_reputation = _loaded_game_data.get("current_reputation", 100.0)

	# === NEW: LOAD PLAYER STATE ===
	_load_player_state()

	# === NEW: LOAD CUSTOMERS ===
	_load_customers()

	# === NEW: LOAD TABLES ===
	# Defer table loading to next frame so scene is fully loaded
	_load_tables.call_deferred()

	# === NEW: REBUILD REFERENCES ===
	# Defer reference rebuilding to ensure tables are loaded first
	_rebuild_customer_table_references.call_deferred()

	# === NEW: LOAD NPC COUNTS ===
	# Defer NPC spawning/loading to avoid blocking
	_schedule_npc_load()

	print("[SaveManager] Loaded data applied - Money: $%.2f, Level: %d" %
		[_loaded_game_data.get("current_money", 0), _loaded_game_data.get("current_level", 1)])

	# DON'T clear cache yet - NPC spawn needs it
	# Cache will be cleared after NPC spawn completes

## Delete save file from specified slot
func delete_save(slot_number: int) -> bool:
	if slot_number < 1 or slot_number > TOTAL_SLOTS:
		push_error("Invalid save slot: %d" % slot_number)
		return false

	var save_path := _get_save_path(slot_number)
	if not FileAccess.file_exists(save_path):
		push_warning("No save file to delete in slot %d" % slot_number)
		return false

	var error := DirAccess.remove_absolute(save_path)
	if error != OK:
		push_error("Failed to delete save file in slot %d: %s" % [slot_number, error])
		return false

	# Also delete custom name file if it exists
	var name_path := _get_slot_name_path(slot_number)
	if FileAccess.file_exists(name_path):
		DirAccess.remove_absolute(name_path)

	if _last_used_slot == slot_number:
		_last_used_slot = -1

	print("[SaveManager] Save deleted from slot %d" % slot_number)
	save_deleted.emit(slot_number)
	return true

## Check if a save exists in the specified slot
func has_save(slot_number: int) -> bool:
	if slot_number < 1 or slot_number > TOTAL_SLOTS:
		return false
	return FileAccess.file_exists(_get_save_path(slot_number))

## Get metadata for a save slot (returns null if no save exists)
func get_save_metadata(slot_number: int) -> Dictionary:
	if not has_save(slot_number):
		return {}

	var save_file := ConfigFile.new()
	var error := save_file.load(_get_save_path(slot_number))

	if error != OK:
		return {}

	return {
		"slot_number": slot_number,
		"slot_name": _get_slot_custom_name(slot_number),
		"save_date": save_file.get_value("metadata", "save_date", "Unknown"),
		"play_time": save_file.get_value("metadata", "play_time", 0.0),
		"level": save_file.get_value("game", "current_level", 1),
		"money": save_file.get_value("economy", "current_money", 0.0),
		"reputation": save_file.get_value("orders", "current_reputation", 100.0)
	}

## Get all save slots metadata (array of 5 dictionaries, empty dict if slot is empty)
func get_all_save_metadata() -> Array[Dictionary]:
	var metadata_list: Array[Dictionary] = []
	for i in range(1, TOTAL_SLOTS + 1):
		metadata_list.append(get_save_metadata(i))
	return metadata_list

## Get the most recently used save slot (returns -1 if no saves exist)
func get_latest_save_slot() -> int:
	if _last_used_slot > 0 and has_save(_last_used_slot):
		return _last_used_slot

	# Find most recent save by timestamp
	var latest_slot := -1
	var latest_time := ""

	for i in range(1, TOTAL_SLOTS + 1):
		if has_save(i):
			var metadata := get_save_metadata(i)
			var save_date: String = metadata.get("save_date", "")
			if save_date > latest_time:
				latest_time = save_date
				latest_slot = i

	return latest_slot

## Set custom name for a save slot
func set_slot_name(slot_number: int, custom_name: String) -> void:
	if slot_number < 1 or slot_number > TOTAL_SLOTS:
		return

	var name_file := FileAccess.open(_get_slot_name_path(slot_number), FileAccess.WRITE)
	if name_file:
		name_file.store_string(custom_name)
		name_file.close()

## Get custom name for a save slot
func get_slot_name(slot_number: int) -> String:
	return _get_slot_custom_name(slot_number)

## Reset play time (used when starting new game)
func reset_play_time() -> void:
	total_play_time = 0.0
	_session_start_time = Time.get_ticks_msec() / 1000.0

# === PRIVATE HELPER METHODS ===

func _get_save_path(slot_number: int) -> String:
	return SAVE_FILE_PREFIX + str(slot_number) + SAVE_FILE_EXTENSION

func _get_slot_name_path(slot_number: int) -> String:
	return SAVE_FILE_PREFIX + str(slot_number) + "_name.txt"

func _get_slot_custom_name(slot_number: int) -> String:
	var name_path := _get_slot_name_path(slot_number)
	if FileAccess.file_exists(name_path):
		var name_file := FileAccess.open(name_path, FileAccess.READ)
		if name_file:
			var custom_name := name_file.get_as_text().strip_edges()
			name_file.close()
			if custom_name.length() > 0:
				return custom_name

	# Default name if no custom name set
	if has_save(slot_number):
		# Read level directly from save file to avoid recursion
		var save_file := ConfigFile.new()
		var error := save_file.load(_get_save_path(slot_number))
		if error == OK:
			var level: int = save_file.get_value("game", "current_level", 1)
			return "Save %d - Level %d" % [slot_number, level]
		else:
			return "Save %d" % slot_number
	else:
		return "Empty Slot"

func _get_customer_spawner() -> Node:
	var spawners = get_tree().get_nodes_in_group("customer_spawner")
	return spawners[0] if spawners.size() > 0 else null

func _get_waiter_spawner() -> Node:
	var spawners = get_tree().get_nodes_in_group("waiter_spawner")
	return spawners[0] if spawners.size() > 0 else null

func _get_chef_spawner() -> Node:
	var spawners = get_tree().get_nodes_in_group("chef_spawner")
	return spawners[0] if spawners.size() > 0 else null

## ===== NEW SAVE/LOAD HELPER FUNCTIONS =====

func _save_player_state(save_file: ConfigFile) -> void:
	"""Save player state to file."""
	var players = get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		push_warning("[SaveManager] No player found to save")
		return

	var player = players[0]
	if not player.has_method("get_save_data"):
		push_warning("[SaveManager] Player doesn't have get_save_data method")
		return

	var data: Dictionary = player.get_save_data()
	save_file.set_value("player", "position", data.get("position", Vector3.ZERO))
	save_file.set_value("player", "rotation_y", data.get("rotation_y", 0.0))
	save_file.set_value("player", "camera_rotation", data.get("camera_rotation", Vector2.ZERO))
	save_file.set_value("player", "held_food", data.get("held_food", null))

	print("[SaveManager] Player state saved")

func _save_customers(save_file: ConfigFile) -> void:
	"""Save all active customers to file."""
	var customers = get_tree().get_nodes_in_group("customers")
	var customer_data_list: Array = []

	# Assign save IDs to customers
	var save_id: int = 1
	for customer in customers:
		if not customer or not customer.has_method("get_save_data"):
			continue

		# Assign unique ID
		customer._save_id = save_id
		save_id += 1

		# Get save data
		var data: Dictionary = customer.get_save_data()
		customer_data_list.append(data)

	save_file.set_value("customers", "count", customer_data_list.size())
	save_file.set_value("customers", "data", customer_data_list)

	print("[SaveManager] Saved %d customers" % customer_data_list.size())

func _save_tables(save_file: ConfigFile) -> void:
	"""Save all table states to file."""
	var tables = get_tree().get_nodes_in_group("tables")
	var table_data_list: Array = []

	for table in tables:
		if not table or not table.has_method("get_save_data"):
			continue

		var data: Dictionary = table.get_save_data()
		table_data_list.append(data)

	save_file.set_value("tables", "count", table_data_list.size())
	save_file.set_value("tables", "data", table_data_list)

	print("[SaveManager] Saved %d tables" % table_data_list.size())

func _save_npc_counts(save_file: ConfigFile) -> void:
	"""Save current NPC counts (waiters and chefs) for respawning."""
	var waiters = get_tree().get_nodes_in_group("waiters")
	var chefs = get_tree().get_nodes_in_group("chefs")

	save_file.set_value("npcs", "waiter_count", waiters.size())
	save_file.set_value("npcs", "chef_count", chefs.size())

	print("[SaveManager] Saved NPC counts - Waiters: %d, Chefs: %d" %
		[waiters.size(), chefs.size()])

func _save_waiters(save_file: ConfigFile) -> void:
	"""Save all active waiters to file."""
	var waiters = get_tree().get_nodes_in_group("waiters")
	var waiter_data_list: Array = []

	for waiter in waiters:
		if not waiter or not waiter.has_method("get_save_data"):
			continue

		var data: Dictionary = waiter.get_save_data()
		waiter_data_list.append(data)

	save_file.set_value("waiters", "count", waiter_data_list.size())
	save_file.set_value("waiters", "data", waiter_data_list)

	print("[SaveManager] Saved %d waiters" % waiter_data_list.size())

func _save_chefs(save_file: ConfigFile) -> void:
	"""Save all active chefs to file."""
	var chefs = get_tree().get_nodes_in_group("chefs")
	var chef_data_list: Array = []

	for chef in chefs:
		if not chef or not chef.has_method("get_save_data"):
			continue

		var data: Dictionary = chef.get_save_data()
		chef_data_list.append(data)

	save_file.set_value("chefs", "count", chef_data_list.size())
	save_file.set_value("chefs", "data", chef_data_list)

	print("[SaveManager] Saved %d chefs" % chef_data_list.size())

func _load_player_state() -> void:
	"""Restore player state from loaded data."""
	var players = get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		push_warning("[SaveManager] No player found to load data into")
		return

	var player = players[0]
	if not player.has_method("apply_save_data"):
		push_warning("[SaveManager] Player doesn't have apply_save_data method")
		return

	var data := {
		"position": _loaded_game_data.get("player_position", Vector3.ZERO),
		"rotation_y": _loaded_game_data.get("player_rotation_y", 0.0),
		"camera_rotation": _loaded_game_data.get("player_camera_rotation", Vector2.ZERO),
		"held_food": _loaded_game_data.get("player_held_food", null)
	}

	player.apply_save_data(data)
	print("[SaveManager] Player state restored")

func _load_customers() -> void:
	"""Recreate customers from loaded data."""
	var customer_count: int = _loaded_game_data.get("customer_count", 0)
	var customer_data: Array = _loaded_game_data.get("customer_data", [])

	if customer_count == 0:
		print("[SaveManager] No customers to load")
		return

	# Load customer scene
	var customer_scene := preload("res://src/characters/scenes/Customer.tscn")
	if not customer_scene:
		push_error("[SaveManager] Failed to load customer scene")
		return

	# Recreate each customer
	for data in customer_data:
		var customer := customer_scene.instantiate() as Customer
		if not customer:
			push_error("[SaveManager] Failed to instantiate customer")
			continue

		# Add to current scene (NOT root, so it gets cleaned up on scene change)
		# Use call_deferred to avoid "parent busy" error during scene initialization
		var current_scene = get_tree().current_scene
		if current_scene:
			current_scene.call_deferred("add_child", customer)
			# Apply saved data after node is in tree (also deferred)
			customer.call_deferred("apply_save_data", data)
		else:
			push_error("[SaveManager] No current scene to add customer to!")
			customer.queue_free()
			continue

		# Store in a temporary list for reference rebuilding
		if not _loaded_game_data.has("customer_instances"):
			_loaded_game_data["customer_instances"] = []
		_loaded_game_data["customer_instances"].append(customer)

	print("[SaveManager] Recreated %d customers" % customer_count)

func _load_tables() -> void:
	"""Restore table states from loaded data."""
	var table_count: int = _loaded_game_data.get("table_count", 0)
	var table_data: Array = _loaded_game_data.get("table_data", [])

	if table_count == 0:
		print("[SaveManager] No tables to load")
		return

	# Get all tables in scene
	var tables = get_tree().get_nodes_in_group("tables")

	# Apply data to each table
	for data in table_data:
		var table_number: int = data.get("table_number", -1)
		if table_number < 0:
			continue

		# Find matching table
		var table = null
		for t in tables:
			if t.table_number == table_number:
				table = t
				break

		if not table:
			push_warning("[SaveManager] Table %d not found in scene" % table_number)
			continue

		# Apply saved data
		table.apply_save_data(data)

	print("[SaveManager] Restored %d tables" % table_count)

func _load_waiters() -> void:
	"""Recreate waiters from loaded data with full state."""
	var waiter_data: Array = _loaded_game_data.get("waiter_data", [])

	if waiter_data.is_empty():
		print("[SaveManager] No waiters to load")
		return

	# Load waiter scene
	var waiter_scene := preload("res://src/characters/scenes/Waiter.tscn")
	if not waiter_scene:
		push_error("[SaveManager] Failed to load waiter scene")
		return

	# Recreate each waiter
	for data in waiter_data:
		var waiter := waiter_scene.instantiate() as Waiter
		if not waiter:
			push_error("[SaveManager] Failed to instantiate waiter")
			continue

		# Add to current scene (NOT root, so it gets cleaned up on scene change)
		# Use call_deferred to avoid "parent busy" error during scene initialization
		var current_scene = get_tree().current_scene
		if current_scene:
			current_scene.call_deferred("add_child", waiter)
			# Apply saved data after node is in tree (also deferred)
			if waiter.has_method("apply_save_data"):
				waiter.call_deferred("apply_save_data", data)
		else:
			push_error("[SaveManager] No current scene to add waiter to!")
			waiter.queue_free()
			continue

	print("[SaveManager] Recreated %d waiters" % waiter_data.size())

func _load_chefs() -> void:
	"""Recreate chefs from loaded data with full state."""
	var chef_data: Array = _loaded_game_data.get("chef_data", [])

	if chef_data.is_empty():
		print("[SaveManager] No chefs to load")
		return

	# Load chef scene
	var chef_scene := preload("res://src/characters/scenes/Chef.tscn")
	if not chef_scene:
		push_error("[SaveManager] Failed to load chef scene")
		return

	# Recreate each chef
	for data in chef_data:
		var chef := chef_scene.instantiate() as Chef
		if not chef:
			push_error("[SaveManager] Failed to instantiate chef")
			continue

		# Add to current scene (NOT root, so it gets cleaned up on scene change)
		# Use call_deferred to avoid "parent busy" error during scene initialization
		var current_scene = get_tree().current_scene
		if current_scene:
			current_scene.call_deferred("add_child", chef)
			# Apply saved data after node is in tree (also deferred)
			if chef.has_method("apply_save_data"):
				chef.call_deferred("apply_save_data", data)
		else:
			push_error("[SaveManager] No current scene to add chef to!")
			chef.queue_free()
			continue

	print("[SaveManager] Recreated %d chefs" % chef_data.size())

func _rebuild_customer_table_references() -> void:
	"""Rebuild customer → table and table → customer references."""
	var customer_instances: Array = _loaded_game_data.get("customer_instances", [])
	var tables = get_tree().get_nodes_in_group("tables")

	# Rebuild customer → table references
	for customer in customer_instances:
		if not customer:
			continue

		# Get saved table number from customer's loaded data
		var customer_data = null
		var customer_data_list: Array = _loaded_game_data.get("customer_data", [])
		for data in customer_data_list:
			if data.get("save_id", -1) == customer._save_id:
				customer_data = data
				break

		if not customer_data:
			continue

		var table_number: int = customer_data.get("table_number", -1)
		if table_number < 0:
			continue

		# Find the table
		for table in tables:
			if table.table_number == table_number:
				customer._assigned_table = table

				# Check customer's state to determine how to restore them
				if customer._state == 0:  # State.ENTERING
					# Customer was walking to table when saved - DON'T add to seated list yet
					# Just set navigation target and let normal sit_customer flow happen
					if customer._agent and table:
						var target_pos = table.get_customer_position()
						customer._agent.set_target_position(target_pos)
						customer._target_position = target_pos
						customer._has_target = true
						print("[SaveManager] Customer %d is ENTERING table %d - set navigation target" % [customer._save_id, table_number])
				else:
					# Customer was already seated (WAITING_FOR_WAITER, ORDERING, WAITING_FOR_FOOD, or EATING)
					# Add to seated list and position at table
					table._seated_customers.append(customer)
					customer.global_position = table.get_customer_position()
					customer._has_target = false
					print("[SaveManager] Customer %d already seated at table %d (state: %d)" % [customer._save_id, table_number, customer._state])

				break

	print("[SaveManager] Rebuilt customer-table references")

func _schedule_npc_load() -> void:
	"""Schedule NPC loading with a delay to ensure spawners are ready."""
	# Use a timer to load NPCs after a delay
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.one_shot = true
	timer.timeout.connect(_delayed_npc_load)
	add_child(timer)
	timer.start()

func _delayed_npc_load() -> void:
	"""Called after delay to load NPCs when spawners and scene are ready."""
	# Load waiters and chefs from save data (with full state)
	_load_waiters()
	_load_chefs()

	# Rebuild NPC references (customer assignments, etc.)
	# Use call_deferred to ensure all NPCs are in the tree before rebuilding references
	_rebuild_npc_references.call_deferred()

	# Clear the loading flag (also deferred to happen after reference rebuild)
	call_deferred("_finalize_load")

func _finalize_load() -> void:
	"""Finalize the load process after all NPCs are in the tree."""
	# Clear the loading flag
	is_loading_save = false
	print("[SaveManager] is_loading_save set to FALSE")

	# Now safe to clear cache
	_loaded_game_data.clear()
	print("[SaveManager] Cache cleared after NPC load")

func _rebuild_npc_references() -> void:
	"""Rebuild waiter/chef → customer references after loading."""
	var customers := get_tree().get_nodes_in_group("customers")
	var waiters := get_tree().get_nodes_in_group("waiters")
	var chefs := get_tree().get_nodes_in_group("chefs")

	# Register loaded customers with CustomerSpawner
	var customer_spawner := _get_customer_spawner()
	if customer_spawner:
		for customer in customers:
			if customer and is_instance_valid(customer):
				# Add to active customers list if not already there
				if customer_spawner.has_method("_register_loaded_customer"):
					customer_spawner._register_loaded_customer(customer)
				else:
					# Fallback: directly access _active_customers if method doesn't exist
					if not customer in customer_spawner._active_customers:
						customer_spawner._active_customers.append(customer)
						print("[SaveManager] Registered loaded customer with CustomerSpawner")

						# Connect signals for loaded customer
						if not customer.order_placed.is_connected(customer_spawner._on_customer_order_placed):
							customer.order_placed.connect(customer_spawner._on_customer_order_placed)
						if not customer.order_received.is_connected(customer_spawner._on_customer_order_received):
							customer.order_received.connect(customer_spawner._on_customer_order_received)
						if not customer.left_restaurant.is_connected(customer_spawner._on_customer_left_restaurant):
							customer.left_restaurant.connect(customer_spawner._on_customer_left_restaurant)
	else:
		push_warning("[SaveManager] CustomerSpawner not found - cannot register loaded customers")

	# Rebuild waiter → customer references
	for waiter in waiters:
		if not waiter or not is_instance_valid(waiter):
			continue

		var saved_customer_id: int = waiter.get_meta("_saved_customer_id", -1)
		if saved_customer_id < 0:
			continue

		# Find the customer with this save_id
		for customer in customers:
			if customer and is_instance_valid(customer) and customer._save_id == saved_customer_id:
				waiter._assigned_customer = customer
				print("[SaveManager] Rebuilt waiter → customer %d reference" % saved_customer_id)
				break

	# Rebuild chef → customer references
	for chef in chefs:
		if not chef or not is_instance_valid(chef):
			continue

		var saved_customer_id: int = chef.get_meta("_saved_customer_id", -1)
		if saved_customer_id < 0:
			continue

		# Find the customer with this save_id
		for customer in customers:
			if customer and is_instance_valid(customer) and customer._save_id == saved_customer_id:
				chef._assigned_customer = customer
				print("[SaveManager] Rebuilt chef → customer %d reference" % saved_customer_id)
				break

	print("[SaveManager] Rebuilt NPC references")
