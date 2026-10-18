#!/usr/bin/env python3
"""Three selected previews plus a vault alternative; Snake/Memory are shown in real time."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from export_previews import probe, run


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('source', type=Path)
    p.add_argument('destination', type=Path)
    p.add_argument('--locale', required=True)
    a = p.parse_args()
    previews = a.destination / 'previews'
    alternatives = a.destination / 'alternatives'
    previews.mkdir(exist_ok=True)
    alternatives.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as temporary:
        intermediate = Path(temporary)
        subprocess.run(['python3', 'scripts/store/export_previews.py', str(a.source), str(intermediate), '--locale', a.locale], check=True)
        old = json.loads((intermediate / 'manifest.json').read_text())
        selected, other = [], []
        for item, name, folder, manifest in [(old[0], '01-review', previews, selected),
                                             (old[1], '03-studio', previews, selected),
                                             (old[2], '04-vault', alternatives, other)]:
            row = dict(item)
            shutil.copyfile(intermediate / item['file'], folder / (name + '.mp4'))
            shutil.copyfile(intermediate / item['poster_file'], folder / (name + '-poster.png'))
            row.update(file=name + '.mp4', poster_file=name + '-poster.png', sha256=digest(folder / (name + '.mp4')))
            manifest.append(row)
    memory = a.source / 'recordings/04-memory.mov'
    snake = a.source / 'recordings/05-snake.mov'
    sources = []
    for path, seconds in [(memory, 8), (snake, 16)]:
        data = probe(path)
        duration = float(data['format']['duration'])
        assert duration >= seconds - 3, (path, duration, seconds)
        sources.append({'file': path.name, 'sha256': digest(path), 'duration': duration,
                        'used_seconds': seconds, 'playback_speed': 1,
                        'recording': json.loads(path.with_suffix('.recording.json').read_text())})
    target = previews / '02-photo-games.mp4'
    common = ('setpts=PTS-STARTPTS,fps=30:start_time=0,'
              'scale=886:1920:force_original_aspect_ratio=decrease,'
              'pad=886:1920:(ow-iw)/2:(oh-ih)/2:black,setsar=1,format=yuv420p,')
    # Keep padding finite. Concat does not retain a reliable output frame rate;
    # reset it before tpad so the final hold advances timestamps at 30 fps.
    filters = (f'[0:v]{common}tpad=stop_mode=clone:stop_duration=3,trim=duration=8,setpts=PTS-STARTPTS[m];'
               f'[1:v]{common}tpad=stop_mode=clone:stop_duration=3,trim=duration=16,setpts=PTS-STARTPTS[s];'
               '[m][s]concat=n=2:v=1:a=0,fps=30:start_time=0,tpad=stop_mode=clone:stop_duration=4[v]')
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(memory), '-i', str(snake),
         '-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=48000',
         '-filter_complex', filters, '-map', '[v]', '-map', '2:a', '-t', '27',
         '-c:v', 'libx264', '-preset', 'fast', '-profile:v', 'high', '-level', '4.0',
         '-b:v', '10M', '-maxrate', '12M', '-bufsize', '20M', '-c:a', 'aac', '-b:a', '256k',
         '-ar', '48000', '-ac', '2', '-movflags', '+faststart', str(target)])
    result = probe(target)
    video = next(s for s in result['streams'] if s['codec_type'] == 'video')
    audio = next(s for s in result['streams'] if s['codec_type'] == 'audio')
    duration = float(result['format']['duration'])
    assert abs(duration - 27) < 0.05 and (video['width'], video['height']) == (886, 1920)
    assert video['r_frame_rate'] == '30/1' and video['codec_name'] == 'h264'
    assert abs(float(video['duration']) - duration) <= 0.05 and abs(float(audio['duration']) - duration) <= 0.05
    poster = previews / '02-photo-games-poster.png'
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', '11', '-i', str(target), '-frames:v', '1', str(poster)])
    selected.append({'file': target.name, 'locale': a.locale, 'duration': duration, 'resolution': [886, 1920],
                     'fps': 30, 'sha256': digest(target), 'poster_file': poster.name, 'poster_sha256': digest(poster),
                     'poster_time': 11, 'poster_timecode': '00:00:11:00', 'audio': 'AAC stereo, silence',
                     'source': 'Actual memory card taps and swipe-only SpriteKit gameplay on its real clock',
                     'sources': sources, 'editing': '8s Memory + 16s Snake at 1x; genuine final frame held for 3s', 'status': 'PASS'})
    (previews / 'manifest.json').write_text(json.dumps(sorted(selected, key=lambda r: r['file']), indent=2) + '\n')
    (alternatives / 'manifest.json').write_text(json.dumps(other, indent=2) + '\n')
    print('PASS:', a.locale, '3 selected previews + 1 vault alternative; games at actual speed')


if __name__ == '__main__':
    main()
