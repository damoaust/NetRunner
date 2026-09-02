class_name CP2020Floor
extends Resource

# Thin Resource wrapper around one floor's tile dictionary. Floors live in
# an `Array[CP2020Floor]` on CP2020DatafortLayout — using a typed array (not
# a Dictionary) keeps the outer collection type-safe, while the inner `tiles`
# dict retains the same Vector2i / "x,y" key structure as the legacy
# `grid_tiles` field. See docs/multi-floor-travel-plan.md §1.

# Vector2i / "x,y" string -> CP2020TileData. Identical structure to
# CP2020DatafortLayout.grid_tiles; the layout's get_tile helper handles both
# key forms transparently.
@export var tiles: Dictionary = {}

# Optional human-readable label (e.g. "B2", "R&D Wing"). Shown in the
# board renderer's floor HUD ("Floor 2/5 — R&D Wing") and the floor-transition
# flash. Empty string is valid — the HUD falls back to "Floor N".
@export var floor_name: String = ""

# NOTE: there is deliberately no floor_index field — the position in the
# layout's `floors` array IS the floor index. A stored duplicate went stale
# silently on inspector reordering (CODE_REVIEW §3.5); enumerate the array
# instead when a numeric index is needed.