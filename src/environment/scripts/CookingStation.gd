extends StaticBody3D
class_name CookingStation

## Base class for all cooking stations (oven, stove, prep counter, etc.)

## Signals
signal food_placed(station: CookingStation, food: FoodItem)
signal food_removed(station: CookingStation, food: FoodItem)
signal cooking_started(station: CookingStation)
signal cooking_finished(station: CookingStation)

## Station types
enum StationType {
	OVEN,
	STOVE,
	PREP_COUNTER,
	SERVING_COUNTER,
	SINK
}

## Station properties
@export var station_type: StationType = StationType.OVEN
@export var station_name: String = "Oven"
@export var can_cook: bool = true
@export var max_items: int = 1
@export var auto_cook: bool = true
@export var cooking_time: float = 5.0  # Default cooking time in seconds

## Visual feedback
@export var highlight_color: Color = Color.YELLOW
@export var active_color: Color = Color.ORANGE

## Internal state
var _placed_foods: Array[FoodItem] = []
var _is_highlighted: bool = false
var _is_cooking: bool = false  # Tracks if ANY food is cooking (updated in _process)
var _interaction_area: Area3D = null
var _cached_material: StandardMaterial3D = null  # Reuse material to prevent memory leaks
var _cooking_sound_player: AudioStreamPlayer3D = null  # For looping cooking sounds
var _steam_particles: GPUParticles3D = null  # Steam effect while cooking

@onready var _visual: MeshInstance3D = $Visual
@onready var _food_position: Marker3D = $FoodPosition
@onready var _light: OmniLight3D = $CookingLight

func _ready() -> void:
	collision_layer = 0b10000  # Layer 4: Interactables
	collision_mask = 0

	# Add to cooking_stations group for order validation
	add_to_group("cooking_stations")

	if _light:
		_light.visible = false

	_setup_interaction_area()
	_setup_cooking_sound()
	_setup_steam_particles()

func _process(delta: float) -> void:
	# Check if ANY food is cooking (foods handle their own timers)
	var any_cooking := false

	for food in _placed_foods:
		if is_instance_valid(food) and food.has_method("get_cooking_state"):
			var food_state = food.get_cooking_state()
			if food_state == 1:  # CookingState.COOKING
				any_cooking = true
				break

	# Update visual state based on whether any food is cooking
	if any_cooking != _is_cooking:
		_is_cooking = any_cooking
		_update_visual()

		# Update light, particles, and sound based on cooking state
		if _is_cooking:
			if _light:
				_light.visible = true
			if _steam_particles:
				_steam_particles.emitting = true
			if _cooking_sound_player and _cooking_sound_player.stream and not _cooking_sound_player.playing:
				_cooking_sound_player.play()
		else:
			if _light:
				_light.visible = false
			if _steam_particles:
				_steam_particles.emitting = false
			if _cooking_sound_player:
				_cooking_sound_player.stop()

## Public interface

func can_interact() -> bool:
	return true

func interact(player: Node3D) -> void:
	"""Called when player presses interact key."""

	# Clean up freed food items
	_placed_foods = _placed_foods.filter(func(f): return is_instance_valid(f))

	if player.has_method("get_held_item"):
		var held_item = player.get_held_item()

		if held_item and held_item is FoodItem:
			# Player is holding food - try to place it
			place_food(held_item, player)
		elif _placed_foods.size() > 0:
			# Player is not holding anything, there's food on the station
			var food: FoodItem = _placed_foods[0]

			# If food is placed but not cooking yet, start cooking (manual cooking stations)
			if not _is_cooking and can_cook and not auto_cook:
				start_cooking()
			# Only allow pickup if NOT currently cooking
			elif not _is_cooking:
				# Pick up the food (either finished cooking, or doesn't need cooking)
				if is_instance_valid(food) and player.has_method("pickup_item"):
					remove_food(food)
					player.pickup_item(food)
			# If cooking, do nothing (player must wait)

func highlight(enabled: bool) -> void:
	"""Highlight station when player looks at it."""
	_is_highlighted = enabled
	_update_visual()

func place_food(food: FoodItem, player: Node3D = null) -> bool:
	"""Place food item on this station."""
	print("[STATION] place_food() called. food: ", food, " | player: ", player)

	if _placed_foods.size() >= max_items:
		print("[STATION] Cannot place - max items reached: ", _placed_foods.size(), "/", max_items)
		return false

	if not _can_accept_food(food):
		print("[STATION] Cannot place - station cannot accept this food type")
		return false

	# Check if there's an active order for this food type
	# Skip validation if placed by Chef (Chef already validated the order)
	var is_chef: bool = player != null and player.is_in_group("chefs")
	print("[STATION] is_chef: ", is_chef, " | player in chefs group: ", player != null and player.is_in_group("chefs"))
	if not is_chef and not _has_active_order_for_food(food):
		print("[STATION] Cannot place - no active order for this food (and placer is not a chef)")
		return false

	# Remove from player if held
	if player and player.has_method("_drop_item"):
		player._drop_item()

	_placed_foods.append(food)

	# Set the station reference on the food
	if food.has_method("set"):
		food._current_station = self

	# Position food on station with vertical offset to prevent overlap
	if _food_position:
		# Calculate vertical offset based on number of existing foods (stack them)
		var food_index := _placed_foods.size() - 1  # Current index (already added to array)
		var offset := Vector3(0, food_index * 0.4, 0)  # Stack vertically
		food.global_position = _food_position.global_position + offset
		food.global_rotation = Vector3.ZERO

	# Freeze food in place and disable collisions to prevent pickup during cooking
	if food is RigidBody3D:
		food.freeze = true
		food.collision_layer = 0  # Disable collision layer to prevent raycast pickup
		food.collision_mask = 0   # Disable collision mask

	food_placed.emit(self, food)

	# Auto start cooking if enabled OR if placed by Chef
	print("[STATION] Food placed! auto_cook: ", auto_cook, " | can_cook: ", can_cook, " | is_chef: ", is_chef, " | About to try start_cooking...")
	if can_cook and (auto_cook or is_chef):
		print("[STATION] Calling start_cooking() from place_food...")
		start_cooking()
	else:
		print("[STATION] NOT calling start_cooking - auto_cook: ", auto_cook, " | can_cook: ", can_cook, " | is_chef: ", is_chef)

	return true

func remove_food(food: FoodItem) -> bool:
	"""Remove food from station."""
	if not food in _placed_foods:
		return false

	_placed_foods.erase(food)

	# Clear station reference on the food
	if food.has_method("set"):
		food._current_station = null

	# Unfreeze food and restore collisions
	if food is RigidBody3D:
		food.freeze = false
		food.collision_layer = 0b100000  # Layer 6: Food
		food.collision_mask = 0b00001    # Layer 1: Environment

	food_removed.emit(self, food)

	# Stop cooking if no more food
	if _placed_foods.is_empty():
		stop_cooking()

	return true

func start_cooking() -> bool:
	"""Start cooking process for newly placed food."""
	print("[STATION] start_cooking() called. can_cook: ", can_cook, " | foods: ", _placed_foods.size())

	if not can_cook or _placed_foods.is_empty():
		print("[STATION] Cannot start cooking - failed precondition")
		return false

	# Clean up any freed food items
	_placed_foods = _placed_foods.filter(func(f): return is_instance_valid(f))

	if _placed_foods.is_empty():
		print("[STATION] No valid foods after filter")
		return false

	print("[STATION] Starting cooking process...")

	# Start cooking for foods that aren't already cooking
	var started_any := false
	for food in _placed_foods:
		if is_instance_valid(food) and food.has_method("start_cooking"):
			if food.has_method("get_cooking_state") and food.get_cooking_state() == 0:  # RAW state
				print("[STATION] Calling start_cooking on food...")
				var success = food.start_cooking(self)
				print("[STATION] start_cooking returned: ", success)
				if success:
					started_any = true

	# Visual effects are now handled in _process based on actual cooking state
	cooking_started.emit(self)

	return started_any

func stop_cooking() -> void:
	"""Stop cooking process for all foods on station."""
	# Stop cooking all foods (check validity first)
	for food in _placed_foods:
		if is_instance_valid(food) and food.has_method("stop_cooking"):
			food.stop_cooking()

	# Visual effects are now handled in _process based on actual cooking state
	cooking_finished.emit(self)


func get_placed_foods() -> Array[FoodItem]:
	return _placed_foods.duplicate()

func get_cooking_foods() -> Array[FoodItem]:
	"""Get all foods currently on this station (including cooking)."""
	return _placed_foods.duplicate()

func is_cooking() -> bool:
	return _is_cooking

func is_available() -> bool:
	return _placed_foods.size() < max_items

func get_station_type() -> String:
	"""Returns station type as string for matching with OrderManager menu."""
	match station_type:
		StationType.OVEN:
			return "oven"
		StationType.STOVE:
			return "stove"
		StationType.PREP_COUNTER:
			return "prep"
		StationType.SERVING_COUNTER:
			return "serving"
		StationType.SINK:
			return "sink"
		_:
			return "unknown"

## Private methods

func _can_accept_food(_food: FoodItem) -> bool:
	"""Check if this station can accept this type of food."""
	# Override in subclasses for specific rules
	return true

func _has_active_order_for_food(food: FoodItem) -> bool:
	"""Check if there's an active order that needs this food type."""
	if not food or not food.has_method("get_food_data"):
		return false

	var food_data := food.get_food_data()
	var food_type: String = food_data.get("type", "")

	if food_type.is_empty():
		return false

	# Find the CustomerSpawner to check active orders
	var spawner: Node = get_tree().get_first_node_in_group("customer_spawner")
	if not spawner or not spawner.has_method("get_active_orders"):
		print("[STATION] Warning: CustomerSpawner not found, allowing food placement")
		return true  # Allow if we can't check (backwards compatibility)

	var active_orders: Array = spawner.get_active_orders()

	# Count how many orders need this food type
	var orders_needing_food: int = 0
	for order in active_orders:
		if order.get("type", "") == food_type:
			orders_needing_food += 1

	# Count how many of this food type are already being cooked in ALL stations
	var foods_being_cooked: int = 0
	var all_stations := get_tree().get_nodes_in_group("cooking_stations")
	for station in all_stations:
		if station and station.has_method("get_placed_foods"):
			var placed: Array[FoodItem] = station.get_placed_foods()
			for placed_food in placed:
				if is_instance_valid(placed_food) and placed_food.has_method("get_food_data"):
					var placed_data := placed_food.get_food_data()
					if placed_data.get("type", "") == food_type:
						foods_being_cooked += 1

	# Allow placement only if there are more orders than foods being cooked
	return foods_being_cooked < orders_needing_food

func _setup_interaction_area() -> void:
	"""Setup area for detecting when player is near."""
	_interaction_area = Area3D.new()
	add_child(_interaction_area)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	shape.shape = sphere
	_interaction_area.add_child(shape)

	_interaction_area.collision_layer = 0
	_interaction_area.collision_mask = 0b00010  # Layer 2: Player

func _update_visual() -> void:
	"""Update visual appearance based on state."""
	if not _visual:
		return

	# Create material once and reuse it to prevent memory leaks
	if not _cached_material:
		var base_material := _visual.get_active_material(0)
		if base_material:
			_cached_material = base_material.duplicate() as StandardMaterial3D
		else:
			_cached_material = StandardMaterial3D.new()

	if _is_cooking:
		_cached_material.emission_enabled = true
		_cached_material.emission = active_color
		_cached_material.emission_energy = 0.5
	elif _is_highlighted:
		_cached_material.emission_enabled = true
		_cached_material.emission = highlight_color
		_cached_material.emission_energy = 0.3
	else:
		_cached_material.emission_enabled = false

	_visual.material_override = _cached_material

func _setup_cooking_sound() -> void:
	"""Create and setup the 3D audio player for cooking sounds."""
	_cooking_sound_player = AudioStreamPlayer3D.new()
	_cooking_sound_player.name = "CookingSound"
	_cooking_sound_player.bus = "SFX"
	_cooking_sound_player.max_distance = 15.0
	_cooking_sound_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_cooking_sound_player)

	# Load appropriate cooking sound based on station type
	var sound_name: String = ""
	match station_type:
		StationType.OVEN:
			sound_name = "cooking_oven"
		StationType.STOVE:
			sound_name = "cooking_sizzle"
		StationType.PREP_COUNTER:
			sound_name = "cooking_chop"
		_:
			sound_name = "cooking_generic"

	# Try to load the sound (with fallback)
	var sound_path := "res://assets/audio/sfx/%s.wav" % sound_name
	if ResourceLoader.exists(sound_path):
		_cooking_sound_player.stream = load(sound_path)
	else:
		sound_path = "res://assets/audio/sfx/%s.ogg" % sound_name
		if ResourceLoader.exists(sound_path):
			_cooking_sound_player.stream = load(sound_path)

	# Make it loop if we have a stream
	if _cooking_sound_player.stream and _cooking_sound_player.stream is AudioStreamWAV:
		(_cooking_sound_player.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD

func _setup_steam_particles() -> void:
	"""Create and setup steam particle effect for cooking."""
	_steam_particles = GPUParticles3D.new()
	_steam_particles.name = "SteamParticles"
	_steam_particles.emitting = false
	_steam_particles.amount = 20
	_steam_particles.lifetime = 2.0
	_steam_particles.explosiveness = 0.0
	_steam_particles.randomness = 0.5
	_steam_particles.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 6, 4))

	# Position above the food position
	if _food_position:
		_steam_particles.position = _food_position.position + Vector3(0, 0.3, 0)
	else:
		_steam_particles.position = Vector3(0, 0.5, 0)

	add_child(_steam_particles)

	# Create particle material
	var particle_material := ParticleProcessMaterial.new()

	# Emission
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_material.emission_sphere_radius = 0.2

	# Direction - upward
	particle_material.direction = Vector3(0, 1, 0)
	particle_material.spread = 15.0
	particle_material.initial_velocity_min = 0.5
	particle_material.initial_velocity_max = 1.0

	# Gravity
	particle_material.gravity = Vector3(0, 0.5, 0)  # Slight upward drift

	# Scale over lifetime (start small, grow, then fade)
	particle_material.scale_min = 0.1
	particle_material.scale_max = 0.3

	# Color fade (white steam that fades to transparent)
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 1, 0.8))  # Start opaque white
	gradient.add_point(0.5, Color(0.9, 0.9, 1, 0.5))  # Middle slightly blue-tinted
	gradient.add_point(1.0, Color(1, 1, 1, 0))  # End transparent

	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	particle_material.color_ramp = gradient_texture

	_steam_particles.process_material = particle_material

	# Create visual mesh for particles (small spheres)
	var particle_mesh := SphereMesh.new()
	particle_mesh.radial_segments = 8
	particle_mesh.rings = 4
	particle_mesh.radius = 0.1
	particle_mesh.height = 0.2

	# Create material for the particle mesh
	var mesh_material := StandardMaterial3D.new()
	mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_material.albedo_color = Color(1, 1, 1, 0.6)
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particle_mesh.material = mesh_material

	_steam_particles.draw_pass_1 = particle_mesh
