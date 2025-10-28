## SaveGameMenu - UI for saving games
## Displays 5 save slots with metadata and handles save/overwrite operations
extends Control

signal back_pressed
signal game_saved

@onready var _slots_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/SlotsContainer
@onready var _back_button: Button = $MarginContainer/VBoxContainer/BackButton
@onready var _title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var _confirmation_dialog: ConfirmationDialog = $ConfirmationDialog
@onready var _rename_dialog: AcceptDialog = $RenameDialog
@onready var _rename_input: LineEdit = $RenameDialog/MarginContainer/VBoxContainer/RenameInput

var _slot_uis: Array = []
var _pending_save_slot: int = -1
var _pending_delete_slot: int = -1
var _pending_rename_slot: int = -1

func _ready() -> void:
	_back_button.pressed.connect(_on_back_button_pressed)
	_confirmation_dialog.confirmed.connect(_on_overwrite_confirmed)
	_rename_dialog.confirmed.connect(_on_rename_confirmed)

	_setup_slot_uis()
	refresh_slots()

func _input(event: InputEvent) -> void:
	# Handle ESC to go back to pause menu
	if event.is_action_pressed("ui_cancel"):
		# Check if any dialog is open
		if _confirmation_dialog.visible or _rename_dialog.visible:
			# Let dialogs handle ESC
			return

		# Go back to pause menu
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()

func _setup_slot_uis() -> void:
	# Load the SaveLoadSlotUI scene
	var slot_scene := preload("res://src/ui/scenes/SaveLoadSlotUI.tscn")

	for i in range(1, 6):  # 5 slots
		var slot_ui = slot_scene.instantiate()
		slot_ui.slot_number = i
		slot_ui.show_delete_button = true
		slot_ui.show_rename_button = false  # Don't show rename until after saving
		slot_ui.slot_selected.connect(_on_slot_selected)
		slot_ui.delete_requested.connect(_on_delete_requested)

		_slots_container.add_child(slot_ui)
		_slot_uis.append(slot_ui)

func refresh_slots() -> void:
	for slot_ui in _slot_uis:
		slot_ui.refresh_display()

func _on_slot_selected(slot_number: int) -> void:
	if not SaveManager.instance:
		push_error("SaveManager not found!")
		return

	# Check if slot already has save data (needs overwrite confirmation)
	if SaveManager.instance.has_save(slot_number):
		_pending_save_slot = slot_number
		var metadata := SaveManager.instance.get_save_metadata(slot_number)
		var slot_name: String = metadata.get("slot_name", "Save %d" % slot_number)
		_confirmation_dialog.dialog_text = "Overwrite existing save?\n\n%s" % slot_name
		_confirmation_dialog.popup_centered()
	else:
		# Empty slot - save immediately
		_save_to_slot(slot_number)

func _save_to_slot(slot_number: int) -> void:
	if not SaveManager.instance:
		return

	print("[SaveGameMenu] Saving game to slot %d..." % slot_number)

	if SaveManager.instance.save_game(slot_number):
		print("[SaveGameMenu] Game saved successfully to slot %d" % slot_number)
		refresh_slots()
		game_saved.emit()

		# No delay needed - just return to pause menu immediately
		# (Previously had await timer that would freeze when game is paused)
	else:
		push_error("Failed to save game to slot %d" % slot_number)

func _on_overwrite_confirmed() -> void:
	if _pending_save_slot < 1:
		return

	_save_to_slot(_pending_save_slot)
	_pending_save_slot = -1

func _on_delete_requested(slot_number: int) -> void:
	if not SaveManager.instance.has_save(slot_number):
		return

	_pending_delete_slot = slot_number

	# Use a separate dialog for delete confirmation
	var delete_dialog := ConfirmationDialog.new()
	delete_dialog.dialog_text = "Are you sure you want to delete this save?\nThis action cannot be undone."
	delete_dialog.title = "Confirm Delete"
	delete_dialog.ok_button_text = "Delete"
	delete_dialog.cancel_button_text = "Cancel"
	delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(delete_dialog)
	delete_dialog.popup_centered()

func _on_delete_confirmed() -> void:
	if _pending_delete_slot < 1:
		return

	if SaveManager.instance:
		SaveManager.instance.delete_save(_pending_delete_slot)
		refresh_slots()

	_pending_delete_slot = -1

func _on_rename_requested(slot_number: int) -> void:
	_pending_rename_slot = slot_number

	# Get current name
	var current_name := ""
	if SaveManager.instance:
		current_name = SaveManager.instance.get_slot_name(slot_number)

	_rename_input.text = current_name
	_rename_dialog.title = "Rename Save Slot %d" % slot_number
	_rename_dialog.popup_centered()
	_rename_input.grab_focus()

func _on_rename_confirmed() -> void:
	if _pending_rename_slot < 1:
		return

	var new_name := _rename_input.text.strip_edges()
	if new_name.is_empty():
		new_name = "Save %d" % _pending_rename_slot

	if SaveManager.instance:
		SaveManager.instance.set_slot_name(_pending_rename_slot, new_name)
		refresh_slots()

	_pending_rename_slot = -1

func _on_back_button_pressed() -> void:
	back_pressed.emit()
	queue_free()
