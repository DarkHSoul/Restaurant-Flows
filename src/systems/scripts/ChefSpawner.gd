extends Node
class_name ChefSpawner

## Manages chef spawning and tracking

## Signals
signal chef_spawned(chef: Chef)
signal chef_removed(chef: Chef)

## Configuration
@export var chef_scene: PackedScene
@export var spawn_position: Vector3 = Vector3.ZERO  # Use ZERO to auto-calculate position
@export var storage_position: Vector3 = Vector3.ZERO  # Where chefs pick up ingredients
@export var max_chefs: int = 3
@export var auto_spawn_initial_chefs: bool = true
@export var initial_chef_count: int = 1

## State
var active_chefs: Array[Chef] = []

func _ready() -> void:
	print("[CHEF_SPAWNER] Ready called!")
	# If no scene assigned, try to load default
	if not chef_scene:
		print("[CHEF_SPAWNER] No chef scene assigned, loading default...")
		chef_scene = load("res://src/characters/scenes/Chef.tscn")
		if chef_scene:
			print("[CHEF_SPAWNER] Chef scene loaded successfully!")
		else:
			print("[CHEF_SPAWNER] ERROR: Failed to load chef scene!")
			return

	print("[CHEF_SPAWNER] Auto spawn: ", auto_spawn_initial_chefs, " | Initial count: ", initial_chef_count)

	# Auto spawn initial chefs (but not when loading a save)
	if auto_spawn_initial_chefs:
		# Check if SaveManager is loading
		if SaveManager.instance and SaveManager.instance.is_loading_save:
			print("[CHEF_SPAWNER] Skipping auto-spawn (SaveManager is loading)")
		else:
			call_deferred("_spawn_initial_chefs")

func _spawn_initial_chefs() -> void:
	"""Spawn initial chefs on game start."""
	print("[CHEF_SPAWNER] _spawn_initial_chefs called! Spawning ", initial_chef_count, " chefs")
	for i in range(initial_chef_count):
		print("[CHEF_SPAWNER] Spawning chef ", i + 1, "/", initial_chef_count)
		var chef = spawn_chef()
		if chef:
			print("[CHEF_SPAWNER] Successfully spawned chef ", i + 1)
		else:
			print("[CHEF_SPAWNER] Failed to spawn chef ", i + 1)

		if not is_inside_tree():
			return

		await get_tree().create_timer(0.1).timeout  # Small delay between spawns

		if not is_inside_tree():
			return

func _input(event: InputEvent) -> void:
	# Listen for F10 key press to spawn chef (F8 conflicts with Godot editor stop)
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_F10:
			spawn_chef()

func spawn_chef() -> Chef:
	"""Spawn a new chef at the spawn position."""
	print("[CHEF_SPAWNER] spawn_chef() called")
	# Check max chefs
	if active_chefs.size() >= max_chefs:
		print("[CHEF_SPAWNER] Max chefs reached: ", active_chefs.size(), "/", max_chefs)
		return null

	var chef: Chef = null

	# Try to instance from scene
	if chef_scene:
		chef = chef_scene.instantiate()
	else:
		# Create chef programmatically
		chef = _create_chef_node()

	if not chef:
		print("[CHEF_SPAWNER] ERROR: Failed to create chef!")
		return null

	print("[CHEF_SPAWNER] Chef instance created successfully")

	# Add to scene - use a safer parent
	var scene_root = get_tree().current_scene
	if scene_root:
		scene_root.add_child(chef)
		print("[CHEF_SPAWNER] Chef added to scene tree")
	else:
		print("[CHEF_SPAWNER] ERROR: Could not find scene root!")
		chef.queue_free()
		return null

	# Position chef
	var spawn_pos := spawn_position
	if spawn_pos == Vector3.ZERO:
		# Try to find a good spawn position near the kitchen/cooking stations
		var station := _find_nearest_cooking_station()
		if station:
			# Spawn near kitchen area
			var kitchen_offset := station.global_transform.basis * Vector3(2.0, 0, 0)
			spawn_pos = station.global_position + kitchen_offset
			spawn_pos.y = 0.0  # Start on the ground
		else:
			spawn_pos = Vector3(0, 0, 0)

	chef.global_position = spawn_pos
	chef.set_idle_position(spawn_pos)

	# Set storage position if provided
	if storage_position != Vector3.ZERO:
		chef.set_storage_position(storage_position)
	else:
		# Try to find storage area
		var storage := _find_storage_area()
		if storage:
			chef.set_storage_position(storage.global_position)

	# Track chef
	active_chefs.append(chef)

	# Add to group for easy finding
	chef.add_to_group("chefs")

	# Connect signals
	chef.tree_exiting.connect(_on_chef_removed.bind(chef))

	print("[CHEF_SPAWNER] Chef spawned successfully at: ", spawn_pos)
	chef_spawned.emit(chef)
	return chef

func _create_chef_node() -> Chef:
	"""Create a chef node programmatically."""
	var chef := Chef.new()
	chef.name = "Chef"

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
	nav_agent.max_speed = 3.5

	# Create held item position marker
	var held_marker := Marker3D.new()
	held_marker.name = "HeldItemPosition"
	held_marker.position = Vector3(0.5, 1.2, -0.5)

	# Add components to chef
	chef.add_child(visual)
	chef.add_child(collision)
	chef.add_child(nav_agent)
	chef.add_child(held_marker)

	# Set physics layers
	chef.collision_layer = 0b1000  # Layer 4: Interactables
	chef.collision_mask = 0b1  # Layer 1: Environment

	return chef

func remove_chef(chef: Chef) -> void:
	"""Remove a chef from the scene."""
	if not chef or not is_instance_valid(chef):
		return

	if chef in active_chefs:
		active_chefs.erase(chef)

	chef.queue_free()
	chef_removed.emit(chef)

func _on_chef_removed(chef: Chef) -> void:
	"""Called when a chef is removed from the tree."""
	if chef in active_chefs:
		active_chefs.erase(chef)

	# Disconnect signal to prevent memory leaks
	if is_instance_valid(chef) and chef.tree_exiting.is_connected(_on_chef_removed):
		chef.tree_exiting.disconnect(_on_chef_removed)

func _find_nearest_cooking_station() -> Node3D:
	"""Find the nearest cooking station in the scene."""
	var stations := get_tree().get_nodes_in_group("cooking_stations")
	if stations.size() > 0:
		return stations[0]
	return null

func _find_storage_area() -> Node3D:
	"""Find the storage area in the scene."""
	var storage_areas := get_tree().get_nodes_in_group("food_spawner")
	if storage_areas.size() > 0:
		return storage_areas[0]
	return null

func get_chef_count() -> int:
	"""Returns the number of active chefs."""
	return active_chefs.size()
