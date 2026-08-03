class_name CP2020SecurityTier
extends RefCounted

# CP2020 datafort security classification. Single source of truth for tier
# metadata shared by the world hub (legacy field), the City Grid datafort
# icon, the designers and the runtime renderers. Distinct from a hub's
# `security_code`, which is the LDL hack difficulty (1D10 >= code).
enum Tier { GREY, LEVEL_1, LEVEL_2, LEVEL_3, BLACK }

const LABELS: Dictionary = {
	Tier.GREY: "GREY",
	Tier.LEVEL_1: "LEVEL 1",
	Tier.LEVEL_2: "LEVEL 2",
	Tier.LEVEL_3: "LEVEL 3",
	Tier.BLACK: "BLACK",
}
const SHORT: Dictionary = {
	Tier.GREY: "Grey",
	Tier.LEVEL_1: "L1",
	Tier.LEVEL_2: "L2",
	Tier.LEVEL_3: "L3",
	Tier.BLACK: "Black",
}
const COLORS: Dictionary = {
	Tier.GREY: Color(0.62, 0.62, 0.62, 1.0),
	Tier.LEVEL_1: Color(0.20, 0.90, 0.35, 1.0),
	Tier.LEVEL_2: Color(1.00, 0.85, 0.20, 1.0),
	Tier.LEVEL_3: Color(1.00, 0.55, 0.15, 1.0),
	Tier.BLACK: Color(1.00, 0.22, 0.27, 1.0),
}
const GLYPHS: Dictionary = {
	Tier.GREY: "G",
	Tier.LEVEL_1: "1",
	Tier.LEVEL_2: "2",
	Tier.LEVEL_3: "3",
	Tier.BLACK: "B",
}