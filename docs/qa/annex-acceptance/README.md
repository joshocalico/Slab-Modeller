# Annex acceptance audit

This read-only audit checks the saved Signal Relay Annex scene. It deserializes every solid's editable bytes through the native kernel validator, inspects generated meshes and collision shapes, records editor locks, and measures painted texture pixels within generated UV footprints.

The recorded run in [final-report.json](final-report.json) found 38 valid, editable solids with enabled collision, no editor locks, and 100% target albedo coverage on the required surfaces. BayFloor has six saved unwrapped faces. The bezel emission is a 9 × 9 pixel blob with 69 lit pixels, all inside the bezel's UV footprint.

The remaining walls, ceiling, loft deck and right jamb still use projected UVs. This result does not satisfy the brief's full architecture Unwrap/Pack/Fit requirement. Collider presence also does not prove that a player can climb the stairs. Use the native scene and runtime walkthrough for that check.

## Dependencies

- The repository's built Slab GDExtension and imported `project` directory.
- Godot 4.7.2, the version used for the recorded run.
- Python 3 with NumPy and Pillow. The Python scripts only read the dump and write reports.

If needed, install the Python packages into a scratch environment:

```sh
python3 -m venv /tmp/annex-audit-python
/tmp/annex-audit-python/bin/pip install numpy pillow
```

## Rerun

Run from the repository root. Close other Godot processes first, or coordinate an exclusive execution window. Even a headless Godot process can interrupt desktop automation on macOS.

Choose a new, absolute scratch output directory outside the repository:

```sh
export ANNEX_AUDIT_OUT="$(mktemp -d /tmp/annex-audit.XXXXXX)"
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path "$PWD/project" \
  --script "$PWD/docs/qa/annex-acceptance/dump_scene.gd" \
  -- --output "$ANNEX_AUDIT_OUT"
/tmp/annex-audit-python/bin/python docs/qa/annex-acceptance/analyze.py "$ANNEX_AUDIT_OUT"
```

On other platforms, replace the Godot executable path. `dump_scene.gd` accepts an optional `--scene res://path.tscn`, although the analyzer's palette and geometry expectations are specific to the Annex.

The dump writes `scene.json` and exported texture PNGs to the scratch directory. It does not save or modify the scene or its resources. The analyzer writes `analysis.json`. Keep the dump and images together. They are intentionally excluded from this evidence package because they are large.

Read the report's `passes`, `missing`, `unwrap_faces`, `enabled_collision`, `valid_editable_bytes`, and `editor_lock` fields. These tools collect evidence; their exit status is not a complete acceptance decision. A successful Godot process must also print `ANNEX_ACCEPTANCE_DUMP 38 solids` without script errors.

## Compare before and after

Keep the first output directory as a baseline. Use a different directory for the second run. Compare raw RGBA hashes, which remain stable when embedded resources become external `.res` files:

```sh
/tmp/annex-audit-python/bin/python docs/qa/annex-acceptance/compare.py \
  /absolute/baseline-directory /absolute/current-directory
```

The comparison writes `baseline-comparison.json`. Explicitly mark intended changes when needed:

```sh
/tmp/annex-audit-python/bin/python docs/qa/annex-acceptance/compare.py \
  /absolute/baseline-directory /absolute/current-directory \
  --expected-change RelayRack/surface1/emission \
  --expected-change BayPier/surface0/albedo \
  --expected-change BayHalfWall/surface0/albedo
```

These were the three intentional changes in the recorded final run. The first replaced the emission flood with the small blob. The other two assigned an existing ochre image to previously untextured solids. Every preexisting albedo image retained identical RGBA pixels.

For repeated runs with the same coverage policy, `analyze.py CURRENT --baseline BASELINE` can reuse prior results when generated UVs, texture bytes and sampling settings match. Omit this option after changing the analyzer's palette policy.

## Measurement details

The dump reads active mesh materials and generated mesh UVs. It records the material's UV scale, offset and repeat setting. The analyzer rasterizes triangle footprints at texture pixel centers, unions overlapping pixels, and handles texture repetition. Coverage is the fraction of that union matching the target palette. A white texture tinted through a material does not count as painted pixels.

The palette test allows a maximum RGB channel difference of 31 out of 255 from the reference color and requires alpha of at least 230. The report includes the reference color and acceptance floor for each measured surface. Results describe raw texture pixels, excluding filtering, mipmaps and lighting. They aggregate each material surface's UV footprint rather than claiming independent coverage for every face island.

Shader and triplanar mappings, clamped out-of-range UVs, excessive repetition and subpixel footprints are reported as unmeasured. Zero-area UV triangles contribute no pixel centers. The recorded WallW mesh has 14 such triangles, and the bezel has one. Uniform painted images cover their sampled texture colors, but these triangles are not evidence of valid atlas islands.

Emission uses a nonblack threshold of 10 out of 255. The report records the lit-pixel count, bounding rectangle, material operator and energy, and the number of lit pixels inside the actual bezel footprint when image dimensions match. The recorded blob occupies pixels `(20,37)` through `(28,45)` on a 256 × 256 image.

## Recorded geometry

The final run measured a 5.27 mm step from the highest tread to the loft, 13.75 mm of actual highest-tread overlap with the landing, 2.3502 m of loft headroom, 0.2998 m between the stair and east wall, and 0.3902 m above the rack. The general analyzer also reports AABB overlap, which is larger than the highest tread's overlap and must not be substituted for it.

The report contains the scene SHA-256 and distinct image RGBA hashes. The scene hash alone cannot identify changes inside external material resources. The saved byte validation invokes `deserialize`, which calls the kernel's `validate`, then verifies serialization equality and a nonempty face set.

The dump's core ran in Godot with no errors or warnings. The Python scripts were rerun against that dump after packaging. The command-line wrapper added during packaging was source-reviewed without launching another Godot process during the final verifier's exclusive window.
