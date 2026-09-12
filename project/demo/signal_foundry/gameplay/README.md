# Signal Foundry player

Reusable first-person controller. **Do not generate level layout here.** Instance this packed scene into `signal_foundry.tscn` in the editor and place the origin on a walkable floor.

**Resource:** `res://demo/signal_foundry/gameplay/player.tscn`

## Controls

| Input | Action |
| --- | --- |
| W A S D | Move (physical keys) |
| Mouse | Look while captured |
| Arrow keys | Look (computer-use / no mouse) |
| Numpad 8 2 4 6 | Look (up / down / left / right) |
| Space | Jump |
| Shift | Sprint (×1.45) |
| Esc | Release mouse; keyboard move/look still work |
| Left click | Recapture mouse |
| R | Reset to this instance’s transform at `_ready` |

Falls below y = −6 also reset to that spawn transform.

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
```
