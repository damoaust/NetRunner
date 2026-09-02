# Design: Up/Down Floor Travel Within a Datafort (Single-File Approach)

## Background

In CP2020, dataforts are 3D structures with multiple floors/levels. The netrunner can move vertically between floors via elevator/shaft tiles. The current game is a flat 2D grid with no concept of vertical levels. Cross-datafort travel already exists via LDL links (ENTRY tiles with `is_ldl_link=true`, `target_subnet_path`, `target_entry_coord`). `load_subnet()` loads a different `.tres` layout and places the runner at the entry coord; trace is preserved.

## Goal

Support multiple floors within a **single `.tres` file** so the designer doesn't manage separate files per floor. Floors live inside one `CP2020DatafortLayout` resource.

---

## Approach: `floors` Array on `CP2020DatafortLayout`

Instead of one `grid_tiles` dict per datafort, the layout holds an array of `CP2020Floor` resources (one per floor). The runner, renderer, and designer track `current_floor` and switch between floors within the same loaded layout — **no `load_subnet` call for up/down travel**.

### 1. Data model

**New `CP2020Floor` Resource (`scripts/resources/CP2020Floor.gd`):**
- A thin Resource wrapper around one floor's tile dict, giving us type safety on the outer collection (see "Why not `Dictionary`" below).
- `@export var tiles: Dictionary = {}` — Vector2i / `"x,y"` -> `CP2020TileData` (identical structure to today's `grid_tiles`).
- `@export var floor_name: String = ""` — optional human-readable label (e.g. "B2", "R&D Wing") for the floor-transition HUD flash and designer panel.
- `@export var floor_index: int = 0` — the floor's position in the array (redundant with array position, but stored so it survives reordering in the designer and is available without a lookup).

**`CP2020DatafortLayout.gd`:**
- Add `@export var floors: Array[CP2020Floor] = []` — typed array; floor 0 = `floors[0]`, floor 1 = `floors[1]`, etc. Array index IS the floor index (no separate int keys to serialise).
- Keep `grid_tiles` for backward compat: on load, if `floors` is empty and `grid_tiles` has content, migrate by wrapping: `var f := CP2020Floor.new(); f.tiles = grid_tiles; f.floor_index = 0; floors = [f]`. New layouts always use `floors`.
- `floor_count` is derived: `floors.size()` — no stored field needed.
- Add `var current_floor: int = 0` (runtime only, not exported — set by game session / designer).
- `get_tile(coord: Vector2i, floor: int)` — **floor is REQUIRED (no default)**. Routes to `floors[floor].tiles` via the existing string-key-tolerant lookup. Every caller must pass the floor explicitly, making floor awareness impossible to silently forget.
- `set_tile(coord, tile, floor: int)` and `erase_tile(coord, floor: int)` — same routing, floor required.
- `get_floor_tiles(floor: int) -> Dictionary` — returns `floors[floor].tiles`.
- `get_current_floor_tiles() -> Dictionary` — convenience: `get_floor_tiles(current_floor)`. Use this for the common "current floor" case so call sites read clearly.

**Why `Array[CP2020Floor]` instead of `Dictionary`:**
- `@export Dictionary` values are untyped Variants — a `Dictionary` of `Dictionary`s loses all type hints, doubling the surface for the string-key bugs that already plague `grid_tiles`.
- `Array[CP2020Floor]` is fully typed: the editor, serialiser, and GDScript all know each element is a `CP2020Floor`. Floor index = array position — no int-key serialisation fragility.
- The inner `tiles` dict on `CP2020Floor` keeps the same Vector2i / `"x,y"` key structure as today's `grid_tiles`, so the existing `get_tile` string-key-tolerant lookup is reused unchanged.

**Why `floor` is required on `get_tile` (no -1 default):**
- The original plan had `floor = -1` meaning "use `current_floor`". This creates hidden coupling: dozens of call sites across 7+ files would silently depend on `current_floor` being in sync. One stale assignment and the wrong floor's tiles are read with no error.
- Making `floor` required forces every caller to be explicit. Callers that mean "current floor" pass `layout.current_floor` or use `get_current_floor_tiles()` — the dependency is visible at the call site, not hidden behind a magic -1.

**`CP2020TileData.gd`:**
- Add up/down link fields:
  - `@export var can_go_up: bool = false`
  - `@export var up_target_entry_coord: Vector2i = Vector2i(-1, -1)` — arrival coord on the floor above (same `.tres`, just a different floor index)
  - `@export var can_go_down: bool = false`
  - `@export var down_target_entry_coord: Vector2i = Vector2i(-1, -1)` — arrival coord on the floor below
- No `target_subnet_path` for up/down — the destination is a floor index within the same layout, not a separate file.
- Existing horizontal LDL fields (`is_ldl_link`, `target_subnet_path`, `target_entry_coord`) stay unchanged for cross-datafort travel.

### 2. Game session (`cp2020_game_session.gd`)
- Add `var current_floor: int = 0` (or read from `layout.current_floor`).
- **Up/down travel** does NOT call `load_subnet`. Instead:
  - `"travel_up"`: target floor = `current_floor + 1`, target coord = `tile.up_target_entry_coord`.
  - `"travel_down"`: target floor = `current_floor - 1`, target coord = `tile.down_target_entry_coord`.
  - **Blocking check** (extended for vertical structure): before switching, look up the tile at the target coord on the target floor. If:
    - The floor doesn't exist (out of range) → block: "No floor above/below."
    - The target coord is out of bounds → block: "Vertical shaft leads nowhere."
    - The destination tile is a **DATAWALL** → block: "Datawall blocks vertical movement."
    - The destination tile is a locked **CODE_GATE** → block: "Locked Code Gate blocks vertical movement."
    - The destination is a non-blocking tile (EMPTY or any entity tile) → allow.
  - If not blocked: `current_floor` = target floor, `netrunner.current_position` = target coord, update `layout.current_floor`, redraw.
  - Fog: each floor has its own explored/visible state (already per-tile). No fog reset needed — the floor's tiles retain their state. Going back to a previously visited floor shows it as explored.
  - Trace: preserved (runner never left the datafort).
  - Board renderer: told to render `floors[current_floor]` only.
- `load_subnet` is only used for horizontal LDL (cross-datafort) and initial dive — unchanged.
- A helper `_can_travel_vertical(target_floor: int, target_coord: Vector2i) -> bool` centralises the blocking check (reusable by both the game session and the interaction handler).
- **Keyboard shortcuts for vertical travel**: in `_input`, alongside the existing WASD handling, add **Q = go up** and **E = go down** (Q sits above E on the keyboard, mirroring up/down). When pressed:
  - Look up the tile at `netrunner.current_position` on `current_floor`.
  - If the tile has `can_go_up` (Q) or `can_go_down` (E), call `travel_up` / `travel_down`.
  - If the tile doesn't allow it, or the destination is blocked (`_can_travel_vertical` returns false), log a brief "Can't go up/down from here." — same pattern as the "Movement blocked" messages.
  - This makes up/down consistent with WASD horizontal movement — the player doesn't need to right-click to travel vertically. The right-click menu remains for discovery (greyed-out items show *why* travel is blocked).
- **Fog/runtime-state reset on `load_subnet` must iterate ALL floors**, not just `grid_tiles`. The current reset loop walks `current_layout.grid_tiles.keys()`; with `floors` populated it must walk every `CP2020Floor.tiles` dict so non-floor-0 tiles get their `is_explored`/`is_visible`/`cpu_crashed_turns`/`is_looted`/`copied_file_paths`/`worm_*` fields reset (ResourceLoader returns a cached instance).

### 2b. ICE / NPC spawn lifecycle (lazy, floor-gated)

The current `spawn_black_ice` / `spawn_npcs` / `spawn_datafort` iterate `grid_tiles` and spawn every entity at once on `load_subnet`. With multiple floors this needs explicit lifecycle management:

- **Lazy per-floor spawning**: `spawn_black_ice` / `spawn_npcs` / `spawn_datafort` are refactored to spawn a **single floor**'s entities. On `load_subnet`, only floor 0 is spawned (existing behaviour, just scoped to `floors[0]`).
- **On floor switch** (`travel_up` / `travel_down`): call `_spawn_floor_entities(target_floor)` if that floor hasn't been spawned yet. Track spawned floors in `_spawned_floors: Array[int]` to avoid re-spawning.
- **Entities persist (dormant) when the runner leaves their floor**: they are NOT despawned. This preserves their state (integrity, position, alarm status) if the runner returns.
- **Each ICE / NPC node stores `home_floor: int`** (set at spawn). The board renderer and turn processing use this to gate activity:
  - `take_ice_turn` / NPC AI: skip any entity where `home_floor != current_floor` (dormant — no movement, no attacks, no detection).
  - Board renderer: only draws entities on `current_floor` (off-floor entities are invisible to the player — they're on a different level).
- This means a floor's ICE is only active while the runner is on that floor. Fleeing to another floor breaks pursuit (a deliberate simplification — see "Design decision: floors as escape hatches" below).
- `_spawn_floor_entities(floor: int)` iterates `floors[floor].tiles`, creates ICE/NPC/CPU nodes for that floor's entity tiles, sets `home_floor = floor` on each, and appends to the shared `ice_nodes` / `npc_nodes` arrays.

### 3. Board renderer (`cp2020_board_renderer.gd`)
- Render only `layout.floors[layout.current_floor].tiles` tiles. The renderer iterates the current floor's tile dict, not the flat `grid_tiles`.
- The early-bail guard `if not layout.grid_tiles: return` must change to check the current floor's dict (`floors[current_floor].tiles`) instead — newly authored multi-floor layouts leave `grid_tiles` empty, so the old guard would draw nothing.
- Visibility/fog: per-tile as today, just scoped to the current floor.
- ICE/NPC entity drawing: gate by `home_floor == current_floor` — off-floor entities are not drawn (they're on a different level).
- **Current-floor HUD**: draw a label in the header area (top of the board, within the `grid_offset_y` band) showing the current floor: `"Floor {current_floor+1}/{floors.size()}"` plus the `floor_name` if set (e.g. `"Floor 2/5 — R&D Wing"`). This gives the player constant spatial context without a minimap.
- **Floor-transition flash**: on floor switch, the game session calls a new `board_renderer.flash_floor_label(floor_name)` which draws a large centered label (e.g. `"FLOOR 2 — R&D Wing"`) that fades out over ~1.5 seconds via a ` Tween`. This makes the "instant" switch feel like a deliberate transition rather than a jarring content swap. If no `floor_name` is set, fall back to `"FLOOR {n}"`.
- ENTRY tile drawing checks `can_go_up` / `can_go_down`. To avoid clutter at 40px, the indicator is split into a **persistent frame colour** (always visible) and a **small corner glyph** (compact, not centered):
  - Up only -> teal frame + small `↑` in the **top-left corner** (8px font)
  - Down only -> purple frame + small `↓` in the **bottom-left corner** (8px font)
  - Both -> split teal/purple frame (top half teal, bottom half purple) + `↑` top-left AND `↓` bottom-left (not stacked/centered — they sit in opposite corners)
  - Horizontal LDL -> blue frame + "L" (unchanged)
  - Corner glyphs are compact enough to coexist with the ENTRY fill and primary-entry mark without overlap. The frame colour is the primary at-a-glance indicator; the glyphs confirm direction on closer look.
- Player sees arrows on visible up/down tiles without right-clicking.

### 4. Netrunner (`cp2020_netrunner.gd`)
- Add `var current_floor: int = 0`.
- `initialize` sets `current_floor = 0` and resolves the arrival ENTRY from `floors[0]`.
- Movement (`move()`) stays 2D — up/down is not keyboard movement; it is a right-click action handled by the game session. EMPTY remains the walkable default; no change to the `move()` blocking rules.
- `current_layout.get_tile(target_pos, current_floor)` calls must pass `current_floor` explicitly (no -1 default — see §1). Alternatively use `current_layout.get_current_floor_tiles()` for the common case.

### 5. Interaction handler (`cp2020_interaction_handler.gd`)
- When building the menu for an ENTRY/link tile:
  - Horizontal LDL -> "Travel to %s" (id 3000, existing)
  - `can_go_up` -> "Go Up" (new id **3002**) — **disabled/greyed** if the floor above or destination tile is blocked (datawall/locked gate/out of bounds).
  - `can_go_down` -> "Go Down" (new id **3003**) — **disabled/greyed** if the floor below or destination tile is blocked.
  - Both -> offer both menu items (each independently enabled/disabled).
- Menu id collision ordering: 3000/3001 (existing) -> 3002/3003 (new, exact-match checks like 3000/3001) -> 4000 (NPC talk) -> 2000+i -> ...
- The handler calls the game session's `_can_travel_vertical` helper (or a shared utility) to pre-check and grey out blocked directions so the player sees at a glance whether up/down is available.

### 6. Designer (`cp2020_datafort_designer.gd` + `cp2020_datafort_grid_canvas.gd` + `.tscn`)
- Add a **Floor SpinBox** to the SettingsRow (next to Columns/Rows/Apply). Changing it switches which floor the canvas paints. Range 0..`floors.size()-1`.
- Add **Add Floor** and **Remove Floor** buttons. Add appends a new `CP2020Floor` to `floors`; Remove removes the current (with a guard against removing the last floor).
- Add a **Floor Name** text field next to the SpinBox so the designer can label each floor (stored on `CP2020Floor.floor_name`).
- Two new toolbar buttons: **Up** and **Down** (paint ENTRY tiles with `can_go_up`/`can_go_down`).
- The Link Editor panel shows:
  - Horizontal LDL section (existing target_subnet_path + target_entry_coord) — for `is_ldl_link` tiles.
  - Up section: `up_target_entry_coord` X/Y SpinBoxes (the arrival coord on the floor above — no file browse needed since it is the same layout).
  - Down section: `down_target_entry_coord` X/Y SpinBoxes.
- Grid canvas `_draw` renders only `floors[current_floor].tiles` and draws up/down glyphs matching the board renderer.
- `fill_empty_tiles` fills the current floor only.
- Save/Load: saves the entire `floors` array in one `.tres` file.

### 7. ICE / NPC pathfinding
- Black ICE and NPC netrunners operate on the **current floor only**. They do not follow the runner between floors — see §2b for the lazy spawn + dormancy lifecycle.
- `cp2020_blackice._update_obstacles` and AStarGrid2D use `floors[current_floor].tiles`.
- Each ICE/NPC node has `home_floor: int`; turn processing and rendering are gated by `home_floor == current_floor`.

---

## What is NOT needed
- **No separate .tres files per floor** — all floors in one layout resource.
- **No `load_subnet` for up/down** — instant floor switch within the same loaded layout.
- **No new tile type** — ENTRY + `can_go_up`/`can_go_down` flags. EMPTY remains the walkable default.
- **No pathfinding across floors** — adversaries stay on their floor.
- **No fog reset on floor change** — each floor retains its own fog state.

## Migration / backward compat
- Existing single-floor `.tres` files: on load, if `floors` is empty and `grid_tiles` has content, auto-migrate by wrapping: `var f := CP2020Floor.new(); f.tiles = grid_tiles; f.floor_index = 0; floors = [f]`. Existing layouts work as floor 0 with no changes.
- `get_tile` / `set_tile` / `erase_tile` require a `floor: int` parameter (no -1 default). All existing call sites must be updated to pass `layout.current_floor` (or the appropriate floor index) explicitly — a mechanical one-time pass across the codebase. This is intentional: it makes floor awareness impossible to silently forget.

## Visual indicator summary
| Tile flags | Board renderer | Designer canvas |
|-----------|---------------|-----------------|
| Horizontal LDL | Blue frame + "L" | Blue frame + "L" |
| Up only | Teal frame + up arrow | Teal frame + up arrow |
| Down only | Purple frame + down arrow | Purple frame + down arrow |
| Up + Down | Split teal/purple + both arrows | Split teal/purple + both arrows |

## Files to change
1. `scripts/resources/CP2020Floor.gd` — **NEW** Resource: `tiles: Dictionary`, `floor_name: String`, `floor_index: int`
2. `scripts/resources/CP2020DatafortLayout.gd` — `floors: Array[CP2020Floor]`, `current_floor`, `get_tile`/`set_tile`/`erase_tile` with required `floor` param, `get_current_floor_tiles()`, migration
3. `scripts/resources/CP2020TileData.gd` — `can_go_up`/`can_go_down` + `up_target_entry_coord`/`down_target_entry_coord`
4. `scripts/resources/cp2020_board_renderer.gd` — render current floor only, fix early-bail guard, up/down glyphs, gate entity drawing by `home_floor`
5. `scripts/resources/cp2020_game_session.gd` — `current_floor`, `travel_up`/`travel_down` handlers, fog-reset loop iterates all floors, lazy `_spawn_floor_entities()`, `_spawned_floors` tracking, gate ICE/NPC turn processing by `home_floor`
6. `scripts/resources/cp2020_netrunner.gd` — `current_floor`, `get_tile` calls pass floor explicitly
7. `scripts/resources/cp2020_interaction_handler.gd` — "Go Up"/"Go Down" menu items (ids 3002/3003)
8. `scripts/resources/cp2020_datafort_grid_canvas.gd` — render current floor, up/down glyphs, floor-aware `fill_empty_tiles`
9. `scripts/resources/cp2020_datafort_designer.gd` — Floor SpinBox, Add/Remove Floor, Up/Down buttons, link editor up/down sections, floor name field
10. `scenes/ui/CP2020DesignerCanvas.tscn` — Floor SpinBox, Add/Remove Floor buttons, Up/Down toolbar buttons, link panel up/down fields, floor name field
11. `scripts/resources/cp2020_blackice.gd` — `home_floor: int`, `_update_obstacles` uses current floor tiles, gate `take_ice_turn` by `home_floor`
12. `scripts/resources/cp2020_npc_netrunner.gd` — `home_floor: int`, pathfinding uses current floor tiles, gate AI by `home_floor`

## Decisions resolved
- **Single file per datafort**: All floors in one `.tres` via an `Array[CP2020Floor]` on `CP2020DatafortLayout` (typed, not a Dictionary — see §1).
- **Floor param required**: `get_tile` / `set_tile` / `erase_tile` take a required `floor: int` — no -1 default. Eliminates implicit `current_floor` coupling.
- **Lazy ICE/NPC spawning**: Floor 0 spawned on `load_subnet`; other floors spawned on first arrival. Entities persist dormant (gated by `home_floor`) when the runner leaves. See §2b.
- **Keyboard vertical travel**: Q = go up, E = go down (consistent with WASD horizontal). Right-click menu stays for discovery + blocking feedback. See §2.
- **Floor-transition feedback**: HUD floor label (persistent) + centered flash on switch (fades over ~1.5s). See §3.
- **Glyph layout**: Corner glyphs (not centered/stacked) + frame colour as primary indicator — avoids 40px clutter. See §3.
- **Floor labeling**: `CP2020Floor.floor_name` + persistent HUD label ("Floor 2/5 — R&D Wing"). No minimap for now — future work if multi-floor orientation becomes a problem.
- **Toolbar**: Separate Up and Down toolbar buttons.
- **Glyphs**: Simple text glyphs (up/down/both via `draw_string`).
- **Both directions**: A tile can have `can_go_up` AND `can_go_down` — independent target coords for each floor.
- **No file loading for up/down**: Instant floor switch within the same layout — no `load_subnet`, no loading screen.
- **No FLOOR tile type**: EMPTY remains the walkable default. Vertical blocking checks only DATAWALL and locked CODE_GATE at the destination.
- **Design decision: floors as escape hatches**: ICE/NPCs do NOT follow the runner between floors. Fleeing to another floor breaks pursuit. This is a deliberate simplification of CP2020 (where Black ICE can follow via elevators). **Future option**: a per-program `follows_across_floors: bool` flag could let specific tracker ICE (Hellhound, Flatline) pursue across floors — designers could mark certain ICE as homing. Not in scope for v1; flagged for revisit if floors feel too safe.

---

## Implementation Status (COMPLETE — one deviation)

Everything in §1–§7 shipped on `feature/2.5d-visual-upgrade`, verified against code: `CP2020Floor` + typed `floors[]` with lazy legacy migration; floor-required `get_tile`/`set_tile`/`erase_tile`; `can_go_up`/`can_go_down` + target coords on `CP2020TileData`; `travel_up`/`travel_down` + `_can_travel_vertical` in the game session; **Q = up / E = down** keyboard travel; current-floor-only rendering with the early-bail guard checking the current floor's dict; persistent HUD floor label ("Floor n/N [— name]") + fade-out transition flash; ENTRY up/down glyphs on both the board renderer and designer canvas; "Go Up"/"Go Down" menu ids 3002/3003 with blocked directions greyed out; designer Floor SpinBox / Add/Remove Floor / floor-name field + link-editor up/down coordinates; `home_floor` gating of ICE/NPC/rezzed-program turns, line-of-sight, and drawing; fog + runtime-state reset iterating **all** floors; `CP2020DatafortLayout.parse_coord()` static helper.

Deviations from this document:
- **§2b lazy per-floor spawning was not built.** There is no `_spawned_floors` tracking or `_spawn_floor_entities()`. Instead `spawn_black_ice` / `spawn_npcs` / `spawn_datafort` spawn **every floor's entities up front** on `load_subnet`, and activity/rendering are gated by `home_floor` (off-floor entities exist but are dormant and invisible). Same player-visible behaviour as designed; different mechanism and memory profile.
- `flash_floor_label()` takes no argument — it reads the current floor's `floor_name` from the layout itself (§3 sketched a `floor_name` parameter).
- The **`follows_across_floors`** homing-ICE flag (see "Design decision: floors as escape hatches" above) remains unbuilt — tracked as a future item in `TODO.md`.