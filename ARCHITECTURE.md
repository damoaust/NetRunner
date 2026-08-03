# Netrunner V0.006 - Architecture & System Reference

This document provides a comprehensive breakdown of the system architecture, code organization, data models, signal flows, and mechanics for the Cyberpunk 2020 (CP2020) Netrunning game built in **Godot 4**. It is designed as a direct technical primer for coding agents and human developers.

---

## 1. Executive Overview & Tech Stack

- **Engine Version**: Godot 4.7 (Forward Plus rendering, 2D canvas nodes)
- **Language**: GDScript (using strictly typed variables, custom resources, enums, signals)
- **Theme/Genre**: Cyberpunk 2020 Netrunning simulation (grid-based datafort intrusion, fog-of-war matrix exploration, turn-based Black ICE pathfinding, program memory unit management)

---

## 2. Directory Structure

```
netrunner-v-0.006/
├── project.godot                     # Godot project configuration & input maps
├── data/                             # Resource instances (.tres) for decks, programs & maps
│   ├── starting_deck.tres            # Cyberdeck resource instance
│   ├── codecracker.tres              # Program resources (.tres)
│   ├── killer2.tres
│   ├── world_map_default.tres        # Default CP2020WorldMapLayout (regions + hubs, hub.city_grid_path)
│   ├── city_grids/                   # CP2020CityGridLayout per city (12 files)
│   │   ├── night_city.tres
│   │   ├── london.tres
│   │   └── ...
│   └── ...
├── scenes/                           # Godot scene files (.tscn)
│   ├── cp2020_gameplay.tscn          # Main gameplay (datafort) scene
│   ├── forts/                        # Saved datafort maps (.tres resources)
│   │   ├── night_city_subnet.tres
│   │   ├── london_subnet.tres
│   │   ├── tokyo_subnet.tres
│   │   └── fort1/2/3.tres
│   └── ui/                           # Subscenes (Netrunner avatar, Black ICE, Designers, Workbench, Maps)
│       ├── cp2020_blackice.tscn
│       ├── cp2020_npc_netrunner.tscn      # NPC netrunner scene (NetWatch + random runners)
│       ├── cp2020_netrunner.tscn
│       ├── cp2020_world_net_map.tscn       # World Map scene (geographic; ENTER city → City Grid)
│       ├── cp2020_world_map_designer.tscn  # World map authoring tool
│       ├── cp2020_city_grid.tscn           # City Grid scene (per-city datafort icons)
│       ├── cp2020_city_grid_designer.tscn  # City Grid authoring tool
│       ├── CP2020DesignerCanvas.tscn       # Datafort authoring tool
│       └── CyberdeckWorkbench.tscn         # Deck/program loadout UI
└── scripts/
    ├── autoload/
    │   └── run_state.gd              # RunState singleton — cross-scene run state
    ├── resources/                    # Core gameplay resources, nodes & controllers
    │   ├── CP2020DatafortLayout.gd   # Datafort grid layout Resource definition
    │   ├── CP2020TileData.gd         # Individual grid tile state Resource (incl. LDL fields)
    │   ├── CP2020WorldMapLayout.gd   # World map layout (regions + hubs) Resource
    │   ├── CP2020WorldHub.gd         # City hub Resource (name, pos, city_grid_path; tier kept for compat)
    │   ├── CP2020WorldRegion.gd      # World region Resource (name + colour, categorising only)
    │   ├── cp2020_security_tier.gd   # CP2020SecurityTier const class (Tier enum + LABELS/COLORS/GLYPHS)
    │   ├── cp2020_city_grid_datafort.gd # CP2020CityGridDatafort resource (datafort icon on a city grid)
    │   ├── cp2020_city_grid_layout.gd  # CP2020CityGridLayout resource (city grid layout)
    │   ├── cp2020_city_grid.gd       # City Grid runtime node (movement, dive, return to world map)
    │   ├── cp2020_city_grid_designer.gd # @tool City Grid authoring tool
    │   ├── cp_2020_world_net_map.gd  # Runtime world map node (movement, LDL jumps, ENTER city grid)
    │   ├── cp2020_blackice.gd        # Black ICE enemy AI node (AStarGrid2D, tracing)
    │   ├── cp2020_npc_netrunner.gd   # NPC netrunner node (NetWatch + random runners; cyberdeck, programs, AI)
    │   ├── cp2020_board_renderer.gd  # CanvasItem custom grid renderer (Fog of War)
    │   ├── cp2020_canvas.gd          # UI container grid loader (legacy/placeholder)
    │   ├── cp2020_cyberdecks.gd      # Cyberdeck data Resource class
    │   ├── cp2020_datafort_designer.gd # @tool editor for building maps + LDL-link editor
    │   ├── cp2020_game_session.gd    # Datafort session manager / orchestrator
    │   ├── cp2020_interaction_handler.gd # Contextual right-click PopupMenu handler
    │   ├── cp2020_netrunner.gd       # Player Netrunner entity controller
    │   ├── cp2020_programs.gd        # Software program Resource class
    │   ├── cp2020_subnet_loader.gd   # ResourceLoader for datafort layout files
    │   ├── cp2020_turn_manager.gd    # Turn state controller
    │   └── cp2020_world_map_designer.gd # @tool world map authoring tool
    └── ui/
        └── cyberdeck_workbench.gd    # Cyberdeck loadout & program management UI script
```

---

## 3. Core Architecture & Component Diagram

The gameplay loop is built around a decoupled component architecture. Cross-scene state lives in the `RunState` autoload singleton. The player flows through **three map levels** matching the CP2020 sourcebook: **Workbench** → **World Map** → **City Grid** → **Datafort (gameplay)**, with LDL links enabling travel between dataforts and back up the stack.

```mermaid
graph TD
    RunState["RunState (autoload: selected_deck, selected_subnet_path, selected_city_grid_path, selected_security_tier, credits, accumulated_trace)"]
    Workbench["CyberdeckWorkbench"]
    WorldMap["CP2020WorldNetMap (cp_2020_world_net_map.gd)"]
    CityGrid["CP2020CityGrid (cp2020_city_grid.gd)"]
    GameSession["GameSession (cp2020_game_session.gd)"]
    SubnetLoader["SubnetLoader (cp2020_subnet_loader.gd)"]
    BoardRenderer["BoardRenderer (cp2020_board_renderer.gd)"]
    Netrunner["CP2020Netrunner (cp2020_netrunner.gd)"]
    BlackIce["BlackIce (cp2020_blackice.gd)"]
    NpcNetrunner["NpcNetrunner (cp2020_npc_netrunner.gd)"]
    InteractionHandler["InteractionHandler (cp2020_interaction_handler.gd)"]
    TurnManager["TurnManager (cp2020_turn_manager.gd)"]

    Workbench -->|sets RunState.selected_deck| RunState
    Workbench -->|change_scene| WorldMap
    WorldMap -->|ENTER city: sets selected_city_grid_path + change_scene| CityGrid
    CityGrid -->|DIVE datafort: sets selected_subnet_path + selected_security_tier + change_scene| GameSession
    CityGrid -->|Return to World Map: reset trace + clear city-grid context| WorldMap
    GameSession -->|draw_grid(canvas, layout)| BoardRenderer
    GameSession -->|recalculate_fog_of_war| BoardRenderer
    Netrunner -->|position_changed| GameSession
    Netrunner -->|interacted_with_tile| GameSession
    InteractionHandler -->|action_triggered(name, coord, prog)| GameSession
    GameSession -->|execute_decryption / shield / ice_attack| Netrunner
    TurnManager -->|turn_ended| GameSession
    BlackIce -->|attacked_netrunner(strength)| GameSession
    NpcNetrunner -->|attacked_netrunner(strength)| GameSession
    NpcNetrunner -->|destroyed| GameSession
    GameSession -->|travel_ldl: load_subnet (preserve trace)| GameSession
    GameSession -->|return_world_map: change_scene to City Grid (preserve trace)| CityGrid
    GameSession -->|jack_out / flatline: reset trace + clear context + change_scene| WorldMap
    BlackIce -->|flatline -> change_scene| Workbench
```

### Scene Flow (3-Level Map Model)

1. **CyberdeckWorkbench** — pick a deck and load programs, then `Jack In`.
2. **World Map** (`cp2020_world_net_map.tscn`) — geographic grid of regions + city markers. Move between cities; hack/pay LDL to build trace. Right-click a city → **ENTER City Grid** (loads that city's `CP2020CityGridLayout` via `hub.city_grid_path`).
3. **City Grid** (`cp2020_city_grid.tscn`) — per-city grid of datafort icons (security-tier coded). Runner enters at the LDL entry tile, moves 5/turn. **Stepping onto a datafort icon auto-dives** into its subnet (no Hack/Pay LDL here — that's world-map only). Right-click the runner's tile to **Return to World Map** (resets trace).
4. **Gameplay / Datafort** (`cp2020_gameplay.tscn`) — explore the datafort with fog of war, fight ICE, use programs. LDL-link tiles travel to other dataforts (preserve trace) or **Return to City Grid** (preserve trace — still in the run). Jack-out / flatline returns to the World Map and resets trace (full abort).

---

## 4. Data Models (Custom Resources)

All data objects inherit from `Resource` to allow direct serialization to `.tres` files and inspector editing.

### 4.1 `CP2020DatafortLayout` ([CP2020DatafortLayout.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/CP2020DatafortLayout.gd))
Represents a grid map layout for a Datafort.
- **Properties**:
  - `fort_name: String`
  - `rows: int` (default 15)
  - `columns: int` (default 15)
  - `cpu: int`, `int_rating: int`, `datawall_strength: int`
  - `grid_tiles: Dictionary` - Maps `Vector2i(x, y)` to [CP2020TileData](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/CP2020TileData.gd)
- **TileType Enum**:
  - `EMPTY` (0), `WALL` (1), `DATAWALL` (2), `ENTRY` (3), `CODE_GATE` (4), `MEMORY_UNIT` (5), `CONTROL_NODE` (6), `BLACK_ICE` (7), `NETWATCH` (8), `NETRUNNER` (9)

### 4.2 `CP2020TileData` ([CP2020TileData.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/CP2020TileData.gd))
Represents state and attributes of a single cell in the datafort layout grid.
- **Properties**:
  - `tile_type: CP2020DatafortLayout.TileType`
  - `tile_name: String`
  - `strength_str: int` (Used as hit points / Difficulty Value for Code Gates and Datawalls)
  - `memory_units_mu: int`
  - `reward_credits: int`
  - `is_unlocked: bool` (Breach / Decrypted state for Code Gates)
  - `ldl_links: Dictionary` (legacy, unused — kept for save compat)
  - `is_visible: bool` (Dynamic Line of Sight visibility)
  - `is_explored: bool` (Visited or previously seen tile state for Fog of War)
  - **LDL Routing** (authored in the datafort designer's LDL-link editor):
    - `is_ldl_link: bool` — marks the tile as a Long Distance Line connection point
    - `target_subnet_path: String` — `.tres` resource path to the linked remote datafort (empty = world-map-return-only)
    - `target_entry_coord: Vector2i` — arrival coordinate in the remote subnet (`(-1,-1)` = unset; falls back to first ENTRY)
  - **Per-tile ICE overrides** (BLACK_ICE tiles; authored in the datafort designer's ICE editor; zero/empty = use the hub security-tier template):
    - `ice_program_name: String`, `ice_strength: int`, `ice_max_ap: int`, `ice_max_integrity: int`, `ice_traces: bool`
    - `ice_has_override: bool` — set true when any field is non-zero/non-empty; the runtime prefers tile stats over the tier template when this is set
  - **Per-tile NPC overrides** (NETWATCH / NETRUNNER tiles; authored in the datafort designer's NPC editor; zero/empty = use the hub security-tier template):
    - `npc_name: String`, `npc_strength: int`, `npc_max_ap: int`, `npc_max_integrity: int`, `npc_max_health: int`, `npc_max_mu: int`, `npc_deck_name: String`, `npc_disposition: int` (0 = Hostile, 1 = Neutral)
    - `npc_has_override: bool` — set true when any field is non-zero/non-empty; the runtime prefers tile stats over the tier template when this is set
    - `npc_programs: Array[NetProgram]` — optional hand-authored loadout (empty = template loadout)

### 4.3 `CP2020WorldMapLayout` ([CP2020WorldMapLayout.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020WorldMapLayout.gd))
Serializable world map authored by the world map designer and loaded at runtime by `cp_2020_world_net_map.gd`.
- **Properties**:
  - `grid_cols: int`, `grid_rows: int` (default 32×18)
  - `regions: Array[CP2020WorldRegion]` — colour + label only (categorising; never block movement)
  - `tile_region: Dictionary` — `Vector2i`/`"x,y"` → region index; absent keys = open ocean
  - `hubs: Array[CP2020WorldHub]` — city hubs overlaying their region tile
  - `runner_spawn_hub: String` (default "Night City")
- **Helpers**: `get_region(pos)`, `get_hub(pos)`, `get_hub_by_name(name)`

### 4.4 `CP2020WorldHub` ([CP2020WorldHub.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_world_hub.gd))
- `name: String`, `pos: Vector2i`, `subnet_path: String` (legacy fallback datafort `.tres`; the City Grid is now the entry point), `ldl_cost: int`, `security_code: int` (1D10 target to hack the LDL), `trace_value: int` (trace added on a successful jump through this hub's LDL)
- `city_grid_path: String` — path to the city's `CP2020CityGridLayout` `.tres`. The world map ENTER action loads this. **This is the primary link from the world map into a city.**
- `security_tier: int` — CP2020 classification (CP2020SecurityTier.Tier: `GREY=0`, `LEVEL_1=1`, `LEVEL_2=2`, `LEVEL_3=3`, `BLACK=4`). **Kept for save compatibility only** — tier no longer drives world-map icons (cities are plain markers) and no longer drives datafort ICE; the per-datafort tier on the City Grid is now the source of truth for ICE loadouts. Tier metadata consts live in `CP2020SecurityTier` (see 4.8).
- `security_code` (LDL hack difficulty) and `security_tier` (classification) are kept separate per the sourcebook.

### 4.5 `CP2020WorldRegion` ([CP2020WorldRegion.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_world_region.gd))
- `name: String`, `color: Color` — purely visual categorisation; ocean is the absence of a region assignment.

### 4.6 `CP2020SecurityTier` ([cp2020_security_tier.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_security_tier.gd)) — *NEW*
Shared const class (single source of truth for tier rendering). Referenced as `CP2020SecurityTier.Tier.GREY`, `CP2020SecurityTier.COLORS[tier]`, etc.
- `enum Tier { GREY, LEVEL_1, LEVEL_2, LEVEL_3, BLACK }`
- `LABELS: Dictionary` — full labels (`"Grey"`, `"Level 1"`, ..., `"Black"`)
- `SHORT: Dictionary` — short tags (`"G"`, `"L1"`, `"L2"`, `"L3"`, `"B"`)
- `COLORS: Dictionary` — tier colours (Grey=grey, L1=green, L2=yellow, L3=orange, Black=red)
- `GLYPHS: Dictionary` — single-char icon glyphs (`"G"`, `"1"`, `"2"`, `"3"`, `"B"`)

### 4.7 `CP2020CityGridDatafort` ([cp2020_city_grid_datafort.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_city_grid_datafort.gd)) — *NEW*
A datafort icon on a City Grid. Tier classifies the datafort (per sourcebook), and the runtime reads `security_tier` at dive time to set `RunState.selected_security_tier`.
- `name: String`, `pos: Vector2i` (grid tile)
- `subnet_path: String` — the datafort interior `.tres` (e.g. `night_city_subnet.tres`)
- `security_tier: int` (CP2020SecurityTier.Tier) — drives the icon colour/glyph AND the datafort's default ICE loadout
- `ldl_cost: int` (default 50), `security_code: int` (default 4, 1D10 hack target), `trace_value: int` (default 5)

### 4.8 `CP2020CityGridLayout` ([cp2020_city_grid_layout.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_city_grid_layout.gd)) — *NEW*
Serializable per-city grid authored by the City Grid designer and loaded at runtime by `cp2020_city_grid.gd`.
- `city_name: String`, `grid_cols: int` (default 20), `grid_rows: int` (default 12)
- `dataforts: Array[CP2020CityGridDatafort]` — the datafort icons on the grid
- `ldl_entry: Vector2i` — the runner arrival tile from the world map
- **Helpers**: `get_datafort(pos)`, `get_datafort_by_name(name)`

### 4.9 `Cyberdeck` ([cp2020_cyberdecks.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_cyberdecks.gd))
Represents the Netrunner's hardware deck.
- **Properties**:
  - `deck_name: String`
  - `max_mu: int` (Maximum Memory Units storage capacity)
  - `speed_bonus: int`
  - `data_wall_strength: int`
  - `interface_rank: int` (default 6) — the Netrunner's Interface skill when using this deck; read by the world map and shown in the workbench.
  - `installed_programs: Array[NetProgram]`
- **Methods**: `get_used_mu() -> int`

### 4.10 `NetProgram` ([cp2020_programs.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_programs.gd))
Represents an executable program software tool loaded into a cyberdeck.
- **ProgramType Enum**: `DECRYPTION`, `DETECTION`, `ANTI_PROGRAM`, `ANTI_PERSONNEL`, `ANTI_SYSTEM`, `UTILITY`, `ICE`
- **EffectType Enum**:
  - `BYPASS_GATE`: Cracks Code Gates (sets `is_unlocked = true`)
  - `BREACH_WALL`: Breaches Datawalls
  - `DEREZ_ICE`: Destroys hostile Black ICE
  - `DAMAGE_RUNNER`: Black ICE direct attacks
  - `REVEAL_NODES`: Scans hidden layout nodes
  - `MODIFY_MU`: Modifies deck speed or memory capacity
  - `SHIELD`: Defense program (raised on the runner's own tile)
- **Properties**: `program_name`, `type`, `effect_type`, `memory_cost` (MU), `strength`, `price`, `icon`, `description` (one-line summary shown in the workbench detail card)

---

## 5. Core Systems & Implementation Details

### 5.1 Game Session Orchestrator ([cp2020_game_session.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_game_session.gd))
Controls gameplay flow, scene initialization, input routing, turn changes, terminal logs, and program interactions.
- **Constants & Grid Math**:
  - `cell_size = 40` px
  - `grid_offset_y = 90` px (Reserving top UI header space)
  - Coordinates match formula: `Vector2(coord.x * 40 + 20, 90 + coord.y * 40 + 20)`
- **`_ready`**: connects interaction/turn/netrunner signals, applies `RunState.selected_deck` to the netrunner (deck name, MU capacity, duplicate of installed programs), loads the subnet from `RunState.selected_subnet_path` (or `starting_subnet_path` fallback), and refreshes deck/health/trace HUD.
- **`load_subnet(path, entry_coord)`**: Loads a `CP2020DatafortLayout` via `ResourceLoader`, assigns it to the renderer, **resets `is_explored`/`is_visible` on every tile** (ResourceLoader returns a cached instance, so a previously-visited datafort would otherwise show as already-revealed after LDL travel), spawns the netrunner at `entry_coord`, spawns ICE + NPCs, and recalculates fog. A fresh run always starts fully fogged.
- **LDL Travel** (`_on_action_triggered`):
  - `"travel_ldl"` — the program arg is the `CP2020TileData` of the LDL link; loads its `target_subnet_path` at `target_entry_coord`. Aborts with a terminal message if no target is set. Trace is preserved across the jump.
  - `"return_world_map"` — changes scene to the **City Grid** (`cp2020_city_grid.tscn`) via `RunState.selected_city_grid_path` (world-map fallback if no city grid recorded) and **preserves trace** (still in the run). Labelled "Returning to the City Grid via LDL."
- **Jack-out** (`_on_jack_out_pressed`) / **Flatline** (`_on_flatlined`): clears `accumulated_trace` + `selected_city_grid_path` + `selected_security_tier` (full abort) and changes scene to the world map.
- **Flatline**: on `netrunner.flatlined`, clears trace and returns to the workbench scene (`CyberdeckWorkbench.tscn`).
- **Camera Follow**: a `Camera2D` ("RunnerCamera") is parented under the board renderer; `_update_camera_limits` clamps it to the datafort rect and `_center_camera_on_runner` snaps it to the netrunner. `netrunner.position_changed` re-centres the camera.
- **Trace HUD**: `_update_trace()` writes `RunState.accumulated_trace` to the `TraceLabel`.
- **Line of Sight / Fog of War**:
  - Uses a grid-based Bresenham raycasting line-of-sight algorithm ([_has_line_of_sight](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_game_session.gd#L163)) up to `vision_radius = 10`.
  - Blocked by `DATAWALL` tiles and locked `CODE_GATE` tiles (`is_unlocked == false`).
  - Sets `tile.is_visible = true` and `tile.is_explored = true`.
- **Decryption Mechanics**:
  - Initiated when player selects a decryption program (`BYPASS_GATE`) via right-click contextual menu on a Code Gate.
  - Roll: `(randi() % 10) + 1 + program.strength` (Cyberpunk 2020 1d10 + Program STR rule).
  - Check: If `total_roll >= tile.strength_str`, `tile.is_unlocked = true`, immediately clearing the movement obstacle, changing tile color from orange to green, and recalculating Line of Sight. Otherwise, the attempt fails and logs the roll details to the terminal.
- **NPC Spawning** (`spawn_npcs`, parallel to `spawn_black_ice`): iterates NETWATCH/NETRUNNER tiles, applies per-tile `npc_*` overrides or falls back to `TIER_NPC_TEMPLATES[_current_security_tier][faction]` (NetWatch leans anti-personnel + shield; random netrunners lean utility + weak attack). Programs are `duplicate()`d at spawn. NPCs are added to `npc_nodes` and their signals connected (`message_logged`, `moved_to`, `attacked_netrunner`, `destroyed`).
- **Turn Execution**: `_all_adversaries()` merges `ice_nodes` + `npc_nodes` into one array passed to `turn_manager.execute_ice_turns`. The turn manager calls `take_turn(target, layout)` on any node that has the method, so NPCs drop in without changing its signature.
- **NPC Combat**: `execute_npc_attack(program, coord)` resolves an opposed 1D10+STR roll vs the NPC's strength (same convention as `execute_ice_attack`); `take_damage` handles destruction + the provoked transition. `_talk_to_npc(coord)` logs flavour text for neutral runners (placeholder for future dialogue/trading).

### 5.2 Board Renderer ([cp2020_board_renderer.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_board_renderer.gd))
Performs procedural drawing via `CanvasItem.draw_*` calls based on the 3 tile visibility states:
1. **Unexplored (`is_explored == false`)**: Solid black background (`Color.BLACK`).
2. **Explored / Fog of War (`is_explored == true`, `is_visible == false`)**: Darkened floor tile (`Color(0.04, 0.04, 0.05)`), faint grid outlines (`alpha = 0.3`), dimmed tile graphics.
3. **Visible (`is_visible == true`)**: Bright floor tile (`Color(0.08, 0.08, 0.08)`), vibrant grid borders (`Color(0.3, 0.4, 0.5)`), full opacity tile graphics:
   - `ENTRY`: Green/Cyan outlined box with directional polygon glyph
   - `DATAWALL`: Solid red barrier box
   - `CODE_GATE`: Orange barrier (locked) or Green barrier (unlocked) with dividing horizontal beam

### 5.3 Player Netrunner Controller ([cp2020_netrunner.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_netrunner.gd))
- Handles keyboard movement (`WASD` or Arrow keys via `ui_up`, `ui_down`, `ui_left`, `ui_right`).
- Checks boundaries against layout bounds (`0..columns-1`, `0..rows-1`).
- Validates movement obstacles: blocks movement into `DATAWALL` tiles or locked `CODE_GATE` tiles. Empty cells (no tile) are walkable.
- `initialize(layout, entry_coord)`: spawns at `entry_coord` if supplied, in-bounds, and a tile exists there (used by mid-run LDL travel); otherwise falls back to the first `ENTRY` tile.
- Emits `position_changed`, `message_logged`, `deck_updated`, `shield_raised`, `shield_consumed`, `health_changed`, and `flatlined` (when `current_health <= 0`).

### 5.4 Hostile Black ICE AI ([cp2020_blackice.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_blackice.gd))
- **Pathfinding**: Instantiates an `AStarGrid2D` instance over the layout matrix region.
- Dynamic obstacle update ([_update_obstacles](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_blackice.gd#L99)): dynamic solid points applied to `DATAWALL` tiles and locked `CODE_GATE` tiles.
- **States**: `IDLE` -> `PURSUE`. Activates upon turn execution, taking up to `max_ap` (3) steps per turn toward the Netrunner's position. On reaching the runner, emits `attacked_netrunner(strength)`.
- **Tracing ICE** (`traces: bool`): on first activation, rolls `1D10 + strength` vs `RunState.accumulated_trace`; if the roll is **less than** the trace difficulty the ICE fails to locate the signal and stays idle. Higher accumulated trace makes tracing ICE easier to spot you.
- **Fog of War Visibility**: Dynamically updates the `skull_label` icon visibility based on the tile fog state.
- **Stat sourcing** (see `cp2020_game_session.spawn_black_ice`): ICE stats are set on the node **before** `initialize()` (which copies `max_integrity` into `current_integrity`). Per-tile override fields (`ice_*` on `CP2020TileData`) take precedence; otherwise the hub's `security_tier` selects a default template from `TIER_ICE_TEMPLATES` (Grey→Watchdog, L1→Killer 1.0, L2→Killer 2.0, L3→Hellhound, Black→Flatline).

### 5.4b NPC Netrunner AI ([cp2020_npc_netrunner.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_npc_netrunner.gd)) — *NEW*
- Full netrunner-entity NPCs (cyberdeck, programs, health, MU) — not contact-attack pathfinders like Black ICE. One node class serves two factions via a `Faction` enum (`NETWATCH`, `NETRUNNER`) and a `Disposition` enum (`HOSTILE`, `NEUTRAL`).
- **NetWatch** (`Faction.NETWATCH`): spawns `Disposition.HOSTILE` — pursues and attacks the player on sight.
- **Random Netrunner** (`Faction.NETRUNNER`): spawns `Disposition.NEUTRAL` — wanders randomly (~50% idle, otherwise steps to a walkable neighbour) until provoked. `take_damage` flips NEUTRAL→HOSTILE for the rest of the run.
- **AI**: HOSTILE NPCs reuse the Black ICE `AStarGrid2D` pursuit pattern (up to `max_ap` steps per turn; attack on reaching the player's tile). `_attack_player()` prefers a `SHIELD` program when hurt, else an anti-personnel (`DAMAGE_RUNNER`) program, falling back to base `strength`. NEUTRAL NPCs wander and do not path toward the player.
- **Signals**: `message_logged`, `moved_to`, `attacked_netrunner(strength)`, `destroyed`, `took_damage`. The session connects `attacked_netrunner` → `_on_ice_attacked` (shared handler) and `destroyed` → `_on_npc_destroyed` (erases from `npc_nodes`).
- **Stat sourcing** (see `cp2020_game_session.spawn_npcs`): NPC stats are set **before** `initialize()`. Per-tile override fields (`npc_*` on `CP2020TileData`) take precedence; otherwise the hub's `security_tier` selects a default template from `TIER_NPC_TEMPLATES` (per faction, per tier). Program resources from templates are `duplicate()`d at spawn to avoid mutating cached `.tres` files.
- **Fog of War**: `update_visibility(explored, visible)` toggles the glyph label like Black ICE. The session's `recalculate_fog_of_war` syncs NPC visibility each move.

### 5.5 Contextual Right-Click Input Handler ([cp2020_interaction_handler.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_interaction_handler.gd))
- Captures right-click mouse events over grid cells.
- Converts mouse pixel coordinates to grid cell coordinates `Vector2i(grid_x, grid_y)`.
- Checks if tile `is_explored` (menus are blocked on unexplored tiles). **Must use `layout.get_tile(coord)`** — `.tres` files store dictionary keys as `"x,y"` strings, so a direct `grid_tiles.get(Vector2i)` always returns null.
- **Menu branches** (first match wins):
  - **LDL-link tiles** (`is_ldl_link`): always add "Travel to \<datafort\>" (id `3000`) + "Return to City Grid" (id `3001`), even with no matching program. Travel uses `_ldl_tile` (the stored tile data); empty target → the session aborts the travel with "no target subnet set", so an empty-target LDL link effectively offers city-grid-return only.
  - **Visible Black ICE on the tile**: offer `DEREZ_ICE` programs (ids `1000+i`).
  - **Visible NPC netrunner on the tile**: offer `DAMAGE_RUNNER` and `DEREZ_ICE` programs (ids `2000+i`) to attack the NPC, plus a "Talk" item (id `4000`) for neutral runners. `_npc_target` stores the NPC node for the callback.
  - **Runner's own tile** (visible): offer `SHIELD` defense programs.
  - **Locked Code Gate**: offer `BYPASS_GATE` programs.
  - **Datawall**: offer `BREACH_WALL` programs.
- `_on_menu_action_selected` checks ids in this order to avoid collision: LDL travel (`3000`/`3001`) → NPC talk (`4000`) → NPC attack (`2000+i`) → program use (`1000+i`).
- Dynamically creates and opens a `PopupMenu` near mouse location (`popup_on_parent`).

### 5.6 Datafort Designer Tool ([cp2020_datafort_designer.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_datafort_designer.gd))
- Runs in editor (`@tool` annotation).
- Visual editor interface for painting tiles. The toolbar has distinct **Entry** (plain datafort arrival point, `is_ldl_link=false`) and **LDL Link** (travel node, `is_ldl_link=true` with no hardcoded target) buttons, plus Datawall, Code Gate, Memory Unit, Control Node, Black ICE, **NetWatch**, **Netrunner**, and Eraser.
- **LDL-Link Editor panel** (built in code as a `PanelContainer`+`VBox` anchored to the right edge so it stays on-screen): target subnet `LineEdit` + Browse `FileDialog` (scoped to `scenes/forts/*.tres`), target entry coord X/Y `SpinBox`es, and a "Clear target" button. In LDL mode, clicking an existing LDL link selects it for editing (does not overwrite); clicking empty space paints a new link and opens the editor. Field edits write back to the tile live and persist on save. Empty target = world-map-return-only. LDL links draw with a distinct blue frame + "L" glyph.
- **ICE Editor panel** (built in code; shown when a BLACK_ICE tile is painted/selected): program name `LineEdit`, strength/AP/integrity `SpinBox`es, traces `CheckBox`, and a "Reset to template" button. Leave fields at 0/empty to use the hub's tier template; set any field to override the template for that tile. Edits write back to the tile's `ice_*` fields live and persist on save.
- **NPC Editor panel** (built in code; shown when a NETWATCH/NETRUNNER tile is painted/selected): name `LineEdit`, strength/AP/integrity/health/MU `SpinBox`es, deck name `LineEdit`, disposition `OptionButton` (Hostile/Neutral), and a "Reset to template" button. Leave fields at 0/empty to use the hub's tier template; set any field to override. Edits write back to the tile's `npc_*` fields live and persist on save. NETWATCH tiles draw a red shield glyph; NETRUNNER tiles draw a gold person glyph.
- Dynamic layout resizing (`SpinBox` input for columns/rows).
- Native file open/save dialog integration (`FileDialog`) for loading and exporting `.tres` layout files.

### 5.7 World Map Designer Tool ([cp2020_world_map_designer.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_world_map_designer.gd))
- `@tool` editor that authors a `CP2020WorldMapLayout` `.tres` (regions + hubs) consumed at runtime by `cp_2020_world_net_map.gd`.
- Tools: `REGION` (paint region colour), `HUB` (place/select a hub), `ERASER`.
- Side panel edits the selected hub: name, subnet path (+ Browse), **City Grid path** (+ Browse `data/city_grids/*.tres`, writes `hub.city_grid_path`), LDL cost, security code, trace value, set-as-spawn, delete. The Security Tier `OptionButton` is **hidden** (tier moved to City Grid dataforts; field kept on the resource for save compat). Hub chips are drawn as plain cyan markers (no tier glyph). Region list with add/paint.

### 5.7b City Grid Designer Tool ([cp2020_city_grid_designer.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_city_grid_designer.gd)) — *NEW*
- `@tool` editor that authors a `CP2020CityGridLayout` `.tres` (dataforts + LDL entry) consumed at runtime by `cp2020_city_grid.gd`. Save/Load to `data/city_grids/*.tres`.
- Tools: `DATAFORT` (place/select), `LDL_ENTRY` (set the runner arrival tile), `ERASER` (remove a datafort). Settings row: city name `LineEdit`, Cols/Rows `SpinBox`es + Apply Size.
- Side panel edits the selected datafort: name, subnet path (+ Browse `scenes/forts/*.tres`), **Security Tier** `OptionButton` (populated via `CP2020SecurityTier.LABELS`), LDL cost, security code, trace value, delete.
- `_draw`: grid + datafort chips in tier colour (`CP2020SecurityTier.COLORS`) with tier glyph (`CP2020SecurityTier.GLYPHS`) + name; LDL entry ring marker.

### 5.8 Cyberdeck Workbench UI ([cyberdeck_workbench.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/ui/cyberdeck_workbench.gd))
- Deck selection via an `OptionButton` (`available_decks`); stats (Model, Speed, MU used/total + coloured MU bar, Data Wall STR, Interface Rank from the deck resource) refresh on selection. The whole UI is built in code from a minimal scene root (matching the designer-panel pattern).
- Three-zone layout: **Deck Stats** (left) | **Loaded into Memory** + `LOAD ▶` / `◀ UNLOAD` / `CLEAR` buttons (centre) | **Program Library** + filter `OptionButton` + detail card (right).
- Two `ItemList`s: **Library** (all `available_programs`, filtered by EffectType category) and **Loaded** (the active deck's `installed_programs`). Items are colour-coded per `EffectType`; library items that won't fit in the remaining MU are greyed out and disabled.
- Click a list item to select it and populate the **detail card** (name, type, effect, STR, MU, price, description). Double-click (or the buttons) load/unload. Load refuses on MU overflow and shows an on-screen `MEMORY FULL` message instead of console `print`.
- MU bar colour states: green (<70%), amber (70–95%), red (≥95%/over).
- `Jack In` writes the active deck to `RunState.selected_deck` and changes scene to the world map. Jacking in with zero programs loaded shows a warning and is blocked until at least one program is loaded.
- Loadouts persist across deck switches within a session (edits mutate the in-memory deck resource directly).

### 5.9 World Map Runtime ([cp_2020_world_net_map.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp_2020_world_net_map.gd))
- Geographic grid titled **"WORLD MAP"**. Runner spawns on the configured spawn hub (Night City fallback) and moves tile-by-tile with a 5-action turn limit (no ICE on the world map). Regions are categorising only — any in-bounds tile is traversable, including open ocean. No tier legend (tier is a datafort property, shown on the City Grid).
- **Plain city markers**: each hub is drawn as a cyan ring + name (tier glyphs removed — tier moved to City Grid datafort icons). The spawn hub additionally shows a cyan "LDL" entry marker.
- Right-click the runner's tile when on a hub opens the popup: **ENTER \<city\> City Grid** (loads `hub.city_grid_path`), **Hack LDL →** or **Pay LDL →** to each nearby hub (Chebyshev ≤ 5). Popup items no longer carry tier tags.
  - **Hack**: `1D10 >= destination security_code` → teleport + add `trace_value`; fail → `_caught_table` (1D6 consequences).
  - **Pay**: deduct `ldl_cost` credits, teleport + add `trace_value`.
  - **ENTER City Grid**: sets `RunState.selected_city_grid_path = hub.city_grid_path`, changes scene to `cp2020_city_grid.tscn`. Adds no trace.
- HUD: Actions, Credits (`RunState.credits`), Location (hub/region/ocean), Trace (`RunState.accumulated_trace`).
- Camera follow via a `Camera2D` clamped to the map rect and centred on the runner.

### 5.10 City Grid Runtime ([cp2020_city_grid.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_city_grid.gd)) — *NEW*
- Per-city grid (`cp2020_city_grid.tscn`) loaded from `RunState.selected_city_grid_path` (`CP2020CityGridLayout`). Runner spawns on `ldl_entry` and moves 5 actions/turn. Reuses the world map movement/camera pattern.
- **Tier-coded datafort icons**: each datafort is drawn as a filled chip in its `security_tier` colour (via `CP2020SecurityTier.COLORS`) with the tier glyph (`CP2020SecurityTier.GLYPHS`) and the datafort name. The LDL entry tile shows a cyan "LDL" ring marker.
- **Stepping onto a datafort icon auto-dives** into its subnet (sets `RunState.selected_subnet_path` + `selected_security_tier`, keeps `selected_city_grid_path`, changes scene to gameplay). No Hack/Pay LDL on the city grid — that is a world-map-only mechanic; dataforts are reached by walking.
- Right-click the runner's tile → **Return to World Map** popup (resets `accumulated_trace`, clears `selected_city_grid_path` + `selected_security_tier`, changes scene to the world map) / Cancel.
- HUD: Actions, Credits, Location (datafort/city), Trace.

### 5.11 Cross-Scene State & Trace ([run_state.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/autoload/run_state.gd))
- `RunState` is an autoload singleton holding state that survives scene changes within a run: `selected_deck`, `selected_subnet_path`, `selected_city_grid_path`, `selected_security_tier`, `credits`, and `accumulated_trace`.
- **`selected_city_grid_path`** — the city grid currently in play, so the datafort LDL-return can go back to the right city grid.
- **`selected_security_tier`** — set at dive time by the City Grid (the datafort icon's tier); read by `game_session._resolve_security_tier()` for the default ICE loadout. Fallback `LEVEL_1`.
- **Trace** (`accumulated_trace`): the total Trace Value of all LDLs passed through in the current Net run. It drives tracing-ICE detection rolls (ICE must roll `1D10+STR ≥ trace` to locate the runner) and is shown on the world map, city grid, and datafort HUDs. It is **reset to 0** on flatline, jack-out, and return-to-world-map; it is **preserved** across in-datafort LDL travel AND across the datafort→City Grid return (mid-run retreat keeps the trace).
- `reset()` clears the run state for a fresh run (including the new city-grid fields).

### 5.11 Camera Follow
- Both the world map and the datafort gameplay use a `Camera2D` ("RunnerCamera") parented under the rendered grid. Limits are clamped to the grid rect so the camera never shows outside the map. The camera re-centres on the runner on every position change (`netrunner.position_changed` / world map move).

---

## 6. Guide for Future Coding Agents

### 6.1 How to Add a New Program
1. Create a new `.tres` resource file in [data/](file:///c:/Users/mecca/Documents/netrunner-v-0.006/data/).
2. Set `script = ExtResource("res://scripts/resources/cp2020_programs.gd")`.
3. Configure properties (`program_name`, `type`, `effect_type`, `memory_cost`, `strength`, `price`).
4. To add a program to the player starting loadout, add it to the `installed_programs` array on [cp2020_netrunner.tscn](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scenes/ui/cp2020_netrunner.tscn) or within [cp2020_gameplay.tscn](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scenes/cp2020_gameplay.tscn).

### 6.2 How to Add a New Tile Type
1. Add the enum value to `TileType` in [CP2020DatafortLayout.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/CP2020DatafortLayout.gd).
2. Update graphics rendering in [_draw_tile_graphics](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_board_renderer.gd#L40).
3. Update obstacle logic in [cp2020_netrunner.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_netrunner.gd#L86), [_has_line_of_sight](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_game_session.gd#L163), and [_update_obstacles](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_blackice.gd#L85).
4. Update the editor toolbar buttons in [cp2020_datafort_designer.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_datafort_designer.gd#L88).
5. If the tile hosts an entity (like BLACK_ICE/NETWATCH/NETRUNNER), add a `paint_tile` case, a spawn function + tier templates in [cp2020_game_session.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_game_session.gd), and an editor side panel (mirror `build_ice_panel`/`build_npc_panel`).

### 6.3 Important Conventions & Gotchas
- **Grid Offset**: The top 90 pixels of the viewport are reserved for UI elements. Always convert world mouse clicks or tile positions using `grid_offset_y = 90` and `cell_size = 40`.
- **Vector2i Coordinates**: Grid positions are integer vectors (`Vector2i`), used as keys in `current_layout.grid_tiles`.
- **`.tres` string keys**: `grid_tiles` dictionaries store keys as `"x,y"` strings when serialised. Always read tiles via `layout.get_tile(coord)` (which handles both `Vector2i` and string keys); never `grid_tiles.get(Vector2i)`.
- **Fog reset on load**: `load_subnet` resets `is_explored`/`is_visible` on every tile because `ResourceLoader` returns a cached instance. Without this, a datafort revisited via LDL travel would show as already-revealed.
- **Floor tiles via designer only**: Hand-authored `.tres` `Empty Path` floor tiles have failed to render in-game, but the same tiles resaved through the datafort designer render correctly. Author floor tiles through the designer; hand-edit `.tres` only for tile properties (e.g. LDL link target fields).
- **LDL link is an ENTRY tile**: There is no separate "return" tile type. Any `ENTRY` tile with `is_ldl_link=true` auto-offers Travel (id `3000`) + Return to City Grid (id `3001`) via the interaction handler. An LDL link with an empty `target_subnet_path` is effectively city-grid-return-only.
- **Trace lifecycle**: `accumulated_trace` resets on flatline / jack-out / return-to-world-map (City Grid return-to-world-map), but is **preserved** across in-datafort LDL travel (`travel_ldl` keeps it) AND across the datafort→City Grid return (`return_world_map` now goes to the City Grid and keeps trace).
- **Lambda Signal Connections**: Popup menus disconnect previous `id_pressed` connections before reconnecting to prevent duplicate signal callbacks. Menu id ranges are a collision hazard — check in this order in `_on_menu_action_selected`: LDL travel (`3000`/`3001`) → NPC talk (`4000`) → NPC attack (`2000+i`) → program use (`1000+i`).
- **NPC program duplication**: `TIER_NPC_TEMPLATES` stores program resource paths (not names). `spawn_npcs` loads and `duplicate()`s each program so cached `.tres` resources are never mutated across runs. The same applies to per-tile `npc_programs` via `_duplicate_programs`.
- **NPC disposition transition**: A neutral netrunner who takes damage flips to hostile for the rest of the run (once hostile, stays hostile). Only damage triggers this — talking does not.
- **@tool panels in code**: The datafort and world map designers build their side panels in code (anchored to stay on-screen) rather than in the `.tscn`, so the scene files stay minimal.
- **Resource Persistence**: Layouts are saved as `.tres` resources containing `grid_tiles` dictionaries. When editing resources at runtime, prefer duplicate or freshly instantiated `CP2020TileData` objects to avoid shared reference bugs.
