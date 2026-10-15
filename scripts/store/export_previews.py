#!/usr/bin/env python3
"""Exports complete actual recordings as three localized, silent App Store previews."""
import argparse,hashlib,json,subprocess
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
  # simctl emits variable-rate frames and omits unchanged tail frames. Wall-clock
  # markers therefore cannot safely define video cuts. Keep the complete recording,
  # normalize its timestamps, and compress longer demos to 24 seconds. Hold the
  # genuine final frame for three seconds so the last tool/state remains readable.
  content_duration=min(duration,24.0)
  factor=content_duration/duration
  target=a.destination/(clip+'.mp4')
  filters=(f'[0:v]setpts={factor:.12f}*(PTS-STARTPTS),fps=30:start_time=0,'
           'scale=886:1920:force_original_aspect_ratio=decrease,'
           'pad=886:1920:(ow-iw)/2:(oh-ih)/2:black,setsar=1,format=yuv420p,'
           'tpad=stop_mode=clone:stop=-1[v]')
  expected_duration=content_duration+3
  run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(source),'-f','lavfi','-i','anullsrc=channel_layout=stereo:sample_rate=48000','-filter_complex',filters,'-map','[v]','-map','1:a','-t',f'{expected_duration:.3f}','-c:v','libx264','-preset','fast','-profile:v','high','-level','4.0','-b:v','10M','-maxrate','12M','-bufsize','20M','-c:a','aac','-b:a','256k','-ar','48000','-ac','2','-movflags','+faststart',str(target)])
  result=probe(target);video=next(s for s in result['streams']if s['codec_type']=='video');audio=next(s for s in result['streams']if s['codec_type']=='audio')
  seconds=float(result['format']['duration']);assert 15<=seconds<=30 and (video['width'],video['height'])==(886,1920)
  assert abs(seconds-expected_duration)<0.1,(seconds,expected_duration)
  assert abs(float(video['duration'])-seconds)<=0.05,(video['duration'],seconds)
  assert abs(float(audio['duration'])-seconds)<=0.05,(audio['duration'],seconds)
  assert video['codec_name']=='h264' and video['r_frame_rate']=='30/1' and audio['channels']==2 and target.stat().st_size<500_000_000
  poster_time=6 if clip=='03-vault' else 1
  poster=a.destination/(clip+'-poster.png')
  run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',str(poster_time),'-i',str(target),'-frames:v','1',str(poster)])
  report.append({'file':target.name,'locale':a.locale,'duration':seconds,'resolution':[886,1920],'fps':30,'poster_file':poster.name,'poster_sha256':hashlib.sha256(poster.read_bytes()).hexdigest(),'poster_time':poster_time,'poster_timecode':f'00:00:{poster_time:02}:00','audio':'AAC stereo, silence','source':'Actual simulator screen recording; no generated UI','source_file':source.name,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'source_duration':duration,'source_recording':timing,'source_markers':events,'editing':{'source_start':0,'source_end':duration,'playback_speed':1/factor,'final_frame_hold_seconds':3,'description':'Complete actual recording, longer demos accelerated to 24 seconds; genuine final frame held for 3 seconds'},'status':'PASS'})
 (a.destination/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
 print('PASS',a.locale,[(x['file'],x['duration'])for x in report])
if __name__=='__main__':main()
