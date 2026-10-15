#!/usr/bin/env python3
"""Cuts actual screen recordings into three localized, silent App Store previews."""
import argparse,hashlib,json,subprocess,math
from pathlib import Path

def run(args):subprocess.run(args,check=True,stdout=subprocess.DEVNULL)
def probe(path):return json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
def main():
 p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('destination',type=Path);p.add_argument('--locale',required=True);a=p.parse_args()
 a.destination.mkdir(parents=True,exist_ok=True)
 markers=[json.loads(l)for l in (a.source/'markers.jsonl').read_text().splitlines()]
 report=[]
 for clip in ['01-review','02-studio','03-vault']:
  source=a.source/'recordings'/(clip+'.mov');timing=json.loads((a.source/'recordings'/(clip+'.recording.json')).read_text())
  duration=float(probe(source)['format']['duration']);events=[m for m in markers if m['clip']==clip]
  assert len(events)==5,(clip,events)
  # Recorder readiness occurs after process start; calibrate its clock using actual media duration.
  offset=timing['end']-duration
  segments=[]
  for index,event in enumerate(events):
   start=max(0,event['time']-offset)
   until_next=events[index+1]['time']-event['time'] if index+1<len(events) else duration-start
   length=min(4.8,duration-start,until_next)
   assert length>=2.5,(clip,event,length,duration)
   segments.append((start,length,event['label']))
  filters=[]
  for i,(start,length,_) in enumerate(segments):
   filters.append(f'[0:v]trim=start={start:.3f}:duration={length:.3f},setpts=PTS-STARTPTS,scale=886:1920:force_original_aspect_ratio=decrease,pad=886:1920:(ow-iw)/2:(oh-ih)/2:black,setsar=1,fps=30,format=yuv420p[v{i}]')
  filters.append(''.join(f'[v{i}]'for i in range(len(segments)))+f'concat=n={len(segments)}:v=1:a=0[v]')
  target=a.destination/(clip+'.mp4')
  run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(source),'-f','lavfi','-i','anullsrc=channel_layout=stereo:sample_rate=48000','-filter_complex',';'.join(filters),'-map','[v]','-map','1:a','-c:v','libx264','-preset','fast','-profile:v','high','-level','4.0','-b:v','10M','-maxrate','12M','-bufsize','20M','-c:a','aac','-b:a','256k','-ar','48000','-ac','2','-shortest','-movflags','+faststart',str(target)])
  result=probe(target);video=next(s for s in result['streams']if s['codec_type']=='video');audio=next(s for s in result['streams']if s['codec_type']=='audio')
  seconds=float(result['format']['duration']);assert 15<=seconds<=30 and (video['width'],video['height'])==(886,1920)
  assert video['codec_name']=='h264' and video['r_frame_rate']=='30/1' and audio['channels']==2 and target.stat().st_size<500_000_000
  poster_time=6 if clip=='03-vault' else 1
  poster=a.destination/(clip+'-poster.png')
  run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',str(poster_time),'-i',str(target),'-frames:v','1',str(poster)])
  report.append({'file':target.name,'locale':a.locale,'duration':seconds,'resolution':[886,1920],'fps':30,'poster_file':poster.name,'poster_sha256':hashlib.sha256(poster.read_bytes()).hexdigest(),'poster_time':poster_time,'poster_timecode':f'00:00:{poster_time:02}:00','audio':'AAC stereo, silence','source':'Actual simulator screen recording; no generated UI','segments':[{'start':s,'duration':d,'label':l}for s,d,l in segments],'status':'PASS'})
 (a.destination/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
 print('PASS',a.locale,[(x['file'],x['duration'])for x in report])
if __name__=='__main__':main()
