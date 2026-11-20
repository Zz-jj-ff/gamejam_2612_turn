#!/usr/bin/env python3
import os, sys
from PIL import Image, ImageDraw, ImageFont
ROOT=os.path.dirname(os.path.abspath(__file__))
FR=os.path.join(ROOT,'renders','v2','frames')
OUT=os.path.join(ROOT,'renders','v2','sheets')
os.makedirs(OUT,exist_ok=True)
VIEWS=['three_q_r','front','side','back']
TW,TH=240,135
LH=22
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',13)
for clip in sorted(os.listdir(FR)):
    d=os.path.join(FR,clip)
    if not os.path.isdir(d): continue
    rows=[]
    for v in VIEWS:
        fs=sorted([f for f in os.listdir(d) if f.startswith(v+'_')])
        if not fs: continue
        rows.append((v,fs))
    if not rows: continue
    W=TW*len(rows[0][1])+6
    H=(TH+LH)*len(rows)+6
    img=Image.new('RGB',(W,H),(8,9,13)); dr=ImageDraw.Draw(img)
    for r,(v,fs) in enumerate(rows):
        y=r*(TH+LH)+4
        dr.text((6,y),v,font=font,fill=(255,160,80))
        for i,f in enumerate(fs):
            im=Image.open(os.path.join(d,f)).convert('RGB').resize((TW,TH),Image.LANCZOS)
            img.paste(im,(i*TW,y+LH))
    img.save(os.path.join(OUT,clip+'.png'))
    print(clip, img.size)
