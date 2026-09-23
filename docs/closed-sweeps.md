# Closed-path sweeps

In Create, choose **Curve Sweep** and enable **Closed path** to create an editable solid around a rectangular loop. Width and Height set the profile. Depth sets the path length; the closed preset enlarges the loop when needed to leave room for the profile.

For a custom path, add a **SlabSweep** node. Set its Points and Profile in the Inspector, then enable Closed. Move the path handles in the 3D viewport to adjust points on their local horizontal planes. Handle drags support Undo, Redo and cancellation. The gizmo draws the final segment back to the first point when Closed is enabled.

Closed paths need at least three distinct points. A final point equal to the first is accepted, but does not create an extra ring. Open paths need two points and receive end caps. Vertical and nonplanar paths are supported. Profile frames follow the path through parallel transport; a closed loop distributes its residual frame rotation along its length. The closing segment shares the first ring's vertices and edges, with no overlapping caps.

The kernel rejects duplicate interior points, reversals, degenerate profiles and solids that fail its normal manifold, intersection or positive-volume checks. A profile that is too large for a bend or for the distance between path segments may be refused. SlabSweep shows a configuration warning and retains its last valid mesh and collision when an edit is invalid. Correct the points or reduce the profile to resume rebuilding.

SlabSweep remains a parametric path node. Curve Sweep from Create produces a SlabSolid with editable mesh topology. Both use the same kernel construction. Frames and faces are quantized to the kernel lattice; curved walls use planar triangles. This does not generate a packed UV atlas or apply smooth shading automatically.

Regression coverage lives in `tests/test_kernel_prims.cpp` and `project/tests/sweep_smoke.gd`. The kernel cases check shared closure, torus topology, nonplanar/reversed loops, vertical paths, repeated endpoints and atomic refusal. The node smoke checks the Closed toggle, collision, in-memory scene reload, recovery after a refused edit and the Create preset.

## Native editor acceptance

1. Choose Curve Sweep in Create. Toggle Closed path, preview and place the default loop. Check its open centre and absence of end caps. Turn the option off and verify the capped open preset.
2. Add a SlabSweep node with Profile `(0.5, 1)`, Closed enabled, and Points `(-2,0,-2)`, `(2,0,-2)`, `(2,0,2)`, `(-2,0,2)`. Check the closing gizmo segment and absence of configuration warnings.
3. Drag a path handle. Undo and Redo must restore and reapply the point positions. Cancel another drag with Escape and verify restoration.
4. Rotate the node 30 degrees around X and drag a handle. Its local Y must stay fixed while the handle follows the tilted editing plane.
5. Reduce the closed path to two points, then try a profile wider than the loop. Each invalid edit must show a warning and preserve the previous mesh and collision. Undo the edit and verify recovery.
6. Save and reopen the scene. Confirm the Closed value, path points and rebuilt loop remain intact.

These steps are a manual checklist, not a claim that a native editor run has already passed.
