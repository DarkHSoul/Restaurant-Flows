## SaveLoadSlotUI - Reusable component for displaying a single save slot
## Shows metadata, handles slot selection, and provides delete/rename functionality
extends PanelContainer

## Emitted when this slot is clicked for load/save
signal slot_selected(slot_number: int)
## Emitted when delete button is clicked
signal delete_requested(slot_number: int)
## Emitted when rename is requested
signal rename_requested(slot_number: int)

@export var slot_number: int = 1
@export var show_delete_button: bool = true
@export var show_rename_button: bool = true

var _metadata: Dictionary = {}
var _is_empty: bool = true

@onready var _slot_button: Button = $MarginContainer/VBoxContainer/SlotButton
@onready var _slot_name_label: Label = $MarginContainer/VBoxContainer/SlotButton/VBoxContainer/SlotNameLabel
@onready var _level_money_label: Label = $MarginContainer/VBoxContainer/SlotButton/VBoxContainer/LevelMoneyLabel
@onready var _timestamp_label: Label = $MarginContainer/VBoxContainer/SlotButton/VBoxContainer/TimestampLabel
@onready var _playtime_label: Label = $MarginContainer/VBoxContainer/SlotButton/VBoxContainer/PlaytimeLabel
@onready var _button_container: HBoxContainer = $MarginContainer/VBoxContainer/ButtonContainer
@onready var _delete_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/DeleteButton
@onready var _rename_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/RenameButton

func _ready() -> void:
	_slot_button.pressed.connect(_on_slot_button_pressed)
	_delete_button.pressed.connect(_on_delete_button_pressed)
	_rename_button.pressed.connect(_on_rename_button_pressed)

	_delete_button.visible = show_delete_button
	_rename_button.visible = show_rename_button

	refresh_display()

## Refresh the display with current save data
func refresh_display() -> void:
	if not SaveManager.instance:
		_display_empty_slot()
		return

	_metadata = SaveManager.instance.get_save_metadata(slot_number)
	_is_empty = _metadata.is_empty()

	if _is_empty:
		_display_empty_slot()
	else:
		_display_save_data()

func _display_empty_slot() -> void:
	_slot_name_label.text = "Empty Slot %d" % slot_number
	_level_money_label.text = "No save data"
	_timestamp_label.text = ""
	_playtime_label.text = ""
	_button_container.visible = false
	_slot_button.disabled = false

func _display_save_data() -> void:
	var slot_name: String = _metadata.get("slot_name", "Save %d" % slot_number)
	var level: int = _metadata.get("level", 1)
	var money: float = _metadata.get("money", 0.0)
	var reputation: float = _metadata.get("reputation", 100.0)
	var save_date: String = _metadata.get("save_date", "Unknown")
	var play_time: float = _metadata.get("play_time", 0.0)

	_slot_name_label.text = slot_name
	_level_money_label.text = "Level %d | $%.2f | Rep: %.0f%%" % [level, money, reputation]
	_timestamp_label.text = "Saved: %s" % _format_timestamp(save_date)
	_playtime_label.text = "Playtime: %s" % _format_playtime(play_time)
	_button_container.visible = show_delete_button or show_rename_button
	_slot_button.disabled = false

func _format_timestamp(datetime_string: String) -> String:
	# Parse datetime string format: "2025-10-28 14:35:22"
	if datetime_string.is_empty() or datetime_string == "Unknown":
		return "Unknown"

	var parts := datetime_string.split(" ")
	if parts.size() < 2:
		return datetime_string

	var date := parts[0]
	var time := parts[1]

	# Format as: Oct 28, 14:35
	var date_parts := date.split("-")
	if date_parts.size() == 3:
		var month_names := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
		var month_idx := date_parts[1].to_int() - 1
		var month: String = month_names[month_idx] if month_idx >= 0 and month_idx < 12 else date_parts[1]
		var day := date_parts[2]
		var time_short := time.substr(0, 5)  # HH:MM
		return "%s %s, %s" % [month, day, time_short]

	return datetime_string

func _format_playtime(seconds: float) -> String:
	var hours := int(seconds) / 3600
	var minutes := (int(seconds) % 3600) / 60

	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	else:
		return "%dm" % minutes

func _on_slot_button_pressed() -> void:
	slot_selected.emit(slot_number)

func _on_delete_button_pressed() -> void:
	delete_requested.emit(slot_number)

func _on_rename_button_pressed() -> void:
	rename_requested.emit(slot_number)

## Check if this slot is empty
func is_empty() -> bool:
	return _is_empty
