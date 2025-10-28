# Remaining Build Mode Implementation

## ⚠️ CRITICAL: Add Zone Areas to Scene

**File:** `src/main/scenes/Main3D.tscn` (use Godot editor)

1. Open Main3D.tscn in Godot editor
2. Create KitchenZone:
   - Add Node → Area3D, name: "KitchenZone"
   - Add child: CollisionShape3D
   - Set shape to BoxShape3D
   - Position and size to cover kitchen area (where ovens/stoves are)
   - In Node tab: Add to group "kitchen_zone"
   - Set collision_layer = 0, collision_mask = 0 (no physics, just detection)

3. Create DiningZone:
   - Add Node → Area3D, name: "DiningZone"
   - Add child: CollisionShape3D
   - Set shape to BoxShape3D
   - Position and size to cover dining area (where tables are)
   - In Node tab: Add to group "dining_zone"
   - Set collision_layer = 0, collision_mask = 0

**Without these zones, placement will be blocked everywhere!**

---

## Phase 4: Item Removal System (Right-Click, 50% Refund)

### 4.1 Add Right-Click Detection in Build Mode
**File:** `src/systems/scripts/BuildModeManager.gd`

In `_process()` function, after updating preview position, add:

```gdscript
# Handle right-click removal (only when NOT placing)
if not placement_preview and Input.is_action_just_pressed("ui_cancel"):  # Right mouse
    var mouse_pos := get_viewport().get_mouse_position()
    var camera_pos := build_mode_camera.project_ray_origin(mouse_pos)
    var camera_dir := build_mode_camera.project_ray_normal(mouse_pos)

    var space_state := build_mode_camera.get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.create(
        camera_pos,
        camera_pos + camera_dir * 1000.0
    )
    query.collision_mask = 0b10000  # Layer 4 (Interactables)

    var result := space_state.intersect_ray(query)
    if result:
        var clicked_object = result.collider
        _attempt_remove_item(clicked_object)
```

### 4.2 Implement Removal Logic
**File:** `src/systems/scripts/BuildModeManager.gd`

Add function at end of file:

```gdscript
func _attempt_remove_item(item: Node3D) -> void:
    """Try to remove a placed item (right-click removal with refund)."""
    # Find which type this item is
    for item_type in placed_items:
        if item in placed_items[item_type]:
            # Get item data for refund
            if not economy_manager:
                return

            var item_data: Dictionary = economy_manager.get_placeable_item(item_type)
            if item_data.is_empty():
                return

            var cost: float = item_data.get("cost", 0.0)
            var refund: float = cost * 0.5  # 50% refund

            # Remove from tracking
            placed_items[item_type].erase(item)

            # Remove from scene
            var position := item.global_position
            item.queue_free()

            # Give refund
            economy_manager.add_money(refund, "building_refund")

            # Emit signal
            item_removed.emit(item_type, position)

            # Show feedback
            error_message = "Removed %s (+$%.2f refund)" % [item_data.get("name", "item"), refund]
            error_message_timer = 3.0

            print("[BUILD_MODE] Removed %s at %v, refunded $%.2f" % [item_type, position, refund])

            # Refresh UI to update counts
            if build_mode_shop_ui and build_mode_shop_ui.has_method("_refresh_items"):
                build_mode_shop_ui._refresh_items()

            return

    # Not a removable item
    print("[BUILD_MODE] Clicked object is not a placed item")
```

### 4.3 Visual Feedback for Removable Items
**File:** `src/systems/scripts/BuildModeManager.gd`

In `_process()`, add hover detection:

```gdscript
# Show hover outline on removable items
if not placement_preview:
    var mouse_pos := get_viewport().get_mouse_position()
    var camera_pos := build_mode_camera.project_ray_origin(mouse_pos)
    var camera_dir := build_mode_camera.project_ray_normal(mouse_pos)

    var space_state := build_mode_camera.get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.create(camera_pos, camera_pos + camera_dir * 1000.0)
    query.collision_mask = 0b10000

    var result := space_state.intersect_ray(query)
    if result:
        var hovered_object = result.collider
        if _is_item_removable(hovered_object):
            _highlight_removable_item(hovered_object)
            # Show tooltip: "Right-click to remove (50% refund)"
```

---

## Phase 5: Right-Side Upgrades Panel

### 5.1 Create UI Structure
**File:** `src/ui/scenes/BuildModeShopUI.tscn` (use Godot editor)

1. Open BuildModeShopUI.tscn
2. Add new PanelContainer as child of root CanvasLayer
   - Name: "RightSidebarPanel"
   - Anchors: Right (1.0, 0.0, 1.0, 1.0)
   - Offset Left: -350, Right: 0
   - Width: 350px (matching left sidebar)

3. Add children to RightSidebarPanel:
   ```
   RightSidebarPanel (PanelContainer)
     └─ MarginContainer
         └─ VBoxContainer
             ├─ TitleLabel: "⬆️ Upgrades"
             ├─ MoneyLabel (duplicate from left)
             ├─ UpgradesScroll (ScrollContainer)
             │   └─ UpgradesContainer (VBoxContainer)
             └─ InfoLabel: "Station & kitchen upgrades"
   ```

### 5.2 Render Upgrades List
**File:** `src/ui/BuildModeShopUI.gd`

Add reference in `_ready()`:

```gdscript
@onready var right_sidebar: PanelContainer = $RightSidebarPanel
@onready var upgrades_container: VBoxContainer = $RightSidebarPanel/MarginContainer/VBoxContainer/UpgradesScroll/UpgradesContainer
```

Add function:

```gdscript
func _create_upgrades_panel() -> void:
    """Create upgrade cards for build-related upgrades."""
    # Clear existing
    for child in upgrades_container.get_children():
        child.queue_free()

    if not economy_manager:
        return

    # Filter build-related upgrades
    var upgrade_types := ["station", "new_station"]

    for upgrade_id in EconomyManager.UPGRADES:
        var upgrade_data: Dictionary = EconomyManager.UPGRADES[upgrade_id]
        var upgrade_type: String = upgrade_data.get("type", "")

        if upgrade_type in upgrade_types:
            _create_upgrade_card(upgrade_id, upgrade_data)
```

### 5.3 Create Upgrade Cards
**File:** `src/ui/BuildModeShopUI.gd`

```gdscript
func _create_upgrade_card(upgrade_id: String, upgrade_data: Dictionary) -> void:
    """Create a card for a single upgrade."""
    var is_owned: bool = economy_manager.owned_upgrades.has(upgrade_id)

    var card := PanelContainer.new()
    # Style similar to item cards...

    # Show:
    # - Upgrade name & icon
    # - Description (effect details)
    # - Cost
    # - "Owned ✓" (green) or "Purchase" button
    # - Disable if unaffordable or already owned
```

### 5.4 Purchase Integration
Connect buttons:

```gdscript
func _on_upgrade_button_pressed(upgrade_id: String) -> void:
    if economy_manager:
        economy_manager.purchase_upgrade(upgrade_id)
        _create_upgrades_panel()  # Refresh
```

---

## Phase 6: Save/Load Integration

### 6.1 Save Placed Items
**File:** `src/systems/scripts/SaveManager.gd`

In `save_game()` function, after saving other data:

```gdscript
# Save build mode placed items
if BuildModeManager.instance:
    var placed_items_data: Array = BuildModeManager.instance.get_placed_items_data()
    save_file.set_value("build_mode", "placed_items", placed_items_data)
```

### 6.2 Load Placed Items
**File:** `src/systems/scripts/SaveManager.gd`

In `load_game()` function, after loading other data:

```gdscript
# Load build mode placed items
if save_file.has_section("build_mode"):
    var placed_items_data: Array = save_file.get_value("build_mode", "placed_items", [])
    if BuildModeManager.instance and placed_items_data.size() > 0:
        # Wait for scene to be ready
        await get_tree().process_frame
        BuildModeManager.instance.restore_placed_items(placed_items_data)
```

---

## Testing Checklist

### Placement System
- [ ] Enter build mode (Tab key)
- [ ] Pre-placed items counted correctly
- [ ] Placement counts show "Placed: X/Y"
- [ ] Cannot place beyond limit (button disabled)
- [ ] Error message shows when at limit

### Zone Restrictions
- [ ] Cannot place tables in kitchen area
- [ ] Cannot place ovens/stoves in dining area
- [ ] Trash bins can go in both zones
- [ ] Error message shows "Cannot place here - wrong zone!"

### Item Removal
- [ ] Right-click on placed item removes it
- [ ] Get 50% refund
- [ ] Count decrements
- [ ] Button re-enables after removal
- [ ] Pre-placed items can be removed

### Upgrades Panel
- [ ] Right sidebar shows upgrades
- [ ] Build-related upgrades only (not business)
- [ ] Owned upgrades show checkmark
- [ ] Purchase button works
- [ ] Unaffordable upgrades grayed out

### Save/Load
- [ ] Save game preserves placed items
- [ ] Load game restores all placed items
- [ ] Positions and rotations preserved
- [ ] Counts update correctly after load

---

## Current Status

✅ **Completed:**
- Placement tracking system
- Placement limits (5-10 items per type)
- Zone-based restrictions (code ready)
- UI count displays
- Limit enforcement

⚠️ **Needs Immediate Attention:**
- Add KitchenZone and DiningZone Area3D to Main3D.tscn
- Without zones, placement is blocked everywhere!

📋 **Remaining Work:**
- Item removal system (Phase 4)
- Right-side upgrades panel (Phase 5)
- Save/load integration (Phase 6)
- Testing and debugging

---

## Quick Test Guide

1. Run game and enter build mode (Tab)
2. Check debug output for:
   ```
   [BUILD_MODE] Scanning scene for existing placed objects...
   [BUILD_MODE] Found 1 existing oven
   [BUILD_MODE] Found 1 existing stove
   [BUILD_MODE] Found 3 existing table
   ```
3. Try placing items - should see counts update
4. Try placing 6th oven - should be blocked
5. Zone restrictions won't work until Area3D nodes added!

---

## Notes

- Error messages display for 3 seconds via `error_message` + `error_message_timer`
- BuildModeManager tracks all placed items in `placed_items` dictionary
- UI refreshes on build mode entry via `scan_existing_objects()`
- Preview color: Green (valid), Red (invalid/zone/limit)
- All limits are "moderate" tier: Oven:5, Stove:5, PrepCounter:3, Table:10, TrashBin:5, ServingCounter:3
