# Signal Foundry player

Reusable first-person controller. **Do not generate level layout here.** Instance this packed scene into `signal_foundry.tscn` in the editor and place the origin on a walkable floor.

**Resource:** `res://demo/signal_foundry/gameplay/player.tscn`

## Gameplay pieces

Instance these scenes wherever they make sense in the editor. Their origins sit on the floor and they need no signal wiring:

| Scene | Behavior |
| --- | --- |
| `res://demo/signal_foundry/gameplay/energy_cell.tscn` | Floating cyan pickup. Each instance adds one energy cell, flashes HUD feedback, then disappears. |
| `res://demo/signal_foundry/gameplay/checkpoint_beacon.tscn` | Orange beacon that turns green on contact. R and fall recovery subsequently spawn 1.5 m along its local −Z, facing local −Z. Rotate the beacon so its blue −Z arrow points in the desired departure direction. Set `checkpoint_title` and `local_respawn_offset` in the Inspector as needed. |
| `res://demo/signal_foundry/gameplay/exit_beacon.tscn` | Red exit field that reports missing cells, or latches green and emits `exit_completed(player)` once powered. Its `required_cells` Inspector value defaults to 3. |
| `res://demo/signal_foundry/gameplay/hazard_reset.tscn` | Pulsing red strip that returns the player to the active checkpoint. Set `footprint_size` in the Inspector for its X/Z coverage; keep the root scale at one. Its shallow trigger matches the visible pulse so players can jump over it. |
| `res://demo/signal_foundry/gameplay/moving_platform.tscn` | Physics-safe shuttle. Add hand-authored SlabSolid nodes below `PlaceSlabChildrenHere`, then set `local_travel`, `travel_duration`, and `endpoint_pause`. Its lower collision priority keeps a descending carrier from forcing the player through a static floor. |

The compact player HUD shows collected energy, the active checkpoint, and short interaction notices. Progress is session-local and requires no autoload or level script.

For spinning fans, gears, and machinery, add a Node3D parent, attach `res://demo/signal_foundry/gameplay/rotating_machinery.gd`, then place authored SlabSolid children beneath it. Choose the axis and speed in the Inspector. Use this for machinery and scenery; use the moving-platform scene when the object must carry the player.

Use Godot's `AnimationPlayer` for unique timing or multi-part sequences: add it beside the animated Node3D, key that node's transform, and enable looping on the animation. For a custom platform route, animate the `MovingPlatform` root itself and turn off `shuttle_enabled`; keeping the root as an `AnimatableBody3D` preserves moving-platform physics. The helper scripts cover only constant rotation and a two-endpoint shuttle.

## Controls

| Input | Action |
| --- | --- |
| W A S D | Move (physical keys). Hold as usual; auto-run does not replace WASD. |
| T | Toggle auto-run: walk forward at normal speed without holding W. Another T, S, Esc, or R stops it. Made for brief computer-use key taps so a run-up jump does not need W held. |
| Q / E | Turn 15° left / right per tap (keyboard-only alignment; holding does not keep spinning) |
| Mouse | Look while captured |
| Arrow keys | Look (computer-use / no mouse) |
| Numpad 8 2 4 6 | Look (up / down / left / right) |
| Space | Jump |
| Shift | Sprint (×1.45). Auto-run stays at walk speed unless Shift is held. |
| Esc | Release mouse and stop auto-run; keyboard move/look still work |
| Left click | Recapture mouse |
| R | Return to the active checkpoint, or the initial spawn before activating a checkpoint; also stops auto-run |
| F3 | Toggle a passive diagnostic overlay with feet XYZ, yaw, grounded state, floor collider/platform, velocity, platform velocity, and auto-run state |

Falls below y = −6 also return to the active checkpoint. Collected cells survive resets within the current play session.

## Default dimensions

Copied from Relay Yard’s capsule so 0.25 m Slab stair risers stay walkable.

| Part | Value |
| --- | --- |
| Origin | Feet (place on the floor) |
| Capsule radius | 0.3 m |
| Capsule height | 1.7 m (shape centred at y = 0.85) |
| Eye / Camera3D | (0, 1.55, 0), FOV 78°, current |
| Walk / sprint / jump | 5 m/s, ×1.45, 6 m/s |
| Gravity | 19 m/s² |
| Coyote / jump buffer | 0.12 s each |
| Step-up | 0.28 m (clears a 0.25 m riser; no hidden ramp) |
| Floor snap | 0.35 m |

Headless check (does not load or write `signal_foundry.tscn`):

```sh
scripts/godot --headless --path project --script res://demo/signal_foundry/gameplay/check_player.gd
scripts/godot --headless --path project --script res://demo/signal_foundry/gameplay/check_interactions.gd
scripts/godot --headless --path project --script res://demo/signal_foundry/gameplay/check_animations.gd
```
