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
├── data/                             # Resource instances (.tres) for decks & programs
│   ├── starting_deck.tres            # Cyberdeck resource instance
│   ├── codecracker.tres              # Program resources (.tres)
│   ├── killer_2_0.tres
│   └── ...
├── scenes/                           # Godot scene files (.tscn)
│   ├── cp2020_gameplay.tscn          # Main gameplay scene
│   ├── forts/                        # Saved datafort maps (.tres resources)
│   └── ui/                           # Subscenes (Netrunner avatar, Black ICE, Designer, Workbench)
│       ├── cp2020_blackice.tscn
│       ├── cp2020_netrunner.tscn
│       ├── CP2020DesignerCanvas.tscn
│       └── CyberdeckWorkbench.tscn
└── scripts/                          # GDScript source code
    ├── resources/                    # Core gameplay resources, nodes & controllers
    │   ├── CP2020DatafortLayout.gd   # Datafort grid layout Resource definition
    │   ├── CP2020TileData.gd         # Individual grid tile state Resource definition
    │   ├── cp2020_blackice.gd        # Black ICE enemy AI node (AStarGrid2D)
    │   ├── cp2020_board_renderer.gd  # CanvasItem custom grid renderer (Fog of War)
    │   ├── cp2020_canvas.gd          # UI container grid loader (legacy/placeholder)
    │   ├── cp2020_cyberdecks.gd      # Cyberdeck data Resource class
    │   ├── cp2020_datafort_designer.gd # Editor tool script for building maps
    │   ├── cp2020_game_session.gd    # Main gameplay session manager / orchestrator
    │   ├── cp2020_interaction_handler.gd # Contextual right-click PopupMenu handler
    │   ├── cp2020_netrunner.gd       # Player Netrunner entity controller
    │   ├── cp2020_programs.gd        # Software program Resource class
    │   ├── cp2020_subnet_loader.gd   # ResourceLoader for datafort layout files
    │   └── cp2020_turn_manager.gd    # Turn state controller
    └── ui/
        └── cyberdeck_workbench.gd    # Cyberdeck loadout & program management UI script
```

---

## 3. Core Architecture & Component Diagram

The gameplay loop is built around a decoupled component architecture centered on [cp2020_game_session.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_game_session.gd).

```mermaid
graph TD
    GameSession["GameSession (cp2020_game_session.gd)"]
    SubnetLoader["SubnetLoader (cp2020_subnet_loader.gd)"]
    BoardRenderer["BoardRenderer (cp2020_board_renderer.gd)"]
    Netrunner["CP2020Netrunner (cp2020_netrunner.gd)"]
    BlackIce["BlackIce (cp2020_blackice.gd)"]
    InteractionHandler["InteractionHandler (cp2020_interaction_handler.gd)"]
    TurnManager["TurnManager (cp2020_turn_manager.gd)"]

    SubnetLoader -->|subnet_loaded(layout)| GameSession
    GameSession -->|draw_grid(canvas, layout)| BoardRenderer
    GameSession -->|recalculate_fog_of_war| BoardRenderer
    Netrunner -->|position_changed(pos)| GameSession
    Netrunner -->|interacted_with_tile| GameSession
    InteractionHandler -->|action_triggered(name, coord, prog)| GameSession
    GameSession -->|execute_decryption| Netrunner
    TurnManager -->|turn_ended| GameSession
    BlackIce -->|attacked_netrunner(strength)| GameSession
```

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
  - `EMPTY` (0), `WALL` (1), `DATAWALL` (2), `ENTRY` (3), `CODE_GATE` (4), `MEMORY_UNIT` (5), `CONTROL_NODE` (6), `BLACK_ICE` (7)

### 4.2 `CP2020TileData` ([CP2020TileData.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/CP2020TileData.gd))
Represents state and attributes of a single cell in the datafort layout grid.
- **Properties**:
  - `tile_type: CP2020DatafortLayout.TileType`
  - `tile_name: String`
  - `strength_str: int` (Used as hit points / Difficulty Value for Code Gates and Datawalls)
  - `memory_units_mu: int`
  - `reward_credits: int`
  - `is_unlocked: bool` (Breach / Decrypted state for Code Gates)
  - `ldl_links: Dictionary`
  - `is_visible: bool` (Dynamic Line of Sight visibility)
  - `is_explored: bool` (Visited or previously seen tile state for Fog of War)

### 4.3 `Cyberdeck` ([cp2020_cyberdecks.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_cyberdecks.gd))
Represents the Netrunner's hardware deck.
- **Properties**:
  - `deck_name: String`
  - `max_mu: int` (Maximum Memory Units storage capacity)
  - `speed_bonus: int`
  - `data_wall_strength: int`
  - `installed_programs: Array[NetProgram]`
- **Methods**: `get_used_mu() -> int`

### 4.4 `NetProgram` ([cp2020_programs.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_programs.gd))
Represents an executable program software tool loaded into a cyberdeck.
- **ProgramType Enum**: `DECRYPTION`, `DETECTION`, `ANTI_PROGRAM`, `ANTI_PERSONNEL`, `ANTI_SYSTEM`, `UTILITY`, `ICE`
- **EffectType Enum**:
  - `BYPASS_GATE`: Cracks Code Gates by reducing `strength_str`
  - `DEREZ_ICE`: Destroys hostile Black ICE
  - `DAMAGE_RUNNER`: Black ICE direct attacks
  - `REVEAL_NODES`: Scans hidden layout nodes
  - `MODIFY_MU`: Modifies deck speed or memory capacity
- **Properties**: `program_name`, `type`, `effect_type`, `memory_cost` (MU), `strength` (added to attack/decryption rolls), `price`, `icon`

---

## 5. Core Systems & Implementation Details

### 5.1 Game Session Orchestrator ([cp2020_game_session.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_game_session.gd))
Controls gameplay flow, scene initialization, input routing, turn changes, terminal logs, and program interactions.
- **Constants & Grid Math**:
  - `cell_size = 40` px
  - `grid_offset_y = 90` px (Reserving top UI header space)
  - Coordinates match formula: `Vector2(coord.x * 40 + 20, 90 + coord.y * 40 + 20)`
- **Line of Sight / Fog of War**:
  - Uses a grid-based Bresenham raycasting line-of-sight algorithm ([_has_line_of_sight](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_game_session.gd#L163)) up to `vision_radius = 10`.
  - Blocked by `DATAWALL` tiles and locked `CODE_GATE` tiles (`is_unlocked == false`).
  - Sets `tile.is_visible = true` and `tile.is_explored = true`.
- **Decryption Mechanics**:
  - Initiated when player selects a decryption program (`BYPASS_GATE`) via right-click contextual menu on a Code Gate.
  - Roll: `(randi() % 10) + 1 + program.strength` (Cyberpunk 2020 1d10 + Program STR rule).
  - Check: If `total_roll >= tile.strength_str`, `tile.is_unlocked = true`, immediately clearing the movement obstacle, changing tile color from orange to green, and recalculating Line of Sight. Otherwise, the attempt fails and logs the roll details to the terminal.

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
- Validates movement obstacles: blocks movement into `DATAWALL` tiles or locked `CODE_GATE` tiles.
- Spawns at the datafort's `ENTRY` tile upon layout loading.

### 5.4 Hostile Black ICE AI ([cp2020_blackice.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_blackice.gd))
- **Pathfinding**: Instantiates an `AStarGrid2D` instance over the layout matrix region.
- Dynamic obstacle update ([_update_obstacles](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_blackice.gd#L85)): dynamic solid points applied to `DATAWALL` tiles and locked `CODE_GATE` tiles.
- **States**: `IDLE` -> `PURSUE`. Activates upon turn execution, taking up to `max_ap` (3) steps per turn toward the Netrunner's position.
- **Fog of War Visibility**: Dynamically updates visual icon (`skull_label`) visibility based on tile fog state.

### 5.5 Contextual Right-Click Input Handler ([cp2020_interaction_handler.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_interaction_handler.gd))
- Captures right-click mouse events over grid cells.
- Converts mouse pixel coordinates to grid cell coordinates `Vector2i(grid_x, grid_y)`.
- Checks if tile `is_explored` (menus are blocked on unexplored tiles).
- Queries Netrunner's installed programs for matching `effect_type` (e.g. `BYPASS_GATE` for Code Gates).
- Dynamically creates and opens a `PopupMenu` near mouse location with positive offset IDs (`1000 + i`) mapped to program choices, firing `action_triggered`.

### 5.6 Datafort Designer Tool ([cp2020_datafort_designer.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/resources/cp2020_datafort_designer.gd))
- Runs in editor (`@tool` annotation).
- Visual editor interface for painting tiles (`Entry`, `Datawall`, `Code Gate`, `Memory Unit`, `Control Node`, `Black ICE`, `Eraser`).
- Dynamic layout resizing (`SpinBox` input for columns/rows).
- Native file open/save dialog integration (`FileDialog`) for loading and exporting `.tres` layout files.

### 5.7 Cyberdeck Workbench UI ([cyberdeck_workbench.gd](file:///c:/Users/mecca/Documents/netrunner-v-0.006/scripts/ui/cyberdeck_workbench.gd))
- UI screen displaying active Cyberdeck details (Deck Name, Speed Bonus, Memory Units used/total, Data Wall STR, Interface Rank).
- Lists currently installed programs in an `ItemList`.

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

### 6.3 Important Conventions & Gotchas
- **Grid Offset**: The top 90 pixels of the viewport are reserved for UI elements. Always convert world mouse clicks or tile positions using `grid_offset_y = 90` and `cell_size = 40`.
- **Vector2i Coordinates**: Grid positions are integer vectors (`Vector2i`), used as keys in `current_layout.grid_tiles`.
- **Lambda Signal Connections**: Popup menus disconnect previous `id_pressed` connections before reconnecting to prevent duplicate signal callbacks.
- **Resource Persistence**: Layouts are saved as `.tres` resources containing `grid_tiles` dictionaries. When editing resources, prefer duplicate or freshly instantiated `CP2020TileData` objects to avoid shared reference bugs.
