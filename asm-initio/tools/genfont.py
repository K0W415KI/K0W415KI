#!/usr/bin/env python3
"""Rasteriza JetBrains Mono (OFL 1.1) a fuentes bitmap con alfa de 8 bits.

Genera, para los codepoints 32..255 (Latin-1), una celda W x H por glifo,
1 byte de alfa por pixel. El binario resultante se embebe con `incbin`,
asi el ejecutable no depende de ninguna fuente del sistema.
Solo se usa en tiempo de desarrollo; compilar no requiere Python.
"""
import sys
from PIL import Image, ImageDraw, ImageFont

TTF = "/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Regular.ttf"
TTF_BOLD = "/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Bold.ttf"

def gen(ttf, size, name, outdir):
    f = ImageFont.truetype(ttf, size)
    asc, desc = f.getmetrics()
    w = int(round(f.getlength("M")))
    h = asc + desc
    blob = bytearray()
    for cp in range(32, 256):
        ch = " " if 127 <= cp < 160 else chr(cp)
        img = Image.new("L", (w, h), 0)
        ImageDraw.Draw(img).text((0, 0), ch, font=f, fill=255)
        blob += img.tobytes()
    with open(f"{outdir}/{name}.bin", "wb") as fh:
        fh.write(blob)
    return name, w, h

if __name__ == "__main__":
    outdir = sys.argv[1] if len(sys.argv) > 1 else "src"
    fonts = [gen(TTF, 13, "font_s", outdir), gen(TTF_BOLD, 26, "font_l", outdir)]
    with open(f"{outdir}/fonts.inc", "w") as fh:
        fh.write("; generado por tools/genfont.py -- no editar\n")
        for name, w, h in fonts:
            fh.write(f"%define {name.upper()}_W {w}\n%define {name.upper()}_H {h}\n")
    for n, w, h in fonts:
        print(n, w, h)
