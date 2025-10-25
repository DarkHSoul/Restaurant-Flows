extends Node
class_name WaiterSpawner

## Manages waiter spawning and tracking

## Signals
signal waiter_spawned(waiter: Waiter)
signal waiter_removed(waiter: Waiter)

## Configuration
@export var waiter_scene: PackedScene
@export var spawn_position: Vector3 = Vector3.ZERO  # Use ZERO to auto-calculate position
@export var max_waiters: int = 5
@export var auto_spawn_initial_waiters: bool = false  # Disabled until NavigationMesh is fixed
@export var initial_waiter_count: int = 1

## State
var active_waiters: Array[Waiter] = []

func _ready() -> void:
	# If no scene assigned, try to load default
	if not waiter_scene:
		print("[WAITER_SPAWNER] No waiter scene assigned, loading default...")
		waiter_scene = load("res://src/characters/scenes/Waiter.tscn")
		if waiter_scene:
			print("[WAITER_SPAWNER] Default waiter scene loaded successfully!")
		else:
			print("[WAITER_SPAWNER] ERROR: Could not load default waiter scene!")

	# Auto spawn initial waiters
	if auto_spawn_initial_waiters:
		call_deferred("_spawn_initial_waiters")

func _spawn_initial_waiters() -> void:
	"""Spawn initial waiters on game start."""
	for i in range(initial_waiter_count):
		var waiter := spawn_waiter()
		if waiter:
			print("[WAITER_SPAWNER] Spawned initial waiter %d/%d" % [i + 1, initial_waiter_count])
		await get_tree().create_timer(0.1).timeout  # Small delay between spawns

func _input(event: InputEvent) -> void:
	# Listen for F6 key press to spawn waiter
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_F6:
			spawn_waiter()

func spawn_waiter() -> Waiter:
	"""Spawn a new waiter at the spawn position."""
	print("[DEBUG] spawn_waiter() called")

	# Check max waiters
	if active_waiters.size() >= max_waiters:
		print("[DEBUG] Max waiters reached (%d/%d)" % [active_waiters.size(), max_waiters])
		return null

	var waiter: Waiter = null

	# Try to instance from scene
	if waiter_scene:
		waiter = waiter_scene.instantiate()
	else:
		# Create waiter programmatically
		waiter = _create_waiter_node()

	if not waiter:
		print("[WAITER_SPAWNER] Failed to create waiter!")
		return null

	# Add to scene
	get_tree().root.add_child(waiter)

	# Position waiter
	var spawn_pos := spawn_position
	if spawn_pos == Vector3.ZERO:
		# Try to find a good spawn position NEAR the counter ON THE CUSTOMER SIDE
		# So waiters don't need to go through doors initially
		var counter := _find_order_counter()
		if counter:
			# Spawn on customer side (counter's local +Z is customer facing)
			# Use a larger offset to ensure waiter is clearly on the customer side
			var customer_side_offset := counter.global_transform.basis * Vector3(0, 0, 4.0)
			spawn_pos = counter.global_position + customer_side_offset
			spawn_pos.y = 0.0  # Start on the ground
			print("[WAITER_SPAWNER] Calculated spawn position: %v (Counter at: %v)" % [spawn_pos, counter.global_position])
		else:
			spawn_pos = Vector3(0, 0, 0)

	waiter.global_position = spawn_pos
	waiter.set_idle_position(spawn_pos)

	# Track waiter
	active_waiters.append(waiter)

	# Connect signals
	waiter.tree_exiting.connect(_on_waiter_removed.bind(waiter))

	print("[WAITER_SPAWNER] Spawned waiter at position: ", spawn_pos)
	waiter_spawned.emit(waiter)

	return waiter

func _create_waiter_node() -> Waiter:
	"""Create a waiter node programmatically."""
	var waiter := Waiter.new()
	waiter.name = "Waiter"

	# Create visual mesh
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.height = 1.8
	capsule_mesh.radius = 0.3
	visual.mesh = capsule_mesh
	visual.position = Vector3(0, 0.9, 0)

	# Create collision shape
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.height = 1.8
	capsule_shape.radius = 0.3
	collision.shape = capsule_shape
	collision.position = Vector3(0, 0.9, 0)

	# Create navigation agent
	var nav_agent := NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.avoidance_enabled = true
	nav_agent.radius = 0.5
	nav_agent.height = 1.8
	nav_agent.path_height_offset = 0.5
	nav_agent.path_max_distance = 5.0
	nav_agent.neighbor_distance = 3.0
	nav_agent.max_neighbors = 5
	nav_agent.time_horizon_agents = 1.0
	nav_agent.time_horizon_obstacles = 0.5
	nav_agent.max_speed = 3.0

	# Create held item position marker
	var held_marker := Marker3D.new()
	held_marker.name = "HeldItemPosition"
	held_marker.position = Vector3(0.5, 1.2, -0.5)

	# Add components to waiter
	waiter.add_child(visual)
	waiter.add_child(collision)
	waiter.add_child(nav_agent)
	waiter.add_child(held_marker)

	# Set physics layers
	waiter.collision_layer = 0b1000  # Layer 4: Interactables
	waiter.collision_mask = 0b1  # Layer 1: Environment

	return waiter

func remove_waiter(waiter: Waiter) -> void:
	"""Remove a waiter from the scene."""
	if not waiter or not is_instance_valid(waiter):
		return

	if waiter in active_waiters:
		active_waiters.erase(waiter)

	waiter.queue_free()
	waiter_removed.emit(waiter)

func _on_waiter_removed(waiter: Waiter) -> void:
	"""Called when a waiter is removed from the tree."""
	if waiter in active_waiters:
		active_waiters.erase(waiter)

	# Disconnect signal to prevent memory leaks
	if is_instance_valid(waiter) and waiter.tree_exiting.is_connected(_on_waiter_removed):
		waiter.tree_exiting.disconnect(_on_waiter_removed)

func _find_order_counter() -> Node3D:
	"""Find the order counter in the scene."""
	var counters := get_tree().get_nodes_in_group("order_counter")
	if counters.size() > 0:
		return counters[0]
	return null

func get_waiter_count() -> int:
	"""Returns the number of active waiters."""
	return active_waiters.size()
