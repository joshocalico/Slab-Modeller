# Room workflow replay

13 September 2026. Native Godot 4.7.2, Signal Foundry, 1225 × 768 window.

## Authored in the editor

Created MaintenanceBay with Create Box, dimensions 4 × 3 × 4. Used the Inspector to place it at (26, 0.17, 19). Selected its top face, applied Inset 0.45, then Extrude -2.4. Saved the scene. The persisted room has 14 faces and volume 24.938059.

Created MaintenanceBayDoorCutter, dimensions 1 × 2 × 1, and positioned it at (27.5, 0.77, 18.8). It intersected the negative-Z wall and started at the room floor. Filtered the Scene tree to the MaintenanceBay nodes, selected MaintenanceBay in Object mode, then extended the selection to MaintenanceBayDoorCutter with Shift+Down. The panel identified MaintenanceBay as **Target** and MaintenanceBayDoorCutter as **Second solid**.

Clicked **Subtract** in the native panel. The status reported 24 faces. The cutter remained visible over the opening, so deleted it with Cmd+Backspace and Return. An outside orbit then showed the doorway through the wall. Saved the completed doorway. This replay covers native authoring and exterior visual inspection; it does not yet cover gameplay traversal or an approach route.

The earlier runtime probe produced the same 24-face room with volume 24.037669.

Created MaintenanceBaySteps through the native Stair selector and placement preview. Entered Width 1.4, Height 0.6, Depth 1.2, and 3 steps. Stair ascent runs along local +X, so rotated the node -90 degrees around Y and placed it at (28.6, 0.17, 18.1). This puts the top tread into the doorway. The saved solid reloads with 10 faces and volume 0.669670746. These are authored steps, not a verified gameplay route yet.

The Stair button initially failed to switch away from Box in the running session. A GUI-event regression exposed a notification ordering defect: create_settings_changed fired before the new shape and controls were installed. The corrected order passes that regression. A fresh native editor then selected Stair, displayed its fields, and placed the requested solid. The earlier unresponsive session has not been conclusively attributed to that ordering defect alone.

That placement exposed two further papercuts: an internal-looking @SlabSolid name and generic Width/Depth labels that concealed the stair's ascent axis. The follow-up pass uses readable names when inserting the preview and gives stairs Run, Rise, Width, and Steps controls. Tooltips and creation docs explain ascent along local +X.

Native verification placed another stair in the saved scene and received Stair2. Undo removed it; Redo restored it with the same name. Undid the temporary placement and saved with no scene diff. The new controls were visible in the editor. Automated coverage exercises repeated placement and name stability through Undo/Redo, plus the shape-specific labels.

## Panel change and verification

During Extrude, Inset, and Bevel previews, hide the unrelated command body and pivot/axis settings. Keep the selection mode strip, numeric operation controls, Apply, Cancel, and feedback visible. Restore the modelling controls when the operation ends.

Native replay verified an invalid extrusion with Apply disabled, Cancel restoring the controls, a valid inset with Apply restoring the controls, and Undo followed by scene save restoring the room to 14 faces. The temporary inset is not in the saved scene.

Chrome smoke passed 41 cases, including visibility and restoration checks. The full slab-verify passed all gates. The docs verifier passed 28 MDX pages and 72 local references. Website lint and the 32-page build passed.

## Outstanding findings

- The generic transform gizmo overlaps the operation handle. Clearing Slab's subgizmo selection merely moves the native gizmo back to the object pivot. That attempted fix failed a native replay and was reverted. No supported visibility hook was found in the exposed editor API.
- Fixed in the rendered-preview pass below: the proposed surface now replaces the source display during a valid operation.
- Fixed in the follow-up pass: Slab's status and boolean operand labels now follow selected-node renames immediately. Native rename to MaintenanceBayRenameCheck updated the status without reselection; Undo restored MaintenanceBay in both the tree and Slab. The test rename was undone and the scene saved without a scene diff. Smoke coverage also checks that renaming an unselected solid preserves current feedback.
- The native doorway authoring replay and local entrance playtest are complete. The bay now has a first material pass, roof, and interior light, but still needs a gameplay interaction and an enclosed-room playtest. The full route from the level's normal spawn remains untested.

The room tutorial now covers installed-addon prerequisites and exact cutter placement using the Inspector, instead of relying on an unspecified wall and drag direction.

## Rendered operation preview replay

Created a temporary 4 × 3 × 4 box in Godot, inset its top by 0.45, and saved that baseline. Extrude -2.4 displayed the cavity before Apply. The old selected-cap fill no longer covered the opening. Save kept the preview active and left the scene file byte-for-byte identical to the baseline. Extrude -4 restored the original surface and disabled Apply; returning to -2.4 recovered the preview. Cancel restored the original display. Apply committed the cavity, and Undo restored the inset cap.

Deleted the temporary box in Godot and restored the cutter's temporary inspection position. Saving returned the scene file to HEAD exactly. A later bevel pick hit PowerHouseVault rather than the intended cutter and was rejected at both 0.5 and 0.05 width. Cancel left its geometry unchanged. Crowded picking needs further investigation.

For a clear bevel replay, temporarily moved the cutter to Y=10 through the Inspector. Selected its exposed vertical edge and previewed a three-segment bevel at widths 0.05 and 0.3. The rendered silhouette changed before Apply; Cancel restored the sharp edge. Restored Y=0.77 and saved, again leaving the scene file identical to HEAD.

The full verifier passed all gates. The viewport smoke covers valid-to-invalid-to-valid preview changes. The new display-preview smoke checks packed scene properties, material references, collision state, mesh export, corrupt preview data, and exact display restoration on Cancel. The docs verifier passed 28 MDX pages and 72 local references.

Undo exposed a separate issue: geometry returned to the inset cap but the native gizmo remained at the extruded floor. The selected face ID had not changed, so the refresh cache missed the geometry change.

Fixed by subscribing to the selected solid's topology changes and invalidating the native gizmo frame. Native replay used an isolated cutter side face: Apply Extrude 0.5 moved the gizmo with the face, Undo restored both, and Redo moved both again. Undid the test edit, restored the cutter's position, and saved with no scene diff.

The full verifier passed all gates. The separate editor-hosted regression passed nine checks, including disconnecting the previously selected solid and preserving pending native drag state while invalidating its cached frame. It now runs in slab-verify. The runtime chrome smoke retains its 41 cases; editor-plugin construction belongs in the editor-hosted test.

## Hidden geometry picking replay

Selected MaintenanceBay, expanded the Inspector's Visibility section, and turned Visible off. Its surface disappeared. Clicked away, then clicked its former location at the left rim. Slab selected the invisible MaintenanceBay again, confirmed by the status label and the Inspector's unchecked Visible property. Restored visibility and saved with no scene diff.

This reproduces a picking defect, not merely an ambiguous click on overlapping visible geometry. Hidden solids must be excluded from both viewport candidates and occlusion checks. X-ray should expose occluded elements of visible solids without making hidden nodes selectable.

After the fix, replayed the same hide-and-click sequence in a restarted editor. The former rim location selected nothing; clicking the visible floor behind the hidden room selected ExteriorCourtyard. Face selection also selected the courtyard with X-ray both off and on. Restored the room's visibility, saved with no scene diff, and selected its visible slanted rim edge successfully.

The picking pass also corrects perspective interpolation: the world point tested for occlusion now projects onto the nearest point along the screen-space edge. Edges crossing the camera near plane are clipped before projection. The focused smoke covers perspective, orthographic, near-plane, hidden-solid, and hidden-ancestor cases. Full slab-verify passed all gates, including the editor-hosted gizmo regression. The docs verifier passed 28 MDX pages and 72 local references; website lint and its 32-page build passed.

## Local entrance gameplay replay

Temporarily moved Player through the Inspector to (28, 0.4, 16.2), facing +Z with Y rotation 180 degrees. Ran the current scene from Godot's toolbar. Enabled F3 diagnostics, started autorun with T, and jumped with Space. The player crossed the hazard strip and entered the bay. Diagnostics reported feet (28.00, 0.77, 22.25), floor YES, and floor body MaintenanceBay/__body. Stopped autorun and turned around to inspect the doorway from inside.

This demonstrates a jump approach through the entrance and standing on the room's collision floor. It does not prove every tread is walkable without jumping, an exit crossing, or the complete gameplay route. Closed the running game and restored Player to (3, 0.4, 3.5), Y rotation -90 degrees, through the Inspector. Saved and verified the scene file matches HEAD exactly.

## Material authoring and selection fill

Used Surface Paint in the native editor to assign brick to the bay, then limestone to its interior floor. Saved and reloaded the scene read-only: 23 faces use brick and one uses limestone. The room retains 24 faces and volume 24.0376685485244; the entrance steps retain their saved position and volume.

Selecting all faces exposed a checker pattern where the selection tint shared the rendered wall surface. Offset the fill vertices 0.001 m along the face normal, retaining depth testing and exact geometry for outlines and edits. After restarting Godot, selected all 24 faces with X-ray off and orbited from above to the doorway, then inspected close and oblique views. The tint remained uniform, without the earlier checker pattern. The regression covers concave faces and reversed winding; the full slab-verify passed all gates.

Surface Paint also swallowed keypad orbit commands. Leaving Paint restored orbit immediately. Fixed the input routing so native keypad view commands pass through after paint handles its own commands. In a restarted editor, KP8 orbited in Material/UV mode and KP5 switched to Orthogonal. Switched to Pixel mode, orbited with KP6, and returned to Perspective with KP5 without leaving paint. The saved scene remained unchanged. Paint and viewport smokes passed, followed by all slab-verify gates.

## Paint canvas sizing replay

At the native editor's current scale and 1225 × 768 window, Material/UV left approximately 77 screen pixels for the canvas. Selected a brick face before opening Paint, enlarged the bottom panel manually, and used Fit UV. The larger canvas made the complete outline readable. A test drag changed its UV offsets; Undo and Save restored the scene file exactly.

The paint panel now derives its minimum height from its visible controls and reserves 190 logical pixels for the canvas. After restarting, entering Material/UV expanded the panel automatically and provided approximately 135 screen pixels for the canvas at this editor scale. Dragging the divider downward respected the minimum. Replayed Fit UV, a UV drag, Undo, and Save without a scene diff. Pixel mode used the freed control-row space for its image. Exiting Paint allowed the divider to return to its previous modelling position. Automated layout coverage also checks 1.5× scaling. Full slab-verify passed all gates; the docs verifier passed 28 MDX pages and 72 references, and website lint and the 32-page build passed.

One design ambiguity remains: selecting Limestone in the palette previews that brush texture beneath the selected Brick face's UV outline, before Assign changes the face. The Brush and face labels correctly differ, but the canvas can look like a committed material change. The follow-up pass below adds an explicit preview caption.

## Brush preview feedback and step materials

Added a canvas caption when the current Brush differs from the selected faces' material. Native replay selected a Brick face, chose the Limestone palette chip, and saw “Brush preview: Limestone” with an instruction to Assign. The face stayed Brick. Assign changed the rendered face and restored the regular gesture hint. Undo restored Brick and the preview caption. Restored the Brick brush and saved after the test.

Also selected all ten MaintenanceBaySteps faces in Godot and loaded the existing limestone material through the material picker. The saved scene reload confirms ten limestone step faces, the original step transform and volume, and the bay's unchanged 23 brick faces and one limestone floor face.

The full slab-verify passed all gates. Regression coverage includes distinct material resources with identical names, mixed/default/empty selections, Assign and Undo, and Pixel mode. The docs verifier passed 28 MDX pages and 72 references; website lint and the 32-page build passed.

## Roof and interior light authoring

Created a Box in Godot with Width 4.4, Height 0.2, and Depth 4.4. Placed it through the viewport, renamed it MaintenanceBayRoof, and set its position through the Inspector to (25.8, 3.17, 18.8). This provides a 0.2 m overhang around the bay. Selected its six faces and loaded the existing teal_steel material through Surface Paint.

Added an OmniLight3D under the roof using Godot's Create Node dialog. Set local position to (2.2, -0.6, 2.2) and enabled shadows. The saved scene reload confirms roof bounds approximately (4.400391, 0.200195, 4.400391), positive volume 3.8764694519341, six teal-steel faces, and the light's intended transform with range 5 and shadows enabled. Room and step geometry and material counts remain as before.

Switching between modelling and painting resized the viewport and moved the target under the cursor during this pass. Rechecked the selected node and face count before applying materials; no unintended material assignments remain. This is evidence for reviewing layout stability, not proof of a picking defect. Gameplay clearance and lighting with the roof in place still need a native playtest.

## Enclosed room replay and wall UV correction

Repeated the native jump approach with the roof visible. The player entered the bay and stood at (28, 0.77, 22.25), with floor contact on MaintenanceBay/__body. Stopped autorun and turned toward the doorway. The interior light kept the walls and ceiling readable, with sunlight entering through the opening. This verifies the local jump entrance and standing clearance, not every stair tread, an exit crossing, or the full gameplay route.

The interior view exposed vertical brick courses on both side walls. Hid the roof through the Inspector, selected each inner side face in Surface Paint, and rotated its UVs by 90 degrees. Restored roof visibility and replayed from inside the room. Both side walls now have horizontal brick courses. Restored Player to (3, 0.4, 3.5), Y rotation -90 degrees, and saved through Godot.

Read-only scene verification confirms that only faces 219043332097 and 261993005057 have the new 90-degree rotations. Room geometry and material counts, step geometry and materials, roof visibility, lighting, and the normal player spawn remain correct. No source code changed in this pass.


## Stable Paint tool switching

At the compact dock size in the 1225 × 768 native editor, switching Material/UV to Pixel moved the divider from approximately Y=409 to Y=466. The view and selected geometry shifted with it. Enlarging the dock manually prevented the jump, identifying different minimum heights as the cause.

Paint now derives a shared minimum from the larger tool layout. Hidden Material/UV controls still contribute to that minimum, while Pixel uses the extra space for the canvas. After restarting Godot, Material/UV and Pixel kept the divider at Y=409. Reopening directly into Pixel retained that minimum. Selected a Teal Steel roof face and switched both tools with the texture loaded; the viewport remained stationary. Exiting Paint returned the compact modelling layout. No scene changes were made.

The focused chrome regression checks both tool directions, Pixel-first entry at 1.5× scale, and restoration of the modelling minimum. Paint smoke and the full slab-verify passed. Entering and leaving the Paint workspace can still resize the viewport; this change addresses switching tools inside it.


## Persistent selection context

Closing Paint left only “Surface Paint closed.” in the status line, hiding the selected object and face count until the next selection change. Added a compact selection summary in the existing header space. Element counts precede the object name so long names cannot hide the count. The existing status line continues to show operation guidance and recovery messages.

In a restarted native editor, selected the roof face, entered Paint, and closed it. The header retained “1 face · MaintenanceBayRoof” beside the mode controls. Started Extrude, entered -1, and saw the crossing-face refusal with Apply disabled while the header retained the target. Cancelled and saved with no scene diff.

Chrome coverage checks reports, selection changes, renames, clearing selection, and long names in a constrained dock. Panel smoke and the full slab-verify passed. The rendered panel editor replay also passed. Regenerated and inspected the Face, Object, Extrude preview, and Boolean panel captures through that editor workflow.


## Loop Cut panel workflow

Selected a roof edge and started Loop Cut with L. The three-cut preview worked, but the panel lacked Apply and Cancel. Moving away from the edge could discard the candidate while the previous cut guidance remained. Enter then appeared to do nothing.

Loop Cut now publishes its active and valid-preview state to the panel. Apply and Cancel accompany Cuts and Centre. An explicitly selected starting edge stays fixed while using the panel. Starting without an edge keeps the hover workflow. Missing candidates clear the preview and replace stale cut guidance.

Native replay cancelled a preview through the panel and saved with no scene diff. Started again, typed 3 into Cuts without pressing Enter, and clicked Apply. The saved roof had 18 faces and unchanged volume 3.8764694519341. One native Undo followed by Save restored the complete scene byte-for-byte. The focused regression checks pending field values, pinned selection, missing candidates, cancellation, preview agreement, and Undo.

The final native layout keeps Apply and Cancel together below the numeric fields at the current dock width. With no edge chosen, Apply is disabled and the status asks for a hover target. Selecting an edge and restarting enables Apply. Cancel returns to the idle panel without a scene diff. The full slab-verify, documentation checks, and website build passed.


## Symmetric bevel selection and perimeter limit

Selected all 12 roof edges and started Bevel. The editor refused before opening the preview because summed adjacent normals cancelled to zero. Its generic message asked for a shared face direction despite Edge mode. A single edge accepted a 0.03 m, three-segment preview.

The handle now falls back to the last selected edge when the aggregate direction cancels, while the kernel still validates the complete selection. Native replay of all 12 edges opened the preview controls and displayed the kernel's collapsed-face refusal with Apply disabled, including at width 0.03 and three segments. Cancel and Save left the scene unchanged. The full slab-verify passed.

A disposable kernel probe also refused the four top perimeter edges of a 4.4 × 0.2 × 4.4 box at width 0.03 and three segments. The operation fails before embedding validation. The current bevel implementation edits edge rails sequentially, with special handling for exactly three edges meeting at one corner. Connected perimeter and complete-box bevels require planning and rebuilding their shared corner geometry together. The roof refinement remains unfinished; no partial bevel was saved.

## Connected perimeter bevel and boundary selection

Added Select Boundary in Face mode after the roof workflow exposed the lack of a direct face-to-perimeter selection command. Native replay selected the roof top and used the new button. The panel switched to Edge mode, retained MaintenanceBayRoof, and reported four selected boundary edges.

The connected bevel path now assembles retained faces and bands from the original geometry in a validated candidate. In Godot, set width 0.03 and three segments, then applied and saved. Read-only reload found 18 teal-steel roof faces, volume 3.87238744273782, unchanged bounds and transform, and the original shadow-casting child light. Room and step geometry, wall UV rotations, materials, and player spawn remained correct. One native Undo and Save restored the entire scene to SHA256 5f27773ca06c6fa691925454046b6ab44208ea80d94d1d4596460ef0c7c216b2. Redo and Save restored the rounded roof.

Kernel coverage includes all 24 perimeter selection orders with oriented face geometry and attributes, exact requested inset width, a connected open chain, atomic unsupported-selection refusal, and an untouched UV seam. The kernel passes 143 tests and 4288 checks. All twelve box edges remain unsupported. Shortened or replaced edges still lose their previous seam marks; geometrically unchanged edges retain them.

The default 0.5 m preview on this thin roof also exposed a remaining feedback issue: the displayed requested width can exceed the geometry's clamped width. The saved 0.03 m case uses the measured requested width. Investigate reporting effective width before claiming exact numeric feedback for oversized amounts.

The full slab-verify passed after updating the panel command inventory and the old bevel-refusal expectations. The rendered panel editor test reported zero failures. Refreshed and inspected the Face and Materials & UV captures with Select Boundary visible. Documentation links passed, and the website build passed.

## Typed UV input

In Surface Paint, selected the roof top face, typed Rotation 15 without pressing Enter, and clicked Apply UV. The field displayed 15 but the texture remained unchanged; the status reported no change. Apply UV now commits pending text in its UV fields before running the operation.

The rendered paint editor regression failed on the original code and passed after the fix, including one Undo and exact Redo. Updated its two stale target-label expectations to include the current material summary. Native replay rotated the roof texture immediately after the same typed-input sequence. One Undo and Save restored the scene with no diff. The complete paint editor replay and full slab-verify passed.

## Typed preview input

The same interaction failed in Extrude: typing 0.05 without Enter and clicking Apply committed the previous 0.5 m value. The saved roof height increased from 0.200195 to 0.700195. Preview controls now retain pending keyboard input across panel refreshes and submit it before Apply. Programmatic value changes remain authoritative, including the room tutorial's -2.4 m extrusion.

The rendered panel regression covers pending Inset distance, Bevel width and segments, and the existing programmatic room sequence. It reports zero failures. Native typing of 0.05 followed directly by Apply and Save produced a roof height of 0.25 m, within the lattice rounding of the requested extrusion. One native Undo and Save restored the scene with no diff.

## Mapping inside Surface Paint

Selected all 18 faces of MaintenanceBayRoof in native Face mode, then opened Surface Paint. The Mapping controls adopted the existing teal texture's width of 256 pixels. Unwrap at 256 pixels/metre refused the atlas and suggested 4096 pixels, without marking the scene dirty. Typed 16 into Pixels/metre without Enter and clicked Unwrap. Save and read-only reload found all 18 faces unwrapped, 15 seams, two material slots, and unchanged volume 3.87238744273782. One Undo and Save restored the exact scene.

The first replay exposed a stale canvas after Unwrap: the model and saved data changed, but the outline remained planar until Fit UV. Successful Unwrap now refreshes UV state and frames the new loops without rebinding the selected brush. A fresh native replay confirmed the new net appeared and framed itself immediately. Undo restored planar mapping.

Created a new untextured StandardMaterial3D through Godot's material picker and switched to Pixel. Typed 128 into New image px without Enter, then clicked Make Unique and saved the scene. Read-only reload found one embedded 128 by 128 image, with the same 18 faces and volume. Two Undo actions followed by Save restored the original material slots and the exact scene. No paint PNG was written during this test.

Godot's material picker search accepted StandardMaterial3D followed by Down and Enter. The newly created material appeared under its generated subresource identifier, which is less readable than a user-facing material name. Improve that label when consolidating material creation.

Pixel exposes only an Image section for image size; Mapping state, density, and Unwrap stay in Material / UV. Native inspection confirmed the existing 256-pixel artwork reports a read-only size. Mapping and the lower placement controls remain reachable by scrolling the shared inspector at the compact dock height.

The final rendered regression passed with zero failures. It checks that Unwrap changes UV loops, centers their canvas bounds within two pixels, updates the Mapping label, and preserves a deliberately different Brush resource. The full slab-verify and documentation link checks passed. The regression capture uses a diagnostic brush and is retained as test evidence rather than a guide illustration.
