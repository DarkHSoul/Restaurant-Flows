extends HSlider
class_name ModernSlider

## Modern thin slider with gold accent colors

@export var theme_color: Color = Color(0.8, 0.6, 0.3, 1.0)  # Gold

# Colors
const COLOR_TRACK_BG = Color(0.15, 0.12, 0.10, 1.0)         # Dark track
const COLOR_TRACK_FILL_START = Color(0.6, 0.45, 0.2, 1.0)   # Darker gold
const COLOR_TRACK_FILL_END = Color(0.8, 0.6, 0.3, 1.0)      # Bright gold
const COLOR_GRABBER = Color(1.0, 0.95, 0.85, 1.0)           # Light cream
const COLOR_GRABBER_HOVER = Color(1.0, 0.9, 0.7, 1.0)       # Warm cream

var is_hovering: bool = false
var is_activated: bool = false  # Whether slider is activated for input

func _ready() -> void:
	custom_minimum_size = Vector2(200, 25)
	focus_mode = Control.FOCUS_ALL  # Enable keyboard focus
	editable = false  # Start locked - must press Enter to edit
	_setup_style()

	# Connect signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	value_changed.connect(_on_value_changed)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)

func _unhandled_input(event: InputEvent) -> void:
	# Only process if we have focus
	if not has_focus():
		return

	# Toggle activation with Enter key
	if event.is_action_pressed("ui_accept"):
		is_activated = not is_activated
		editable = is_activated  # Lock/unlock slider
		_update_activation_visual()
		get_viewport().set_input_as_handled()

# Note: We use editable property instead of _gui_input blocking
# This is more reliable and prevents all slider interactions when locked

func _setup_style() -> void:
	"""Setup modern slider styling."""
	# Track background (empty part)
	var track_style = StyleBoxFlat.new()
	track_style.bg_color = COLOR_TRACK_BG
	track_style.corner_radius_top_left = 3
	track_style.corner_radius_top_right = 3
	track_style.corner_radius_bottom_left = 3
	track_style.corner_radius_bottom_right = 3
	track_style.content_margin_top = 8
	track_style.content_margin_bottom = 8

	add_theme_stylebox_override("slider", track_style)

	# Track fill (filled part) - will be updated with gradient
	_update_track_fill()

	# Grabber (the handle)
	var grabber_style = StyleBoxFlat.new()
	grabber_style.bg_color = COLOR_GRABBER
	grabber_style.corner_radius_top_left = 6
	grabber_style.corner_radius_top_right = 6
	grabber_style.corner_radius_bottom_left = 6
	grabber_style.corner_radius_bottom_right = 6
	grabber_style.shadow_color = Color(0, 0, 0, 0.4)
	grabber_style.shadow_size = 4
	grabber_style.shadow_offset = Vector2(0, 2)

	add_theme_stylebox_override("grabber_area", grabber_style)
	add_theme_stylebox_override("grabber_area_highlight", grabber_style)

	# Tick marks (optional, disable for clean look)
	add_theme_constant_override("tick_count", 0)

func _update_track_fill() -> void:
	"""Update the filled part of the track with gradient."""
	var fill_style = StyleBoxFlat.new()

	# Calculate gradient based on value
	var percent = (value - min_value) / (max_value - min_value)
	var current_color = COLOR_TRACK_FILL_START.lerp(COLOR_TRACK_FILL_END, percent)

	fill_style.bg_color = current_color
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	fill_style.content_margin_top = 8
	fill_style.content_margin_bottom = 8

	add_theme_stylebox_override("slider", fill_style)

func _on_value_changed(_new_value: float) -> void:
	"""Called when slider value changes."""
	_update_track_fill()

func _on_mouse_entered() -> void:
	"""Mouse entered slider area."""
	is_hovering = true
	# Subtle hover feedback even when not activated
	if not is_activated:
		_play_hover_animation()

func _on_mouse_exited() -> void:
	"""Mouse left slider area."""
	is_hovering = false
	# Remove hover feedback when mouse leaves
	if not is_activated:
		_play_unhover_animation()

func _play_hover_animation() -> void:
	"""Scale up slightly on hover."""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale:y", 1.05, 0.15)

func _play_unhover_animation() -> void:
	"""Scale back to normal."""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale:y", 1.0, 0.15)

func _on_focus_entered() -> void:
	"""Focus entered - show that Enter activates."""
	# Visual feedback that this slider has focus
	modulate = Color(1.2, 1.2, 1.2, 1.0)

	# Scale up slightly for prominence
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(self, "scale", Vector2(1.05, 1.15), 0.3)

func _on_focus_exited() -> void:
	"""Focus lost - deactivate and reset."""
	is_activated = false
	editable = false  # Lock slider when focus is lost
	modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Reset scale
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)

func _update_activation_visual() -> void:
	"""Update visual to show activation state."""
	if is_activated:
		# Activated - brighter
		modulate = Color(1.3, 1.3, 1.0, 1.0)
	else:
		# Not activated - normal focus look
		modulate = Color(1.2, 1.2, 1.2, 1.0)

func set_theme_color(color: Color) -> void:
	"""Update the theme color for this slider."""
	theme_color = color
	# Update colors based on theme
	# This allows user to change the color scheme
	_setup_style()
