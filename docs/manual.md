# Iron Tide · 钢铁洪流

Iron Tide is a Battle City style tank game. Each game runs an independent
headless Godot world that owns the rules, a fixed simulation clock and the
pixel-art renderer; the ETAF application owns the stage select, battle panel,
map editor, settings, dialogs and file prompts. Requiring GameKit never loads
or launches this game.

```elisp
(add-to-list 'load-path "/path/to/etaf-games/etaf-tanks")
(require 'etaf-tanks)
(etaf-tanks-open)
```

Install ETAF, etaf-ui and GameKit, including its Godot runtime, before opening.
The bundled project is `native/godot/`, resolved relative to this package's own
entry. The [entry Commentary](../etaf-tanks.el) documents the supported Lisp API.

## Rules

Defend the eagle base at the bottom of the field and destroy every enemy tank
of the stage. The battle is lost when an enemy shell (or your own) hits the
base or when your last tank is destroyed. Enemies enter in batches from the
spawn points at the top; only a limited number are on the field at once. The
battle panel lists the tanks still waiting, your lives, score and firepower.

| Enemy | Behaviour | Points |
| --- | --- | --- |
| Basic | Slow | 100 |
| Fast | Twice as fast | 200 |
| Power | Fires fast shells | 300 |
| Armored | Takes four hits; its colour shows the remaining armour | 400 |

Enemies that flash red drop a bonus when destroyed (500 points when collected):
the helmet shields your tank for 10 seconds, the clock freezes enemies for 10
seconds, the shovel walls the base with steel for 20 seconds, the star upgrades
your cannon, the grenade destroys every enemy on the field and the tank adds a
life. Each star makes shells faster, then allows two shells in flight, then
breaks steel; losing a tank resets the cannon. Every 20,000 points add a life.
A new tank is shielded for 3 seconds.

A shell chips one quarter-block layer of brick across a tank's width; a
three-star shell cuts two layers and also breaks steel. Water blocks tanks but
not shells, forest hides tanks beneath it and ice makes tanks slide.

Difficulty is easy (five lives, three enemies on the field), normal (three
lives, four enemies) or hard (six enemies, faster spawns and fire, more armored
upgrades). Later stages spawn and fire faster and put one more enemy on the
field from stage 10. Clearing stage 20 continues with stage 1 at a higher loop
level. Lives, score and firepower carry into the next stage; retrying restores
the stage's opening resources.

## Keys

| Screen | Key | Action |
| --- | --- | --- |
| Menu | Arrows, Return, G | Choose a stage; start it |
| Menu | E, N, D | Edit the selected map, create a new map, cycle difficulty |
| Battle | Arrow keys | Drive |
| Battle | Shift+arrow | Turn in place |
| Battle | F, X | Fire; stop driving |
| Battle | P, R, N, M | Pause or resume, retry the stage, next stage, return |
| Battle | C-s, C-o | Save or load a snapshot through a file prompt |
| Editor | Arrows, 1–9 | Move the cursor; choose a brush |
| Editor | F, D, B, U | Paint, toggle continuous painting, brush size, undo |
| Editor | P, C-s, M | Test-play, save the map, return to the menu |
| Any | S, T, F1, Q | Settings, light/dark palette, rules and keys, close |

Every key also has a button. Help, settings and file prompts pause a running
battle first and dismissing them does not resume it. The game pauses when its
buffer stops being the selected window's buffer. Retrying or leaving a running
battle asks for confirmation; a paused battle is left immediately.

## Settings

`S` opens the settings, which take effect immediately: game speed and the
player's tank speed (50–200 %), arrow-key sensitivity (follow the system key
repeat, sensitive, standard or smooth), driving mode (drive while an arrow is
held, or keep driving after one press until X or Shift+arrow) and the frame
rate (30 or 60). *Save as default* stores them, with the difficulty, through
Customize in the `etaf-tanks-*` variables listed in the Commentary.

## Maps and the editor

The campaign tab lists the twenty built-in stages with a ✓ on the ones cleared;
`etaf-tanks-progress-file` records cleared stages and best scores per
difficulty. The custom tab lists the maps in `etaf-tanks-map-directory`;
*Import* opens any map file in the editor.

A map is a UTF-8 text file:

```
name: Two Rivers
enemies: 14 4 2 0
map:
EE..........EE..........EE
...
```

`name:` is optional (1–24 characters). `enemies:` gives the basic, fast, power
and armored counts (1–60 in total). The `map:` section has equal rows of 12–52
columns by 12–40 rows; each character is a quarter of a tank: `.` ground,
`#` brick, `@` steel, `~` water, `*` forest and `=` ice. 2×2 groups mark the
base `H` (exactly one), the player start `P` (exactly one) and one to four
enemy spawns `E`. Lines beginning with `;` are comments; files over 64 KiB are
rejected. The menu preview reports a map's defects before it can be played.

The editor paints with 1×1 or 2×2 brushes, undoes strokes, edits the name and
enemy counts, test-plays the draft (M returns to the editor) and saves into the
map directory, asking before overwriting a file.

## Snapshots and programmatic callers

A definition can be started with `etaf-gamekit-start etaf-tanks-game`; the
caller owns its buffer and uses `etaf-gamekit-close` to release it. Read the
current state with `etaf-gamekit-observation`, or `etaf-gamekit-view` in
reactive views. Wait for `etaf-gamekit-status` to report `ready` before the
first command. Commands go through `etaf-gamekit-action`:

- `begin` takes a map text `:map` and optional `:stage` (1–999),
  `:difficulty` (`"easy"`, `"normal"`, `"hard"`), `:seed` and carried
  `:lives`, `:score`, `:star` and `:next_life`.
- `next` takes the following `:map` and `:stage` after a cleared stage and
  carries lives, score and firepower; `restart` retries the current stage
  with its opening resources.
- `menu` previews an optional `:map`; `edit` previews `:map` with an editor
  cursor at `:x`, `:y` and brush `:size` (1 or 2).
- `drive` and `aim` take `:direction` (`"n"`, `"e"`, `"s"` or `"w"`); `fire`
  and `stop` take no arguments.
- `pause` toggles a running battle, or sets `:paused` to `t` or `:false`.
- `settings` takes `:speed`, `:player_speed`, `:hold`, `:repeat`, `:latch` and
  `:frame_rate`; `display` takes the frame `:directory` and `:theme`.
- `save` and `load` take an explicit `:path` string.

The observation reports `phase` (`menu`, `edit`, `intro`, `play`, `cleared`
or `over`), `paused`, the map `size`, the battle `hud`, the player `actor` and
the end-of-stage `tally`; without a frame directory it also reports the
`world` grid of units, shells and bonuses. A rejected command reports its
reason through `etaf-gamekit-last-error` and leaves the state unchanged.

Snapshots are written only to explicit paths, atomically. Loading validates the
complete file against its map before replacing the battle, resumes paused and
clears in-flight shells and spawns. Malformed files leave the current battle
untouched. Closing never saves.

## Display

On graphic displays Godot renders each frame at the original console
resolution (8-pixel blocks) and Emacs scales it by a whole factor without
smoothing, half steps on high-density screens. The board takes the largest
scale that fits; in battle a compact panel moves below the board when that
allows a larger scale. Below the smallest scale the board stays at scale 1
and the window clips it. Palette changes affect presentation only and never
restart or pause the battle. Text displays show a two-character-per-block
grid instead.

Correctness lives in `tests/acceptance.json`, which runs the real Godot backend
through public game and UI interfaces. `scripts/etaf-tanks-gui-scenarios.el`
drives the application in a dedicated graphical frame with exactly one visible
frame: load it with `scripts/emacs-gui-verifier.el` from ETAF and call
`etaf-tanks-gui-run` with an evidence directory. It covers both palettes
across the viewport matrix, battle keys, snapshot prompts, the editor, a
cleared stage and a defeat.

The workspace performance driver runs `benchmarks/performance-scenarios.el`.
The `etaf-tanks.keys.*` workloads measure driving, aiming, firing and
driving while firing on the largest stage on hard: native key input, the
Godot response and the changed board image offered to redisplay. Theme, pause
and resize workloads are measured separately. Background GUI results do not
certify foreground operating-system input latency.
