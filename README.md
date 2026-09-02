# Netrunner V0.006

A **Cyberpunk 2020 (CP2020) netrunning simulation** built in Godot 4.7 — grid-based datafort intrusion, fog-of-war matrix exploration, turn-based Black ICE pathfinding, and cyberdeck/program loadout management, wrapped in a permadeath rogue-like meta-loop.

> **Looking for the technical docs?** [ARCHITECTURE.md](ARCHITECTURE.md) is the **single source of truth** for system internals, data models, signal flows, and the coding-agent guide. This README is the front door: what the game is, how to run it, and where to find things.

## What's in the box

- **Netrunning core loop** — jack into dataforts via a three-level map model: **Workbench (hub)** → **World Map** → **City Grid** → **Datafort** (see [ARCHITECTURE.md §3](ARCHITECTURE.md))
- **CP2020 combat model** — unified action economy (move-or-program), initiative rolls, Black ICE AI with A* pathfinding, program effects from flat damage to 2D10 dice
- **Permadeath meta-loop** — die in the Net and your run state is lost; blueprint unlocks persist and are repurchased across lives
- **Missions system** — contract/bounty layer with a rotating mission board on the workbench
- **2.5D visuals** — optional 3D proxies for rezzed programs/ICE with Fresnel outlines
- **Agent harness** — `scripts/dsh/` headless tools plus a localhost TCP automation server for driving the game from scripts

## Requirements

- **Godot 4.7** (Forward Plus renderer; developed against 4.7.2)
- Optional: local copies of `data/seguiemj.ttf` (Segoe UI Emoji) and `data/webdings.ttf` for full glyph rendering — deliberately not committed; the game degrades gracefully without them (see [ARCHITECTURE.md](ARCHITECTURE.md))

## Getting started

```bash
git clone https://github.com/damoaust/NetRunner.git
cd NetRunner
godot --editor .        # or open the project from the Godot Project Manager
```

- **Run the game**: `F5` in the editor, or `godot --path .` from the project directory
- **Headless validation** (no display needed):

  ```bash
  godot --headless --import        # import assets + rebuild script class cache
  godot --headless --quit-after 10 # boot smoke test (10 frames)
  ```

- **Headless functional test**: `scripts/dsh/test_missions_runner.tscn` exercises the missions flows end-to-end; the game also exposes a localhost automation API (`McpInteractionServer`, TCP `127.0.0.1:9090`) used by the `scripts/dsh/` tools — see [ARCHITECTURE.md §8](ARCHITECTURE.md)

## Controls

| Input | Action |
|---|---|
| `W A S D` | Move the netrunner |
| Right-click | Contextual tile actions (use programs, copy files, loot, attack, travel…) |
| `Space` | End the current movement action early / end the turn |

## Project layout

```
netrunner-v-0.006/
├── project.godot            # Godot project config & input maps
├── autoload/                # MCP interaction server (TCP automation, dev tool)
├── data/                    # Resource instances (.tres): decks, programs, missions, maps
├── scenes/                  # Game scenes: gameplay, forts, ui/, models/
├── scripts/
│   ├── autoload/            # RunState / MetaState singletons (+ screenshot tool)
│   ├── programs/            # Program behaviour (Demon, Probe, Speed, Watchdog, Worm)
│   ├── resources/           # Core gameplay resources, nodes & controllers
│   ├── dsh/                 # Headless agent-harness helpers (test runner, mission tooling)
│   ├── shaders/             # 3D outline shader
│   └── ui/                  # Workbench, game-over screens
├── themes/                  # UI themes (cyberpunk_theme.tres)
├── tools/                   # One-shot build/generation tools
├── docs/                    # Design plans (multi-floor travel)
└── ARCHITECTURE.md          # Full technical reference — START HERE for code work
```

## Documentation map

| Document | Purpose |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | **Single source of truth** — §1 tech stack · §2 directory · §3 architecture diagram · §4 data models · §5 core systems · §6 agent guide & gotchas · §7 missions · §8 MCP server |
| [MISSIONS_PLAN.md](MISSIONS_PLAN.md) | Missions system design (implemented) |
| [WORLD_TIME_PLAN.md](WORLD_TIME_PLAN.md) | World-time / net-time clock design (implemented) |
| [TODO.md](TODO.md) | Development checklist |
| [CODE_REVIEW.md](CODE_REVIEW.md) | Historical code-review snapshot |
| [docs/multi-floor-travel-plan.md](docs/multi-floor-travel-plan.md) | Multi-floor datafort travel design |

## Working on the project

- **Documentation policy**: [ARCHITECTURE.md](ARCHITECTURE.md) is where technical facts live — update it when systems change and keep this README to quick-start, layout, and links. Don't duplicate technical content in both files.
- **Branch policy**: active development happens on `feature/2.5d-visual-upgrade`; `main` tracks stable milestones.
- **Proprietary fonts**: never commit `data/seguiemj.ttf` / `data/webdings.ttf` (see `.gitignore`) — font references in code must tolerate their absence.