extends Node
class_name BuildModeManager

## Build Mode Manager - Handles automatic zone-based placement system
## Activated by pressing Tab key, instantly places items in appropriate zones

## Signals
signal build_mode_entered()
signal build_mode_exited()
signal item_placed(item_type: String, position: Vector3, rotation: float)
signal item_removed(item_type: String, position: Vector3)
signal item_purchased(item_type: String)
signal zone_changed(new_zone: int)

## Zones
enum Zone { DINING, KITCHEN }

## Zone names (icon + Turkish)
const ZONE_NAMES := {
	Zone.DINING: "🍽️ Yemek Salonu",
	Zone.KITCHEN: "🍳 Mutfak"
}

## Zone-specific categories
const ZONE_CATEGORIES := {
	Zone.DINING: ["furniture", "utility", "premium"],
	Zone.KITCHEN: ["kitchen", "utility", "premium"]
}

## Singleton
static var instance: BuildModeManager

## State
var is_build_mode_active: bool = false
var is_transitioning: bool = false
var current_zone: Zone = Zone.DINING

## Item removal/hover
var hovered_item: Node3D = null
var hover_highlight: Node3D = null

## References
var game_manager: GameManager
var economy_manager: EconomyManager
var player_controller: Node3D  # PlayerController
var first_person_camera: Camera3D
var dining_build_camera: Camera3D
var kitchen_build_camera: Camera3D
var zone_cameras: Dictionary = {}  # Zone → Camera3D mapping
var build_mode_shop_ui: CanvasLayer  # BuildModeShopUI is a CanvasLayer
var build_mode_upgrades_ui: CanvasLayer  # BuildModeUpgradesUI is a CanvasLayer
var zone_selector_ui: CanvasLayer  # ZoneSelectorUI
var navigation_region: NavigationRegion3D = null  # For proper parent assignment

## Placement tracking
var placed_items: Dictionary = {
	"oven": [],
	"stove": [],
	"prep_counter": [],
	"table": [],
	"trash_bin": [],
	"serving_counter": []
}

## Permanent items (cannot be removed) - initial scene objects
var permanent_items: Array[Node3D] = []

## Zone system - defines where each item type goes
const ITEM_ZONES := {
	"oven": "kitchen",
	"stove": "kitchen",
	"prep_counter": "kitchen",
	"serving_counter": "kitchen",
	"table": "dining",
	"trash_bin": "storage"
}

## Zone markers (will be found in scene)
var zone_centers: Dictionary = {}  # "kitchen": Vector3, "dining": Vector3, "storage": Vector3

## Placement spacing
const PLACEMENT_SPACING: float = 2.5  # Meters between auto-placed items (tables need more space)

## Error message state
var error_message: String = ""
var error_message_timer: float = 0.0

func _ready() -> void:
	if instance and instance != self:
		queue_free()
		return

	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Find managers
	game_manager = GameManager.instance
	if game_manager:
		economy_manager = game_manager.economy_manager

	# Find NavigationRegion3D - CRITICAL for proper object functionality
	navigation_region = get_tree().get_first_node_in_group("navigation_region")
	if not navigation_region:
		# Fallback: search by node name in Main3D
		var main_scene := get_tree().current_scene
		if main_scene:
			navigation_region = main_scene.get_node_or_null("NavigationRegion3D")

	if navigation_region:
		print("[BUILD_MODE] Found NavigationRegion3D - objects will be functional!")
	else:
		push_error("[BUILD_MODE] NavigationRegion3D not found! Placed objects won't work with AI!")

	# Find zone centers
	_find_zone_centers()

	# Find cameras
	_find_cameras()

	# Find UI references
	_find_ui_references()

	# Connect to signals
	item_placed.connect(_on_item_placed)

	print("[BUILD_MODE] BuildModeManager ready!")

func _find_zone_centers() -> void:
	"""Find zone marker nodes in the scene."""
	# Look for zone markers by group or name
	var kitchen_zone := get_tree().get_first_node_in_group("kitchen_zone")
	if kitchen_zone and kitchen_zone is Node3D:
		zone_centers["kitchen"] = kitchen_zone.global_position
		print("[BUILD_MODE] Found kitchen zone at: %v" % zone_centers["kitchen"])

	var dining_zone := get_tree().get_first_node_in_group("dining_zone")
	if dining_zone and dining_zone is Node3D:
		zone_centers["dining"] = dining_zone.global_position
		print("[BUILD_MODE] Found dining zone at: %v" % zone_centers["dining"])

	var storage_zone := get_tree().get_first_node_in_group("storage_zone")
	if storage_zone and storage_zone is Node3D:
		zone_centers["storage"] = storage_zone.global_position
		print("[BUILD_MODE] Found storage zone at: %v" % zone_centers["storage"])

	# Fallback: use default positions if zones not found
	if zone_centers.is_empty():
		print("[BUILD_MODE] WARNING: No zone markers found! Using default positions.")
		zone_centers["kitchen"] = Vector3(-5, 0, -5)
		zone_centers["dining"] = Vector3(5, 0, 5)
		zone_centers["storage"] = Vector3(0, 0, -8)

func _find_cameras() -> void:
	"""Find build mode cameras."""
	# Find dining camera
	dining_build_camera = get_tree().get_first_node_in_group("dining_build_camera")
	if dining_build_camera:
		zone_cameras[Zone.DINING] = dining_build_camera
		print("[BUILD_MODE] Found dining build camera")

	# Find kitchen camera
	kitchen_build_camera = get_tree().get_first_node_in_group("kitchen_build_camera")
	if kitchen_build_camera:
		zone_cameras[Zone.KITCHEN] = kitchen_build_camera
		print("[BUILD_MODE] Found kitchen build camera")

	if zone_cameras.is_empty():
		push_error("[BUILD_MODE] No build mode cameras found!")

func _find_ui_references() -> void:
	"""Find UI references."""
	# Find player controller and first-person camera
	player_controller = get_tree().get_first_node_in_group("player")
	if player_controller:
		var camera_pivot = player_controller.get_node_or_null("CameraPivot")
		if camera_pivot:
			first_person_camera = camera_pivot.get_node_or_null("Camera3D")
			if first_person_camera:
				print("[BUILD_MODE] Found first-person camera")

	# Find shop UI
	build_mode_shop_ui = get_tree().get_first_node_in_group("build_mode_shop")
	if build_mode_shop_ui:
		print("[BUILD_MODE] Found build mode shop UI")

	# Find upgrades UI
	build_mode_upgrades_ui = get_tree().get_first_node_in_group("build_mode_upgrades")
	if build_mode_upgrades_ui:
		print("[BUILD_MODE] Found build mode upgrades UI")

	# Find zone selector UI
	await get_tree().process_frame  # Wait for ZoneSelectorUI to be ready
	zone_selector_ui = get_node_or_null("/root/Main3D/ZoneSelectorUI")
	if zone_selector_ui:
		print("[BUILD_MODE] Found zone selector UI")
		# Connect zone change signal
		if zone_selector_ui.has_signal("zone_changed"):
			zone_selector_ui.zone_changed.connect(_on_zone_selector_changed)
	else:
		push_warning("[BUILD_MODE] Zone selector UI not found!")

func _input(event: InputEvent) -> void:
	# Build mode toggle - now using toggle_shop (Tab) to enter, ESC to exit
	if event.is_action_pressed("toggle_shop") and not is_transitioning:
		if is_build_mode_active:
			# In build mode: Tab cycles zones
			_cycle_zone()
		else:
			# Not in build mode: Tab enters build mode
			enter_build_mode()
		get_viewport().set_input_as_handled()

	# Build mode controls (only when active and not transitioning)
	if is_build_mode_active and not is_transitioning:
		if event.is_action_pressed("ui_cancel"):
			# ESC exits build mode
			exit_build_mode()
			get_viewport().set_input_as_handled()

		# Left/Right arrow keys for zone switching
		if event.is_action_pressed("ui_left"):
			_cycle_zone()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_right"):
			_cycle_zone()
			get_viewport().set_input_as_handled()

		# Left click - Forward to UI for shop interactions
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var mouse_pos := get_viewport().get_mouse_position()
			var screen_width := get_viewport().get_visible_rect().size.x
			var is_over_left_ui := mouse_pos.x < 350  # Left sidebar (shop)
			var is_over_right_ui := mouse_pos.x > (screen_width - 350)  # Right sidebar (upgrades)

			if is_over_left_ui:
				# Forward click to shop UI (needed because pause mode blocks normal input)
				if build_mode_shop_ui and build_mode_shop_ui.has_method("_handle_click"):
					build_mode_shop_ui._handle_click(mouse_pos)
					get_viewport().set_input_as_handled()
			elif is_over_right_ui:
				# Forward click to upgrades UI
				if build_mode_upgrades_ui and build_mode_upgrades_ui.has_method("_handle_click"):
					build_mode_upgrades_ui._handle_click(mouse_pos)
					get_viewport().set_input_as_handled()

		# Right click - Forward to shop UI for item removal OR remove hovered item
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var mouse_pos := get_viewport().get_mouse_position()
			var is_over_left_ui := mouse_pos.x < 350  # Left sidebar (shop)

			if is_over_left_ui:
				# Forward right-click to shop UI for removing last placed item
				if build_mode_shop_ui and build_mode_shop_ui.has_method("_handle_right_click"):
					build_mode_shop_ui._handle_right_click(mouse_pos)
					get_viewport().set_input_as_handled()
			elif hovered_item:
				# Remove the hovered item with 50% refund (world right-click)
				remove_item(hovered_item)
				get_viewport().set_input_as_handled()

func enter_build_mode() -> void:
	"""Enter build mode with smooth camera transition - always starts at Dining zone."""
	if is_build_mode_active or is_transitioning:
		return

	print("[BUILD_MODE] Entering build mode...")
	is_transitioning = true

	# Check cameras
	if not first_person_camera or zone_cameras.is_empty():
		push_error("[BUILD_MODE] Cameras not found! Cannot enter build mode.")
		is_transitioning = false
		return

	# Set initial zone to Dining Room
	current_zone = Zone.DINING

	# Pause the game
	if game_manager:
		game_manager.current_state = GameManager.GameState.BUILD_MODE
		get_tree().paused = true

	# Disable player controller
	if player_controller and player_controller.has_method("set_controls_enabled"):
		player_controller.set_controls_enabled(false)

	# Show mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Smooth camera transition (1.0 seconds)
	await _transition_to_build_camera(current_zone)

	# Scan for existing objects to track
	scan_existing_objects()

	# Show build mode UI with zone-specific categories (hidden initially for fade-in)
	if build_mode_shop_ui and build_mode_shop_ui.has_method("refresh_for_zone"):
		build_mode_shop_ui.refresh_for_zone(current_zone)
		build_mode_shop_ui.show_shop()
	elif build_mode_shop_ui:
		build_mode_shop_ui.show_shop()

	if build_mode_upgrades_ui:
		build_mode_upgrades_ui.show_panel()

	# Show zone selector UI
	if zone_selector_ui:
		zone_selector_ui.show_selector()
		var item_count := _get_zone_item_count(current_zone)
		zone_selector_ui.update_zone_display(current_zone, ZONE_NAMES[current_zone], item_count)

	# Fade in UI elements after camera transition (0.2s)
	if build_mode_shop_ui and build_mode_shop_ui.has_method("fade_in"):
		build_mode_shop_ui.fade_in(0.2)

	if zone_selector_ui and zone_selector_ui.has_method("fade_in"):
		# Fade in just the label, panel stays visible
		zone_selector_ui.fade_in(0.2)

	# Wait for fade in to complete
	await get_tree().create_timer(0.2, true, false, true).timeout

	is_build_mode_active = true
	is_transitioning = false
	build_mode_entered.emit()

	print("[BUILD_MODE] Build mode active!")

func exit_build_mode() -> void:
	"""Exit build mode and return to first-person."""
	if not is_build_mode_active or is_transitioning:
		return

	print("[BUILD_MODE] Exiting build mode...")
	is_transitioning = true

	# Hide build mode UI
	if build_mode_shop_ui:
		build_mode_shop_ui.hide_shop()

	if build_mode_upgrades_ui:
		build_mode_upgrades_ui.hide_panel()

	# Hide zone selector UI
	if zone_selector_ui:
		zone_selector_ui.hide_selector()

	# REBAKE NAVIGATION MESH - Critical for AI pathfinding to new objects
	if navigation_region and navigation_region.has_method("bake_navigation_mesh"):
		print("[BUILD_MODE] Rebaking navigation mesh for new objects...")
		navigation_region.bake_navigation_mesh()
		# Wait one frame for navigation to update
		await get_tree().process_frame
		print("[BUILD_MODE] Navigation mesh updated!")

	# Animate camera transition back
	await _transition_to_first_person_camera()

	# Resume the game
	if game_manager:
		game_manager.current_state = GameManager.GameState.PLAYING
		get_tree().paused = false

	# Re-enable player controller
	if player_controller and player_controller.has_method("set_controls_enabled"):
		player_controller.set_controls_enabled(true)

	# Hide mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	is_build_mode_active = false
	is_transitioning = false
	build_mode_exited.emit()

	print("[BUILD_MODE] Returned to gameplay!")

func _transition_to_build_camera(zone: Zone) -> void:
	"""Smooth transition from first-person to zone-specific build camera with Tween (1 second)."""
	if not first_person_camera or not zone in zone_cameras:
		push_error("[BUILD_MODE] Camera transition failed - missing cameras")
		return

	var target_camera: Camera3D = zone_cameras[zone]

	# Disable first-person camera
	first_person_camera.current = false

	# Enable target zone camera
	target_camera.current = true

	# Smooth transition duration (1.0 second for professional feel)
	await get_tree().create_timer(1.0, true, false, true).timeout

	print("[BUILD_MODE] Transitioned to %s camera" % ZONE_NAMES[zone])

func _transition_to_first_person_camera() -> void:
	"""Smooth transition from any zone camera back to first-person (1 second)."""
	if not first_person_camera:
		return

	# Disable all zone cameras
	for zone_camera in zone_cameras.values():
		if zone_camera:
			zone_camera.current = false

	# Enable first-person camera
	first_person_camera.current = true

	# Wait for transition duration
	await get_tree().create_timer(1.0, true, false, true).timeout

	print("[BUILD_MODE] Transitioned to first-person camera")

## ========== ZONE SWITCHING SYSTEM ==========

func _cycle_zone() -> void:
	"""Cycle to next zone (Tab or arrow keys handler)."""
	if is_transitioning:
		return

	# Toggle between DINING and KITCHEN (2-zone system)
	var new_zone: Zone = Zone.KITCHEN if current_zone == Zone.DINING else Zone.DINING
	switch_to_zone(new_zone)

func switch_to_zone(new_zone: Zone) -> void:
	"""Switch to a specific zone with smooth camera transition and UI updates."""
	if is_transitioning or new_zone == current_zone:
		return

	print("[BUILD_MODE] Switching from %s to %s" % [ZONE_NAMES[current_zone], ZONE_NAMES[new_zone]])
	is_transitioning = true

	# Set zone selector to transitioning state (disables arrows)
	if zone_selector_ui:
		zone_selector_ui.set_transitioning(true)

	# Fade out UI elements (0.2s)
	if build_mode_shop_ui and build_mode_shop_ui.has_method("fade_out"):
		build_mode_shop_ui.fade_out(0.2)

	if zone_selector_ui:
		zone_selector_ui.fade_out(0.2)

	# Wait for fade out
	await get_tree().create_timer(0.2, true, false, true).timeout

	# Update current zone
	current_zone = new_zone

	# Smooth camera transition to new zone (1.0s)
	var old_camera: Camera3D = zone_cameras[Zone.KITCHEN if new_zone == Zone.DINING else Zone.DINING]
	var new_camera: Camera3D = zone_cameras[new_zone]

	if old_camera:
		old_camera.current = false
	if new_camera:
		new_camera.current = true

	await get_tree().create_timer(1.0, true, false, true).timeout

	# Refresh shop UI with zone-specific categories
	if build_mode_shop_ui and build_mode_shop_ui.has_method("refresh_for_zone"):
		build_mode_shop_ui.refresh_for_zone(current_zone)

	# Update zone selector display with item count
	if zone_selector_ui:
		var item_count := _get_zone_item_count(current_zone)
		zone_selector_ui.update_zone_display(current_zone, ZONE_NAMES[current_zone], item_count)

	# Fade in UI elements (0.2s)
	if build_mode_shop_ui and build_mode_shop_ui.has_method("fade_in"):
		build_mode_shop_ui.fade_in(0.2)

	if zone_selector_ui:
		zone_selector_ui.fade_in(0.2)

	# Wait for fade in
	await get_tree().create_timer(0.2, true, false, true).timeout

	# Re-enable zone selector
	if zone_selector_ui:
		zone_selector_ui.set_transitioning(false)

	is_transitioning = false
	print("[BUILD_MODE] Zone switch complete: %s" % ZONE_NAMES[current_zone])

func _on_zone_selector_changed(new_zone: int) -> void:
	"""Handle zone change signal from ZoneSelectorUI."""
	if new_zone >= 0 and new_zone < Zone.size():
		switch_to_zone(new_zone as Zone)

func _get_zone_item_count(zone: Zone) -> int:
	"""Count placed items in a specific zone."""
	var count := 0

	# Get zone-specific categories
	var zone_categories: Array = ZONE_CATEGORIES.get(zone, [])

	# Count items belonging to zone categories
	for item_type: String in placed_items.keys():
		var item_category: String = _get_item_category(item_type)
		if item_category in zone_categories:
			count += placed_items[item_type].size()

	return count

func _get_item_category(item_type: String) -> String:
	"""Get category for an item type."""
	if item_type in ["table", "chair", "decoration"]:
		return "furniture"
	elif item_type in ["stove", "oven", "prep_counter", "serving_counter"]:
		return "kitchen"
	elif item_type in ["trash_bin", "storage"]:
		return "utility"
	elif item_type in ["premium_table", "premium_decor"]:
		return "premium"
	else:
		return "furniture"  # Default

## ========== INSTANT PLACEMENT SYSTEM ==========

func purchase_and_place_item(item_type: String) -> bool:
	"""Instantly purchase and place an item in its appropriate zone."""
	if not economy_manager:
		push_error("[BUILD_MODE] No EconomyManager found!")
		return false

	# Get item data
	var item_data: Dictionary = economy_manager.get_placeable_item(item_type)
	if item_data.is_empty():
		push_error("[BUILD_MODE] Item data not found for: %s" % item_type)
		return false

	var cost: float = item_data.get("cost", 0.0)
	var max_count: int = item_data.get("max_count", 999)

	# Check placement limit
	var current_count: int = get_placement_count(item_type)
	if current_count >= max_count:
		error_message = "Limit reached! (%d/%d %s placed)" % [current_count, max_count, item_data.get("name", "items")]
		error_message_timer = 3.0
		print("[BUILD_MODE] %s" % error_message)
		return false

	# Check if player can afford it
	if not economy_manager.can_afford(cost):
		error_message = "Cannot afford! Need $%.2f" % cost
		error_message_timer = 3.0
		print("[BUILD_MODE] Cannot afford %s (Cost: $%.2f)" % [item_type, cost])
		return false

	# Find next available position in appropriate zone
	var zone: String = ITEM_ZONES.get(item_type, "dining")
	var placement_pos: Vector3 = _get_next_available_position_in_zone(zone, item_type)

	if placement_pos == Vector3.ZERO:
		error_message = "No space available in %s zone!" % zone
		error_message_timer = 3.0
		print("[BUILD_MODE] No space in %s zone for %s" % [zone, item_type])
		return false

	# Deduct money
	economy_manager.subtract_money(cost, "building")

	# Instantiate the actual object
	var prefab_path: String = item_data.get("prefab", "")
	if prefab_path.is_empty():
		push_error("[BUILD_MODE] No prefab path for: %s" % item_type)
		economy_manager.add_money(cost, "building_refund")  # Refund on error
		return false

	var scene := load(prefab_path) as PackedScene
	if not scene:
		push_error("[BUILD_MODE] Failed to load prefab: %s" % prefab_path)
		economy_manager.add_money(cost, "building_refund")  # Refund on error
		return false

	var instance := scene.instantiate()

	# CRITICAL FIX: Add to NavigationRegion3D first, THEN set position
	if navigation_region:
		navigation_region.add_child(instance)
		print("[BUILD_MODE] Placed %s inside NavigationRegion3D - will be functional!" % item_type)
	else:
		# Fallback: add to scene root (not ideal but better than crashing)
		get_tree().root.add_child(instance)
		push_error("[BUILD_MODE] WARNING: Placed %s at scene root - may not work with AI!" % item_type)

	# NOW set position (after being in scene tree)
	instance.global_position = placement_pos
	# No rotation - keep tables aligned
	print("[BUILD_MODE] ✅ Placed %s at position: %v" % [item_type, placement_pos])

	# INSTANT TRACKING: Add to placed_items immediately
	if item_type in placed_items:
		placed_items[item_type].append(instance)
		print("[BUILD_MODE] Tracked placed %s (total: %d)" % [item_type, placed_items[item_type].size()])

	# Emit signals
	item_placed.emit(item_type, instance.global_position, instance.rotation.y)
	item_purchased.emit(item_type)

	print("[BUILD_MODE] Successfully placed %s at %v for $%.2f" % [item_type, instance.global_position, cost])
	return true

func _get_next_available_position_in_zone(zone: String, _item_type: String) -> Vector3:
	"""Find the next available position in a zone - wide spacing similar to initial 3 tables."""
	# Get zone center
	if not zone in zone_centers:
		push_error("[BUILD_MODE] Zone '%s' not found!" % zone)
		return Vector3.ZERO

	var zone_center: Vector3 = zone_centers[zone]

	# Permanent tables: (0,0,-3), (3.5,0,-3), (7,0,-3) - First row
	# 3 columns (X: 0, 3.5, 7) × 4 rows (Z: -3, 0, 3, 6)
	# Safe from walls: X ∈ [-9, 9], Z ∈ [-9, 9], avoiding door at Z=10

	# Define specific positions - CENTERED 3×4 GRID
	var preset_positions: Array[Vector3] = [
		# Row 1 (Top, Z = -3.0) - PERMANENT TABLES
		# (0.0, 0, -3.0) - Table1 permanent
		# (3.5, 0, -3.0) - Table2 permanent
		# (7.0, 0, -3.0) - Table3 permanent

		# Row 2 (Middle-top, Z = 0.0)
		Vector3(0.0, 0, 0.0),     # Row2-Col1
		Vector3(3.5, 0, 0.0),     # Row2-Col2
		Vector3(7.0, 0, 0.0),     # Row2-Col3

		# Row 3 (Middle-bottom, Z = 3.0)
		Vector3(0.0, 0, 3.0),     # Row3-Col1
		Vector3(3.5, 0, 3.0),     # Row3-Col2
		Vector3(7.0, 0, 3.0),     # Row3-Col3

		# Row 4 (Bottom, Z = 6.0)
		Vector3(0.0, 0, 6.0),     # Row4-Col1
		Vector3(3.5, 0, 6.0),     # Row4-Col2
		Vector3(7.0, 0, 6.0),     # Row4-Col3
	]

	print("[BUILD_MODE] 🔍 Searching for placement in zone: %s" % zone)

	# Try each preset position in order
	for i in range(preset_positions.size()):
		var pos: Vector3 = preset_positions[i]
		print("[BUILD_MODE]   Trying preset position %d: %v" % [i + 1, pos])
		if _is_position_clear(pos):
			print("[BUILD_MODE]   ✅ Position is clear! Using this spot.")
			return pos
		else:
			print("[BUILD_MODE]   ❌ Position blocked, trying next...")

	# If all preset positions full, use expanding search from zone center
	print("[BUILD_MODE] All preset positions full, using expanding search...")
	for distance in range(5, 20, 3):  # 5, 8, 11, 14, 17 meters
		for angle_deg in range(0, 360, 45):  # Every 45 degrees
			var angle_rad := deg_to_rad(angle_deg)
			var offset := Vector3(cos(angle_rad) * distance, 0, sin(angle_rad) * distance)
			var test_pos := zone_center + offset

			if _is_position_clear(test_pos):
				return test_pos

	# No space found
	return Vector3.ZERO

func _is_position_clear(position: Vector3) -> bool:
	"""Check if a position has no overlapping objects using distance check."""
	# Check distance to all existing placed items
	var min_distance: float = 3.0  # Minimum 3 meters between items

	for item_type in placed_items:
		for item in placed_items[item_type]:
			if is_instance_valid(item) and item is Node3D:
				var distance: float = item.global_position.distance_to(position)
				if distance < min_distance:
					print("[BUILD_MODE]   ❌ Too close to existing %s (distance: %.1fm)" % [item_type, distance])
					return false

	print("[BUILD_MODE]   ✅ Position clear (no items within %.1fm)" % min_distance)
	return true

func _disable_physics_collisions(node: Node) -> void:
	"""Disable physics collisions for preview (ghost mode)."""
	# Disable collision shapes
	if node is CollisionShape3D or node is CollisionPolygon3D:
		node.disabled = true

	# Set collision layers to 0 for physics bodies
	if node is StaticBody3D or node is RigidBody3D or node is CharacterBody3D:
		node.collision_layer = 0
		node.collision_mask = 0

	# Disable Area3D monitoring
	if node is Area3D:
		node.monitoring = false
		node.monitorable = false

	# Recurse through children
	for child in node.get_children():
		_disable_physics_collisions(child)

func _make_ghost_material(node: Node) -> void:
	"""Apply ghost material to all MeshInstance3D children."""
	if node is MeshInstance3D:
		# Create semi-transparent material
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1, 1, 1, 0.5)  # Semi-transparent
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		node.material_override = material

	# Recurse through children
	for child in node.get_children():
		_make_ghost_material(child)

func _process(_delta: float) -> void:
	"""Update hover detection for placed items in build mode."""
	if not is_build_mode_active or is_transitioning:
		return

	var mouse_pos := get_viewport().get_mouse_position()

	# Check if mouse is over UI areas
	var screen_width := get_viewport().get_visible_rect().size.x
	var is_over_left_ui := mouse_pos.x < 350
	var is_over_right_ui := mouse_pos.x > (screen_width - 350)
	var is_over_ui := is_over_left_ui or is_over_right_ui

	if is_over_ui:
		_clear_hover()
		return

	# Check for hover over placed items (for removal)
	_update_item_hover(mouse_pos)

## ========== PLACEMENT TRACKING SYSTEM ==========

func _on_item_placed(item_type: String, position: Vector3, _rotation: float) -> void:
	"""Called when an item is placed - tracking happens immediately in purchase_and_place_item."""
	# This signal is kept for backward compatibility and future features
	# The actual tracking now happens in purchase_and_place_item() for instant updates
	print("[BUILD_MODE] Item placed signal received: %s at %v" % [item_type, position])

func _find_placed_instance_at(position: Vector3) -> Node3D:
	"""Find the node that was just placed at this position in NavigationRegion3D."""
	if not navigation_region:
		return null

	# Search through NavigationRegion3D children for one at this position
	for node in navigation_region.get_children():
		if node is Node3D and node.global_position.distance_to(position) < 0.1:
			# Check if it's one of the placeable types (has certain class names)
			if node.has_method("_can_accept_food") or node is StaticBody3D:
				return node
	return null

func get_placement_count(item_type: String) -> int:
	"""Get the current number of placed items of this type."""
	if item_type in placed_items:
		# Clean up any freed instances
		placed_items[item_type] = placed_items[item_type].filter(func(item): return is_instance_valid(item))
		return placed_items[item_type].size()
	return 0

func scan_existing_objects() -> void:
	"""Scan scene for existing objects and add to tracking (called on build mode entry)."""
	print("[BUILD_MODE] Scanning scene for existing placed objects...")

	# Clear permanent items list (will be repopulated every time)
	permanent_items.clear()

	# Scan for ovens - mark ALL existing ones as permanent
	for oven in get_tree().get_nodes_in_group("cooking_stations"):
		if "Oven" in oven.name:
			if oven not in placed_items["oven"]:
				placed_items["oven"].append(oven)
			# ALWAYS mark as permanent (whether newly added or already tracked)
			if oven not in permanent_items:
				permanent_items.append(oven)

	# Scan for stoves
	for stove in get_tree().get_nodes_in_group("cooking_stations"):
		if "Stove" in stove.name:
			if stove not in placed_items["stove"]:
				placed_items["stove"].append(stove)
			if stove not in permanent_items:
				permanent_items.append(stove)

	# Scan for prep counters
	for prep in get_tree().get_nodes_in_group("cooking_stations"):
		if "Prep" in prep.name or "Counter" in prep.name:
			if prep not in placed_items["prep_counter"]:
				placed_items["prep_counter"].append(prep)
			if prep not in permanent_items:
				permanent_items.append(prep)

	# Scan for tables
	for table in get_tree().get_nodes_in_group("tables"):
		if table not in placed_items["table"]:
			placed_items["table"].append(table)
		if table not in permanent_items:
			permanent_items.append(table)

	# Scan for trash bins
	for trash in get_tree().get_nodes_in_group("trash_bins"):
		if trash not in placed_items["trash_bin"]:
			placed_items["trash_bin"].append(trash)
		if trash not in permanent_items:
			permanent_items.append(trash)

	# Scan for serving counters
	for counter in get_tree().get_nodes_in_group("serving_counters"):
		if counter not in placed_items["serving_counter"]:
			placed_items["serving_counter"].append(counter)
		if counter not in permanent_items:
			permanent_items.append(counter)

	# Print results
	for item_type in placed_items:
		print("[BUILD_MODE] Found %d existing %s" % [placed_items[item_type].size(), item_type])
	print("[BUILD_MODE] Marked %d items as permanent (cannot be removed)" % permanent_items.size())

func get_placed_items_data() -> Array:
	"""Get data for all placed items (for saving)."""
	var data: Array = []
	for item_type in placed_items:
		for item in placed_items[item_type]:
			if is_instance_valid(item):
				data.append({
					"type": item_type,
					"position": [item.global_position.x, item.global_position.y, item.global_position.z],
					"rotation_y": item.rotation.y
				})
	return data

func restore_placed_items(data: Array) -> void:
	"""Restore placed items from save data."""
	for item_data in data:
		var item_type: String = item_data.get("type", "")
		var pos_array: Array = item_data.get("position", [0, 0, 0])
		var position := Vector3(pos_array[0], pos_array[1], pos_array[2])
		var rotation_y: float = item_data.get("rotation_y", 0.0)

		# Load and instantiate the item
		if not economy_manager:
			continue

		var item_info: Dictionary = economy_manager.get_placeable_item(item_type)
		if item_info.is_empty():
			continue

		var prefab_path: String = item_info.get("prefab", "")
		if prefab_path.is_empty():
			continue

		var scene := load(prefab_path) as PackedScene
		if not scene:
			continue

		var instance := scene.instantiate()
		instance.global_position = position
		instance.rotation.y = rotation_y

		# CRITICAL FIX: Add to NavigationRegion3D, not scene root!
		if navigation_region:
			navigation_region.add_child(instance)
		else:
			get_tree().root.add_child(instance)

		# Track it
		if item_type in placed_items:
			placed_items[item_type].append(instance)

	print("[BUILD_MODE] Restored %d placed items from save" % data.size())

## ========== ITEM REMOVAL SYSTEM ==========

func _update_item_hover(mouse_pos: Vector2) -> void:
	"""Detect which placed item the mouse is hovering over."""
	# Get current zone camera
	var current_camera: Camera3D = zone_cameras.get(current_zone)
	if not current_camera:
		return

	# Raycast from camera to objects
	var from := current_camera.project_ray_origin(mouse_pos)
	var to := from + current_camera.project_ray_normal(mouse_pos) * 1000.0

	var space_state := current_camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b10000  # Layer 4 (Interactables)

	var result := space_state.intersect_ray(query)
	if result:
		var hit_object: Node = result.collider

		# Check if hit object is in our placed items
		var found_item: Node3D = null
		var found_type: String = ""

		for item_type in placed_items:
			if hit_object in placed_items[item_type]:
				found_item = hit_object
				found_type = item_type
				break

		if found_item:
			# Hover over a placed item
			if found_item != hovered_item:
				_set_hovered_item(found_item, found_type)
		else:
			_clear_hover()
	else:
		_clear_hover()

func _set_hovered_item(item: Node3D, item_type: String) -> void:
	"""Set the currently hovered item and show highlight."""
	# Clear previous hover
	_clear_hover()

	hovered_item = item

	# Create highlight overlay (yellow semi-transparent)
	_create_hover_highlight(item)

	# Could show tooltip here with item info and refund amount
	var item_data: Dictionary = economy_manager.get_placeable_item(item_type) if economy_manager else {}
	var refund: float = item_data.get("cost", 0.0) * 0.5

	print("[BUILD_MODE] Hovering over %s - Right-click to remove (refund: $%.2f)" % [item_type, refund])

func _clear_hover() -> void:
	"""Clear the current hover state and highlight."""
	if hover_highlight:
		hover_highlight.queue_free()
		hover_highlight = null

	hovered_item = null

func _create_hover_highlight(item: Node3D) -> void:
	"""Create a semi-transparent yellow highlight overlay on the item."""
	# Find all MeshInstance3D children and clone them with highlight material
	var highlight_parent := Node3D.new()
	highlight_parent.name = "HoverHighlight"
	highlight_parent.global_transform = item.global_transform

	# Find all mesh instances in the item
	_clone_meshes_for_highlight(item, highlight_parent)

	# Add to scene
	get_tree().root.add_child(highlight_parent)
	hover_highlight = highlight_parent

func _clone_meshes_for_highlight(node: Node, parent: Node3D) -> void:
	"""Recursively clone mesh instances for highlighting."""
	if node is MeshInstance3D:
		var mesh_copy := MeshInstance3D.new()
		mesh_copy.mesh = node.mesh
		mesh_copy.transform = node.transform

		# Create yellow semi-transparent highlight material
		var highlight_mat := StandardMaterial3D.new()
		highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		highlight_mat.albedo_color = Color(1, 1, 0, 0.3)  # Yellow, 30% opacity
		highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		highlight_mat.disable_receive_shadows = true
		highlight_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Show from all angles

		mesh_copy.material_override = highlight_mat
		parent.add_child(mesh_copy)

	# Recurse through children
	for child in node.get_children():
		_clone_meshes_for_highlight(child, parent)

func remove_item(item: Node3D) -> void:
	"""Remove a placed item and give 50% refund."""
	if not item or not is_instance_valid(item):
		return

	# Check if item is permanent (initial scene objects cannot be removed)
	if item in permanent_items:
		error_message = "Cannot remove initial objects!"
		error_message_timer = 3.0
		print("[BUILD_MODE] ❌ Attempted to remove permanent item: %s" % item.name)
		return

	# Find which type this item is
	var item_type: String = ""
	for type in placed_items:
		if item in placed_items[type]:
			item_type = type
			break

	if item_type.is_empty():
		push_error("[BUILD_MODE] Cannot remove item - not found in tracking!")
		return

	# Get item data and calculate refund
	var item_data: Dictionary = economy_manager.get_placeable_item(item_type) if economy_manager else {}
	var original_cost: float = item_data.get("cost", 0.0)
	var refund: float = original_cost * 0.5

	# Give refund
	if economy_manager:
		economy_manager.add_money(refund, "building_refund")

	# Remove from tracking
	placed_items[item_type].erase(item)

	# Remove from scene
	item.queue_free()

	# Clear hover
	_clear_hover()

	# Emit signal
	item_removed.emit(item_type, item.global_position)

	print("[BUILD_MODE] Removed %s, refunded $%.2f (50%% of $%.2f)" % [item_type, refund, original_cost])

func remove_last_placed_item(item_type: String) -> bool:
	"""Remove the most recently placed item of a specific type. Returns true if successful."""
	if not item_type in placed_items:
		return false

	# Get all items of this type (excluding permanent ones)
	var items: Array = placed_items[item_type].filter(func(item):
		return is_instance_valid(item) and item not in permanent_items
	)

	if items.is_empty():
		error_message = "No removable %s found!" % item_type
		error_message_timer = 3.0
		print("[BUILD_MODE] ❌ No removable %s to remove" % item_type)
		return false

	# Remove the last item (most recently placed)
	var last_item: Node3D = items[-1]
	remove_item(last_item)
	return true
