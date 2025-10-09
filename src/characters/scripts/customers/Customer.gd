extends CharacterBody3D

## Signals ------------------------------------------------------------------
## Emitted when the customer finishes travelling to the current destination.
signal destination_reached(customer: Node, label: StringName)
## Emitted whenever the internal state of the customer changes.
signal state_changed(customer: Node, state: int)

## Enumerated states used by the simple state machine that drives the
## customer behaviour.
enum State { IDLE, MOVING, WAITING, EXITING }

## --- Tunables --------------------------------------------------------------
## Movement speed in metres per second.
@export var move_speed: float = 2.6
## Acceleration applied when the customer starts moving.
@export var acceleration: float = 6.0
## Distance tolerance used when checking if the customer has arrived.
@export var arrival_tolerance: float = 0.3

## --- Internal bookkeeping --------------------------------------------------
var _state: State = State.IDLE
var _current_label: StringName = &""
var _target_position: Vector3 = Vector3.ZERO
var _has_target: bool = false

@onready var _agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

func _ready() -> void:
    if _agent:
        _agent.velocity_computed.connect(_on_agent_velocity_computed)
    state_changed.emit(self, _state)

func move_to(position: Vector3, label: StringName = &"") -> void:
    ## Ask the customer to walk towards a world position.
    _target_position = position
    _target_position.y = global_transform.origin.y
    _current_label = label
    _has_target = true

    if _agent:
        _agent.target_position = _target_position

    _set_state(State.MOVING)

func wait(label: StringName = &"") -> void:
    ## Transition into a waiting state without clearing the current label.
    _current_label = label if label != &"" else _current_label
    _has_target = false
    velocity = Vector3.ZERO
    _set_state(State.WAITING)

func exit_world(exit_position: Vector3) -> void:
    ## Helper used by the spawner to dismiss the customer from the scene.
    move_to(exit_position, &"exit")
    _set_state(State.EXITING)

func _physics_process(delta: float) -> void:
    match _state:
        State.MOVING, State.EXITING:
            _update_movement(delta)
        _:
            velocity = Vector3.ZERO

func _update_movement(delta: float) -> void:
    if not _has_target:
        return

    var target: Vector3 = _target_position
    if _agent and not _agent.is_navigation_finished():
        target = _agent.get_next_path_position()

    var delta_vector: Vector3 = target - global_transform.origin
    delta_vector.y = 0.0

    if delta_vector.length() <= arrival_tolerance:
        _finish_movement()
        return

    var desired_velocity: Vector3 = delta_vector.normalized() * move_speed
    velocity = velocity.move_toward(desired_velocity, acceleration * delta)
    move_and_slide()

    if _agent:
        _agent.set_velocity(velocity)

func _finish_movement() -> void:
    velocity = Vector3.ZERO
    _has_target = false
    if _agent:
        _agent.set_velocity(Vector3.ZERO)

    if _state == State.EXITING:
        destination_reached.emit(self, _current_label)
        queue_free()
        return

    _set_state(State.WAITING)
    destination_reached.emit(self, _current_label)

func _on_agent_velocity_computed(safe_velocity: Vector3) -> void:
    if _state not in [State.MOVING, State.EXITING]:
        return
    velocity = safe_velocity
    move_and_slide()

func _set_state(new_state: State) -> void:
    if _state == new_state:
        return
    _state = new_state
    state_changed.emit(self, _state)
