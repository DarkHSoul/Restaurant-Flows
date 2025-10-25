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

func _ready() -> void:
	# Capture mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Setup interaction raycast
	if interaction_raycast:
		interaction_raycast.target_position = Vector3(0, 0, -interaction_range)
		# Layer 4 (0b10000 = 16) + Layer 5 (0b100000 = 32) + Layer 6 (0b1000000 = 64)
		# Total: 16 + 32 + 64 = 112 = 0b1110000
		interaction_raycast.collision_mask = 0b1110000  # Layers 4, 5, 6: Interactables + Food
		print("[DEBUG] Raycast collision_mask set to: ", interaction_raycast.collision_mask, " (binary: ", String.num_int64(interaction_raycast.collision_mask, 2), ")")

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

	# Interaction
	if event.is_action_pressed("interact"):
		_try_interact()

	# Pickup/Drop
	if event.is_action_pressed("pickup"):
		if held_item:
			_drop_item()
		else:
			_try_pickup()

func _physics_process(delta: float) -> void:
	_update_camera_rotation()
	_handle_movement(delta)
	_update_interaction_highlight()
	_update_held_item_position()

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
	if interactable is CookingStation:
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
