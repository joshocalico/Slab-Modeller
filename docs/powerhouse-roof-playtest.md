# PowerHouse roof authoring pass

This pass was authored in the Godot editor using Slab creation, Plane Cut, face selection, Surface Paint, native duplication, and Inspector transforms. No scene generator was used.

## Saved construction

- `PowerHouseCeiling`: 10 by 0.25 by 8 metre box at `(34, 5.12, 19)`. It overlaps the wall tops by 0.05 metres to close the room.
- `PowerHouseVault`: 10 metre, 180-degree arch, 8 metres deep, 16 segments, thickness 0.35. Position `(34, 5.32, 19)`, Y scale 0.5. All 36 faces use Teal Steel.
- `PowerHouseFrontGable`: 9.3 metre diameter cylinder, height 0.25, 32 sides. Plane Cut kept negative local Z at offset zero. X rotation 90 degrees and local Z scale 0.5 fit the semicircle inside the vault. Position `(39, 5.32, 19.05)`.
- `PowerHouseRearGable`: native duplicate of the front gable at Z 26.7. Both end panels use Timber, with Repeat V 0.5 to account for the node scale.
- `PowerHouse/OmniLight3D`: authored Godot light at local `(5, 3.5, 4)`, energy 1.5, range 8, shadows enabled. The saved light is visible.

The existing limestone doorway wall and timber floor remain. A follow-up editor pass assigned Limestone to the room's base material slot, finishing the remaining walls. All six ceiling faces now use Timber, assigned through Surface Paint's native Quick Load. Native Undo restored the empty ceiling material and clean scene state; Redo restored Timber, then the scene was saved. The front perspective view showed the limestone interior through the doorway and the timber floor. The running-game check below predates these material-only changes.

A second normal-controls game pass loaded the saved materials, walked around the turbine, jumped both courtyard hazards, and entered the room. F3 showed `(38.95, 0.47, 23.00)`, floor contact with `PowerHouse/__body`, and autorun off. The interior showed limestone on the back and side walls, timber on the floor, and a continuous timber ceiling when looking up. This confirms the material assignments survived saving and appeared in the running scene.

## Running-game check

Starting from START, the author used normal movement controls to reach the courtyard, jumped both hazard strips, and entered the enclosed room. F3 reported feet `(38.67, 0.47, 23.58)`, floor contact with `PowerHouse/__body`, and autorun off. The exit correctly reported three remaining cells. The courtyard view showed the curved timber gable within its teal roof rim. Looking up inside showed the continuous ceiling and lit walls. This checks the new room route and enclosure, not the complete three-cell game loop.

## Workflow findings

Creation still places new solids at the origin, away from this work area. Inspector transforms were needed for each part. Plane Cut correctly produced a capped half-cylinder, but positioning the preview near the work would make this flow easier to follow.

Selecting the authored light exposed a stale modelling target: Slab resolved every child node to its ancestor solid, leaving the previous solid and face selection active. The fix restricts native selection ownership to solids and their generated internal nodes. Authored children clear Slab's target and remain under Godot's control. The regression also verifies that a modelling command cannot alter the old solid and that reselecting the solid restores editing.

After restarting Godot, the author selected one PowerHouse face, then its OmniLight3D child in the Scene tree. Slab displayed `No solid selected.` and disabled face commands. Clicking the disabled Subdivide control left the scene clean. Reselecting PowerHouse prompted for a face; clicking a face restored its commands. The full verifier, including `native_selection_scope_smoke`, passed in `/tmp/slab-gable-selection-verify.log`.
