# SpatialReflectionNavigationAgent3D Reference

`SpatialReflectionNavigationAgent3D` is a 3D routing helper for reflected audio.  
It computes a collision-aware path from a source origin to the listener (active camera by default), then can drive a proxied `SpatialAudioPlayer3D` along that path.

## What It Solves

- Prevents reflected audio from traveling in a straight line through walls.
- Routes proxy audio around corners and through openings.
- Supports true 3D space (air navigation), not only flat floor movement.

## Typical Scene Setup

1. Add `SpatialReflectionNavigationAgent3D` at the source location.
2. Add `SpatialAudioPlayer3D` as a child of the agent, or assign one via `audio_player_node`.
3. Enable `move_audio_player`.
4. Keep `target_override` empty to use the active camera automatically.
5. Pick a `navigation_profile`:
   - `OPEN_AREAS` for open levels.
   - `HALLWAYS` for tight corridors.
   - `CUSTOM` for manual tuning.

## Core Inspector Groups

### Navigation

- `navigation_profile`: High-level tuning preset (`CUSTOM`, `OPEN_AREAS`, `HALLWAYS`).
- Graph and solve controls (visible in `CUSTOM`):
  - `navigation_radius`, `sample_point_count`, `max_connection_distance`
  - `use_reachable_scan`, `scan_*`
  - `graph_neighbor_limit`, `dynamic_connection_limit`
  - `reuse_*`, `heuristic_weight`, `distance_mode`

### Origin

- `origin_mode`:
  - `NODE_POSITION`
  - `NODE_WITH_LOCAL_OFFSET`
  - `FIXED_WORLD_POSITION`
- Use `fixed_world_origin` for moving-parent scenarios where world origin should stay stable.

### Target

- `target_override`: Manual listener target.
- Empty value uses active camera.

### Audio Proxy

- `move_audio_player`: Enables proxy movement.
- `audio_player_node`: Explicit proxied player.
- `auto_find_audio_player_child`: Auto-resolve first child `AudioStreamPlayer3D`.
- `proxy_spring_arm_enabled`: Keeps proxy from getting too close to listener.
- `enable_proxy_listener_backoff`: Backoff mode when spring-arm is disabled.

### Reflection Audio

- `apply_reflection_volume_loss`: Adds dB loss by routed path distance.
- `proxy_occlusion_transition_smoothing`: Handles return transition smoothing.

### Debug

- Runtime debug toggles:
  - `debug_draw_bounds`, `debug_draw_path`, `debug_draw_graph_points`, `debug_draw_graph_edges`, `debug_draw_audio_proxy`
- Editor behavior:
  - When selected, bounds/path preview can render in editor.
  - `preview_pathing_in_editor` controls full editor runtime pathing behavior.
  - Turning `preview_pathing_in_editor` off resets proxied player position back to origin.

## Inspector Field Visibility

The inspector hides dependent properties until the required toggle is enabled. Examples:

- `navigation_profile != CUSTOM`: hides low-level tuning fields.
- `move_audio_player = false`: hides proxy movement, spring-arm, reflection-loss, and proxy debug fields.
- `proxy_spring_arm_enabled = true`: hides backoff-only fields.
- `apply_reflection_volume_loss = false`: hides reflection loss coefficients.
- `proxy_occlusion_transition_smoothing = false`: hides occlusion hold timing fields.

## Editor Warnings

The node surfaces configuration warnings when:

- No `SpatialAudioPlayer3D` is found for proxy routing.
- A regular `AudioStreamPlayer3D` is assigned (routing integration features are incomplete without `SpatialAudioPlayer3D`).
- `audio_player_node` is assigned to a non-audio node type.

## SpatialAudioPlayer3D Integration

When reflected proxying is active, the navigation agent can feed debug and control data to `SpatialAudioPlayer3D`:

- External reflection volume offset.
- External occlusion-hold coordination.
- Proxy-only navigation diagnostics in the player's debug overlay (`Navigation` dropdown).

## Signals

- `path_updated(path_world, direct_path)`
- `path_failed(origin_world, target_world)`
- `audio_proxy_position_updated(proxy_world)`
- `graph_rebuilt(point_count)`

## Performance Tuning Notes

Start with:

1. `navigation_profile` (`HALLWAYS` in tight indoor levels).
2. `update_interval` (increase to reduce solve frequency).
3. `scan_max_cells` / `scan_max_cell_extent` for reachable-scan builds.
4. Disable debug drawing outside diagnostics.

If you need manual control, switch to `CUSTOM` and tune from there.
