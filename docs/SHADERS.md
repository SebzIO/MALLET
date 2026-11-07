# Your own skies and surfaces (shaders)

MALLET can use your own **Godot shaders** for the map's sky and for ramp and block surfaces. You write the shader
once, and MALLET turns its settings into sliders and color pickers, so anyone can tweak it without touching code.

## Where the files go

**View > Your shaders folder…** (or the **Folder…** button next to a shader list) opens the folder. On Windows it's
`%APPDATA%\Godot\app_userdata\MALLET\shaders`. The first time it opens, it already holds two commented examples:

- `example_sky.gdshader`: a gradient sky with drifting clouds and a sun.
- `example_surface.gdshader`: a surface with glowing stripes and an optional image.

Copy one, rename it (the file name is the name MALLET shows), and change it in any text editor. Save it and switch back
to MALLET: it picks up new, changed and deleted files on its own.

## Skies

A file that starts with `shader_type sky;` is a sky. Click empty space to show the Map panel and pick it under
**Sky**. The sky preset, sun, shadow fill and fog settings keep working with your own sky. The built-in sky's colors,
stars, aurora and nebula are hidden while your sky is in use.

- `EYEDIR` is the direction the pixel looks in (`y` is up). Write the color to `COLOR`.
- The sun from the Map panel: `LIGHT0_ENABLED`, `LIGHT0_DIRECTION`, `LIGHT0_COLOR`, `LIGHT0_ENERGY`.
- Using `TIME` animates the sky (MALLET then redraws it every frame).

## Surfaces (ramps and blocks)

A file that starts with `shader_type spatial;` is a surface. Select a ramp or block, set **Look** to
**Your own shader** and pick it under **Shader**.

- Write `ALBEDO`, `ROUGHNESS`, `METALLIC`, `EMISSION` and so on, as in any Godot spatial shader.
- On ramps, `UV.x` goes 0 to 1 across the riding face and `UV.y` is meters along the ramp divided by 20.
  On blocks, UV is meters divided by 4, lined up across neighboring blocks.
- Ramps are seen from both sides: keep `render_mode cull_disabled;`.

## Settings become controls

Every `uniform` becomes a control in the panel, named after the uniform (`cloud_amount` shows as "Cloud amount"):

| In the shader | In the panel |
|---|---|
| `uniform float x : hint_range(0.0, 1.0, 0.01) = 0.5;` | a slider from 0 to 1 |
| `uniform int n : hint_range(1, 9) = 3;` | a slider in whole steps |
| `uniform float x = 2.0;` (no range) | a slider around the default; the number box goes further |
| `uniform vec3 c : source_color = vec3(1.0);` | a color picker (`vec4`: with see-through) |
| `uniform bool on = true;` | a switch |
| `uniform vec2 / vec3 / vec4 v;` (no `source_color`) | number boxes |
| `uniform sampler2D img : source_color;` | Choose image… (the image goes inside the exported map) |

- A comment after the uniform on the same line becomes its tooltip: `uniform float speed = 1.0; // How fast it moves`.
- A uniform whose name starts with `_` gets no control (for values only you should change).
- **Back to the shader's own values** clears the map's settings for that shader.

## When something's wrong

A shader that doesn't compile is never used. The panel shows the line and Godot's message (for example
`Line 12: Unknown identifier in expression: 'colr'`), and until you fix it the map shows the built-in sky, or a plain
color in the Color above. Nothing turns white and nothing crashes. Files with a shader type MALLET doesn't use
(`canvas_item`, `particles`, `fog`) are listed as errors too.

## Sharing and exporting

- **Saved maps** carry the code of the shaders they use, so a map you send someone looks the same on their computer
  (the shader shows as "only in this map" there). If you delete a shader file, the open map keeps its copy.
- **SurfsUp**: the shader goes inside the map, like MALLET's built-in looks (no scripts, which SurfsUp doesn't allow).
- **Counter-Strike: Source** can't run shaders. Export > To Counter-Strike: Source offers **This map's sky (made into
  a skybox)**, picked automatically when you use your own sky: MALLET renders the sky into Source's six skybox images
  and packs them into the map. A surface shader exports as its first chosen image, otherwise its first color.
- Prefabs don't carry shader code: a prefab that uses your shader needs the file on the computer it's used on.

## Learn more

Godot's shader documentation covers the language: docs.godotengine.org, "Shading language", "Sky shaders" and
"Spatial shaders". Most Godot 4 sky and spatial shaders work in MALLET as they are.
