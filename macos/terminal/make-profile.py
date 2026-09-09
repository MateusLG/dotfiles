#!/usr/bin/env python3
"""Gera um perfil .terminal (Terminal.app) a partir de um tema do Omarchy.

Lê o colors.toml de omarchy/themes/<tema>/ e escreve <tema>.terminal, que o
macOS importa com um duplo clique. Mesmo caminho do port pro Ghostty: a
paleta vive num lugar só e os terminais derivam dela.

Uso: make-profile.py [tema] [fonte] [tamanho]
"""
import plistlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def archive(objects):
    """Empacota no formato NSKeyedArchiver que o Terminal.app espera."""
    return plistlib.dumps({
        "$version": 100000,
        "$archiver": "NSKeyedArchiver",
        "$top": {"root": plistlib.UID(1)},
        "$objects": ["$null"] + objects,
    }, fmt=plistlib.FMT_BINARY)


def color(hex_str):
    """#rrggbb -> NSColor arquivado, em espaço sRGB."""
    h = hex_str.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return archive([
        {"$class": plistlib.UID(2),
         "NSColorSpace": 2,  # 2 = sRGB
         "NSComponents": f"{r:.6f} {g:.6f} {b:.6f} 1".encode()},
        {"$classes": ["NSColor", "NSObject"], "$classname": "NSColor"},
    ])


def font(name, size):
    return archive([
        {"$class": plistlib.UID(3), "NSName": plistlib.UID(2),
         "NSSize": float(size), "NSfFlags": 16},
        name,
        {"$classes": ["NSFont", "NSObject"], "$classname": "NSFont"},
    ])


def parse_colors(path):
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r'\s*([a-z0-9_]+)\s*=\s*"(#[0-9a-fA-F]{6})"', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def main():
    theme = sys.argv[1] if len(sys.argv) > 1 else "lg-abissal"
    fontname = sys.argv[2] if len(sys.argv) > 2 else "MesloLGS-NF-Regular"
    size = sys.argv[3] if len(sys.argv) > 3 else "13"

    src = REPO / "omarchy" / "themes" / theme / "colors.toml"
    c = parse_colors(src)

    names = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
    profile = {
        "name": theme,
        "type": "Window Settings",
        "ProfileCurrentVersion": 2.0400000000000001,
        "Font": font(fontname, size),
        "FontAntialias": True,
        "BackgroundColor": color(c["background"]),
        "TextColor": color(c["foreground"]),
        "TextBoldColor": color(c["color15"]),
        "CursorColor": color(c["cursor"]),
        "SelectionColor": color(c["selection_background"]),
        "columnCount": 110,
        "rowCount": 30,
        "ShouldLimitScrollback": False,
        "ShowWindowSettingsNameInTitle": False,
        "useOptionAsMetaKey": True,   # senão os atalhos com Meta não chegam no zsh
    }
    for i, n in enumerate(names):
        profile[f"ANSI{n}Color"] = color(c[f"color{i}"])
        profile[f"ANSIBright{n}Color"] = color(c[f"color{i + 8}"])

    dest = Path(__file__).parent / f"{theme}.terminal"
    dest.write_bytes(plistlib.dumps(profile, fmt=plistlib.FMT_XML))
    print(f"gerado: {dest.relative_to(REPO)}  (fonte {fontname} {size}pt)")


if __name__ == "__main__":
    main()
