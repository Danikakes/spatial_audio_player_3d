# Installation

## From the Godot Asset Library

1. Open your project in Godot.
2. Go to **AssetLib** (top centre tab).
3. Search for **Spatial Audio Extended**.
4. Click **Download** → **Install**.
5. In **Project → Project Settings → Plugins**, find **Spatial Audio Extended** and set it to **Enabled**.

## Manual Installation

1. Download or clone this repository.
2. Copy the `addons/spatial_audio_extended/` folder into your project's `addons/` directory.

 ```
 your_project/
 └── addons/
 └── spatial_audio_extended/
 ├── plugin.cfg
 ├── plugin.gd
 ├── spatial_audio_player_3d.gd
 ├── spatial_reflection_navigation_agent_3d.gd
 ├── acoustic_body.gd
 ├── acoustic_material.gd
 ├── presets/
 │ ├── brick.tres
 │ ├── carpet.tres
 │ └── … (12 presets total)
 └── *.svg (editor icons)
 ```

3. In Godot, go to **Project → Project Settings → Plugins**.
4. Find **Spatial Audio Extended** and toggle it to **Enabled**.

## Verifying the Install

After enabling the plugin you should see:

- `SpatialAudioPlayer3D` available in the **Add Node** dialog (under Node3D → AudioStreamPlayer3D).
- `SpatialReflectionNavigationAgent3D` available in the **Add Node** dialog.
- `AcousticBody` available in the **Add Node** dialog (under Node).
- A new **"Add AcousticBody"** button appearing in the Inspector when a `CollisionShape3D` or `CSGShape3D` is selected.

> **Tip:** If the node types aren't appearing, try reloading the project (**Project → Reload Current Project**).
