extends CharacterBody3D
class_name PlayerController

## Signals
signal item_picked_up(item: Node3D)
signal item_dropped(item: Node3D)
signal interacted_with(target: Node3D)

## Movement parameters
@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var acceleration: float = 10.0
@export var deceleration: float = 12.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.003

## Interaction parameters
@export_group("Interaction")
@export var interaction_range: float = 2.5
@export var pickup_offset: Vector3 = Vector3(0.5, 0.5, -0.8)

## References
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var interaction_raycast: RayCast3D = $CameraPivot/Camera3D/InteractionRay
@onready var held_item_position: Marker3D = $CameraPivot/Camera3D/HeldItemPosition

## Internal state
var held_item: Node3D = null
var current_interactable: Node3D = null
var camera_rotation: Vector2 = Vector2.ZERO
var interaction_prompt: Label3D = null
var _last_debug_object: Node3D = null  # Track last debug printed object to avoid spam
var controls_enabled: bool = true  # For disabling during build mode

## Hold-to-interact state
var is_holding_interact: bool = false
var interaction_progress_bar = null  # InteractionProgressBar reference

func _ready() -> void:
	# Add to player group for easy finding
	add_to_group("player")

	# Don't capture mouse initially - wait for game to start
	# (MainMenu will show first)

	# Connect to game_started signal
	await get_tree().process_frame
	if GameManager.instance:
		GameManager.instance.game_started.connect(_on_game_started)

	# Setup interaction raycast
	if interaction_raycast:
		interaction_raycast.target_position = Vector3(0, 0, -interaction_range)
		# Layer 4 (0b10000 = 16) + Layer 5 (0b100000 = 32) + Layer 6 (0b1000000 = 64)
		# Total: 16 + 32 + 64 = 112 = 0b1110000
		interaction_raycast.collision_mask = 0b1110000  # Layers 4, 5, 6: Interactables + Food
		print("[DEBUG] Raycast collision_mask set to: ", interaction_raycast.collision_mask, " (binary: ", String.num_int64(interaction_raycast.collision_mask, 2), ")")

	# Find interaction progress bar from HUD
	await get_tree().process_frame
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_node("InteractionProgressBar"):
		interaction_progress_bar = hud.get_node("InteractionProgressBar")
		if interaction_progress_bar and interaction_progress_bar.has_signal("interaction_completed"):
			interaction_progress_bar.interaction_completed.connect(_on_interaction_completed)

	# Create interaction prompt
	_create_interaction_prompt()

func _create_interaction_prompt() -> void:
	"""Create a Label3D to show interaction prompts."""
	interaction_prompt = Label3D.new()
	interaction_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	interaction_prompt.font_size = 64
	interaction_prompt.outline_size = 12
	interaction_prompt.modulate = Color(1, 1, 1, 1)
	interaction_prompt.outline_modulate = Color(0, 0, 0, 1)
	interaction_prompt.visible = false
	interaction_prompt.pixel_size = 0.004
	interaction_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Make hint text always render on top (ignore depth testing)
	interaction_prompt.no_depth_test = true
	interaction_prompt.render_priority = 10  # Higher priority = rendered later = on top
	add_child(interaction_prompt)

func _input(event: InputEvent) -> void:
	# Disable all input if controls are disabled (build mode, etc.)
	if not controls_enabled:
		return

	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_rotation.x -= event.relative.y * mouse_sensitivity
		camera_rotation.y -= event.relative.x * mouse_sensitivity
		camera_rotation.x = clamp(camera_rotation.x, -PI/2.5, PI/2.5)

	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Interaction (removed - now handled in _physics_process for hold detection)

	# Pickup/Drop
	if event.is_action_pressed("pickup"):
		if held_item:
			_drop_item()
		else:
			_try_pickup()

func _physics_process(delta: float) -> void:
	# Disable physics processing if controls are disabled
	if not controls_enabled:
		return

	# Only update camera and movement when game is playing
	var game_manager = GameManager.instance
	var is_playing = game_manager and game_manager.current_state == GameManager.GameState.PLAYING

	# Always allow camera rotation and movement - let input determine when to respond
	_update_camera_rotation()
	_handle_movement(delta)

	# Only do interactions when playing
	if is_playing:
		_update_interaction_highlight()
		_update_held_item_position()
		_handle_hold_to_interact()

func _update_camera_rotation() -> void:
	if camera_pivot:
		camera_pivot.rotation.x = camera_rotation.x
		rotation.y = camera_rotation.y

func _handle_movement(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Get input direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	# Calculate movement direction relative to camera
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Determine speed
	var target_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed

	# Apply movement
	if direction:
		var target_velocity := direction * target_speed
		velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)

	move_and_slide()

func _update_interaction_highlight() -> void:
	if not interaction_raycast:
		return

	# Debug raycast setup
	if not interaction_raycast.enabled:
		print("[DEBUG] Raycast is disabled!")
		return

	if not interaction_raycast.is_colliding():
		if _last_debug_object != null:
			_last_debug_object = null
		_clear_interactable()
		return

	var collider := interaction_raycast.get_collider()

	# Only print debug when we look at a new object
	if collider != _last_debug_object:
		_last_debug_object = collider
		print("[DEBUG] Raycast hit: ", collider.name if collider else "null",
			  " | Type: ", collider.get_class() if collider else "null",
			  " | Layer: ", collider.collision_layer if collider else "null")

	# Check if this is a door pivot that references a parent door
	var actual_interactable := collider
	if collider and collider.has_meta("parent_door"):
		actual_interactable = collider.get_meta("parent_door")

	if actual_interactable and actual_interactable.has_method("can_interact"):
		# Check if we can actually interact with this object
		var can_interact: bool = actual_interactable.can_interact()

		# Special case for tables - only interactable if holding food
		if actual_interactable is Table:
			var was_interactable: bool = can_interact
			can_interact = can_interact and held_item != null and held_item is FoodItem
			if not can_interact and was_interactable and collider != _last_debug_object:
				print("[DEBUG TABLE] Table can_interact but player not holding food. Held item: ", held_item)

		if can_interact:
			if actual_interactable != current_interactable:
				_clear_interactable()
				current_interactable = actual_interactable
				if current_interactable.has_method("highlight"):
					current_interactable.highlight(true)

				# Show interaction prompt
				_show_interaction_prompt(actual_interactable)
				print("[DEBUG] Set interactable: ", current_interactable.name)
		else:
			if collider != _last_debug_object and actual_interactable is Table:
				print("[DEBUG TABLE] Clearing table interactable - can_interact: ", actual_interactable.can_interact(), " holding food: ", held_item != null and held_item is FoodItem)
			_clear_interactable()
	else:
		if collider != null:
			print("[DEBUG] No can_interact method on: ", collider.name)
		_clear_interactable()

func _show_interaction_prompt(interactable: Node3D) -> void:
	"""Show the interaction prompt above the interactable."""
	if not interaction_prompt:
		return

	# Determine the action text with machine/object name
	var action_text := "[E] Interact"
	if interactable is Customer:
		action_text = "[E] Take Order"
	elif interactable is CookingStation:
		var station_name: String = interactable.station_name if "station_name" in interactable else "Station"
		if held_item:
			action_text = "[E] Place on %s" % station_name
		else:
			action_text = "[E] Use %s" % station_name
	elif interactable is Table:
		var table_num: int = interactable.table_number if "table_number" in interactable else 0
		action_text = "[E] Serve to Table #%d" % table_num
	elif interactable is FoodItem:
		var food_name: String = ""
		if interactable.has_method("get_food_data"):
			var food_data: Dictionary = interactable.get_food_data()
			food_name = food_data.get("name", "Food")
		else:
			food_name = "Food"
		action_text = "[Click] Pick Up %s" % food_name
	elif interactable is Door:
		if interactable.is_open:
			action_text = "[E] Close Door"
		else:
			action_text = "[E] Open Door"

	interaction_prompt.text = action_text
	# Position prompt at different heights for better visibility
	var prompt_height := 0.5
	if interactable is CookingStation or interactable is Table:
		prompt_height = 0.8
	elif interactable is Door:
		prompt_height = 1.0
	elif interactable is FoodItem:
		prompt_height = 0.3

	interaction_prompt.global_position = interactable.global_position + Vector3(0, prompt_height, 0)
	interaction_prompt.visible = true

func _clear_interactable() -> void:
	if current_interactable and current_interactable.has_method("highlight"):
		current_interactable.highlight(false)
	current_interactable = null

	# Hide interaction prompt
	if interaction_prompt:
		interaction_prompt.visible = false

func _try_interact() -> void:
	print("[DEBUG] _try_interact() called. Current interactable: ", current_interactable.name if current_interactable else "null")
	if current_interactable and current_interactable.has_method("interact"):
		print("[DEBUG] Calling interact() on: ", current_interactable.name)
		current_interactable.interact(self)
		interacted_with.emit(current_interactable)
	else:
		print("[DEBUG] Cannot interact - no current_interactable or no interact method")

func _try_pickup() -> void:
	if not interaction_raycast or not interaction_raycast.is_colliding():
		return

	var collider := interaction_raycast.get_collider()
	if collider and collider.has_method("can_pickup") and collider.can_pickup():
		_pickup_item(collider)

func _pickup_item(item: Node3D) -> void:
	print("[DEBUG PLAYER] _pickup_item called for: ", item.name if item else "null")
	if held_item:
		print("[DEBUG PLAYER] Cannot pick up - already holding: ", held_item.name)
		return

	held_item = item
	print("[DEBUG PLAYER] Picked up item: ", item.name)

	# Disable physics
	if item is RigidBody3D:
		item.freeze = true
		item.collision_layer = 0
		item.collision_mask = 0
	elif item is StaticBody3D or item is CharacterBody3D:
		item.collision_layer = 0
		item.collision_mask = 0

	# Notify item
	if item.has_method("on_picked_up"):
		item.on_picked_up(self)

	item_picked_up.emit(item)

func _drop_item() -> void:
	if not held_item:
		return

	var item := held_item
	held_item = null

	# Re-enable physics
	if item is RigidBody3D:
		item.freeze = false
		item.collision_layer = 0b100000  # Layer 6: Food
		item.collision_mask = 0b00001    # Layer 1: Environment

		# Add small forward velocity
		var drop_velocity := -camera.global_transform.basis.z * 2.0
		item.linear_velocity = drop_velocity
	elif item is StaticBody3D or item is CharacterBody3D:
		item.collision_layer = 0b100000
		item.collision_mask = 0b00001

	# Notify item
	if item.has_method("on_dropped"):
		item.on_dropped(self)

	item_dropped.emit(item)

func _update_held_item_position() -> void:
	if not held_item or not held_item_position:
		return

	# Smoothly move item to held position
	var target_pos := held_item_position.global_position
	var target_rot := held_item_position.global_rotation

	held_item.global_position = held_item.global_position.lerp(target_pos, 0.3)
	held_item.global_rotation = lerp(held_item.global_rotation, target_rot, 0.3)

func get_held_item() -> Node3D:
	return held_item

func has_item() -> bool:
	return held_item != null

func drop_item() -> void:
	"""Public method to drop the currently held item."""
	_drop_item()

func pickup_item(item: Node3D) -> void:
	"""Public method to pick up an item."""
	_pickup_item(item)

## Hold-to-interact methods

func _handle_hold_to_interact() -> void:
	"""Handle hold-to-interact logic for customers."""
	if not current_interactable:
		# No interactable object, hide progress if showing
		if is_holding_interact:
			is_holding_interact = false
			if interaction_progress_bar:
				interaction_progress_bar.set_holding(false)
		return

	# Check if this is a customer that requires hold-to-interact
	var requires_hold: bool = current_interactable.has_method("requires_hold_interaction") and current_interactable.requires_hold_interaction()

	if not requires_hold:
		# This object doesn't need hold interaction, use instant interaction
		if Input.is_action_just_pressed("interact"):
			_try_interact()
		return

	# This object requires hold interaction
	var is_pressing: bool = Input.is_action_pressed("interact")

	if is_pressing and not is_holding_interact:
		# Start holding
		is_holding_interact = true
		if interaction_progress_bar:
			var action_text: String = "Taking Order"
			if current_interactable.has_method("get_interaction_text"):
				action_text = current_interactable.get_interaction_text()
			interaction_progress_bar.start_interaction(current_interactable, action_text)
			interaction_progress_bar.set_holding(true)

	elif is_pressing and is_holding_interact:
		# Continue holding
		if interaction_progress_bar:
			interaction_progress_bar.set_holding(true)

	elif not is_pressing and is_holding_interact:
		# Released the key
		is_holding_interact = false
		if interaction_progress_bar:
			interaction_progress_bar.set_holding(false)

func _on_game_started() -> void:
	"""Called when the game starts - capture mouse for first-person control."""
	print("[PLAYER] Game started - capturing mouse")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Reset player velocity to prevent jumping on game start
	velocity = Vector3.ZERO

	# Ensure player is on the ground
	if not is_on_floor():
		# Apply a small downward force to snap to ground
		velocity.y = -1.0

func _on_interaction_completed(target: Node3D) -> void:
	"""Called when hold-to-interact completes."""
	print("[DEBUG] Interaction completed with: ", target.name if target else "null")
	is_holding_interact = false

	if target and target.has_method("interact"):
		target.interact(self)
		interacted_with.emit(target)

func set_controls_enabled(enabled: bool) -> void:
	"""Enable or disable player controls (for build mode, menus, etc.)."""
	controls_enabled = enabled
	print("[PLAYER] Controls %s" % ("enabled" if enabled else "disabled"))

## ===== SAVE/LOAD SYSTEM =====

func get_save_data() -> Dictionary:
	"""Returns player state as a Dictionary for saving."""
	var data := {}

	# Position and rotation
	data["position"] = global_position
	data["rotation_y"] = rotation.y
	data["camera_rotation"] = camera_rotation

	# Held item data
	if held_item:
		# Check if held item is a FoodItem
		if held_item is FoodItem:
			var food: FoodItem = held_item as FoodItem
			data["held_food"] = {
				"type": food.food_type,
				"state": food._cooking_state if food.has_method("get") else 0,
				"cooking_progress": food._cooking_progress if food.has_method("get") else 0.0
			}
		else:
			data["held_food"] = null
	else:
		data["held_food"] = null

	print("[PLAYER] Save data created - Position: %v, Held: %s" % [global_position, "yes" if held_item else "no"])
	return data

func apply_save_data(data: Dictionary) -> void:
	"""Restores player state from saved Dictionary."""
	if not data:
		push_warning("[PLAYER] No save data to apply")
		return

	# Restore position and rotation
	global_position = data.get("position", Vector3.ZERO)
	rotation.y = data.get("rotation_y", 0.0)
	camera_rotation = data.get("camera_rotation", Vector2.ZERO)

	# Apply camera rotation
	if camera_pivot:
		camera_pivot.rotation.x = camera_rotation.y
	rotation.y = camera_rotation.x

	# Restore held item (if any)
	var held_food_data = data.get("held_food", null)
	if held_food_data:
		# Need to wait a frame for the scene to be fully ready
		await get_tree().process_frame
		_restore_held_food(held_food_data)

	print("[PLAYER] Save data applied - Position: %v" % global_position)

func _restore_held_food(food_data: Dictionary) -> void:
	"""Helper to restore held food item."""
	# Get food type
	var food_type: int = food_data.get("type", 0)  # Default to PIZZA (0)

	# Load the appropriate scene based on food type
	var food_scene: PackedScene
	match food_type:
		0:  # PIZZA
			food_scene = preload("res://src/systems/scenes/FoodPizza.tscn")
		1:  # BURGER
			food_scene = preload("res://src/systems/scenes/FoodBurger.tscn")
		2:  # PASTA
			food_scene = preload("res://src/systems/scenes/FoodPasta.tscn")
		3:  # SALAD
			food_scene = preload("res://src/systems/scenes/FoodSalad.tscn")
		4:  # SOUP
			food_scene = preload("res://src/systems/scenes/FoodSoup.tscn")
		_:
			food_scene = preload("res://src/systems/scenes/FoodPizza.tscn")

	var food := food_scene.instantiate() as FoodItem
	if not food:
		push_error("[PLAYER] Failed to create FoodItem for restore")
		return

	# Add to scene first
	get_tree().root.add_child(food)

	# Then set state (needs to be in scene tree)
	if food_data.has("state"):
		food._cooking_state = food_data.get("state", 0)
	if food_data.has("cooking_progress"):
		food._cooking_progress = food_data.get("cooking_progress", 0.0)

	# Pick up the food
	_pickup_item(food)

	print("[PLAYER] Restored held food: type=%d, state=%d" % [food.food_type, food._cooking_state])
