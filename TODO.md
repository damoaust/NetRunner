# Netrunner V0.006 - Development TODO

## Harness Setup
- [x] Create scripts/dsh directory.
- [x] Create scripts/dsh/dsh_harness.js.
- [x] Implement mission generation logic in `dsh_harness.js`.

## Missions System (IMPLEMENTED)
- [x] Create `CP2020Mission` resource class (`scripts/resources/cp2020_mission.gd`).
- [x] Author static mission library (11 `.tres` files in `data/missions/`).
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
- `check_scripts.gd` / `.tscn` — full-compile gate: load()s every `.gd` in the project; run as a scene so autoloads resolve. Run: `godot --headless --path . res://scripts/dsh/check_scripts.tscn`.

## Open Items (triaged from CODE_REVIEW.md + plan docs — feature/2.5d-visual-upgrade)

Refactors:
- [x] Split `cyberdeck_workbench.gd` into sub-scripts (CR §6.4) — popup windows extracted to `WorkbenchSubroutinesWindow` / `WorkbenchUpgradesWindow` (1880 → 1529 lines). Shop + missions domains remain:
- [ ] Continue workbench split: shop + missions domains into sub-scripts (1529 lines remain).
- [x] Extract per-arm handlers from `_on_action_triggered`'s ~230-line match; collapse `handle_right_click`'s long if/elif (CR §7.3/§7.4).
- [x] De-duplicate `_can_travel_vertical` — the interaction handler mirrors the game session's authoritative one (CR §7.10).
- [x] World-map designer: delegate rendering to the shared renderer (CR §5.1 — new `CP2020WorldMapRenderer` used by runtime + designer).

Bugs / polish:
- [x] Add `Protection` to the workbench `PROGRAM_TYPE_NAMES` map (rendered "?") — renamed the enum member to `PROTECTION` and added it to both label maps (CR §3.7).
- [x] Workbench HP label printed `max_health` twice — now reads "MAX HP: n" (CR §6.6).
- [x] Watchdog trace tie used `>=` (attacker-favored) — now `>`, defender-favored like every other opposed roll (CR §4.9).
- [x] Copy-menu `fits` check now decrements `free_mu` per copyable file, matching `copy_all_files` (CR §7.11).
- [x] Removed dead NPC `max_health` / `current_health` fields + template/spawn writes (shield model lives on integrity; CR §4.1). `TileData.npc_max_health` kept, documented deprecated.
- [x] Persist the run save at the end of `start_new_life()` — already implemented (`save_run()` with explanatory comment); no change needed (CR §6.5).

Data model / perf:
- [x] `CP2020Floor.floor_index` removed entirely — array position is the floor index; designer add/remove resync was already correct, and nothing read the field (CR §3.5).
- [x] `generate_theme.gd` palette consts now alias `CP2020Theme` instead of re-declaring Colors (CR §5.4).
- [x] Designer canvas `_ready` no longer creates a throwaway layout; parent owns the lifecycle (CR §5.7).
- [x] Per-frame `queue_redraw()` resolved: netrunner skips redraw in 3D mode / when hidden; world map delegates to the renderer child (CR §8.3).

Future (flagged in plans, not scheduled):
- [ ] `follows_across_floors` per-program flag so tracker ICE (Hellhound, Flatline) can pursue across floors (multi-floor plan §"Design decision: floors as escape hatches").