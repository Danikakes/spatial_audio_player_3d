# Spatial Audio Extended

An advanced, drop-in replacement for Godot's `AudioStreamPlayer3D` that adds physically-inspired, real-time spatial audio to your 3D games.

**Version 3.0.1** · Godot 4.x · by danikakes

Feel free to donate to my [Paypal]( https://www.paypal.com/donate/?business=WK8M59YJRAYAJ&no_recurring=0&currency_code=USD) if you like what I make :)


## Features

- **Volume Attenuation** — Multiple falloff curves (Linear, Logarithmic, Inverse, Natural Sound, and user-defined) with configurable inner and outer radii.
- **Room Size Reverb** — Omni-directional raycasts estimate room geometry and apply reverb automatically. Works in real time as the player moves between spaces.
- **Wall Occlusion** — Multi-wall detection with material-based lowpass filtering and volume reduction. Sounds become progressively more muffled behind each wall.
- **Air Absorption** — Distance-based high-frequency rolloff simulating how air attenuates sound over long distances.
- **Sound Speed Delay** — Realistic propagation delay for one-shot sounds. Fire a gunshot across a valley and hear it arrive a moment later.
- **Acoustic Materials** — Physics-based surface properties (absorption, scattering, transmission) with 12 built-in presets covering brick, concrete, carpet, glass, wood, metal, acoustic foam, and more.
- **Debug Overlay** — On-screen HUD, in-editor ray visualisation, radius wireframes, and a live A/B effect toggle.
- **Rich Signals** — Zone transitions, occlusion events, reverb updates, air absorption changes, playback state, and diagnostic data.
- **Reflection Navigation Agent (Experimental)** — `SpatialReflectionNavigationAgent3D` routes reflected proxy audio around corners in 3D space and integrates with `SpatialAudioPlayer3D`.

---

## Installation

**From the Godot Asset Library:**

1. Open your project and go to the **AssetLib** tab.
2. Search for **Spatial Audio Extended** and install it.
3. Go to **Project → Project Settings → Plugins** and enable **Spatial Audio Extended**.

**Manual:**

1. Copy the `addons/danikakes.spatial_audio/` folder into your project's `addons/` directory.
2. Enable the plugin in **Project → Project Settings → Plugins**.

---

## Quick Start

Replace any `AudioStreamPlayer3D` in your scene with a `SpatialAudioPlayer3D`. All existing properties and method calls work identically — no code changes needed.

```gdscript
# No changes required. play(), stop(), is_playing() all work as before.
$MySpatialAudio.play()
```

To give surfaces acoustic properties, add an `AcousticBody` node as a direct child of any `StaticBody3D`, `RigidBody3D`, `Area3D`, or `CSGShape3D`, then assign one of the built-in material presets:

```
StaticBody3D  (concrete wall)
├── CollisionShape3D
├── MeshInstance3D
└── AcousticBody        <-- assign concrete.tres here
```

The plugin adds an **"Add AcousticBody"** button to the Inspector when a `CollisionShape3D` or `CSGShape3D` is selected, so you can skip the Add Node dialog.

---

## Node Overview

| Node | Description |
|---|---|
| `SpatialAudioPlayer3D` | The main audio player. Drop-in for `AudioStreamPlayer3D`. |
| `SpatialReflectionNavigationAgent3D` | 3D path-routing agent for reflected/proxy audio around occluders. |
| `AcousticBody` | Attach to collision geometry to define its acoustic surface properties. |
| `AcousticMaterial` | Resource defining absorption, scattering, and transmission per frequency band. |

---

## Acoustic Material Presets

12 presets are included, based on real-world acoustic data:

`brick` · `concrete` · `ceramic` · `carpet` · `glass` · `gravel` · `metal` · `plaster` · `rock` · `wood` · `generic` · `acoustic_foam`

```gdscript
# Load from disk
var mat = load("res://addons/danikakes.spatial_audio/presets/concrete.tres")

# Or use a static constructor
var mat = AcousticMaterial.preset_concrete()
```

---

## Signals

```gdscript
# Zone transitions
signal inner_radius_entered(listener)
signal inner_radius_exited(listener)
signal falloff_zone_entered(listener)
signal falloff_zone_exited(listener)
signal attenuation_zone_entered(listener)
signal attenuation_zone_exited(listener)

# Occlusion
signal audio_occluded(listener, wall_count)
signal audio_unoccluded(listener)
signal occlusion_changed(wall_count, cutoff_hz)

# Reverb / air absorption
signal reverb_updated(room_size, wetness, damping)
signal reverb_zone_changed(room_size, wetness)
signal air_absorption_updated(cutoff_hz)

# Playback
signal spatial_audio_playback_started()
signal spatial_audio_playback_stopped()
signal listener_distance_changed(distance)
```

---

## Global Effect Toggle

Disable all spatial effects across every instance at once — useful for accessibility or performance modes:

```gdscript
SpatialAudioPlayer3D.set_global_effects_disabled(true)
```

---

## Spatial Reflection Navigation Agent (Experimental)

Use `SpatialReflectionNavigationAgent3D` to move a proxied `SpatialAudioPlayer3D` along a collision-aware path between a source origin and the active camera. This allows audio to route around corners instead of leaking directly through walls.

### Quick Setup

1. Add `SpatialReflectionNavigationAgent3D` to your scene at the source location.
2. Add a `SpatialAudioPlayer3D` as a child of the agent (or assign it via `audio_player_node`).
3. Enable `move_audio_player`.
4. Select a `navigation_profile`:
   - `OPEN_AREAS` for open spaces.
   - `HALLWAYS` for tight interior corridors.
   - `CUSTOM` for manual tuning.
5. Enable debug toggles to inspect bounds/path in runtime. In editor, bounds/path preview can be shown while selected.

### Notable Capabilities

- 3D graph pathing (not limited to flat ground).
- Profile-driven tuning plus custom manual controls.
- Proxy spring-arm/backoff to keep reflected proxy away from the listener.
- Reflection volume-loss integration with `SpatialAudioPlayer3D`.
- Proxy-only navigation diagnostics in the `SpatialAudioPlayer3D` debug overlay.
- Inspector warnings when no `SpatialAudioPlayer3D` is available, or when a regular `AudioStreamPlayer3D` is used.

---

## Documentation

Full documentation is available in the [Wiki](../../wiki):

- [Installation](../../wiki/Installation)
- [Getting Started](../../wiki/Getting-Started)
- [SpatialAudioPlayer3D Reference](../../wiki/SpatialAudioPlayer3D-Reference)
- [SpatialReflectionNavigationAgent3D Reference](../../wiki/SpatialReflectionNavigationAgent3D-Reference)
- [AcousticBody Reference](../../wiki/AcousticBody-Reference)
- [AcousticMaterial Reference](../../wiki/AcousticMaterial-Reference)
- [Material Presets](../../wiki/Material-Presets)
- [Signals Reference](../../wiki/Signals-Reference)
- [Debug Tools](../../wiki/Debug-Tools)
- [Tips & Recipes](../../wiki/Tips-and-Recipes)

---

## License

See [LICENSE](LICENSE).
