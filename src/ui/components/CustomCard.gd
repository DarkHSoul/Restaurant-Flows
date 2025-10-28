extends PanelContainer
class_name CustomCard

## Custom styled card container with slide-in animation and hover effects

@export var card_title: String = "CARD TITLE"
@export var card_emoji: String = "⚙"
@export var slide_delay: float = 0.0  # Delay before slide-in animation

# Colors (matching Main Menu theme)
const COLOR_BG = Color(0.12, 0.10, 0.08, 0.95)     # Dark brown
const COLOR_BORDER = Color(0.8, 0.6, 0.3, 0.6)     # Gold border
const COLOR_TEXT = Color(1.0, 0.95, 0.85, 1)       # Light cream

var is_animating: bool = false
var hover_tween: Tween = null

func _ready() -> void:
	# Create custom StyleBox
	_setup_style()

	# Setup mouse events for hover effect
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _setup_style() -> void:
	"""Setup custom card styling."""
	var style = StyleBoxFlat.new()

	# Background
	style.bg_color = COLOR_BG

	# Border
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = COLOR_BORDER

	# Corner radius
	style.corner_radius_top_left = 15
	style.corner_radius_top_right = 15
	style.corner_radius_bottom_right = 15
	style.corner_radius_bottom_left = 15

	# Shadow
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 5)

	# Content margins
	style.content_margin_left = 20
	style.content_margin_top = 15
	style.content_margin_right = 20
	style.content_margin_bottom = 15

	add_theme_stylebox_override("panel", style)

func play_slide_in_animation() -> void:
	"""Play slide-in animation from right."""
	if is_animating:
		return

	is_animating = true

	# Start off-screen to the right and invisible
	modulate.a = 0.0
	position.x += 300

	# Create slide-in tween
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_parallel()

	# Fade in and slide in
	tween.tween_property(self, "modulate:a", 1.0, 0.5).set_delay(slide_delay)
	tween.tween_property(self, "position:x", position.x - 300, 0.6).set_delay(slide_delay)

	await tween.finished
	is_animating = false

func _on_mouse_entered() -> void:
	"""Add subtle hover effect."""
	if hover_tween and hover_tween.is_valid():
		hover_tween.kill()

	hover_tween = create_tween()
	hover_tween.set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(self, "scale", Vector2(1.02, 1.02), 0.2)

func _on_mouse_exited() -> void:
	"""Remove hover effect."""
	if hover_tween and hover_tween.is_valid():
		hover_tween.kill()

	hover_tween = create_tween()
	hover_tween.set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)
