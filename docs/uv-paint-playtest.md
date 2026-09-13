# Curved-face UV and pixel painting check

This pass uses the authored PowerHouse front gable in Signal Foundry. Its semicircular face spans several repeats of the Timber texture.

## Native editor exercise

The author selected the gable face in modelling, opened Surface Paint, and clicked Sample. Sampling was necessary because the active material slot still referred to slot 0; the selected face used Timber in slot 1.

The original Material / UV canvas folded all clipped texture-tile intersections into one square. The orange lines crossed repeatedly, so the semicircular face outline could not be recognized. The underlying ordered face UV loop was correct; the distortion came from the canvas display.

Make Unique assigned a copy of Timber to the selected face in slot 2. In Pixel mode, the author clicked the image with an 8-pixel red brush, then a 64-pixel brush. Save Paint wrote `PowerHouseFrontGable_m2.png`, and saving the scene preserved the unique material. Inspecting the PNG confirmed both test marks. The marks were not clearly visible on the gable in the editor viewport, so their rendered face target requires further investigation.

After Save Paint followed by saving the scene, both Paint status labels still claimed that the scene needed saving. Godot's window title was clean. This is a stale status message, not evidence of an unsaved scene.

The author undid both strokes and Make Unique through the native editor, then saved again. The scene matched the committed file exactly. The temporary PNG was removed after preserving diagnostic snapshots at `/tmp/slab-gable-paint-test.tscn` and `/tmp/slab-gable-paint-test.png`.

## Required follow-through

- Show recognizable unwrapped outlines across repeated tiles in Material / UV.
- Keep Pixel coordinates tied to the actual image.
- Verify Fit, pan, zoom, numeric edits, and Undo on the curved face.
- Show every selected face when a UV edit affects several faces.
- Correct the saved-scene status and establish the rendered target of the test strokes.

## UV canvas validation

After restarting Godot with the new canvas, the selected gable appeared as one continuous curved outline over repeated Timber tiles. Changing Repeat V from 0.5 to 1 expanded the outline; Fit UV framed it again. Command-Z restored the original repeat and clean scene. Dragging the outline changed Offset U and V to approximately 0.55 and 0.25 without reframing during the drag. One Undo restored the original placement. Canvas scrolling visibly changed its zoom.

The author then selected the doorway wall in modelling, used Select Coplanar, and opened Surface Paint. The target row reported 21 faces, and the canvas showed their outlines together. These checks changed no saved scene geometry, materials, or UVs.

The first layout clipped the Fit UV label at the right edge and drew instructions directly over the texture. After correcting child anchoring and minimum-size growth, a native reload showed the complete Fit UV button inside the dock and readable instructions on a dark background. Scrolling enlarged the outline; clicking Fit UV restored the full curved face to view.

## Pixel rendering and save feedback

The saved material and emitted gable surface referred to the same painted image. The missing marks came from stale mipmaps: painting changed the full-resolution pixels but left the smaller images used at viewing distance unchanged. A rendered diagnostic showed no red with the stale mipmaps and 6,802 red pixels after regenerating them with the material's mip filtering preserved.

The corrected editor was tested on the same gable. After Sample and Make Unique, a red 64-pixel brush mark appeared immediately as repeated dots on the model. Command-Z removed the dots from both the image and model; Command-Shift-Z restored them. Save Paint followed by Command-S cleared both pending-save messages and the scene's dirty marker.

Both temporary operations were then undone and the scene saved. The scene matched the committed file exactly, and the temporary paint PNG was removed. The pixel rendering and save-status checks therefore leave no test marks in the sample level.

## Verification

`scripts/slab-verify` passed all gates after the final layout correction, including 135 kernel tests with 4,031 checks, the paint and save-status smokes, editor initialization, and gameplay checks. `scripts/slab-docs-verify` passed for 28 MDX pages and 74 local references. The website lint and production build also passed during the tutorial revision.

Middle-button canvas panning was not exercised through the native computer-use API in this pass. Native checks covered zoom, Fit, UV dragging, numeric repeat edits, multi-face outlines, pixel painting, Undo/Redo, and scene-save feedback.
