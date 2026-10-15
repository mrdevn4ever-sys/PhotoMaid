#!/usr/bin/env python3
"""Generate labeled review sheets. Originals remain unchanged; review status starts PENDING."""
import argparse,hashlib,json,math,subprocess,tempfile
from pathlib import Path
from PIL import Image,ImageOps,ImageDraw,ImageFont


def font(size):
    for path in ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf','/System/Library/Fonts/Supplemental/Arial.ttf']:
        if Path(path).exists():return ImageFont.truetype(path,size)
    return ImageFont.load_default()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('locale_dir',type=Path);parser.add_argument('--previews-only',action='store_true');args=parser.parse_args()
    root=args.locale_dir;out=root/'review';out.mkdir(parents=True,exist_ok=True)
    manifest=[]
    if args.previews_only and (out/'manifest.json').exists():
        manifest=[sheet for sheet in json.loads((out/'manifest.json').read_text())if sheet['kind']=='screenshots']
        for sheet in manifest:
            for item in sheet['originals']:
                assert hashlib.sha256((root/item['file']).read_bytes()).hexdigest()==item['sha256'],'Original changed after screenshot review'
    paths=[]if args.previews_only else sorted((root/'all-pages').rglob('*.png'))
    for start in range(0,len(paths),12):
        page=Image.new('RGB',(1200,3*710),'#181818');draw=ImageDraw.Draw(page);entries=[]
        for cell,path in enumerate(paths[start:start+12]):
            with Image.open(path)as original:thumbnail=ImageOps.contain(original.convert('RGB'),(290,640))
            x=(cell%4)*300+(300-thumbnail.width)//2;y=(cell//4)*710
            page.paste(thumbnail,(x,y))
            draw.text(((cell%4)*300+5,y+645),path.stem[:33],font=font(12),fill='white')
            draw.text(((cell%4)*300+5,y+666),path.parent.name,font=font(11),fill='#bbbbbb')
            entries.append({'file':str(path.relative_to(root)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        name=f'screenshots-{start//12:02}.jpg';page.save(out/name,quality=92)
        manifest.append({'sheet':name,'kind':'screenshots','originals':entries,'review':'PENDING'})
    for path in sorted((root/'previews').glob('*.mp4')):
        result=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
        duration=float(result['format']['duration']);video=next(s for s in result['streams']if s['codec_type']=='video')
        assert 15<=duration<=30 and (video['width'],video['height'])==(886,1920) and video['r_frame_rate']=='30/1'
        subprocess.run(['ffmpeg','-hide_banner','-v','error','-i',str(path),'-map','0:v','-f','null','-'],check=True)
        sheet=Image.new('RGB',(1200,2*700),'#181818');draw=ImageDraw.Draw(sheet);times=[]
        with tempfile.TemporaryDirectory()as temporary:
            for cell in range(8):
                seconds=.4+cell*(duration-.8)/7;times.append(round(seconds,3));frame=Path(temporary)/f'{cell}.png'
                subprocess.run(['ffmpeg','-hide_banner','-v','error','-y','-ss',str(seconds),'-i',str(path),'-frames:v','1',str(frame)],check=True)
                with Image.open(frame)as original:thumbnail=ImageOps.contain(original.convert('RGB'),(290,640))
                x=(cell%4)*300+(300-thumbnail.width)//2;y=(cell//4)*700;sheet.paste(thumbnail,(x,y))
                draw.text(((cell%4)*300+5,y+650),f'{path.stem} | {seconds:.1f}s',font=font(13),fill='white')
        name=path.stem+'-video.jpg';sheet.save(out/name,quality=92)
        manifest.append({'sheet':name,'kind':'video','originals':[{'file':str(path.relative_to(root)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}],'sample_times':times,'full_decode':'PASS','review':'PENDING'})
    posters=sorted((root/'previews').glob('*-poster.png'))
    if posters:
        page=Image.new('RGB',(1200,710),'#181818');draw=ImageDraw.Draw(page);entries=[]
        assert len(posters)<=3
        for cell,path in enumerate(posters):
            with Image.open(path)as original:
                assert original.size==(886,1920)
                thumbnail=ImageOps.contain(original.convert('RGB'),(290,640))
            x=cell*400+(400-thumbnail.width)//2;page.paste(thumbnail,(x,0))
            draw.text((cell*400+10,650),path.stem,font=font(14),fill='white')
            entries.append({'file':str(path.relative_to(root)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        page.save(out/'posters.jpg',quality=92)
        manifest.append({'sheet':'posters.jpg','kind':'posters','originals':entries,'review':'PENDING'})
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(root.name,len(paths),'screenshots,',len(list((root/'previews').glob('*.mp4'))),'videos,',len(manifest),'review sheets')

if __name__=='__main__':main()
