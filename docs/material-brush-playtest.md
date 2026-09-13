# Material brush identity and selection feedback

## Reproduced in Godot

In Signal Foundry, selecting the PowerHouse front gable and entering Surface Paint showed an empty Slot 0 brush even though the selected face used Timber in slot 1. The Material / UV canvas displayed a fallback brown image rather than the face's texture.

After clicking Sample on that gable, clicking the PowerHouse doorway wall in Material / UV did not apply Timber. The status reported that Set Material did not change the solid, and the picker switched to Limestone. The room's slot 1 contained Limestone. The operation carried a local slot number between solids instead of the sampled material resource. This reproduction did not change the saved scene.

Selecting all 145 room faces and entering Paint showed a single Limestone material label, despite the selection containing both Limestone and Timber faces. The label described the active brush without distinguishing it from the selected faces.

## Intended interaction

- Entering Paint inspects a common selected material without editing the scene.
- The target line names the object, face count, and selected material or mixed state.
- Brush identifies the material used by Material / UV clicks. Texture identifies the bound pixel-paint material.
- A sampled material transfers between solids by resource identity, regardless of local slot numbering.
- In-mode selection changes preserve the chosen material brush.
- Palette chips and the resource picker choose a brush; Assign or a viewport click applies it.
- Mixed and empty selections do not silently choose an arbitrary assignable material on entry.

## Native verification

After restarting Godot, selecting the front gable and entering Paint immediately showed Timber in the target summary, Brush label, picker, and canvas. No Sample click or scene edit was required.

Clicking the room's doorway wall applied Timber, reusing the room's existing Timber resource. Command-Z restored Limestone on the face while the Brush label stayed Timber. Command-Shift-Z restored the assignment. Switching to Pixel after Undo showed Texture: Limestone and the limestone image; switching back restored the Timber brush.

The temporary assignment was undone. Selecting all 145 room faces and re-entering Paint showed Mixed, Brush: none, and UV outlines over a checker background. All temporary changes were undone; the saved scene remained identical to the committed scene.

## Regression coverage

The focused material-scope smoke checks common-material entry without edits, conflicting slot numbers across solids, synchronous selection changes during native focus, exact assignment Undo/Redo, resource reuse, persistent brushes absent from target slots, and separate Pixel binding. Additional review checks cover mixed Make Unique refusal, copying a brush before assigning it to another solid, and preventing a palette choice from redirecting Pixel to an unrelated image.

On the final native reload, Make Unique was disabled for the mixed selection with no brush. Choosing Timber enabled it without changing the faces or dirtying the scene.

A temporary unique gable texture was painted and saved with the scene. Undo removed the paint and reported Unsaved paint; Redo restored the saved pixels and cleared that status. The comparison now excludes derived mipmap bytes. Both temporary operations were undone, the scene saved, and the generated test PNG removed. The saved scene again matched the committed file exactly.

Final `scripts/slab-verify` passed all gates, including 135 kernel tests with 4,031 checks and the new material-scope smoke. Documentation reference verification passed for 28 pages and 74 local references. Website lint and the 32-page production build passed during the documentation update.

## Pixel workspace layout

A subsequent native pass separated the controls by mode. Pixel shows Make Unique, Save Paint, and brush controls. Assign, Sample, the material picker, and the material palette remain in Material / UV. At the same editor and dock size, the square image grew from roughly 208 to 264 screen pixels per side. The shared-texture hint explains Make Unique, and Save Paint is disabled until the selected image is editable.

Pixel now opens without repeated UV lines obscuring the image. The Show UV checkbox was clicked on and off in Godot; it displayed the original wrapped boundaries without dirtying the scene. Material / UV continues showing its full unwrapped outlines.

Make Unique, a red stroke, Save Paint, and scene save were exercised through the simplified Pixel controls. Both edits were undone, the scene saved, and the temporary PNG removed. The saved scene matched the committed scene. A final reload confirmed the compact Material / UV picker and the mixed-selection Pixel state: no image, disabled Make Unique and Save Paint, and guidance to select faces sharing one material.

The full verification suite passed. After the final picker-width adjustment, paint and chrome checks passed again with no script errors, followed by the native reload above. Documentation verification passed for 28 pages and 72 references; website lint and its 32-page build also passed.

## Explicit picker preview and material inspection

The resource picker now chooses a Brush preview, matching palette chips. Assign is the edit that adds a slot and applies it to selected faces. The picker preview opens Godot's Inspector. Unnamed resources use New material before assignment and Material N for a scene slot, rather than a generated subresource identifier. Explicit names and external filenames remain visible.

Native replay selected all 18 MaintenanceBayRoof faces, opened Surface Paint, and created a new StandardMaterial3D through the picker. The Brush and canvas became white while the roof and selected-material header stayed Teal Steel. Clicking the preview opened the material Inspector without losing the face selection.

Editing Albedo Color to c98239 exposed a stale preview: the Inspector sphere changed to copper, but Slab's canvas stayed white. StandardMaterial3D's Inspector edit did not notify the existing Resource.changed listener. The fix also listens to EditorInspector.property_edited for the active Brush and defers a preview refresh, preserving the selected faces and pending UV placement. A fresh native replay confirmed the copper color appeared in both the Paint sphere and canvas immediately after closing the color picker. Native Undo restored white in both previews, and Redo restored copper. The roof and its 18-face selection stayed teal until assignment. Undo, leaving Paint, and Save restored the exact scene. The Inspector connection lives behind the existing editor-host adapter.

Before Assign, Save produced no scene diff, despite Godot marking the Inspector edit dirty. Assign followed by Save produced three roof material slots and copper faces, with the original 18 faces and volume 3.87238744273782. One native Undo and Save restored the scene exactly.

The final rendered paint regression passed with zero failures. It clicks the picker preview, checks choice leaves the solid unchanged, applies through Assign, and verifies exact Undo and Redo. Its Inspector final-property-edit path updates preview pixels without manually emitting Resource.changed. The complete verifier, the final editor-boundary chrome check, documentation links, and website build passed.

## First face selection and empty gestures

In the saved Signal Foundry scene, entering Surface Paint from Object mode showed Select a face to paint and Brush: none. Clicking the MaintenanceBayRoof side instead reported Choose or sample a material before painting, leaving the selection empty. Dragging the native Y handle above the roof also created a Translate history entry and dirtied the scene. The displayed node position did not change during that reproduction. Undo restored the clean scene.

The corrected native replay used Front Orthogonal at 1225 by 768. Entering Paint with no face IDs and dragging from `(613, 193)` to `(613, 157)` left History at The Beginning. Clicking the roof side at `(760, 273)` selected one face and adopted Teal Steel, its image, and UV values without dirtying the scene. Switching to Pixel, dragging the newly centred Y handle through empty sky, and clicking empty sky preserved that face and the clean history. The saved scene and texture stayed unchanged.

The rendered native-input fixture checks that its initial Y-axis coordinate misses geometry. Paint preserves exact mesh bytes, node transform, history version, and empty selection. After leaving Paint and restoring the fixture's original element selection, the same coordinate gesture changes the mesh, creates history, and supports exact Undo restoration. All nine checks passed. The fixture sends held-button motion through Godot's connected viewport input handler; the saved-scene computer-use drag alone did not establish post-exit movement.

Headless coverage checks both paint modes, dragging from empty space onto geometry, first-click adoption, default-material selection without edits, and release of gesture ownership. The full verifier passed all gates. Documentation verification passed for 28 pages and 72 references, and the website production build passed.

Godot's view-name menu also offers View Transform Gizmo. A native toggle hid and restored the widget while retaining the selected solid, Inspector, and Paint workspace without editing the scene. The pixel-paint guide documents this manual option. Automatic hiding remains unresolved.
