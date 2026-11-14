# Your own skies and surfaces (shaders)

MALLET can use your own **Godot shaders** for the map's sky and for ramp and block surfaces. You write the shader
once, and MALLET turns its settings into sliders and color pickers, so anyone can tweak it without touching code.

## Where the files go

**Options > Your shaders folder…** (or the **Folder…** button next to a shader list) opens the folder. On Windows it's
`%APPDATA%\Godot\app_userdata\MALLET\shaders`. The first time it opens, it already holds two commented examples:

- `example_sky.gdshader`: a gradient sky with drifting clouds and a sun.
- `example_surface.gdshader`: a surface with glowing stripes and an optional image.

Copy one, rename it (the file name is the name MALLET shows), and change it in any text editor. Save it: MALLET
picks up new, changed and deleted files on its own within a couple of seconds, when you switch back to it, and
whenever you open a shader list. The file must end in `.gdshader`: a shader saved as `n64` or `n64.txt` is listed
grayed out with "rename it to n64.gdshader", and a shader type MALLET can't use is listed grayed out with why.

## Skies

A file that starts with `shader_type sky;` is a sky. Click empty space to show the Map panel and pick it under
**Sky**. The sky preset, sun, shadow fill and fog settings keep working with your own sky. The built-in sky's colors,
stars, aurora and nebula are hidden while your sky is in use.

- `EYEDIR` is the direction the pixel looks in (`y` is up). Write the color to `COLOR`.
- The sun from the Map panel: `LIGHT0_ENABLED`, `LIGHT0_DIRECTION`, `LIGHT0_COLOR`, `LIGHT0_ENERGY`.
- Using `TIME` animates the sky (MALLET then redraws it every frame).
- **Every sky keeps its own settings.** Switch to another sky and back, and the first one's settings are still there
  (they're saved with the map, and undo takes a switch back). Back to the shader's own values clears only the sky
  that's showing.

### 2D skies (`shader_type canvas_item;`)

A file that starts with `shader_type canvas_item;` is a sky too: handy for the many 2D shaders on godotshaders.com.
MALLET draws it as a flat picture, 2048 x 1024 pixels, and wraps that picture around the world like a panorama:

- `UV.x` goes once around you: the middle of the picture (`UV.x = 0.5`) faces north (Godot -Z)
  and 0 and 1 meet in the south. `UV.y` goes from straight up (0) to straight down (1); the horizon is at
  `UV.y = 0.5`. Write the color to `COLOR` in `fragment()`, as in any 2D shader.
- `TIME` animates it (redrawn every frame); without `TIME` it's drawn once, and again when you change a setting.
  Its uniforms become controls like any shader's.

Limits:
- It's a flat picture: there's no `EYEDIR` and no sun (`LIGHT0_*`), the picture is squeezed toward straight up and
  straight down, and a picture whose left and right edges don't match shows a seam in the south.
- 2048 x 1024 is the most detail it has; very fine patterns look soft up close.
- **Screen effects aren't skies**: a canvas_item shader that reads the screen (`hint_screen_texture`,
  `SCREEN_TEXTURE`, such as a VHS or blur effect) is listed with an error, because a sky has no screen to read.
- **SurfsUp** gets the picture as it looks when you export (a still picture, so a moving 2D sky stands still in the
  game). Counter-Strike: Source gets it in the baked skybox like any sky.

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
| `uniform ivec2 / ivec3 / ivec4 v;` | number boxes in whole steps |
| `uniform sampler2D img : source_color;` | Choose image… (the image goes inside the exported map) |

- A comment after the uniform on the same line becomes its tooltip: `uniform float speed = 1.0; // How fast it moves`.
- A uniform whose name starts with `_` gets no control (for values only you should change).
- A uniform MALLET has no control for (a matrix, an array, a cubemap or other non-2D texture) is listed under the
  controls as "Not shown", with why, so nothing goes missing without a word.
- **Back to the shader's own values** clears the map's settings for that shader.

## When something's wrong

A shader that doesn't compile is never used. The panel shows the line and Godot's message (for example
`Line 12: Unknown identifier in expression: 'colr'`), and until you fix it the map shows the built-in sky, or a plain
color in the Color above. Nothing turns white and nothing crashes. Files with a shader type MALLET doesn't use
(`particles`, `fog`) and canvas_item screen effects are listed with their reason too.

## Sharing and exporting

- **Saved maps** carry the code of the shaders they use, so a map you send someone looks the same on their computer
  (the shader shows as "only in this map" there). If you delete a shader file, the open map keeps its copy.
- **SurfsUp**: the shader goes inside the map, like MALLET's built-in looks (no scripts, which SurfsUp doesn't allow).
- **Counter-Strike: Source** can't run shaders. File > Export > To Counter-Strike: Source offers **This map's sky (made into
  a skybox)**, picked automatically when you use your own sky: MALLET renders the sky into Source's six skybox images
  and packs them into the map. A surface shader exports as its first chosen image, otherwise its first color.
- Prefabs don't carry shader code: a prefab that uses your shader needs the file on the computer it's used on.

## Learn more

Godot's shader documentation covers the language: docs.godotengine.org, "Shading language", "Sky shaders" and
"Spatial shaders". Most Godot 4 sky and spatial shaders work in MALLET as they are.
