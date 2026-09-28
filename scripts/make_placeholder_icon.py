"""Erzeugt ein Platzhalter-App-Icon (1024 px, ohne Transparenz) im hellblauen PhotoMaid-Stil.
Das finale Icon ist ein Release-Blocker (Design-Abnahme)."""
from PIL import Image, ImageDraw
import sys

S = 1024
img = Image.new("RGB", (S, S))
top, bottom = (238, 245, 253), (160, 200, 245)
for y in range(S):
    t = y / (S - 1)
    c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    ImageDraw.Draw(img).line([(0, y), (S, y)], fill=c)
d = ImageDraw.Draw(img)
# Zwei gestapelte "Fotos" als abstraktes Motiv
d.rounded_rectangle([250, 300, 720, 720], radius=70, fill=(200, 222, 250), outline=(255, 255, 255), width=18)
d.rounded_rectangle([320, 250, 790, 670], radius=70, fill=(30, 111, 241), outline=(255, 255, 255), width=18)
d.polygon([(380, 600), (500, 450), (590, 560), (650, 500), (740, 600)], fill=(255, 255, 255))
d.ellipse([640, 320, 710, 390], fill=(255, 255, 255))
img.save(sys.argv[1], "PNG")
