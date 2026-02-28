# SpatialAudioPlayer3D Reference

`SpatialAudioPlayer3D` extends `AudioStreamPlayer3D` and serves as a drop-in replacement with physically-inspired spatial audio effects.

**Class:** `SpatialAudioPlayer3D` 
**Inherits:** `AudioStreamPlayer3D` 
**Script:** `spatial_audio_player_3d.gd`

---

## Enums

### RayDistribution

Controls how the omni-directional room-sensing rays are arranged around the emitter.

| Value | Description |
|---|---|
| `CLASSIC` | 10 predefined rays (cardinal + diagonal + up/down). Fast and predictable. |
| `FIBONACCI_SPHERE` | Evenly distributed rays using a Fibonacci sphere. Better coverage for complex geometry, supports reflections. |
| `SHAPE_SCATTER` | Rays scattered outward from a given collision shape node. Useful for large/irregular emitters. |

### AttenuationFunction

The falloff curve used between the inner radius and the outer boundary.

| Value | Description |
|---|---|
| `LINEAR` | Volume drops at a constant rate. Simple and predictable. |
| `LOGARITHMIC` | Faster drop-off close to the edge, slower tail. Good for spot sounds. |
| `INVERSE` | Very steep near the source, nearly silent far away. |
| `LOG_REVERSE` | Stays loud across distance, drops dramatically at the far end. |
| `NATURAL_SOUND` | Middle-ground between Logarithmic and Inverse. Closest to real-world behaviour. |
| `USER_DEFINED` | Uses a custom `Curve` resource you provide via `user_attenuation_curve`. |

---

## Exported Properties

> **Note on `volume_db`:** This property is managed internally by `SpatialAudioPlayer3D`. Editing it directly at runtime has no effect — use `max_db` to control maximum loudness and the attenuation settings below to control falloff.

### Ray Distribution

| Property | Type | Default | Description |
|---|---|---|---|
| `ray_distribution` | `RayDistribution` | `CLASSIC` | How room-sensing rays are arranged. |
| `fibonacci_ray_count` | `int` (4–128) | `8` | Number of rays in Fibonacci Sphere mode. More = better accuracy, higher CPU cost. |
| `fibonacci_ray_reflections` | `int` (0–8) | `0` | Reflection bounces per Fibonacci ray (0 = no reflections). Improves estimation in L-shaped rooms or corridors. |
| `scatter_shape` | `Node3D` | `null` | The node used as the scattering origin in Shape Scatter mode. |
| `shape_ray_count` | `int` (1–256) | `32` | Number of rays in Shape Scatter mode. |
| `shape_scatter_randomness` | `int` (0–50) | `0` | How randomly ray directions deviate from the center-to-surface direction. 0 = outward only, 50 = fully random. |
| `max_raycast_distance` | `float` (m) | `50.0` | Maximum distance all raycasts travel. Keep close to `max_distance`. |

### Room Size Reverb

| Property | Type | Default | Description |
|---|---|---|---|
| `room_size_reverb` | `bool` | `true` | Enable automatic reverb based on surrounding geometry. |
| `max_reverb_wetness` | `float` (0–1) | `0.5` | Global ceiling on reverb wetness, regardless of enclosure. |
| `surface_absorption` | `bool` | `true` | Modulate reverb using `AcousticMaterial` absorption on surfaces hit by rays. |
| `absorption_wetness_influence` | `float` (0–2) | `1.0` | How strongly surface absorption affects reverb wetness. |
| `absorption_damping_influence` | `float` (0–2) | `1.0` | How strongly surface absorption affects reverb damping. |
| `ignore_floor` | `bool` | `false` | Exclude downward rays from room-size calculations (prevents the floor from shrinking perceived room size). |
| `floor_angle_threshold` | `float` (5–90 deg) | `30.0` | Cone angle within which a ray is considered a "floor ray". |
| `reverb_collision_mask` | `int` (flags) | `1` | Physics layers the room-sensing raycasts collide with. |

### Occlusion

| Property | Type | Default | Description |
|---|---|---|---|
| `audio_occlusion` | `bool` | `true` | Enable wall occlusion simulation via a lowpass filter. |
| `occlusion_strength` | `float` (0–5) | `1.0` | How strongly the lowpass filter is applied when occluded. Values > 1 push beyond the occluded cutoff toward 20 Hz. |
| `max_occlusion_hits` | `int` (1–16) | `4` | Maximum walls detected between emitter and listener. Each wall further muffles the sound. |
| `fallback_transmission` | `float` (0–1) | `0.030` | Fraction of high-frequency sound that passes through surfaces without an `AcousticBody`. |
| `occlusion_volume_strength` | `float` (0–1) | `0.35` | How strongly walls reduce volume (in addition to lowpass filtering). |
| `max_occlusion_volume_reduction` | `float` (0–60 dB) | `18.0` | Maximum total volume reduction from wall occlusion. Prevents complete silence behind many walls (unless a hit material has `total_absorption = true`). |
| `occlusion_collision_mask` | `int` (flags) | `1` | Physics layers the occlusion raycast collides with. Can differ from the reverb mask. |
| `ignore_listener_body` | `bool` | `true` | Automatically exclude the listener's `CharacterBody3D` from occlusion raycasts. |

### Attenuation

| Property | Type | Default | Description |
|---|---|---|---|
| `enable_volume_attenuation` | `bool` | `true` | Enable the custom distance attenuation model (overrides Godot's built-in model). |
| `inner_radius` | `float` (m) | `2.0` | Distance at which the sound plays at full volume. |
| `falloff_distance` | `float` (m) | `20.0` | Distance beyond the inner radius over which sound fades to silence. |
| `attenuation_function` | `AttenuationFunction` | `LINEAR` | The falloff curve used within the falloff zone. |
| `user_attenuation_curve` | `Curve` | `null` | Custom attenuation curve (X: normalised distance 0–1, Y: volume 1–0). Used when `USER_DEFINED` is selected. |
| `inner_radius_panning_strength` | `float` (0–2) | `1.0` | Panning strength when the listener is at the centre of the inner radius. `0` = fully centred, `1` = default, `2` = exaggerated. |

### Air Absorption

| Property | Type | Default | Description |
|---|---|---|---|
| `enable_air_absorption` | `bool` | `false` | Enable distance-based high-frequency rolloff simulating air absorption. |
| `air_absorption_min_distance` | `float` (m) | `2.0` | Distance at which filtering begins. |
| `air_absorption_max_distance` | `float` (m) | `100.0` | Distance at which filtering reaches maximum effect. |
| `air_absorption_cutoff_freq_min` | `int` (Hz) | `20000` | Lowpass cutoff at minimum distance (near the source). |
| `air_absorption_cutoff_freq_max` | `int` (Hz) | `4000` | Lowpass cutoff at maximum distance (furthest from the source). |
| `air_absorption_log_frequency_scaling` | `bool` | `true` | Use logarithmic (perceptually linear) frequency interpolation. |

### Sound Speed Delay

| Property | Type | Default | Description |
|---|---|---|---|
| `enable_sound_delay` | `bool` | `false` | Delay `play()` based on distance / speed of sound. Best for one-shot sounds. |
| `speed_of_sound` | `float` (m/s) | `343.0` | Speed of sound in metres per second. Lower values exaggerate the delay effect. |

### Advanced

| Property | Type | Default | Description |
|---|---|---|---|
| `minimum_volume_db` | `float` (dB) | `-80` | Volume the emitter fades from on startup, and the floor for attenuation. |
| `autoplay_fade_in` | `bool` | `true` | When `autoplay` is on, start at `minimum_volume_db` and lerp up after the first geometry scan. |
| `autoplay_fade_in_speed` | `float` (0.1–40) | `6.0` | Lerp speed used specifically for the autoplay fade-in. |
| `lerp_speed` | `float` (1–20) | `15.0` | How quickly effect values (reverb, lowpass, volume) interpolate toward their targets. Higher = snappier. |
| `custom_listener_target` | `Node3D` | `null` | Override the default listener (active `Camera3D`) with a custom node. |
| `occluded_lowpass_cutoff_minimum` | `int` (Hz) | `600` | Minimum lowpass cutoff frequency when the listener is fully occluded. |
| `open_lowpass_cutoff` | `int` (Hz) | `20000` | Lowpass cutoff frequency when there is a clear line of sight. |
| `update_frequency` | `float` (s) | `0.2` | How often geometry is re-sampled and effects recalculated. Increase for static emitters to save CPU. |
| `audio_bus_prefix` | `String` | `"SpatialBus"` | Prefix for the dynamically created audio bus. |
| `effects_enabled` | `bool` | `true` | Toggle all spatial audio effects on this instance on/off. Also controls `global_effects_disabled`. |

### Debug

| Property | Type | Default | Description |
|---|---|---|---|
| `debug_draw_rays` | `bool` | `false` | Draw coloured raycast lines at runtime. Blue = room-sensing, Green = clear to listener, Red = occluded. |
| `debug_draw_radius` | `bool` | `false` | Draw wireframe spheres for inner (cyan) and outer (orange) radius at runtime. |
| `debug_draw_playing_state` | `bool` | `false` | Draw a small sphere at the emitter. Green = playing, Yellow = delay pending, Red = stopped. |
| `display_debug_info` | `bool` | `false` | Show the on-screen debug HUD while within range. |
| `debug_toggle_effects_key` | `Key` | `KEY_F1` | Key to toggle all effects on/off while the debug HUD is visible. |
| `debug_toggle_shapes_key` | `Key` | `KEY_F2` | Key to toggle debug shape drawing at runtime. |

---

## Methods

### `play(from_position: float = 0.0) -> void`

Overrides `AudioStreamPlayer3D.play()`. If `enable_sound_delay` is active, playback is deferred by `distance / speed_of_sound` seconds. Emits `spatial_audio_playback_started` when audio actually begins.

### `play_spatial(from_position: float = 0.0) -> void`

Alias for `play()`. Call this directly if the `play()` override is not dispatched (e.g. the node was instantiated as a plain `AudioStreamPlayer3D`).

### `stop() -> void`

Overrides `AudioStreamPlayer3D.stop()`. Emits `spatial_audio_playback_stopped`.

### `static set_global_effects_disabled(disabled: bool) -> void`

Disables (or re-enables) all spatial audio effects across **every** `SpatialAudioPlayer3D` instance in the scene at once. Useful for a global accessibility option or performance mode.

```gdscript
# Disable all spatial effects globally
SpatialAudioPlayer3D.set_global_effects_disabled(true)
```

### External Integration Methods (Proxy/Navigation)

These are used by external systems such as `SpatialReflectionNavigationAgent3D` to coordinate reflection routing without fighting internal attenuation/occlusion logic.

| Method | Description |
|---|---|
| `set_external_volume_db_offset(offset_db: float) -> void` | Applies extra dB offset on top of internal attenuation. |
| `get_external_volume_db_offset() -> float` | Returns current external dB offset. |
| `clear_external_volume_db_offset() -> void` | Clears external dB offset back to `0.0`. |
| `set_external_occlusion_hold(seconds: float) -> void` | Temporarily holds occlusion open for transition smoothing. |
| `clear_external_occlusion_hold() -> void` | Clears any active external occlusion hold. |
| `is_external_occlusion_held() -> bool` | Returns whether external occlusion hold is currently active. |
| `set_external_navigation_debug_data(active: bool, info: Dictionary = {}) -> void` | Injects navigation/proxy diagnostics for the debug HUD's Navigation dropdown. |
| `clear_external_navigation_debug_data() -> void` | Clears injected external navigation diagnostics. |

---

## Static Variables

| Variable | Type | Description |
|---|---|---|
| `global_effects_disabled` | `bool` | When `true`, all instances bypass reverb, occlusion, and air absorption. |

---

## Inherited properties to be aware of

| Property | Notes |
|---|---|
| `volume_db` | **Managed internally.** Editing directly at runtime has no effect while attenuation is active. |
| `max_db` | Controls the maximum loudness of the stream — this one is yours to set. |
| `unit_size` | The radius at which the sound plays at full volume in Godot's built-in model. Less relevant when `enable_volume_attenuation` is on. |
| `max_distance` | The furthest distance at which the sound is audible. Should equal or exceed `max_raycast_distance`. |
| `bus` | The plugin creates its own child bus automatically — do not change this at runtime. |
