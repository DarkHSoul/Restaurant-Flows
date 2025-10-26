extends Control

## Custom circular progress ring drawer

var progress: float = 0.0:
	set(value):
		progress = clamp(value, 0.0, 100.0)
		queue_redraw()

@export var ring_color: Color = Color(0, 0.8, 0.2, 1.0)
@export var background_color: Color = Color(0.3, 0.3, 0.3, 0.5)
@export var ring_thickness: float = 10.0
@export var ring_radius_offset: float = 15.0

func _draw() -> void:
	var center := size / 2.0
	var radius: float = min(center.x, center.y) - ring_radius_offset
	var progress_angle := (progress / 100.0) * TAU
	var start_angle := -PI / 2.0  # Start from top (12 o'clock)

	# Draw background circle
	draw_arc(center, radius, 0, TAU, 64, background_color, ring_thickness, true)

	# Draw progress arc
	if progress > 0:
		draw_arc(center, radius, start_angle, start_angle + progress_angle, 64, ring_color, ring_thickness, true)
