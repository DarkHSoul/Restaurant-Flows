extends CanvasLayer
class_name BuildModeUpgradesUI

## Build Mode Upgrades Panel - Right-side panel for station upgrades

## Signals
signal upgrade_purchased(upgrade_id: String)

## Node references
@onready var sidebar_panel: PanelContainer = $SidebarPanel
@onready var title_label: Label = $SidebarPanel/MarginContainer/VBoxContainer/TitleLabel
@onready var upgrades_scroll: ScrollContainer = $SidebarPanel/MarginContainer/VBoxContainer/UpgradesScroll
@onready var upgrades_container: VBoxContainer = $SidebarPanel/MarginContainer/VBoxContainer/UpgradesScroll/UpgradesContainer

## State
var is_open: bool = false

## References
var economy_manager: EconomyManager
var build_mode_manager: BuildModeManager

## Build-related upgrade filter (only show these types)
const BUILD_UPGRADE_TYPES := ["station", "new_station", "capacity"]

func _ready() -> void:
	# Add to build_mode_upgrades group
	add_to_group("build_mode_upgrades")

	# Find managers
	economy_manager = EconomyManager.instance
	build_mode_manager = BuildModeManager.instance

	# Connect to economy signals
	if economy_manager:
		economy_manager.upgrade_purchased.connect(_on_upgrade_purchased)
		economy_manager.money_changed.connect(_on_money_changed)

	# Start hidden
	visible = false
	is_open = false

	print("[BUILD_UPGRADES] BuildModeUpgradesUI ready!")

func show_panel() -> void:
	"""Show the upgrades panel."""
	visible = true
	is_open = true

	# Refresh upgrades list
	_refresh_upgrades()

	print("[BUILD_UPGRADES] Panel opened")

func hide_panel() -> void:
	"""Hide the upgrades panel."""
	visible = false
	is_open = false
	print("[BUILD_UPGRADES] Panel closed")

func _refresh_upgrades() -> void:
	"""Refresh the upgrades list - only build-related upgrades."""
	# Clear existing items
	for child in upgrades_container.get_children():
		child.queue_free()

	if not economy_manager:
		return

	# Get all upgrades from EconomyManager
	var upgrades: Dictionary = economy_manager.UPGRADES
	var build_upgrades: Array = []

	# Filter to only build-related upgrades
	for upgrade_id in upgrades:
		var upgrade_data: Dictionary = upgrades[upgrade_id]
		var upgrade_type: String = upgrade_data.get("type", "")

		if upgrade_type in BUILD_UPGRADE_TYPES:
			build_upgrades.append({
				"id": upgrade_id,
				"data": upgrade_data
			})

	# Sort by cost (cheapest first)
	build_upgrades.sort_custom(func(a, b): return a.data.cost < b.data.cost)

	# Create upgrade cards
	for upgrade in build_upgrades:
		_create_upgrade_card(upgrade.id, upgrade.data)

	print("[BUILD_UPGRADES] Loaded %d build upgrades" % build_upgrades.size())

func _create_upgrade_card(upgrade_id: String, upgrade_data: Dictionary) -> void:
	"""Create a card for an upgrade."""
	var card_panel := PanelContainer.new()
	card_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.8, 0.6, 0.3, 0.5)  # Gold border
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	card_panel.add_theme_stylebox_override("panel", style)

	# Margin container
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card_panel.add_child(margin)

	# Vertical layout
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	# Title
	var name_label := Label.new()
	name_label.text = upgrade_data.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(1, 1, 0.8))
	vbox.add_child(name_label)

	# Description
	var desc_label := Label.new()
	desc_label.text = upgrade_data.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)

	# Bottom row: Cost + Status
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	bottom_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(bottom_hbox)

	# Cost
	var cost_label := RichTextLabel.new()
	cost_label.bbcode_enabled = true
	cost_label.fit_content = true
	cost_label.scroll_active = false
	cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cost: float = upgrade_data.get("cost", 0.0)
	cost_label.text = "[color=#CC9933]💰[/color] $%.2f" % cost
	cost_label.add_theme_font_size_override("normal_font_size", 18)
	bottom_hbox.add_child(cost_label)

	# Status label
	var status_label := Label.new()
	status_label.custom_minimum_size = Vector2(100, 35)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Check if already owned
	var is_owned: bool = economy_manager and economy_manager.owned_upgrades.has(upgrade_id)
	var can_afford: bool = economy_manager and economy_manager.can_afford(cost)

	if is_owned:
		status_label.text = "✅ Owned"
		status_label.add_theme_color_override("font_color", Color(0.2, 1, 0.3))
		status_label.add_theme_font_size_override("font_size", 16)
		card_panel.set_meta("disabled", true)
		card_panel.set_meta("reason", "owned")
	elif not can_afford:
		status_label.text = "❌ Too Expensive"
		status_label.add_theme_color_override("font_color", Color(0.7, 0.3, 0.3))
		status_label.add_theme_font_size_override("font_size", 14)
		card_panel.set_meta("disabled", true)
		card_panel.set_meta("reason", "expensive")
	else:
		status_label.text = "🖱️ Click to Buy"
		status_label.add_theme_color_override("font_color", Color(0.2, 1, 0.3))
		status_label.add_theme_font_size_override("font_size", 16)
		card_panel.set_meta("disabled", false)

	# Store upgrade_id in panel for click detection
	card_panel.set_meta("upgrade_id", upgrade_id)

	bottom_hbox.add_child(status_label)

	# Add to container
	upgrades_container.add_child(card_panel)

func _handle_click(mouse_pos: Vector2) -> void:
	"""Handle mouse click forwarded from BuildModeManager (pause mode workaround)."""
	print("[BUILD_UPGRADES] Click received at: %v" % mouse_pos)

	# Check all upgrade panels to see if click is inside their rect
	for child in upgrades_container.get_children():
		if child is PanelContainer:
			var global_rect: Rect2 = child.get_global_rect()

			# Expand the clickable area by 20 pixels in all directions
			var expanded_rect := Rect2(
				global_rect.position.x - 20,
				global_rect.position.y - 20,
				global_rect.size.x + 40,
				global_rect.size.y + 40
			)

			if expanded_rect.has_point(mouse_pos):
				# Get upgrade info from panel metadata
				var upgrade_id: String = child.get_meta("upgrade_id", "")
				var is_disabled: bool = child.get_meta("disabled", false)
				var reason: String = child.get_meta("reason", "")

				print("[BUILD_UPGRADES] ✅ Panel clicked - ID: %s, Disabled: %s" % [upgrade_id, is_disabled])

				# Check if disabled
				if is_disabled:
					if reason == "owned":
						print("[BUILD_UPGRADES] Upgrade already owned: %s" % upgrade_id)
					elif reason == "expensive":
						print("[BUILD_UPGRADES] Cannot afford upgrade: %s" % upgrade_id)
					return

				# Upgrade is clickable - purchase it!
				if upgrade_id != "":
					_purchase_upgrade(upgrade_id)
					return

func _purchase_upgrade(upgrade_id: String) -> void:
	"""Purchase an upgrade."""
	if not economy_manager:
		return

	# Try to purchase through EconomyManager
	if economy_manager.purchase_upgrade(upgrade_id):
		print("[BUILD_UPGRADES] ✅ Purchased upgrade: %s" % upgrade_id)
		upgrade_purchased.emit(upgrade_id)

		# Refresh UI to show new status
		_refresh_upgrades()
	else:
		print("[BUILD_UPGRADES] ❌ Failed to purchase upgrade: %s" % upgrade_id)

func _on_upgrade_purchased(_upgrade_id: String, _cost: float) -> void:
	"""Called when any upgrade is purchased."""
	# Refresh UI to update affordability
	if is_open:
		_refresh_upgrades()

func _on_money_changed(_new_amount: float, _change: float) -> void:
	"""Called when money changes."""
	# Refresh UI to update affordability
	if is_open:
		_refresh_upgrades()
