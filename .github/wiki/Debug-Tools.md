# Debug Tools

`SpatialAudioPlayer3D` includes a comprehensive debugging system that works both in the editor and at runtime.

---

## In-Editor Visualisation

Whenever a `SpatialAudioPlayer3D` node is **selected** in the editor, the following are drawn automatically in the 3D viewport — no extra settings required:

- **Blue lines** — omni room-sensing rays (direction and length represent detected geometry).
- **Red lines** — escaped rays (no surface hit within `max_raycast_distance`) or occluded target ray.
- **Green line** — target ray toward the editor camera (clear line of sight).
- **Cyan wireframe sphere** — inner radius.
- **Orange wireframe sphere** — outer boundary (`inner_radius + falloff_distance`).
- **Small wireframe sphere at origin** — playback state indicator.

These overlays help you tune `inner_radius`, `falloff_distance`, and `max_raycast_distance` visually without running the game.

---

## Runtime Debug Properties

Enable these in the **Debug** export group on the node:

| Property | What It Shows |
|---|---|
| `debug_draw_rays` | Coloured raycast lines during gameplay (same colour scheme as editor). |
| `debug_draw_radius` | Cyan (inner) and orange (outer) radius wireframe spheres during gameplay. |
| `debug_draw_playing_state` | Small sphere at the emitter: **Green** = playing, **Yellow** = delay pending, **Red** = stopped. The sphere scales with camera distance so it stays visible at range. |
| `display_debug_info` | On-screen HUD with full diagnostics (see below). |

---

## Debug HUD

When `display_debug_info` is enabled, a panel appears on-screen whenever the listener is within range. It shows:

| Field | Description |
|---|---|
| Listener dist | Current distance to listener and effective max distance |
| Attenuation | Inner/outer radius, current zone (INNER / FALLOFF / OUTSIDE), and attenuation function |
| Air absorption | Current target cutoff and min/max distances |
| Occluded | YES / NO, wall count, and material names of hit surfaces |
| Lowpass cutoff | Current and target cutoff in Hz |
| Reverb wet | Current and target reverb wetness, and max wetness cap |
| Reverb room | Current and target room size |
| Reverb damp | Current and target reverb damping |
| Avg absorption | Average absorption across all omni ray hits and count of surfaces |
| Openness | Percentage and environment label (INDOOR / SEMI-OPEN / OUTDOOR) |
| Floor ignore | Whether floor exclusion is active and the threshold angle |
| Est. room size | Estimated room diameter in metres (average hit distance × 2) |
| Volume | Current and target volume in dB |
| Effects | Whether effects are on/off per-instance and globally |
| Bus | The name and index of the dynamically created audio bus |
| Ray mode | Distribution type and omni ray count |
| Navigation proxy | Proxy-routing diagnostics injected by `SpatialReflectionNavigationAgent3D` while reflected proxy mode is active |

### Multiple Sources

When multiple `SpatialAudioPlayer3D` nodes all have `display_debug_info` enabled, their panels are stacked in a shared scrollable container in the top-left corner of the screen. Each panel can be individually minimised.

### Navigation Dropdown (Proxy Mode)

When a `SpatialAudioPlayer3D` is being driven by `SpatialReflectionNavigationAgent3D` in reflected proxy mode, the HUD shows a **Navigation** dropdown with:

- Agent name and navigation profile
- Path point count, path length, direct distance, and detour ratio
- Graph point/edge counts
- Proxy waypoint index and distances to listener/origin/target
- Backoff and spring-arm state
- Current solve rate (Hz)

---

## Debug Keyboard Shortcuts

While the debug HUD is visible (and the listener is in range), two keys are active:

| Key | Action |
|---|---|
| `F1` (default, `debug_toggle_effects_key`) | Toggle **all spatial audio effects** on/off for an A/B comparison. |
| `F2` (default, `debug_toggle_shapes_key`) | Toggle **debug shape drawing** (rays and radius spheres) on/off. |

You can change both keys in the Inspector under the **Debug** export group.

---

## Ray List Panel

Inside the debug HUD, click the **▶ Rays (N)** toggle to expand a scrollable list of all rays and their measured distances:

- **Normal ray** — shows distance in metres.
- **Escaped ray** — shows `∞ (open)` in red.
- **Floor-ignored ray** — shows `(floor)` in grey.
- **Material tag** — if the ray hit an `AcousticMaterial`, shows the material name and absorption value.
- **Reflection rays** (Fibonacci mode with `fibonacci_ray_reflections > 0`) — show `▶ seg N (N refl)` with an expandable dropdown listing per-segment distances and escape status.

---

## `spatial_audio_debug` Signal

For programmatic access to the same data, connect to the `spatial_audio_debug` signal. It fires every update cycle while the debug HUD is visible:

```gdscript
func _ready():
 $MySpatialAudio.display_debug_info = true
 $MySpatialAudio.spatial_audio_debug.connect(_on_debug_info)

func _on_debug_info(info: Dictionary):
 # info.keys(): distance, volume_db_target, lowpass_cutoff,
 # reverb_room_size, reverb_wetness, reverb_damping, wall_count,
 # navigation_proxy_active, navigation
 %DistanceLabel.text = "%.1f m" % info.distance
```

See **[[Signals Reference]]** for the full dictionary schema.

---

## Global Effect Toggle (Code)

You can disable all spatial effects globally from code, useful for a performance/accessibility mode:

```gdscript
# Disable effects on ALL SpatialAudioPlayer3D instances
SpatialAudioPlayer3D.set_global_effects_disabled(true)

# Re-enable
SpatialAudioPlayer3D.set_global_effects_disabled(false)
```
