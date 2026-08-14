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
│   ├── watchdog.tres                 # Watchdog — Detection/Alarm program (STR 4, 610eb, 5 MU)
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
    │   ├── run_state.gd              # RunState singleton — cross-scene PER-LIFE run state (lost on death)
    │   ├── meta_state.gd             # MetaState singleton — PERSISTENT vendor catalogue (survives death)
    │   └── meta_state_data.gd        # MetaStateData Resource (unlocked_decks/programs + run history)
    ├── resources/                    # Core gameplay resources, nodes & controllers
    │   ├── CP2020DatafortLayout.gd   # Datafort grid layout Resource definition
    │   ├── CP2020TileData.gd         # Individual grid tile state Resource (incl. LDL fields)
    │   ├── CP2020WorldMapLayout.gd   # World map layout (regions + hubs) Resource
    │   ├── CP2020WorldHub.gd         # City hub Resource (name, pos, city_grid_path; tier kept for compat)
    │   ├── CP2020WorldRegion.gd      # World region Resource (name + colour, categorising only)
    │   ├── cp2020_security_tier.gd   # CP2020SecurityTier const class (Tier enum + LABELS/COLORS/GLYPHS)
    │   ├── cp2020_city_grid_datafort.gd # CP2020CityGridDatafort resource (datafort icon on a city grid)
    │   ├── cp2020_city_grid_layout.gd  # CP2020CityGridLayout resource (city grid layout)
    │   ├── cp2020_city_grid.gd       # City Grid runtime node (movement, dive, return to world map / jack out to hub)
    │   ├── cp2020_city_grid_designer.gd # @tool City Grid authoring tool
    │   ├── cp_2020_world_net_map.gd  # Runtime world map node (movement, LDL jumps, ENTER city grid)
    │   ├── cp2020_blackice.gd        # Black ICE enemy AI node (AStarGrid2D, tracing)
    │   ├── cp2020_npc_netrunner.gd   # NPC netrunner node (NetWatch + random runners; cyberdeck, programs, AI)
    │   ├── cp2020_board_renderer.gd  # CanvasItem custom grid renderer (Fog of War)
    │   ├── cp2020_canvas.gd          # UI container grid loader (legacy/placeholder)
    │   ├── cp2020_cyberdecks.gd      # Cyberdeck data Resource class
    │   ├── cp2020_datafort_designer.gd # @tool root coordinator for the datafort designer (panels, file I/O, signal wiring)
    │   ├── cp2020_datafort_grid_canvas.gd # @tool grid canvas child node (drawing, input, tile painting)
    │   ├── cp2020_game_session.gd    # Datafort session manager / orchestrator
    │   ├── cp2020_interaction_handler.gd # Contextual right-click PopupMenu handler
    │   ├── cp2020_netrunner.gd       # Player Netrunner entity controller
    │   ├── cp2020_programs.gd        # Software program Resource class
    │   ├── cp2020_net_file.gd        # NetFile Resource — discrete file on a MEMORY_UNIT tile (memory-tile loot)
    │   ├── cp2020_subnet_loader.gd   # ResourceLoader for datafort layout files
    │   ├── cp2020_turn_manager.gd    # Turn state controller
    │   └── cp2020_world_map_designer.gd # @tool world map authoring tool
    └── ui/
        ├── cyberdeck_workbench.gd    # Hub: Cyberdeck loadout + Buy/Sell shop UI script
        └── game_over.gd              # GameOver screen script (permadeath → New Life)
```

---

## 3. Core Architecture & Component Diagram

The game is structured as a **permadeath rogue-like**. The gameplay loop is built around a decoupled component architecture with **two autoload singleons**: `RunState` (per-life state, LOST on death) and `MetaState` (persistent vendor catalogue, SURVIVES death). The player flows through **three map levels** matching the CP2020 sourcebook: **Workbench (hub)** → **World Map** → **City Grid** → **Datafort (gameplay)**, with LDL links enabling travel between dataforts and back up the stack.

**Rogue-like meta-loop:** New life → hub (starting gear + 0 eb) → run (copy files from `MEMORY_UNIT` tiles + loot programs from `CONTROL_NODE` tiles, manage accumulated trace) → jack out (only if trace < `BUSTED_THRESHOLD`, else **busted** = permadeath) → return to hub, sell carried files + loot, **buy blueprint unlocks** (permanent `MetaState` catalogue) **+ buy-to-own upgrades** (per-life) from the catalogue → push deeper next run → **die** (flatline in a datafort OR busted on jack-out) → `GameOver` scene → **New Life** (fresh runner, but the `MetaState` catalogue of discovered/unlocked decks/programs persists across lives, saved to `user://`).

```mermaid
graph TD
    RunState["RunState (autoload: PER-LIFE — selected_deck, credits, accumulated_trace, loot, owned_decks, owned_programs)"]
    MetaState["MetaState (autoload: PERSISTENT — unlocked_decks, unlocked_programs, run_history; saved to user://)"]
    Workbench["CyberdeckWorkbench (hub: loadout + Buy/Sell shop)"]
    GameOver["GameOver (permadeath screen → New Life)"]
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
    CityGrid -->|Return to World Map (id 998): reset trace + clear city-grid context| WorldMap
    CityGrid -->|Jack Out to Hub (id 997): reset trace + clear run context| Workbench
    WorldMap -->|Jack Out to Hub (id 998): reset trace + clear run context| Workbench
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
    GameSession -->|copy_file: copy MEMORY_UNIT files → RunState.carried_files| RunState
    GameSession -->|jack_out (trace < BUSTED_THRESHOLD): reset trace + clear run context + change_scene| Workbench
    GameSession -->|jack_out (trace >= BUSTED_THRESHOLD): BUSTED permadeath → record_run + change_scene| GameOver
    GameSession -->|flatline: FLATLINED permadeath → record_run + change_scene| GameOver
    GameOver -->|New Life button: RunState.start_new_life() + change_scene| Workbench
    Workbench -->|Buy/Sell: MetaState catalogue ↔ RunState.credits/owned_*/loot; SELL FILES ↔ RunState.carried_files| MetaState
```

> **Permadeath routing:** both flatline and busted route to the `GameOver` scene, which records the run into `MetaState` and offers a "New Life" button. `New Life` calls `RunState.start_new_life()` (full wipe to starting gear) and reloads the workbench. The `MetaState` catalogue is untouched — discovered decks/programs remain purchasable in the next life.

### Scene Flow (3-Level Map Model)

1. **CyberdeckWorkbench (hub)** — pick an owned deck, load programs, and use the **Shop** (buy decks/programs from the `MetaState` catalogue, sell loot from `RunState.loot`), then `Jack In`.
2. **World Map** (`cp2020_world_net_map.tscn`) — geographic grid of regions + city markers. Move between cities; hack/pay LDL to build trace. Right-click a city → **ENTER City Grid** (loads that city's `CP2020CityGridLayout` via `hub.city_grid_path`).
3. **City Grid** (`cp2020_city_grid.tscn`) — per-city grid of datafort icons (security-tier coded). Runner enters at the LDL entry tile, moves 5/turn. **Stepping onto a datafort icon auto-dives** into its subnet (no Hack/Pay LDL here — that's world-map only). Right-click the runner's tile to **Return to World Map** (resets trace).
4. **Gameplay / Datafort** (`cp2020_gameplay.tscn`) — explore the datafort with fog of war, fight ICE, use programs, **copy files from `MEMORY_UNIT` tiles** (per-file copy-to-deck, MU cost) and **loot `CONTROL_NODE` tiles** (Download Files program loot). LDL-link tiles travel to other dataforts (preserve trace) or **Return to City Grid** (preserve trace — still in the run). Jack-out with trace < `BUSTED_THRESHOLD` returns to the World Map (reset trace, keep loot + carried files); jack-out at trace ≥ threshold = **Busted (permadeath)**. Flatline = **permadeath**. Both route to the `GameOver` scene → **New Life** restarts at the hub with starting gear (`MetaState` catalogue persists).

---

## 4. Data Models (Custom Resources)

All data objects inherit from `Resource` to allow direct serialization to `.tres` files and inspector editing.

### 4.1 `CP2020DatafortLayout` ([CP2020DatafortLayout.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/CP2020DatafortLayout.gd))
Represents a grid map layout for a Datafort.
- **Properties**:
  - `fort_name: String`
  - `rows: int` (default 15)
  - `columns: int` (default 15)
  - `cpu: int`, `int_rating: int` — DEPRECATED (per-CPU INT is now fixed at 3 per CP2020 PnP; total INT = 3 × active CPU count). Kept for .tres backward compat.
  - `datawall_strength: int`
  - `resident_programs: Array[NetProgram]` — layout-level programs the datafort's CPUs run against an intruding netrunner each turn (assigned in the designer; duplicated at spawn)
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
    - `target_entry_coord: Vector2i` — arrival coordinate in the remote subnet (`(-1,-1)` = unset; the remote map's primary/first ENTRY is used instead)
    - `is_primary_entry: bool` — marks this ENTRY as the map's primary arrival point (initial city-grid dive, and inbound LDL travel when `target_entry_coord` is unset). At most one ENTRY per map (enforced by the designer's "Primary entry" checkbox, which clears the flag on all other ENTRY tiles). Defaults `false` so existing `.tres` keep the first-ENTRY fallback.
  - **Per-tile ICE config** (BLACK_ICE tiles; authored in the datafort designer's ICE editor):
    - `ice_program: NetProgram` — **required** assigned `program.tres`. It supplies the ICE's `program_name` / `strength` / `effect_type` / `damage_dice` / `damage_dice_count` (the `effect_type` **drives in-game behavior**: `DAMAGE_RUNNER` = anti-personnel health attack; `DEREZ_ICE` = stationary anti-program sentry that scans for Worms in LoS and attacks them via an opposed roll). The program is `duplicate()`d at spawn so the cached `.tres` is never mutated. If no program is assigned, the ICE is skipped at spawn with a warning.
    - There are no per-tile scalar stat overrides and no tier templates — `max_integrity` is derived 1:1 from `program.strength` at spawn, movement is STR-based (`program.strength` spaces/turn), and tracing behavior is deferred to program-specific logic for Watchdog-type programs (no scalar `traces` flag).
  - **Per-tile NPC overrides** (NETWATCH / NETRUNNER tiles; authored in the datafort designer's NPC editor; zero/empty = use the hub security-tier template):
    - `npc_name: String`, `npc_strength: int`, `npc_max_ap: int`, `npc_max_integrity: int`, `npc_max_health: int`, `npc_max_mu: int`, `npc_deck_name: String`, `npc_disposition: int` (0 = Hostile, 1 = Neutral)
    - `npc_has_override: bool` — set true when any field is non-zero/non-empty; the runtime prefers tile stats over the tier template when this is set
    - `npc_programs: Array[NetProgram]` — optional hand-authored loadout (empty = template loadout)
  - **Files** (MEMORY_UNIT tiles; authored in the datafort designer's Files Editor). The memory-tile loot model is now discrete `NetFile` resources, NOT `loot_programs`/`loot_credits` (those fields are retained on `CONTROL_NODE` only — see below):
    - `files: Array[NetFile]` — the discrete files sitting on this tile; each has a `file_name`, lore `description`, fixed `credit_value` (fence price at the hub, in eb), and `mu_size` (deck MU consumed while carrying). See [4.11](#411-netfile-cp2020_net_filegd).
    - `copied_file_paths: PackedStringArray` — the indices (as strings) of files already copied this dive. Per-file one-shot: a file stays on the tile but can't be recopied. Reset (cleared) on every `load_subnet` (same cached-instance fog-reset rationale — a datafort revisited via LDL travel must be re-copyable), alongside `is_explored`/`is_visible`/`cpu_crashed_turns`/`is_looted`.
    - `is_looted: bool` — kept for save compat; no longer the memory-tile harvest flag (per-file `copied_file_paths` now drives the "already copied" state). The board renderer draws a "data copied" marker on a fully-harvested memory tile.
  - **Loot** (`CONTROL_NODE` tiles only; authored in the datafort designer's Loot Editor). `MEMORY_UNIT` no longer uses these:
    - `loot_programs: Array[NetProgram]` — programs downloadable from this tile (the "loot")
    - `loot_credits: int` — optional bonus credits bundled with the loot
    - `is_looted: bool` — true once the runner has Downloaded this tile; reset to `false` on every `load_subnet` (same fog-reset rationale — a revisited datafort's loot must be re-downloadable)
  - **Per-CPU fields** (CONTROL_NODE tiles):
    - `cpu_int: int` — DEPRECATED. Per CP2020 PnP rules each CPU contributes a flat 3 INT (`CP2020Datafort.INT_PER_CPU`). Kept for .tres backward compat; no longer used in logic.
    - `cpu_crashed_turns: int` — >0 means the CPU is crashed by a Krash anti-system program and contributes no INT / actions / MU until it reboots. Reset to 0 on every `load_subnet`.

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
  - `price: int` (default 0) — purchase price at the hub shop; read by the workbench Buy panel.
- **Methods**: `get_used_mu() -> int`

### 4.10 `NetProgram` ([cp2020_programs.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_programs.gd))
Represents an executable program software tool loaded into a cyberdeck.
- **ProgramType Enum**: `DECRYPTION`, `DETECTION`, `ANTI_PROGRAM`, `ANTI_PERSONNEL`, `ANTI_SYSTEM`, `UTILITY`, `ICE`
- **EffectType Enum**:
  - `BYPASS_GATE`: Cracks Code Gates (sets `is_unlocked = true`)
  - `BREACH_WALL`: Breaches Datawalls
  - `DEREZ_ICE`: Anti-program combat. As a **runner program**, it attacks hostile Black ICE via an opposed roll (Attacker STR + 1D10 vs Defender STR + 1D10, loser takes 1D6). As **enemy ICE** (Killer), it is a **stationary anti-program sentry** that scans for Worm-active tiles in LoS each turn and attacks the Worm via the same opposed roll — only the Killer can deal damage on a win (Worms are passive defenders). Killers do NOT pursue or attack the netrunner.
  - `DAMAGE_RUNNER`: Black ICE direct attacks
  - `REVEAL_NODES`: Scans hidden layout nodes
  - `MODIFY_MU`: Modifies deck speed or memory capacity
  - `SHIELD`: Defense program (raised on the runner's own tile)
  - `CRASH_CPU`: Anti-system program (Krash) — crashes a datafort CPU for 1D6+1 turns, dropping the datafort's INT and extra actions until it reboots. Also used by datafort resident programs to crash the **runner's cyberdeck** (see §5.3 deck crash).
  - `ARMOR`: Defense program (raised on the runner's own tile) — persistent point-for-point damage absorber. Absorbs `min(incoming_damage, armor.strength)` before the Shield opposed roll; NOT consumed on a hit.
  - `WORM`: Stealth opener — slips behind a DATAWALL or locked CODE_GATE and opens it from the inside over 2 turns. No alert (no trace increase, no ICE activation).
  - `DETECTION`: Detection/Alarm program (Watchdog). Dual-role: as **ICE** (a `BlackIce` with `effect_type = DETECTION`), it scans a 20-space LoS radius each turn and trips the datafort alarm on first sighting the runner (emits `alarm_triggered`); as a **netrunner-deployed program**, it drops a stationary beacon at the runner's position that watches for enemies entering its 20-space LoS each turn. STR 4, 610 eb, 5 MU.
  - `INVISIBILITY`: Stealth cloak (raised on the runner's own tile, consumes 1 action). While `netrunner.cloak` is set, each **dormant** adversary's first LoS detection is gated by an opposed roll each turn it has LoS while still dormant: Hider `1D10 + cloak.strength` vs Seeker `1D10 + seeker.strength` (ICE uses `program.strength`, NPC uses `npc.strength`). Tie or hider ≥ seeker → cloak holds (seeker ignores the runner this turn, stays dormant); seeker > hider → cloak pierced (that seeker activates and the cloak is broken globally). Only prevents *initial* notice — already-active adversaries (ICE already `_activated`, NPC already `_had_los`) bypass the cloak and attack normally. Does not affect `accumulated_trace` or block attacks once detected. Re-activating after a pierce costs another action. STR 3, 300 eb, 1 MU.
- **Properties**: `program_name`, `type`, `effect_type`, `memory_cost` (MU), `strength`, `price`, `icon` (Texture2D — workbench list rows only), `description` (one-line summary shown in the workbench detail card), `glyph` + `color` (on-map visual identity — see below), `glyph_offset` (optional `Vector2` nudge for glyphs that the auto-centring can't fix — see "Auto-centring" below; default `ZERO`), `damage_dice` (optional: `0` = use flat `strength` as damage on each Black ICE hit, the default for all existing programs; `>0` = roll `1D{damage_dice}` per hit instead, e.g. **Sword** sets `6` to roll 1D6 per hit), `damage_dice_count` (optional: number of dice to roll; default `1`; e.g. **Hellhound** sets `damage_dice=10, damage_dice_count=2` to roll 2D10). Backward-compatible: every existing `.tres` keeps flat-strength damage without re-saving.
- **Attack visuals** (`ATTACK_VISUALS` const + `get_attack_visual()`): the visual config (color / width / duration / style) for a program's attack effect lives **with the program logic**, so adding or customizing an attack program's beam is a one-file change. `ATTACK_VISUALS` maps `EffectType` → `{"color", "width", "duration", "style"}` (DEREZ_ICE → red beam, DAMAGE_RUNNER → orange-red beam, CRASH_CPU → orange beam). `get_attack_visual()` returns the entry for this program's `effect_type`, or a default red beam. The `CombatEffectAnimator` (§5.15) renders the effect; subclasses can override `get_attack_visual()` for unique visuals.
- **On-map visual identity** (`glyph` + `color` exports, `DEFAULT_VISUALS` const, `get_visual()`): each program carries its own on-map glyph + tint, stored in its `.tres`. `get_visual()` returns `{"glyph", "color"}` — a program's own `glyph` (non-empty) / `color` (alpha > 0) override the per-`EffectType` `DEFAULT_VISUALS`, so every program gets a distinct-by-effect-type look with zero `.tres` authoring; designers set `glyph`/`color` in a `.tres` for a custom icon. The rezzed-program node (`RezzedProgram.apply_visual_from_program`) and Black ICE node (`BlackIce.apply_visual_from_program`) set their label text + tint from this, and the board renderer's rezzed overlay tints its pulsing halo with the program color. The existing `icon: Texture2D` export is separate (workbench list rows only) — the in-map visual is glyph-based to match the procedural aesthetic.
- **Auto-centring** (`NetProgram.compute_glyph_centering()`): different Unicode glyphs render at different positions within their text box (baseline / em-square fill vary by block), so a single global label offset can't centre them all. `compute_glyph_centering(glyph, font, font_size, cell_size)` measures the glyph's actual bitmap via the TextServer API (`font_get_glyph_index` / `font_get_glyph_size` / `font_get_glyph_offset` / `font_get_glyph_advance` + `font.get_ascent()`/`get_descent()`) and returns the offset that centres the bitmap in the tile. `apply_visual_from_program()` uses this as the auto offset, falling back to the node's manual `label_visual_offset` when metrics are unavailable (glyph not in the font → zero-size). The per-program `glyph_offset` stacks on top for stubborn edge cases. Most glyphs therefore centre automatically with no `.tres` tuning.

### 4.11 `NetFile` ([cp2020_net_file.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_net_file.gd)) — *NEW*
Represents a discrete data file sitting on a `MEMORY_UNIT` tile (the memory-tile loot model). Files are copied onto the runner's deck during a dive, carried back to the hub, and fenced for credits. A `NetFile` is an authored resource — it may be a `.tres` on disk or inline-created/duplicated at runtime, so identity is **not** `resource_path`-based (see the `copied_file_paths` gotcha in 6.4).
- **Properties**:
  - `file_name: String` — label shown in the copy menu and the SELL FILES panel.
  - `description: String` — lore/flavour text.
  - `credit_value: int` — fixed authored fence price at the hub, in eb. Sold at full value (no fence factor — unlike `loot_programs`).
  - `mu_size: int` — deck memory consumed while the file is carried (counts toward `carried_files_mu`).
- **Helper**: `get_used_mu() -> int` (returns `mu_size`).
- **Lifecycle**: lives in `CP2020TileData.files` until copied; copied into `RunState.carried_files` (`duplicate()`d on copy so cached `.tres` files aren't mutated); lost on death (`reset`/`start_new_life` clear `carried_files`).

---

## 5. Core Systems & Implementation Details

### 5.1 Game Session Orchestrator ([cp2020_game_session.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_game_session.gd))
Controls gameplay flow, scene initialization, input routing, turn changes, terminal logs, and program interactions.
- **Constants & Grid Math**:
  - `cell_size = 40` px
  - `grid_offset_y = 90` px (Reserving top UI header space)
  - Coordinates match formula: `Vector2(coord.x * 40 + 20, 90 + coord.y * 40 + 20)`
- **`_ready`**: connects interaction/turn/netrunner signals, applies `RunState.selected_deck` to the netrunner (deck name, MU capacity, duplicate of installed programs), then calls `netrunner.seed_program_integrity()` to seed the `program_integrity` HP tracker for every loaded program (the direct array assignment bypasses `install_program`, which is the only other place that seeds integrity). Loads the subnet from `RunState.selected_subnet_path` (or `starting_subnet_path` fallback), and refreshes deck/health/trace HUD.
- **`load_subnet(path, entry_coord)`**: Loads a `CP2020DatafortLayout` via `ResourceLoader`, assigns it to the renderer, **resets `is_explored`/`is_visible` on every tile** (ResourceLoader returns a cached instance, so a previously-visited datafort would otherwise show as already-revealed after LDL travel), spawns the netrunner at `entry_coord`, spawns ICE + NPCs, and recalculates fog. A fresh run always starts fully fogged. Also clears `_watchdog_beacons` / `_watchdog_alerted` / `_deployed_programs` (deployed Watchdog beacons do not persist across dataforts) and calls `_clear_rezzed_programs()` (rezzed attack-program nodes do not persist across dataforts).
- **LDL Travel** (`_on_action_triggered`):
  - `"travel_ldl"` — the program arg is the `CP2020TileData` of the LDL link; loads its `target_subnet_path` at `target_entry_coord`. Aborts with a terminal message if no target is set. If a `target_entry_coord` was requested but no valid tile exists there, `netrunner.initialize` falls back to the remote map's primary/first ENTRY and the session logs a terminal warning (`"LDL target entry %s invalid — arrived at remote entry %s instead."`). Trace is preserved across the jump.
  - `"return_world_map"` — changes scene to the **City Grid** (`cp2020_city_grid.tscn`) via `RunState.selected_city_grid_path` (world-map fallback if no city grid recorded) and **preserves trace** (still in the run). Labelled "Returning to the City Grid via LDL."
- **Jack-out** (`_on_jack_out_pressed`): **first checks `BUSTED_THRESHOLD`** — if `RunState.accumulated_trace >= BUSTED_THRESHOLD`, the runner is **Busted** (NetWatch arrests): records the run summary into `RunState.last_run_summary`/`last_death_cause="busted"` and changes scene to `GameOver.tscn` (permadeath). Otherwise (trace < threshold) the existing successful jack-out path runs: clears `accumulated_trace` + `selected_city_grid_path` + `selected_security_tier` and changes scene to the World Map, **keeping `RunState.loot` and `RunState.carried_files`** for sale at the hub.
- **Flatline** (`_on_flatlined`): permadeath — records the run summary into `RunState.last_run_summary`/`last_death_cause="flatlined"` and changes scene to `GameOver.tscn` (no trace clear, no workbench return).
- **Copy file** (`_on_action_triggered "copy_file"`): a free action (no turn consumed) for an adjacent, visible `MEMORY_UNIT` tile. The interaction handler passes the tile index of the chosen `NetFile` (or "Copy All"). The file is `duplicate()`d, appended to `RunState.carried_files`, and its index is recorded in `tile.copied_file_paths` (one-shot). **Fails if not enough free deck MU** — free MU = `deck.max_mu − used_programs_mu − carried_files_mu` (see `CP2020Netrunner.get_used_memory` below). Files stay on the tile (not removed) and the tile is never "consumed" — only the per-file `copied_file_paths` flag advances.
- **Loot** (`_on_action_triggered "loot_tile"`): a free action (no turn consumed) for an adjacent, visible, un-looted `CONTROL_NODE` tile with program loot. Moves the tile's `loot_programs` into `RunState.loot` (each `duplicate()`d so cached `.tres` files aren't mutated), unlocks their resource paths in `MetaState`, adds `loot_credits` to `RunState.credits`, and marks `tile.is_looted = true`. (The old single `MEMORY_UNIT` loot path has been replaced by per-file copy — `loot_tile` is now `CONTROL_NODE`-only.)
- **NPC defeat unlock** (`_on_npc_destroyed`): unlocks the defeated NPC's template program paths in `MetaState.unlocked_programs` (reads `TIER_NPC_TEMPLATES` paths directly — see gotcha below). NPCs carry only a `deck_name` String (no Cyberdeck resource), so deck-unlock-via-defeat is not possible.
- **Camera Follow**: a `Camera2D` ("RunnerCamera") is parented under the board renderer; `_update_camera_limits` clamps it to the datafort rect and `_center_camera_on_runner` snaps it to the netrunner. `netrunner.position_changed` re-centres the camera.
- **Trace HUD**: `_update_trace()` writes `RunState.accumulated_trace` to the `TraceLabel`.
- **Line of Sight / Fog of War**:
  - The shared line-of-sight helper is `CP2020DatafortLayout.line_of_sight(from, to, max_range)` — a Euclidean distance check (`from.distance_to(Vector2(to)) <= max_range`) combined with the Bresenham raycast that blocks on `DATAWALL` tiles and locked `CODE_GATE` tiles (`is_unlocked == false`). The target tile itself is never a blocker.
  - `max_range` is **required** (no shared default): the runner and each program keep **separate** per-entity `@export var sight_range` values — `CP2020Netrunner` and `BlackIce` default to **20** (CP2020 PnP max sight range), `CP2020NpcNetrunner` and `CP2020Datafort` default to 10 — so future modifiers (deck/gear/program upgrades) can affect one side without touching the other.
  - Fog of war (`recalculate_fog_of_war`) uses `netrunner.sight_range` and the shared helper; sets `tile.is_visible = true` and `tile.is_explored = true`. `cp2020_game_session._has_line_of_sight` is now a thin wrapper over the helper (kept for existing references).
  - **Sight-gated adversaries**: Black ICE, hostile NPC netrunners, and the datafort's resident programs only act when they have line of sight to the netrunner within their own `sight_range`. Without LoS they go **dormant** (hold position, no activation/attack this turn). NEUTRAL NPCs keep wandering regardless of LoS; CPU reboot timers continue regardless of sight. Transition (seen↔lost) messages log only on the change. Last-known-position hunting is intentionally **not** implemented (future stealth/triggers pass).
- **Decryption Mechanics**:
  - Initiated when player selects a decryption program (`BYPASS_GATE`) via right-click contextual menu on a Code Gate.
  - Roll: `(randi() % 10) + 1 + program.strength` (Cyberpunk 2020 1d10 + Program STR rule).
  - Check: If `total_roll >= tile.strength_str`, `tile.is_unlocked = true`, immediately clearing the movement obstacle, changing tile color from orange to green, and recalculating Line of Sight. Otherwise, the attempt fails and logs the roll details to the terminal.
- **Worm Mechanics** (`execute_worm(program, target_coord)` / `_tick_worm_programs()`):
  - `execute_worm` is called from `_on_action_triggered` when a `WORM`-effect program is used on a `DATAWALL` or locked `CODE_GATE` tile. It validates the target tile type, sets `tile.worm_turns_remaining = 2` and `tile.worm_integrity = tile.worm_max_integrity = program.strength`, logs the action, and triggers a redraw. The tile is **not** opened immediately — the worm works over 2 turns. **No trace increase, no ICE activation** (stealth opener).
  - `_tick_worm_programs()` is called at the start of each netrunner turn (by `_on_turn_ended`). It iterates all grid tiles, decrements `worm_turns_remaining`, and when a tile reaches 0 it opens it: `DATAWALL` → converted to `EMPTY`, `CODE_GATE` → `is_unlocked = true`. It then resets `worm_integrity` / `worm_max_integrity` to 0, logs the opening, recalculates fog of war, and redraws the board.
  - **Worm integrity** (`worm_integrity` / `worm_max_integrity` on `CP2020TileData`): a deployed Worm has structural integrity equal to its `strength` (5 for the stock Worm). Enemy DEREZ_ICE (Killer) ICE that has LoS to the worm-active tile attacks it via an **opposed roll** (Killer STR + 1D10 vs Worm integrity + 1D10). **Only the Killer can deal damage on a win** — Worms are passive defenders that can only damage walls/gates, not ICE. If the Worm wins or ties, no damage to either side. If the Killer wins, the Worm takes 1D6 damage; at 0 integrity the Worm is destroyed (`worm_turns_remaining` reset to 0, tile stays closed — intrusion failed).
- **Watchdog Alarm & Beacons** (Detection/Alarm system — dual-role `DETECTION` effect):
  - **ICE-side alarm** (`_on_ice_alarm_triggered()`): connected to each `BlackIce.alarm_triggered` signal at spawn. When a DETECTION ICE (Watchdog) first sights the runner within its 20-space LoS, it emits `alarm_triggered`; the handler iterates all `ice_nodes` and calls `activate_alarm()` on every non-DETECTION ICE, waking dormant ICE to `PURSUE` (`_activated = true`, `current_state = PURSUE`). The Watchdog itself stays stationary — no pursuit, no attack, no trace. Initiative is handled naturally by the turn manager (the runner can kill it or retreat before it acts).
  - **Netrunner-side tripwire** (`execute_detection()` / `_tick_watchdog_beacons()`): the `DETECTION` case in `_on_action_triggered` calls `execute_detection(program)`, which spends 1 action to deploy a Watchdog beacon at the runner's current grid coord. Beacons are stored in `_watchdog_beacons: Array[Vector2i]`; `_watchdog_alerted: Dictionary` (keyed by coord) tracks whether a beacon has already logged its first detection. Each netrunner turn, `_tick_watchdog_beacons()` scans a 20-space LoS from every beacon for enemy ICE/NPCs and logs a `"WATCHDOG ALERT"` message the first time an enemy enters range (per beacon). Beacons are passive — they do not attack, move, or consume further actions.
  - **One File, One Instance**: deployed programs are appended to `_deployed_programs: Array[NetProgram]` on the game session. In `_input`, the available-programs list passed to the interaction handler is filtered to exclude any program in `_deployed_programs`, so a deployed Watchdog cannot be re-deployed. To run two beacons, load two copies of the Watchdog program at the workbench (each `.tres` is a separate program instance). Beacons + `_deployed_programs` + `_watchdog_alerted` are cleared in `load_subnet` (same cached-instance reset pattern as fog/worm/CPU crash).
- **Invisibility Cloak** (`INVISIBILITY` effect — stealth utility): `_execute_invisibility(program)` (returns `bool`) is called from the base `NetProgram.execute_runner_action` `INVISIBILITY` case via the `use_program` action, so it consumes 1 action on success. It sets `netrunner.cloak` (via `raise_cloak`, emitting `cloak_raised`) and pushes the cloak `NetProgram` onto `cloak_program` on every `ice_nodes` / `npc_nodes` entry (idempotently connecting each `cloak_pierced` signal to `_on_cloak_pierced`). Each dormant adversary then runs the opposed roll inside its own `take_turn` (BlackIce after LoS passes and before `program.take_ice_turn`, gated on `not _activated`; CP2020NpcNetrunner in the hostile LoS branch, gated on `not was_engaged`). On a hold the adversary stays dormant this turn (and re-rolls next LoS turn). On a pierce the adversary emits `cloak_pierced`; `_on_cloak_pierced()` calls `netrunner.pierce_cloak()` (emitting `cloak_pierced`), clears `cloak_program` on all adversaries, logs the breach, and redraws. `cloak_raised` / `cloak_pierced` are wired to `_update_trace` so the trace label appends ` | CLOAK` while cloaked. Already-active adversaries ignore the cloak (Invisibility only prevents *initial* notice). The cloak is transient per-run — not persisted across sessions (like `raised_shield` / `active_armor`) and dropped on scene change.
- **Rezzed Attack Programs** (Phase 1 — on-map program model): attack programs (`DEREZ_ICE` / `DAMAGE_RUNNER` / `CRASH_CPU`) no longer fire directly from the cyberdeck. The runner first **rezzes** an installed attack program onto the net as a `RezzedProgram` node ([cp2020_rezzed_program.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_rezzed_program.gd) / [cp2020_rezzed_program.tscn](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scenes/ui/cp2020_rezzed_program.tscn)), modeled on `BlackIce`. The node owns a `duplicate()` of the installed program (`source_program` refs the original for de-rez bookkeeping); `max_integrity` = `program.strength` (1:1, like ICE). Defense/utility programs (Shield, Armor, Invisibility, Watchdog, Worm, Bypass, Breach) keep their direct-from-deck behavior.
  - **Rez** (`_rez_program`, action `"rez_program"`, menu id `8000+i`): right-click the runner's own tile → "Rez \<program\>". Validates: effect type is rezzable (`REZZABLE_EFFECT_TYPES`), not already rezzed (`_is_program_rezzed` checks `source_program` identity), program integrity > 0 (crashed programs can't rez). Spawns at the runner's tile or nearest walkable adjacent tile (`_find_rez_spawn_tile` — avoids tiles occupied by other rezzed nodes / ICE / NPCs). Sets `home_floor = current_floor`. Wires `message_logged` / `moved_to` / `destroyed` signals. Consumes **1 action**.
  - **Attack via rezzed** (`_attack_with_rezzed`, action `"attack_with_rezzed"`, menu ids `8200+i` / `8300+i` / `8400+i`): right-click a target (Black ICE / NPC / CPU) → pick a rezzed program. Dispatches to the existing `_execute_ice_attack` / `execute_npc_attack` / `datafort.crash_cpu` helpers, sourcing stats from the rezzed node's program duplicate. Consumes **1 action**. If no matching rezzed program exists, the menu shows a disabled hint ("Rez an anti-ICE program first").
  - **De-rez** (`_derez_program`, action `"derez_program"`, menu id `8100+i`): right-click a rezzed node (or the runner's tile) → "De-rez \<program\>". Frees the node; the installed copy is available for re-rezzing. **Free** (no action cost).
  - **Auto-follow** (`_tick_rezzed_programs`): called at the start of each netrunner turn (in `_on_turn_ended`, alongside the watchdog tick). Each rezzed program on the runner's floor steps toward the runner via AStarGrid2D pathfinding until adjacent. Does NOT consume the runner's movement points. Programs on other floors hold position. If no path exists (surrounded), the program stays put — no turn block.
  - **Rendering**: `CP2020BoardRenderer` draws rezzed nodes as a pulsing cyan diamond "◆" glyph with the program's initial letter, floor-gated like ICE (only drawn on `current_floor`).
  - **Reset**: `_clear_rezzed_programs()` (called in `load_subnet`) frees all rezzed nodes — they don't persist across dataforts / LDL travel.
  - **Filtering**: in `_input`, installed attack programs that are already rezzed are filtered out of the `available_programs` list (via `_is_program_rezzed`), so the rez menu only shows un-rezzed copies. The `[REZZED]` prefix (cyan) is shown in `update_deck_info` for rezzed programs.
- **NPC Spawning** (`spawn_npcs`, parallel to `spawn_black_ice`): iterates NETWATCH/NETRUNNER tiles, applies per-tile `npc_*` overrides or falls back to `TIER_NPC_TEMPLATES[_current_security_tier][faction]` (NetWatch leans anti-personnel + shield; random netrunners lean utility + weak attack). Programs are `duplicate()`d at spawn. NPCs are added to `npc_nodes` and their signals connected (`message_logged`, `moved_to`, `attacked_netrunner`, `destroyed`).
- **Turn Execution**: `_all_adversaries()` merges `datafort` + `ice_nodes` + `npc_nodes` into one array passed to `turn_manager.execute_ice_turns` (datafort first so it acts first). The turn manager calls `take_turn(target, layout)` on any node that has the method, so NPCs and the datafort drop in without changing its signature.
- **Turn economy (movement + actions split)**: The turn manager gives the netrunner **1 action** (`max_actions = 1`) and **5 movement points** (`max_movement = 5`) per turn, per CP2020 PnP. Moving consumes a movement point (`consume_movement`); running a program or performing a net action consumes the action. The turn ends only when **both** the action and all movement points are exhausted (or the player explicitly ends the turn). The HUD shows `"Actions: 1/1 | Move: 5/5"`. The `movement_changed` signal keeps the HUD's move counter in sync.
- **Initiative**: `execute_ice_turns` accepts `netrunner_int` and `system_int` params. After adversaries finish, if `system_int > 0`, the turn manager rolls 1D10 + netrunner INT vs 1D10 + system INT and emits `initiative_rolled(nr_roll, sys_roll, netrunner_first, is_tie)`. The netrunner's INT is `netrunner.reflex + RunState.selected_deck.speed_bonus` (CP2020: `1D10 + REF + Cyberdeck Speed`); the system's is `datafort.total_int()` (CPUs × 3). If the system wins, adversaries act again (system goes first in the new round) before `start_netrunner_turn()`. **Ties are simultaneous** (`is_tie = true`): no extra adversary phase is run — both sides act in the same round. No datafort / all CPUs crashed (system INT = 0) → initiative skipped, player goes first. If the system wins initiative in consecutive rounds, it acts at end of round N and start of round N+1 — two adversary phases back to back. NPC netrunners do NOT roll initiative separately — they act during the adversary phase.
- **NPC Combat**: `execute_npc_attack(program, coord)` resolves an opposed 1D10+STR roll vs the NPC's strength (same convention as `execute_ice_attack`); `take_damage` handles destruction + the provoked transition. Called via `_attack_with_rezzed` when a rezzed `DAMAGE_RUNNER` / `DEREZ_ICE` program strikes an NPC (Phase 1 — the program must be rezzed first). `_talk_to_npc(coord)` logs flavour text for neutral runners (placeholder for future dialogue/trading).
- **Datafort Adversary** (`spawn_datafort`, after `spawn_npcs`): spawns a [CP2020Datafort](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_datafort.gd) node that treats the datafort itself as an adversary. It owns the CPU list (built from `CONTROL_NODE` tiles), computes total INT (`3 × active CPUs`), actions-per-turn (`1 × active CPUs`), and MU capacity (`10 × active CPUs`) per CP2020 PnP rules. It takes a turn each round running `resident_programs` (anti-runner `DAMAGE_RUNNER` programs) against the netrunner, and decrements crashed-CPU reboot timers. Signals: `message_logged`, `attacked_netrunner` (→ `_on_ice_attacked`), `attacked_runner_deck` (→ `_on_runner_deck_attacked`, for `CRASH_CPU` resident programs that crash the runner's cyberdeck), `cpu_crashed`, `cpu_rebooted`, `state_changed` (→ `update_datafort_info`). The datafort is **prepended** to `_all_adversaries()` so it acts before ICE/NPC, but it does **not** command them — ICE and NPCs stay independent.
- **Krash / CPU Crash**: the `crash_cpu` action (right-click a visible `CONTROL_NODE` tile → pick a **rezzed** `CRASH_CPU` program, ids `8400+i`) calls `datafort.crash_cpu(program, coord)`: opposed 1d10+program.STR vs 1d10+**system INT** (`total_int()`, which drops as CPUs are crashed); on a hit the CPU is crashed for `1D6+1` turns (`tile.cpu_crashed_turns`), dropping the datafort's INT, actions, and MU until it reboots. `load_subnet` resets all `cpu_crashed_turns` to 0 (alongside the fog reset). The program must be rezzed onto the net first (Phase 1 — see Rezzed Attack Programs above).
- **Initiative log**: `_on_initiative_rolled(netrunner_roll, system_roll, netrunner_first, is_tie)` logs who acts first (or "simultaneous" on a tie) to the terminal.
- **HUD**: `update_datafort_info()` refreshes the `DatafortLabel` (datafort name, active/total CPUs, total INT, actions/turn, MU used/total) on spawn, crash, reboot, and turn boundaries.

### 5.2 Board Renderer ([cp2020_board_renderer.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_board_renderer.gd))
Performs procedural drawing via `CanvasItem.draw_*` calls using a **neon cyberpunk grid style** (matching the city grid's visual language). All visual colors are `@export`-ed in two inspector groups (Grid + Grid Effects) for easy theming. The `draw_grid()` pipeline renders in this order: base background → neon grid lines → fog-of-war overlays → tile graphics → scanlines → vignette → tech frame. A `_pulse_time` var accumulates in `_process()` and drives a continuous pulse animation (always redraws).

**Fog-of-war (3 states):**
1. **Unexplored (`is_explored == false`)**: Opaque black fill (`color_unexplored_fill`), grid lines hidden.
2. **Explored / Fog of War (`is_explored == true`, `is_visible == false`)**: Semi-transparent dark overlay (`color_fog_overlay`, alpha ~0.88 — darker so explored tiles read distinctly from visible), grid lines dimly visible, dimmed tile graphics.
3. **Visible (`is_visible == true`)**: Subtle tint (`color_visible_overlay`), vivid neon grid lines (`color_grid_line` / `color_grid_line_bright`), full opacity tile graphics:
   - `ENTRY`: Green/Cyan outlined box with directional polygon glyph
   - `DATAWALL`: Solid red barrier box
   - `CODE_GATE`: Orange barrier (locked) or Green barrier (unlocked) with dividing horizontal beam
   - **Worm-in-progress indicator**: DATAWALL and CODE_GATE tiles with `worm_turns_remaining > 0` render a pulsing purple circle with a "W" glyph (three diagonal strokes), signalling an active stealth open. (Worms are stealth code breakers — invisible to ICE, so this overlay is the only visual indication of a Worm at work. The overlay colour shifts purple→orange→red as `worm_integrity` decreases, and a "cur/max" integrity readout is drawn below the W glyph when the Worm has taken damage.)
   - **Watchdog beacon overlay**: tiles in the renderer's `watchdog_beacons: Array[Vector2i]` array (synced from the game session) render a pulsing amber circle with a "W" glyph — visually distinct from the Worm's purple "W" (different colour + stroke style). Drawn in `draw_grid()` over the beacon tiles so deployed tripwires are visible at a glance.
   - **Rezzed attack-program overlay**: nodes in the renderer's `rezzed_program_nodes` array (synced from the game session) render a pulsing cyan diamond "◆" glyph with the program's initial letter, drawn on top of tiles + beacons. Floor-gated — only nodes with `home_floor == current_floor` are drawn. Visually distinct from enemy ICE (which uses the skull "☠").
   - `MEMORY_UNIT`: renders its tile graphics plus a **"data copied" marker** when the tile is fully harvested (all `files` copied this dive — every index present in `copied_file_paths`).

### 5.3 Player Netrunner Controller ([cp2020_netrunner.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_netrunner.gd))
- Handles keyboard movement (`WASD` or Arrow keys via `ui_up`, `ui_down`, `ui_left`, `ui_right`).
- Checks boundaries against layout bounds (`0..columns-1`, `0..rows-1`).
- Validates movement obstacles: blocks movement into `DATAWALL` tiles or locked `CODE_GATE` tiles. Empty cells (no tile) are walkable.
- `initialize(layout, entry_coord)`: spawns at `entry_coord` if supplied, in-bounds, and a tile exists there (used by mid-run LDL travel); otherwise picks an arrival point with a deterministic ordering so the initial city-grid dive never lands on an outbound LDL link: (1) the map's primary entry (`is_primary_entry`), then (2) any plain (non-LDL) `ENTRY` tile, then (3) any `ENTRY` tile at all. Logs a warning if no ENTRY tile exists.
- **`get_used_memory() -> int`**: returns used program MU **plus `RunState.get_carried_files_mu()`** (the MU consumed by copied `NetFile`s in the runner's possession). Free MU for copying a new file = `deck.max_mu − get_used_memory()`. The copy interaction handler rejects a file whose `mu_size` would exceed this free MU.
- **`interface_rank: int`** (default 6) — kept for backward compat; no longer the initiative stat. Initiative now uses `reflex` + `deck.speed_bonus` (see §5.1 Initiative).
- **`@export var reflex: int = 8`** — the netrunner's Reflexes stat, used for initiative (`1D10 + REF + Cyberdeck Speed`).
- **`@export var intelligence: int = 8`** / **`@export var body: int = 8`** — INT and BODY meat-space stats. Anti-personnel hits reduce INT (`intelligence_lost` tracks cumulative loss; `int_changed` signal). BODY is the Mortal/Stun save bonus.
- **Armor & Shield defense (CP2020 RAW)**: `active_armor` and `raised_shield` are both one-shot protection programs that use the **same opposed-roll mechanic**: attacker rolls `1D10 + attack_strength`, defender rolls `1D10 + protection.strength`. **Ties → defender** (safe). If Shield is loaded, it resolves first; if Shield is breached and Armor is loaded, Armor gets a second opposed roll. Both are consumed on use (one-shot). If no protection program is loaded & active → **auto-hit** (no defense roll, full payload applies). Physical body armor provides zero protection (Armor here is a program, not meat-space armor).
- **Anti-personnel damage resolution (CP2020 RAW)**: `apply_damage(attack_strength, attacker_name, is_anti_personnel, prog)` follows a 4-step model:
  - **Step 1 — Interface Defense Roll**: opposed roll (above). The payload is rolled only if the attack hits.
  - **Step 2 — Payload**: `prog._roll_damage()` (per-program dice: Hellhound 2D10, Sword 1D6, Flatline flat STR). NPC/datafort direct attacks (prog=null) use flat `attack_strength`.
  - **Step 3 — Death Save**: if HP ≤ 0, roll `1D10 + BODY` vs 15. Success → survive at 1 HP; failure → flatline.
  - **Step 3b — Anti-personnel after-effects**: INT loss (1/hit, `int_changed` signal) + Stun save.
  - **Step 4 — Stun save**: roll `1D10` **under** `BODY − wound penalty` (Light 0, Serious −2, Critical −4, Mortal −6, derived from cumulative damage). Failure → `is_stunned = true` (Death Trap).
- **Stunned Runner Death Trap**: a stunned runner cannot act, move, or jack out. Both action and movement pools are zeroed at turn start. All attacks auto-hit (no defense roll). The stun persists until flatline or rescue by a meat-space ally (future feature). The `stunned` signal (no params) is emitted on stun.
- **Deck crash**: `crash_deck(duration, attacker)` sets `deck_crashed_turns`; the game session ticks it at turn start and forces `actions_remaining = 0` while crashed (movement preserved so the runner can flee). Emitted via the datafort's `attacked_runner_deck` signal for `CRASH_CPU` resident programs.
- Emits `position_changed`, `message_logged`, `deck_updated`, `shield_raised`, `shield_consumed`, `armor_raised`, `armor_consumed`, `health_changed`, `int_changed`, `stunned`, `deck_crashed`, and `flatlined` (when `current_health <= 0`).
- **Program-HP model** (`program_integrity: Dictionary`): a program's `strength` is also its max health (integrity). Installed programs are seeded to `prog.strength` on `install_program` and erased on `uninstall_program` / `clear_crashed_program`. `seed_program_integrity()` clears and re-seeds the dictionary from `installed_programs` — called by the game session after the direct `installed_programs` assignment at run start (bypassing `install_program`). `damage_program(amount, attacker)` picks a random installed program with integrity > 0 and reduces it; `damage_specific_program(prog, amount, attacker)` targets a specific program (used by the runner's anti-IC opposed roll when the runner loses). At 0 integrity the program is **DEREZZED** — it **crashes and clogs MU**: it stays in `installed_programs` (still counts toward `get_used_memory()`) but can't be used (integrity 0). The runner must call `clear_crashed_program(prog)` to free the MU. `has_crashed_programs()` returns true if any installed program is crashed. The `use_program` action in the game session blocks crashed programs (integrity ≤ 0) before consuming an action. The raised shield does **not** block anti-program attacks (shields protect the runner's persona/health, not programs). If the runner has no installed programs, a `DEREZ_ICE` attack logs "no programs to target" and does nothing (no fallback to health damage). The `update_deck_info()` HUD renders three visual states per program: `[ACTIVE]` (green, raised shield), `[CRASHED]` (red, de-rezzed/clogging MU), and damaged (shows `STR cur/max` when integrity < strength but > 0).
- Emits `position_changed`, `message_logged`, `deck_updated`, `shield_raised`, `shield_consumed`, `health_changed`, and `flatlined` (when `current_health <= 0`).

### 5.4 Hostile Black ICE AI ([cp2020_blackice.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_blackice.gd))
- **Pathfinding**: Instantiates an `AStarGrid2D` instance over the layout matrix region.
- Dynamic obstacle update ([_update_obstacles](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_blackice.gd#L99)): dynamic solid points applied to `DATAWALL` tiles and locked `CODE_GATE` tiles.
- **States**: `IDLE` -> `PURSUE`. Activates upon turn execution, taking up to `program.strength` steps per turn toward the Netrunner's position (CP2020: ICE moves at STR speed — so a STR-6 Flatline moves 6 spaces/turn while a STR-2 Watchdog would move 2; Watchdog overrides `take_ice_turn` and never moves). On reaching the runner, branches on `effect_type`: `DAMAGE_RUNNER` emits `attacked_netrunner(strength)` — the program's STR (not rolled damage), so the interface defense roll in `apply_damage` happens first, and the payload is rolled only if the attack hits. The attack is a single action delivered when the ICE reaches the runner's tile and does not consume movement.
- **DEREZ_ICE (Killer) — stationary anti-program sentry**: a `BlackIce` with `effect_type = DEREZ_ICE` does **NOT** pursue or attack the netrunner. `BlackIce.take_turn` early-returns for DEREZ_ICE, skipping the runner LoS check, `_had_los` tracking, and Invisibility cloak gate. `NetProgram.take_ice_turn` branches to `_take_killer_turn(ice, layout)`: it scans `ice.rezzed_programs` (a live reference to the game session's `rezzed_program_nodes` array, set at spawn time — same pattern as `cloak_program`) for a rezzed attack program on the same floor (`rez.home_floor == ice.home_floor`), alive (`current_integrity > 0`), and within LoS (`ice.has_los_to(rez.current_position, layout)` within `sight_range`). If a rezzed program is in LoS, it emits `attacked_program(attacker_str, tile_coord)` (one attack per turn, first target in LoS wins). If no target is in LoS, the Killer holds position silently. The game session's `_on_ice_attacked_program(attacker_str, tile_coord, ice)` resolves the **opposed roll** (Killer STR + 1D10 vs rezzed program `current_integrity` + 1D10): Killer wins → rezzed program takes 1D6 damage via `take_damage()` (de-rezzed at 0 integrity — the `destroyed` signal + `_on_rezzed_program_destroyed` handler erases it from `rezzed_program_nodes`); rezzed program wins or tie → no damage (passive defender during adversary phase — fights back via player command on the runner's turn). **Worms are stealth code breakers** — invisible to ICE and never targeted by Killers. The Worm tile fields (`worm_turns_remaining` / `worm_integrity` / `worm_max_integrity`) are preserved on `CP2020TileData` for the autonomous Worm tick (`_tick_worm_programs`) but no adversary attacks them.
- **DETECTION ICE (Watchdog alarm)**: a `BlackIce` with `effect_type = DETECTION` (value `10`) is a stationary alarm tripwire — it **does not pursue, attack, or trace**. In `take_turn`, the DETECTION case scans a 20-space LoS radius (`sight_range`) for the netrunner; on the first sighting it emits `alarm_triggered` (once per ICE) and logs the alert. The game session's `_on_ice_alarm_triggered()` then calls `activate_alarm()` on every other non-DETECTION ICE node, waking dormant ICE (`_activated = true`, `current_state = PURSUE`). Initiative is handled naturally by the turn manager — the runner can kill the Watchdog or retreat before it acts. See §5.1 for the alarm handler + netrunner-side beacon system.
- **`activate_alarm()`**: new method that wakes a dormant ICE node — sets `_activated = true` and `current_state = PURSUE`. Called by the game session on all non-DETECTION ICE when a DETECTION ICE trips the alarm. Has no effect on an already-active node.
- **New signal**: `alarm_triggered` — emitted by a DETECTION ICE on its first sighting of the netrunner. Connected to `game_session._on_ice_alarm_triggered()`.
- **Tracing ICE**: tracing behavior (formerly a per-tile `traces` scalar that rolled `1D10 + strength` vs `RunState.accumulated_trace` on first activation) has been **removed as a scalar** and is deferred to program-specific logic for Watchdog-type programs. No ICE traces in the current build; the activation-trace block was removed from `NetProgram.take_ice_turn`.
- **Fog of War Visibility**: Dynamically updates the `skull_label` icon visibility based on the tile fog state.
- **Stat sourcing** (see `cp2020_game_session.spawn_black_ice`): ICE stats are set on the node **before** `initialize()` (which copies `max_integrity` into `current_integrity`). There are no tier templates — every BLACK_ICE tile **must** have an assigned `ice_program` (.tres). If `tile.ice_program` is null, the ICE is skipped at spawn with a warning. The program (duplicate'd) supplies `program_name` / `strength` / `effect_type` / `damage_dice` / `damage_dice_count`. `max_integrity` is always derived 1:1 from `program.strength` (so a stronger program is also tougher to DEREZ). Movement is STR-based (`program.strength` spaces/turn). The old `ice_*` scalar fields, the `ice_has_override` override path, and `TIER_ICE_TEMPLATES` / `_build_template_program` have all been removed.

### 5.4b NPC Netrunner AI ([cp2020_npc_netrunner.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_npc_netrunner.gd)) — *NEW*
- Full netrunner-entity NPCs (cyberdeck, programs, health, MU) — not contact-attack pathfinders like Black ICE. One node class serves two factions via a `Faction` enum (`NETWATCH`, `NETRUNNER`) and a `Disposition` enum (`HOSTILE`, `NEUTRAL`).
- **NetWatch** (`Faction.NETWATCH`): spawns `Disposition.HOSTILE` — pursues and attacks the player on sight.
- **Random Netrunner** (`Faction.NETRUNNER`): spawns `Disposition.NEUTRAL` — wanders randomly (~50% idle, otherwise steps to a walkable neighbour) until provoked. `take_damage` flips NEUTRAL→HOSTILE for the rest of the run.
- **AI**: HOSTILE NPCs reuse the Black ICE `AStarGrid2D` pursuit pattern (up to `max_ap` steps per turn; attack on reaching the player's tile). `_attack_player()` prefers a `SHIELD` program when hurt, else an anti-personnel (`DAMAGE_RUNNER`) program, falling back to base `strength`. NEUTRAL NPCs wander and do not path toward the player.
- **Signals**: `message_logged`, `moved_to`, `attacked_netrunner(strength)`, `destroyed`, `took_damage`. The session connects `attacked_netrunner` → `_on_ice_attacked` (shared handler) and `destroyed` → `_on_npc_destroyed` (erases from `npc_nodes`).
- **Stat sourcing** (see `cp2020_game_session.spawn_npcs`): NPC stats are set **before** `initialize()`. Per-tile override fields (`npc_*` on `CP2020TileData`) take precedence; otherwise the hub's `security_tier` selects a default template from `TIER_NPC_TEMPLATES` (per faction, per tier). Program resources from templates are `duplicate()`d at spawn to avoid mutating cached `.tres` files.
- **Fog of War**: `update_visibility(explored, visible)` toggles the glyph label like Black ICE. The session's `recalculate_fog_of_war` syncs NPC visibility each move.

### 5.4c Datafort CPU Adversary ([cp2020_datafort.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_datafort.gd)) — *NEW*

The datafort itself is an adversary, not just a passive map. Its CPUs determine its INT, actions per turn, MU capacity, and program-running ability — modelled on the Cyberpunk 2020 pen-and-paper netrunning rules. Per CP2020 PnP, each CPU is identical: **3 INT**, **1 action/turn**, **10 MU**.

- **class_name CP2020Datafort extends Node** — one node per subnet, spawned by `spawn_datafort` after `spawn_npcs`. Inner `Cpu` class holds `coord` and `tile` (CP2020TileData). CPUs are built from all `CONTROL_NODE` tiles in the layout. Constants: `INT_PER_CPU = 3`, `ACTIONS_PER_CPU = 1`, `MU_PER_CPU = 10`.
- **Total INT** = `INT_PER_CPU × active_cpu_count()` (3 per active CPU). **Actions per turn** = `ACTIONS_PER_CPU × active_cpu_count()` (1 per active CPU). **Total MU** = `MU_PER_CPU × active_cpu_count()` (10 per active CPU). A crashed CPU contributes zero to all three until it reboots. System INT also feeds the **initiative roll** — see §5.1 Turn Execution.
- **MU capacity**: `total_mu()` = 10 × active CPUs. `used_mu()` = sum of `memory_cost` across all `resident_programs`. `available_mu()` = `total_mu() - used_mu()`. The designer enforces this — adding a program that would overflow available MU is rejected with a warning.
- **Krash / CPU crash** (`crash_cpu(program, coord)`): opposed `1d10 + program.strength` vs `1d10 + total_int()` (current **system INT**, which drops as CPUs are crashed); on a hit the CPU is crashed for `1D6+1` turns (`tile.cpu_crashed_turns = randi_range(1,6)+1`), emitting `cpu_crashed(coord)` + `state_changed`. A crashed CPU contributes no INT, actions, or MU until it reboots.
- **take_turn(layout)** — called by the turn manager: decrements every `cpu_crashed_turns > 0`; at 0 the CPU reboots (emit `cpu_rebooted(coord)`). Then runs `resident_programs` (anti-runner `DAMAGE_RUNNER` programs `duplicate()`d from the layout) up to `actions_per_turn` against the runner: emits `attacked_netrunner(strength)`. Emits `state_changed` at the end.
- **Independence**: the datafort does **not** command the Black ICE or NPC netrunners — they stay independent turn-manager adversaries with their own `take_turn`. The datafort is simply one more entry in `_all_adversaries()` (prepended so it acts first) running its own resident programs. Any program the datafort spawns follows its own programming (same principle as ICE).
- **Signals**: `message_logged`, `attacked_netrunner(strength)`, `cpu_crashed(coord)`, `cpu_rebooted(coord)`, `state_changed`. The session connects `attacked_netrunner` → `_on_ice_attacked` (shared handler) and `state_changed` → `update_datafort_info`.

### 5.5 Contextual Right-Click Input Handler ([cp2020_interaction_handler.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_interaction_handler.gd))
- Captures right-click mouse events over grid cells.
- Converts mouse pixel coordinates to grid cell coordinates `Vector2i(grid_x, grid_y)`.
- Checks if tile `is_explored` (menus are blocked on unexplored tiles). **Must use `layout.get_tile(coord)`** — `.tres` files store dictionary keys as `"x,y"` strings, so a direct `grid_tiles.get(Vector2i)` always returns null.
- **Menu branches** (first match wins):
  - **LDL-link tiles** (`is_ldl_link`): always add "Travel to \<datafort\>" (id `3000`) + "Return to City Grid" (id `3001`), even with no matching program. Travel uses `_ldl_tile` (the stored tile data); empty target → the session aborts the travel with "no target subnet set", so an empty-target LDL link effectively offers city-grid-return only.
  - **Rezzed program node on this tile**: offer "De-rez \<program\>" (id `8100+i` over `_current_rezzed_nodes`). Checked before ice/npc branches so a rezzed program on an entity tile still gets its own menu.
  - **Visible Black ICE on the tile**: offer **rezzed** `DEREZ_ICE` programs (ids `8200+i` over `_current_rezzed_nodes`). Attack programs must be rezzed before they can strike — installed programs are no longer offered directly. If none rezzed, show a disabled hint ("Rez an anti-ICE program first").
  - **Visible NPC netrunner on the tile**: offer **rezzed** `DAMAGE_RUNNER` / `DEREZ_ICE` programs (ids `8300+i`), plus a "Talk" item (id `4000`) for neutral runners. If none rezzed, show a disabled hint.
  - **Visible CPU tile** (`CONTROL_NODE`): offer **rezzed** `CRASH_CPU` programs (ids `8400+i`). If none rezzed, show a disabled hint ("Rez an anti-system program first").
  - **Visible, adjacent `MEMORY_UNIT` with files**: offer one menu item per file labelled `"<file_name> (<mu> MU)"` (NO credit value shown — value is discovered at the hub), plus a "Copy All" item. Already-copied files (index present in `tile.copied_file_paths`) show a `"✓ "` prefix and are disabled. Per-file items use ids `6000+i`; "Copy All" uses id `6999`. Free action, no turn consumed. Copy is rejected (item disabled / on-screen message) if the file's `mu_size` exceeds the runner's free deck MU. (The old single `6000` `MEMORY_UNIT` `loot_tile` id is removed — `6000` is now the first file id, `6000+0`.)
  - **Visible, adjacent, un-looted `CONTROL_NODE` with loot**: offer "Download Files" (the `loot_tile` action, now `CONTROL_NODE`-only — program loot moved off `MEMORY_UNIT`). Free action, no turn consumed. Its menu id is kept **disjoint from the `6000–6999` file range** to avoid collision.
  - **Runner's own tile** (visible): offer `SHIELD` defense programs (ids `1000+i`), `ARMOR` defense programs (ids `7000+i`), `DETECTION` programs (ids `1000+i`) labelled `"Watchdog (Deploy STR X, X MU)"`, `INVISIBILITY` programs (ids `1000+i`) labelled `"<name> (Cloak STR X, X MU)"`, **Rez** entries for attack programs (`DEREZ_ICE` / `DAMAGE_RUNNER` / `CRASH_CPU`, ids `8000+i`), and **De-rez** entries for currently rezzed programs (ids `8100+i`). Armor is a persistent passive absorber; raising it does not consume a turn action. A `DETECTION` program consumes 1 action to deploy a Watchdog beacon at the runner's current position (see §5.1 Watchdog Beacons). An `INVISIBILITY` program consumes 1 action to raise the stealth cloak (see §5.x Invisibility Cloak); a no-op while already cloaked returns false so no action is spent. Rez consumes 1 action (spawns a `RezzedProgram` node); de-rez is free. A program already deployed or rezzed this run is filtered out of the offered list (one file, one instance — load a second copy at the workbench to run two).
  - **Locked Code Gate**: offer `BYPASS_GATE` programs and `WORM`-effect programs (stealth opener, 2-turn open, no alert). Menu label: `"Worm (Stealth, 2 turns, X MU)"`.
  - **Datawall**: offer `BREACH_WALL` programs and `WORM`-effect programs (stealth opener, 2-turn open, no alert). Menu label: `"Worm (Stealth, 2 turns, X MU)"`.
- `_on_menu_action_selected` checks ids in this order to avoid collision: LDL travel (`3000`/`3001`) → vertical travel (`3002`/`3003`) → NPC talk (`4000`) → **memory files (`6000+i` per file / `6999` Copy All)** → **Armor-raise (`7000+i`)** → **rez program (`8000+i`)** → **de-rez (`8100+i`)** → **rezzed anti-ICE attack (`8200+i`)** → **rezzed NPC attack (`8300+i`)** → **rezzed CPU crash (`8400+i`)** → `CONTROL_NODE` loot (`loot_tile`) → program use (`1000+i`). **Do not reorder — the `6000–6999` file range, the `7000+i` Armor range, the `8000–8499` rezzed-program ranges, and the `loot_tile` id must all be checked before the `1000+i` program range.** The old direct NPC-attack (`2000+i`) and CPU-crash (`5000+i`) ranges have been removed — attack programs must be rezzed first (Phase 1).
- Dynamically creates and opens a `PopupMenu` near mouse location (`popup_on_parent`).

### 5.6 Datafort Designer Tool ([cp2020_datafort_designer.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_datafort_designer.gd) + [cp2020_datafort_grid_canvas.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_datafort_grid_canvas.gd))
- Runs in editor (`@tool` annotation). The designer is split into a **root coordinator** (`cp2020_datafort_designer.gd`, `extends Control`) and a **grid canvas child node** (`cp2020_datafort_grid_canvas.gd`, `extends Control`, `class_name CP2020DatafortGridCanvas`). All UI elements — toolbar buttons, side panels, file dialogs, the grid canvas, and the programs toggle button — are authored in the scene tree (`CP2020DesignerCanvas.tscn`) so the layout can be rearranged visually in the Godot editor. The root coordinator uses `@onready` references to scene-tree nodes and connects their signals in `_ready()`. The grid canvas owns `_draw` / `_gui_input` / `paint_tile` and emits 5 signals (`tile_selected`, `tile_painted`, `ldl_link_selected`, `ldl_link_painted`, `tile_moved`) that the root connects to for opening/closing side panels.
- Visual editor interface for painting tiles. The toolbar has a **Select** tool (click an existing tile to open its editor without overwriting it; the selected tile gets a yellow outline highlight), plus distinct **Entry** (plain datafort arrival point, `is_ldl_link=false`) and **LDL Link** (travel node, `is_ldl_link=true` with no hardcoded target) buttons, and Datawall, Code Gate, Memory Unit, Control Node, Black ICE, **NetWatch**, **Netrunner**, and Eraser. Picking any paint tool exits Select mode.
- **Drag-to-move** (Select mode only): left-press a non-empty tile, drag, release over an empty cell to move it (preserves all configured fields — ICE stats, NPC params, files, LDL target, etc.). Drops onto occupied non-empty cells are **rejected** (tile stays at source); out-of-bounds or same-cell release cancels and opens the editor at source (so a plain click still works). On a successful move the source cell is filled with a fresh `EMPTY` tile so the grid stays walkable floor. A drag ghost (semi-transparent rounded rect) follows the cursor and the source cell dims while dragging. The layout helpers `set_tile(coord, tile)` and `erase_tile(coord)` on `CP2020DatafortLayout` centralise the Vector2i-vs-`"x,y"`-string key duality (serialised `.tres` files can store string keys; runtime uses Vector2i). `paint_tile` also routes through `set_tile` to avoid duplicate keys.
- **LDL-Link Editor panel** (scene-tree `PanelContainer` anchored to the right edge): target subnet `LineEdit` + Browse `FileDialog` (scoped to `scenes/forts/*.tres`), target entry coord X/Y `SpinBox`es, a "Clear target" button, and a shared "Primary entry" checkbox (an LDL link can also be the map's primary arrival; toggling it on clears the flag on every other ENTRY tile so at most one ENTRY per map is primary). In LDL mode, clicking an existing LDL link selects it for editing (does not overwrite); clicking empty space paints a new link and opens the editor. Field edits write back to the tile live and persist on save. Empty target = world-map-return-only. LDL links draw with a distinct blue frame + "L" glyph.
- **Entry Node Editor panel** (scene-tree `PanelContainer`; shown when a plain non-LDL ENTRY tile is painted/selected): shows the tile's grid coord and the shared "Primary entry" checkbox. Painting the first plain Entry on a map auto-sets it as primary (only if no other ENTRY is primary yet) so a freshly-authored map gets a deterministic arrival point without manual setup; the designer can move the flag via the checkbox. Primary-entry tiles draw a small white inset square marker (both in the designer and in-game via the board renderer).
- **Coordinate display** (grid canvas, `@tool`): column (x) tick labels along the top edge of the grid, row (y) tick labels along the left edge, and a floating `"(x, y)"` tooltip that follows the cursor — redrawn on every mouse motion — so the designer can read a tile's grid coord to fill the LDL `target_entry_coord` spinboxes.
- **ICE Editor panel** (scene-tree `PanelContainer`; shown when a BLACK_ICE tile is painted/selected): a "Program .tres..." browse button + "Clear assigned program" button (assigns a **required** `NetProgram` `.tres` whose `program_name`/`strength`/`effect_type`/`damage_dice`/`damage_dice_count` derive the ICE's name/strength/behavior/damage — the program's effect_type and damage are shown as readable text). There is no "Reset to template" button — tier templates have been removed. If no program is assigned, a warning is shown ("NONE — WARNING: no program assigned! This ICE will be skipped at spawn."). `max_integrity` is derived 1:1 from the program's `strength`, movement is STR-based (`program.strength` spaces/turn), and tracing is deferred to program-specific logic — so there are no per-tile scalar stat fields. Edits write back to the tile's `ice_program` field live and persist on save.
- **NPC Editor panel** (scene-tree `PanelContainer`; shown when a NETWATCH/NETRUNNER tile is painted/selected): name `LineEdit`, strength/AP/integrity/health/MU `SpinBox`es, deck name `LineEdit`, disposition `OptionButton` (Hostile/Neutral, items populated in `_ready()`), and a "Reset to template" button. Leave fields at 0/empty to use the hub's tier template; set any field to override. Edits write back to the tile's `npc_*` fields live and persist on save. NETWATCH tiles draw a red shield glyph; NETRUNNER tiles draw a gold person glyph.
- **CPU Editor panel** (scene-tree `PanelContainer`; shown when a CONTROL_NODE tile is painted/selected): read-only info displaying the per-CPU stats (3 INT, 1 action/turn, 10 MU) per CP2020 PnP rules. No editable fields — CPU stats are fixed. CPUs are structural tiles (walkable) and render with a purple diamond glyph; a crashed CPU (`cpu_crashed_turns > 0`) renders dimmed red with an "X" glyph in the gameplay view.
- **Files Editor panel** (scene-tree `PanelContainer`; shown when a `MEMORY_UNIT` tile is painted/selected): an `ItemList` with Add/Edit/Remove/Clear buttons authoring `NetFile`s — name `LineEdit`, description `TextEdit` (lore/flavour), `credit_value` `SpinBox` (fixed authored fence price at the hub, in eb), `mu_size` `SpinBox` (deck MU consumed while carrying). Writes the tile's `files: Array[NetFile]`. This is the new memory-tile loot model (replaces `loot_programs`/`loot_credits` for `MEMORY_UNIT`). The board renderer draws a "data copied" marker on a fully-harvested memory tile.
- **Loot Editor panel** (scene-tree `PanelContainer`; shown when a `CONTROL_NODE` tile is painted/selected): an `ItemList` with Add/Remove buttons loading `NetProgram` `.tres` files → writes the tile's `loot_programs`, plus a `loot_credits` `SpinBox`. This is the runner's "Download Files" program loot, now `CONTROL_NODE`-only (the `MEMORY_UNIT` Loot Editor is replaced by the Files Editor above).
- **Resident Programs editor** (scene-tree `PanelContainer` toggled by a button at the bottom-right; an `ItemList` with Add/Remove buttons loading `NetProgram` `.tres` files): sets `layout.resident_programs` — the programs the [CP2020Datafort](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_datafort.gd) adversary runs against the intruding netrunner each turn. An MU capacity label shows used/total MU (10 × CPU count); adding a program that would overflow available MU is rejected with a warning. Scope for this pass: Krash (player weapon) + anti-runner `DAMAGE_RUNNER` attacks; Murphy / Viral 15 later.
- Dynamic layout resizing (`SpinBox` input for columns/rows).
- Native file open/save dialog integration (scene-tree `FileDialog` nodes) for loading and exporting `.tres` layout files.

### 5.7 World Map Designer Tool ([cp2020_world_map_designer.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_world_map_designer.gd))
- `@tool` editor that authors a `CP2020WorldMapLayout` `.tres` (regions + hubs) consumed at runtime by `cp_2020_world_net_map.gd`.
- Tools: `REGION` (paint region colour), `HUB` (place/select a hub), `ERASER`.
- Side panel edits the selected hub: name, subnet path (+ Browse), **City Grid path** (+ Browse `data/city_grids/*.tres`, writes `hub.city_grid_path`), LDL cost, security code, trace value, set-as-spawn, delete. The Security Tier `OptionButton` is **hidden** (tier moved to City Grid dataforts; field kept on the resource for save compat). Hub chips are drawn as plain cyan markers (no tier glyph). Region list with add/paint.

### 5.7b City Grid Designer Tool ([cp2020_city_grid_designer.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_city_grid_designer.gd)) — *NEW*
- `@tool` editor that authors a `CP2020CityGridLayout` `.tres` (dataforts + LDL entry) consumed at runtime by `cp2020_city_grid.gd`. Save/Load to `data/city_grids/*.tres`.
- Tools: `DATAFORT` (place/select), `LDL_ENTRY` (set the runner arrival tile), `ERASER` (remove a datafort). Settings row: city name `LineEdit`, Cols/Rows `SpinBox`es + Apply Size.
- Side panel edits the selected datafort: name, subnet path (+ Browse `scenes/forts/*.tres`), **Security Tier** `OptionButton` (populated via `CP2020SecurityTier.LABELS`), LDL cost, security code, trace value, delete.
- `_draw`: grid + datafort chips in tier colour (`CP2020SecurityTier.COLORS`) with tier glyph (`CP2020SecurityTier.GLYPHS`) + name; LDL entry ring marker.

### 5.8 Cyberdeck Workbench / Hub UI ([cyberdeck_workbench.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/ui/cyberdeck_workbench.gd))
The workbench is the rogue-like **hub** — loadout plus a Buy/Sell shop. State lives in `RunState` (per-life owned gear, loot, credits) and `MetaState` (persistent catalogue).
- **First-life init**: on first entry (or when `RunState.owned_decks` is empty), calls `RunState.start_new_life()` to seed the starting deck + starting programs (0 eb starting credits — earn from runs).
- **Shop — Buy Decks**: lists every deck path in `MetaState.unlocked_decks` (always includes the starting deck); shows `Cyberdeck.price`; `Buy` checks `RunState.credits >= price`, subtracts, and appends a `duplicate()`d deck to `RunState.owned_decks`.
- **Shop — Buy Programs**: lists every program path in `MetaState.unlocked_programs`; `Buy` checks credits, subtracts `price`, appends a `duplicate()`d program to `RunState.owned_programs`.
- **Shop — Sell Loot**: lists `RunState.loot` (`NetProgram`s); `Sell` pays `price × fence_factor` (default 0.5) into `RunState.credits` and removes the item from loot.
- **Shop — Sell Files** (NEW): lists `RunState.carried_files` (`NetFile`s); each row shows the file's `credit_value` (full authored fence price, **no fence factor**) with a per-file `Sell` button. `Sell` calls `RunState.sell_file(file)` → adds `credit_value` to `RunState.credits` and removes the file from `carried_files`. Separate panel from "Sell Loot" (which is for program loot).
- **Loadout**: deck selection now reads from `RunState.owned_decks`; the program library reads from `RunState.owned_programs`. `Jack In` writes the active deck to `RunState.selected_deck` and changes scene to the world map. Loading/unloading mutates the in-memory (owned) deck resource.
- Three-zone layout: **Deck Stats** (left) | **Loaded into Memory** + `LOAD ▶` / `◀ UNLOAD` / `CLEAR` buttons (centre) | **Program Library** + filter `OptionButton` + detail card (right).
- Two `ItemList`s: **Library** (all `available_programs`, filtered by EffectType category) and **Loaded** (the active deck's `installed_programs`). Items are colour-coded per `EffectType`; library items that won't fit in the remaining MU are greyed out and disabled.
- Click a list item to select it and populate the **detail card** (name, type, effect, STR, MU, price, description). Double-click (or the buttons) load/unload. Load refuses on MU overflow and shows an on-screen `MEMORY FULL` message instead of console `print`.
- MU bar colour states: green (<70%), amber (70–95%), red (≥95%/over).
- `Jack In` writes the active deck to `RunState.selected_deck` and changes scene to the world map. Jacking in with zero programs loaded shows a warning and is blocked until at least one program is loaded.
- **Exit Game button**: an `ExitButton` next to the `Jack In` button calls `get_tree().quit()`. The `ESC` key is also wired to quit via `_unhandled_key_input`.
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
`RunState` is an autoload singleton holding **per-life** state (LOST on death) that survives scene changes within a run.
- **Fields**: `selected_deck`, `selected_subnet_path`, `selected_city_grid_path`, `selected_security_tier`, `credits` (`STARTING_CREDITS = 1000`), `accumulated_trace`, plus the rogue-like additions: `loot: Array[NetProgram]` (run inventory of program loot to sell at the hub), `carried_files: Array[NetFile]` (per-life, like `loot` — discrete files copied from `MEMORY_UNIT` tiles, fenced at the hub; lost on death), `owned_decks: Array[Cyberdeck]`, `owned_programs: Array[NetProgram]` (per-life purchases), and transient death fields `last_death_cause` / `last_run_summary` (read by the GameOver scene).
- **`start_new_life()`** — the permadeath reset: calls `reset()` (full wipe), then loads a `duplicate()`d starting deck (`STARTING_DECK_PATH`) into `owned_decks`/`selected_deck` and `duplicate()`d starting programs (`STARTING_PROGRAM_PATHS`) into `owned_programs`, sets `credits = STARTING_CREDITS`. Used by the GameOver "New Life" button.
- **Buy/Sell helpers**: `add_loot(prog)` (duplicate + `MetaState.unlock_program`), `sell_loot_program(prog, fence_factor=0.5)`, `buy_deck(path)`/`buy_program(path)` (check price, subtract, append duplicate), `equip_deck(deck)`. **File helpers** (NEW): `copy_file(file)` (duplicate + append to `carried_files`), `get_carried_files_mu() -> int` (sum of `mu_size` across `carried_files`, the deck-MU cost of carried files), `sell_file(file)` (sells at full `credit_value` — no fence factor — into `RunState.credits`, removes from `carried_files`).
- **`selected_city_grid_path`** — the city grid currently in play, so the datafort LDL-return can go back to the right city grid.
- **`selected_security_tier`** — set at dive time by the City Grid (the datafort icon's tier); read by `game_session._resolve_security_tier()` for the default ICE loadout. Fallback `LEVEL_1`.
- **Trace** (`accumulated_trace`): the total Trace Value of all LDLs passed through in the current Net run. It drives tracing-ICE detection rolls (ICE must roll `1D10+STR ≥ trace` to locate the runner) and is shown on the world map, city grid, and datafort HUDs. It is **reset to 0** on flatline, jack-out, and return-to-world-map; it is **preserved** across in-datafort LDL travel AND across the datafort→City Grid return (mid-run retreat keeps the trace). The **busted** check (`accumulated_trace >= BUSTED_THRESHOLD`) happens in `_on_jack_out_pressed` *before* trace is cleared.

### 5.12 Meta State — Persistent Catalogue ([meta_state.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/autoload/meta_state.gd)) — *NEW*
`MetaState` is the second autoload singleton (registered **after** `RunState`), holding the **persistent** vendor catalogue that **survives permadeath** and is saved/loaded to `user://netrunner_meta.tres` (Godot's writable per-user dir — never write to `res://` at runtime).
- **Data**: a `MetaStateData` Resource (`class_name MetaStateData`) with `unlocked_decks: Array[String]` (resource paths), `unlocked_programs: Array[String]` (resource paths), and `run_history: Array`. Deduped on insert.
- **Constants**: `STARTING_DECK = "res://data/starting_deck.tres"`, `STARTING_PROGRAMS = ["res://data/codecracker.tres","res://data/shield.tres"]` — the catalogue always contains these (the always-purchasable baseline).
- **API**: `unlock_deck(path)` / `unlock_program(path)` / `unlock_program_resource(prog)` (no-op on empty path), `record_run(summary)`, `has_deck(path)` / `has_program(path)`, `reset_catalogue()`, `save()`. Loads on `_ready`, saves after every mutation.
- **Unlock sources**: looting a `CONTROL_NODE` tile (`RunState.add_loot` → `unlock_program`); defeating an NPC netrunner (`game_session._on_npc_destroyed` → unlocks the template program paths); **and the Workbench PURCHASE UNLOCKS window** (spend credits to buy a blueprint — see §5.14). (Copying `MEMORY_UNIT` files does NOT unlock anything in `MetaState` — files are fenced for credits, not added to the program catalogue.)

### 5.14 Workbench Shop — Two-Tier Buy + Unlock ([cyberdeck_workbench.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/ui/cyberdeck_workbench.gd)) — *NEW*
The hub shop has **two distinct purchase tiers**:
- **PURCHASE UNLOCKS** (a popup `Window`, opened by the shop-column "PURCHASE UNLOCKS" button): spend `RunState.credits` to buy a **blueprint/source-code** that permanently adds a program or deck to the `MetaState` catalogue (`unlock_deck`/`unlock_program`, persists across lives). The unlock catalogue is **all `data/*.tres` decks + programs**, discovered at runtime by scanning `res://data` (`_scan_data_catalogue`, cached). Unlock cost = each item's `.tres` `price`. Already-unlocked rows show `✓ UNLOCKED` (disabled grey); unaffordable rows are disabled. On unlock, the list + the BUY panels refresh so the new item appears for buy-to-own.
- **BUY DECKS / BUY PROGRAMS** (per-life, `RunState`): purchase an item you've *already unlocked* into `owned_decks`/`owned_programs` for the current life only (lost on death). Items come from `MetaState.unlocked_decks`/`unlocked_programs`, filtered to not-already-owned, with unaffordable rows disabled.
- **SELL LOOT** / **SELL FILES**: fence `RunState.loot` (at 50% of `price`) and `RunState.carried_files` (at full `credit_value`) for credits.
- **Starting credits = 0 eb** (`RunState.STARTING_CREDITS = 0`): a fresh life grants starting gear (deck + codecracker + shield via `start_new_life()`) but **no credits**, so persistent unlocks can't be farmed across new lives — credits must be earned from runs (sell loot/files) before buying unlocks/upgrades.

### 5.13 Game Over Scene ([game_over.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/ui/game_over.gd) + `scenes/ui/GameOver.tscn`) — *NEW*
Permadeath end-of-life screen, reached on **Flatline** or **Busted**. Shows a cause-specific header (`RunState.last_death_cause`), the run summary (`RunState.last_run_summary`), and a **New Life** button → `RunState.start_new_life()` + `change_scene_to_file("res://scenes/ui/CyberdeckWorkbench.tscn")`. The `MetaState` catalogue is untouched.

### 5.11 Camera Follow
- Both the world map and the datafort gameplay use a `Camera2D` ("RunnerCamera") parented under the rendered grid. Limits are clamped to the grid rect so the camera never shows outside the map. The camera re-centres on the runner on every position change (`netrunner.position_changed` / world map move).

### 5.15 Combat Effect Animator ([cp2020_combat_effect_animator.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_combat_effect_animator.gd)) — *NEW*
Fire-and-forget visual effect renderer for combat. A `Node2D` (`class_name CombatEffectAnimator`) added **programmatically as a child of the BoardRenderer** in `CP2020GameSession._ready()` (no `.tscn` edit), so its effects draw on top of the grid. Syncs `cell_size` / `grid_offset_y` from the renderer and uses the same grid→pixel formula as `RezzedProgram` / `BlackIce`.
- **Lifecycle**: idle and zero-cost until `play_effect(from_grid, to_grid, visual)` is called — `set_process(false)` in `_ready()`. `play_effect` converts both grid coords to pixel centers, appends an effect entry (`elapsed = 0`), enables `_process`, and `queue_redraw()`s. `_process` advances `elapsed` per effect, removes expired entries, and re-enables idle when none remain. Effects are **non-blocking** — combat resolution (dice rolls, damage) proceeds immediately; the beam is visual flavour that fades over ~0.5s.
- **Visual config lives with the program, not the animator.** The caller passes a `visual` Dictionary (`{color, width, duration, style}`) obtained from `NetProgram.get_attack_visual()` (see §4.10). The animator only renders. Enemy attacks without a `NetProgram` reference (NPC netrunners, datafort resident programs) use the session's `ENEMY_ATTACK_VISUAL` const fallback.
- **Styles** (extensible via the `style` field — new styles add a new `_draw_*` branch):
  - `"beam"`: wide semi-transparent glow underlay + narrow opaque core line, with an alpha envelope (fade-in 0–15%, hold 15–75%, fade-out 75–100%) and an impact-flash circle at the target during 40–60% of the lifetime.
  - `"pulse"` (stub): expanding ring at the target.
  - `"flash"` (stub): radial flash at the target. Unknown styles fall back to `"beam"`.
- **Trigger points** (in `cp2020_game_session.gd`): `_attack_with_rezzed()` fires a beam from the rezzed program to its target before dispatching to the attack handler; the Black-ICE `attacked_netrunner` / `attacked_program` lambdas and the NPC `attacked_netrunner` lambda fire enemy→runner / enemy→rezzed-program beams. Datafort resident-program attacks have no single grid origin and are not beamed (extensible later).

---

## 6. Guide for Future Coding Agents

### 6.1 How to Add a New Program
1. Create a new `.tres` resource file in [data/](file:///c:/Users/mecca/Documents/netrunner-v-0.006/data/).
2. Set `script = ExtResource("res://scripts/resources/cp2020_programs.gd")`.
3. Configure properties (`program_name`, `type`, `effect_type`, `memory_cost`, `strength`, `price`, and optionally `damage_dice` — `0` = flat `strength` per Black ICE hit; `>0` = roll `1D{damage_dice}` per hit, e.g. Sword = 6; and `damage_dice_count` for multi-dice damage, e.g. Hellhound = `damage_dice=10, damage_dice_count=2` for 2D10). Optionally set `glyph` (a single Unicode char) and/or `color` to override the per-`effect_type` `DEFAULT_VISUALS` default for the program's on-map icon (rezzed-program node + Black ICE node + board renderer overlay); leave them blank to inherit the effect-type default (see §5 `get_visual()`). Glyphs auto-centre in their tile via `NetProgram.compute_glyph_centering()` (TextServer bitmap metrics) — only set `glyph_offset` (`Vector2`) if a chosen glyph still sits off-centre (edge case).
4. The hub shop auto-discovers any `NetProgram` `.tres` in `data/` via `cyberdeck_workbench._scan_data_catalogue()` — no catalogue registration needed.
5. To add a program to the player starting loadout, add it to the `installed_programs` array on [cp2020_netrunner.tscn](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scenes/ui/cp2020_netrunner.tscn) or within [cp2020_gameplay.tscn](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scenes/cp2020_gameplay.tscn).
6. **If the program is an attack/defense type that should show a combat beam** (`DEREZ_ICE` / `DAMAGE_RUNNER` / `CRASH_CPU`), add/adjust its entry in `NetProgram.ATTACK_VISUALS` (§4.10) — `{color, width, duration, style}`. Existing styles: `"beam"`. New animation styles require a matching `_draw_*` branch in `CombatEffectAnimator` (§5.15). Non-attack programs need no entry (the animator is only triggered on attacks).

### 6.2 How to Add a New Tile Type
1. Add the enum value to `TileType` in [CP2020DatafortLayout.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/CP2020DatafortLayout.gd).
2. Update graphics rendering in [_draw_tile_graphics](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_board_renderer.gd#L40).
3. Update obstacle logic in [cp2020_netrunner.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_netrunner.gd#L86), [_has_line_of_sight](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_game_session.gd#L163), and [_update_obstacles](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_blackice.gd#L85).
4. Update the editor toolbar buttons in [cp2020_datafort_designer.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_datafort_designer.gd#L88).
5. If the tile hosts an entity (like BLACK_ICE/NETWATCH/NETRUNNER), add a `paint_tile` case, a spawn function + tier templates in [cp2020_game_session.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_game_session.gd), and an editor side panel (mirror `build_ice_panel`/`build_npc_panel`).

### 6.3 How to Add Files to a Memory Tile
1. Open the datafort layout in the datafort designer and paint/select a `MEMORY_UNIT` tile.
2. Use the **Files Editor** side panel (MEMORY_UNIT only) to add/edit/remove/clear `NetFile`s — set `file_name`, `description` (lore), `credit_value` (fixed fence price at the hub, in eb), and `mu_size` (deck MU consumed while carrying). Files are written to the tile's `files: Array[NetFile]`. (`CONTROL_NODE` keeps the Loot Editor for program loot — do not put program loot on `MEMORY_UNIT`.)
3. At runtime, right-clicking a visible, adjacent `MEMORY_UNIT` shows one menu item per file (`"<file_name> (<mu> MU)"`, no credit value shown) plus "Copy All". Each copy is a free action that `duplicate()`s the `NetFile`, appends it to `RunState.carried_files`, and records the file's index in `tile.copied_file_paths` (one-shot). Copy fails if not enough free deck MU — free MU = `deck.max_mu − used_programs_mu − carried_files_mu` (see `CP2020Netrunner.get_used_memory`).
4. Files stay on the tile (never removed) but can't be recopied per-dive. The board renderer draws a "data copied" marker on a fully-harvested memory tile.
5. Carried files survive jack-out (kept in `RunState.carried_files` alongside `loot`) and are fenced at the hub via the workbench's **SELL FILES** panel — `RunState.sell_file(file)` pays the full `credit_value` (no fence factor). Files are lost on death (`reset`/`start_new_life` clear `carried_files`).
6. `copied_file_paths` is reset (cleared) on every `load_subnet` — same cached-instance fog-reset pattern as `is_explored`/`is_visible`/`cpu_crashed_turns`/`is_looted` — so a datafort revisited via LDL travel is re-copyable.

### 6.4 Important Conventions & Gotchas
- **Grid Offset**: The top 90 pixels of the viewport are reserved for UI elements. Always convert world mouse clicks or tile positions using `grid_offset_y = 90` and `cell_size = 40`.
- **Vector2i Coordinates**: Grid positions are integer vectors (`Vector2i`), used as keys in `current_layout.grid_tiles`.
- **`.tres` string keys**: `grid_tiles` dictionaries store keys as `"x,y"` strings when serialised. Always read tiles via `layout.get_tile(coord)` (which handles both `Vector2i` and string keys); never `grid_tiles.get(Vector2i)`.
- **Fog reset on load**: `load_subnet` resets `is_explored`/`is_visible` on every tile because `ResourceLoader` returns a cached instance. Without this, a datafort revisited via LDL travel would show as already-revealed. The same reset now zeroes `cpu_crashed_turns` so revisited CPUs boot fresh, **clears `MEMORY_UNIT` `copied_file_paths`** so revisited memory tiles are re-copyable (per-file one-shot resets each dive), and **zeroes `worm_turns_remaining` / `worm_integrity` / `worm_max_integrity`** so revisited DATAWALL/CODE_GATE tiles don't show a stale worm-in-progress indicator. It also **clears `_watchdog_beacons` / `_watchdog_alerted` / `_deployed_programs`** — deployed Watchdog beacons are per-datafort and do not carry across LDL travel (see the Watchdog beacon reset gotcha below).
- **Deprecated CPU fields**: `CP2020TileData.cpu_int`, `CP2020DatafortLayout.cpu`, and `CP2020DatafortLayout.int_rating` are DEPRECATED — per CP2020 PnP rules each CPU contributes a flat 3 INT. They are kept in the resource classes for .tres backward compat but no longer used in logic.
- **Initiative & system INT**: When all CPUs are crashed, `total_int()` returns 0, so initiative is skipped and the player always goes first. This is intentional — a crashed system can't win initiative.
- **Datafort does not control ICE**: The [CP2020Datafort](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_datafort.gd) adversary runs its **own** `resident_programs` against the runner; it does not command the Black ICE or NPC netrunners, which stay independent turn-manager adversaries. The datafort is prepended to `_all_adversaries()` so it acts first.
- **Floor tiles via designer only**: Hand-authored `.tres` `Empty Path` floor tiles have failed to render in-game, but the same tiles resaved through the datafort designer render correctly. Author floor tiles through the designer; hand-edit `.tres` only for tile properties (e.g. LDL link target fields).
- **LDL link is an ENTRY tile**: There is no separate "return" tile type. Any `ENTRY` tile with `is_ldl_link=true` auto-offers Travel (id `3000`) + Return to City Grid (id `3001`) via the interaction handler. An LDL link with an empty `target_subnet_path` is effectively city-grid-return-only.
- **Primary entry & arrival ordering**: A map's initial-dive arrival point is the ENTRY tile with `is_primary_entry=true` (auto-set on the first plain Entry painted in the designer; adjustable via the Entry/LDL panel "Primary entry" checkbox — at most one per map). `netrunner.initialize` resolves the spawn with a deterministic ordering — `entry_coord` (LDL travel) → primary entry → plain non-LDL ENTRY → any ENTRY — so the initial city-grid dive never lands on an outbound LDL link. An LDL's `target_entry_coord` points into the **remote** map; if that coord has no valid tile, `initialize` falls back to the remote's primary/first ENTRY and `travel_ldl` logs a terminal warning instead of silently dropping the runner somewhere unexpected. `is_primary_entry` defaults `false`, so existing `.tres` files keep the previous behaviour (now preferring non-LDL entries).
- **Trace lifecycle**: `accumulated_trace` resets on flatline / jack-out / return-to-world-map (City Grid "Return to World Map", id 998) / jack-out-to-hub (Datafort Jack Out, City Grid "Jack Out to Hub" id 997, World Map "Jack Out to Hub" id 998 — all route to `CyberdeckWorkbench.tscn`), but is **preserved** across in-datafort LDL travel (`travel_ldl` keeps it) AND across the datafort→City Grid return (`return_world_map` id `3001` goes to the City Grid and keeps trace). The three **end-run exits** (Datafort Jack Out, City Grid Jack Out to Hub, World Map Jack Out to Hub) all end the run and return to the Workbench; the **one-level-back** travel options (Datafort→City Grid via LDL return id `3001`, City Grid→World Map via "Return to World Map" id 998) are preserved.
- **Lambda Signal Connections**: Popup menus disconnect previous `id_pressed` connections before reconnecting to prevent duplicate signal callbacks. Menu id ranges are a collision hazard — check in this order in `_on_menu_action_selected`: LDL travel (`3000`/`3001`) → vertical travel (`3002`/`3003`) → NPC talk (`4000`) → **memory files (`6000+i` per file / `6999` Copy All)** → **Armor-raise (`7000+i`)** → **rez program (`8000+i`)** → **de-rez (`8100+i`)** → **rezzed anti-ICE attack (`8200+i`)** → **rezzed NPC attack (`8300+i`)** → **rezzed CPU crash (`8400+i`)** → `CONTROL_NODE` loot (`loot_tile`) → program use (`1000+i`). Do not reorder. The old direct NPC-attack (`2000+i`) and CPU-crash (`5000+i`) ranges have been removed — attack programs must be rezzed first (Phase 1).
- **Memory-tile file menu ids**: The `MEMORY_UNIT` file menu uses ids `6000+i` per file and `6999` for "Copy All", checked BEFORE the `1000+i` program range to avoid collision. **The old single `6000` `MEMORY_UNIT` `loot_tile` id is removed** — `6000` is now the first file id (`6000+0`). `loot_tile` (program loot) is now `CONTROL_NODE`-only and its id must be kept disjoint from the `6000–6999` file range.
- **`copied_file_paths` is index-based, not resource_path-based**: `MEMORY_UNIT` harvest tracking stores the **indices** (as strings) of already-copied files in `tile.copied_file_paths`, not their `resource_path`. `NetFile`s may be inline-created or `duplicate()`d at runtime, in which case `resource_path` is empty/non-unique, so a path-based check would be unreliable. Always compare against the array index.
- **Loot reset on load**: `load_subnet` resets `is_looted` on every `CONTROL_NODE` tile (same cached-instance rationale as the fog reset) so a datafort revisited via LDL travel is re-lootable. Looting is a **free action** (no turn consumed) and requires the tile to be visible, un-looted, holding loot, and Manhattan-adjacent (≤1) to the netrunner. (Program loot now lives on `CONTROL_NODE`; `MEMORY_UNIT` uses per-file copy via `copied_file_paths`, reset alongside the fog reset — see above.)
- **Watchdog beacon reset on load**: `load_subnet` also clears `_watchdog_beacons`, `_watchdog_alerted`, and `_deployed_programs` (same cached-instance reset pattern as fog/worm/CPU crash). Deployed Watchdog beacons are per-datafort — they do not carry across LDL travel, and a program deployed in one datafort is available again in the next. To run two beacons simultaneously, load two copies of `watchdog.tres` at the workbench (one file, one instance — a deployed program is filtered out of the offered list until the datafort changes).
- **Permadeath**: both flatline and busted route to `GameOver.tscn` (not back to the workbench). `RunState` is per-life (lost on death); `MetaState` is persistent (survives death, saved to `user://netrunner_meta.tres`). `RunState.start_new_life()` is the only correct way to begin a fresh life — it wipes to starting gear. Never write to `res://` at runtime; `MetaState` uses `user://`.
- **NPC catalogue unlock caveat**: NPC programs are `duplicate()`d at spawn, and Godot `Resource.duplicate()` does **not** preserve `resource_path`. So `_on_npc_destroyed` must unlock the **original `.tres` paths** from `TIER_NPC_TEMPLATES[_current_security_tier][faction]["programs"]` directly via `MetaState.unlock_program(path)` — not the duplicate's (empty) `resource_path`. NPCs carry only a `deck_name` String (no `Cyberdeck` resource), so deck-unlock-via-defeat is not possible.
- **NPC program duplication**: `TIER_NPC_TEMPLATES` stores program resource paths (not names). `spawn_npcs` loads and `duplicate()`s each program so cached `.tres` resources are never mutated across runs. The same applies to per-tile `npc_programs` via `_duplicate_programs`.
- **NPC disposition transition**: A neutral netrunner who takes damage flips to hostile for the rest of the run (once hostile, stays hostile). Only damage triggers this — talking does not.
- **@tool panels in code**: The world map and city grid designers build their side panels in code (anchored to stay on-screen) rather than in the `.tscn`, so the scene files stay minimal. The **datafort designer** has been migrated to a scene-tree-based architecture: all UI (toolbar, side panels, file dialogs, grid canvas) is authored in `CP2020DesignerCanvas.tscn` and the root coordinator script (`cp2020_datafort_designer.gd`) references nodes via `@onready` and connects their signals in `_ready()`. The grid canvas (`cp2020_datafort_grid_canvas.gd`, `class_name CP2020DatafortGridCanvas`) is a child `Control` node that owns `_draw` / `_gui_input` / `paint_tile` and emits 5 signals that the root connects to for opening/closing side panels. This lets the layout be rearranged visually in the Godot editor.
- **Resource Persistence**: Layouts are saved as `.tres` resources containing `grid_tiles` dictionaries. When editing resources at runtime, prefer duplicate or freshly instantiated `CP2020TileData` objects to avoid shared reference bugs.
- **Shared default arrays/dicts in CP2020TileData**: Godot shares the default value `[]` / `{}` across all `new()` instances, so `files`, `loot_programs`, `npc_programs`, and `ldl_links` would be shared across all tiles created in the designer. `CP2020TileData._init()` assigns fresh instances of each collection so every `new()` tile gets its own array/dict. `.tres` deserialization overrides these after `_init()`, so loaded layouts are unaffected.
- **Combat effect animator**: `CombatEffectAnimator` (§5.15) is created **programmatically** as a child of the BoardRenderer in `_ready()` (no `.tscn` node). Because it declares a `class_name`, a freshly-added animator won't resolve on first run until the Godot editor rebuilds `global_script_class_cache.cfg` — launch the editor briefly (or run once after editing) if you see `Could not find type "CombatEffectAnimator"`. Visual config for attacks lives with each program (`NetProgram.ATTACK_VISUALS` / `get_attack_visual()`, §4.10); the animator only renders and is generic (not combat-specific) — non-combat effects can call `play_effect()` with any visual Dictionary. Effects are fire-and-forget and non-blocking; do not `await` them or gate combat resolution on them.
