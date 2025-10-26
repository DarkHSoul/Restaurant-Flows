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

	# Create economy manager
	economy_manager = EconomyManager.new()
	add_child(economy_manager)

	# Create order manager
	order_manager = OrderManager.new()
	order_manager.economy_manager = economy_manager
	add_child(order_manager)

func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		game_time += delta

		# Check level time limit
		if game_time >= level_time_limit:
			_complete_level()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if current_state == GameState.PLAYING:
			pause_game()
		elif current_state == GameState.PAUSED:
			resume_game()

	# Debug key: F9 to add money
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_F9:
			if economy_manager:
				economy_manager.add_money(100.0, "debug")
				print("[DEBUG] F9 pressed - Added $100. Current money: $", economy_manager.current_money)

## Public interface

func start_game() -> void:
	"""Start a new game."""
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
