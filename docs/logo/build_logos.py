"""Genera las 3 propuestas de icono de Matrix Terminal (SVG 1024×1024, rejilla de icono macOS)."""
import random
from pathlib import Path

OUT = Path(__file__).parent
KANA = "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾜ0123456789Z:・"
GREEN, MINT, VOID = "#00FF41", "#C6F2D0", "#050806"
MONO = "'SF Mono', Menlo, 'Hiragino Sans', monospace"

# Squircle de icono macOS: 824 pt dentro de 1024 con radio ~185.
SHAPE = '<rect x="100" y="100" width="824" height="824" rx="185" ry="185"/>'

COMMON_DEFS = f"""
  <clipPath id="shape">{SHAPE}</clipPath>
  <radialGradient id="bg" cx="50%" cy="38%" r="75%">
    <stop offset="0" stop-color="#0F2214"/>
    <stop offset="0.6" stop-color="#07100A"/>
    <stop offset="1" stop-color="{VOID}"/>
  </radialGradient>
  <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.10"/>
    <stop offset="0.35" stop-color="#FFFFFF" stop-opacity="0"/>
  </linearGradient>
  <filter id="glow" x="-30%" y="-30%" width="160%" height="160%">
    <feGaussianBlur stdDeviation="14" result="b1"/>
    <feGaussianBlur in="SourceGraphic" stdDeviation="4" result="b2"/>
    <feMerge><feMergeNode in="b1"/><feMergeNode in="b2"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="soft"><feGaussianBlur stdDeviation="1.2"/></filter>
  <filter id="drop" x="-10%" y="-10%" width="120%" height="125%">
    <feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#000" flood-opacity="0.45"/>
  </filter>
"""


def rain(seed, x0, x1, y0, y1, size, alpha, step=None, heads=True):
    """Columnas de glifos (espejados, como en la película) con estela que se desvanece."""
    rnd = random.Random(seed)
    step = step or int(size * 1.05)
    parts = []
    x = x0
    while x < x1:
        length = rnd.randint(5, 14)
        head_y = rnd.randint(y0 + length * step // 2, y1 + step * 2)
        for i in range(length):
            y = head_y - i * step
            if y < y0 - step or y > y1 + step:
                continue
            fade = (1 - i / length) ** 1.6
            is_head = heads and i == 0
            color = MINT if is_head else GREEN
            op = (0.95 if is_head else alpha * fade)
            ch = rnd.choice(KANA)
            parts.append(
                f'<text x="0" y="0" transform="translate({x},{y}) scale(-1,1)" '
                f'fill="{color}" fill-opacity="{op:.3f}" font-size="{size}" '
                f'font-family="{MONO}" text-anchor="middle">{ch}</text>'
            )
        x += int(size * rnd.uniform(1.0, 1.6))
    return "\n".join(parts)


def frame(body, extra_defs=""):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>{COMMON_DEFS}{extra_defs}</defs>
<g filter="url(#drop)">
  <g clip-path="url(#shape)">
    <rect width="1024" height="1024" fill="url(#bg)"/>
    {body}
    <rect width="1024" height="1024" fill="url(#sheen)"/>
  </g>
  <rect x="100.5" y="100.5" width="823" height="823" rx="185" fill="none" stroke="{GREEN}" stroke-opacity="0.18" stroke-width="2"/>
</g>
</svg>"""


# A · «Prompt»: el ❯_ del prompt Matrix sobre lluvia tenue. Directo, se lee a 16 px.
def option_a():
    body = f"""
    <g filter="url(#soft)">{rain(7, 120, 920, 110, 930, 44, 0.22)}</g>
    <rect width="1024" height="1024" fill="{VOID}" fill-opacity="0.35"/>
    <g filter="url(#glow)" font-family="{MONO}" font-weight="700">
      <text x="318" y="620" font-size="380" fill="{GREEN}" text-anchor="middle">❯</text>
      <rect x="520" y="560" width="230" height="58" rx="6" fill="{GREEN}"/>
    </g>"""
    return frame(body)


# B · «Glifo M»: monograma M esculpido en lluvia digital; cabezas brillantes al pie de cada trazo.
def option_b():
    m_path = "M250 790 V250 H360 L512 520 L664 250 H774 V790 H668 V450 L548 662 H476 L356 450 V790 Z"
    defs = f'<clipPath id="m"><path d="{m_path}"/></clipPath>'
    body = f"""
    <g fill-opacity="0.25" filter="url(#soft)">{rain(3, 120, 920, 110, 930, 30, 0.12, heads=False)}</g>
    <path d="{m_path}" fill="{GREEN}" fill-opacity="0.06"/>
    <g clip-path="url(#m)">
      <rect width="1024" height="1024" fill="#03140A"/>
      {rain(11, 255, 775, 230, 800, 40, 0.95, step=38)}
    </g>
    <path d="{m_path}" fill="none" stroke="{GREEN}" stroke-width="5" stroke-opacity="0.85" filter="url(#glow)"/>"""
    return frame(body, defs)


# C · «Ventana»: una ventana de terminal nativa de Mac de la que cae la lluvia; prompt con cursor abajo.
def option_c():
    win = '<rect x="196" y="236" width="632" height="552" rx="44"/>'
    defs = f'<clipPath id="win">{win}</clipPath>'
    lights = "".join(
        f'<circle cx="{252 + i * 44}" cy="290" r="13" fill="{GREEN}" fill-opacity="{op}"/>'
        for i, op in enumerate((0.9, 0.55, 0.3))
    )
    body = f"""
    <g fill-opacity="0.5" filter="url(#soft)">{rain(5, 110, 930, 110, 930, 34, 0.10, heads=False)}</g>
    <g filter="url(#drop)">
      <rect x="196" y="236" width="632" height="552" rx="44" fill="#0A0F0B"/>
    </g>
    <g clip-path="url(#win)">
      <rect x="196" y="236" width="632" height="108" fill="#101A12"/>
      {rain(19, 230, 800, 360, 690, 38, 0.85)}
      <rect x="196" y="640" width="632" height="148" fill="#0A0F0B" fill-opacity="0.92"/>
    </g>
    {lights}
    <rect x="196.5" y="236.5" width="631" height="551" rx="44" fill="none" stroke="{GREEN}" stroke-opacity="0.35" stroke-width="3"/>
    <g filter="url(#glow)" font-family="{MONO}" font-weight="700">
      <text x="248" y="738" font-size="76" fill="{GREEN}">❯</text>
      <rect x="320" y="682" width="40" height="66" rx="4" fill="{MINT}"/>
    </g>"""
    return frame(body, defs)


for name, fn in (("A-prompt", option_a), ("B-glifo-m", option_b), ("C-ventana", option_c)):
    (OUT / f"logo-{name}.svg").write_text(fn(), encoding="utf-8")
print("ok")
