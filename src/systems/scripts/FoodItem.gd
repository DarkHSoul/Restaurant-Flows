extends RigidBody3D
class_name FoodItem

## Signals
signal state_changed(food: FoodItem, new_state: CookingState)
signal cooking_progress_updated(food: FoodItem, progress: float)
signal food_burnt(food: FoodItem)

## Cooking states
enum CookingState {
	RAW,           # Not cooked yet
	COOKING,       # Currently cooking
	COOKED,        # Properly cooked
	BURNT,         # Overcooked/burnt
	PREPARED       # Ready to serve (plated)
}

## Food types
enum FoodType {
	PIZZA,
	BURGER,
	PASTA,
	SALAD,
	SOUP,
	STEAK,
	FRIES,
	DRINK
}

## Food properties
@export var food_type: FoodType = FoodType.PIZZA
@export var food_name: String = "Pizza"
@export var cooking_time: float = 15.0  # Seconds to cook
@export var burn_time: float = 25.0     # Seconds until burnt
@export var requires_prep: bool = true   # Needs preparation first
@export var is_pickupable: bool = true

## Visual
@export var raw_color: Color = Color(0.8, 0.6, 0.4)
@export var cooked_color: Color = Color(0.9, 0.7, 0.3)
@export var burnt_color: Color = Color(0.2, 0.1, 0.05)

## Internal state
var _cooking_state: CookingState = CookingState.RAW
var _cooking_progress: float = 0.0
var _is_being_held: bool = false
var _current_station: Node3D = null
var _reserved_by_waiter: Node = null  # Track which waiter has reserved this food for pickup

@onready var _visual: MeshInstance3D = $Visual
@onready var _steam_particles: GPUParticles3D = $SteamParticles

func _ready() -> void:
	collision_layer = 0b100000  # Layer 6: Food (changed to avoid conflict)
	collision_mask = 0b00001    # Layer 1: Environment
	_update_visual()

	if _steam_particles:
		_steam_particles.emitting = false

func _physics_process(delta: float) -> void:
	if _cooking_state == CookingState.COOKING:
		_update_cooking(delta)

## Public interface

func can_interact() -> bool:
	"""Can interact with food when it's on a station (to pick it up)."""
	# Can interact if on a station and not currently cooking
	if _current_station != null and _cooking_state != CookingState.COOKING:
		return true
	return false

func interact(player: Node3D) -> void:
	"""Pick up food from station when player presses E."""
	if _current_station and player.has_method("pickup_item"):
		var station = _current_station
		if station.has_method("remove_food"):
			station.remove_food(self)
		player.pickup_item(self)

func can_pickup() -> bool:
	# Cannot pick up if currently cooking
	if _cooking_state == CookingState.COOKING:
		return false
	# Cannot pick up if on a cooking station (should use station's interact instead)
	if _current_station != null:
		return false
	return is_pickupable and not _is_being_held

func on_picked_up(_picker: Node3D) -> void:
	_is_being_held = true

	# Remove from cooking station
	if _current_station and _current_station.has_method("remove_food"):
		_current_station.remove_food(self)
		_current_station = null

	# Stop cooking
	if _cooking_state == CookingState.COOKING:
		_set_cooking_state(CookingState.RAW)

func on_dropped(_dropper: Node3D) -> void:
	_is_being_held = false

func start_cooking(station: Node3D) -> bool:
	"""Start cooking this food item."""
	print("[FOOD] start_cooking called. Current state: ", _cooking_state, " | requires_prep: ", requires_prep)

	if _cooking_state != CookingState.RAW:
		print("[FOOD] Cannot cook - not in RAW state")
		return false

	if requires_prep and _cooking_state == CookingState.RAW:
		# Needs preparation first
		print("[FOOD] Cannot cook - requires prep")
		return false

	_current_station = station
	_set_cooking_state(CookingState.COOKING)
	_cooking_progress = 0.0

	print("[FOOD] Started cooking! New state: ", _cooking_state)

	if _steam_particles:
		_steam_particles.emitting = true

	return true

func stop_cooking() -> void:
	"""Stop cooking process."""
	if _cooking_state == CookingState.COOKING:
		# Keep current state if cooked, otherwise go back to raw
		if _cooking_progress >= cooking_time:
			_set_cooking_state(CookingState.COOKED)
		else:
			_set_cooking_state(CookingState.RAW)

	if _steam_particles:
		_steam_particles.emitting = false

func prepare() -> void:
	"""Prepare the food (chop, mix, etc.)."""
	if _cooking_state == CookingState.RAW and requires_prep:
		requires_prep = false
		# Could add "PREPARED_RAW" state here

func get_cooking_state() -> CookingState:
	return _cooking_state

func get_cooking_progress() -> float:
	"""Returns 0.0 to 1.0 progress."""
	if _cooking_state != CookingState.COOKING:
		return 0.0
	return clamp(_cooking_progress / cooking_time, 0.0, 1.0)

func get_food_data() -> Dictionary:
	"""Returns food information for order matching."""
	return {
		"type": FoodType.keys()[food_type].to_lower(),
		"name": food_name,
		"state": _cooking_state,
		"is_edible": _cooking_state == CookingState.COOKED
	}

func is_properly_cooked() -> bool:
	return _cooking_state == CookingState.COOKED

func is_burnt() -> bool:
	return _cooking_state == CookingState.BURNT

func reserve_for_waiter(waiter: Node) -> bool:
	"""Reserve this food for a specific waiter. Returns true if successful."""
	if _reserved_by_waiter != null and is_instance_valid(_reserved_by_waiter):
		return false  # Already reserved by another waiter
	_reserved_by_waiter = waiter
	return true

func unreserve() -> void:
	"""Clear waiter reservation."""
	_reserved_by_waiter = null

func is_reserved() -> bool:
	"""Check if this food is reserved by a waiter."""
	return _reserved_by_waiter != null and is_instance_valid(_reserved_by_waiter)

func get_reserved_waiter() -> Node:
	"""Get the waiter who reserved this food."""
	return _reserved_by_waiter

func set_cooked() -> void:
	"""Manually set food to cooked state (for instant-ready foods like salad)."""
	_set_cooking_state(CookingState.COOKED)

## Private methods

func _update_cooking(delta: float) -> void:
	_cooking_progress += delta

	# Check if cooked
	if _cooking_progress >= cooking_time and _cooking_state != CookingState.COOKED:
		_set_cooking_state(CookingState.COOKED)

	# Check if burnt
	if _cooking_progress >= burn_time and _cooking_state != CookingState.BURNT:
		_set_cooking_state(CookingState.BURNT)
		food_burnt.emit(self)

	cooking_progress_updated.emit(self, get_cooking_progress())
	_update_visual()

func _set_cooking_state(new_state: CookingState) -> void:
	if _cooking_state == new_state:
		return

	_cooking_state = new_state
	state_changed.emit(self, _cooking_state)
	_update_visual()

func _update_visual() -> void:
	if not _visual or not _visual.mesh:
		return

	var material := StandardMaterial3D.new()

	match _cooking_state:
		CookingState.RAW:
			material.albedo_color = raw_color
		CookingState.COOKING:
			var progress := get_cooking_progress()
			material.albedo_color = raw_color.lerp(cooked_color, progress)
		CookingState.COOKED:
			material.albedo_color = cooked_color
			material.emission_enabled = true
			material.emission = cooked_color * 0.3
		CookingState.BURNT:
			material.albedo_color = burnt_color
			material.roughness = 0.9
		CookingState.PREPARED:
			material.albedo_color = cooked_color
			material.emission_enabled = true
			material.emission = Color.GOLD * 0.4

	_visual.material_override = material
