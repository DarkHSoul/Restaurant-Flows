# Build Mode Setup Guide

## Manual Scene Modifications Required

The build mode system requires adding nodes to **Main3D.tscn**. Since .tscn files are binary and complex, these changes must be made in the Godot editor.

---

## Step 1: Add BuildModeManager

1. Open `src/main/scenes/Main3D.tscn` in Godot editor
2. Add a new **Node** as child of the root (Main3D)
3. **Name it:** `BuildModeManager`
4. **Attach script:** `res://src/systems/scripts/BuildModeManager.gd`
5. **Set process mode:** Always (so it works during pause)

---

## Step 2: Add BuildModeCamera

1. In Main3D scene, add a new **Camera3D** as child of the root
2. **Name it:** `BuildModeCamera`
3. **Add to group:** `build_mode_camera` (in Node tab → Groups → Add)
4. **Set properties:**
   - **Position:** (0, 15, -10) - 15 units above center, 10 units back
   - **Rotation (degrees):** (-60, 0, 0) - 60° downward angle
   - **FOV:** 60
   - **Current:** OFF (false) - Don't make it active camera by default
5. **Optional:** Adjust position to center over your restaurant layout

---

## Step 3: Add BuildModeShopUI

1. In Main3D scene, instantiate `res://src/ui/scenes/BuildModeShopUI.tscn`
2. This will add the sidebar UI as a CanvasLayer
3. It should be invisible by default (script handles this)

---

## Step 4: Verify Existing Nodes

Make sure these nodes exist in Main3D:
- ✅ **GameManager** (should already exist)
- ✅ **Player** in "player" group (PlayerController)
- ✅ **Floor/Ground** with collision layer 1 (for raycast placement)

---

## Alternative: Quick Add via Script

If you prefer, you can add these nodes via a temporary setup script:

```gdscript
# Temporary setup script - run once in Main3D _ready()
func _setup_build_mode():
    # Add BuildModeManager
    var build_manager = Node.new()
    build_manager.name = "BuildModeManager"
    build_manager.set_script(preload("res://src/systems/scripts/BuildModeManager.gd"))
    build_manager.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(build_manager)

    # Add BuildModeCamera
    var build_cam = Camera3D.new()
    build_cam.name = "BuildModeCamera"
    build_cam.add_to_group("build_mode_camera")
    build_cam.position = Vector3(0, 15, -10)
    build_cam.rotation_degrees = Vector3(-60, 0, 0)
    build_cam.fov = 60.0
    build_cam.current = false
    add_child(build_cam)

    # Add BuildModeShopUI
    var shop_ui_scene = preload("res://src/ui/scenes/BuildModeShopUI.tscn")
    var shop_ui = shop_ui_scene.instantiate()
    add_child(shop_ui)

    print("[SETUP] Build mode nodes added!")
```

Then call `_setup_build_mode()` in Main3D's `_ready()` function ONCE, then remove the function.

---

## Testing the Setup

1. Run the game
2. Press **P** during gameplay
3. You should see:
   - Camera smoothly transition to bird's eye view (1 second)
   - Sidebar shop UI appears on left
   - Mouse becomes visible
   - Player controls disabled
4. Try:
   - Clicking category tabs (Kitchen, Furniture, Utility)
   - Selecting an item to place
   - Mouse shows green/red ghost preview
   - **Q/E** to rotate preview
   - **G** to toggle grid snapping
   - **Left Click** to place (if enough money)
   - **ESC** to exit build mode

---

## Debug Messages to Expect

```
[BUILD_MODE] BuildModeManager ready!
[BUILD_SHOP] BuildModeShopUI ready!
[BUILD_MODE] Found first-person camera
[BUILD_MODE] Found build mode camera
[BUILD_MODE] Found build mode shop UI
[BUILD_MODE] Entering build mode...
[PLAYER] Controls disabled
[BUILD_SHOP] Shop opened
[BUILD_MODE] Build mode active!
```

---

## Common Issues & Fixes

### "Cameras not found!" error
- **Fix:** Make sure BuildModeCamera is in group "build_mode_camera"
- **Fix:** Make sure PlayerController exists in "player" group

### Camera doesn't transition smoothly
- **Fix:** Check BuildModeCamera rotation is (-60, 0, 0) degrees
- **Fix:** Verify position is high enough (Y=15 or more)

### Placement preview not showing
- **Fix:** Make sure floor has collision layer 1 (Environment)
- **Fix:** Check EconomyManager.PLACEABLE_ITEMS has valid prefab paths

### Grid snapping not working
- **Fix:** Press **G** to toggle grid on
- **Fix:** Check BuildModeManager.grid_size (default 0.5m)

### Can't afford items
- **Fix:** Use debug console to add money: `EconomyManager.instance.add_money(1000, "debug")`

---

## Camera Position Recommendations

Depending on your restaurant size, you may need to adjust camera position:

- **Small restaurant (10x10m):** Position (0, 12, -8), Rotation (-60, 0, 0)
- **Medium restaurant (20x20m):** Position (0, 18, -12), Rotation (-60, 0, 0)
- **Large restaurant (30x30m):** Position (0, 25, -15), Rotation (-65, 0, 0)

You can also make the camera height adjustable in build mode later!

---

## Next Steps

After setup is complete:
1. Test placing all item types (tables, ovens, etc.)
2. Verify placed items become functional immediately
3. Test save/load with placed items (future feature)
4. Add visual grid lines on floor (optional enhancement)
5. Add item rotation preview arrows (optional enhancement)

---

**Setup created by:** Claude Code
**Date:** 2025-01-28
**Build Mode Version:** 1.0
