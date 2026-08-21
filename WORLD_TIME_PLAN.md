# Netrunner V0.006 - Global World-Time System Implementation Plan

This document outlines the architecture for the **World-Time System** which acts as the global clock for mission rotations and future timed game events.

---

## 1. Executive Summary

The **World-Time System** tracks the passage of time based on player actions (Action Points). Time progresses exclusively within the Net (Subnets, City Grids, World Map) and is managed as part of the `RunState` (resetting on every `NewLife`). The mission system utilizes this global clock to rotate available contracts when the player returns to the hub after sufficient time has elapsed.

---

## 2. Core Mechanics

1. **Tick Mechanism**: Time advances based on Action Points (AP) spent by the player. Each action type (movement, hacking, etc.) contributes a specific amount of time, scaled by the current map environment (World Map vs. City Grid vs. Subnet).
2. **Units**: Time is stored as a high-precision float (`total_seconds`), providing days, hours, minutes, seconds, and nanoseconds.
3. **Persistence & Reset**: The clock is stored in `RunState` and resets to `0` whenever `RunState.start_new_life()` is called (permadeath).
4. **Mission Rotation**: When entering the Workbench, the system compares the current `total_seconds` against the `last_mission_refresh_time`. If ≥ 3600 seconds (1 hour) have passed, it rotates the mission pool.

---

## 3. Data Models

### 3.1 `WorldClock` (`scripts/resources/world_clock.gd`)
A helper resource/script to manage time calculations.

- **Properties**:
  - `total_seconds: float`
- **Methods**:
  - `advance_time(actions: int, environment_scale: float)`: Updates `total_seconds`.
  - `get_time_formatted() -> Dictionary`: Returns `{days, hours, minutes, seconds, nanos}`.

---

## 4. Implementation Roadmap

### Phase 1: World-Time Integration
1. Implement `WorldClock` logic within `RunState`.
2. Update `TurnManager` and `GameSession` to call `RunState.advance_time(actions, scale)` whenever actions are consumed.

### Phase 2: Workbench Refresh Hook
1. Add `last_mission_refresh_time` to `MetaStateData` (to ensure persistent tracking of the refresh).
2. Implement the `check_mission_refresh()` logic in `cyberdeck_workbench.gd`.
3. Create the rotation logic: removes the oldest mission and appends a new one from the static library.

### Phase 3: Testing
1. Verify time scaling in different environments (World Map vs. Subnet).
2. Validate that `total_seconds` resets correctly upon initiating a `NewLife`.
3. Verify mission rotation triggers after 3600 seconds of accumulated action-time.
