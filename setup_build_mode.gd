extends Node

## ONE-TIME SETUP SCRIPT FOR BUILD MODE
## Add this script to Main3D scene, run once, then remove it!

func _ready() -> void:
	print("[SETUP] Starting Build Mode setup...")
	await get_tree().process_frame

	# Get Main3D root node
	var main3d := get_parent()
	if not main3d:
		push_error("[SETUP] Could not find Main3D parent!")
		return

	# Check if BuildModeManager already exists
	var existing_manager := main3d.get_node_or_null("BuildModeManager")
	if existing_manager:
		print("[SETUP] BuildModeManager already exists, skipping...")
	else:
		# Add BuildModeManager
		var build_manager := Node.new()
		build_manager.name = "BuildModeManager"
		build_manager.set_script(preload("res://src/systems/scripts/BuildModeManager.gd"))
		build_manager.process_mode = Node.PROCESS_MODE_ALWAYS
		main3d.add_child(build_manager)
		build_manager.owner = main3d  # Make it saveable in scene
		print("[SETUP] ✅ Added BuildModeManager")

	# Check if BuildModeCamera already exists
	var existing_camera := main3d.get_node_or_null("BuildModeCamera")
	if existing_camera:
		print("[SETUP] BuildModeCamera already exists, skipping...")
	else:
		# Add BuildModeCamera
		var build_cam := Camera3D.new()
		build_cam.name = "BuildModeCamera"
		build_cam.add_to_group("build_mode_camera")
		build_cam.position = Vector3(0, 15, -10)
		build_cam.rotation_degrees = Vector3(-60, 0, 0)
		build_cam.fov = 60.0
		build_cam.current = false
		main3d.add_child(build_cam)
		build_cam.owner = main3d  # Make it saveable in scene
		print("[SETUP] ✅ Added BuildModeCamera at position (0, 15, -10)")

	# Check if BuildModeShopUI already exists
	var existing_shop := get_tree().get_first_node_in_group("build_mode_shop")
	if existing_shop:
		print("[SETUP] BuildModeShopUI already exists, skipping...")
	else:
		# Add BuildModeShopUI
		var shop_ui_scene := load("res://src/ui/scenes/BuildModeShopUI.tscn") as PackedScene
		if shop_ui_scene:
			var shop_ui := shop_ui_scene.instantiate()
			main3d.add_child(shop_ui)
			shop_ui.owner = main3d  # Make it saveable in scene
			print("[SETUP] ✅ Added BuildModeShopUI")
		else:
			push_error("[SETUP] Could not load BuildModeShopUI scene!")

	print("[SETUP] Build Mode setup complete!")
	print("[SETUP] IMPORTANT: Save the Main3D scene (Ctrl+S) to persist these changes!")
	print("[SETUP] Then remove this setup_build_mode.gd script from the scene.")
	print("[SETUP] Press P during gameplay to test Build Mode!")
