# Getting Started

This guide gets you from zero to a fully working spatial audio source in about five minutes.

---

## Step 1 — Replace your AudioStreamPlayer3D

Wherever you currently have an `AudioStreamPlayer3D` in your scene, replace it with a `SpatialAudioPlayer3D`. All existing properties (stream, volume_db, bus, autoplay, etc.) work exactly as before.

> **No code changes needed** — `SpatialAudioPlayer3D` is a drop-in replacement. Calls to `play()`, `stop()`, and `is_playing()` all work the same way.

If you're creating one fresh:

1. In your scene tree, click **Add Child Node**.
2. Search for `SpatialAudioPlayer3D`.
3. Assign an `AudioStream` to the **Stream** property.

---

## Step 2 — Configure the basics in the Inspector

With the node selected, you'll see several new export groups. Sensible defaults are applied out of the box, but you'll typically want to tweak:

| Property | Suggestion |
|---|---|
| `inner_radius` | Distance at which the sound plays at full volume (e.g. `2.0 m`) |
| `falloff_distance` | How far beyond that the sound fades to silence (e.g. `20.0 m`) |
| `max_raycast_distance` | Should match or exceed `inner_radius + falloff_distance` |
| `attenuation_function` | `NATURAL_SOUND` is a good starting point for most sources |
| `room_size_reverb` | Leave **on** for enclosed/varied environments |
| `audio_occlusion` | Leave **on** if there are walls between the source and player |

---

## Step 3 — Give your walls acoustic properties

For occlusion and reverb to react to surface type, add an `AcousticBody` to your collision geometry:

1. Select a `StaticBody3D` (or `CSGShape3D`) in your scene.
2. Click **Add Child Node** → `AcousticBody`.
3. In the `AcousticBody` Inspector, click the `acoustic_material` slot and load one of the **built-in presets** from `addons/spatial_audio_extended/presets/` (e.g. `concrete.tres`).

Repeat for every distinct surface type (walls, floor, glass partitions, etc.). Surfaces without an `AcousticBody` use the player's `fallback_transmission` value.

> **Editor shortcut:** When a `CollisionShape3D` or `CSGShape3D` is selected, the Inspector shows an **"Add AcousticBody"** button — click it to skip the Add Node dialog.

---

## Step 4 — Enable the debug overlay during development

Select your `SpatialAudioPlayer3D` and in the **Debug** export group, enable:

- `debug_draw_rays` — see the room-sensing raycasts
- `debug_draw_radius` — cyan inner radius + orange outer radius spheres
- `display_debug_info` — on-screen HUD showing distance, reverb, occlusion, etc.

Press **F1** (default) while playing to toggle all effects on/off for an A/B comparison.

---

## Step 5 — Reflected proxy pathing around corners (experimental)

If you want corner-aware reflected audio routing:

1. Add `SpatialReflectionNavigationAgent3D` at the source location.
2. Add your `SpatialAudioPlayer3D` as a child of the agent (or assign it via `audio_player_node`).
3. Enable `move_audio_player`.
4. Set `navigation_profile` to:
   - `HALLWAYS` for tight indoor corridors.
   - `OPEN_AREAS` for open maps.
5. Use debug overlays to validate bounds/pathing.

See **[[SpatialReflectionNavigationAgent3D Reference]]** for full configuration.

---

## Minimal GDScript example

```gdscript
# Your player or game manager script

@onready var footstep_player := $FootstepSpatialAudio # SpatialAudioPlayer3D

func _on_player_stepped():
 footstep_player.play()
```

Because `SpatialAudioPlayer3D` overrides `play()`, all spatial audio effects apply automatically — no extra code needed.

---

## Sound speed delay example (gunshot, explosion)

```gdscript
@onready var explosion := $ExplosionAudio # SpatialAudioPlayer3D

func detonate():
 # Enable in the Inspector, or set at runtime:
 explosion.enable_sound_delay = true
 explosion.speed_of_sound = 343.0
 explosion.play()
 # The audio will play after distance / 343 seconds automatically.
```

---

## Responding to signals

```gdscript
func _ready():
 $MySpatialAudio.audio_occluded.connect(_on_occluded)
 $MySpatialAudio.inner_radius_entered.connect(_on_player_close)

func _on_occluded(listener, wall_count):
 print("Sound blocked by %d wall(s)!" % wall_count)

func _on_player_close(listener):
 print("Player is very close to the sound source!")
```

See the **[[Signals Reference]]** page for the full list.
