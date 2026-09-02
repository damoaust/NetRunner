# NetRunner V0.006 — Code Review Findings (DRAFT)

> Auto-generated comprehensive code review. Findings are categorized by area and rated by severity (HIGH / MEDIUM / LOW).
>
> **Status (triaged on `feature/2.5d-visual-upgrade`):** this file is now a historical snapshot, not a worklist. The triage table under §9 maps each priority to verified-fixed / still-open; remaining open items are tracked as unchecked boxes in `TODO.md`.

---

## 1. Procedural Generation → Scene Tree Opportunities

### 1.1 `_create_datafort_font()` duplicated across two files — MEDIUM
**Files:** `cp2020_city_grid.gd:72`, `cp2020_city_grid_renderer.gd:63`

Both the runtime city grid node and the @tool designer renderer contain identical `_create_datafort_font()` methods that load `webdings.ttf`. This is duplicated code that should be:
- Extracted to a shared autoload or static utility, OR
- Replaced with a pre-saved `FontFile` `.tres` resource referenced from both scenes (so the font is editable in the inspector).

**Fix:** Create a `data/webdings_font.tres` (FontFile resource) or a shared `cp2020_font_utils.gd` static class.

### 1.2 `tools/generate_theme.gd` — one-shot theme generator — LOW
Generates `themes/cyberpunk_theme.tres` procedurally. This is a one-shot build tool (not runtime), so it doesn't need scene tree integration. However, the generated `.tres` could be manually edited in the Godot Theme editor after generation if the generator output were more modular.

**Assessment:** No change needed — this is the correct pattern for a build-time asset generator.

### 1.3 `tools/build_pacifica_map.py` — static PNG generator — LOW
Python/Pillow script generating a background PNG. Not a Godot scene-tree candidate.

**Assessment:** No change needed.

### 1.4 Missing `tools/generate_city_grids.gd` — MEDIUM
The copilot instructions and ARCHITECTURE.md reference `tools/generate_city_grids.gd` as a "city-grid generator script (run from the editor)", but this file **does not exist** in the project. Either it was removed or never created. The 12 city grid `.tres` files in `data/city_grids/` were presumably authored manually via the city grid designer.

**Fix:** Either create the missing generator or remove the stale reference from documentation.

### 1.5 City grid / world map runtime `_build_grid()` / `_build_world()` — LOW
These build the runtime grid from `.tres` layout resources (not procedurally generated). The layout data IS already editable via the designer tools. The `_build_*` methods are just runtime instantiation from serialized data — correct pattern, no scene-tree conversion needed.

---

## 2. Duplicated Code Patterns

### 2.1 City grid rendering duplicated between runtime + designer — HIGH
**Files:** `cp2020_city_grid.gd` (436 lines) vs `cp2020_city_grid_renderer.gd` (187 lines)

Both files contain near-identical code:
- `_create_datafort_font()` — identical
- Grid drawing, datafort chip rendering, tier glyph rendering — near-identical
- `_process()` pulse animation — identical pattern
- Scanline/vignette/tech-frame rendering — near-identical

The `@tool` renderer was likely forked from the runtime node. They should share a common base class or the runtime node should USE the renderer as a child.

**Fix:** Make `CP2020CityGridRenderer` the single rendering component, used by both the designer (@tool) and the runtime (`cp2020_city_grid.gd` should instantiate/contain a renderer node instead of duplicating its `_draw`).

### 2.2 Opposed-roll combat pattern repeated ~8 times — MEDIUM
**Files:** `cp2020_game_session.gd`, `cp2020_netrunner.gd`, `cp2020_npc_netrunner.gd`, `cp2020_datafort.gd`

The `randi_range(1, 10) + STR` opposed roll pattern appears in:
- `execute_ice_attack` (game_session:875-880)
- `_on_ice_attacked_program` (game_session:2193-2197)
- `apply_damage` shield/armor rolls (netrunner:394, 427, 484)
- `crash_cpu` (datafort:137)
- NPC attack (npc_netrunner:271-272)
- Initiative (turn_manager:163-164)

There's no shared `_opposed_roll(attacker_str, defender_str) -> Dictionary` helper. Each call site reimplements the roll + tie-break + damage.

**Fix:** Add a static helper `func roll_opposed(atk_str, def_str) -> {winner, atk_roll, def_roll, margin}` to a shared class (e.g., `CP2020Dice`).

---

## 3. Data Model & Resources (from `review-data-model` agent)

### 3.1 `CP2020DatafortLayout.get_tile()` raw-dict migration drops most fields — MEDIUM
**File:** `CP2020DatafortLayout.gd:62-78`

When a legacy `.tres` stores a tile as a raw `Dictionary`, the on-the-fly conversion only copies 4 fields (`tile_type`, `is_explored`, `is_visible`, `is_unlocked`). All other fields (`strength_str`, `memory_units_mu`, `reward_credits`, `tile_name`, `ldl_links`, `npc_*`, `files`, `loot_*`, worm fields, LDL fields) are silently lost. Also mutates the cached dict on read (line 77).

**Fix:** Copy all `@export` fields, or drop the raw-dict branch and run a one-time migration script. At minimum `push_error()` when a raw dict is encountered.

### 3.2 `CP2020DatafortLayout.get_tile()` mutates floor dict on read — MEDIUM
**File:** `CP2020DatafortLayout.gd:77`

On a `ResourceLoader`-cached layout, `tile_dict[key] = tile_obj` permanently mutates the cached instance. Combined with field-drop above, a cached legacy layout gets *partially* converted permanently.

**Fix:** Perform migration in `_ensure_floors_migrated()` rather than inside the read helper.

### 3.3 Dual-key (Vector2i / "x,y" string) Dictionary contract reimplemented 3+ places — MEDIUM
**Files:** `CP2020DatafortLayout.get_tile`/`set_tile`/`erase_tile`, `CP2020WorldMapLayout.get_region_index`, `CP2020Floor.tiles`

The string-key fallback exists because `.tres` serialisation historically stored string keys.

**Fix:** A single static helper class `Vector2iDict.get(d, coord)` / `.set()` / `.erase()` used everywhere; eventually migrate `.tres` to `Vector2i` keys.

### 3.4 Enum-typed fields stored as raw `int` — MEDIUM
**Files:** `cp2020_city_grid_datafort.gd:9`, `cp2020_world_hub.gd`, `cp2020_tile_data.gd:86`

`security_tier: int` and `npc_disposition: int` lose inspector dropdowns and type safety. Godot 4 supports enum-typed exports.

**Fix:** `@export var security_tier: CP2020SecurityTier.Tier = ...`

### 3.5 `CP2020Floor.floor_index` stored duplicate of array position — MEDIUM
**File:** `CP2020Floor.gd:18`

Goes stale silently if designer reorders the `floors` array in the inspector. Any code trusting `floor_index` over the array index will be wrong.

**Fix:** Make `floor_index` derived via getter, or add an editor `_validate()` hook that re-syncs on save.

### 3.6 `NetProgram.type` (ProgramType) is display-only metadata while `effect_type` drives all behaviour — MEDIUM
**File:** `cp2020_programs.gd:65-66`

Two parallel categorisation enums on one resource. `ProgramType` only consumed by `cyberdeck_workbench.gd` label maps; every behaviour dispatch goes through `effect_type`. Designers must keep both consistent by hand.

**Fix:** Derive `type` from `effect_type` via a const mapping, or remove `ProgramType` and label from `effect_type` directly.

### 3.7 `ProgramType.Protection` is PascalCase, not in workbench label maps — MEDIUM
**File:** `cp2020_programs.gd:14`

`cyberdeck_workbench.gd` `PROGRAM_TYPE_NAMES` and `_type_short()` do NOT handle `Protection`, so a Protection-typed program renders `"?"`.

**Fix:** Rename to `PROTECTION` and add to both workbench maps.

### 3.8 `CP2020TileData.reward_credits` is dead data — MEDIUM
**File:** `CP2020TileData.gd:19, 105`

Two credit fields (`reward_credits`, `loot_credits`) on the same resource is a footgun for designers.

**Fix:** Fold into `loot_credits` in a migration pass and remove.

### 3.9 Deprecated fields retained with no removal trigger — LOW
**Files:** `cpu`, `int_rating`, `grid_tiles`, `reward_credits`, `ldl_cost`, hub `security_tier`

Collectively they bloat the data model and invite accidental re-use.

**Fix:** Track in `docs/deprecation.md` with target removal version; hide from inspector via `_can_export`.

### 3.10 No `_validate()` / pre-save hooks anywhere — LOW
None of the 14 resources validate cross-field invariants (`ldl_entry` in bounds, `floor_index` matches array position, `installed_modules.size() ≤ upgrade_slots`, `security_tier` in enum range).

**Fix:** Add `_validate()` to base resources to catch designer errors at save time.

### 3.11 Other LOW data-model findings
- `CP2020TileData.npc_disposition: int = -1` uses magic sentinel — use `npc_disposition_override: bool` (mirrors `npc_has_override`).
- `copied_file_paths: PackedStringArray` stores indices as strings — use `Array[int]`.
- `CP2020WorldHub` — 3 of 6 fields deprecated (`subnet_path`, `ldl_cost`, `security_tier`); hide from inspector.
- `CP2020SecurityTier` — 4 parallel Dictionary consts could be one `META` dict.
- `Cyberdeck.effective_*` accessors re-loop `installed_modules` for every call — cache `Dictionary[ModuleEffect, int]`.
- `NetProgram.icon: Texture2D` vs `sprite_texture` — rename `icon` → `ui_icon` and document.
- `NetProgram._roll_damage()` non-deterministic — route through central RNG for seedable replays.
- `NetProgram.ATTACK_VISUALS` covers only 4 of 12 effect types; un-mapped effects use red default indistinguishable from DEREZ_ICE.
- `CP2020WorldMapLayout.get_region_index` never normalises to `Vector2i` (same dual-key issue).
- `CP2020Character` — no validation/clamps on stat ranges; `luck` stored but unwired.
- `DeckModule` — no `DEFAULT_VISUALS` const keyed by `ModuleEffect` (inconsistent with NetProgram).

---

## 4. ICE / Entity Nodes & Programs (from `review-ice-entities-programs` agent)

### 4.1 NPC `current_health` is never decremented — entire NPC shield model is dead — HIGH
**File:** `cp2020_npc_netrunner.gd:222-238`

`_attack_player` shield branch gated on `if current_health < max_health`, but `current_health` is **never decremented anywhere** — `take_damage` only reduces `current_integrity`. The `max_health`/`current_health` fields are dead and the shield branch never fires.

**Fix:** Either remove the health/shield model, or decrement `current_health` in `take_damage` and gate the shield on `current_integrity < max_integrity` (with a `_shield_cooldown` to prevent infinite-shield exploit — see 4.2).

### 4.2 NPC infinite-shield exploit if revived naïvely — MEDIUM
**File:** `cp2020_npc_netrunner.gd:222-238`

If you gate the shield on `current_integrity < max_integrity`, the NPC re-raises a fresh shield **every turn it is damaged** (`raised_shield` only consumed when actually hit). Far stronger than the player's one-shot shield.

**Fix:** Only raise a shield when the NPC has none raised, and consume/lock it for at least one turn (`_shield_cooldown` flag).

### 4.3 Datafort resident-program alternation is broken — MEDIUM
**File:** `cp2020_datafort.gd:167-185`

When **any** DAMAGE_RUNNER program is loaded, the `else` (CRASH_CPU / anti-system) never runs — so a datafort loaded with both never attacks the runner's cyberdeck.

**Fix:** True alternation: `var use_crash := (i % 2 == 1) and not crash_programs.is_empty()`, fall back to the other list if the chosen one is empty.

### 4.4 Unguarded `await` in NPC movement + `_wander` — MEDIUM
**File:** `cp2020_npc_netrunner.gd:196-206, 246`

Bare `await get_tree().create_timer(0.3).timeout` then `moved_to.emit` — if the scene is torn down mid-await (player flatlines → GameOver scene swap), `get_tree()` returns null on resume and `moved_to.emit` runs on a freed node → crash. `BlackIce.move_to_step` already guards this.

**Fix:** Replicate the `BlackIce.move_to_step` guard: `var tree := get_tree(); if tree == null: return` before each await.

### 4.5 `RezzedProgram.move_to_step` has no freed-node guard — MEDIUM
**File:** `cp2020_rezzed_program.gd:52`

Same issue as 4.4 but for rezzed programs. If DEREZed during follow animation, resuming emits `moved_to` on a freed node → crash.

**Fix:** Copy the `BlackIce.move_to_step` guard exactly.

### 4.6 NPC attacks across walls when path is blocked — MEDIUM
**File:** `cp2020_npc_netrunner.gd:191-206`

In the `while ap_remaining > 0` loop, the `else` branch (`path.size() <= 1`) calls `_attack_player(); break` regardless of whether the runner is actually adjacent. AStarGrid2D returns a 1-element path when no route exists; the NPC "hits you with STR" from across a Datawall it has LoS around but no path to.

**Fix:** Only attack when `current_position` is adjacent to `target_pos` (Manhattan distance 1); otherwise hold.

### 4.7 Massive duplication across BlackICE / NPC / RezzedProgram — HIGH
**Files:** `cp2020_blackice.gd`, `cp2020_npc_netrunner.gd`, `cp2020_rezzed_program.gd`

`initialize`, `update_visual_position`, `apply_visual_from_program`, `refresh_pathfinding`, the `raw_key.split(",")` string-key parsing loop, and the astar setup are duplicated nearly verbatim across all three entity classes (~150 lines).

**Fix:** Extract a common `GridEntityBase` (Node2D) with `initialize/update_visual_position/refresh_pathfinding/apply_visual_from_program` (with the freed-node `await` guard and a `const` fallback font), and have the three classes extend it. This eliminates 4.4/4.5 crashes, the `load()`-per-call perf hit, and ~150 lines of duplication in one pass.

### 4.8 `load("res://data/seguiemj.ttf")` called every `apply_visual_from_program` — MEDIUM
**Files:** `cp2020_blackice.gd:238`, `cp2020_rezzed_program.gd` (equivalent)

`load()` runs at spawn for every ICE. Although cached by Godot, it still does a resource-path lookup + cast each call.

**Fix:** `const FALLBACK_FONT := preload("res://data/seguiemj.ttf")` (fixed by 4.7 base class).

### 4.9 Other LOW entity/program findings
- `BlackIce.move_to_step(coord)` ignores its parameter — rename to `_coord` or make no-arg `step_animation()`.
- `BlackIce.next_step_to` appears to be dead code.
- Duplicated comment block in `cp2020_blackice.gd:9-11`.
- `Demon.apply_visual_from_program` redundant override; `take_damage` pure pass-through; `get_commandable_subroutines` returns mutable ref.
- `watchdog_program.gd:21` trace tie uses `>=` (attacker-favored) — inconsistent with defender-favored opposed-roll convention elsewhere.
- `watchdog_program.gd:32` `execute_runner_action` always returns `true` without checking deploy success.
- `probe_program.gd:8` always returns `true` regardless of valid in-LoS target.
- `worm_program.gd:8` no null guard on `session.current_layout`.
- `cp2020_datafort.gd` `cpus: Array` untyped → `Array[Cpu]`; `crash_cpu` uses `total_int()` (all CPUs × 3) vs literal "CPU INT" — clarify spec.
- `cp2020_datafort.gd` `take_turn` rebuilds `attack_programs`/`crash_programs` arrays every turn — cache in `initialize`.

---

## 5. Designers & Procedural Generation (from `review-designers-procgen` agent)

### 5.1 Procedural `_draw` logic duplicated between designers and runtime — HIGH
**Files:** `cp2020_city_grid_renderer.gd` (designer) vs `cp2020_city_grid.gd` (runtime); `cp2020_world_map_designer.gd:450-580` inlines entire `_draw_designer_*` vs `cp_2020_world_net_map.gd`

Two copies of the same neon rendering. `CanvasItem.draw_*` calls can't literally be scene-tree nodes, but the **logic** should be shared.

**Fix:** Extract a single `CP2020NeonGridRenderer` (Node2D, `@export` palette) and instance it in both the designer scene AND the runtime scene, feeding it `current_layout`. The world-map designer should delegate to a renderer child like the city-grid designer already does.

### 5.2 Glyph/sprite align controls built in code — MEDIUM
**File:** `cp2020_datafort_designer.gd:909 (_build_glyph_align_controls), :1034 (_build_sprite_align_controls)`

~15 controls each built in code and `add_child()`'d with `has_node("GlyphSep")` reload guards. ARCHITECTURE.md line 468 says the datafort designer was *migrated* to scene-tree authoring — these two blocks are the leftover non-migrated UI.

**Fix:** Author the glyph/sprite alignment rows directly in `CP2020DesignerCanvas.tscn` under `IceEditorPanel/VBox`, reference via `@onready`, drop the duplicate-guard logic.

### 5.3 Code-built `FileDialog` fallbacks in world/city designers — LOW/MEDIUM
**Files:** `cp2020_city_grid_designer.gd:155`, `cp2020_world_map_designer.gd:84`

`@onready var save_dialog = get_node_or_null("SaveDialog")` implies scene-tree presence, but the fallback `add_child(FileDialog.new())` builds them in code when absent.

**Fix:** Place the three `FileDialog` nodes in the `.tscn` (as the datafort designer does), then delete the fallback builders.

### 5.4 `generate_theme.gd` palette duplicated from `cp2020_theme.gd` — MEDIUM
**File:** `tools/generate_theme.gd:10-17`

Re-declares `COL_BG/COL_PANEL/COL_BORDER/...` that mirror `CP2020Theme` const class. Two sources of truth for the palette.

**Fix:** `generate_theme.gd` should `preload("res://scripts/resources/cp2020_theme.gd")` and read `CP2020Theme.COL_*` consts instead of re-declaring them.

### 5.5 `_refresh_side_panel` feedback loops (city + world designers) — MEDIUM
**Files:** `cp2020_city_grid_designer.gd:355-372`, `cp2020_world_map_designer.gd`

Setting `.text`/`.value`/`.select()` in code re-emits signals, invoking `_on_df_name_changed` → `_sync_renderer()`. Harmless but wasteful and confusing. The datafort designer correctly uses `set_block_signals(true)/false`.

**Fix:** Wrap each populate in `set_block_signals(true)/false`.

### 5.6 `subnet_loader.gd` silent failure on wrong resource type — MEDIUM
**File:** `cp2020_subnet_loader.gd:11-13`

If the path exists but loads a non-`CP2020DatafortLayout`, `new_layout` is null and no error is logged.

**Fix:** Add `else: log_message.emit("ERROR: … is not a CP2020DatafortLayout")`.

### 5.7 Child `_ready` runs before parent — wasted layout creation — LOW
**File:** `cp2020_datafort_grid_canvas.gd:53`

Canvas `_ready()` creates `current_layout = CP2020DatafortLayout.new()` and calls `fill_empty_tiles()` (spawns 225 `CP2020TileData`). Then the parent designer `setup_new_map()` *replaces* it. The canvas's 225 tiles are immediately discarded.

**Fix:** Remove the `current_layout = CP2020DatafortLayout.new()` fallback from the canvas's `_ready`; let the parent own lifecycle.

### 5.8 `_theme_font()` allocates a `Label` every frame — LOW (also flagged in §6)
**File:** `cp2020_city_grid_renderer.gd:223`

`var label := Label.new(); var f := label.get_theme_default_font(); label.free(); return f` — called once per `_draw()`. Node2D lacks `get_theme_default_font()`, which is why the Label trick is used.

**Fix:** Cache `var _theme_cache: Font` on first call.

### 5.9 Other LOW designer findings
- `grid_canvas._draw` fetches default font per-tile per-frame — cache once at top of `_draw()`.
- `generate_theme.gd` `DirAccess.open` null-deref risk; `make_dir` return value unchecked.
- `cp2020_sprite_preview.gd` uses `AtlasTexture` in `@tool` (grid canvas deliberately avoids it) — prefer `draw_texture_rect_region` for consistency.
- `cp2020_datafort_designer.gd` (1520 lines) — duplicated coord-key parsing inline in 6+ places; expose `CP2020DatafortLayout.coords()` helper.
- 11 near-identical `_on_<tool>_tool()` functions — pass label into `_set_paint_tool` and delete the wrappers.
- `cp2020_city_grid_designer.gd:91-140` `_apply_cyberpunk_ui_theme()` manually builds StyleBoxes — use generated `cyberpunk_theme.tres` instead.
- `generate_theme.gd` StyleBox builders repetitive — single `_flat(...)` helper would halve line count.
- World-map designer `_process` continuous redraw — gate with `is_visible_in_tree()`.
- `cp2020_world_map_designer.gd:11` hardcoded `GRID_OFFSET_Y = 90` (datafort designer already fixed this).
- `_screen_to_grid` clamps out-of-bounds clicks to edge cells — dead code + latent footgun.
- Random region colour with no `randomize()` — pick from curated neon palette.
- `_clear_npc_override` double-writes (no `set_block_signals`).
- `_clear_ice_program` doesn't clear glyph/sprite offset spins — stale values shown with no program.
- `_on_npc_field_changed(_value: Variant = null)` overloaded signal handler — fragile; use three thin typed handlers.
- `generate_theme.gd` ends with `get_tree().quit()` — running via F6 closes the editor; document in file header.

---

## 6. UI, Rendering & Autoloads (from `review-ui-rendering-autoloads` agent)

### 6.1 `cp2020_canvas.gd` is dead stub code — HIGH
**File:** `scripts/resources/cp2020_canvas.gd` (21 lines)

`render_grid` only `print`s and has a `TODO: Spawn visual grid icon` with `pass`. `@onready var grid_container` untyped and unused. Abandoned prototype superseded by `cp2020_board_renderer.gd`. Not referenced by any `.tscn` or `.gd`.

**Fix:** Delete the file.

### 6.2 Per-frame `Label.new()`/`free()` in `_theme_font()` — HIGH (performance)
**Files:** `cp_2020_world_net_map.gd:431`, `cp2020_city_grid.gd:354`, `cp2020_city_grid_renderer.gd:223`

`_theme_font()` allocates `Label.new()`, reads font, and `free()`s it — called every frame from `_draw()`. Per-frame node allocation + freeing is a known Godot anti-pattern (pressures the allocator and theme cache).

**Fix:** Cache the font in a member var on first call (as `cp2020_board_renderer._get_default_font` does).

### 6.3 Unconditional per-frame `queue_redraw()` in board renderer — HIGH (performance)
**File:** `cp2020_board_renderer.gd:155`

`_process(delta)` unconditionally calls `queue_redraw()` every frame even when the board is static. Combined with 37 explicit `board_renderer.queue_redraw()` calls in the game session, the entire grid is redrawn 60fps.

**Fix:** Only `queue_redraw()` when `_floor_flash_alpha > 0` or watchdog/rezzed arrays animate; otherwise throttle to ~10 Hz. Or use a shader for the pulse.

### 6.4 `cyberdeck_workbench.gd` is 1498 lines in one class — HIGH (structure)
**File:** `scripts/ui/cyberdeck_workbench.gd`

Shop, loadout, subroutines window, upgrades window, unlock window, drag-drop, character roster, and HUD all coexist. The three popup windows (`_build_subroutines_window`, `_build_upgrades_window`, `_build_unlock_window`) are near-identical scaffolding (~80 lines each).

**Fix:** Split into `workbench_shop.gd`, `workbench_subroutines.gd`, `workbench_upgrades.gd`, `workbench_unlocks.gd`, each owning its Window; share a base popup helper.

### 6.5 `RunState.start_new_life()` does not persist — HIGH
**File:** `scripts/autoload/run_state.gd:100-135`

State is set up in memory only; persistence happens later when the workbench `_ready` calls `save_run()`. If the app is closed between `start_new_life()` (game_over `_on_new_life_pressed`) and the workbench finishing `_ready`, the cleared save file means next launch runs `_load_run()` (no-op) then `start_new_life()` again. Self-healing but fragile.

**Fix:** Call `RunState.save_run()` at the end of `start_new_life()`, or document the contract explicitly. Add a `schema_version` field to `RunStateData` for forward-compatible migration.

### 6.6 `cyberdeck_workbench.gd:434` HP label uses `max_health` twice — MEDIUM
**File:** `scripts/ui/cyberdeck_workbench.gd:434`

`hp_label.text = "HP: %d / %d" % [ch.max_health, ch.max_health]` — HP always shows as full. Misleading during a run (though the workbench is the hub where HP is full by design).

**Fix:** Use `ch.current_health` if it exists, or remove the label and show only wounds, or clarify it's "max HP" only.

### 6.7 `cp2020_city_grid.gd:48` `_ready` resets `net_time_seconds` — MEDIUM
**File:** `scripts/resources/cp2020_city_grid.gd:48`

Per ARCHITECTURE, net_time is "preserved across in-datafort LDL travel + the datafort→City Grid return (mid-run)." Resetting in `_ready` violates that for the datafort→citygrid return path.

**Fix:** Remove the `_ready` reset (line 48); reset only at run start (world map) and run end.

### 6.8 `last_run_summary.duplicate()` is shallow — MEDIUM
**File:** `scripts/autoload/run_state.gd:225, 277`

Nested dictionaries inside the summary would be shared by reference between in-memory and saved resource, mutating the saved `.tres` on disk on next save.

**Fix:** Use `duplicate(true)` for deep copy.

### 6.9 `city_grid_renderer.gd` `@tool` + `_process` redraws editor continuously — MEDIUM
**File:** `cp2020_city_grid_renderer.gd:38`

Runs the renderer continuously in the editor even when no scene is open, eating editor CPU.

**Fix:** Guard with `if Engine.is_editor_hint():` and only redraw on data change, or throttle.

### 6.10 Other LOW UI/autoload findings
- `run_state.gd` — `sell_loot_program`/`sell_file` fallback matching by `resource_path` can sell the wrong item when two loot programs share a path.
- `run_state.gd` — `buy_deck`/`buy_program`/`buy_module` append duplicates but never call `save_run()` — responsibility split across files.
- `run_state.gd` — `add_loot`/`add_module_loot` call `MetaState.unlock_*` directly during datafort gameplay; defer to jack-out.
- `meta_state.gd` — `_migrate_paths()` calls `save()` inside `_load()` — unexpected write on load.
- `meta_state.gd` — `unlock_deck()` returns void while `unlock_program()`/`unlock_module()` return bool — inconsistent.
- `meta_state.gd` — `unlock_program_resource`/`unlock_deck_resource` exist but not `unlock_module_resource` — asymmetry.
- `cyberdeck_workbench.gd` — `_refresh_loaded()` sets `unload_button.disabled` before `_selected_loaded_idx = -1` reset — uses stale value.
- `cyberdeck_workbench.gd` — `_load_program_at()` Demon duplicate-then-erase silently fails if `duplicate()` returns null.
- `cyberdeck_workbench.gd` — `_start_jackin_pulse()` creates infinite-looping Tween; `_start_cursor_blink()` adds `Timer.new()` non-idempotently.
- `cyberdeck_workbench.gd` — `_build_unlock_window()` uses `get_node("%CreditsLabel")` with no null check.
- `cyberdeck_workbench.gd` — `_scan_data_catalogue()` scans `res://data` non-recursively — misses subfolders.
- `cyberdeck_workbench.gd` — Duplicated palette constants (lines 197-207) mirror `CP2020Theme`.
- `cyberdeck_workbench.gd` — ESC quits the whole game from the workbench — surprising UX.
- `intro_screen.gd` — `_load_art()` warning condition is wrong; `_fade_in_prompt` can create racing tweens.
- `cp2020_board_renderer.gd` — `draw_grid` calls `Time.get_ticks_msec()` per-beacon per-frame; `rezzed_program_nodes: Array` untyped.
- `cp2020_city_grid.gd` — `_datafort_at`/`_hub_at` return `Variant`; `_resolve_entry` falls back to center tile silently.
- `cp_2020_world_net_map.gd` — `_log_terminal` splits entire text by `\n` every call; `_parse_coord` no bounds check; `backdrop_texture` declared but never used.
- `cp2020_combat_effect_animator.gd` — `queue_redraw()` called in both `play_effect` AND `_process` (double redraw first frame).
- `cp2020_explosion_effect.gd` — `_material = ShaderMaterial.new()` per instance; relies entirely on shader for visible output.
- `cp2020_theme.gd` — `make_mono_font()` returns fresh `SystemFont` each call; palette duplicated with workbench.

---

## 7. Core Gameplay (from `review-core-gameplay` agent)

### 7.1 "Copy All" menu item added once per file — HIGH
**File:** `cp2020_interaction_handler.gd:429-431`

`_dynamic_menu.add_item("Copy All", 6999)` is *inside* the `for i in range(tile_data.files.size()):` loop. A memory tile with N files renders N "Copy All" rows (all sharing id 6999). `get_item_index(6999)` returns only the first match, so `set_item_disabled` only disables the first; the remaining N-1 rows stay enabled and each fires `copy_all_files`.

**Fix:** Move the three "Copy All" lines outside/after the for loop.

### 7.2 Tie-resolution inconsistency between anti-ICE and anti-NPC opposed rolls — HIGH
**File:** `cp2020_game_session.gd:879` vs `:1515-1516`

`_execute_ice_attack`: `if prog_roll > ice_roll:` (ties → defender). `execute_npc_attack`: `if prog_roll >= npc_roll:` with comment "CP2020: ties go to the ATTACKER". CP2020 convention is ties go to the *defender* on attack rolls; the NPC attack's `>=` is almost certainly a bug.

**Fix:** Change line 1516 to `if prog_roll > npc_roll:` and update the log string on line 1514.

### 7.3 `_on_action_triggered` is a ~230-line `match` statement — HIGH (structure)
**File:** `cp2020_game_session.gd:581-810`

Each arm repeats: `if not turn_manager.can_use_programs(): log; return` → execute → `turn_manager.consume_action()` → `_check_actions_exhausted()`.

**Fix:** Extract a helper `_try_action_consuming(callable: Callable, busy_msg: String) -> bool` and per-arm handlers (`_handle_use_program`, `_handle_rez_program`, etc.).

### 7.4 `handle_right_click` is ~230 lines with deeply nested if/elif — HIGH (structure)
**File:** `cp2020_interaction_handler.gd:50-280`

Each branch repeats the "loop rezzed programs + loop demon subroutines + add_item" pattern 4 times (ICE, NPC, CPU, runner-tile).

**Fix:** Extract `_add_rezzed_attack_options(target_label, effect_types, base_id)` and `_add_demon_subroutine_options(target_label, effect_types)` helpers; the four branches collapse to a couple of calls each.

### 7.5 `_find_rez_spawn_tile` doesn't gate NPC occupancy by floor — MEDIUM
**File:** `cp2020_game_session.gd:1291-1293`

The ICE loop gates `ice.home_floor == current_floor`, but the NPC loop only checks `npc.current_position != Vector2i(-1, -1)`. An NPC on another floor at the same coord adds that coord to `occupied`, causing `runner_pos in occupied` to be true, so the spawn falls through to an adjacent tile even though the runner's own tile is free.

**Fix:** Add `and npc.home_floor == current_floor` to line 1292.

### 7.6 `update_deck_info` only marks SHIELD as `[ACTIVE]`, not ARMOR — MEDIUM
**File:** `cp2020_game_session.gd:~1618`

`var active := (netrunner.raised_shield == prog and not crashed)`. The runner can have `active_armor` raised, but it never shows as active in the program list.

**Fix:** `var active := (netrunner.raised_shield == prog or netrunner.active_armor == prog) and not crashed`.

### 7.7 Session reaches into turn manager internals — MEDIUM
**File:** `cp2020_game_session.gd:144, 1956-1957, 1940`

`turn_manager.actions_remaining = 0`, `turn_manager.movement_remaining = 0`, `turn_manager.actions_changed.emit(...)`, `turn_manager._post_round_adversary = true`. The turn manager is supposed to own its state machine.

**Fix:** Add `apply_stun()` and `block_programs()` methods on `CP2020TurnManager` that encapsulate the transitions.

### 7.8 Duplicated initiative calculation — MEDIUM
**File:** `cp2020_game_session.gd:~1930, ~2111`

```gdscript
var nr_init := netrunner.reflex + (RunState.selected_deck.effective_speed_bonus() if RunState.selected_deck != null else 0) + netrunner.temp_speed_bonus
```

**Fix:** Extract `func _netrunner_initiative() -> int`.

### 7.9 Duplicated `raw_key.split(",")` Vector2i parsing across 7+ sites — MEDIUM
**File:** `cp2020_game_session.gd` (lines ~253, ~1655, ~1700, ~2023, ~2367, ~2325), `netrunner.initialize`

**Fix:** Add `CP2020DatafortLayout.parse_coord(raw_key) -> Vector2i` static helper, or have `get_floor_tiles` return typed `Vector2i` keys.

### 7.10 Duplicated `_can_travel_vertical` — MEDIUM
**File:** `cp2020_interaction_handler.gd:558-567`

Comment admits it "Mirrors the game session's authoritative `_on_travel_vertical`". Two implementations will drift.

**Fix:** Move to `CP2020DatafortLayout` as a static/method, or have the handler query the session.

### 7.11 Per-file `fits` check uses static `free_mu` — MEDIUM
**File:** `cp2020_interaction_handler.gd:~415-423`

Each file's `fits` computed against the original `free_mu` without decrementing, so the menu marks all files as fitting even when copying them all would overflow. Display bug — `copy_all_files` handler decrements correctly.

**Fix:** Decrement `free_mu -= file.mu_size` inside the loop when a file fits.

### 7.12 `apply_damage` stunned branch re-emits `stunned` signal — MEDIUM
**File:** `cp2020_netrunner.gd:~410-435`

When already stunned, the path still calls `_apply_anti_personnel_effects`, rolls a Stun save, fails, sets `is_stunned = true` again, and emits `stunned` a second time. HUD/log gets duplicate "STUNNED" messages per hit.

**Fix:** Guard `_apply_anti_personnel_effects` with `if not is_stunned:` before re-emitting.

### 7.13 `program_integrity` Dictionary keyed by shared NetProgram instances — LOW/MEDIUM
**File:** `cp2020_netrunner.gd:86, 271-284`

`deck.installed_programs.duplicate()` is shallow; `NetProgram` instances shared with the deck. If the deck has two slots pointing to the same `.tres`, the dict key collides and they share one HP pool.

**Fix:** Deep-duplicate programs on deck load (`prog.duplicate()` per element), or key the integrity dict by a unique per-slot id.

### 7.14 Other LOW core-gameplay findings
- `turn_manager.gd` — `_on_turn_ended(false)` semantics ambiguous; `_post_round_adversary` never reset on `start_netrunner_turn`; magic `0.3` delay; `_count_valid_adversaries` untyped `Array`.
- `netrunner.gd` — `move()` has no `is_stunned`/`can_act()` guard; `raise_shield`/`raise_armor` accept any program without validation; `_wound_state` returns untyped Dictionary; magic numbers (wound thresholds 4/8/12, penalties 0/2/4/6, death save 15); per-frame `queue_redraw()` + `PackedVector2Array` allocation.
- `interaction_handler.gd` — stale `_ldl_tile`/`_npc_target`/`_netrunner_node` between popups (not cleared at popup start); `_on_menu_action_selected` long if-chain (use `match id / 100` or Dictionary); pervasive `print("DEBUG: ...")` statements in production; `_current_demon_commands: Array` untyped holding `[DemonNode, int]` pairs — define `DemonCommand` class; `handle_input`/`handle_right_click` 11-arg parameter lists — bundle into `MenuContext`.
- `game_session.gd` — `_on_action_triggered` "command_demon" arm broken indentation (5 tabs vs 4); `recalculate_fog_of_war` no null guard on `netrunner`; `_tick_rezzed_programs` no null guard on `rez.astar_grid`; `_on_npc_destroyed` dead null check; `_on_jack_out_pressed` success path not guarded by `_game_over_queued`; `_on_ice_attacked_program` uses `current_integrity` for defender roll (wounded program defends worse — clarify intent); `action_triggered` signal carries `Variant`; `TIER_NPC_TEMPLATES` hardcodes `.tres` paths — move to `data/npc_templates.tres`; `execute_npc_attack` uses `(randi() % 10) + 1` vs `randi_range(1, 10)` elsewhere; dead code `reveal_entry_points()` + `spawn_netrunner_at_entry()` (writes to non-existent `netrunner.grid_position`); `recalculate_fog_of_war` O(floors × tiles) + O(vision²) per move — only reset previously-visible floor.

---

## 8. Pre-existing Personal Analysis Findings (consolidated)

### 8.1 37 redundant `queue_redraw()` calls in game session — MEDIUM
**File:** `cp2020_game_session.gd`

37 explicit `board_renderer.queue_redraw()` calls scattered across functions. Combined with the board renderer's per-frame `_process` redraw (§6.3), these are redundant no-ops. Code clutter.

**Fix:** Remove the redundant calls (the renderer already redraws every frame), OR fix the root cause (gate the per-frame redraw — §6.3) and keep the explicit calls as the only redraw trigger.

### 8.2 26 untyped `Array` declarations across 15 files — LOW
Violates "typed GDScript everywhere" convention (ARCHITECTURE line 10).

**Fix:** Type all to `Array[Type]`.

### 8.3 `_process()` + `queue_redraw()` every-frame pattern in 8 files — MEDIUM
**Files:** `cp2020_board_renderer.gd`, `cp2020_city_grid.gd`, `cp2020_city_grid_renderer.gd`, `cp2020_combat_effect_animator.gd`, `cp2020_explosion_effect.gd`, `cp2020_netrunner.gd`, `cp_2020_world_net_map.gd`, `cp2020_world_map_designer.gd`

**Fix:** Use shaders for pulse animations, or only redraw when state changes.

---

## 9. Summary — Top Priorities (All 5 Agents + Personal Analysis)

### Triage table (verified on `feature/2.5d-visual-upgrade`)

✅ = verified fixed in code on this branch · ⬜ = still open (tracked in `TODO.md`)

| # | Item | Status |
|---|------|--------|
| 1 | "Copy All" added once per file (§7.1) | ✅ fixed — item moved outside the file loop |
| 2 | Tie-resolution inconsistency (§7.2) | ✅ fixed — defender-favored via `CP2020Dice.roll_opposed` |
| 3 | NPC shield model dead (§4.1/§4.2) | ✅ rebuilt on integrity + `_shield_cooldown`; dead `max_health`/`current_health` fields removed |
| 4 | Datafort alternation broken (§4.3) | ✅ fixed — `i % 2` + empty-list fallback, exactly as prescribed |
| 5 | Rez-spawn NPC floor gate (§7.5) | ✅ fixed — `npc.home_floor == current_floor` |
| 6 | Armor not `[ACTIVE]` (§7.6) | ✅ fixed |
| 7 | city_grid `_ready` resets net_time (§6.7) | ✅ fixed — reset contract documented in `_ready` |
| 8 | Extract `GridEntityBase` (§4.7) | ✅ done — also fixes the §4.4/§4.5 unguarded awaits |
| 9 | Split `cyberdeck_workbench.gd` (§6.4) | ◐ partially — popup windows extracted (1880 → 1529 lines); shop + missions domains remain (TODO) |
| 10 | Split `_on_action_triggered` + `handle_right_click` (§7.3/§7.4) | ✅ done — per-arm `_handle_*` methods, shared `_programs_available`/`_consume_program_action`, shared `_add_rezzed_attack_options`/`_add_demon_subroutine_options` |
| 11 | Unify city-grid rendering (§5.1/§2.1) | ✅ city grid uses shared `CP2020NeonGridRenderer` · ⬜ world-map designer still inline |
| 12 | `CP2020Dice.roll_opposed` (§2.2) | ✅ done — 5+ call sites |
| 13 | Cache `_theme_font()` (§6.2/§5.8) | ✅ done in all three files |
| 14 | Gate board-renderer per-frame redraw (§6.3) | ✅ done — redraws only while animating |
| 15 | Font `const` preload (§4.8) | ✅ done — portable static `get_fallback_font()` with `ResourceLoader.exists` guard |
| 16 | Delete `cp2020_canvas.gd` (§6.1) | ✅ deleted |
| 17 | Delete `cp2020_subnet_loader.gd` (§6.1/§5.6) | ✅ deleted |
| 18 | Delete dead session code (§7.14) | ✅ done |
| 19 | Remove stale generator references (§1.4) | ✅ removed — copilot-instructions now states no generator exists |
| 20 | `get_tile()` raw-dict migration (§3.1/§3.2) | ✅ fixed — full-field copy via `_convert_raw_tile` + `push_error` + key normalisation |
| 21 | Enum-typed exports (§3.4) | ✅ `security_tier` typed · ⬜ `npc_disposition` not re-verified |
| 22 | `schema_version` (§6.5) | ✅ done — ⬜ save-at-end-of-`start_new_life()` half still open |
| 23 | Glyph/sprite controls → `.tscn` (§5.2) | ✅ done — code builders removed |
| 24 | `FileDialog` nodes → `.tscn` (§5.3) | ✅ done — code fallbacks removed |
| 25 | Procgen assessment | n/a — assessment, no action |

Untriaged LOW tails remain in §3.9–3.11, §4.9, §5.9, §6.10, §7.14. Separately verified as fixed but not listed above: §3.3 (dual-key helper), §5.7 (partially — fallback still present, see TODO), §6.8 (`duplicate(true)` both directions), §7.12 (redesigned as CP2020 Death-Trap auto-hit), §3.8 (resolved by documentation — `reward_credits` marked legacy in source), §5.5 (`set_block_signals` present in both designers).

### Critical bugs to fix first (HIGH severity, behavioral correctness):
1. **"Copy All" menu item added once per file** — `cp2020_interaction_handler.gd:429` (§7.1)
2. **Tie-resolution inconsistency** — `cp2020_game_session.gd:1516` NPC attack ties go to attacker (should be defender) (§7.2)
3. **NPC `current_health` never decremented — entire shield model dead** — `cp2020_npc_netrunner.gd:222` (§4.1)
4. **Datafort resident-program alternation broken** — CRASH_CPU never runs when DAMAGE_RUNNER loaded (§4.3)
5. **`_find_rez_spawn_tile` doesn't gate NPC by floor** — `cp2020_game_session.gd:1292` (§7.5)
6. **Armor not shown as `[ACTIVE]` in program list** — `cp2020_game_session.gd:1618` (§7.6)
7. **`cp2020_city_grid.gd:48` `_ready` resets `net_time_seconds`** — violates mid-run preservation (§6.7)

### Structural refactors (HIGH severity, maintainability):
8. **Extract `GridEntityBase`** — eliminate ~150 lines duplication across BlackICE/NPC/RezzedProgram + fix unguarded `await` crashes (§4.7)
9. **Split `cyberdeck_workbench.gd`** (1498 lines) into sub-scripts (§6.4)
10. **Split `_on_action_triggered`** (230-line match) + `handle_right_click` (230-line if/elif) (§7.3, §7.4)
11. **Unify city grid rendering** — runtime + designer share one `CP2020NeonGridRenderer` (§5.1, §2.1)
12. **Extract shared opposed-roll helper** `CP2020Dice.roll_opposed()` (§2.2)

### Performance quick wins (HIGH severity, perf):
13. **Cache `_theme_font()` in 3 files** — eliminate per-frame `Label.new()`/`free()` (§6.2, §5.8)
14. **Gate per-frame `queue_redraw()` in board renderer** (§6.3)
15. **Cache `load("res://data/seguiemj.ttf")` as `const` preload** in entity `apply_visual_from_program` (§4.8)

### Dead code cleanup:
16. **Delete `cp2020_canvas.gd`** (21 lines, unused) (§6.1)
17. **Delete `cp2020_subnet_loader.gd`** (13 lines, unused by scripts) + remove its node from `cp2020_gameplay.tscn`
18. **Delete dead code** in game_session: `reveal_entry_points()`, `spawn_netrunner_at_entry()` (§7.9 LOW)
19. **Remove stale `tools/generate_city_grids.gd` reference** from copilot instructions + ARCHITECTURE.md (§1.4)

### Data model correctness:
20. **Fix `get_tile()` raw-dict migration** dropping fields + mutating cached dict on read (§3.1, §3.2)
21. **Type enum fields as enum types** (security_tier, npc_disposition) (§3.4)
22. **Add schema_version to RunStateData** for forward-compatible migration (§6.5)

### Procedural generation → scene tree (user's specific ask):
23. **Move glyph/sprite align controls to `.tscn`** — leftover non-migrated UI in datafort designer (§5.2)
24. **Place `FileDialog` nodes in `.tscn`** for world/city designers (§5.3)
25. **Assessment:** Most "procedural" code is runtime instantiation from `.tres` data (already editable via designers). Only true generators are `generate_theme.gd` (one-shot, OK), `build_pacifica_map.py` (Python PNG, not scene-tree), `add_windows_cmap.py` (Python font patcher, not scene-tree). The real opportunity is reducing renderer code duplication (§5.1), not scene-tree conversion.