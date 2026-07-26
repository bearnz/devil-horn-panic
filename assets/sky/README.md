# Sky images

Drop finished sky art in this folder. Nothing else in the project needs editing
except one line in a `.tres` — see *Wiring a new image in* below.

`placeholder_panorama.png` is a generated reference grid, not art. It is here so
that orientation, seam placement and pole distortion are visible before anyone
paints anything. Replace it or leave it; it costs nothing.

## The format

**Equirectangular, exactly 2:1, sRGB.** Godot's `PanoramaSkyMaterial` wraps the
image onto a sphere as:

```
u = x / width    ->  yaw,   a full 360 degrees left to right
v = y / height   ->  pitch, +90 (top row) down to -90 (bottom row)
```

so the middle row is the horizon, the top and bottom rows each collapse to a
single point, and the left and right edges are the same seam and must match.

| Size | Use |
| --- | --- |
| 2048x1024 | placeholder / blockout |
| 4096x2048 | recommended for shipping |
| 8192x4096 | only if the sky has fine detail near the horizon |

PNG is fine for a stylised sky. Use `.hdr` or `.exr` instead if you want values
above 1.0 to bloom — the arena has glow enabled at 0.55 intensity, so a bright
sun disc painted into an HDR panorama will actually bleed.

The sky is decoration, not lighting: the arena's `ambient_light_source` is a
flat colour and the `Sun` is a `DirectionalLight3D`, so changing the image never
changes how the level is lit.

That cuts both ways — if you paint a sun disc, it has to go where the existing
shadows already say the sun is, or the two will disagree. Working the arena's
`Sun` transform back through the projection puts it at **u ≈ 0.36, v ≈ 0.25**
(45 degrees above the horizon, between +X and +Z — up and behind the player's
right shoulder at spawn). Move the disc and you have to re-aim the light to
match.

## Which part of the image ends up where

Verified by rendering the placeholder from inside the arena. The coloured bands
in it sit at the quarter turns:

| u | Band | World direction | In the arena |
| --- | --- | --- | --- |
| 0.00 | red (the seam) | -Z | over the far wall, ahead of the player spawn |
| 0.25 | green | +X | over the east steps and the ferry |
| 0.50 | blue | +Z | behind the player spawn |
| 0.75 | yellow | -X | over the west perch and the high ledge |

`u` increases turning from -Z toward +X, i.e. clockwise seen from above. **Put
the seam behind whatever the player looks at least.** Right now that is roughly
+Z, so shifting the image half a turn (`u` 0.5 at the seam) would hide it behind
the spawn.

## The horizon is mostly hidden

The arena's perimeter walls are 18 m tall and the floor is 92 m square, so from
the ground the bottom ~25 degrees of the sky is never visible; from the high
ledge at y=16 you see a little more. **The upper half of the image is what gets
looked at.** Detail painted below the horizon line is wasted except on the very
top platforms.

## Fog eats the sky

`Environment.fog_sky_affect` decides how much of the fog colour replaces the sky.
It defaults to **1.0, which erases the sky completely** — the arena rendered as
flat maroon before this was noticed. `000_poc_1.tscn` now sets it to **0.25**,
which keeps the level's haze while leaving the image readable. Raise it for more
atmosphere, lower it for a crisper sky, but do not put it back to 1.0 unless the
sky is meant to be invisible. The smoke test fails if it goes above 0.9.

## The gradient is the floor, not the current choice

The level's `WorldEnvironment` is a `SkyLoader` ([scripts/world/sky_loader.gd](../../scripts/world/sky_loader.gd)).
Its `sky` property holds the procedural gradient and **always** does. That is
what renders on the first frame, and it is what you are left with if anything
about the real sky goes wrong:

| Situation | What happens |
| --- | --- |
| `sky_path` empty — today's state | Gradient stays. Not a warning; "no sky yet" is a supported configuration. |
| `sky_path` points at a missing file | Warning, gradient stays. |
| `sky_path` points at a .tres that is not a `Sky` | Warning, gradient stays. |
| `sky_path` loads fine | Gradient renders first, real sky swaps in a few frames later. |

There is no path through that table where the level renders an empty background,
which is the entire reason the loader exists rather than just assigning the
panorama in the scene.

The load is synchronous, deferred by three frames.
`ResourceLoader.load_threaded_request()` would be the better tool and is **not
usable in this build** — it never completes for any resource with an
`ext_resource` dependency, plain level scenes included. Deferring still gets the
gradient up first; what it does not do is hide the hitch of decoding a large
panorama. Budget for that if you ship an 8K image.

## Wiring a new image in

1. Drop the file in this folder and let Godot import it (or run
   `godot --path . --headless --import`).
2. Open `resources/sky/arena_panorama.tres` and point its `panorama` at the new
   image.
3. In `scenes/levels/000_poc_1.tscn`, set the `WorldEnvironment`'s **`sky_path`**
   to `res://resources/sky/arena_panorama.tres`. Leave its `sky` alone — that is
   the fallback, and overwriting it is how you end up with no safety net.

To keep several skies around, add more `.tres` files next to those two. The
preview tool picks up whatever is in `resources/sky/` with no code change, the
same way perks and weapons work.

## Looking at it

```bash
godot --path . --resolution 1280x720 res://scenes/dev/sky_preview.tscn ++ <out_dir>
```

Renders every sky in `resources/sky/` from inside the arena — the horizon at
each quarter turn plus the zenith — against the level's real lighting and fog.
That is the check that matters; a panorama that looks good in an image editor
routinely looks wrong once it is on a sphere. The tool clears the level's
`sky_path` before it starts, so what you see is the sky it named and never the
loader's fallback arriving late.

To regenerate this folder's reference grid at another resolution:

```bash
godot --path . --headless res://scenes/dev/gen_sky_placeholder.tscn ++ 4096
```

## If you want a model instead of an image

A mesh skybox is a different mechanism and none of the above applies to it: it
is a `MeshInstance3D` with an inverted, unshaded mesh, either parented to the
camera or made huge, with the `Environment` background set to a flat colour
rather than a sky. It buys you geometry you can animate — moving clouds, a
rotating moon — and costs you the image-based ambient light a `Sky` can feed
into the scene. That cost is currently zero: the arena sets
`ambient_light_source` to **colour**, not sky, so it lights off a fixed tint and
swapping the sky image changes what you see but not how the level is lit. If
that is the direction, say so — it is worth doing properly rather than bolting a
mesh onto the panorama setup.
