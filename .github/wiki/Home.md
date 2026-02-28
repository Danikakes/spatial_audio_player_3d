# Spatial Audio Extended — Wiki

> **Version 3.0.1** · by [danikakes](https://github.com/danikakes) · Godot 4.x

**Spatial Audio Extended** is an advanced, drop-in replacement for Godot's built-in `AudioStreamPlayer3D` that adds physically-inspired, real-time spatial audio effects to your 3D games.

---

## Features

| Feature | Description |
|---|---|
| **Volume Attenuation** | Multiple falloff curves (Linear, Logarithmic, Inverse, Natural Sound, and user-defined) with configurable inner/outer radii |
| **Room Size Reverb** | Omni-directional raycasts estimate room size and apply reverb automatically |
| **Wall Occlusion** | Multi-wall detection with material-based lowpass filtering and volume reduction |
| **Air Absorption** | Distance-based high-frequency rolloff for realism at range |
| **Sound Speed Delay** | Realistic propagation delay for one-shot sounds (gunshots, explosions, etc.) |
| **Acoustic Materials** | Physics-based surface properties (absorption, scattering, transmission) with 12 built-in presets |
| **Reflection Navigation Agent (Experimental)** | `SpatialReflectionNavigationAgent3D` routes reflected proxy audio around corners in full 3D space |
| **Debug Overlay** | Runtime HUD, in-editor ray visualisation, radius wireframes, and A/B effect toggle |
| **Rich Signals** | Zone transitions, occlusion, reverb, air absorption, playback, and diagnostics |

---

## Quick Links

- **[[Installation]]** — Installing the plugin and enabling it in your project
- **[[Getting Started]]** — Your first `SpatialAudioPlayer3D` in 5 minutes
- **[[SpatialAudioPlayer3D Reference]]** — All exported properties and methods
- **[[SpatialReflectionNavigationAgent3D Reference]]** — Corner-aware reflected proxy pathing in 3D
- **[[AcousticBody Reference]]** — Giving surfaces acoustic properties
- **[[AcousticMaterial Reference]]** — Absorption, scattering, and transmission settings
- **[[Material Presets]]** — The 12 built-in acoustic material presets
- **[[Signals Reference]]** — Every signal, with arguments and use cases
- **[[Debug Tools]]** — In-editor visualisation and runtime overlay
- **[[Tips & Recipes]]** — Common patterns and performance advice

---

## Node Overview

```
SpatialAudioPlayer3D ← drop-in replacement for AudioStreamPlayer3D
├── (internal raycasts created automatically)
└── …

SpatialReflectionNavigationAgent3D (experimental)
└── SpatialAudioPlayer3D (proxied reflected playback)

CollisionObject3D / CSGShape3D (your wall, floor, prop…)
└── AcousticBody ← add this to give the surface sound properties
 └── [AcousticMaterial] ← assign a preset .tres or create your own
```

---

## Compatibility

- **Godot 4.x** (developed and tested on Godot 4.3+)
- Works with all renderer backends (Forward+, Mobile, Compatibility)
- `@tool` — live preview in the editor
