# Tips & Recipes

Common patterns, performance advice, and gotchas for getting the most out of Spatial Audio Extended.

---

## Performance Tips

### Increase `update_frequency` for static emitters

By default, spatial audio is recalculated every `0.2` seconds. For sounds that don't move — ambient machinery, flowing water, static alarm — you can safely increase this to `0.5` or even `1.0`:

```gdscript
$AmbientHum.update_frequency = 1.0
```

### Use Classic ray distribution for simple rooms

`CLASSIC` uses only 10 fixed rays and is the cheapest option. Use `FIBONACCI_SPHERE` (with a modest ray count like 8–16) only when you need better room estimation in complex geometry.

### Disable unused features

If a sound doesn't need a particular feature, turn it off to save the calculation:

```gdscript
$FootstepPlayer.room_size_reverb = false # no reverb for quick footsteps
$FootstepPlayer.enable_air_absorption = false
$FootstepPlayer.audio_occlusion = false # or keep on for a muffled-behind-wall effect
```

### Separate collision masks

The `reverb_collision_mask` and `occlusion_collision_mask` can be different. Put your major architectural surfaces (walls, floor, ceiling) on one layer for reverb, and thinner occluders (doors, furniture) on another for occlusion. This avoids thin props distorting room size estimates.

---

## Common Recipes

### Gunshot / explosion with realistic delay

```gdscript
@onready var explosion := $ExplosionAudio # SpatialAudioPlayer3D

func detonate(position: Vector3):
 explosion.global_position = position
 explosion.enable_sound_delay = true
 explosion.speed_of_sound = 343.0
 explosion.play()
```

### Looping ambient with autoplay fade-in

Set `autoplay = true` on the node and leave `autoplay_fade_in = true`. The sound will start silently and lerp up to full volume once the first geometry scan completes, preventing a loud unfiltered burst on scene load.

Tune the fade speed with `autoplay_fade_in_speed` (default `6.0`). Lower = slower fade.

### Trigger a subtitle when sound becomes occluded

```gdscript
func _ready():
 $NPC_Voice.audio_occluded.connect(_on_voice_occluded)
 $NPC_Voice.audio_unoccluded.connect(_on_voice_clear)

func _on_voice_occluded(_listener, wall_count):
 $SubtitleUI.show_muffled_indicator(wall_count)

func _on_voice_clear(_listener):
 $SubtitleUI.hide_muffled_indicator()
```

### Custom panning inside a large speaker

Set `inner_radius_panning_strength = 0.0` for a sound source the player can walk inside (e.g. a large speaker or explosion radius). The sound will be centred and non-directional at close range, then pan normally as the player moves away.

### Disable all effects globally for a performance mode

```gdscript
func _on_performance_mode_toggled(enabled: bool):
 SpatialAudioPlayer3D.set_global_effects_disabled(enabled)
```

### User-defined attenuation curve

```gdscript
var curve := Curve.new()
curve.add_point(Vector2(0.0, 1.0))
curve.add_point(Vector2(0.5, 0.9)) # stays loud until halfway
curve.add_point(Vector2(0.8, 0.3)) # sharp drop
curve.add_point(Vector2(1.0, 0.0))

$MyPlayer.attenuation_function = SpatialAudioPlayer3D.AttenuationFunction.USER_DEFINED
$MyPlayer.user_attenuation_curve = curve
```

### Reflected proxy routing around corners

```gdscript
@onready var nav_agent := $SpatialReflectionNavigationAgent3D

func _ready():
 nav_agent.navigation_profile = SpatialReflectionNavigationAgent3D.NavigationProfile.HALLWAYS
 nav_agent.move_audio_player = true
 nav_agent.proxy_only_when_blocked = true
 nav_agent.proxy_spring_arm_enabled = true
 nav_agent.proxy_spring_min_distance = 1.5
```

Use `HALLWAYS` for tight indoor spaces, `OPEN_AREAS` for large maps, and switch to `CUSTOM` only when you need manual tuning.

### React to room size for gameplay

```gdscript
$MySpatialAudio.reverb_zone_changed.connect(func(room_size, wetness):
 if room_size > 0.75:
 enemy_ai.set_state("alerted_open_space")
 elif room_size < 0.15:
 enemy_ai.set_state("in_tight_corridor")
)
```

---

## Gotchas

### `volume_db` is managed internally

Don't set `volume_db` at runtime on a `SpatialAudioPlayer3D` — the node overwrites it every physics frame. Use `max_db` to cap loudness and the attenuation properties to control distance falloff.

### AcousticBody must be a direct child

`AcousticBody.find_for_collider()` only checks one level up (to handle CSG). If your scene tree is deeper, the material won't be found.

### CSG geometry needs `use_collision = true`

For `AcousticBody` to work on a `CSGShape3D`, the shape must have `use_collision` enabled in the Inspector.

### `max_distance` vs `max_raycast_distance`

`max_distance` is an inherited `AudioStreamPlayer3D` property that controls Godot's audio engine attenuation. `max_raycast_distance` is the range of the plugin's raycasts. Keep them in sync (both set to your furthest hearing distance) to avoid mismatches between audio and spatial effects.

### `ignore_listener_body` requires a `CharacterBody3D` ancestor

The listener-body exclusion walks up the scene tree from the `Camera3D`. It finds the **first** `CharacterBody3D` ancestor. If your player structure differs (e.g. you use `RigidBody3D` or a custom rig), disable `ignore_listener_body` and handle exclusions manually via the physics layer masks.

### Sound speed delay is one-shot only

`enable_sound_delay` only delays the initial `play()` call. It doesn't affect looping playback once started. Use it for impulsive sounds: gunshots, explosions, distant thunder.
