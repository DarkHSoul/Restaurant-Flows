extends VBoxContainer
class_name SidebarMenu

## Sidebar navigation menu for Settings categories

signal category_selected(category_id: String)

@export var categories: Array[String] = ["sound", "graphics", "color", "gui", "about"]
@export var category_labels: Array[String] = ["Sound Settings", "Graphics Settings", "Color Settings", "GUI Settings", "About"]
@export var category_icons: Array[String] = ["🔊", "🎨", "🎨", "⚙", "ℹ"]

# Colors (dark theme + gold accents)
const COLOR_BG_INACTIVE = Color(0.05, 0.04, 0.03, 0.95)    # Very dark brown
const COLOR_BG_ACTIVE = Color(0.8, 0.6, 0.3, 0.3)          # Gold translucent
const COLOR_BG_HOVER = Color(0.15, 0.12, 0.10, 1.0)        # Slightly lighter dark
const COLOR_TEXT_INACTIVE = Color(0.6, 0.55, 0.5, 0.9)     # Gray
const COLOR_TEXT_ACTIVE = Color(1.0, 0.95, 0.85, 1.0)      # Light cream
const COLOR_BORDER_ACTIVE = Color(0.8, 0.6, 0.3, 1.0)      # Gold

var buttons: Array[Button] = []
var active_category: String = "graphics"  # Default to graphics
var currently_focused_button: Button = null

func _ready() -> void:
	add_theme_constant_override("separation", 8)

	# Add padding to prevent focus border clipping
	# Top padding prevents Sound Settings border from being cut
	# Right padding prevents right edge overflow
	add_theme_constant_override("margin_top", 5)
	add_theme_constant_override("margin_bottom", 5)
	add_theme_constant_override("margin_left", 5)
	add_theme_constant_override("margin_right", 10)

	_create_category_buttons()
	_set_active_category("graphics")  # Default to Graphics Settings

func _create_category_buttons() -> void:
	"""Create a button for each category."""
	for i in range(categories.size()):
		var button := Button.new()
		var category_id := categories[i]
		var label := category_labels[i] if i < category_labels.size() else categories[i]
		var icon := category_icons[i] if i < category_icons.size() else ""

		# Button setup
		button.text = icon + " " + label if icon else label
		button.custom_minimum_size = Vector2(220, 60)  # Further reduced to prevent overflow
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_ALL  # Enable keyboard focus
		button.clip_text = true  # Prevent text overflow

		# Store category ID in metadata
		button.set_meta("category_id", category_id)

		# Connect signals
		button.pressed.connect(_on_category_button_pressed.bind(category_id))
		button.mouse_entered.connect(_on_button_hover.bind(button))
		button.mouse_exited.connect(_on_button_unhover.bind(button))
		button.focus_entered.connect(_on_button_focus_entered.bind(button))
		button.focus_exited.connect(_on_button_focus_exited.bind(button))

		# Styling
		_style_button(button, false)

		add_child(button)
		buttons.append(button)

	# After all buttons are created, set up focus neighbors to keep focus in sidebar
	await get_tree().process_frame
	_setup_focus_neighbors()

func _on_category_button_pressed(category_id: String) -> void:
	"""Handle category button press."""
	_set_active_category(category_id)
	category_selected.emit(category_id)

func _set_active_category(category_id: String) -> void:
	"""Set the active category and update button states."""
	active_category = category_id

	for button in buttons:
		var button_category = button.get_meta("category_id")
		var is_active = button_category == category_id
		_style_button(button, is_active)

		# If this button currently has focus, restore the focus text size
		if button == currently_focused_button:
			_enlarge_button_text(button, 1.2)

func _style_button(button: Button, is_active: bool) -> void:
	"""Apply styling to a category button."""
	# Create StyleBoxFlat
	var style = StyleBoxFlat.new()

	if is_active:
		style.bg_color = COLOR_BG_ACTIVE
		style.border_width_left = 3
		style.border_color = COLOR_BORDER_ACTIVE
		button.add_theme_color_override("font_color", COLOR_TEXT_ACTIVE)
	else:
		style.bg_color = COLOR_BG_INACTIVE
		style.border_width_left = 0
		button.add_theme_color_override("font_color", COLOR_TEXT_INACTIVE)

	# Rounded corners on right side
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8

	# Padding - reduced to prevent overflow
	style.content_margin_left = 15
	style.content_margin_top = 10
	style.content_margin_right = 8
	style.content_margin_bottom = 10

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)

	# Font size - bigger for better readability
	# Using smaller base size to prevent overflow
	button.add_theme_font_size_override("font_size", 18)

func _on_button_hover(button: Button) -> void:
	"""Add hover effect."""
	if button.get_meta("category_id") != active_category:
		# Transfer focus on hover
		button.grab_focus()

		# Remove scale animation - only use text size for better quality
		# Text size animation - smaller scale to prevent overflow
		_enlarge_button_text(button, 1.15)

func _on_button_unhover(button: Button) -> void:
	"""Remove hover effect."""
	if button != currently_focused_button and button.get_meta("category_id") != active_category:
		# Remove scale animation
		_reset_button_text(button)

func _on_button_focus_entered(button: Button) -> void:
	"""Keyboard focus entered - prominent visual feedback."""
	currently_focused_button = button

	# Remove scale animation - only use text size
	_enlarge_button_text(button, 1.2)

func _on_button_focus_exited(button: Button) -> void:
	"""Keyboard focus lost - reset."""
	if currently_focused_button == button:
		currently_focused_button = null

	if button.get_meta("category_id") != active_category:
		# Remove scale animation
		_reset_button_text(button)

func _enlarge_button_text(button: Button, scale_factor: float = 1.05) -> void:
	"""Enlarge the text inside a button."""
	if button.has_meta("text_tween"):
		var old_tween = button.get_meta("text_tween")
		if old_tween:
			old_tween.kill()

	var original_size = 18  # Match the base font size
	var target_size = int(original_size * scale_factor)

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)  # Smoother transition
	tween.tween_property(button, "theme_override_font_sizes/font_size", target_size, 0.15)
	button.set_meta("text_tween", tween)

func _reset_button_text(button: Button) -> void:
	"""Reset button text to original size."""
	if button.has_meta("text_tween"):
		var old_tween = button.get_meta("text_tween")
		if old_tween:
			old_tween.kill()

	var original_size = 18  # Match the base font size
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(button, "theme_override_font_sizes/font_size", original_size, 0.12)
	button.set_meta("text_tween", tween)

func get_active_category() -> String:
	"""Get the currently active category ID."""
	return active_category

func get_button_by_category(category_id: String) -> Button:
	for button in buttons:
		if button.get_meta("category_id") == category_id:
			return button
	return null

func _setup_focus_neighbors() -> void:
	"""Set up focus neighbors to keep navigation within sidebar."""
	for i in range(buttons.size()):
		var button = buttons[i]

		# Set up vertical navigation (up/down stays in sidebar)
		if i > 0:
			button.focus_neighbor_top = button.get_path_to(buttons[i - 1])
		else:
			# First button: wrap to last button when going up
			button.focus_neighbor_top = button.get_path_to(buttons[buttons.size() - 1])

		if i < buttons.size() - 1:
			button.focus_neighbor_bottom = button.get_path_to(buttons[i + 1])
		else:
			# Last button: wrap to first button when going down
			button.focus_neighbor_bottom = button.get_path_to(buttons[0])

		# Right arrow is handled by Godot's automatic focus system
		# It will find the next focusable control to the right
