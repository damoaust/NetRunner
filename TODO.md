# Netrunner V0.006 - Development TODO

## Harness Setup
- [x] Create scripts/dsh directory.
- [x] Create scripts/dsh/dsh_harness.js.
- [x] Implement mission generation logic in `dsh_harness.js`.

## Missions System (IMPLEMENTED)
- [x] Create `CP2020Mission` resource class (`scripts/resources/cp2020_mission.gd`).
- [x] Author static mission library (10 `.tres` files in `data/missions/`).
- [x] Extend `RunStateData` with mission persistence fields (available pool, active mission, objective flag, refresh timestamp).
- [x] Extend `RunState` with `active_mission`, `available_missions`, `mission_objective_met`, `last_mission_refresh_time`; board seeding, hourly refresh, accept/abandon/hand-in, objective notify hooks, save/load.
- [x] Wire objective checks in `cp2020_game_session.gd`: DATA_HARVEST (copy_file / copy_all_files), SABOTAGE (attack_with_rezzed / command_demon / loot_tile at target coord), RECON (netrunner position_changed). Added `current_subnet_path` tracking (LDL-travel-safe).
- [x] Add Missions tab to `CyberdeckWorkbench.tscn` (available list, detail card, accept button, active status box, hand-in + abandon buttons, refresh countdown).
- [x] Implement Missions tab UI logic in `cyberdeck_workbench.gd`.
- [x] Wire file-bearing subnets into Night City city grid (Pirate BBS → p2, Warez Node → p5; City Hall already → night_city_subnet via the datafort default path).
- [x] Validate: headless boot (no script errors) + functional test (`scripts/dsh/test_missions_runner.tscn` — all flows PASS) + in-game UI smoke test (4 contracts render, refresh countdown correct).

### DSH helper scripts (scripts/dsh/)
- `scan_mission_targets.gd` — headless scan of datafort MEMORY_UNIT / CONTROL_NODE coordinates (used to author against real targets).
- `wire_mission_subnets.gd` — adds the Pirate BBS / Warez Node datafort entries to the Night City grid (idempotent).
- `author_missions.gd` — regenerates the `data/missions/*.tres` library from the spec table (idempotent).
- `test_missions_runner.gd` / `.tscn` — headless functional test runner (backs up + restores the user's run save).