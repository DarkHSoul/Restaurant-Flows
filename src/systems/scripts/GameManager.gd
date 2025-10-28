extends Node
class_name GameManager

## Main game manager - handles game state, level progression, etc.

## Signals
signal game_started()
signal game_paused()
signal game_resumed()
signal game_over(final_score: Dictionary)
signal level_completed(level: int, score: Dictionary)

## Game state
enum GameState {
	MENU,
	PLAYING,
	PAUSED,
	BUILD_MODE,
	GAME_OVER
}

var current_state: GameState = GameState.MENU
var current_level: int = 1
var game_time: float = 0.0
var level_time_limit: float = 300.0  # 5 minutes per level

## References
var order_manager: OrderManager
var economy_manager: EconomyManager
var customer_spawner: Node3D  # CustomerSpawner

## Singletons
static var instance: GameManager

func _ready() -> void:
	if instance and instance != self:
		queue_free()
		return

	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Connect to window focus change notifications
	get_tree().root.focus_entered.connect(_on_window_focus_entered)
	get_tree().root.focus_exited.connect(_on_window_focus_exited)

	# Create economy manager
	economy_manager = EconomyManager.new()
	add_child(economy_manager)

	# Create order manager
	order_manager = OrderManager.new()
	order_manager.economy_manager = economy_manager
	add_child(order_manager)

	# Apply any loaded game data ONLY if loading a game (must happen AFTER managers are created)
	if SaveManager.instance and SaveManager.instance.should_start_loaded_game:
		SaveManager.instance.apply_loaded_data()

	# Check if we should auto-start a game (loaded or new)
	if SaveManager.instance:
		# Wait a frame for everything to be ready
		await get_tree().process_frame

		if SaveManager.instance.should_start_loaded_game:
			SaveManager.instance.should_start_loaded_game = false  # Reset flag
			current_state = GameState.PLAYING
			print("[GAME_MANAGER] Auto-started loaded game - State: PLAYING")
		elif SaveManager.instance.should_start_new_game:
			SaveManager.instance.should_start_new_game = false  # Reset flag
			# Start a new game
			start_game()
			print("[GAME_MANAGER] Auto-started new game - State: PLAYING")

func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		game_time += delta

		# Check level time limit
		if game_time >= level_time_limit:
			_complete_level()

func _input(event: InputEvent) -> void:
	# Let PauseMenu handle ESC key - don't handle it here to avoid conflicts
	# PauseMenu will call pause_game() and resume_game() when needed

	# Debug key: F9 to add money
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_F9:
			if economy_manager:
				economy_manager.add_money(100.0, "debug")
				print("[DEBUG] F9 pressed - Added $100. Current money: $", economy_manager.current_money)

## Public interface

func start_game() -> void:
	"""Start a new game."""
	print("[GAME_MANAGER] Starting game...")
	current_state = GameState.PLAYING
	current_level = 1
	game_time = 0.0

	if order_manager:
		order_manager.total_orders_completed = 0
		order_manager.total_orders_failed = 0
		order_manager.current_reputation = 100.0

	# Reset economy
	if economy_manager:
		economy_manager._reset_economy()

	print("[GAME_MANAGER] Game started! State: PLAYING")
	game_started.emit()

func pause_game() -> void:
	"""Pause the game."""
	if current_state != GameState.PLAYING:
		return

	current_state = GameState.PAUSED
	get_tree().paused = true
	game_paused.emit()

func resume_game() -> void:
	"""Resume the game."""
	if current_state != GameState.PAUSED:
		return

	current_state = GameState.PLAYING
	get_tree().paused = false
	game_resumed.emit()

func end_game() -> void:
	"""End the current game."""
	current_state = GameState.GAME_OVER

	var final_score := _calculate_final_score()
	game_over.emit(final_score)

func get_remaining_time() -> float:
	"""Get time remaining in current level."""
	return max(0.0, level_time_limit - game_time)

func get_time_percent() -> float:
	"""Get level progress as 0.0-1.0."""
	return game_time / level_time_limit

## Private methods

func _complete_level() -> void:
	"""Complete the current level."""
	var score := _calculate_final_score()

	level_completed.emit(current_level, score)

	# Auto-save progress after level completion
	_auto_save_progress()

	# Check if player met requirements
	if order_manager and order_manager.current_reputation >= 50.0:
		current_level += 1
		game_time = 0.0
		_setup_next_level()
	else:
		end_game()

func _setup_next_level() -> void:
	"""Setup the next level with increased difficulty."""
	level_time_limit = 300.0 - (current_level * 20.0)  # Shorter time
	level_time_limit = max(level_time_limit, 120.0)    # Min 2 minutes

	# Increase customer spawn rate
	if customer_spawner:
		var base_min := 10.0 - current_level
		var base_max := 20.0 - current_level

		# Apply economy upgrade multipliers if available
		if economy_manager:
			base_min /= economy_manager.active_multipliers.spawn_rate
			base_max /= economy_manager.active_multipliers.spawn_rate
			# Increase costs for new level
			economy_manager._increase_difficulty_costs(current_level)

		customer_spawner.spawn_interval_min = max(5.0, base_min)
		customer_spawner.spawn_interval_max = max(10.0, base_max)

func _calculate_final_score() -> Dictionary:
	"""Calculate final score."""
	var stats := {}

	if order_manager:
		stats = order_manager.get_stats()

	stats["level"] = current_level
	stats["time"] = game_time

	# Calculate total score
	var score := 0.0
	score += stats.get("money", 0.0)
	score += stats.get("orders_completed", 0) * 10.0
	score -= stats.get("orders_failed", 0) * 5.0
	score += stats.get("reputation", 0.0) * 2.0

	stats["total_score"] = score

	return stats

func _auto_save_progress() -> void:
	"""Auto-save game progress to the most recently used slot."""
	if not SaveManager.instance:
		push_warning("[GameManager] SaveManager not available for auto-save")
		return

	# Get the latest save slot (or default to slot 1 if no previous saves)
	var save_slot := SaveManager.instance.get_latest_save_slot()
	if save_slot < 1:
		save_slot = 1  # Default to slot 1 for first auto-save

	print("[GameManager] Auto-saving to slot %d..." % save_slot)
	if SaveManager.instance.save_game(save_slot):
		print("[GameManager] Auto-save successful!")
	else:
		push_error("[GameManager] Auto-save failed!")

func _on_window_focus_exited() -> void:
	"""Automatically pause when window loses focus."""
	if current_state == GameState.PLAYING:
		print("[GameManager] Window lost focus - auto-pausing game")
		# Show pause menu instead of just pausing
		var pause_menu = get_tree().get_first_node_in_group("pause_menu")
		if pause_menu and pause_menu.has_method("show_pause_menu"):
			pause_menu.show_pause_menu()
		else:
			# Fallback: just pause if menu not found
			pause_game()

func _on_window_focus_entered() -> void:
	"""Window regained focus - game stays paused, player must manually resume."""
	print("[GameManager] Window gained focus - game remains paused (press ESC to resume)")
