#!/usr/bin/env python3
"""Documentation-only visualization of actual Swift engine snapshots. NOT iOS screenshots.

No interactive game, app assets, personal pictures or native UI/FPS claims.
Photo fixtures already licensed CC0 in app-store/media/SOURCES.md; never copied to the app target.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/photo-blocks-20261018'
STATES = json.loads((OUT/'engine-states.json').read_text())
PHOTOS = [ROOT/'app-store/media/01-chalets-on-a-wooded-slope-unsplash.jpg',
          ROOT/'app-store/media/07-mountain-reflection-in-a-lake-unsplash.jpg']
COLORS = ['#59c2c2', '#bfa3e8', '#f0a67a', '#add07a', '#6ea8e8', '#e888a8']
SCALE = 2
def font(size, bold=False):
    return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans'+('-Bold' if bold else '')+'.ttf', size*SCALE)
def text(image, x, y, value, size=14, bold=False, fill='#f4faf9'):
    ImageDraw.Draw(image).text((x*SCALE,y*SCALE),value,font=font(size,bold),fill=fill)
def box(image, rect, fill, outline=None, radius=7, width=1):
    ImageDraw.Draw(image).rounded_rectangle(tuple(int(v*SCALE) for v in rect),radius=radius*SCALE,fill=fill,outline=outline,width=width*SCALE)
def tile(image, x, y, unit, color, ghost=False):
    rect=(x+1.5,y+1.5,x+unit-1.5,y+unit-1.5)
    box(image,rect,None if ghost else color,'#82968f' if ghost else '#dae9e4',radius=4)
    if not ghost:
        ImageDraw.Draw(image).line(((int((x+5)*SCALE),int((y+5)*SCALE)),(int((x+unit-5)*SCALE),int((y+5)*SCALE))),fill='#d1e7df',width=2)

W,H=1240,770
result=Image.new('RGB',(W*SCALE,H*SCALE),'#091016')
text(result,24,15,'FOTO BLOCKS · STATISCHE ENGINE-ANSICHT',22,True)
text(result,24,48,'Keine iOS-Screenshots · echte Swift-Zustände · CC0-Testfotos, keine App-Demobilder',14,fill='#9fbab4')
for index,state in enumerate(STATES):
    game=state['game']; x=24+index*305; top=194; unit=28; bw=game['width']*unit; bh=game['height']*unit
    text(result,x,90,'Level '+str(game['level'])+'  ·  '+str(game['revealedStrips']*10)+' %',17,True)
    text(result,x,120,'Score: '+str(game['score'])+'  ·  Reihen: '+str(game['totalRows']),13)
    box(result,(x,152,x+bw,158),'#253e3a',radius=3)
    if game['revealedStrips']:
        box(result,(x,152,x+bw*game['revealedStrips']/10,158),'#7ae0c7',radius=3)
    board=Image.new('RGB',(bw*SCALE,bh*SCALE),'#091016')
    source=Image.open(PHOTOS[0 if game['level']==1 else 1]).convert('RGB')
    if game['phase']=='discovered':
        photo=ImageOps.contain(source,board.size,Image.Resampling.LANCZOS)
        board.paste(photo,((board.width-photo.width)//2,(board.height-photo.height)//2))
    else:
        photo=ImageOps.fit(source,board.size,Image.Resampling.LANCZOS)
        dark=Image.new('RGB',board.size,'black');photo=Image.blend(photo,dark,0.55)
        reveal=round(bh*SCALE*game['revealedStrips']/10)
        board.paste(photo.crop((0,0,board.width,reveal)),(0,0))
        draw=ImageDraw.Draw(board)
        for col in range(1,game['width']):draw.line((col*unit*SCALE,0,col*unit*SCALE,board.height),fill='#243033')
        for row in range(1,game['height']):draw.line((0,row*unit*SCALE,board.width,row*unit*SCALE),fill='#243033')
        for cell in state['ghostCells']:tile(board,cell['x']*unit,cell['y']*unit,unit,'#8db6ab',True)
        for row,cells in enumerate(game['board']):
            for col,shape in enumerate(cells):
                if shape is not None:tile(board,col*unit,row*unit,unit,COLORS[shape])
        if game.get('active'):
            for cell in state['activeCells']:tile(board,cell['x']*unit,cell['y']*unit,unit,COLORS[game['active']['shape']])
    result.paste(board,(x*SCALE,top*SCALE))
    ImageDraw.Draw(result).rectangle((x*SCALE,top*SCALE,(x+bw)*SCALE,(top+bh)*SCALE),outline='#5a716b',width=2)
    text(result,x,692,state['title'],12,True)
    text(result,x,718,'Phase: '+game['phase'],12,fill='#9fbab4')
result.save(OUT/'static-engine-review.png',optimize=True)
evidence={'kind':'static-engine-visualization-not-iOS-screenshot',
          'input_sha256':hashlib.sha256((OUT/'engine-states.json').read_bytes()).hexdigest(),
          'output_sha256':hashlib.sha256((OUT/'static-engine-review.png').read_bytes()).hexdigest(),
          'photos':[{'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'license':'CC0 1.0; app-store/media/SOURCES.md'} for p in PHOTOS]}
(OUT/'static-review-provenance.json').write_text(json.dumps(evidence,indent=2)+'\n')
print('Created documentation-only static-engine-review.png; NOT a native UI screenshot.')
