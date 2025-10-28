extends Button
class_name StyledToggle

## Custom toggle button (replacement for CheckBox) with styled ON/OFF states

signal state_changed(enabled: bool)

@export var is_on: bool = false:
	set(value):
		is_on = value
		_update_visual_state()

# Colors
const COLOR_ON = Color(0.8, 0.6, 0.3, 1.0)        # Gold
const COLOR_OFF = Color(0.3, 0.3, 0.3, 0.6)       # Dark gray
const COLOR_TEXT_ON = Color(1.0, 0.95, 0.85, 1)
const COLOR_TEXT_OFF = Color(0.6, 0.55, 0.5, 0.8)

var switch_tween: Tween = null

func _ready() -> void:
	custom_minimum_size = Vector2(120, 45)
	flat = true

	# Set initial text
	_update_text()

	# Connect button press
	pressed.connect(_on_pressed)

	# Initial visual state
	_update_visual_state()

func _on_pressed() -> void:
	"""Toggle state on press."""
	is_on = not is_on
	state_changed.emit(is_on)

	# Play toggle animation
	_play_toggle_animation()

func _update_text() -> void:
	"""Update button text based on state."""
	text = "ON" if is_on else "OFF"

func _update_visual_state() -> void:
	"""Update button appearance based on state."""
	_update_text()

	# Kill existing tween
	if switch_tween and switch_tween.is_valid():
		switch_tween.kill()

	# Animate color change
	switch_tween = create_tween()
	switch_tween.set_ease(Tween.EASE_OUT)
	switch_tween.set_trans(Tween.TRANS_CUBIC)
	switch_tween.set_parallel()

	if is_on:
		# ON state
		switch_tween.tween_property(self, "modulate", COLOR_ON, 0.3)
		add_theme_color_override("font_color", COLOR_TEXT_ON)
		add_theme_font_size_override("font_size", 22)
	else:
		# OFF state
		switch_tween.tween_property(self, "modulate", COLOR_OFF, 0.3)
		add_theme_color_override("font_color", COLOR_TEXT_OFF)
		add_theme_font_size_override("font_size", 20)

func _play_toggle_animation() -> void:
	"""Play bounce animation when toggled."""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.2)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.3)

func set_state(enabled: bool) -> void:
	"""Programmatically set toggle state."""
	is_on = enabled

func get_state() -> bool:
	"""Get current toggle state."""
	return is_on
