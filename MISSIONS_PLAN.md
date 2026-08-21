# Netrunner V0.006 - Missions System Implementation Plan

This document outlines the architecture, data models, UI changes, and workflow for adding the **Missions System** to Netrunner V0.006.

---

## 1. Executive Summary

The **Missions System** introduces a structured bounty/contract layer to the rogue-like hub loop. Players visit a new **Missions tab** on the `CyberdeckWorkbench`, view available high-payout contracts, accept one active mission at a time, navigate to target dataforts manually, fulfill strict requirements (e.g., retrieving a specific file or sabotaging a specific grid target), jack out safely, and return to the workbench to **hand in** the contract for flat credit rewards.

---

## 2. Core Mechanics & Specifications

1. **Workbench Tab**: A dedicated "MISSIONS" tab added to the workbench interface alongside current tabs.
2. **Mission Pool & Refresh**: 
   - A list of available missions is always visible.
   - The board refreshes over time: **one new mission is generated/rotated based on the global world-time system** (tracked in `MetaState` by comparing `current_world_time` vs `last_refresh_timestamp`).
3. **Active Limit**: The player may accept **at most one** mission at a time.
4. **Mission Types & Strict Requirements (Exact Targeting)**:
   - **Data Harvest**: Go to a specific subnet (`target_subnet_path`) and steal a specific named file (`target_file_name`) from a `MEMORY_UNIT` tile, then jack out.
   - **Sabotage**: Travel to a specific subnet (`target_subnet_path`) and execute a sabotage action at an **exact grid coordinate** (`target_coord: Vector2i`).
   - **Recon**: Navigate to an exact coordinate (`target_coord`) within a specific subnet (`target_subnet_path`) to survey/scan the node.
5. **No Timers (For Now)**: Contracts have no expiration time limit during a run, but failing a run (death/busted) discards the active mission.
6. **Rewards**: Flat credit payment handed in upon successful completion at the workbench.
7. **Failure**: Mission progress is lost on death/busted; no additional penalties.
8. **Navigation & Tracking**: The player must find their own way; the Active Mission Status Box displays a simple target location label (e.g., "Night City: City Hall").
9. **Hand-in Requirement**: Missions are *not* auto-completed on jack-out; the player must return to the workbench with the required proofs/files and click **"Hand In"**.

---

## 3. Data Models (Custom Resources)

### 3.1 `CP2020Mission` (`scripts/resources/cp2020_mission.gd`)
Extends `Resource`. Represents a single contract/mission.

- **Properties**:
  - `mission_id: String` (Unique identifier)
  - `title: String` (e.g., "City Hall Mainframe Sabotage")
  - `description: String` (Lore details and target instructions)
  - `mission_type: MissionType` (Enum: `DATA_HARVEST`, `SABOTAGE`, `RECON`)
  - `reward_credits: int` (Credit payment on hand-in)
  - **Exact Targeting Fields**:
    - `target_subnet_path: String` (Path to the destination subnet `.tres`)
    - `target_coord: Vector2i` (Exact grid coordinate `Vector2i(x, y)` for Sabotage/Recon)
    - `target_file_name: String` (Exact file name required for Data Harvest)
  - `is_completed: bool`
  - `source_path: String`

---

## 4. State Management & Persistence

### 4.1 MetaState Integration (`MetaState` / `MetaStateData`)
- Persists available mission pools and timer state across runs (`user://netrunner_meta.tres`).
- Tracks the last refresh timestamp to generate a new mission every hour.

### 4.2 RunState Integration (`RunState`)
- `active_mission: CP2020Mission` (holds the currently accepted mission).
- `mission_objective_met: bool` (tracks exact coordinate sabotage/recon completion during the run).
- `check_sabotage_target(subnet_path, coord)`: Validates exact coordinate matches when the player performs sabotage actions.

---

## 5. UI Design: Workbench Missions Tab

Added to `CyberdeckWorkbench` (`CyberdeckWorkbench.tscn` / `cyberdeck_workbench.gd`):
- **Layout**:
  - Left/Center: **Available Missions List** (shows title, type, target city, reward).
  - Right: **Mission Detail Card** (full description, requirements, "Accept Mission" button).
  - Bottom/Header: **Active Mission Status Box** (shows current accepted mission, progress status, and **"Hand In Contract"** button when requirements are met).

---

## 6. Implementation Roadmap

### Phase 1: Resource & Data Layer
1. Create `CP2020Mission` script resource class.
2. Create sample mission `.tres` files in `data/missions/`.
3. Extend `MetaStateData` to store available missions, active mission, and refresh timestamps.

### Phase 2: Workbench UI Integration
1. Add the Missions tab to the `CyberdeckWorkbench` scene.
2. Implement the available mission list, detail view, and hourly refresh logic.
3. Wire up "Accept Mission" and active mission display.

### Phase 3: Gameplay & Verification Hook
1. Implement mission validation logic when checking items at the workbench (e.g., comparing `carried_files` against `target_file_name`).
2. Wire up the "Hand In" button to pay out credits and close the mission.
3. Test the full loop: Accept mission $\rightarrow$ Travel $\rightarrow$ Hack/Steal $\rightarrow$ Jack out $\rightarrow$ Return to Workbench $\rightarrow$ Hand in $\rightarrow$ Receive credits.

---

## 7. Implementation Status (COMPLETE)

All three phases are implemented and validated.

### Data layer
- `CP2020Mission` (`scripts/resources/cp2020_mission.gd`): `MissionType` enum (`DATA_HARVEST`, `SABOTAGE`, `RECON`), all targeting fields (`target_subnet_path`, `target_coord: Vector2i`, `target_file_name`), `reward_credits`, `objective_text()` / `type_tag()` / `type_label()` helpers, and a runtime `source_path` tag for save/load.
- Static library: 10 authored `.tres` files in `data/missions/` (4 Data Harvest, 3 Sabotage, 3 Recon), each referencing a real, reachable subnet + exact coordinate / file name. Regenerable via `scripts/dsh/author_missions.gd`.

### State layer (per-life, in `RunState` / `RunStateData`)
- `available_missions: Array[CP2020Mission]`, `active_mission: CP2020Mission`, `mission_objective_met: bool`, `last_mission_refresh_time: float`.
- Board seeded on `start_new_life()` (`_seed_mission_board`, `MISSION_BOARD_SIZE = 4`).
- Hourly refresh (`check_mission_refresh`, `MISSION_REFRESH_SECONDS = 3600`): rotates the oldest entry for a fresh library mission when ≥ 1 hour of net-time has elapsed. The clock only ticks while jacked in (`RunState.net_time_seconds`), so the board does not advance at the hub.
- Accept (`accept_mission` — one active at a time), abandon (`abandon_mission` — returns to board), hand-in (`hand_in_mission` — pays flat reward; for DATA_HARVEST also removes the proof file from `carried_files`).
- Objective notify hooks called by the game session: `notify_file_copied`, `notify_action_at_coord`, `notify_position`.
- Persisted across app restarts via `RunStateData` (paths); older saves without the fields re-seed a fresh board automatically.

### Gameplay hooks (`cp2020_game_session.gd`)
- Added `current_subnet_path` (set in `load_subnet`, LDL-travel-safe) so objective subnet checks compare against the *current* datafort, not the stale `RunState.selected_subnet_path`.
- **DATA_HARVEST**: `notify_file_copied` fires on `copy_file` and `copy_all_files` when the copied file's name matches the active mission's target.
- **SABOTAGE**: `notify_action_at_coord` fires for `attack_with_rezzed` / `command_demon` / `loot_tile` when the action targets the exact mission coordinate in the target subnet (covers CPU crash, ICE/NPC attack, node loot).
- **RECON**: a new `position_changed` handler (`_on_netrunner_position_changed_mission`) sets the flag when the runner steps onto the target coord in the target subnet.
- Each objective completion logs `>> MISSION OBJECTIVE MET: <title> — jack out and hand in at the workbench.` to the datafort terminal.
- Active mission + objective flag are preserved across a successful jack-out (so the runner can hand in) and discarded on death/busted (`reset()` clears them via `start_new_life`).

### Workbench UI (Missions tab, index 2 in `CyberdeckWorkbench.tscn`)
- Available-contracts list (colour-coded by type), detail card (title/type/location/objective/reward/briefing), Accept button (disabled while a mission is active).
- Active-contract status box with live objective + completion indicator and Hand In / Abandon buttons (Hand In disabled until `can_hand_in_mission()`).
- Refresh countdown label ("Next contract in: Xm Ys of net-time").
- Re-checks the board refresh + repopulates on tab switch to Missions and on workbench entry.

### Reachability
- City Hall (Night City grid) already targets `night_city_subnet.tres` via the `CP2020CityGridDatafort` default path — its MEMORY_UNIT tiles carry the named files used by the Data Harvest contracts.
- Two new Night City dataforts were wired in via `scripts/dsh/wire_mission_subnets.gd` (idempotent): "Pirate BBS" → `p2.tres`, "Warez Node" → `p5.tres`, so those file-bearing subnets are diveable.

### Verification
- Headless boot (`--quit-after`) loads the project with zero script errors (only pre-existing unrelated UID warnings).
- Functional test `scripts/dsh/test_missions_runner.tscn` (run as a scene so autoloads resolve): backs up the user save, drives a fresh life through DATA_HARVEST / SABOTAGE / RECON accept→objective→hand-in, the active-mission limit, and the board refresh — **all PASS** — then restores the save.
- In-game smoke test: the Missions tab renders 4 contracts, the active box reads "No active contract.", and the refresh countdown reads "Next contract in: 60m 0s of net-time".
