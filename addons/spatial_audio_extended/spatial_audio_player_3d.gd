@tool
@icon("images/spatial_audio_player_3d.svg")
extends AudioStreamPlayer3D
class_name SpatialAudioPlayer3D
## `SpatialAudioPlayer3D` is an advanced, drop-in replacement for Godot's [AudioStreamPlayer3D] that provides physically-inspired, real-time spatial audio effects for immersive 3D games.
##
## Features:
## - Customizable distance attenuation with multiple falloff curves, inner/falloff radii, and user-defined curves.
## - Real-time room size and reverb estimation using omni-directional raycasts, with support for surface absorption and reflections.
## - Wall occlusion simulation with multi-wall detection, lowpass filtering, and volume reduction, including material-based transmission and absorption.
## - Air absorption (distance-based high-frequency rolloff) with linear or logarithmic scaling.
## - Sound speed delay for realistic propagation of one-shot sounds.
## - Debug overlay and runtime visualization tools for rays, radii, and playback state.
## - Rich signal set for zone transitions, occlusion, reverb, air absorption, playback, and diagnostics.
## - All key parameters are exposed as exports for easy tuning in the Godot editor.
##
## Usage:
## - Add this node in place of [AudioStreamPlayer3D] for any 3D sound that needs advanced spatialization.
## - Configure attenuation, reverb, occlusion, and debug options via the Inspector.
## - Connect to signals for gameplay, analytics, or UI feedback on spatial audio events.
##
## [b]Key inherited parameters to be aware of:[/b][br]
## - [param volume_db]: Managed internally — editing it directly has no effect.[br]
## - [param max_db]: Controls the maximum loudness of the stream.[br]
## - [param unit_size]: The radius at which the sound plays at full volume.[br]
## - [param max_distance]: The furthest distance at which the sound is audible. Should be equal to or greater than [param max_raycast_distance].[br]

## Signals
## Attenuation / zone transitions
## Emitted when a listener enters the inner (full-volume) radius.
signal inner_radius_entered(listener)
## Emitted when a listener leaves the inner (full-volume) radius.
signal inner_radius_exited(listener)
## Emitted when a listener enters the falloff zone (between inner and outer).
signal falloff_zone_entered(listener)
## Emitted when a listener exits the falloff zone.
signal falloff_zone_exited(listener)
## Emitted when a listener becomes audible (enters outer boundary).
signal attenuation_zone_entered(listener)
## Emitted when a listener becomes inaudible (leaves outer boundary).
signal attenuation_zone_exited(listener)

## Occlusion signals
## Emitted when occlusion parameters change. Args: `wall_count (int)`, `cutoff_hz (float)`.
signal occlusion_changed(wall_count, cutoff_hz)
## Emitted when the audio becomes occluded by one or more walls. Args: `listener`, `wall_count (int)`.
signal audio_occluded(listener, wall_count)
## Emitted when occlusion clears and the audio becomes unoccluded. Args: `listener`.
signal audio_unoccluded(listener)

## Reverb / air absorption updates
## Emitted when reverb targets change. Args: `room_size (float)`, `wetness (float)`, `damping (float)`.
signal reverb_updated(room_size, wetness, damping)
## Emitted when room size or wetness changes (higher-level reverb zone change).
signal reverb_zone_changed(room_size, wetness)
## Emitted when air-absorption lowpass cutoff changes. Args: `cutoff_hz (float)`.
signal air_absorption_updated(cutoff_hz)
## Emitted when the air-absorption zone changes (min/max thresholds crossed).
signal air_absorption_zone_changed(cutoff_hz)

## Misc playback / debug signals
## Emitted periodically when listener distance changes significantly. Args: `distance (float)`.
signal listener_distance_changed(distance)
## Emitted when playback actually starts (immediate or deferred).
signal spatial_audio_playback_started()
## Emitted when playback is stopped.
signal spatial_audio_playback_stopped()
## Emitted when the debug overlay visibility is toggled. Args: `visible (bool)`.
signal debug_overlay_toggled(visible)
## Emits a compact diagnostics dictionary when the debug overlay is shown.
## Example keys: `distance`, `volume_db_target`, `lowpass_cutoff`, `reverb_room_size`, `wall_count`.
signal spatial_audio_debug(info)

## Emitted when an occlusion ray collides with a surface. Args: `hit_position (Vector3)`, `from_position (Vector3)`, `collider (Node)`, `listener (Node)`
signal occlusion_ray_collided(hit_position, from_position, collider, listener)
## Emitted when a reverb/reflection ray collides with a surface. Args: `hit_position (Vector3)`, `from_position (Vector3)`, `collider (Node)`
signal reverb_ray_collided(hit_position, from_position, collider)


## How the omni-directional room-sensing rays are distributed around
## the emitter.
enum RayDistribution {
	CLASSIC,          ## 10 predefined rays (cardinal + diagonal + up/down).
	FIBONACCI_SPHERE, ## Evenly distributed rays using a Fibonacci sphere.
	SHAPE_SCATTER, ## Rays scattered outward from a given collision shape.
}

## The falloff curve used to calculate volume attenuation between the
## inner radius and the outer boundary (inner_radius + falloff_distance).
enum AttenuationFunction {
	LINEAR,        ## Volume decreases at a constant rate with distance.
	LOGARITHMIC,   ## Greater volume changes at close distances, lesser at far.
	INVERSE,       ## Like Logarithmic but more exaggerated; only audible very close.
	LOG_REVERSE,   ## Lesser volume changes close, dramatic changes far away.
	NATURAL_SOUND, ## Middle-ground between Logarithmic and Inverse; closest to reality.
	USER_DEFINED,  ## Use a custom attenuation curve provided by the user.
}

var _last_wall_absorptions: Array = []
#region EXPORTS

## How the room-sensing rays are arranged around the emitter.
## [b]Classic[/b] uses 10 fixed directions; [b]Fibonacci Sphere[/b] distributes
## rays evenly over a sphere for more uniform coverage.
@export var ray_distribution : RayDistribution = RayDistribution.CLASSIC :
	set(value):
		ray_distribution = value
		notify_property_list_changed()
		if _setup_complete:
			_rebuild_raycasts()

## Number of omni-directional rays when using [b]Fibonacci Sphere[/b] distribution.
## More rays = better room-size estimation at higher CPU cost.
## Ignored in [b]Classic[/b] mode (always 10 rays).
@export_range(4, 128, 1) var fibonacci_ray_count : int = 8 :
	set(value):
		fibonacci_ray_count = value
		if _setup_complete and ray_distribution == RayDistribution.FIBONACCI_SPHERE:
			_rebuild_raycasts()

## The collision-shape (or any Node3D) used as the scattering origin. Rays
## will be positioned around this node and fired outward. If
## empty, rays will be scattered around this node's global origin.
@export var scatter_shape : Node3D = null :
	set(value):
		scatter_shape = value
		if _setup_complete and ray_distribution == RayDistribution.SHAPE_SCATTER:
			_rebuild_raycasts()


## Number of rays when using the collision-shape random distribution.
@export_range(1, 256, 1) var shape_ray_count : int = 32 :
	set(value):
		shape_ray_count = value
		if _setup_complete and ray_distribution == RayDistribution.SHAPE_SCATTER:
			_rebuild_raycasts()


## How strongly the ray direction deviates from the center-to-surface
## direction. 0 = rays point exactly away from the shape center; 50 =
## entirely random directions. Internally mapped to [0.0, 1.0].
@export_range(0, 50, 1, "prefer_slider") var shape_scatter_randomness : int = 0 :
	set(value):
		shape_scatter_randomness = value
		if _setup_complete and ray_distribution == RayDistribution.SHAPE_SCATTER:
			_rebuild_raycasts()

## Number of times each Fibonacci ray can reflect (bounce) off surfaces.
## More reflections improve room-size estimation in complex geometry
## (L-shaped rooms, corridors, etc.) at higher CPU cost.
## Ignored in [b]Classic[/b] mode.
@export_range(0, 8, 1) var fibonacci_ray_reflections : int = 0

## The maximum distance raycasts will travel when sensing geometry.
## Keep this close to [param max_distance] to avoid audible mismatches.
@export_range(.01, 4096, 0.01, "suffix:m") var max_raycast_distance : float = 50.0


@export_group("Room Size Reverb")
## When enabled, reverb room size and wetness are calculated from surrounding
## geometry and applied automatically via omni-directional raycasts.
@export var room_size_reverb := true :
	set(value):
		room_size_reverb = value
		notify_property_list_changed()

## The maximum reverb wetness that can be applied. Acts as a global ceiling on
## the wet signal regardless of how enclosed the space is.
@export_range(0, 1, .01) var max_reverb_wetness : float = 0.5

## When enabled, the absorption properties of [AcousticMaterial]s on
## surfaces hit by room-sensing rays are used to modulate reverb wetness
## and damping.  Highly absorptive surfaces (carpet, curtains) reduce
## reverb wetness and increase damping; reflective surfaces (concrete,
## glass) preserve reverb energy.
## [br][br]
## Surfaces without an [AcousticBody] / [AcousticMaterial] are ignored —
## only surfaces with explicit materials contribute to the absorption
## average.
@export var surface_absorption := true :
	set(value):
		surface_absorption = value
		notify_property_list_changed()

## How strongly surface absorption influences reverb wetness.
## [code]0.0[/code] = absorption has no effect on wetness.
## [code]1.0[/code] = full physical effect.
@export_range(0.0, 2.0, 0.01) var absorption_wetness_influence : float = 1.0

## How strongly surface absorption influences reverb damping.
## [code]0.0[/code] = absorption has no effect on damping.
## [code]1.0[/code] = full physical effect.
@export_range(0.0, 2.0, 0.01) var absorption_damping_influence : float = 1.0

## When enabled, rays pointing downward (below the floor angle threshold)
## are excluded from room-size and openness calculations. This prevents
## the floor — which is almost always present — from shrinking the
## perceived room size.
@export var ignore_floor := false :
	set(value):
		ignore_floor = value
		notify_property_list_changed()

## The angle in degrees from straight down within which a ray is considered
## a "floor ray" and will be ignored when [param ignore_floor] is enabled.
## [code]30[/code] = only nearly-vertical rays, [code]60[/code] = wider cone.
@export_range(5.0, 90.0, 1.0, "suffix:deg") var floor_angle_threshold : float = 30.0

## Physics layers the room-sensing raycasts collide with.
## Should match the layers your level geometry occupies.
@export_flags_3d_physics var reverb_collision_mask := 1


@export_group("Occlusion")
## When enabled, a lowpass filter simulates sound being muffled by walls
## between the emitter and the listener using a single target raycast.
@export var audio_occlusion := true :
	set(value):
		audio_occlusion = value
		notify_property_list_changed()

## How strongly the lowpass filter is applied when the listener is occluded.
## [code]1.0[/code] = full effect (cutoff reaches [param occluded_lowpass_cutoff]).
## [code]0.0[/code] = no filtering at all regardless of occlusion.
@export_range(0.0, 5.0, 0.01) var occlusion_strength : float = 1.0

## Maximum number of walls (collisions) to detect between the emitter and the
## listener.  Each additional wall multiplicatively reduces the lowpass
## cutoff, making the sound progressively more muffled.
@export_range(1, 16, 1) var max_occlusion_hits : int = 4

## Fraction of sound that passes through surfaces without an [AcousticBody].
## [code]0.0[/code] = fully blocks, [code]1.0[/code] = fully transparent.
## Mirrors the [i]transmission_high[/i] band of [AcousticMaterial].
@export_range(0.0, 1.0, 0.001) var fallback_transmission : float = 0.030

## How strongly walls reduce volume (in addition to lowpass filtering).
## [code]0.0[/code] = no volume reduction at all, only filtering.
## [code]1.0[/code] = full physically-derived dB loss per wall.
## Values around [code]0.3[/code]–[code]0.5[/code] sound natural for most games.
@export_range(0.0, 1.0, 0.01) var occlusion_volume_strength : float = 0.35

## Maximum combined volume reduction (in dB) that wall occlusion can apply.
## Prevents the sound from going completely silent behind many walls.
@export_range(0.0, 60.0, 0.5, "suffix:dB") var max_occlusion_volume_reduction : float = 18.0

## Physics layers the occlusion raycast collides with.
## Can differ from reverb if e.g. thin walls should occlude but not
## affect perceived room size.
@export_flags_3d_physics var occlusion_collision_mask := 1

## When enabled, the listener’s [CharacterBody3D] (if any) is automatically
## excluded from occlusion raycasts. This prevents the player’s own
## collision shapes from being detected as walls.
## [br][br]
## Detection walks up the scene tree from the active [Camera3D] looking
## for the first [CharacterBody3D] ancestor, then excludes it and all of
## its collision shape children.
@export var ignore_listener_body := true

@export_group("Attenuation")

## When enabled, volume is attenuated based on inner / outer radius and the
## chosen attenuation function.
## [br][br]
## [b]Note:[/b] This overrides Godot's built-in distance attenuation model at
## runtime so there is no double-falloff.
@export var enable_volume_attenuation := true :
	set(value):
		enable_volume_attenuation = value
		notify_property_list_changed()

## The radius around the emitter inside which the sound plays at full volume
## (completely unattenuated).
@export_range(0.0, 4096.0, 0.01, "suffix:m") var inner_radius : float = 2.0

## The distance beyond the inner radius over which the sound fades from full
## volume to silence.  The outer boundary equals
## [code]inner_radius + falloff_distance[/code].
@export_range(0.01, 4096.0, 0.01, "suffix:m") var falloff_distance : float = 20.0


## The curve that controls how quickly volume drops between the inner radius
## and the outer boundary. Select "User Defined" to use a custom curve.
@export var attenuation_function : AttenuationFunction = AttenuationFunction.LINEAR :
	set(value):
		attenuation_function = value
		notify_property_list_changed()

## Custom attenuation curve used when AttenuationFunction.USER_DEFINED is selected.
## X axis: normalized distance (0 = inner, 1 = outer). Y axis: volume (1 = full, 0 = silent).
@export var user_attenuation_curve : Curve = null

## Panning strength multiplier applied when the listener is at the centre of
## the inner radius. The value interpolates back to default ([code]1.0[/code])
## at the inner radius edge.
## [br][code]0.0[/code] = fully centred (no panning / non-directional).
## [br][code]1.0[/code] = default (no modification).
## [br][code]2.0[/code] = exaggerated panning (full left/right).
@export_range(0.0, 2.0, 0.01) var inner_radius_panning_strength : float = 1.0

@export_group("Air Absorption")

## When enabled, a distance-based lowpass filter simulates how air absorbs
## high-frequency sound energy over distance. This is independent of wall
## occlusion and stacks with it.
@export var enable_air_absorption := false :
	set(value):
		enable_air_absorption = value
		notify_property_list_changed()

## Distance from the emitter at which air absorption filtering begins.
## Below this distance no filtering is applied.
@export_range(0.0, 4096.0, 0.01, "suffix:m") var air_absorption_min_distance : float = 2.0

## Distance from the emitter at which air absorption filtering reaches its
## maximum effect. The filter interpolates between min and max cutoff
## frequencies over this range.
@export_range(0.01, 4096.0, 0.01, "suffix:m") var air_absorption_max_distance : float = 100.0

## Lowpass cutoff frequency at the minimum distance (closest to the source).
## Higher values mean less filtering when nearby — recommended to keep
## close to 20 000 Hz.
@export_custom(PROPERTY_HINT_NONE, "suffix:Hz") var air_absorption_cutoff_freq_min : int = 20000

## Lowpass cutoff frequency at the maximum distance (furthest from the source).
## Lower values produce heavier muffling at long range.
@export_custom(PROPERTY_HINT_NONE, "suffix:Hz") var air_absorption_cutoff_freq_max : int = 4000

## When enabled, the filter cutoff interpolation uses a logarithmic frequency
## scale instead of linear. This produces a perceptually smoother sweep
## that better matches how we perceive pitch.
@export var air_absorption_log_frequency_scaling := true

@export_group("Sound Speed Delay")

## When enabled, playback is delayed based on the distance between the
## emitter and the listener divided by [param speed_of_sound], simulating
## the finite travel time of sound through air.
## [br][br]
## Only affects the initial [method play] call — once playback has started
## it runs at normal speed. Best suited for one-shot sounds (gunshots,
## explosions, impacts).
@export var enable_sound_delay := false :
	set(value):
		enable_sound_delay = value
		notify_property_list_changed()

## The speed at which sound travels, in metres per second.
## Earth sea-level is ~343 m/s. Lower values exaggerate the delay.
@export_range(10.0, 2000.0, 1.0, "suffix:m/s") var speed_of_sound : float = 343.0

@export_group("Advanced")

## The volume this emitter fades up from when it first becomes active, before
## the initial geometry scan completes.
@export_range(-80, 80, 0.1, "suffix:dB") var minimum_volume_db : float = -80

## When true and the node's `autoplay` is enabled, the player will start at
## `minimum_volume_db` on ready and lerp up once the first geometry scan
## completes. Toggle this to disable the automatic silent startup for autoplay.
@export var autoplay_fade_in := true :
	set(value):
		autoplay_fade_in = value
		notify_property_list_changed()

## Speed used specifically for fading the volume in when `autoplay_fade_in`
## is active. Separate from `lerp_speed` so effect parameters can remain
## snappier while the audible fade is tuned independently.
@export_range(0.1, 40.0, 0.1) var autoplay_fade_in_speed : float = 6.0

## How quickly effect values (lowpass, reverb wet, room size) interpolate
## toward their targets each frame. Higher = snappier, lower = smoother.
@export_range(1.0, 20.0, 0.1) var lerp_speed : float = 15.0

## Overrides the default listener target (the active [Camera3D]).
@export var custom_listener_target : Node3D

## Lowpass cutoff when the listener is fully occluded by a wall.
## Lower values produce a heavier, more muffled sound.
@export_custom(PROPERTY_HINT_NONE, "suffix:Hz") var occluded_lowpass_cutoff_minimum : int = 600

## Lowpass cutoff when the listener has clear line of sight to the emitter.
@export_custom(PROPERTY_HINT_NONE, "suffix:Hz") var open_lowpass_cutoff : int = 20000

## How often geometry is re-sampled and audio effects are recalculated, in
## seconds. Increase for static or slow-moving emitters to save CPU.
@export_range(.01, 1, .01, "suffix:s") var update_frequency : float = 0.2

## Name prefix for the dynamically created audio bus. Will be a child of the selected bus in the [AudioStreamPlayer3D] settings.
@export var audio_bus_prefix := "SpatialBus"

@export_group("Debug")

## Draws coloured lines for every raycast at runtime (in-game).
## Blue = omni room-sensing rays, green = target ray (clear line of sight),
## red = target ray (occluded).
## [br][br][b]Note:[/b] Rays are always shown in the editor when the node is selected.
@export var debug_draw_rays := false

## Draws wireframe spheres for the inner radius (cyan) and outer boundary
## (orange) at runtime (in-game) when volume attenuation is enabled.
## [br][br][b]Note:[/b] Radius shapes are always shown in the editor when the node is selected.
@export var debug_draw_radius := false

## Draws a small wireframe sphere at the emitter origin that indicates
## playback state: [color=green]green[/color] = playing,
## [color=red]red[/color] = stopped.
## [br][br][b]Note:[/b] Always shown in the editor when the node is selected.
@export var debug_draw_playing_state := false

## Displays key spatial-audio diagnostics as an on-screen overlay every
## update cycle while within the radius of the source.
## [br]Displays: listener distance, occlusion state, lowpass cutoff, reverb
## room size / wetness, volume, and per-ray distances.
@export var display_debug_info := false :
	set(value):
		display_debug_info = value
		notify_property_list_changed()

## While the debug overlay is visible, press this key to toggle all
## spatial-audio effects on/off so you can A/B compare the difference.
@export var debug_toggle_effects_key : Key = KEY_F1

## While the debug overlay is visible, press this key to toggle debug
## shape drawing (rays, spheres) on/off at runtime.
@export var debug_toggle_shapes_key : Key = KEY_F2
#endregion

#region INTERNAL STATE

var _raycasts : Array[RayCast3D] = []
var _distances : Array[float] = []
var _ray_names : Array[String] = []

## Normalised world-space direction for each omni ray (used for floor check).
var _ray_directions : Array[Vector3] = []

## Stores reflection segments for debug drawing.
## Each entry is an Array of Vector3 points (world-space) tracing the
## ray path: [origin, hit1, hit2, ...].  Empty for non-reflected rays.
var _reflection_paths : Array[Array] = []

## Per-ray flag: true when the last segment in _reflection_paths escaped
## (no hit) and should be drawn red / excluded from distance.
var _reflection_escaped : Array[bool] = []

## Average absorption coefficient of the surface(s) each omni ray hit.
## For reflected rays this is the cumulative weighted absorption along
## the entire path.  Escaped rays store -1.0 (ignored in averaging).
var _ray_absorptions : Array[float] = []

## Material name of the surface each omni ray first hit (for debug display).
var _ray_material_names : Array[String] = []

var _target_raycast : RayCast3D = null

## Classic omni ray definitions: direction + rotation_degrees.
const _CLASSIC_RAYS := {
	"Left":          [Vector3( 1, 0, 0), Vector3.ZERO],
	"Right":         [Vector3(-1, 0, 0), Vector3.ZERO],
	"Forward":       [Vector3( 0, 0, 1), Vector3.ZERO],
	"ForwardLeft":   [Vector3( 0, 0, 1), Vector3(0,  45, 0)],
	"ForwardRight":  [Vector3( 0, 0, 1), Vector3(0, -45, 0)],
	"Backward":      [Vector3( 0, 0,-1), Vector3(0,  45, 0)],
	"BackwardLeft":  [Vector3( 0, 0,-1), Vector3(0, -45, 0)],
	"BackwardRight": [Vector3( 0, 0,-1), Vector3.ZERO],
	"Up":            [Vector3( 0, 1, 0), Vector3.ZERO],
	"Down":          [Vector3( 0,-1, 0), Vector3.ZERO],
}

var _last_update_time := 0.0
var _setup_complete := false
var _initial_scan_done := false
var _autoplay_fade_active := false

## Internal state for signal emission
var _was_inside_inner := false
var _was_in_falloff := false
var _was_audible := false
var _last_listener_distance := -1.0

var _last_reverb_room_size := -1.0
var _last_reverb_wetness := -1.0
var _last_reverb_damping := -1.0
var _last_air_absorption_cutoff := -1.0

var _bus_name : String
var _bus_idx : int = -1
var _reverb_effect : AudioEffectReverb
var _lowpass_filter : AudioEffectLowPassFilter

# Target parameters (lerped toward each frame)
var _target_lowpass_cutoff : float = 20000.0
var _target_reverb_room_size : float = 0.0
var _target_reverb_wetness : float = 0.0
var _target_reverb_damping : float = 0.0
var _target_volume_db : float = 0.0

## Ratio of omni rays that escaped to infinity (0 = enclosed, 1 = fully open).
var _openness : float = 0.0

## Stored base panning strength so we can restore it.
var _base_panning_strength : float = 1.0
var _target_panning_strength : float = 1.0

## Air absorption lowpass target (combined with occlusion in _lerp_parameters).
var _target_air_absorption_cutoff : float = 20000.0

## Active delay timer for sound-speed playback deferral (if any).
var _pending_delay_timer : SceneTreeTimer = null

## Timestamp (msec) when play() was initiated (for debug indicator).
var _play_initiated_time : int = -1
## Duration (msec) the debug indicator should stay green after play() is called.
var _play_initiated_duration : int = 0

## Number of walls detected in the last occlusion update (for debug display).
var _last_wall_count : int = 0

## Material names of walls hit in the last occlusion update (for debug display).
var _last_wall_materials : Array[String] = []

var _debug_immediate : ImmediateMesh = null
var _debug_instance : MeshInstance3D = null

var _base_volume_db : float = 0.0
## External volume offset (dB) injected by routing/reflection systems.
var _external_volume_db_offset : float = 0.0
## External occlusion hold-until time (msec). While active, occlusion is forced open.
var _external_occlusion_hold_until_msec : int = 0

var _debug_panel : PanelContainer = null
var _debug_minimized := false
var _debug_minimize_btn : Button = null
var _debug_header_label : RichTextLabel = null
var _debug_content_vbox : VBoxContainer = null
var _debug_overlay_label : RichTextLabel = null
var _debug_rays_label : RichTextLabel = null
var _debug_rays_scroll : ScrollContainer = null
var _debug_rays_toggle : Button = null
var _debug_rays_expanded := false
var _debug_navigation_label : RichTextLabel = null
var _debug_navigation_scroll : ScrollContainer = null
var _debug_navigation_toggle : Button = null
var _debug_navigation_expanded := false
var _debug_connector_line : Line2D = null
var _debug_occl_abs_weight: float = 0.0
## Per-ray expansion state for reflection dropdowns in debug overlay.
var _debug_ray_reflections_expanded = {}  # int index -> bool
var _external_navigation_debug_active: bool = false
var _external_navigation_debug: Dictionary = {}

static var global_effects_disabled : bool = false

## Shared debug overlay container (created lazily, used by all instances).
static var _debug_shared_layer : CanvasLayer = null
static var _debug_shared_scroll : ScrollContainer = null
static var _debug_shared_vbox : VBoxContainer = null

## Explicitly using EditorInterface throws errors in exported builds. Use it implicitly.
static var _editor_interface

var _effects_enabled_value : bool = true
@export var effects_enabled : bool = true :
	set(value):
		_effects_enabled_value = value
		SpatialAudioPlayer3D.global_effects_disabled = not value
	get():
		return _effects_enabled_value

static func set_global_effects_disabled(disabled: bool) -> void:
	SpatialAudioPlayer3D.global_effects_disabled = disabled


func set_external_volume_db_offset(offset_db: float) -> void:
	## Allows external systems (e.g. reflection routing) to apply extra
	## loudness loss without fighting this class's internal attenuation.
	_external_volume_db_offset = offset_db


func get_external_volume_db_offset() -> float:
	return _external_volume_db_offset


func clear_external_volume_db_offset() -> void:
	_external_volume_db_offset = 0.0


func _apply_external_volume_offset(volume_db_value: float) -> float:
	return maxf(volume_db_value + _external_volume_db_offset, minimum_volume_db)


func set_external_occlusion_hold(seconds: float) -> void:
	## Temporarily forces occlusion open. Intended for proxy-transition smoothing.
	var duration_ms := int(maxf(seconds, 0.0) * 1000.0)
	if duration_ms <= 0:
		return
	var until := Time.get_ticks_msec() + duration_ms
	_external_occlusion_hold_until_msec = maxi(_external_occlusion_hold_until_msec, until)


func clear_external_occlusion_hold() -> void:
	_external_occlusion_hold_until_msec = 0


func is_external_occlusion_held() -> bool:
	return Time.get_ticks_msec() < _external_occlusion_hold_until_msec


func set_external_navigation_debug_data(active: bool, info: Dictionary = {}) -> void:
	## Injects navigation/proxy diagnostics from an external routing agent.
	_external_navigation_debug_active = active
	_external_navigation_debug = info.duplicate(true) if active else {}
	_refresh_navigation_debug_visibility()


func clear_external_navigation_debug_data() -> void:
	_external_navigation_debug_active = false
	_external_navigation_debug.clear()
	_refresh_navigation_debug_visibility()
#endregion

#region SOUND SPEED DELAY

## Deisgned as an override for [method AudioStreamPlayer3D.play] to delay playback
## based on the listener's distance and [param speed_of_sound].
func play_with_delay(from_position: float = 0.0) -> void:
	# Track initiation time for the debug playing-state sphere.
	var stream_len := 0.0
	if stream != null:
		stream_len = stream.get_length()

	if Engine.is_editor_hint() or not enable_sound_delay:
		_play_initiated_time = Time.get_ticks_msec()
		_play_initiated_duration = int(stream_len * 1000.0)
		super.play(from_position)
		emit_signal("spatial_audio_playback_started")
		return

	var listener := _get_listener()
	if listener == null:
		_play_initiated_time = Time.get_ticks_msec()
		_play_initiated_duration = int(stream_len * 1000.0)
		super.play(from_position)
		return

	var distance := global_position.distance_to(listener.global_position)
	var delay := distance / speed_of_sound

	# Skip negligible delays (<10 ms).
	if delay < 0.01:
		_play_initiated_time = Time.get_ticks_msec()
		_play_initiated_duration = int(stream_len * 1000.0)
		super.play(from_position)
		return

	# Mark initiated now — duration is the stream length from the call.
	_play_initiated_time = Time.get_ticks_msec()
	_play_initiated_duration = int(stream_len * 1000.0)

	# Cancel any previously pending delayed play.
	if _pending_delay_timer != null and _pending_delay_timer.time_left > 0.0:
		if _pending_delay_timer.timeout.is_connected(_deferred_play):
			_pending_delay_timer.timeout.disconnect(_deferred_play)

	_pending_delay_timer = get_tree().create_timer(delay)
	_pending_delay_timer.timeout.connect(_deferred_play.bind(from_position))


func _deferred_play(from_position: float) -> void:
	_pending_delay_timer = null
	if is_inside_tree():
		super.play(from_position)
		emit_signal("spatial_audio_playback_started")


func stop() -> void:
	# Override to emit a stopped signal
	super.stop()
	emit_signal("spatial_audio_playback_stopped")
#endregion

#region LIFECYCLE


func _validate_property(property: Dictionary) -> void:
	if property.name in ["fibonacci_ray_count", "fibonacci_ray_reflections"] and ray_distribution != RayDistribution.FIBONACCI_SPHERE:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# Hide Room Size Reverb children when disabled
	if not room_size_reverb and property.name in ["max_reverb_wetness", "surface_absorption", "absorption_wetness_influence", "absorption_damping_influence", "ignore_floor", "floor_angle_threshold", "reverb_collision_mask"]:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# Hide surface absorption children when disabled
	if not surface_absorption and property.name in ["absorption_wetness_influence", "absorption_damping_influence"]:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# Hide floor angle threshold when ignore_floor is off
	if not ignore_floor and property.name == "floor_angle_threshold":
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# Hide Occlusion children when disabled
	if not audio_occlusion and property.name in ["occlusion_strength", "max_occlusion_hits", "fallback_transmission", "occlusion_volume_strength", "max_occlusion_volume_reduction", "occlusion_collision_mask", "ignore_listener_body"]:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# Hide Attenuation children when disabled
	if not enable_volume_attenuation and property.name in ["inner_radius", "falloff_distance", "attenuation_function", "inner_radius_panning_strength", "user_attenuation_curve"]:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# Hide collision-shape distribution fields when that distribution isn't selected
	if property.name in ["shape_ray_count", "scatter_shape", "shape_scatter_randomness"] and ray_distribution != RayDistribution.SHAPE_SCATTER:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# If a scatter shape hasn't been selected, hide shape-specific children
	if scatter_shape == null and property.name in ["shape_ray_count", "shape_scatter_randomness"]:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# Hide user curve unless user-defined attenuation is selected
	if property.name == "user_attenuation_curve" and attenuation_function != AttenuationFunction.USER_DEFINED:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# Hide Air Absorption children when disabled
	if not enable_air_absorption and property.name in ["air_absorption_min_distance", "air_absorption_max_distance", "air_absorption_cutoff_freq_min", "air_absorption_cutoff_freq_max", "air_absorption_log_frequency_scaling"]:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# Hide Sound Speed Delay children when disabled
	if not enable_sound_delay and property.name == "speed_of_sound":
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# Hide autoplay fade speed when autoplay fade-in is disabled
	if not autoplay_fade_in and property.name == "autoplay_fade_in_speed":
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# Hide debug keybinds when debug overlay display is disabled
	if not display_debug_info and property.name in ["debug_toggle_effects_key", "debug_toggle_shapes_key"]:
		property.usage &= ~PROPERTY_USAGE_EDITOR


func _ready() -> void:
	if not Engine.is_editor_hint():
		_base_volume_db = volume_db
		_target_volume_db = volume_db
		_base_panning_strength = panning_strength
		_target_panning_strength = panning_strength
		# Start at inaudible volume — the first spatial update will compute
		# correct targets, snap them, and let the volume lerp up naturally.
		# Only start at `minimum_volume_db` when autoplay is enabled and the
		# `autoplay_fade_in` option is turned on. This prevents loud unfiltered
		# playback when spawning with autoplay.
		if autoplay and autoplay_fade_in:
			volume_db = minimum_volume_db
			_autoplay_fade_active = true

		# Disable Godot's built-in distance attenuation when we handle it.
		if enable_volume_attenuation:
			attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED

		# Create a dedicated audio bus with reverb + lowpass.
		_bus_name = audio_bus_prefix + "#" + str(randi())
		AudioServer.add_bus()
		_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(_bus_idx, _bus_name)
		AudioServer.set_bus_send(_bus_idx, bus)
		self.bus = _bus_name

		AudioServer.add_bus_effect(_bus_idx, AudioEffectReverb.new(), 0)
		_reverb_effect = AudioServer.get_bus_effect(_bus_idx, 0)
		AudioServer.add_bus_effect(_bus_idx, AudioEffectLowPassFilter.new(), 1)
		_lowpass_filter = AudioServer.get_bus_effect(_bus_idx, 1)

	# Build raycasts based on the chosen distribution.
	_rebuild_raycasts()

	if Engine.is_editor_hint() or debug_draw_rays or debug_draw_radius or debug_draw_playing_state:
		_setup_debug_mesh()

	effects_enabled = not SpatialAudioPlayer3D.global_effects_disabled
	_setup_complete = true

	# Initialise last-known values for signals
	_last_listener_distance = -1.0
	_was_inside_inner = false
	_was_in_falloff = false
	_was_audible = false
	_last_reverb_room_size = _target_reverb_room_size
	_last_reverb_wetness = _target_reverb_wetness
	_last_reverb_damping = _target_reverb_damping
	_last_air_absorption_cutoff = _target_air_absorption_cutoff

	# Set EditorInterface safely
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		_editor_interface = Engine.get_singleton("EditorInterface")


func _rebuild_raycasts() -> void:
	# Remove existing raycast children.
	for r in _raycasts:
		if r != null and r.is_inside_tree():
			remove_child(r)
			r.queue_free()

	_raycasts.clear()
	_distances.clear()
	_ray_names.clear()
	_ray_directions.clear()
	_reflection_paths.clear()
	_reflection_escaped.clear()
	_ray_absorptions.clear()
	_ray_material_names.clear()
	_target_raycast = null

	if ray_distribution == RayDistribution.CLASSIC:
		for key in _CLASSIC_RAYS:
			var r := RayCast3D.new()
			r.name = key
			r.target_position = _CLASSIC_RAYS[key][0] * max_raycast_distance
			r.rotation_degrees = _CLASSIC_RAYS[key][1]
			r.collision_mask = reverb_collision_mask
			r.debug_shape_thickness = 0
			# Compute the world-space direction accounting for rotation.
			var rot_deg : Vector3 = _CLASSIC_RAYS[key][1]
			var rot_rad := Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
			var basis := Basis.from_euler(rot_rad)
			var dir := (basis * (_CLASSIC_RAYS[key][0] as Vector3)).normalized()
			_raycasts.append(r)
			_distances.append(0.0)
			_ray_names.append(key)
			_ray_directions.append(dir)
			_reflection_paths.append([])
			_reflection_escaped.append(false)
			_ray_absorptions.append(0.0)
			_ray_material_names.append("")
			add_child(r, false, Node.INTERNAL_MODE_FRONT)
	elif ray_distribution == RayDistribution.FIBONACCI_SPHERE:
		var fib_dirs := _generate_fibonacci_sphere(fibonacci_ray_count)
		for i in fib_dirs.size():
			var r := RayCast3D.new()
			var ray_name := "Fib_%02d" % i
			r.name = ray_name
			r.target_position = fib_dirs[i] * max_raycast_distance
			r.collision_mask = reverb_collision_mask
			r.debug_shape_thickness = 0
			_raycasts.append(r)
			_distances.append(0.0)
			_ray_names.append(ray_name)
			_ray_directions.append(fib_dirs[i].normalized())
			_reflection_paths.append([])
			_reflection_escaped.append(false)
			_ray_absorptions.append(0.0)
			_ray_material_names.append("")
			add_child(r, false, Node.INTERNAL_MODE_FRONT)
	elif ray_distribution == RayDistribution.SHAPE_SCATTER:
		var center_world := global_transform.origin
		var shape_origin := center_world
		var radius := 0.5
		if scatter_shape != null and scatter_shape.is_inside_tree():
			shape_origin = scatter_shape.global_transform.origin
			# Approximate radius from node scale; user can adjust scatter by scale.
			var s := scatter_shape.scale
			radius = max(max(abs(s.x), abs(s.y)), abs(s.z)) * 0.5
		# Create rays positioned around the shape and fire outward.
		for i in range(shape_ray_count):
			# Spawn point around the shape (random point within radius).
			var spawn_dir := _random_unit_vector()
			var origin_world := shape_origin + spawn_dir * radius * randf()
			# Direction from shape center toward the spawn point.
			var center_dir := (origin_world - shape_origin).normalized()
			# Purely random direction for full randomness.
			var random_dir := _random_unit_vector()
			# Blend between center-directed and random. 0 => center only, 1 => random only.
			var t := clampf(float(shape_scatter_randomness) / 50.0, 0.0, 1.0)
			var dir := (center_dir * (1.0 - t) + random_dir * t).normalized()
			var r := RayCast3D.new()
			var ray_name := "Shape_%02d" % i
			r.name = ray_name
			_raycasts.append(r)
			_distances.append(0.0)
			_ray_names.append(ray_name)
			_ray_directions.append(dir)
			_reflection_paths.append([])
			_reflection_escaped.append(false)
			_ray_absorptions.append(0.0)
			_ray_material_names.append("")
			add_child(r, false, Node.INTERNAL_MODE_FRONT)
			# Place the ray at the computed world origin and set its target.
			r.global_transform = Transform3D(Basis(), origin_world)
			r.target_position = dir * max_raycast_distance
			r.collision_mask = reverb_collision_mask
			r.debug_shape_thickness = 0
			# Note: ray direction stored in _ray_directions for later use.

	# Target ray — always added last for wall-occlusion.
	var target_r := RayCast3D.new()
	target_r.name = "Target"
	target_r.target_position = Vector3(0, 0, 1) * max_raycast_distance
	target_r.collision_mask = occlusion_collision_mask
	target_r.debug_shape_thickness = 0
	_target_raycast = target_r
	_raycasts.append(target_r)
	_distances.append(0.0)
	_ray_names.append("Target")
	_ray_directions.append(Vector3.FORWARD) # placeholder, not used for reverb
	_reflection_paths.append([])
	_reflection_escaped.append(false)
	_ray_absorptions.append(0.0)
	_ray_material_names.append("")
	add_child(target_r, false, Node.INTERNAL_MODE_FRONT)


func _unhandled_input(event: InputEvent) -> void:
	if not display_debug_info or Engine.is_editor_hint():
		return
	# Only respond when this instance's debug panel is visible.
	if _debug_panel == null or not _debug_panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == debug_toggle_effects_key:
			effects_enabled = not effects_enabled
			get_viewport().set_input_as_handled()
		elif (event as InputEventKey).keycode == debug_toggle_shapes_key:
			debug_draw_rays = not debug_draw_rays
			debug_draw_radius = not debug_draw_radius
			get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	# Remove per-instance debug nodes from the shared container.
	if is_instance_valid(_debug_panel):
		if _debug_panel.get_parent() != null:
			_debug_panel.get_parent().remove_child(_debug_panel)
		_debug_panel.queue_free()
	_debug_panel = null
	if is_instance_valid(_debug_connector_line):
		if _debug_connector_line.get_parent() != null:
			_debug_connector_line.get_parent().remove_child(_debug_connector_line)
		_debug_connector_line.queue_free()
	_debug_connector_line = null
	if not Engine.is_editor_hint():
		var idx := AudioServer.get_bus_index(_bus_name)
		if idx >= 0:
			AudioServer.remove_bus(idx)
#endregion

#region PHYSICS PROCESS


func _physics_process(delta: float) -> void:
	if not _setup_complete:
		return

	_last_update_time += delta

	# Full spatial audio update at the configured frequency.
	if _last_update_time > update_frequency:
		# Update all omni raycasts in one batch.
		if room_size_reverb:
			for i in range(_distances.size() - 1):  # skip Target (last)
				_update_omni_distance(_raycasts[i], i)

		var listener := _get_listener()
		if listener != null:
			_on_spatial_audio_update(listener)

		# On the first completed scan, snap all effects to their targets so
		# there is no audible unfiltered bleed. Subsequent frames lerp.
		if not _initial_scan_done and not Engine.is_editor_hint():
			_initial_scan_done = true
			# If we're performing an autoplay fade-in, skip snapping the audible
			# volume so it can lerp up with its dedicated speed. Other params
			# still snap to avoid audible artifacting.
			_snap_parameters(not _autoplay_fade_active)

		_last_update_time = 0.0

	# Smooth parameter lerping (runtime only — no effects in editor).
	if not Engine.is_editor_hint():
		_lerp_parameters(delta)

	# Debug visualisation.
	var _editor_selected := _is_editor_selected()
	if debug_draw_rays or debug_draw_radius or debug_draw_playing_state or _editor_selected:
		_draw_debug_shapes(_editor_selected)
	elif _debug_immediate != null:
		_debug_immediate.clear_surfaces()

	# Update the connector line every frame for smooth tracking.
	_update_debug_connector_line()
#endregion

#region HELPERS

func _is_editor_selected() -> bool:
	if not Engine.is_editor_hint():
		return false
	var selection = _editor_interface.get_selection()
	return self in selection.get_selected_nodes()


func _get_listener() -> Node3D:
	if custom_listener_target != null:
		return custom_listener_target
	if Engine.is_editor_hint():
		# Use the editor's 3D viewport camera so the target ray and debug
		# visualisation point at the developer's viewpoint.
		var vp = _editor_interface.get_editor_viewport_3d()
		if vp != null:
			return vp.get_camera_3d()
		return null
	return get_viewport().get_camera_3d()


## Walks up the scene tree from [param node] to find the first
## [CharacterBody3D] ancestor. Returns [code]null[/code] if none is found.
static func _find_character_body(node: Node) -> CharacterBody3D:
	var current := node
	while current != null:
		if current is CharacterBody3D:
			return current
		current = current.get_parent()
	return null


static func _generate_fibonacci_sphere(count: int) -> Array[Vector3]:
	## Returns [code]count[/code] unit-length directions evenly distributed
	## over a sphere using a Fibonacci / golden-angle spiral.
	var directions : Array[Vector3] = []
	var golden_ratio := (1.0 + sqrt(5.0)) / 2.0
	for i in count:
		# Polar angle — uniform in cos(θ) so points aren't bunched at poles.
		var theta := acos(1.0 - 2.0 * (float(i) + 0.5) / float(count))
		# Azimuthal angle — golden-angle increments for even spread.
		var phi := TAU * float(i) / golden_ratio
		directions.append(Vector3(
			sin(theta) * cos(phi),
			cos(theta),
			sin(theta) * sin(phi)
		))
	return directions
 
static func _random_unit_vector() -> Vector3:
	# Uniformly sample a direction on the unit sphere.
	var z := randf_range(-1.0, 1.0)
	var theta := randf_range(0.0, TAU)
	var r := sqrt(max(0.0, 1.0 - z * z))
	return Vector3(r * cos(theta), r * sin(theta), z)
#endregion

#region PARAMETER LERPING

func _lerp_parameters(delta: float) -> void:
	var t := clampf(delta * lerp_speed, 0.0, 1.0)

	# Use a dedicated speed for the autoplay volume fade when active so
	# effect parameters can continue to use the general `lerp_speed`.
	var t_volume := t
	if _autoplay_fade_active:
		t_volume = clampf(delta * autoplay_fade_in_speed, 0.0, 1.0)

	volume_db = lerpf(volume_db, _target_volume_db, t_volume)
	panning_strength = lerpf(panning_strength, _target_panning_strength, t)

	# Interpolate lowpass cutoff on a log scale for perceptual smoothness.
	# Combine occlusion lowpass and air absorption by taking the darker filter.
	if _lowpass_filter != null:
		var combined_cutoff := minf(_target_lowpass_cutoff, _target_air_absorption_cutoff)
		var cur_cut := maxf(1.0, float(_lowpass_filter.cutoff_hz))
		var tgt_cut := maxf(1.0, combined_cutoff)
		_lowpass_filter.cutoff_hz = exp(lerp(log(cur_cut), log(tgt_cut), t))

	if _reverb_effect != null:
		_reverb_effect.wet = lerp(_reverb_effect.wet, _target_reverb_wetness * max_reverb_wetness, t)
		_reverb_effect.room_size = lerp(_reverb_effect.room_size, _target_reverb_room_size, t)
		_reverb_effect.damping = lerp(_reverb_effect.damping, _target_reverb_damping, t)

	# If autoplay fade was active and we've effectively reached the target
	# volume, disable the special fade so normal lerps take over.
	if _autoplay_fade_active:
		if abs(volume_db - _target_volume_db) < 0.1:
			volume_db = _target_volume_db
			_autoplay_fade_active = false


## Instantly snaps all audio parameters to their target values, bypassing
## the smooth lerp. Used on the first frame to avoid audible unfiltered bleed.
func _snap_parameters(snap_volume: bool = true) -> void:
	if snap_volume:
		volume_db = _target_volume_db
	# Always snap non-audible parameters to avoid artifacting.
	panning_strength = _target_panning_strength

	if _lowpass_filter != null:
		var combined_cutoff := minf(_target_lowpass_cutoff, _target_air_absorption_cutoff)
		_lowpass_filter.cutoff_hz = maxf(1.0, combined_cutoff)

	if _reverb_effect != null:
		_reverb_effect.wet = _target_reverb_wetness * max_reverb_wetness
		_reverb_effect.room_size = _target_reverb_room_size
		_reverb_effect.damping = _target_reverb_damping
#endregion

#region SPATIAL AUDIO UPDATE

func _on_spatial_audio_update(listener: Node3D) -> void:
	_update_volume_attenuation(listener)
	_update_panning_strength(listener)
	_update_air_absorption(listener)
	_update_reverb()
	_update_lowpass(listener)

	if display_debug_info:
		var dist := listener.global_position.distance_to(global_position)
		var outer := inner_radius + falloff_distance
		var in_range := not enable_volume_attenuation or dist <= outer

		if in_range:
			_print_debug(listener)
		else:
			if _debug_panel != null:
				_debug_panel.visible = false
			if _debug_connector_line != null:
				_debug_connector_line.visible = false
	else:
		if _debug_panel != null:
			_debug_panel.visible = false
		if _debug_connector_line != null:
			_debug_connector_line.visible = false
#endregion

#region VOLUME ATTENUATION (inner / outer radius)

func _update_volume_attenuation(listener: Node3D) -> void:
	if not enable_volume_attenuation:
		_target_volume_db = _apply_external_volume_offset(_base_volume_db)
		return

	var dist := listener.global_position.distance_to(global_position)

	# Emit distance change when it moves enough (0.5 m threshold)
	if _last_listener_distance < 0.0 or abs(dist - _last_listener_distance) >= 0.5:
		_last_listener_distance = dist
		emit_signal("listener_distance_changed", dist)
	var outer_radius := inner_radius + falloff_distance
	# Zone flags for signal transitions
	var inside_inner := dist <= inner_radius
	var in_falloff := dist > inner_radius and dist <= outer_radius
	var audible := dist <= outer_radius

	# Emit transitions
	if inside_inner and not _was_inside_inner:
		emit_signal("inner_radius_entered", listener)
	if not inside_inner and _was_inside_inner:
		emit_signal("inner_radius_exited", listener)

	if in_falloff and not _was_in_falloff:
		emit_signal("falloff_zone_entered", listener)
	if not in_falloff and _was_in_falloff:
		emit_signal("falloff_zone_exited", listener)

	if audible and not _was_audible:
		emit_signal("attenuation_zone_entered", listener)
	if not audible and _was_audible:
		emit_signal("attenuation_zone_exited", listener)

	_was_inside_inner = inside_inner
	_was_in_falloff = in_falloff
	_was_audible = audible

	if inside_inner:
		_target_volume_db = _apply_external_volume_offset(_base_volume_db)
		return

	if dist >= outer_radius:
		_target_volume_db = _apply_external_volume_offset(minimum_volume_db)
		return

	# Normalised distance within the falloff zone (0 = inner edge, 1 = outer edge).
	var alpha := (dist - inner_radius) / falloff_distance
	var att := _apply_attenuation_function(alpha)
	# Interpolate in linear amplitude (not dB) for perceptually smoother falloff.
	var min_gain := pow(10.0, minimum_volume_db / 20.0)
	var base_gain := pow(10.0, _base_volume_db / 20.0)
	var gain := lerp(min_gain, base_gain, att)
	gain = max(gain, 1e-8)
	_target_volume_db = _apply_external_volume_offset(20.0 * log(gain) / log(10.0))


func _update_panning_strength(listener: Node3D) -> void:
	## Scales stereo panning when the listener is inside the inner radius.
	## 0 = centred, 1 = default, 2 = exaggerated.
	if not enable_volume_attenuation or is_equal_approx(inner_radius_panning_strength, 1.0):
		_target_panning_strength = _base_panning_strength
		return

	var dist := listener.global_position.distance_to(global_position)
	if dist >= inner_radius or inner_radius <= 0.0:
		_target_panning_strength = _base_panning_strength
		return

	# 0 at centre → 1 at inner_radius boundary.
	var ratio := dist / inner_radius
	# At the centre, apply the multiplier fully; at the edge, return to default.
	var centre_pan := clampf(_base_panning_strength * inner_radius_panning_strength, 0.0, 2.0)
	_target_panning_strength = lerpf(centre_pan, _base_panning_strength, ratio)


func _update_air_absorption(listener: Node3D) -> void:
	## Distance-based lowpass that models high-frequency decay through air.
	if not enable_air_absorption or global_effects_disabled:
		_target_air_absorption_cutoff = 20000.0
		return

	var dist := listener.global_position.distance_to(global_position)

	if dist <= air_absorption_min_distance:
		_target_air_absorption_cutoff = float(air_absorption_cutoff_freq_min)
		return

	if dist >= air_absorption_max_distance:
		_target_air_absorption_cutoff = float(air_absorption_cutoff_freq_max)
		return

	# Normalised position between min and max distance.
	var alpha := (dist - air_absorption_min_distance) / maxf(air_absorption_max_distance - air_absorption_min_distance, 0.001)

	if air_absorption_log_frequency_scaling:
		# Logarithmic interpolation for perceptually linear sweep.
		var log_min := log(maxf(float(air_absorption_cutoff_freq_min), 1.0))
		var log_max := log(maxf(float(air_absorption_cutoff_freq_max), 1.0))
		_target_air_absorption_cutoff = exp(lerpf(log_min, log_max, alpha))
	else:
		_target_air_absorption_cutoff = lerpf(float(air_absorption_cutoff_freq_min), float(air_absorption_cutoff_freq_max), alpha)

	# Emit air absorption changes when cutoff changes meaningfully
	if abs(_target_air_absorption_cutoff - _last_air_absorption_cutoff) > 1.0:
		emit_signal("air_absorption_updated", _target_air_absorption_cutoff)
		emit_signal("air_absorption_zone_changed", _target_air_absorption_cutoff)
		_last_air_absorption_cutoff = _target_air_absorption_cutoff


func _apply_attenuation_function(alpha: float) -> float:
	## Returns 1.0 (full volume) → 0.0 (silent) for alpha 0 → 1.
	match attenuation_function:
		AttenuationFunction.LINEAR:
			return 1.0 - alpha
		AttenuationFunction.LOGARITHMIC:
			# Fast drop close, slow tail — good for spot sounds.
			return 1.0 - (log(alpha * 9.0 + 1.0) / log(10.0))
		AttenuationFunction.INVERSE:
			# Very steep near the source, nearly silent far away.
			return 1.0 / (1.0 + alpha * 9.0)
		AttenuationFunction.LOG_REVERSE:
			# Stays loud across distance, drops dramatically at far end.
			return log(1.0 + (1.0 - alpha) * 9.0) / log(10.0)
		AttenuationFunction.NATURAL_SOUND:
			# Power curve — middle-ground between Logarithmic and Inverse.
			return pow(1.0 - alpha, 1.5)
		AttenuationFunction.USER_DEFINED:
			if user_attenuation_curve != null:
				return clampf(user_attenuation_curve.sample(clampf(alpha, 0.0, 1.0)), 0.0, 1.0)
			else:
				return 1.0 - alpha # fallback to linear if no curve
	return 1.0 - alpha
#endregion

#region REVERB (room-size estimation via omni raycasts)


func _update_omni_distance(ray: RayCast3D, idx: int) -> void:
	ray.force_raycast_update()
	_reflection_paths[idx] = []
	_reflection_escaped[idx] = false
	_ray_absorptions[idx] = -1.0  # -1 = no hit / escaped
	_ray_material_names[idx] = ""

	if ray.get_collider() == null:
		_distances[idx] = max_raycast_distance
		_reflection_escaped[idx] = true
		ray.enabled = false
		return

	var first_hit := ray.get_collision_point()
	var total_dist := global_position.distance_to(first_hit)

	# Sample absorption from the first-hit surface (only if it has a material).
	var first_absorption := -1.0  # -1 = no material found
	var first_mat_name := ""
	if surface_absorption:
		var collider := ray.get_collider() as Node
		var ab := AcousticBody.find_for_collider(collider)
		if ab != null and ab.acoustic_material != null:
			var mat := ab.acoustic_material
			first_absorption = (mat.absorption_low + mat.absorption_mid + mat.absorption_high) / 3.0
			if mat.resource_name != "":
				first_mat_name = mat.resource_name
			elif mat.resource_path != "":
				first_mat_name = mat.resource_path.get_file().get_basename()
			else:
				first_mat_name = "AcousticMaterial"
	_ray_absorptions[idx] = first_absorption
	_ray_material_names[idx] = first_mat_name

	# Reflections only for Fibonacci mode with reflections > 0.
	if ray_distribution != RayDistribution.FIBONACCI_SPHERE or fibonacci_ray_reflections <= 0:
		_distances[idx] = total_dist
		ray.enabled = false
		return

	# Trace reflections using the physics space directly.
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.collision_mask = reverb_collision_mask

	var path : Array[Vector3] = [global_position, first_hit]
	var current_pos := first_hit
	var incoming_dir := (first_hit - global_position).normalized()
	var current_normal := ray.get_collision_normal()
	var remaining_dist := max_raycast_distance - total_dist

	# Accumulate absorption across all bounces (only surfaces with materials).
	var absorption_sum := maxf(first_absorption, 0.0)
	var absorption_count := 1 if first_absorption >= 0.0 else 0

	for _bounce in fibonacci_ray_reflections:
		if remaining_dist <= 0.01:
			break
		# Reflect the incoming direction about the surface normal.
		var reflect_dir := incoming_dir - 2.0 * incoming_dir.dot(current_normal) * current_normal
		reflect_dir = reflect_dir.normalized()

		# Offset slightly to avoid self-intersection.
		params.from = current_pos + current_normal * 0.01
		params.to = params.from + reflect_dir * remaining_dist

		var result := space.intersect_ray(params)
		if result.is_empty():
			# Ray escaped — sound energy lost to open space.
			# Append the escaped endpoint for red debug drawing but
			# do NOT count this distance (it never hit a surface).
			var escape_end := params.from + reflect_dir * remaining_dist
			path.append(escape_end)
			_reflection_escaped[idx] = true
			break

		var hit_point : Vector3 = result["position"]
		var seg_dist := current_pos.distance_to(hit_point)
		total_dist += seg_dist
		remaining_dist -= seg_dist
		path.append(hit_point)

		# Emit signal for reverb/reflection ray collision
		var bounce_collider : Node = result["collider"]
		emit_signal("reverb_ray_collided", hit_point, current_pos, bounce_collider)

		# Sample absorption from the bounced surface (skip if no material).
		if surface_absorption:
			var bounce_ab := AcousticBody.find_for_collider(bounce_collider)
			if bounce_ab != null and bounce_ab.acoustic_material != null:
				var bmat := bounce_ab.acoustic_material
				var bounce_absorption := (bmat.absorption_low + bmat.absorption_mid + bmat.absorption_high) / 3.0
				absorption_sum += bounce_absorption
				absorption_count += 1

		incoming_dir = reflect_dir
		current_normal = result["normal"]
		current_pos = hit_point

	# Store the average absorption across all hits in this ray's path.
	if surface_absorption and absorption_count > 0:
		_ray_absorptions[idx] = absorption_sum / float(absorption_count)

	_distances[idx] = total_dist
	_reflection_paths[idx] = path
	ray.enabled = false


func _update_reverb() -> void:
	if _reverb_effect == null:
		return

	if global_effects_disabled:
		_target_reverb_wetness = 0.0
		_target_reverb_room_size = 0.0
		_target_reverb_damping = 0.0
		_openness = 0.0
		return

	if not room_size_reverb:
		_target_reverb_wetness = 0.0
		_target_reverb_room_size = 0.0
		_target_reverb_damping = 0.0
		_openness = 0.0
		return

	var omni_count := maxi(_distances.size() - 1, 1)  # exclude Target ray (last)
	var room_size := 0.0
	var floor_cos_threshold := cos(deg_to_rad(floor_angle_threshold))
	var active_count := 0  # rays actually considered (after floor exclusion)

	# Openness is computed as a continuous value per ray rather than a binary
	# escaped/not-escaped count.  A ray that travels 95 % of max_raycast_distance
	# before hitting something is almost as "open" as one that fully escapes.
	var openness_sum := 0.0

	for i in range(omni_count):
		# Skip rays pointing at the floor when floor ignore is enabled.
		if ignore_floor and i < _ray_directions.size():
			if _ray_directions[i].y <= -floor_cos_threshold:
				continue

		active_count += 1
		var d : float = _distances[i]
		var escaped : bool = i < _reflection_escaped.size() and _reflection_escaped[i]

		if escaped:
			# Fully escaped — maximum openness and room-size contribution.
			openness_sum += 1.0
		elif d > 0.0:
			# Distance-based openness: rays that travel far indicate open space.
			openness_sum += d / max_raycast_distance

	var active_f := float(maxi(active_count, 1))

	# Openness ratio: 0.0 = fully enclosed, 1.0 = fully open/outdoor.
	_openness = openness_sum / active_f

	# Room size is the average normalised distance across all active rays.
	# In open environments this naturally approaches 1.0.
	for i in range(omni_count):
		if ignore_floor and i < _ray_directions.size():
			if _ray_directions[i].y <= -floor_cos_threshold:
				continue
		var d : float = _distances[i]
		var escaped : bool = i < _reflection_escaped.size() and _reflection_escaped[i]
		if escaped:
			room_size += 1.0 / active_f
		elif d > 0.0:
			room_size += (d / max_raycast_distance) / active_f

	room_size = minf(room_size, 1.0)

	# Enclosed spaces reflect energy back → high wetness.
	# Open spaces let energy escape → low wetness.
	# Use a power curve so wetness drops off faster as openness increases.
	var wetness := pow(1.0 - _openness, 2.0)

	# In outdoor environments, what little reverb remains should decay quickly.
	# Damping 0.0 = long tail (indoor), 1.0 = short tail (outdoor).
	var damping := lerpf(0.0, 1.0, _openness)

	#  Surface absorption modulation 
	# Average the absorption sampled from each omni ray that hit a surface.
	# This drives wetness down (absorptive walls eat energy) and damping up
	# (absorptive rooms decay faster).
	if surface_absorption:
		var abs_sum := 0.0
		var abs_count := 0
		var floor_cos_abs := cos(deg_to_rad(floor_angle_threshold))
		for i in range(omni_count):
			if ignore_floor and i < _ray_directions.size() and _ray_directions[i].y <= -floor_cos_abs:
				continue
			if i < _ray_absorptions.size() and _ray_absorptions[i] >= 0.0:
				abs_sum += _ray_absorptions[i]
				abs_count += 1
		if abs_count > 0:
			var avg_abs := abs_sum / float(abs_count)
			# Wetness: reflective surfaces (low absorption) preserve reverb;
			# absorptive surfaces reduce it.
			wetness *= lerpf(1.0, 1.0 - avg_abs, absorption_wetness_influence)
			# Damping: absorptive surfaces increase damping (shorter tail).
			damping = clampf(damping + avg_abs * absorption_damping_influence, 0.0, 1.0)

	# Emit reverb changes when significant differences occur
	var prev_room := _last_reverb_room_size
	var prev_wet := _last_reverb_wetness
	var prev_damp := _last_reverb_damping

	_target_reverb_damping = damping
	_target_reverb_wetness = wetness
	_target_reverb_room_size = room_size

	if abs(_target_reverb_room_size - prev_room) > 0.01 or abs(_target_reverb_wetness - prev_wet) > 0.01 or abs(_target_reverb_damping - prev_damp) > 0.01:
		emit_signal("reverb_updated", _target_reverb_room_size, _target_reverb_wetness, _target_reverb_damping)
		emit_signal("reverb_zone_changed", _target_reverb_room_size, _target_reverb_wetness)

	_last_reverb_room_size = _target_reverb_room_size
	_last_reverb_wetness = _target_reverb_wetness
	_last_reverb_damping = _target_reverb_damping
#endregion

#region OCCLUSION (single target raycast)

func _update_lowpass(listener: Node3D) -> void:
	if _lowpass_filter == null or not audio_occlusion:
		_target_lowpass_cutoff = float(open_lowpass_cutoff)
		return

	if is_external_occlusion_held():
		var prev_wall_count := _last_wall_count
		_target_lowpass_cutoff = float(open_lowpass_cutoff)
		_last_wall_count = 0
		_last_wall_materials.clear()
		_last_wall_absorptions.clear()
		if prev_wall_count > 0:
			emit_signal("occlusion_changed", 0, _target_lowpass_cutoff)
			emit_signal("audio_unoccluded", listener)
		return

	if global_effects_disabled:
		_target_lowpass_cutoff = float(open_lowpass_cutoff)
		return

	if _target_raycast == null:
		return

	# When volume attenuation is enabled, use the outer radius as the
	# effective range for occlusion — the sound is inaudible beyond it.
	# Otherwise fall back to max_distance / max_raycast_distance.
	var effective_max_dist : float
	if enable_volume_attenuation:
		effective_max_dist = inner_radius + falloff_distance
	else:
		effective_max_dist = max_distance if max_distance > 0.0 else max_raycast_distance

	var dist_to_player := clampf(
		listener.global_position.distance_to(global_position), 0.0, effective_max_dist
	)

	# Disable the ray when the listener is out of range.
	if dist_to_player >= effective_max_dist:
		_target_raycast.enabled = false
		_target_lowpass_cutoff = float(open_lowpass_cutoff)
		return

	# We still point the RayCast3D node toward the listener for the debug
	# overlay's occluded/clear colouring, but the actual multi-hit detection
	# uses PhysicsDirectSpaceState3D so we can march through multiple walls.
	_target_raycast.enabled = true
	_target_raycast.target_position = (
		(listener.global_position - global_position).normalized() * dist_to_player
	)
	_target_raycast.force_raycast_update()

	#  Multi-hit ray march 
	# Walk from emitter → listener, detecting each wall entry.
	var space := get_world_3d().direct_space_state
	var ray_dir := (listener.global_position - global_position).normalized()
	var params := PhysicsRayQueryParameters3D.new()
	params.collision_mask = occlusion_collision_mask
	params.collide_with_areas = false

	# Exclude the listener's CharacterBody3D so the player's own collision
	# shapes aren't detected as walls.
	if ignore_listener_body:
		var body := _find_character_body(listener)
		if body != null:
			params.exclude = [body.get_rid()]

	var march_pos := global_position
	var wall_count := 0
	var prev_wall_count := _last_wall_count
	var lp_cutoff := float(open_lowpass_cutoff)
	var open_hz := float(open_lowpass_cutoff)
	var occl_hz := float(occluded_lowpass_cutoff_minimum)
	var wall_materials : Array[String] = []

	# Cumulative volume reduction from low-frequency blocking per wall.
	var vol_reduction_db := 0.0

	_last_wall_absorptions.clear()
	for _hit_idx in max_occlusion_hits:
		params.from = march_pos
		params.to = listener.global_position
		var result := space.intersect_ray(params)
		if result.is_empty():
			break  # clear line to listener

		var hit_point : Vector3 = result["position"]
		var hit_normal : Vector3 = result["normal"]
		var dist_hit := global_position.distance_to(hit_point)

		# Make sure the hit is between emitter and listener.
		if dist_hit >= dist_to_player:
			break

		wall_count += 1

		# Look for an AcousticBody on the collider to get material data.
		# Uses find_for_collider to also resolve CSG internal StaticBody3D.
		var collider : Node = result["collider"]
		var acoustic_body := AcousticBody.find_for_collider(collider)
		var mat_name := "(fallback)"

		var t_high := fallback_transmission
		var t_low := fallback_transmission
		var absorption_weighted := -1.0

		if acoustic_body != null and acoustic_body.acoustic_material != null:
			var mat := acoustic_body.acoustic_material
			t_high = mat.transmission_high
			t_low = mat.transmission_low
			absorption_weighted = 0.7 * mat.absorption_high + 0.3 * mat.absorption_mid
			# Use the resource name, or the file name, or a fallback.
			if mat.resource_name != "":
				mat_name = mat.resource_name
			elif mat.resource_path != "":
				mat_name = mat.resource_path.get_file().get_basename()
			else:
				mat_name = "AcousticMaterial"

		wall_materials.append(mat_name)

		# Store absorption for debug overlay
		if absorption_weighted >= 0.0:
			_last_wall_absorptions.append(clampf(absorption_weighted, 0.0, 1.0))
		else:
			_last_wall_absorptions.append(-1.0)

		# Use weighted absorption to interpolate cutoff for this wall.
		# 0 absorption = open_hz (no muffling), 1 absorption = occl_hz (max muffling)
		if absorption_weighted >= 0.0:
			var interp := clampf(absorption_weighted, 0.0, 1.0)
			var wall_cutoff := open_hz - interp * (open_hz - occl_hz)
			lp_cutoff *= wall_cutoff / open_hz
		else:
			# Fallback: use transmission_high as before
			lp_cutoff *= clampf(t_high, 0.001, 1.0)

		# Low-frequency blocking contributes a volume reduction.
		# Convert transmission fraction to dB loss per wall, scaled by strength.
		# Raw: -20*log10(0.03) ≈ 30 dB — far too aggressive unscaled.
		var raw_db := -20.0 * log(maxf(t_low, 0.001)) / log(10.0)
		vol_reduction_db += raw_db * occlusion_volume_strength

		# Advance past the wall.
		march_pos = hit_point + ray_dir * 0.02

	_last_wall_count = wall_count
	_last_wall_absorptions.clear()
	_last_wall_materials = wall_materials

	# Emit occlusion signals when wall count or cutoff changes
	if wall_count != prev_wall_count:
		emit_signal("occlusion_changed", wall_count, _target_lowpass_cutoff)
		if wall_count > 0 and prev_wall_count == 0:
			emit_signal("audio_occluded", listener, wall_count)
		elif wall_count == 0 and prev_wall_count > 0:
			emit_signal("audio_unoccluded", listener)

	if wall_count == 0:
		_target_lowpass_cutoff = open_hz
		return

	# Clamp so combined cutoff never drops below the minimum.
	lp_cutoff = clampf(lp_cutoff, occl_hz, open_hz)

	# Apply volume reduction from low-frequency blocking.
	# Cap at the configured maximum to avoid silence behind many walls.
	vol_reduction_db = minf(vol_reduction_db, max_occlusion_volume_reduction)
	_target_volume_db = maxf(_target_volume_db - vol_reduction_db, minimum_volume_db)

	# Apply occlusion strength.
	# 0–1 : lerp from open toward the computed cutoff.
	# >1  : push past occluded cutoff toward a 20 Hz hard floor.
	var strength_floor := 20.0
	if occlusion_strength <= 1.0:
		_target_lowpass_cutoff = lerpf(open_hz, lp_cutoff, occlusion_strength)
	else:
		var excess := (occlusion_strength - 1.0) / 4.0
		_target_lowpass_cutoff = lerpf(lp_cutoff, strength_floor, excess)
#endregion

#region DEBUG OVERLAY
func _ensure_shared_debug_container() -> void:
	## Creates the shared debug container used by all instances.
	## In the editor the overlay is parented to the 3D viewport's SubViewport
	## so it stays confined to the 3D view.  At runtime a CanvasLayer is used
	## so the overlay renders on top of all game content.
	if Engine.is_editor_hint():
		# In-editor: skip CanvasLayer — add directly to the 3D SubViewport.
		if _debug_shared_scroll != null and is_instance_valid(_debug_shared_scroll):
			return

		_debug_shared_scroll = ScrollContainer.new()
		_debug_shared_scroll.name = "DebugScroll"
		_debug_shared_scroll.anchor_left = 0.0
		_debug_shared_scroll.anchor_top = 0.0
		_debug_shared_scroll.anchor_right = 0.0
		_debug_shared_scroll.anchor_bottom = 1.0
		_debug_shared_scroll.offset_left = 8.0
		_debug_shared_scroll.offset_top = 8.0
		_debug_shared_scroll.offset_right = 460.0
		_debug_shared_scroll.offset_bottom = -8.0
		_debug_shared_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_debug_shared_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE

		_debug_shared_vbox = VBoxContainer.new()
		_debug_shared_vbox.name = "SourceList"
		_debug_shared_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_debug_shared_vbox.add_theme_constant_override("separation", 6)

		_debug_shared_scroll.add_child(_debug_shared_vbox)
		get_viewport().add_child(_debug_shared_scroll)
	else:
		# Runtime: use a CanvasLayer on the root so it renders above game UI.
		if _debug_shared_layer != null and is_instance_valid(_debug_shared_layer):
			return

		_debug_shared_layer = CanvasLayer.new()
		_debug_shared_layer.name = "SpatialAudioDebugOverlay"
		_debug_shared_layer.layer = 100

		_debug_shared_scroll = ScrollContainer.new()
		_debug_shared_scroll.name = "DebugScroll"
		_debug_shared_scroll.anchor_left = 0.0
		_debug_shared_scroll.anchor_top = 0.0
		_debug_shared_scroll.anchor_right = 0.0
		_debug_shared_scroll.anchor_bottom = 1.0
		_debug_shared_scroll.offset_left = 8.0
		_debug_shared_scroll.offset_top = 8.0
		_debug_shared_scroll.offset_right = 460.0
		_debug_shared_scroll.offset_bottom = -8.0
		_debug_shared_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

		_debug_shared_vbox = VBoxContainer.new()
		_debug_shared_vbox.name = "SourceList"
		_debug_shared_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_debug_shared_vbox.add_theme_constant_override("separation", 6)

		_debug_shared_scroll.add_child(_debug_shared_vbox)
		_debug_shared_layer.add_child(_debug_shared_scroll)
		get_tree().root.add_child.call_deferred(_debug_shared_layer)


func _setup_debug_overlay() -> void:
	_ensure_shared_debug_container()

	_debug_panel = PanelContainer.new()
	_debug_panel.name = "DebugPanel_%s" % name
	_debug_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.65)
	stylebox.corner_radius_top_left = 6
	stylebox.corner_radius_top_right = 6
	stylebox.corner_radius_bottom_left = 6
	stylebox.corner_radius_bottom_right = 6
	stylebox.content_margin_left = 10.0
	stylebox.content_margin_right = 10.0
	stylebox.content_margin_top = 6.0
	stylebox.content_margin_bottom = 6.0
	_debug_panel.add_theme_stylebox_override("panel", stylebox)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.name = "OuterVBox"

	# Header bar with minimize button and title.
	var header := HBoxContainer.new()
	header.name = "Header"

	_debug_minimize_btn = Button.new()
	_debug_minimize_btn.name = "MinBtn"
	_debug_minimize_btn.text = "▼"
	_debug_minimize_btn.flat = true
	_debug_minimize_btn.custom_minimum_size = Vector2(20, 20)
	_debug_minimize_btn.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	_debug_minimize_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	_debug_minimize_btn.add_theme_font_size_override("font_size", 13)
	_debug_minimize_btn.pressed.connect(_on_debug_minimize_toggled)
	header.add_child(_debug_minimize_btn)

	_debug_header_label = RichTextLabel.new()
	_debug_header_label.name = "HeaderLabel"
	_debug_header_label.bbcode_enabled = true
	_debug_header_label.fit_content = true
	_debug_header_label.scroll_active = false
	_debug_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debug_header_label.add_theme_font_size_override("normal_font_size", 13)
	_debug_header_label.add_theme_font_size_override("bold_font_size", 14)
	_debug_header_label.add_theme_color_override("default_color", Color.WHITE)
	header.add_child(_debug_header_label)

	outer_vbox.add_child(header)

	# Content area (hidden when minimized).
	_debug_content_vbox = VBoxContainer.new()
	_debug_content_vbox.name = "Content"

	# Main info label
	_debug_overlay_label = RichTextLabel.new()
	_debug_overlay_label.name = "Label"
	_debug_overlay_label.bbcode_enabled = true
	_debug_overlay_label.fit_content = true
	_debug_overlay_label.custom_minimum_size = Vector2(420, 0)
	_debug_overlay_label.scroll_active = false
	_debug_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_overlay_label.add_theme_font_size_override("normal_font_size", 13)
	_debug_overlay_label.add_theme_font_size_override("bold_font_size", 14)
	_debug_overlay_label.add_theme_color_override("default_color", Color.WHITE)
	_debug_content_vbox.add_child(_debug_overlay_label)

	# Collapsible ray list toggle button
	_debug_rays_toggle = Button.new()
	_debug_rays_toggle.name = "RaysToggle"
	_debug_rays_toggle.text = "▶ Rays"
	_debug_rays_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_debug_rays_toggle.flat = true
	_debug_rays_toggle.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	_debug_rays_toggle.add_theme_color_override("font_hover_color", Color.WHITE)
	_debug_rays_toggle.add_theme_font_size_override("font_size", 13)
	_debug_rays_toggle.pressed.connect(_on_rays_toggle_pressed)
	_debug_content_vbox.add_child(_debug_rays_toggle)

	# Scrollable container for ray distances
	_debug_rays_scroll = ScrollContainer.new()
	_debug_rays_scroll.name = "RaysScroll"
	_debug_rays_scroll.custom_minimum_size = Vector2(420, 0)
	_debug_rays_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_debug_rays_scroll.visible = false  # collapsed by default

	_debug_rays_label = RichTextLabel.new()
	_debug_rays_label.name = "RaysLabel"
	_debug_rays_label.bbcode_enabled = true
	_debug_rays_label.fit_content = true
	_debug_rays_label.custom_minimum_size = Vector2(420, 0)
	_debug_rays_label.scroll_active = false
	_debug_rays_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_debug_rays_label.add_theme_font_size_override("normal_font_size", 13)
	_debug_rays_label.add_theme_color_override("default_color", Color.WHITE)
	_debug_rays_label.meta_clicked.connect(_on_ray_meta_clicked)

	_debug_rays_scroll.add_child(_debug_rays_label)
	_debug_content_vbox.add_child(_debug_rays_scroll)

	# Collapsible navigation/proxy diagnostics (only shown while in proxy mode).
	_debug_navigation_toggle = Button.new()
	_debug_navigation_toggle.name = "NavigationToggle"
	_debug_navigation_toggle.text = "▶ Navigation"
	_debug_navigation_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_debug_navigation_toggle.flat = true
	_debug_navigation_toggle.visible = false
	_debug_navigation_toggle.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	_debug_navigation_toggle.add_theme_color_override("font_hover_color", Color.WHITE)
	_debug_navigation_toggle.add_theme_font_size_override("font_size", 13)
	_debug_navigation_toggle.pressed.connect(_on_navigation_toggle_pressed)
	_debug_content_vbox.add_child(_debug_navigation_toggle)

	_debug_navigation_scroll = ScrollContainer.new()
	_debug_navigation_scroll.name = "NavigationScroll"
	_debug_navigation_scroll.custom_minimum_size = Vector2(420, 0)
	_debug_navigation_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_debug_navigation_scroll.visible = false

	_debug_navigation_label = RichTextLabel.new()
	_debug_navigation_label.name = "NavigationLabel"
	_debug_navigation_label.bbcode_enabled = true
	_debug_navigation_label.fit_content = true
	_debug_navigation_label.custom_minimum_size = Vector2(420, 0)
	_debug_navigation_label.scroll_active = false
	_debug_navigation_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_navigation_label.add_theme_font_size_override("normal_font_size", 13)
	_debug_navigation_label.add_theme_color_override("default_color", Color.WHITE)

	_debug_navigation_scroll.add_child(_debug_navigation_label)
	_debug_content_vbox.add_child(_debug_navigation_scroll)

	outer_vbox.add_child(_debug_content_vbox)
	_debug_panel.add_child(outer_vbox)
	_debug_shared_vbox.add_child(_debug_panel)

	# Connector line (on the shared container, outside the scroll).
	_debug_connector_line = Line2D.new()
	_debug_connector_line.name = "Connector_%s" % name
	_debug_connector_line.width = 1.5
	_debug_connector_line.default_color = Color.WHITE
	_debug_connector_line.z_index = -1
	if Engine.is_editor_hint():
		# In the editor there's no CanvasLayer — parent to the viewport.
		get_viewport().add_child(_debug_connector_line)
	else:
		_debug_shared_layer.add_child(_debug_connector_line)
	_refresh_navigation_debug_visibility()


func _on_debug_minimize_toggled() -> void:
	_debug_minimized = not _debug_minimized
	if _debug_content_vbox != null:
		_debug_content_vbox.visible = not _debug_minimized
	if _debug_minimize_btn != null:
		_debug_minimize_btn.text = "▶" if _debug_minimized else "▼"

	# Emit debug overlay visibility toggle
	if _debug_content_vbox != null:
		emit_signal("debug_overlay_toggled", _debug_content_vbox.visible)


func _on_rays_toggle_pressed() -> void:
	_debug_rays_expanded = not _debug_rays_expanded
	_debug_rays_scroll.visible = _debug_rays_expanded
	if _debug_rays_toggle != null:
		var omni_count := maxi(_ray_names.size() - 1, 0)
		var arrow := "▼" if _debug_rays_expanded else "▶"
		_debug_rays_toggle.text = "%s Rays (%d)" % [arrow, omni_count]


func _on_navigation_toggle_pressed() -> void:
	_debug_navigation_expanded = not _debug_navigation_expanded
	_refresh_navigation_debug_visibility()


func _refresh_navigation_debug_visibility() -> void:
	if _debug_navigation_toggle == null or _debug_navigation_scroll == null:
		return
	var visible := _external_navigation_debug_active
	_debug_navigation_toggle.visible = visible
	_debug_navigation_scroll.visible = visible and _debug_navigation_expanded
	if _debug_navigation_toggle.visible:
		var arrow := "▼" if _debug_navigation_expanded else "▶"
		_debug_navigation_toggle.text = "%s Navigation" % arrow


func _format_navigation_debug_text() -> String:
	if not _external_navigation_debug_active:
		return ""
	var d := _external_navigation_debug
	var profile := str(d.get("profile", ""))
	var node_name := str(d.get("agent_name", ""))
	var path_points := int(d.get("path_points", 0))
	var graph_points := int(d.get("graph_points", 0))
	var graph_edges := int(d.get("graph_edges", 0))
	var path_len := float(d.get("path_length", 0.0))
	var direct_len := float(d.get("direct_distance", 0.0))
	var detour_ratio := float(d.get("detour_ratio", 1.0))
	var proxy_to_listener := float(d.get("proxy_to_listener", 0.0))
	var proxy_to_origin := float(d.get("proxy_to_origin", 0.0))
	var target_delta := float(d.get("proxy_to_target", 0.0))
	var in_backoff := bool(d.get("proxy_backoff_active", false))
	var spring_active := bool(d.get("spring_arm_active", false))
	var spring_from_end := float(d.get("spring_arm_distance_from_end", 0.0))
	var waypoint_idx := int(d.get("proxy_waypoint_index", 0))
	var update_hz := float(d.get("update_hz", 0.0))

	var txt := ""
	txt += "Agent           [color=white]%s[/color]\n" % node_name
	txt += "Profile         [color=yellow]%s[/color]\n" % profile
	txt += "Path            [color=yellow]%d pts[/color]  len: %.2f m  direct: %.2f m  ratio: %.2f\n" % [path_points, path_len, direct_len, detour_ratio]
	txt += "Graph           [color=yellow]%d pts[/color]  %d edges\n" % [graph_points, graph_edges]
	txt += "Proxy           waypoint: %d  to listener: %.2f m  to origin: %.2f m\n" % [waypoint_idx, proxy_to_listener, proxy_to_origin]
	txt += "Proxy target    delta: %.2f m  backoff: %s  spring: %s\n" % [target_delta, "ON" if in_backoff else "OFF", "ON" if spring_active else "OFF"]
	if spring_active:
		txt += "Spring dist     %.2f m from path end\n" % spring_from_end
	txt += "Solve rate      %.2f Hz\n" % update_hz
	return txt


func _on_ray_meta_clicked(meta: Variant) -> void:
	var key := str(meta)
	if key.begins_with("ray_"):
		var idx := key.substr(4).to_int()
		if not (_debug_ray_reflections_expanded is Dictionary):
			_debug_ray_reflections_expanded = {}
		_debug_ray_reflections_expanded[idx] = not _debug_ray_reflections_expanded.get(idx, false)


func _print_debug(listener: Node3D) -> void:
	if not is_instance_valid(_debug_panel):
		_setup_debug_overlay()

	_debug_panel.visible = true

	# Emit a compact debug dictionary for external tooling when requested
	var info := {
		"distance": listener.global_position.distance_to(global_position),
		"volume_db_target": _target_volume_db,
		"lowpass_cutoff": _target_lowpass_cutoff,
		"reverb_room_size": _target_reverb_room_size,
		"reverb_wetness": _target_reverb_wetness,
		"reverb_damping": _target_reverb_damping,
		"wall_count": _last_wall_count,
		"navigation_proxy_active": _external_navigation_debug_active,
	}
	if _external_navigation_debug_active:
		info["navigation"] = _external_navigation_debug
	emit_signal("spatial_audio_debug", info)

	var effective_max_dist := max_distance if max_distance > 0.0 else max_raycast_distance
	var dist_to_listener := listener.global_position.distance_to(global_position)

	# Update header (always visible, even when minimized).
	var fps := Engine.get_frames_per_second()
	var frame_time_ms := 1000.0 / maxf(fps, 1.0)
	var fps_col := "green" if fps >= 60 else ("yellow" if fps >= 30 else "red")
	var header_text := "[b][color=cyan]SpatialAudio[/color]  [color=white]%s[/color][/b]" % name
	if not _debug_minimized:
		header_text += "  [color=%s]%d FPS[/color]  [color=gray](%.1f ms)[/color]" % [fps_col, fps, frame_time_ms]
	if _debug_header_label != null:
		_debug_header_label.text = header_text

	if _debug_minimized:
		return

	# Occlusion info
	var is_occluded := _last_wall_count > 0

	# Current effect values (what the bus is actually using right now)
	var cur_lowpass_hz := _lowpass_filter.cutoff_hz if _lowpass_filter != null else -1.0
	var cur_reverb_wet := _reverb_effect.wet if _reverb_effect != null else -1.0
	var cur_reverb_room := _reverb_effect.room_size if _reverb_effect != null else -1.0
	var cur_reverb_damp := _reverb_effect.damping if _reverb_effect != null else -1.0

	# Build BBCode text (header is separate, content starts from separator).
	var t := "[color=gray][/color]\n"
	t += "Listener dist   [color=yellow]%.2f m[/color]  (max: %.1f m)\n" % [dist_to_listener, effective_max_dist]

	if enable_volume_attenuation:
		var outer_r := inner_radius + falloff_distance
		var zone := "INNER" if dist_to_listener <= inner_radius else ("FALLOFF" if dist_to_listener < outer_r else "OUTSIDE")
		var zone_col := "green" if zone == "INNER" else ("yellow" if zone == "FALLOFF" else "red")
		t += "Attenuation     [color=cyan]%.1f m[/color] / [color=orange]%.1f m[/color]  zone: [color=%s]%s[/color]\n" % [inner_radius, outer_r, zone_col, zone]
		t += "Atten. func     %s\n" % AttenuationFunction.keys()[attenuation_function]
		if not is_equal_approx(inner_radius_panning_strength, 1.0):
			t += "Panning         [color=yellow]%.2f[/color]  → %.2f  (inner: x%.2f)\n" % [panning_strength, _target_panning_strength, inner_radius_panning_strength]

	if enable_air_absorption:
		var combined := minf(_target_lowpass_cutoff, _target_air_absorption_cutoff)
		t += "Air absorption  [color=yellow]%.0f Hz[/color]  → %.0f Hz  (%.0f–%.0f m)\n" % [_target_air_absorption_cutoff, combined, air_absorption_min_distance, air_absorption_max_distance]

	if is_occluded:
		var walls_str := ", ".join(_last_wall_materials) if _last_wall_materials.size() > 0 else ""
		t += "Occluded        [color=red]YES[/color]  (%d wall%s)\n" % [_last_wall_count, "s" if _last_wall_count != 1 else ""]
		if walls_str != "":
			t += "  Materials     [color=gray]%s[/color]\n" % walls_str
	else:
		t += "Occluded        [color=green]NO[/color]\n"

	t += "Lowpass cutoff  [color=yellow]%.0f Hz[/color]  → %.0f Hz\n" % [cur_lowpass_hz, _target_lowpass_cutoff]
	t += "Reverb wet      [color=yellow]%.3f[/color]  → %.3f  (max: %.2f)\n" % [cur_reverb_wet, _target_reverb_wetness, max_reverb_wetness]
	t += "Reverb room     [color=yellow]%.3f[/color]  → %.3f\n" % [cur_reverb_room, _target_reverb_room_size]
	t += "Reverb damp     [color=yellow]%.3f[/color]  → %.3f\n" % [cur_reverb_damp, _target_reverb_damping]

	# Surface absorption summary
	if surface_absorption:
		var valid_abs := []
		for a in _last_wall_absorptions:
			if typeof(a) == TYPE_FLOAT and a >= 0.0:
				valid_abs.append(a)
		# Avg absorption for surfaces
		var _abs_sum := 0.0
		var _abs_count := 0
		for i in range(_ray_absorptions.size()):
			if _ray_absorptions[i] >= 0.0:
				_abs_sum += _ray_absorptions[i]
				_abs_count += 1
		var avg_abs := _abs_sum / float(maxi(_abs_count, 1))
		t += "Avg absorption  [color=yellow]%.2f[/color]  (%d surfaces)\n" % [avg_abs, _abs_count]

	var openness_pct := _openness * 100.0
	var env_label := "OUTDOOR" if _openness > 0.5 else ("SEMI-OPEN" if _openness > 0.1 else "INDOOR")
	var env_col := "cyan" if _openness > 0.5 else ("yellow" if _openness > 0.1 else "green")
	t += "Openness        [color=%s]%.0f%% %s[/color]\n" % [env_col, openness_pct, env_label]
	if ignore_floor:
		t += "Floor ignore    [color=green]ON[/color]  (" + String.num(floor_angle_threshold, 0) + " deg)\n"

	# Estimated room size from average hit distances (excluding escaped + floor-ignored + Target).
	var _hit_sum := 0.0
	var _hit_count := 0
	var _floor_cos := cos(deg_to_rad(floor_angle_threshold))
	for i in range(_distances.size() - 1):  # skip last entry (Target ray)
		if ignore_floor and i < _ray_directions.size() and _ray_directions[i].y <= -_floor_cos:
			continue
		var ray_escaped := i < _reflection_escaped.size() and _reflection_escaped[i]
		if not ray_escaped and _distances[i] > 0.0:
			_hit_sum += _distances[i]
			_hit_count += 1
	var avg_dist := _hit_sum / float(maxi(_hit_count, 1))
	t += "Est. room size  [color=yellow]~%.1f m[/color]  (avg of %d hits)\n" % [avg_dist * 2.0, _hit_count]

	t += "Volume          [color=yellow]%.1f dB[/color]  → %.1f dB\n" % [volume_db, _target_volume_db]
	t += "Effects         %s  (global off: %s)\n" % [
		"[color=green]ON[/color]" if effects_enabled else "[color=red]OFF[/color]",
		"[color=red]YES[/color]" if global_effects_disabled else "[color=green]NO[/color]"
	]
	t += "Bus             %s (idx %d)\n" % [_bus_name, _bus_idx]

	var key_name := OS.get_keycode_string(debug_toggle_effects_key)
	var shapes_key_name := OS.get_keycode_string(debug_toggle_shapes_key)
	t += "[color=gray]Press [color=white][b]%s[/b][/color] to toggle effects  |  [color=white][b]%s[/b][/color] to toggle shapes[/color]\n" % [key_name, shapes_key_name]

	t += "Ray mode        %s  (%d omni rays)\n" % [
		RayDistribution.keys()[ray_distribution],
		_ray_names.size() - 1  # exclude Target
	]

	_debug_overlay_label.text = t
	_refresh_navigation_debug_visibility()
	if _external_navigation_debug_active and _debug_navigation_label != null:
		_debug_navigation_label.text = _format_navigation_debug_text()
	elif _debug_navigation_label != null:
		_debug_navigation_label.text = ""

	# Update the toggle button text
	if _debug_rays_toggle != null:
		var omni_count := maxi(_ray_names.size() - 1, 0)
		var arrow := "▼" if _debug_rays_expanded else "▶"
		_debug_rays_toggle.text = "%s Rays (%d)" % [arrow, omni_count]

	# Update the ray list content (even when collapsed, so it's ready)
	if _debug_rays_label != null:
		var max_scroll_h := 200.0  # cap the scroll area height
		var r := ""
		var floor_cos := cos(deg_to_rad(floor_angle_threshold))
		for i in range(_distances.size()):
			var ray_name : String = _ray_names[i] if i < _ray_names.size() else "?"
			var has_reflections := (i < _reflection_paths.size() and _reflection_paths[i].size() > 2)
			var escaped := (i < _reflection_escaped.size() and _reflection_escaped[i])
			var d_str : String
			var is_floor_ignored := ignore_floor and i < _ray_directions.size() and _ray_directions[i].y <= -floor_cos

			# Material tag for this ray (only for omni rays, not Target).
			var mat_tag := ""
			if surface_absorption and i < _ray_material_names.size() and _ray_material_names[i] != "":
				var abs_val := _ray_absorptions[i] if i < _ray_absorptions.size() else -1.0
				if abs_val >= 0.0:
					mat_tag = "  [color=gray]%s (abs: %.2f)[/color]" % [_ray_material_names[i], abs_val]
				else:
					mat_tag = "  [color=gray]%s[/color]" % _ray_material_names[i]

			if is_floor_ignored:
				d_str = "(floor)"
			elif escaped and not has_reflections:
				d_str = "∞ (open)"
			elif _distances[i] > 0.0:
				d_str = "%.1fm" % _distances[i]
			else:
				d_str = "--"
			if has_reflections:
				if not (_debug_ray_reflections_expanded is Dictionary):
					_debug_ray_reflections_expanded = {}
				var is_expanded : bool = _debug_ray_reflections_expanded.get(i, false)
				var arrow := "▼" if is_expanded else "▶"
				var ref_count : int = _reflection_paths[i].size() - 2  # segments beyond the first
				if escaped:
					ref_count -= 1  # last segment is the escape, don't count it as a real reflection
				var esc_tag := "  [color=red](escaped)[/color]" if escaped else ""
				r += "[url=ray_%d]%s[/url] %-11s %s  [color=gray](%d refl)%s[/color]%s\n" % [i, arrow, ray_name, d_str, ref_count, esc_tag, mat_tag]
				if is_expanded:
					var path : Array = _reflection_paths[i]
					for seg in range(path.size() - 1):
						var seg_dist := (path[seg] as Vector3).distance_to(path[seg + 1] as Vector3)
						var is_escape := (escaped and seg == path.size() - 2)
						if seg == 0:
							r += "    [color=#3388ff]● seg %d[/color]  [color=yellow]%.1fm[/color]\n" % [seg, seg_dist]
						elif is_escape:
							r += "    [color=red]● seg %d  %.1fm (escaped)[/color]\n" % [seg, seg_dist]
						else:
							r += "    [color=#b34dff]● seg %d[/color]  [color=yellow]%.1fm[/color]\n" % [seg, seg_dist]
			else:
				if is_floor_ignored:
					r += "  %-14s [color=gray]%s[/color]%s\n" % [ray_name, d_str, mat_tag]
				elif escaped:
					r += "  %-14s [color=red]%s[/color]%s\n" % [ray_name, d_str, mat_tag]
				else:
					r += "  %-14s %s%s\n" % [ray_name, d_str, mat_tag]
		_debug_rays_label.text = r

	# Clamp scroll container height so it doesn't grow unbounded
	if _debug_rays_expanded and _debug_rays_label != null and _debug_rays_scroll != null:
		await get_tree().process_frame
		if _debug_rays_label != null and _debug_rays_scroll != null:
			var content_h := _debug_rays_label.get_combined_minimum_size().y
			var max_scroll_h := 200.0
			_debug_rays_scroll.custom_minimum_size.y = minf(content_h, max_scroll_h)
			_debug_rays_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if content_h > max_scroll_h else ScrollContainer.SCROLL_MODE_DISABLED
	if _external_navigation_debug_active and _debug_navigation_expanded and _debug_navigation_label != null and _debug_navigation_scroll != null:
		await get_tree().process_frame
		if _debug_navigation_label != null and _debug_navigation_scroll != null:
			var nav_h := _debug_navigation_label.get_combined_minimum_size().y
			var max_nav_h := 160.0
			_debug_navigation_scroll.custom_minimum_size.y = minf(nav_h, max_nav_h)
			_debug_navigation_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if nav_h > max_nav_h else ScrollContainer.SCROLL_MODE_DISABLED
#endregion

#region DEBUG DRAWING

func _update_debug_connector_line() -> void:
	## Draws a 2D line from the debug overlay panel to the audio source's
	## screen-projected position. Runs every frame for smooth tracking.
	if _debug_connector_line == null or _debug_panel == null:
		return
	if not _debug_panel.visible:
		_debug_connector_line.visible = false
		return
	if Engine.is_editor_hint():
		_debug_connector_line.visible = false
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(global_position):
		_debug_connector_line.visible = false
		return

	var screen_pos := camera.unproject_position(global_position)
	# Anchor from the right edge, vertically centred on the panel.
	var panel_rect := _debug_panel.get_global_rect()
	var panel_anchor := Vector2(
		panel_rect.position.x + panel_rect.size.x,
		panel_rect.position.y + panel_rect.size.y * 0.5
	)
	_debug_connector_line.clear_points()
	_debug_connector_line.add_point(panel_anchor)
	_debug_connector_line.add_point(screen_pos)
	_debug_connector_line.visible = true


func _setup_debug_mesh() -> void:
	_debug_immediate = ImmediateMesh.new()
	_debug_instance = MeshInstance3D.new()
	_debug_instance.name = "AudioDebug"
	_debug_instance.mesh = _debug_immediate
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_instance.material_override = mat
	add_child(_debug_instance)


func _draw_debug_shapes(editor_selected: bool = false) -> void:
	if _debug_immediate == null:
		_setup_debug_mesh()

	_debug_immediate.clear_surfaces()
	_debug_immediate.surface_begin(Mesh.PRIMITIVE_LINES)

	if debug_draw_rays or editor_selected:
		_draw_debug_rays()

	# Inner / outer radius wireframe spheres.
	# Always shown when selected in the editor; at runtime, gated by the
	# debug_draw_radius export and hidden when attenuation is off or effects
	# have been toggled off via the debug key.
	var show_radius := editor_selected or (debug_draw_radius and not global_effects_disabled)
	if show_radius and enable_volume_attenuation:
		if inner_radius > 0.0:
			_draw_wireframe_sphere(Vector3.ZERO, inner_radius, Color(0.0, 1.0, 1.0, 0.5))
		var outer := inner_radius + falloff_distance
		_draw_wireframe_sphere(Vector3.ZERO, outer, Color(1.0, 0.55, 0.0, 0.45))

	# Playing-state indicator sphere — scales with camera distance so it
	# stays visible at long range.
	# Yellow = sound is still traveling (delay pending),
	# Green = perceived play duration (stream length from call),
	# Red = idle / finished.
	if debug_draw_playing_state or editor_selected:
		var state_color : Color
		if _pending_delay_timer != null:
			state_color = Color.YELLOW
		elif playing:
			state_color = Color.GREEN
		else:
			state_color = Color.RED
		var cam := _get_listener()
		var indicator_radius := 0.15
		if cam != null:
			var dist := global_position.distance_to(cam.global_position)
			indicator_radius = maxf(0.15, dist * 0.02)
		_draw_wireframe_sphere(Vector3.ZERO, indicator_radius, state_color, 16)

	_debug_immediate.surface_end()


func _draw_debug_rays() -> void:
	# Omni rays (blue) + reflection bounces (purple).
	for i in range(_raycasts.size()):
		var ray : RayCast3D = _raycasts[i]
		if ray == null or ray == _target_raycast:
			continue

		# Check if this ray has stored reflection path segments.
		if i < _reflection_paths.size() and _reflection_paths[i].size() >= 2:
			var path : Array = _reflection_paths[i]
			var escaped : bool = i < _reflection_escaped.size() and _reflection_escaped[i]
			for seg in range(path.size() - 1):
				var start := to_local(path[seg])
				var end := to_local(path[seg + 1])
				var col : Color
				if escaped and seg == path.size() - 2:
					# Last segment escaped (no hit) — red.
					col = Color(1.0, 0.15, 0.15, 0.7)
				elif seg == 0:
					col = Color(0.2, 0.5, 1.0, 0.7) # blue — first segment
				else:
					col = Color(0.7, 0.3, 1.0, 0.6) # purple — bounce
				_debug_immediate.surface_set_color(col)
				_debug_immediate.surface_add_vertex(start)
				_debug_immediate.surface_set_color(col)
				_debug_immediate.surface_add_vertex(end)
		else:
			# No reflections — draw the single ray segment.
			var world_dir := (ray.global_transform.basis * ray.target_position).normalized()
			var draw_len : float
			if i < _distances.size() and _distances[i] > 0.0:
				draw_len = minf(_distances[i], max_raycast_distance)
			else:
				draw_len = max_raycast_distance
			var start := to_local(ray.global_position)
			var end   := to_local(ray.global_position + world_dir * draw_len)
			var escaped : bool = i < _reflection_escaped.size() and _reflection_escaped[i]
			var col := Color(1.0, 0.15, 0.15, 0.7) if escaped else Color(0.2, 0.5, 1.0, 0.7)
			_debug_immediate.surface_set_color(col)
			_debug_immediate.surface_add_vertex(start)
			_debug_immediate.surface_set_color(col)
			_debug_immediate.surface_add_vertex(end)

	# Target ray (green = clear, red = occluded).
	# Direction is computed live every frame from the current listener position
	# so the line always tracks the camera regardless of update_frequency.
	var listener := _get_listener()
	if _target_raycast != null and listener != null:
		var to_listener := listener.global_position - global_position
		var dist_to_listener := to_listener.length()
		var t_max : float
		if enable_volume_attenuation:
			t_max = inner_radius + falloff_distance
		else:
			t_max = max_raycast_distance
		var t_len := minf(dist_to_listener, t_max)
		var t_dir := to_listener.normalized() if dist_to_listener > 0.0 else Vector3.FORWARD
		var t_start := to_local(global_position)
		var t_end   := to_local(global_position + t_dir * t_len)
		var tc := Color.GREEN
		if _target_raycast.is_colliding():
			var dist_to_wall := global_position.distance_to(
				_target_raycast.get_collision_point()
			)
			if dist_to_wall < t_len:
				tc = Color.RED
				# Cap the line at the collision point.
				t_end = to_local(global_position + t_dir * dist_to_wall)
		_debug_immediate.surface_set_color(tc)
		_debug_immediate.surface_add_vertex(t_start)
		_debug_immediate.surface_set_color(tc)
		_debug_immediate.surface_add_vertex(t_end)




func _draw_wireframe_sphere(center: Vector3, radius: float, color: Color, segments: int = 64) -> void:
	## Draws three orthogonal circles (XZ, XY, YZ) to approximate a wireframe sphere.
	for plane in 3:
		for i in segments:
			var a0 := (float(i) / float(segments)) * TAU
			var a1 := (float(i + 1) / float(segments)) * TAU
			var p0 : Vector3
			var p1 : Vector3
			match plane:
				0: # XZ (horizontal)
					p0 = center + Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
					p1 = center + Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
				1: # XY (front)
					p0 = center + Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
					p1 = center + Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
				2: # YZ (side)
					p0 = center + Vector3(0.0, cos(a0) * radius, sin(a0) * radius)
					p1 = center + Vector3(0.0, cos(a1) * radius, sin(a1) * radius)
			_debug_immediate.surface_set_color(color)
			_debug_immediate.surface_add_vertex(p0)
			_debug_immediate.surface_set_color(color)
			_debug_immediate.surface_add_vertex(p1)
#endregion
