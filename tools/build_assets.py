"""Build a simple original vector-style app icon and copy the local source PDF."""
import json
from pathlib import Path
import shutil
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
folder=ROOT/'Words800App/Assets.xcassets/AppIcon.appiconset'
folder.mkdir(parents=True,exist_ok=True)
image=Image.new('RGB',(1024,1024),'#0F6E87')
draw=ImageDraw.Draw(image)
# Open book, with a yellow bookmark: recognizable at phone icon size.
draw.rounded_rectangle((170,215,854,800),radius=60,fill='#F8FBFC')
draw.rounded_rectangle((496,215,528,800),radius=10,fill='#D4E6EA')
draw.polygon([(690,215),(774,215),(774,436),(732,401),(690,436)],fill='#F5BE59')
for y in [425,500,575]:
    draw.rounded_rectangle((242,y,435,y+24),radius=12,fill='#82AAB5')
for y in [500,575,650]:
    draw.rounded_rectangle((591,y,784,y+24),radius=12,fill='#82AAB5')
images=[]
for idiom,sizes in [('iphone',[(20,2),(20,3),(29,2),(29,3),(40,2),(40,3),(60,2),(60,3)]),
                    ('ipad',[(20,1),(20,2),(29,1),(29,2),(40,1),(40,2),(76,1),(76,2),(83.5,2)]),
                    ('ios-marketing',[(1024,1)])]:
    for size,scale in sizes:
        pixels=int(size*scale)
        filename=f'icon-{pixels}.png'
        image.resize((pixels,pixels),Image.Resampling.LANCZOS).save(folder/filename)
        images.append(dict(idiom=idiom,size=f'{size}x{size}',scale=f'{scale}x',filename=filename))
(folder/'Contents.json').write_text(json.dumps(dict(images=images,info=dict(author='xcode',version=1)),indent=2),encoding='utf-8')
source = ROOT.parent/'高频800词.pdf'
if source.exists():
    shutil.copy2(source,ROOT/'Words800App/Resources/source.pdf')
print('Icons and source PDF ready')
