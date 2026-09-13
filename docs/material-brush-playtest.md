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
- Palette chips choose a brush; Assign or a viewport click applies it. The resource picker retains its existing immediate-assignment behavior.
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
