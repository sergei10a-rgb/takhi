from PIL import Image, ImageDraw, ImageFilter
import numpy as np, os

INK=(28,26,22); GOLD=(201,154,60); GOLD2=(166,124,40); PAPER=(244,241,233)
os.makedirs("out", exist_ok=True)
src=Image.open("gen/takhi_v1.png").convert("RGB")
g=np.asarray(src.convert("L"))
# horse = dark pixels; threshold separates charcoal horse from gold ground
mask=(g<110).astype(np.uint8)*255
m=Image.fromarray(mask,"L").filter(ImageFilter.MedianFilter(3))  # denoise
# crop to bbox
bbox=m.getbbox()
m=m.crop(bbox)
mw,mh=m.size

def horse_layer(size, color, scale=0.80):
    canvas=Image.new("RGBA",(size,size),(0,0,0,0))
    target=int(size*scale)
    r=min(target/mw, target/mh)
    nw,nh=int(mw*r),int(mh*r)
    ml=m.resize((nw,nh),Image.LANCZOS)
    solid=Image.new("RGBA",(nw,nh),color+(255,))
    solid.putalpha(ml)
    canvas.alpha_composite(solid,((size-nw)//2,(size-nh)//2))
    return canvas

def rounded(size,color,color2=None,rad=0.225):
    base=Image.new("RGBA",(size,size),(0,0,0,0))
    if color2:
        top=np.array(color,float); bot=np.array(color2,float)
        arr=np.zeros((size,size,4),np.uint8)
        for y in range(size):
            t=y/size; c=top*(1-t)+bot*t
            arr[y,:, :3]=c.astype(np.uint8); arr[y,:,3]=255
        base=Image.fromarray(arr,"RGBA")
    else:
        base=Image.new("RGBA",(size,size),color+(255,))
    mask=Image.new("L",(size,size),0)
    d=ImageDraw.Draw(mask); d.rounded_rectangle([0,0,size-1,size-1],radius=int(size*rad),fill=255)
    base.putalpha(mask); return base

# transparent horse (ink) + (gold) for reuse
horse_layer(1024, INK, 0.94).save("out/takhi_horse_ink.png")
horse_layer(1024, GOLD,0.94).save("out/takhi_horse_gold.png")

# app icons: gold ground + ink horse
for s in (1024,512,192,96,48):
    ic=rounded(s,GOLD,GOLD2); ic.alpha_composite(horse_layer(s,INK,0.78)); ic.save(f"out/icon_gold_{s}.png")
# ink ground + gold horse variant
ink_ic=rounded(1024,INK,(38,34,28)); ink_ic.alpha_composite(horse_layer(1024,GOLD,0.78)); ink_ic.save("out/icon_ink_1024.png")
# paper ground for light contexts
p=rounded(1024,PAPER); p.alpha_composite(horse_layer(1024,INK,0.78)); p.save("out/icon_paper_1024.png")
print("mask bbox size", (mw,mh), "-> assets written to out/")
