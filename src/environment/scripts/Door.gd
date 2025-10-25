extends Node3D
class_name Door

## Interactive door that can open and close

signal door_opened
signal door_closed

## Door properties
@export_group("Door Settings")
@export var is_open: bool = false
@export var open_angle: float = 90.0  # Degrees to rotate when open
@export var open_speed: float = 2.0  # Rotation speed
@export var auto_close: bool = false
@export var auto_close_delay: float = 2.0

## Visual properties
@export_group("Visual")
@export var door_color: Color = Color(0.6, 0.4, 0.2)
@export var highlight_color: Color = Color.YELLOW

## Internal state
var _is_highlighted: bool = false
var _is_animating: bool = false
var _target_rotation: float = 0.0
var _start_rotation: float = 0.0
var _auto_close_timer: float = 0.0

@onready var _visual: MeshInstance3D = $DoorPivot/Visual if has_node("DoorPivot/Visual") else null
@onready var _door_pivot: AnimatableBody3D = $DoorPivot if has_node("DoorPivot") else null
@onready var _nav_obstacle: NavigationObstacle3D = $NavigationObstacle3D if has_node("NavigationObstacle3D") else null

func _ready() -> void:
	if _door_pivot:
		_door_pivot.collision_layer = 0b10001  # Layer 1 (environment) + Layer 5 (interactables)
		_door_pivot.collision_mask = 0
		_start_rotation = _door_pivot.rotation.y
		_target_rotation = _start_rotation

		# Add reference to parent door for interaction detection
		_door_pivot.set_meta("parent_door", self)

	# Setup navigation obstacle to block pathfinding when door is closed
	if _nav_obstacle:
		_nav_obstacle.avoidance_enabled = not is_open

	_update_visual()

func _physics_process(delta: float) -> void:
	if _is_animating:
		_animate_door(delta)

	if is_open and auto_close:
		_auto_close_timer += delta
		if _auto_close_timer >= auto_close_delay:
			close()

## Public interface

func can_interact() -> bool:
	"""Check if player can interact with door."""
	return not _is_animating

func interact(player: Node3D) -> void:
	"""Toggle door open/closed."""
	if _is_animating:
		return

	if is_open:
		close()
	else:
		open()

func open() -> void:
	"""Open the door."""
	if is_open or _is_animating:
		return

	is_open = true
	_is_animating = true
	_target_rotation = _start_rotation + deg_to_rad(open_angle)
	_auto_close_timer = 0.0

	# Disable navigation obstacle when door opens
	if _nav_obstacle:
		_nav_obstacle.avoidance_enabled = false

	door_opened.emit()

func close() -> void:
	"""Close the door."""
	if not is_open or _is_animating:
		return

	is_open = false
	_is_animating = true
	_target_rotation = _start_rotation

	# Enable navigation obstacle when door closes
	if _nav_obstacle:
		_nav_obstacle.avoidance_enabled = true

	door_closed.emit()

func highlight(enabled: bool) -> void:
	"""Highlight door when player looks at it."""
	_is_highlighted = enabled
	_update_visual()

## Private methods

func _animate_door(delta: float) -> void:
	"""Animate door rotation."""
	if not _door_pivot:
		_is_animating = false
		return

	var current_rot := _door_pivot.rotation.y
	var new_rot := lerp_angle(current_rot, _target_rotation, delta * open_speed)

	_door_pivot.rotation.y = new_rot

	# Check if animation is complete
	if abs(new_rot - _target_rotation) < 0.01:
		_door_pivot.rotation.y = _target_rotation
		_is_animating = false

func _update_visual() -> void:
	"""Update visual appearance based on state."""
	if not _visual:
		return

	var material := StandardMaterial3D.new()

	if _is_highlighted:
		material.emission_enabled = true
		material.emission = highlight_color
		material.emission_energy = 0.3
		material.albedo_color = door_color
	else:
		material.albedo_color = door_color

	_visual.material_override = material
