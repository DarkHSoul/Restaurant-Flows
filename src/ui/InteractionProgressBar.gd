extends Control
class_name InteractionProgressBar

## Circular progress bar for hold-to-interact actions

@onready var progress_bar: ProgressBar = $TextureProgressBar
@onready var label: Label = $Label
@onready var progress_ring: Control = $ProgressRing

@export var fill_time: float = 1.5  # Time in seconds to fill completely
@export var decay_speed: float = 2.0  # How fast it decays when not holding (multiplier)

var current_progress: float = 0.0
var is_holding: bool = false
var target_object: Node3D = null
var action_text: String = "Interact"

signal interaction_completed(target: Node3D)

func _ready() -> void:
	visible = false
	current_progress = 0.0
	if progress_bar:
		progress_bar.value = 0
	_setup_circular_progress()

func _process(delta: float) -> void:
	if not visible:
		return

	if is_holding:
		# Fill progress
		current_progress += (100.0 / fill_time) * delta
		current_progress = min(current_progress, 100.0)

		# Check if completed
		if current_progress >= 100.0:
			_complete_interaction()
	else:
		# Decay progress
		current_progress -= (100.0 / fill_time) * decay_speed * delta
		current_progress = max(current_progress, 0.0)

		# Hide if empty
		if current_progress <= 0.0:
			hide_progress()

	# Update visual
	if progress_bar:
		progress_bar.value = current_progress
	_draw_circular_progress()

func start_interaction(target: Node3D, text: String = "Taking Order") -> void:
	"""Start showing the progress bar for an interaction."""
	target_object = target
	action_text = text

	if label:
		label.text = text

	visible = true
	current_progress = 0.0
	if progress_bar:
		progress_bar.value = 0

func set_holding(holding: bool) -> void:
	"""Set whether the player is currently holding the interact key."""
	is_holding = holding

func hide_progress() -> void:
	"""Hide the progress bar."""
	visible = false
	current_progress = 0.0
	is_holding = false
	target_object = null

func _complete_interaction() -> void:
	"""Called when the interaction is completed."""
	var completed_target := target_object
	hide_progress()

	if completed_target:
		interaction_completed.emit(completed_target)

func get_progress() -> float:
	"""Get current progress (0-100)."""
	return current_progress

func _setup_circular_progress() -> void:
	"""Setup circular progress rendering."""
	pass  # CircularProgress script handles its own drawing

func _draw_circular_progress() -> void:
	"""Update circular progress ring."""
	if progress_ring and "progress" in progress_ring:
		progress_ring.progress = current_progress
