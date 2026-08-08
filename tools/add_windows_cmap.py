"""Add a Windows-platform (3,1) cmap subtable to data/webdings.ttf.

The bundled webdings.ttf only has a legacy Mac-platform (1,0,0) format-0
cmap that Godot/HarfBuzz cannot resolve, so U+0043 (the "C" = cityscape
glyph) renders as a tofu "43" box. This script adds a Unicode BMP
(3,1) cmap mirroring the Mac mapping (ASCII 0x20-0x7E -> glyph ids 3-97)
so Godot can look the glyphs up by codepoint.
"""
import sys
from pathlib import Path
from fontTools.ttLib import TTFont


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    src = repo / "data" / "webdings.ttf"
    if not src.exists():
        print(f"ERROR: {src} not found", file=sys.stderr)
        return 1

    font = TTFont(str(src))
    cmap = font["cmap"]

    existing = None
    for sub in cmap.tables:
        if sub.platformID == 1 and sub.platEncID == 0 and sub.format == 0:
            existing = sub
            break
    if existing is None:
        print("ERROR: no Mac (1,0,0) format-0 cmap to mirror", file=sys.stderr)
        return 1

    mac_map = existing.cmap
    if not mac_map:
        print("ERROR: Mac cmap is empty", file=sys.stderr)
        return 1

    # Mirror every Mac mapping into Unicode codepoints (already U+0020-U+007E).
    win_map = dict(mac_map)

    # Sanity: confirm the cityscape glyph resolves.
    gid = win_map.get(0x43)
    print(f"U+0043 -> glyph {gid}")
    if gid is None:
        print("ERROR: U+0043 missing from mapping", file=sys.stderr)
        return 1

    from fontTools.ttLib.tables._c_m_a_p import CmapSubtable

    sub = CmapSubtable.newSubtable(4)
    sub.platformID = 3
    sub.platEncID = 1
    sub.format = 4
    sub.reserved = 0
    sub.length = 0
    sub.language = 0
    sub.cmap = win_map
    cmap.tables.append(sub)

    font.save(str(src))
    print(f"Wrote {src}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())