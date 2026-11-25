"""Genera el fondo del DMG de Construct (660×420 pt, @1x y @2x) a partir de un SVG.

Uso: python3 -I scripts/dmg/build_background.py
Requiere Google Chrome (para renderizar el SVG) y `tiffutil` (incluido en macOS).
Salida: scripts/dmg/background.tiff (multirresolución, la usa dmgbuild).
"""
import random
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 660, 420
APP_X, APPS_X, ICON_Y = 180, 480, 200  # Deben coincidir con icon_locations de settings.py.
KANA = "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾜ0123456789Z:・"
GREEN, MINT, VOID = "#00FF41", "#C6F2D0", "#050806"
# Placa bajo los nombres: luminancia relativa ≈0,18, así el texto de Finder (negro en modo claro,
# blanco en modo oscuro) mantiene ≈4,6:1 en los dos casos.
PLATE = "#52805B"
MONO = "'SF Mono', Menlo, 'Hiragino Sans', monospace"


def rain(seed):
    """Columnas de glifos espejados que se apagan cerca de los iconos para no competir con ellos."""
    rnd = random.Random(seed)
    parts, x = [], 8
    while x < W:
        size = rnd.choice((11, 12, 13, 14))
        step = int(size * 1.15)
        length = rnd.randint(6, 18)
        head = rnd.randint(40, H + 80)
        near_icons = min(abs(x - APP_X), abs(x - APPS_X)) < 90
        base = 0.10 if near_icons else 0.24
        for i in range(length):
            y = head - i * step
            if not -step < y < H + step:
                continue
            fade = (1 - i / length) ** 1.5
            head_glyph = i == 0
            parts.append(
                f'<text transform="translate({x},{y}) scale(-1,1)" font-size="{size}" '
                f'fill="{MINT if head_glyph else GREEN}" fill-opacity="{(0.55 if head_glyph else base) * (1 if head_glyph else fade):.3f}" '
                f'font-family="{MONO}" text-anchor="middle">{rnd.choice(KANA)}</text>'
            )
        x += int(size * rnd.uniform(1.2, 2.2))
    return "\n".join(parts)


def plate(cx):
    return f'<rect x="{cx - 66}" y="{ICON_Y + 71}" width="132" height="26" rx="13" fill="{PLATE}" fill-opacity="0.92"/>'


def svg():
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs>
  <radialGradient id="bg" cx="50%" cy="45%" r="70%">
    <stop offset="0" stop-color="#0F2214"/><stop offset="0.65" stop-color="#07100A"/><stop offset="1" stop-color="{VOID}"/>
  </radialGradient>
  <filter id="glow" x="-20%" y="-50%" width="140%" height="200%">
    <feGaussianBlur stdDeviation="6" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <linearGradient id="scan" x1="0" y1="0" x2="0" y2="3" gradientUnits="userSpaceOnUse" spreadMethod="repeat">
    <stop offset="0" stop-color="#000" stop-opacity="0"/><stop offset="0.5" stop-color="#000" stop-opacity="0.18"/>
  </linearGradient>
</defs>
<rect width="{W}" height="{H}" fill="url(#bg)"/>
<g>{rain(42)}</g>
<rect width="{W}" height="{H}" fill="url(#scan)"/>
<g filter="url(#glow)" font-family="{MONO}" text-anchor="middle">
  <text x="{W / 2}" y="62" font-size="34" font-weight="700" fill="{GREEN}" letter-spacing="2">❯ Construct</text>
</g>
<text x="{W / 2}" y="92" font-family="-apple-system, 'SF Pro Text', sans-serif" font-size="14" fill="{MINT}" fill-opacity="0.85" text-anchor="middle">Drag Construct to Applications to install</text>
<g filter="url(#glow)" stroke="{GREEN}" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">
  <path d="M{APP_X + 84} {ICON_Y} H{APPS_X - 92}" stroke-dasharray="2 10"/>
  <path d="M{APPS_X - 104} {ICON_Y - 12} L{APPS_X - 90} {ICON_Y} L{APPS_X - 104} {ICON_Y + 12}"/>
</g>
{plate(APP_X)}
{plate(APPS_X)}
<text x="{W / 2}" y="{H - 44}" font-family="-apple-system, 'SF Pro Text', sans-serif" font-size="11" fill="{MINT}" fill-opacity="0.45" text-anchor="middle">Signed with Developer ID · Notarized by Apple</text>
</svg>"""


def render(svg_path, png_path, scale):
    subprocess.run(
        [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
         f"--force-device-scale-factor={scale}", f"--window-size={W},{H}",
         f"--screenshot={png_path}", svg_path.as_uri()],
        check=True, capture_output=True,
    )


def main():
    (HERE / "background.svg").write_text(svg(), encoding="utf-8")
    with tempfile.TemporaryDirectory() as tmp:
        one, two = Path(tmp) / "bg.png", Path(tmp) / "bg@2x.png"
        render(HERE / "background.svg", one, 1)
        render(HERE / "background.svg", two, 2)
        subprocess.run(["tiffutil", "-cathidpicheck", str(one), str(two), "-out", str(HERE / "background.tiff")],
                       check=True, capture_output=True)
        # Copia @2x para revisarlo a ojo.
        (HERE / "background-preview.png").write_bytes(two.read_bytes())
    print(HERE / "background.tiff")


if __name__ == "__main__":
    main()
