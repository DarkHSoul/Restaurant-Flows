extends CanvasLayer
class_name ShopUI

## Shop interface for purchasing upgrades and improvements

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var money_label: Label = $Panel/VBoxContainer/MoneyDisplay
@onready var upgrades_container: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/UpgradesContainer
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton
@onready var no_upgrades_label: Label = $Panel/VBoxContainer/NoUpgradesLabel

var economy_manager: EconomyManager
var game_manager: GameManager
var pause_menu: PauseMenu  # Reference to pause menu if opened from there

var is_open: bool = false
var selected_index: int = 0
var available_upgrades: Array = []
var upgrade_buttons: Array[Button] = []

func _ready() -> void:
	# Find managers
	game_manager = GameManager.instance
	if game_manager:
		economy_manager = game_manager.economy_manager

	# Find pause menu
	await get_tree().process_frame
	pause_menu = get_tree().get_first_node_in_group("pause_menu") as PauseMenu

	# Connect signals
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	if economy_manager:
		economy_manager.money_changed.connect(_on_money_changed)
		economy_manager.upgrade_purchased.connect(_on_upgrade_purchased)

	# Start hidden
	hide_shop()

func _input(event: InputEvent) -> void:
	# P key is now used for Build Mode, so disable toggle_shop here
	# Shop can still be opened via Tab key or from pause menu
	# if event.is_action_pressed("toggle_shop"):
	# 	if is_open:
	# 		hide_shop()
	# 	else:
	# 		show_shop()
	# 	get_viewport().set_input_as_handled()
	# 	return

	if not is_open:
		return

	# Close with Escape
	if event.is_action_pressed("ui_cancel"):
		hide_shop()
		get_viewport().set_input_as_handled()
		return

	# Navigate with Up/Down arrows
	if event.is_action_pressed("ui_up"):
		_navigate_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_navigate_selection(1)
		get_viewport().set_input_as_handled()

	# Purchase with Enter
	elif event.is_action_pressed("ui_accept"):
		_purchase_selected()
		get_viewport().set_input_as_handled()

func show_shop() -> void:
	"""Show the shop interface."""
	if not economy_manager:
		return

	is_open = true
	visible = true

	# Show mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Pause the game only if not already paused
	if game_manager and game_manager.current_state == GameManager.GameState.PLAYING:
		get_tree().paused = true

	# Reset selection
	selected_index = 0
	_refresh_shop()
	_update_selection_visual()

func hide_shop() -> void:
	"""Hide the shop interface."""
	is_open = false
	visible = false

	# Only unpause and hide cursor if game is not in pause menu
	if game_manager and game_manager.current_state == GameManager.GameState.PAUSED:
		# Game is still paused (pause menu is open), keep mouse visible and show pause menu
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if pause_menu and pause_menu.is_paused:
			pause_menu.panel.visible = true
	else:
		# Return to normal gameplay
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_tree().paused = false

func _refresh_shop() -> void:
	"""Refresh the shop display with current upgrades."""
	if not economy_manager:
		return

	# Update money display
	_update_money_display()

	# Clear existing upgrade displays
	if upgrades_container:
		for child in upgrades_container.get_children():
			child.queue_free()

	# Clear button tracking
	upgrade_buttons.clear()

	# Get available upgrades
	available_upgrades = economy_manager.get_available_upgrades()

	if available_upgrades.is_empty():
		if no_upgrades_label:
			no_upgrades_label.visible = true
			no_upgrades_label.text = "All upgrades purchased!"
		return
	else:
		if no_upgrades_label:
			no_upgrades_label.visible = false

	# Create upgrade items
	for upgrade in available_upgrades:
		_create_upgrade_item(upgrade)

	# Clamp selection index
	if selected_index >= upgrade_buttons.size():
		selected_index = max(0, upgrade_buttons.size() - 1)

func _create_upgrade_item(upgrade: Dictionary) -> void:
	"""Create a UI element for an upgrade."""
	if not upgrades_container:
		return

	var upgrade_panel := PanelContainer.new()
	upgrade_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade_panel.add_child(hbox)

	# Info container (left side)
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	# Upgrade name
	var name_label := Label.new()
	name_label.text = upgrade.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(1, 1, 0.8))
	info_vbox.add_child(name_label)

	# Description
	var desc_label := Label.new()
	desc_label.text = upgrade.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(desc_label)

	# Type indicator
	var type_label := Label.new()
	type_label.text = "Type: %s" % upgrade.get("type", "").capitalize()
	type_label.add_theme_font_size_override("font_size", 12)
	type_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.8))
	info_vbox.add_child(type_label)

	# Purchase button (right side)
	var buy_button := Button.new()
	var cost: float = upgrade.get("cost", 0.0)
	buy_button.text = "$%.0f\nBuy" % cost
	buy_button.custom_minimum_size = Vector2(100, 60)
	buy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Check if affordable
	if economy_manager.can_afford(cost):
		buy_button.add_theme_color_override("font_color", Color(0.2, 1, 0.2))
	else:
		buy_button.disabled = true
		buy_button.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	var upgrade_id: String = upgrade.get("id", "")
	buy_button.pressed.connect(_on_purchase_upgrade.bind(upgrade_id))

	hbox.add_child(buy_button)

	upgrades_container.add_child(upgrade_panel)

	# Track button for keyboard navigation
	upgrade_buttons.append(buy_button)

func _on_purchase_upgrade(upgrade_id: String) -> void:
	"""Called when player attempts to purchase an upgrade."""
	if not economy_manager:
		return

	if economy_manager.purchase_upgrade(upgrade_id):
		# Success! Refresh shop
		_refresh_shop()
		# Play sound effect (if available)
		# show_purchase_feedback()
	else:
		# Failed - show error
		_show_error("Cannot afford this upgrade!")

func _on_money_changed(_new_amount: float, _change: float) -> void:
	"""Called when money changes."""
	if is_open:
		_update_money_display()
		_update_button_affordability()

func _update_button_affordability() -> void:
	"""Update button states based on current money."""
	if not economy_manager:
		return

	for i in range(available_upgrades.size()):
		if i < upgrade_buttons.size():
			var button := upgrade_buttons[i]
			var upgrade: Dictionary = available_upgrades[i]
			var cost: float = upgrade.get("cost", 0.0)

			# Update button state based on affordability
			if economy_manager.can_afford(cost):
				button.disabled = false
				button.add_theme_color_override("font_color", Color(0.2, 1, 0.2))
			else:
				button.disabled = true
				button.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

func _on_upgrade_purchased(_upgrade_id: String, _cost: float) -> void:
	"""Called when an upgrade is purchased."""
	if is_open:
		_refresh_shop()

func _update_money_display() -> void:
	"""Update the money display."""
	if money_label and economy_manager:
		var stats := economy_manager.get_stats()
		money_label.text = "Available Money: $%.2f" % stats.money

func _show_error(message: String) -> void:
	"""Show an error message to the player."""
	# Could implement a temporary popup/label here
	print("Shop Error: ", message)

func _on_close_pressed() -> void:
	"""Called when close button is pressed."""
	hide_shop()

func _navigate_selection(direction: int) -> void:
	"""Navigate the selection up or down."""
	if upgrade_buttons.is_empty():
		return

	# Remove highlight from current selection
	if selected_index >= 0 and selected_index < upgrade_buttons.size():
		_unhighlight_button(upgrade_buttons[selected_index])

	# Update selection index
	selected_index += direction

	# Wrap around
	if selected_index < 0:
		selected_index = upgrade_buttons.size() - 1
	elif selected_index >= upgrade_buttons.size():
		selected_index = 0

	# Update visual
	_update_selection_visual()

func _update_selection_visual() -> void:
	"""Update the visual highlight for the selected item."""
	if upgrade_buttons.is_empty():
		return

	if selected_index >= 0 and selected_index < upgrade_buttons.size():
		_highlight_button(upgrade_buttons[selected_index])

func _highlight_button(button: Button) -> void:
	"""Highlight a button to show it's selected."""
	if button:
		# Add a visual indicator (yellow border or background)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.3, 0.3, 0.1, 0.8)
		style.border_width_left = 3
		style.border_width_right = 3
		style.border_width_top = 3
		style.border_width_bottom = 3
		style.border_color = Color(1, 1, 0, 1)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)

func _unhighlight_button(button: Button) -> void:
	"""Remove highlight from a button."""
	if button:
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_stylebox_override("hover")
		button.remove_theme_stylebox_override("pressed")

func _purchase_selected() -> void:
	"""Purchase the currently selected upgrade."""
	if upgrade_buttons.is_empty():
		return

	if selected_index >= 0 and selected_index < upgrade_buttons.size():
		var button := upgrade_buttons[selected_index]
		if button and not button.disabled:
			# Trigger the button press
			button.emit_signal("pressed")
