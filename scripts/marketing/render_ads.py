#!/usr/bin/env python3
"""Render branded German social ads from genuine, immutable PhotoMaid captures.

Requires Python + Pillow + NumPy, FFmpeg and DejaVu Sans (Debian fonts-dejavu-core).
No network calls, new app recordings, voice cloning, stock music or app changes.
"""
import argparse
import hashlib
import json
import math
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]
ROOT = REPO / 'marketing/de'
FONT_DIR = Path('/usr/share/fonts/truetype/dejavu')
WIDTH, HEIGHT, FPS = 1080, 1920, 30
SCENE, END, DURATION = 4.8, 3.6, 18.0
STYLES = {
    'blue': ((59, 159, 255), (11, 19, 34), 'Blue Focus'),
    'mint': ((96, 224, 181), (9, 26, 27), 'Fresh Mint'),
    'violet': ((176, 145, 255), (22, 15, 37), 'Soft Violet'),
    'coral': ((255, 146, 137), (34, 17, 24), 'Warm Coral'),
    'amber': ((255, 209, 119), (30, 24, 14), 'Golden Hour'),
}


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()


def concept_sha(ad):
    return hashlib.sha256(json.dumps(ad, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def font(size, bold=False):
    return ImageFont.truetype(str(FONT_DIR / ('DejaVuSans-Bold.ttf' if bold else 'DejaVuSans.ttf')), size)


def text_width(draw, text, face):
    return draw.textlength(text, font=face)


def fit_lines(draw, text, size=84, width=900, bold=True):
    lines = text.split('\n')
    while max(text_width(draw, line, font(size, bold)) for line in lines) > width:
        size -= 1
    assert size >= 60, (text, size)
    return lines, font(size, bold), size


def wrapped(draw, text, face, max_width):
    lines, line = [], ''
    for word in text.split():
        candidate = f'{line} {word}'.strip()
        if line and text_width(draw, candidate, face) > max_width:
            lines.append(line)
            line = word
        else:
            line = candidate
    if line:
        lines.append(line)
    return lines


def icon(canvas, box):
    # Faithful app-brand placement in a video layout; do not alter the asset.
    image = Image.open(REPO / 'PhotoMaid/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png').convert('RGB')
    image.thumbnail((box[2], box[2]), Image.Resampling.LANCZOS)
    mask = Image.new('L', image.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius=box[2] * .22, fill=255)
    canvas.paste(image, (box[0], box[1]), mask)


def background(style):
    accent, base, _ = STYLES[style]
    yy, xx = np.mgrid[:HEIGHT, :WIDTH]
    glow = np.exp(-(((xx - 730) / 670) ** 2 + ((yy - 1080) / 900) ** 2))
    second = np.exp(-(((xx - 80) / 600) ** 2 + ((yy - 240) / 430) ** 2))
    rgb = np.zeros((HEIGHT, WIDTH, 3), dtype=np.uint8)
    for channel in range(3):
        rgb[:, :, channel] = np.clip(base[channel] + glow * accent[channel] * .14 + second * accent[channel] * .035, 0, 255)
    canvas = Image.fromarray(rgb)
    d = ImageDraw.Draw(canvas)
    ring = tuple(int(base[n] + accent[n] * .1) for n in range(3))
    for radius in (390, 440, 490):
        d.ellipse((540-radius, 1110-radius, 540+radius, 1110+radius), outline=ring, width=2)
    d.line((90, 1675, 990, 1675), fill=ring, width=2)
    d.text((90, 1710), 'ECHTE APP-AUFNAHMEN', font=font(19, True), fill=(146, 151, 163))
    d.text((90, 1750), 'PhotoMaid  /  für iPhone', font=font(22), fill=(146, 151, 163))
    return canvas


def scene_card(ad, index, path):
    scene = ad['scenes'][index]
    accent = STYLES[ad['style']][0]
    canvas = background(ad['style'])
    icon(canvas, (90, 136, 70))
    d = ImageDraw.Draw(canvas)
    d.text((182, 148), 'PhotoMaid', font=font(40, True), fill='white')
    d.text((90, 244), scene['tag'], font=font(25, True), fill=accent)
    lines, face, size = fit_lines(d, scene['headline'])
    for n, line in enumerate(lines):
        d.text((84, 294 + n * (size + 10)), line, font=face, fill=(250, 250, 252), stroke_width=0)
    body = wrapped(d, scene['body'], font(30), 880)
    assert len(body) <= 2, body
    for n, line in enumerate(body):
        d.text((90, 488 + n * 37), line, font=font(30), fill=(195, 202, 214))
    # Phone screen is inset, proportional, with no generated app UI.
    d.rounded_rectangle((278, 568, 802, 1678), radius=49, fill=(2, 4, 8), outline=(82, 91, 109), width=3)
    d.rounded_rectangle((284, 574, 796, 1672), radius=43, outline=(24, 29, 39), width=2)
    d.text((90, 974), f'0{index+1}', font=font(84, True), fill=accent)
    d.text((95, 1070), '/ 03', font=font(26), fill=(164, 173, 188))
    for n in range(3):
        d.rounded_rectangle((90+n*50, 1140, 128+n*50, 1147), radius=3, fill=accent if n == index else (60, 65, 80))
    canvas.save(path)


def end_card(ad, path):
    accent = STYLES[ad['style']][0]
    canvas = background(ad['style'])
    icon(canvas, (430, 340, 220))
    d = ImageDraw.Draw(canvas)
    brand = font(82, True)
    d.text(((WIDTH-text_width(d, 'PhotoMaid', brand))/2, 618), 'PhotoMaid', font=brand, fill='white')
    lines, face, size = fit_lines(d, ad['endline'], size=61, width=900)
    for n, line in enumerate(lines):
        d.text(((WIDTH-text_width(d, line, face))/2, 827+n*(size+18)), line, font=face, fill='white')
    d.rounded_rectangle((144, 1116, 936, 1240), radius=62, fill=accent)
    cta, face = 'PhotoMaid entdecken', font(39, True)
    d.text(((WIDTH-text_width(d, cta, face))/2, 1151), cta, font=face, fill=(8, 18, 29))
    subtitle, face = 'für iPhone · iOS 26+', font(30)
    d.text(((WIDTH-text_width(d, subtitle, face))/2, 1290), subtitle, font=face, fill=(198, 205, 216))
    canvas.save(path)


def music(style, path):
    """Original instrumental, synthesized from oscillators and deterministic noise."""
    sample_rate = 48000
    count = round(DURATION * sample_rate)
    mix = np.zeros((count, 2), dtype=np.float64)
    number = list(STYLES).index(style)
    rng = np.random.default_rng(6400 + number)
    bpm = (116, 120, 112, 124, 108)[number]
    beat = 60 / bpm
    root = (48, 50, 45, 53, 43)[number]
    progression = ((0, 4, 7), (9, 12, 16), (5, 9, 12), (7, 11, 14))

    def add(start, data, gain=1, pan=0):
        offset = round(start * sample_rate)
        if offset >= count:
            return
        data = data[:count-offset] * gain
        mix[offset:offset+len(data), 0] += data * math.sqrt((1-pan)/2)
        mix[offset:offset+len(data), 1] += data * math.sqrt((1+pan)/2)

    def tone(note, duration, soft=False):
        t = np.arange(round(duration*sample_rate)) / sample_rate
        frequency = 440 * 2 ** ((note-69)/12)
        signal = np.sin(2*np.pi*frequency*t) + .25*np.sin(2*np.pi*frequency*2*t) + .08*np.sin(2*np.pi*frequency*3*t)
        envelope = (1-np.exp(-t/(.055 if soft else .006))) * np.exp(-t/(1.4 if soft else .20))
        envelope *= np.clip((duration-t)/.10, 0, 1)
        return signal * envelope

    bars = math.ceil(DURATION / (beat*4))
    for bar in range(bars):
        chord = progression[bar % 4]
        when = bar * beat * 4
        for n, interval in enumerate(chord):
            add(when, tone(root+interval, beat*3.9, True), .105, (n-1)*.32)
        for half in (0, 2):
            add(when+beat*half, tone(root+chord[0]-12, beat*.75), .16)
        melody = (0, 2, 1, 2, 0, 1, 2, 1)
        for step in range(8):
            interval = chord[melody[(step+number) % len(melody)]]
            add(when + beat*(step/2+.25), tone(root+24+interval, beat*.7), .045, math.sin(step)*.45)
    for step in range(math.ceil(DURATION/beat)):
        when = step*beat
        t = np.arange(round(.23*sample_rate))/sample_rate
        if step % 4 in (0, 2):
            kick = np.sin(2*np.pi*(46*t+2.9*(1-np.exp(-t*30)))) * np.exp(-t*23)
            add(when, kick, .24)
        else:
            noise = rng.normal(size=len(t))
            high = noise - np.convolve(noise, np.ones(9)/9, mode='same')
            add(when, high*np.exp(-t*55), .055, .12)
        for half in (0, .5):
            t = np.arange(round(.075*sample_rate))/sample_rate
            noise = rng.normal(size=len(t))
            high = noise - np.convolve(noise, np.ones(13)/13, mode='same')
            add(when+half*beat, high*np.exp(-t*95), .021, -.28 if half else .28)
    timeline = np.arange(count)/sample_rate
    fade = np.minimum(1, timeline/.25)*np.minimum(1, (DURATION-timeline)/.65)
    mix *= fade[:, None]
    mix = np.tanh(mix*.95)
    peak = np.abs(mix).max()
    mix *= .80 / peak
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes((mix*32767).astype('<i2').tobytes())


def subtitle(ad, path):
    def ts(seconds):
        millis = round(seconds*1000)
        return f'{millis//3600000:02}:{millis//60000%60:02}:{millis//1000%60:02},{millis%1000:03}'
    blocks = []
    for i, scene in enumerate(ad['scenes']):
        blocks.append(f'{i+1}\n{ts(i*SCENE)} --> {ts((i+1)*SCENE)}\n{scene["headline"]}\n{scene["body"]}\n')
    blocks.append(f'4\n{ts(3*SCENE)} --> {ts(DURATION)}\nPhotoMaid\n{ad["endline"]}\nPhotoMaid entdecken\n')
    path.write_text('\n'.join(blocks))


def render(ad, work):
    name = f'{ad["id"]:02}-{ad["slug"]}'
    dest = ROOT/'videos'/f'{name}.mp4'
    directory = work/name
    directory.mkdir(parents=True, exist_ok=True)
    for n in range(3):
        scene_card(ad, n, directory/f'card-{n}.png')
    end_card(ad, directory/'end.png')
    song = work/f'{ad["style"]}.wav'
    if not song.exists():
        music(ad['style'], song)
    master = ROOT/'music'/f'{ad["style"]}.flac'
    master.parent.mkdir(exist_ok=True)
    if not master.exists():
        run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(song), '-c:a', 'flac', str(master)])
    args = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-filter_complex_threads', '2']
    for n, scene in enumerate(ad['scenes']):
        args += ['-loop', '1', '-framerate', '1', '-i', str(directory/f'card-{n}.png')]
        source = scene['source']
        if source['type'] == 'recording':
            args += ['-ss', str(source['start']), '-i', str(REPO/source['file'])]
        else:
            args += ['-loop', '1', '-framerate', '1', '-i', str(REPO/source['file'])]
    args += ['-loop', '1', '-framerate', '1', '-i', str(directory/'end.png'), '-i', str(song)]
    filters = []
    for n, scene in enumerate(ad['scenes']):
        bg, source = n*2, n*2+1
        filters += [f'[{bg}:v]fps={FPS},trim=duration={SCENE},setpts=PTS-STARTPTS,format=yuv420p[b{n}]']
        if scene['source']['type'] == 'recording':
            source_filter = f'fps={FPS},scale=500:1086:force_original_aspect_ratio=decrease:flags=lanczos,pad=500:1086:(ow-iw)/2:(oh-ih)/2:black'
        else:
            source_filter = "scale=1000:2172:force_original_aspect_ratio=decrease:flags=lanczos,pad=1000:2172:(ow-iw)/2:(oh-ih)/2:black,zoompan=z='1+0.00010*on':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=144:s=500x1086:fps=30"
        filters += [f'[{source}:v]{source_filter},setsar=1,trim=duration={SCENE},setpts=PTS-STARTPTS[s{n}]']
        filters += [f'[b{n}][s{n}]overlay=290:580:shortest=1,fade=t=in:st=0:d=0.12,format=yuv420p[v{n}]']
    filters += [f'[6:v]fps={FPS},trim=duration={END},setpts=PTS-STARTPTS,fade=t=in:st=0:d=0.18,format=yuv420p[v3]']
    filters += ['[v0][v1][v2][v3]concat=n=4:v=1:a=0,setsar=1[outv]']
    filters += ['[7:a]loudnorm=I=-17:TP=-1.5:LRA=7,aresample=48000,atrim=duration=18,asetpts=PTS-STARTPTS[outa]']
    args += ['-filter_complex', ';'.join(filters), '-map', '[outv]', '-map', '[outa]', '-t', str(DURATION),
             '-c:v', 'libx264', '-threads', '3', '-preset', 'fast', '-crf', '20', '-maxrate', '6M', '-bufsize', '12M',
             '-profile:v', 'high', '-level:v', '4.1', '-pix_fmt', 'yuv420p', '-r', str(FPS),
             '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2', '-movflags', '+faststart',
             '-metadata', f'title=PhotoMaid | {ad["title"]}', '-metadata', 'language=deu', str(dest)]
    (directory/'ffmpeg-command.json').write_text(json.dumps(args, ensure_ascii=False, indent=2)+'\n')
    print(f'RENDER {name}', flush=True)
    run(args)
    (ROOT/'subtitles').mkdir(exist_ok=True)
    subtitle(ad, ROOT/'subtitles'/f'{name}.srt')
    poster = ROOT/'posters'/f'{name}.jpg'
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', '1.5', '-i', str(dest), '-frames:v', '1', '-q:v', '2', str(poster)])
    sources = [{**scene['source'], 'sha256': sha(REPO/scene['source']['file'])} for scene in ad['scenes']]
    metadata = {'id': ad['id'], 'file': f'videos/{name}.mp4', 'poster': f'posters/{name}.jpg', 'locale': 'de-DE',
                'concept_sha256': concept_sha(ad),
                'title': ad['title'], 'theme': ad['theme'], 'style': ad['style'], 'duration': DURATION,
                'sha256': sha(dest), 'poster_sha256': sha(poster), 'source_assets': sources,
                'music': {'origin': 'Original oscillator/noise synthesis; no samples or external tracks', 'style': ad['style'],
                          'render_wav_sha256': sha(song), 'master_file': str(master.relative_to(ROOT)), 'master_sha256': sha(master)},
                'voice': 'none; German text is burned into the picture',
                'editing': {'scene_seconds': SCENE, 'end_seconds': END, 'screenshot_zoom_max': 1.0143,
                            'source_policy': 'Proportional inset captures. Original app media and UI content unchanged. Marketing titles outside the app frame.'},
                'technical_review': 'PENDING', 'visual_review': 'PENDING'}
    (ROOT/'manifests').mkdir(exist_ok=True)
    (ROOT/'manifests'/f'{name}.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+'\n')
    print(f'DONE {name} {dest.stat().st_size/1024/1024:.1f} MiB', flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ids', help='Comma-separated IDs; default: all twenty')
    parser.add_argument('--work', type=Path, default=Path(tempfile.gettempdir())/'photomaid-marketing-render')
    parser.add_argument('--overwrite', action='store_true')
    args = parser.parse_args()
    concepts = json.loads((ROOT/'concepts.json').read_text())['ads']
    chosen = set(map(int, args.ids.split(','))) if args.ids else set(range(1, 21))
    assert chosen and chosen <= set(range(1, 21))
    args.work.mkdir(parents=True, exist_ok=True)
    for ad in concepts:
        if ad['id'] not in chosen:
            continue
        dest = ROOT/'videos'/f'{ad["id"]:02}-{ad["slug"]}.mp4'
        if dest.exists() and not args.overwrite:
            manifest = ROOT/'manifests'/f'{ad["id"]:02}-{ad["slug"]}.json'
            assert manifest.exists() and json.loads(manifest.read_text())['sha256'] == sha(dest), 'Incomplete output; rerun with --overwrite'
            assert json.loads(manifest.read_text()).get('concept_sha256') == concept_sha(ad), 'Concept changed; rerun with --overwrite'
            print('SKIP existing', dest.name, flush=True)
            continue
        render(ad, args.work)


if __name__ == '__main__':
    main()
