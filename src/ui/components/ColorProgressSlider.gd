extends HSlider
class_name ColorProgressSlider

## Custom styled slider with gradient color transition based on value

@export var color_low: Color = Color(1.0, 0.4, 0.1, 1)     # Orange (0-33%)
@export var color_mid: Color = Color(1.0, 0.8, 0.3, 1)     # Yellow (34-66%)
@export var color_high: Color = Color(0.8, 0.6, 0.3, 1)    # Gold (67-100%)
@export var enable_hover_pulse: bool = true

var is_hovered: bool = false
var pulse_time: float = 0.0

func _ready() -> void:
	# Connect signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	value_changed.connect(_on_value_changed)

	# Initial color update
	_update_progress_color()

func _process(delta: float) -> void:
	if enable_hover_pulse and is_hovered:
		pulse_time += delta
		var pulse = 1.0 + sin(pulse_time * 8.0) * 0.05  # Subtle pulse
		modulate = Color(pulse, pulse, pulse, 1.0)
	else:
		modulate = Color.WHITE
		pulse_time = 0.0

func _on_value_changed(_new_value: float) -> void:
	"""Update color when value changes."""
	_update_progress_color()

func _update_progress_color() -> void:
	"""Calculate and apply gradient color based on current value."""
	var percent := (value - min_value) / (max_value - min_value)
	var final_color: Color

	if percent < 0.33:
		# Interpolate between low and mid
		var t := percent / 0.33
		final_color = color_low.lerp(color_mid, t)
	elif percent < 0.67:
		# Interpolate between mid and high
		var t := (percent - 0.33) / 0.34
		final_color = color_mid.lerp(color_high, t)
	else:
		# Interpolate to gold
		var t := (percent - 0.67) / 0.33
		final_color = color_mid.lerp(color_high, t)

	# Apply color to modulate (works with theme)
	add_theme_color_override("font_color", final_color)
	add_theme_color_override("grabber_highlight_color", final_color)

func _on_mouse_entered() -> void:
	is_hovered = true

func _on_mouse_exited() -> void:
	is_hovered = false
