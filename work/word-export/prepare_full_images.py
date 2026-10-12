from pathlib import Path
from PIL import Image
import json
b=Path('/Users/blackwave/Documents/Crest/work/word-export/full-images')
summary=[]
for name in ['dashboard-a','dashboard-b','dashboard-c','dashboard-d','order-a','order-b','order-c']:
    meta=json.loads((b/f'{name}-hi.json').read_text())
    src=b/f'{name}-page-hi.png'
    if not src.exists(): src=b/f'{name}-page.png'
    im=Image.open(src).convert('RGB');s=meta['pixelScale'];r=meta['phone']
    box=(round(r['x']*s),round(r['y']*s),round((r['x']+r['width'])*s),round((r['y']+r['height'])*s))
    full=im.crop(box);full.save(b/f'{name}-full.png')
    cuts=[round((c['y']-r['y']-18)*s) for c in meta['cards'][1:]]
    cut=min(cuts,key=lambda y:max(y,full.height-y))
    gap=round(full.width*.09)
    composite=Image.new('RGB',(full.width*2+gap,max(cut,full.height-cut)),(255,255,255))
    composite.paste(full.crop((0,0,full.width,cut)),(0,0))
    composite.paste(full.crop((0,cut,full.width,full.height)),(full.width+gap,0))
    composite.save(b/f'{name}-spread.png')
    summary.append({'name':name,'full':full.size,'cut':cut,'spread':composite.size,'inches_at_6_8':round(6.8*composite.height/composite.width,2)})
for name in ['dashboard-a','dashboard-b','order-b']:
    meta=json.loads((b/f'{name}-wide-hi.json').read_text());im=Image.open(b/f'{name}-wide-page-hi.png').convert('RGB');s=meta['pixelScale'];r=meta['phone']
    im.crop((round(r['x']*s),round(r['y']*s),round((r['x']+r['width'])*s),round((r['y']+r['height'])*s))).save(b/f'{name}-wide.png')
print(json.dumps(summary,ensure_ascii=False))
