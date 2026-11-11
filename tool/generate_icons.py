"""Regenerate original pallet mark (requires Pillow); all outputs are opaque RGB."""
from pathlib import Path
import json
from PIL import Image, ImageDraw
root = Path(__file__).resolve().parents[1]
im = Image.new('RGB', (1024,1024), '#102c3c')
d = ImageDraw.Draw(im)
for x,y,fill in [(224,240,'#84d5bf'), (532,240,'#58b5a5'), (224,528,'#36988e'), (532,528,'#e9a04f')]:
    d.rounded_rectangle((x,y,x+268,y+242), radius=28, fill=fill)
    d.line((x+134,y+12,x+134,y+76), fill='#102c3c', width=14)
d.rounded_rectangle((196,810,828,850),radius=12,fill='#d8e5e4')
folder=root/'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((folder/'Contents.json').read_text())['images']:
    if not item.get('filename'): continue
    width=float(item['size'].split('x')[0]); scale=float(item['scale'][:-1])
    size=round(width*scale)
    im.resize((size,size),Image.Resampling.LANCZOS).save(folder/item['filename'])
for path,size in [('web/favicon.png',32),('web/icons/Icon-192.png',192),('web/icons/Icon-512.png',512),('web/icons/Icon-maskable-192.png',192),('web/icons/Icon-maskable-512.png',512)]:
    im.resize((size,size),Image.Resampling.LANCZOS).save(root/path)
