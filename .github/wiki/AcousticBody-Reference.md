# AcousticBody Reference

`AcousticBody` is a helper node you attach as a **direct child** of any collision object or CSG shape to give that surface acoustic properties. When `SpatialAudioPlayer3D` traces a ray that hits the parent body, it looks for an `AcousticBody` to retrieve the `AcousticMaterial`.

**Class:** `AcousticBody` 
**Inherits:** `Node` 
**Script:** `acoustic_body.gd`

---

## Supported Parent Nodes

| Parent Type | Notes |
|---|---|
| `StaticBody3D` | Standard use — walls, floors, ceilings, props |
| `RigidBody3D` | Dynamic/movable objects (crates, doors, debris) |
| `CharacterBody3D` | Player or NPC bodies (rare but possible) |
| `Area3D` | Trigger volumes that affect sound |
| `CSGShape3D` | CSG-based geometry (CSGBox3D, CSGSphere3D, etc.) — requires `use_collision = true` |

> **Important:** `AcousticBody` must be a **direct child** of the collision object or CSG shape. It is not detected if placed deeper in the hierarchy.

---

## Exported Properties

| Property | Type | Description |
|---|---|---|
| `acoustic_material` | `AcousticMaterial` | The acoustic material that defines how this surface absorbs, scatters, and transmits sound. Assign a preset `.tres` or create a custom resource. |

---

## Scene Tree Examples

```
# Standard wall
StaticBody3D (concrete wall)
├── CollisionShape3D
├── MeshInstance3D
└── AcousticBody ← assign concrete.tres here

# Movable crate
RigidBody3D
├── CollisionShape3D
└── AcousticBody ← assign wood.tres here

# Trigger/reverb zone
Area3D
├── CollisionShape3D
└── AcousticBody ← assign generic.tres or a custom material

# CSG geometry
CSGBox3D (use_collision = true)
└── AcousticBody ← also works on CSG shapes
```

---

## Editor Shortcut

When a `CollisionShape3D` or `CSGShape3D` node is selected in the editor, the plugin adds an **"Add AcousticBody"** button to the Inspector. Click it to automatically add an `AcousticBody` as a sibling without going through the Add Node dialog.

---

## Configuration Warnings

The editor will display warnings in the scene tree if:

- `AcousticBody` is not a direct child of a `CollisionObject3D` or `CSGShape3D`.
- The parent `CSGShape3D` does not have `use_collision` enabled (raycasts won't hit it).
- The parent is a CSG shape inside a `CSGCombiner3D` (may not work correctly).
- Multiple `AcousticBody` nodes are children of the same parent (only the first is used).
- No `acoustic_material` is assigned (the player will use `fallback_transmission` instead).

---

## Static Methods

### `static find_on(node: Node) -> AcousticBody`

Returns the first `AcousticBody` child of `node`, or `null` if none exists. Used internally by `SpatialAudioPlayer3D` to look up surface properties.

### `static find_for_collider(collider: Node) -> AcousticBody`

Resolves the `AcousticBody` for a raycast collider. Checks the collider directly first, then walks up to handle CSG shapes whose internal `StaticBody3D` is what raycasts actually hit.

```gdscript
# Example: manually query a surface's acoustic body
var hit := space.intersect_ray(params)
if not hit.is_empty():
 var body := AcousticBody.find_for_collider(hit["collider"])
 if body and body.acoustic_material:
 print("Surface absorption mid: ", body.acoustic_material.absorption_mid)
```

---

## CSG Gotchas

When you use CSG geometry (`CSGBox3D`, `CSGSphere3D`, etc.) with `use_collision = true`, Godot internally creates a `StaticBody3D` child. Raycasts hit that internal body, not the CSG node itself. `AcousticBody.find_for_collider()` handles this automatically by walking up to the CSG parent — but **only if** the `AcousticBody` is a direct child of the CSG node, not of the internal `StaticBody3D`.

```
CSGBox3D (use_collision = true) ← place AcousticBody here 
├── [internal StaticBody3D] ← NOT here 
└── AcousticBody
```
