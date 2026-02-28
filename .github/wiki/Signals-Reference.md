# Signals Reference

`SpatialAudioPlayer3D` emits a rich set of signals that let your game react to spatial audio events — zone transitions, occlusion changes, reverb updates, and more.

---

## Attenuation / Zone Transition Signals

These signals fire when the listener crosses the boundaries defined by `inner_radius` and `falloff_distance`.

| Signal | Arguments | Description |
|---|---|---|
| `inner_radius_entered(listener)` | `listener: Node3D` | Listener entered the inner (full-volume) radius. |
| `inner_radius_exited(listener)` | `listener: Node3D` | Listener left the inner radius. |
| `falloff_zone_entered(listener)` | `listener: Node3D` | Listener entered the falloff zone (between inner radius and outer boundary). |
| `falloff_zone_exited(listener)` | `listener: Node3D` | Listener left the falloff zone. |
| `attenuation_zone_entered(listener)` | `listener: Node3D` | Listener became audible (entered the outer boundary). |
| `attenuation_zone_exited(listener)` | `listener: Node3D` | Listener became inaudible (left the outer boundary). |

**Example use cases:** Trigger footstep sounds, activate enemy awareness, spawn particles near a sound source, show UI indicators.

```gdscript
$MySpatialAudio.inner_radius_entered.connect(func(listener):
 print("Player is right next to the source!")
)

$MySpatialAudio.attenuation_zone_exited.connect(func(listener):
 print("Player can no longer hear this sound.")
)
```

---

## Occlusion Signals

Emitted when walls come between the listener and the emitter, or when line-of-sight is restored.

| Signal | Arguments | Description |
|---|---|---|
| `audio_occluded(listener, wall_count)` | `listener: Node3D`, `wall_count: int` | Occlusion started — at least one wall is now blocking the path. |
| `audio_unoccluded(listener)` | `listener: Node3D` | Occlusion cleared — clear line of sight restored. |
| `occlusion_changed(wall_count, cutoff_hz)` | `wall_count: int`, `cutoff_hz: float` | Emitted whenever the wall count or lowpass cutoff changes. |
| `occlusion_ray_collided(hit_position, from_position, collider, listener)` | `Vector3`, `Vector3`, `Node`, `Node3D` | An occlusion ray hit a surface. Useful for VFX or custom logic. |

```gdscript
$MySpatialAudio.audio_occluded.connect(func(listener, wall_count):
 print("Blocked by %d wall(s)" % wall_count)
 # e.g. add a muffled subtitle indicator
)

$MySpatialAudio.audio_unoccluded.connect(func(listener):
 print("Clear line of sight!")
)
```

---

## Reverb / Room Signals

Emitted when the estimated room size or reverb parameters change significantly.

| Signal | Arguments | Description |
|---|---|---|
| `reverb_updated(room_size, wetness, damping)` | `float`, `float`, `float` | Detailed reverb targets changed (threshold: > 0.01 difference). |
| `reverb_zone_changed(room_size, wetness)` | `room_size: float`, `wetness: float` | Higher-level room zone change (emitted alongside `reverb_updated`). |

```gdscript
$MySpatialAudio.reverb_zone_changed.connect(func(room_size, wetness):
 if room_size > 0.7:
 print("Large open space detected")
 elif room_size < 0.2:
 print("Small enclosed room")
)
```

---

## Air Absorption Signals

Emitted when the air absorption lowpass cutoff changes.

| Signal | Arguments | Description |
|---|---|---|
| `air_absorption_updated(cutoff_hz)` | `cutoff_hz: float` | Air absorption cutoff changed by more than 1 Hz. |
| `air_absorption_zone_changed(cutoff_hz)` | `cutoff_hz: float` | Emitted alongside `air_absorption_updated` when distance thresholds are crossed. |

---

## Ray Collision Signals

Useful for custom visual effects or gameplay hooks on individual raycast hits.

| Signal | Arguments | Description |
|---|---|---|
| `occlusion_ray_collided(hit_position, from_position, collider, listener)` | `Vector3`, `Vector3`, `Node`, `Node3D` | The occlusion (target) ray hit a surface. |
| `reverb_ray_collided(hit_position, from_position, collider)` | `Vector3`, `Vector3`, `Node` | A reverb/reflection ray hit a surface during a bounce. |

---

## Playback Signals

| Signal | Arguments | Description |
|---|---|---|
| `spatial_audio_playback_started()` | — | Playback actually began (after any sound-speed delay). |
| `spatial_audio_playback_stopped()` | — | Playback was stopped via `stop()`. |
| `listener_distance_changed(distance)` | `distance: float` | Emitted periodically when the listener distance changes by ≥ 0.5 m. |

```gdscript
$MySpatialAudio.spatial_audio_playback_started.connect(func():
 print("Audio started playing!")
)
```

---

## Debug Signals

| Signal | Arguments | Description |
|---|---|---|
| `debug_overlay_toggled(visible)` | `visible: bool` | The debug overlay was minimised or expanded. |
| `spatial_audio_debug(info)` | `info: Dictionary` | Emitted every update cycle when the debug overlay is visible. |

### `spatial_audio_debug` Dictionary Keys

| Key | Type | Description |
|---|---|---|
| `distance` | `float` | Current listener distance in metres. |
| `volume_db_target` | `float` | Target volume level in dB. |
| `lowpass_cutoff` | `float` | Current target lowpass cutoff in Hz. |
| `reverb_room_size` | `float` | Current target reverb room size (0–1). |
| `reverb_wetness` | `float` | Current target reverb wetness (0–1). |
| `reverb_damping` | `float` | Current target reverb damping (0–1). |
| `wall_count` | `int` | Number of walls currently occluding the sound. |
| `navigation_proxy_active` | `bool` | `true` when external reflected proxy navigation debug data is attached. |
| `navigation` | `Dictionary` | Proxy-navigation diagnostics from `SpatialReflectionNavigationAgent3D` (present only when active). |

```gdscript
$MySpatialAudio.display_debug_info = true
$MySpatialAudio.spatial_audio_debug.connect(func(info):
 var nav_state := "OFF"
 if info.get("navigation_proxy_active", false):
  nav_state = "ON"
 $DebugLabel.text = "Distance: %.1f m | Walls: %d | Nav: %s" % [info.distance, info.wall_count, nav_state]
)
```

---

## SpatialReflectionNavigationAgent3D Signals

When using reflected proxy routing, the navigation agent emits:

| Signal | Arguments | Description |
|---|---|---|
| `path_updated(path_world, direct_path)` | `PackedVector3Array`, `bool` | Emitted whenever a path solve succeeds. |
| `path_failed(origin_world, target_world)` | `Vector3`, `Vector3` | Emitted when solve fails while direct line is blocked. |
| `audio_proxy_position_updated(proxy_world)` | `Vector3` | Emitted after proxy position updates. |
| `graph_rebuilt(point_count)` | `int` | Emitted when the sampled graph is rebuilt. |
