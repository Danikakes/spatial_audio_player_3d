# Material Presets

The plugin ships with 12 built-in `AcousticMaterial` presets as `.tres` files located at:

```
addons/spatial_audio_extended/presets/
```

All values are physically derived from acoustic literature. You can use them as-is, or duplicate and tweak them for your project.

---

## Preset Values

### Absorption (fraction of energy absorbed per bounce)

| Preset | Low (≤ 400 Hz) | Mid (400–2500 Hz) | High (≥ 2500 Hz) |
|---|---|---|---|
| generic | 0.10 | 0.20 | 0.30 |
| brick | 0.03 | 0.04 | 0.07 |
| concrete | 0.05 | 0.07 | 0.08 |
| ceramic | 0.01 | 0.02 | 0.02 |
| gravel | 0.60 | 0.70 | 0.80 |
| carpet | 0.24 | 0.69 | 0.73 |
| glass | 0.25 | 0.06 | 0.03 |
| plaster | 0.12 | 0.06 | 0.04 |
| wood | 0.11 | 0.07 | 0.06 |
| metal | 0.20 | 0.07 | 0.06 |
| rock | 0.13 | 0.20 | 0.24 |
| acoustic_foam | 1.00 | 1.00 | 1.00 |

### Transmission (fraction of energy passing through)

| Preset | Low (≤ 400 Hz) | Mid (400–2500 Hz) | High (≥ 2500 Hz) |
|---|---|---|---|
| generic | 0.100 | 0.050 | 0.030 |
| brick | 0.025 | 0.019 | 0.010 |
| concrete | 0.015 | 0.011 | 0.008 |
| ceramic | 0.060 | 0.044 | 0.011 |
| gravel | 0.031 | 0.012 | 0.008 |
| carpet | 0.020 | 0.005 | 0.003 |
| glass | 0.060 | 0.044 | 0.011 |
| plaster | 0.056 | 0.028 | 0.004 |
| wood | 0.070 | 0.014 | 0.005 |
| metal | 0.200 | 0.025 | 0.010 |
| rock | 0.015 | 0.002 | 0.001 |
| acoustic_foam | 0.000 | 0.000 | 0.000 |

### Scattering

All presets use a `scattering` value of `0.05`, except:

| Preset | Scattering |
|---|---|
| gravel | 0.60 |
| carpet | 0.57 |
| rock | 0.20 |
| acoustic_foam | 0.60 |

### Special

| Preset | total_absorption |
|---|---|
| acoustic_foam | true |

### Total-Absorption Transition Speed

| Preset | total_absorption_transition_speed |
|---|---|
| acoustic_foam | 1.2 |

---

## Choosing the Right Preset

| Scenario | Recommended Preset |
|---|---|
| Generic interior walls | `generic` or `plaster` |
| Industrial/warehouse | `concrete` or `brick` |
| Old stone building | `rock` or `brick` |
| Modern office/apartment | `plaster` or `wood` |
| Tiled bathroom/kitchen | `ceramic` |
| Carpeted room (reduces echo) | `carpet` |
| Glass facade/windows | `glass` |
| Metal duct / machinery | `metal` |
| Cave / outdoor terrain | `rock` or `gravel` |
| Outdoor ground | `gravel` |
| Soundproof barrier / booth | `acoustic_foam` |

---

## Key Differences to Listen For

**Carpet vs. Concrete:** 
Carpet has very high absorption (especially for mids/highs), so reverb tails will be much shorter in carpeted rooms. Concrete has low absorption, so sound bounces around a lot.

**Glass vs. Brick:** 
Glass has moderate-to-high transmission (sound leaks through) but also noticeably absorbs bass. Brick is nearly opaque to sound, with very low transmission values.

**Metal:** 
Metal has relatively high low-frequency transmission — bass bleeds through metal walls more than most other materials. Useful for thin partitions and vents.

**Rock:** 
Rock has high scattering (0.20), making reflections more diffuse and cave-like rather than the sharp echoes you'd get from flat concrete.

---

## Using Presets in Code

```gdscript
# Load from disk (returns the shared resource — duplicate if you want to modify)
var mat = load("res://addons/spatial_audio_extended/presets/concrete.tres")

# Or use the static constructor (returns a new instance each time)
var mat = AcousticMaterial.preset_concrete()
```
