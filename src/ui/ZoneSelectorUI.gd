extends CanvasLayer
class_name ZoneSelectorUI

## Zone selector UI - Bottom-center navigation between build zones

signal zone_changed(new_zone: int)

@onready var left_arrow: Button = $CenterContainer/HBoxContainer/LeftArrow
@onready var right_arrow: Button = $CenterContainer/HBoxContainer/RightArrow
@onready var zone_panel: PanelContainer = $CenterContainer/HBoxContainer/ZonePanel
@onready var zone_label: Label = $CenterContainer/HBoxContainer/ZonePanel/ZoneLabel

var current_zone: int = 0  # BuildModeManager.Zone enum
var is_transitioning: bool = false

func _ready() -> void:
	# Connect button signals
	if left_arrow:
		left_arrow.pressed.connect(_on_left_arrow_pressed)
	if right_arrow:
		right_arrow.pressed.connect(_on_right_arrow_pressed)

	# Start hidden
	visible = false

func _input(event: InputEvent) -> void:
	if not visible or is_transitioning:
		return

	# Left/Right arrow keys for zone navigation
	if event.is_action_pressed("ui_left"):
		_on_left_arrow_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_on_right_arrow_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_shop"):  # Tab key
		_cycle_zone()
		get_viewport().set_input_as_handled()

func show_selector() -> void:
	"""Show the zone selector UI."""
	visible = true
	# Set label alpha to 0 for fade-in animation (panel stays visible)
	if zone_label:
		zone_label.modulate.a = 0.0

func hide_selector() -> void:
	"""Hide the zone selector UI."""
	visible = false

func update_zone_display(zone: int, zone_name: String, item_count: int = -1) -> void:
	"""Update the zone label with current zone info."""
	current_zone = zone

	if item_count >= 0:
		zone_label.text = "%s (%d)" % [zone_name, item_count]
	else:
		zone_label.text = zone_name

	# Update arrow states (both always enabled for 2-zone system)
	if left_arrow:
		left_arrow.disabled = false
	if right_arrow:
		right_arrow.disabled = false

func set_transitioning(transitioning: bool) -> void:
	"""Set transitioning state to prevent spam."""
	is_transitioning = transitioning
	if left_arrow:
		left_arrow.disabled = transitioning
	if right_arrow:
		right_arrow.disabled = transitioning

func fade_out(duration: float) -> void:
	"""Fade out animation - only fade the label, not the panel."""
	if not zone_label:
		return
	var tween := create_tween()
	tween.tween_property(zone_label, "modulate:a", 0.0, duration)
	await tween.finished

func fade_in(duration: float) -> void:
	"""Fade in animation - only fade the label, not the panel."""
	if not zone_label:
		return
	zone_label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(zone_label, "modulate:a", 1.0, duration)
	await tween.finished

func _on_left_arrow_pressed() -> void:
	"""Navigate to previous zone."""
	if is_transitioning:
		return

	# Cycle: DINING <-> KITCHEN
	var new_zone: int = 1 if current_zone == 0 else 0
	zone_changed.emit(new_zone)

func _on_right_arrow_pressed() -> void:
	"""Navigate to next zone."""
	if is_transitioning:
		return

	# Cycle: DINING <-> KITCHEN
	var new_zone: int = 1 if current_zone == 0 else 0
	zone_changed.emit(new_zone)

func _cycle_zone() -> void:
	"""Cycle to next zone (Tab key handler)."""
	if is_transitioning:
		return

	var new_zone: int = 1 if current_zone == 0 else 0
	zone_changed.emit(new_zone)
