extends CanvasLayer
class_name BuildModeShopUI

## Build Mode Shop UI - Sidebar shop for placing objects in build mode

## Signals
signal item_selected(item_id: String)

## Node references
@onready var sidebar_panel: PanelContainer = $SidebarPanel
@onready var money_label: RichTextLabel = $SidebarPanel/MarginContainer/VBoxContainer/MoneyPanel/MarginContainer/MoneyLabel
@onready var category_tabs: HBoxContainer = $SidebarPanel/MarginContainer/VBoxContainer/CategoryTabs
@onready var items_scroll: ScrollContainer = $SidebarPanel/MarginContainer/VBoxContainer/ItemsScroll
@onready var items_container: VBoxContainer = $SidebarPanel/MarginContainer/VBoxContainer/ItemsScroll/ItemsContainer
@onready var grid_status_label: Label = $SidebarPanel/MarginContainer/VBoxContainer/BottomPanel/MarginContainer/GridStatusLabel

## State
var is_open: bool = false
var current_category: String = "kitchen"
var selected_item_id: String = ""
var current_zone: int = 0  # BuildModeManager.Zone enum

## References
var economy_manager: EconomyManager
var build_mode_manager: BuildModeManager

## Category buttons
var category_buttons: Dictionary = {}

## Zone-specific category definitions (must match BuildModeManager.ZONE_CATEGORIES)
const ZONE_CATEGORIES := {
	0: ["furniture", "utility", "premium"],  # DINING zone
	1: ["kitchen", "utility", "premium"]     # KITCHEN zone
}

func _ready() -> void:
	# Add to build_mode_shop group
	add_to_group("build_mode_shop")

	# Find managers
	economy_manager = EconomyManager.instance
	build_mode_manager = BuildModeManager.instance

	# Connect to economy signals
	if economy_manager:
		economy_manager.money_changed.connect(_on_money_changed)

	# Create category tabs
	_create_category_tabs()

	# Start hidden
	visible = false
	is_open = false

	print("[BUILD_SHOP] BuildModeShopUI ready!")

func _create_category_tabs() -> void:
	"""Create category selection buttons - dynamically filtered by zone."""
	var all_categories := [
		{"id": "kitchen", "name": "🍳 Mutfak", "icon": "🍳"},
		{"id": "furniture", "name": "🪑 Mobilya", "icon": "🪑"},
		{"id": "utility", "name": "🗑️ Utility", "icon": "🗑️"},
		{"id": "premium", "name": "⭐ Premium", "icon": "⭐"}
	]

	# Create all buttons (they'll be shown/hidden based on zone)
	for cat in all_categories:
		var button := Button.new()
		button.name = cat.id + "_button"
		button.text = cat.name
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
		button.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.85))
		button.add_theme_color_override("font_pressed_color", Color(0.8, 0.6, 0.3))
		button.flat = true
		button.pressed.connect(_on_category_selected.bind(cat.id))
		category_tabs.add_child(button)
		category_buttons[cat.id] = button

	# Start with dining zone categories (zone 0)
	_update_visible_categories(0)

func _update_visible_categories(zone: int) -> void:
	"""Show/hide category buttons based on current zone."""
	var zone_cats: Array = ZONE_CATEGORIES.get(zone, [])

	print("[BUILD_SHOP] Updating categories for zone %d. Allowed: %s" % [zone, zone_cats])

	for cat_id in category_buttons:
		var button: Button = category_buttons[cat_id]
		var should_show: bool = (cat_id in zone_cats)
		button.visible = should_show
		button.disabled = not should_show  # Also disable to prevent clicking

		if should_show:
			print("[BUILD_SHOP]   ✅ %s button visible" % cat_id)
		else:
			print("[BUILD_SHOP]   ❌ %s button hidden" % cat_id)

	# If current category is not in zone, switch to first available
	if not current_category in zone_cats and zone_cats.size() > 0:
		print("[BUILD_SHOP] Current category '%s' not in zone, switching to '%s'" % [current_category, zone_cats[0]])
		_on_category_selected(zone_cats[0])

func _on_category_selected(category: String) -> void:
	"""Switch to a different category."""
	current_category = category
	print("[BUILD_SHOP] Selected category: %s" % category)

	# Update button styles
	for cat_id in category_buttons:
		var button: Button = category_buttons[cat_id]
		if cat_id == category:
			# Selected style (gold)
			button.add_theme_color_override("font_color", Color(0.8, 0.6, 0.3))
		else:
			# Normal style (cream)
			button.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))

	# Refresh items list
	_refresh_items()

func _refresh_items() -> void:
	"""Refresh the items list for current category."""
	# Clear existing items
	for child in items_container.get_children():
		child.queue_free()

	if not economy_manager:
		return

	# Get items for current category
	var items: Array[Dictionary] = economy_manager.get_placeable_items_by_category(current_category)

	# Special case: Premium category is empty for now
	if current_category == "premium":
		var label := Label.new()
		label.text = "⭐ Premium items coming soon!"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		items_container.add_child(label)
		return

	# Create item buttons
	for item in items:
		_create_item_button(item)

	print("[BUILD_SHOP] Loaded %d items for category: %s" % [items.size(), current_category])

func _create_item_button(item_data: Dictionary) -> void:
	"""Create a button for a placeable item."""
	var item_panel := PanelContainer.new()
	item_panel.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow mouse events to reach buttons

	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.6, 1.0, 0.5)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	item_panel.add_theme_stylebox_override("panel", style)

	# Margin container
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow mouse events to reach buttons
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	item_panel.add_child(margin)

	# Vertical layout
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow mouse events to reach buttons
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	# Top row: Icon + Name
	var top_hbox := HBoxContainer.new()
	top_hbox.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow mouse events to reach buttons
	top_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(top_hbox)

	# Icon
	var icon_label := Label.new()
	icon_label.text = item_data.get("icon", "📦")
	icon_label.add_theme_font_size_override("font_size", 32)
	top_hbox.add_child(icon_label)

	# Name
	var name_label := Label.new()
	name_label.text = item_data.get("name", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(1, 1, 0.8))
	top_hbox.add_child(name_label)

	# Description
	var desc_label := Label.new()
	desc_label.text = item_data.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)

	# Placement count label (shows X/Y placed)
	var item_id: String = item_data.get("id", "")
	var max_count: int = item_data.get("max_count", 999)
	var current_count: int = 0
	if build_mode_manager:
		current_count = build_mode_manager.get_placement_count(item_id)

	var count_label := Label.new()
	var count_ratio: float = float(current_count) / float(max_count) if max_count > 0 else 0.0
	var count_color := Color.GREEN if count_ratio < 0.7 else (Color.ORANGE if count_ratio < 1.0 else Color.RED)
	count_label.text = "Placed: %d/%d" % [current_count, max_count]
	count_label.add_theme_font_size_override("font_size", 16)
	count_label.add_theme_color_override("font_color", count_color)
	vbox.add_child(count_label)

	# Bottom row: Cost + Buy button
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow mouse events to reach buttons
	bottom_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(bottom_hbox)

	# Cost
	var cost_label := RichTextLabel.new()
	cost_label.bbcode_enabled = true
	cost_label.fit_content = true
	cost_label.scroll_active = false
	cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cost: float = item_data.get("cost", 0.0)
	cost_label.text = "[color=#CC9933]💰[/color] $%.2f" % cost
	cost_label.add_theme_font_size_override("normal_font_size", 20)
	bottom_hbox.add_child(cost_label)

	# Action label (replaces button since whole panel is clickable)
	var action_label := Label.new()
	action_label.custom_minimum_size = Vector2(100, 35)
	action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Check if affordable or at limit
	var at_limit: bool = current_count >= max_count
	var can_afford: bool = economy_manager and economy_manager.can_afford(cost)

	if not can_afford:
		action_label.text = "❌ Too Expensive"
		action_label.add_theme_color_override("font_color", Color(0.7, 0.3, 0.3))
		action_label.add_theme_font_size_override("font_size", 16)
		# Mark panel as disabled
		item_panel.set_meta("disabled", true)
		item_panel.set_meta("reason", "expensive")
	elif at_limit:
		action_label.text = "❌ Limit Reached"
		action_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		action_label.add_theme_font_size_override("font_size", 16)
		# Mark panel as disabled
		item_panel.set_meta("disabled", true)
		item_panel.set_meta("reason", "limit")
	else:
		action_label.text = "🖱️ Buy & Place"
		action_label.add_theme_color_override("font_color", Color(0.2, 1, 0.3))
		action_label.add_theme_font_size_override("font_size", 18)
		# Mark panel as enabled
		item_panel.set_meta("disabled", false)

	# Store item_id in panel for click detection
	item_panel.set_meta("item_id", item_id)

	bottom_hbox.add_child(action_label)

	print("[BUILD_SHOP] Created '%s' card - ID: %s, Disabled: %s" % [item_data.get("name", ""), item_id, item_panel.get_meta("disabled", false)])

	# Add to container
	items_container.add_child(item_panel)

func _handle_click(mouse_pos: Vector2) -> void:
	"""Handle mouse click forwarded from BuildModeManager (pause mode workaround)."""
	print("[BUILD_SHOP] Click received at: %v" % mouse_pos)

	# First check category tab buttons
	for cat_id in category_buttons:
		var button: Button = category_buttons[cat_id]
		if button and not button.disabled:  # Only process clicks on enabled buttons
			var btn_rect: Rect2 = button.get_global_rect()
			if btn_rect.has_point(mouse_pos):
				print("[BUILD_SHOP] Category button clicked: %s" % cat_id)
				_on_category_selected(cat_id)
				return

	# Check all item panels to see if click is inside their rect
	for child in items_container.get_children():
		# Each child is an item_panel (PanelContainer)
		if child is PanelContainer:
			var global_rect: Rect2 = child.get_global_rect()

			# Expand the clickable area by 20 pixels in all directions for easier clicking
			var expanded_rect := Rect2(
				global_rect.position.x - 20,
				global_rect.position.y - 20,
				global_rect.size.x + 40,
				global_rect.size.y + 40
			)

			print("[BUILD_SHOP] Panel rect: pos(%.1f, %.1f) size(%.1f, %.1f) - Click at: (%.1f, %.1f) - Contains: %s" % [
				expanded_rect.position.x, expanded_rect.position.y,
				expanded_rect.size.x, expanded_rect.size.y,
				mouse_pos.x, mouse_pos.y,
				expanded_rect.has_point(mouse_pos)
			])

			if expanded_rect.has_point(mouse_pos):
				# Get item info from panel metadata
				var item_id: String = child.get_meta("item_id", "")
				var is_disabled: bool = child.get_meta("disabled", false)
				var reason: String = child.get_meta("reason", "")

				print("[BUILD_SHOP] ✅ Panel clicked - ID: %s, Disabled: %s" % [item_id, is_disabled])

				# Check if item is disabled
				if is_disabled:
					if reason == "limit":
						print("[BUILD_SHOP] Placement limit reached for %s" % item_id)
					elif reason == "expensive":
						print("[BUILD_SHOP] Cannot afford %s" % item_id)
					return

				# Item is clickable and available - select it!
				if item_id != "":
					print("[BUILD_SHOP] Item selected: %s" % item_id)
					_on_item_selected(item_id)
					return

# Removed unused button helper functions - now using panel metadata directly

func _handle_right_click(mouse_pos: Vector2) -> void:
	"""Handle right-click on shop items - removes last placed item of that type."""
	print("[BUILD_SHOP] Right-click received at: %v" % mouse_pos)

	# Check all item panels to see if right-click is inside their rect
	for child in items_container.get_children():
		if child is PanelContainer:
			var global_rect: Rect2 = child.get_global_rect()
			var expanded_rect := Rect2(
				global_rect.position.x - 20,
				global_rect.position.y - 20,
				global_rect.size.x + 40,
				global_rect.size.y + 40
			)

			if expanded_rect.has_point(mouse_pos):
				var item_id: String = child.get_meta("item_id", "")
				if item_id != "":
					print("[BUILD_SHOP] Right-click on %s - removing last placed" % item_id)
					_on_item_right_clicked(item_id)
					return

func _on_item_right_clicked(item_id: String) -> void:
	"""Called when an item is right-clicked - removes last placed item of that type."""
	print("[BUILD_SHOP] ========== RIGHT-CLICK! Removing last %s ==========" % item_id)

	# Tell BuildModeManager to remove the last placed item
	if build_mode_manager:
		var success: bool = build_mode_manager.remove_last_placed_item(item_id)
		if success:
			print("[BUILD_SHOP] ✅ Successfully removed last %s!" % item_id)
			# Refresh items list to update counts and affordability
			_refresh_items()
			# Update money display
			_update_money_display()
		else:
			print("[BUILD_SHOP] ❌ Failed to remove %s (no removable items or all are permanent)" % item_id)
	else:
		print("[BUILD_SHOP] ERROR: build_mode_manager is NULL!")

func _on_item_selected(item_id: String) -> void:
	"""Called when an item is clicked - instantly purchases and places it."""
	selected_item_id = item_id
	print("[BUILD_SHOP] ========== ITEM CLICKED! Purchasing and placing: %s ==========" % item_id)

	# Instantly purchase and place the item
	if build_mode_manager:
		var success: bool = build_mode_manager.purchase_and_place_item(item_id)
		if success:
			print("[BUILD_SHOP] ✅ Successfully purchased and placed %s!" % item_id)
			# Refresh items list to update counts and affordability
			_refresh_items()
			# Update money display
			_update_money_display()
		else:
			print("[BUILD_SHOP] ❌ Failed to purchase/place %s" % item_id)
			# Error message is already handled by BuildModeManager
	else:
		print("[BUILD_SHOP] ERROR: build_mode_manager is NULL!")

	item_selected.emit(item_id)

func show_shop() -> void:
	"""Show the build mode shop UI."""
	visible = true
	is_open = true

	# Set initial alpha to 0 for fade-in animation
	if sidebar_panel:
		sidebar_panel.modulate.a = 0.0

	# Update money display
	_update_money_display()

	# Refresh items to update affordability
	_refresh_items()

	print("[BUILD_SHOP] Shop opened")

func hide_shop() -> void:
	"""Hide the build mode shop UI."""
	visible = false
	is_open = false
	print("[BUILD_SHOP] Shop closed")

func _update_money_display() -> void:
	"""Update the money label."""
	if not economy_manager or not money_label:
		return

	var money: float = economy_manager.current_money
	money_label.text = "[color=#CC9933]💰[/color] $%.2f" % money

func _on_money_changed(_new_amount: float, _change: float) -> void:
	"""Called when money changes."""
	_update_money_display()

	# Refresh items to update affordability
	if is_open:
		_refresh_items()

# Grid system removed - instant placement now

func _process(_delta: float) -> void:
	"""Update money display every frame (for real-time updates)."""
	if is_open:
		_update_money_display()

## ========== ZONE SYSTEM INTEGRATION ==========

func refresh_for_zone(zone: int) -> void:
	"""Refresh UI for a specific zone - updates categories and items."""
	print("[BUILD_SHOP] Refreshing for zone: %d" % zone)

	current_zone = zone

	# Update visible category buttons
	_update_visible_categories(zone)

	# Refresh items for current category
	_refresh_items()

	# Update money display
	_update_money_display()

func fade_out(duration: float) -> void:
	"""Fade out animation for zone transitions."""
	var tween := create_tween()
	tween.tween_property(sidebar_panel, "modulate:a", 0.0, duration)
	await tween.finished

func fade_in(duration: float) -> void:
	"""Fade in animation for zone transitions."""
	sidebar_panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(sidebar_panel, "modulate:a", 1.0, duration)
	await tween.finished
