# Copilot Instructions — Netrunner V0.006

This is a **Cyberpunk 2020 Netrunning** game built in **Godot 4.7** with **GDScript**. The authoritative technical reference is `ARCHITECTURE.md` at the repo root — read it before making non-trivial changes. This file only captures conventions that are easy to get wrong.

## Running the project

Open the project in the Godot 4.7 editor (or run the editor headless with `godot --editor -e` against this folder). There is no package manager, test runner, or linter — validation is done by running the game/scene in the editor. Use the editor's **Scene → Run Scene** (F6) to test a single scene; **Play** (F5) runs from the main scene (`cp2020_gameplay.tscn` via UID).

Designer tools (`@tool` scripts in `scripts/resources/*_designer.gd` and `cp2020_city_grid_designer.gd`) run inside the editor and are exercised by opening their corresponding `.tscn` and using the in-canvas toolbar.

## High-level architecture

The game is a **decoupled component architecture** driven by signals and a single autoload singleton. Read `ARCHITECTURE.md` §3–5 for the full component diagram; the essentials:

- **`RunState`** (`scripts/autoload/run_state.gd`) is the autoload singleton holding cross-scene state: `selected_deck`, `selected_subnet_path`, `selected_city_grid_path`, `selected_security_tier`, `credits`, `accumulated_trace`. Set at the workbench/world map, read by gameplay. `reset()` clears it for a fresh run.
- **Three map levels** matching the CP2020 sourcebook: **Workbench → World Map → City Grid → Datafort (gameplay)**. Scene changes use `get_tree().change_scene_to_file(...)`, passing context through `RunState` fields rather than arguments.
- **Data models are `Resource` subclasses** serialised to `.tres` files in `data/`, `scenes/forts/`, and `data/city_grids/`. All grid tile data lives in `CP2020DatafortLayout.grid_tiles` (a `Dictionary` keyed by grid coord) plus the world/city layout resources.
- **`CP2020GameSession`** (`scripts/resources/cp2020_game_session.gd`) is the gameplay orchestrator: it owns the board renderer, netrunner, ICE nodes, turn manager, and interaction handler, wiring their signals together in `_ready()`.
- **Rendering is procedural** — `CP2020BoardRenderer` draws the grid via `CanvasItem.draw_*` from a three-state fog-of-war model (unexplored / explored-not-visible / visible), not via `TileMap`/sprites.
- **`@tool` designer scripts** (datafort, world map, city grid) author `.tres` layouts from within the editor; their side panels are built in code, not in the `.tscn`, to keep scene files minimal.

## Key conventions & gotchas

- **Typed GDScript everywhere.** Use `var x: Type` and `func f() -> ReturnType`; match the existing style.
- **Grid coordinates are `Vector2i`**, used as keys in `grid_tiles`. Pixel ↔ grid conversion uses `cell_size = 40` and `grid_offset_y = 90` (top 90 px reserved for the UI header). Formula in `CP2020GameSession`: `Vector2(coord.x * 40 + 20, 90 + coord.y * 40 + 20)`.
- **Always read tiles via `layout.get_tile(coord)`**, never `grid_tiles.get(Vector2i(...))`. Serialised `.tres` files store dictionary keys as `"x,y"` strings; `get_tile` handles both forms, a direct lookup returns null.
- **Fog must be reset on load.** `load_subnet` resets `is_explored`/`is_visible` on every tile because `ResourceLoader` returns a cached instance — without this, a datafort revisited via LDL travel shows as already revealed.
- **Author floor tiles through the datafort designer, not by hand-editing `.tres`.** Hand-authored `Empty Path` floor tiles have failed to render in-game; the same tiles resaved through the designer render correctly. Hand-edit `.tres` only for tile properties (e.g. LDL link target fields).
- **LDL links are ENTRY tiles with `is_ldl_link = true`.** There is no separate "return" tile type. The interaction handler auto-offers Travel (menu id `3000`) + Return to City Grid (id `3001`). An LDL link with an empty `target_subnet_path` is effectively city-grid-return-only. LDL travel ids (`3000`/`3001`) are checked **before** the `1000+i` program range to avoid id collision.
- **Trace lifecycle:** `accumulated_trace` is reset on flatline / jack-out / return-to-world-map (City Grid's return action), but **preserved** across in-datafort LDL travel (`travel_ldl`) and across the datafort→City Grid return (`return_world_map` now targets the City Grid and keeps trace). Don't break this asymmetry.
- **ICE stat sourcing:** per-tile override fields (`ice_*` on `CP2020TileData`) take precedence; otherwise the datafort's `security_tier` (set at dive time via `RunState.selected_security_tier`) selects a default template from `TIER_ICE_TEMPLATES` in `CP2020GameSession`. Stats are set on the ICE node **before** `initialize()` (which copies `max_integrity` into `current_integrity`).
- **NPC stat sourcing:** same pattern as ICE — per-tile `npc_*` override fields take precedence; otherwise `TIER_NPC_TEMPLATES[_current_security_tier][faction]` supplies defaults. Programs are `duplicate()`d at spawn to avoid mutating cached `.tres` files. NetWatch spawns hostile; random netrunners spawn neutral until damaged.
- **Menu id collision hazard:** `_on_menu_action_selected` must check in this order: LDL travel (`3000`/`3001`) → NPC talk (`4000`) → NPC attack (`2000+i`) → program use (`1000+i`). Don't reorder.
- **Security tier source of truth:** `CP2020SecurityTier` (`scripts/resources/cp2020_security_tier.gd`) is the single const class for `Tier` enum + `LABELS`/`SHORT`/`COLORS`/`GLYPHS`. Tier is a **per-datafort** property on the City Grid (`CP2020CityGridDatafort.security_tier`); the legacy `security_tier` on `CP2020WorldHub` is kept for save compatibility only and no longer drives icons or ICE.
- **Signal connections are idempotent.** Components check `is_connected` before connecting (see `CP2020GameSession._ready`); follow the same pattern. Popup menus disconnect previous `id_pressed` connections before reconnecting to avoid duplicate callbacks.
- **Resource references are shared by default.** When editing loaded resources at runtime, prefer `duplicate()` or freshly instantiated `CP2020TileData` to avoid mutating cached instances across scenes.
- **Adding a new program:** create a `.tres` in `data/` with `script = res://scripts/resources/cp2020_programs.gd`, set `program_name`/`type`/`effect_type`/`memory_cost`/`strength`/`price`. See `ARCHITECTURE.md` §6.1.
- **Adding a new tile type:** add the `TileType` enum value in `CP2020DatafortLayout.gd`, then update rendering in `cp2020_board_renderer._draw_tile_graphics`, obstacle logic in `cp2020_netrunner.gd` / `cp2020_game_session._has_line_of_sight` / `cp2020_blackice._update_obstacles`, and the editor toolbar in `cp2020_datafort_designer.gd`. If the tile hosts an entity (like BLACK_ICE/NETWATCH/NETRUNNER), also add a `paint_tile` case, spawn function + tier templates in `cp2020_game_session.gd`, and an editor side panel. See `ARCHITECTURE.md` §6.2.

## Files that matter most

- `ARCHITECTURE.md` — full system reference; the first thing to read.
- `scripts/autoload/run_state.gd` — cross-scene state singleton.
- `scripts/resources/cp2020_game_session.gd` — gameplay orchestrator and the grid-math constants.
- `scripts/resources/cp2020_npc_netrunner.gd` — NPC netrunner node (NetWatch + random runners).
- `scripts/resources/CP2020DatafortLayout.gd` + `CP2020TileData.gd` — core data model.
- `scripts/resources/cp2020_security_tier.gd` — shared tier constants (single source of truth).
- `scripts/resources/cp2020_datafort_designer.gd`, `cp2020_world_map_designer.gd`, `cp2020_city_grid_designer.gd` — `@tool` authoring tools.
- `tools/generate_city_grids.gd` — city-grid generator script (run from the editor).