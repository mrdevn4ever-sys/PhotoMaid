#!/usr/bin/env python3
"""Decode and audit final ads; create review sheets requiring human/model sight review."""
import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]
ROOT = REPO/'marketing/de'
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1024*1024):
            h.update(chunk)
    return h.hexdigest()


def capture(args):
    return subprocess.run(args, check=True, text=True, capture_output=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ids')
    parser.add_argument('--aggregate-only', action='store_true', help='Rebuild summary/poster sheets from already audited unchanged files')
    args = parser.parse_args()
    chosen = set() if args.aggregate_only else (set(map(int, args.ids.split(','))) if args.ids else set(range(1, 21)))
    concepts = json.loads((ROOT/'concepts.json').read_text())['ads']
    records = []
    for ad in concepts:
        if ad['id'] not in chosen:
            continue
        stem = f'{ad["id"]:02}-{ad["slug"]}'
        manifest_file = ROOT/'manifests'/f'{stem}.json'
        metadata = json.loads(manifest_file.read_text())
        assert metadata['concept_sha256'] == hashlib.sha256(json.dumps(ad, ensure_ascii=False, sort_keys=True).encode()).hexdigest()
        path = ROOT/metadata['file']
        assert sha(path) == metadata['sha256']
        assert sha(ROOT/metadata['poster']) == metadata['poster_sha256']
        for source in metadata['source_assets']:
            assert sha(REPO/source['file']) == source['sha256']
        data = json.loads(capture(['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(path)]).stdout)
        video = next(s for s in data['streams'] if s['codec_type'] == 'video')
        audio = next(s for s in data['streams'] if s['codec_type'] == 'audio')
        assert (video['width'], video['height']) == (1080, 1920)
        assert video['codec_name'] == 'h264' and video['pix_fmt'] == 'yuv420p'
        assert video['r_frame_rate'] == '30/1' and video['sample_aspect_ratio'] == '1:1'
        assert int(video['nb_frames']) == 540
        assert audio['codec_name'] == 'aac' and audio['channels'] == 2 and audio['sample_rate'] == '48000'
        durations = [float(s['duration']) for s in [video, audio, data['format']]]
        assert all(abs(d-18) < .05 for d in durations), durations
        assert path.stat().st_size < 95*1024*1024
        subtitle = (ROOT/'subtitles'/f'{stem}.srt').read_text()
        assert len(re.findall(r' --> ', subtitle)) == 4 and '00:00:18,000' in subtitle
        # One complete decode verifies both tracks and measures the actual final audio.
        decoded = capture(['ffmpeg', '-hide_banner', '-nostats', '-v', 'info', '-i', str(path),
                           '-map', '0:v:0', '-map', '0:a:0', '-af', 'ebur128=peak=true', '-f', 'null', '-'])
        loudness = float(re.findall(r'I:\s+(-?[0-9.]+) LUFS', decoded.stderr)[-1])
        peak = float(re.findall(r'Peak:\s+(-?[0-9.]+) dBFS', decoded.stderr)[-1])
        assert -18.5 <= loudness <= -15.5, loudness
        assert peak <= -1.0, peak
        review_path = ROOT/'review'/f'{stem}.json'
        previous = json.loads(review_path.read_text()) if review_path.exists() else {}
        result = {'id': ad['id'], 'file': metadata['file'], 'sha256': metadata['sha256'],
                  'sheet': f'{stem}.jpg', 'sample_times': [2.4, 7.2, 12, 16.2],
                  'full_decode': 'PASS', 'duration_video_audio_container': durations,
                  'loudness_lufs': loudness, 'true_peak_dbfs': peak,
                  'technical_review': 'PASS', 'visual_review': 'PENDING'}
        if previous.get('sha256') == result['sha256'] and previous.get('visual_review') == 'PASS':
            result['visual_review'] = 'PASS'
            result['findings'] = previous['findings']
        with tempfile.TemporaryDirectory(prefix='photomaid-ad-review-') as directory:
            canvas = Image.new('RGB', (1080, 1980), (12, 16, 24))
            draw = ImageDraw.Draw(canvas)
            for n, seconds in enumerate(result['sample_times']):
                frame = Path(directory)/f'{n}.jpg'
                capture(['ffmpeg', '-hide_banner', '-v', 'error', '-y', '-ss', str(seconds), '-i', str(path),
                         '-frames:v', '1', '-vf', 'scale=540:960', '-q:v', '2', str(frame)])
                with Image.open(frame) as image:
                    canvas.paste(image, (n % 2 * 540, n // 2 * 990))
                draw.text((n % 2 * 540 + 10, n // 2 * 990 + 964), f'{stem} | {seconds:.1f}s',
                          font=ImageFont.truetype(FONT, 17), fill='white')
            canvas.save(ROOT/'review'/result['sheet'], quality=90)
        review_path.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
        metadata['technical_review'] = 'PASS'
        metadata['visual_review'] = result['visual_review']
        manifest_file.write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+'\n')
        records.append(result)
        print(f'PASS technical {stem}: {loudness} LUFS, {peak} dBTP; visual {result["visual_review"]}', flush=True)
    assert len(records) == len(chosen)
    if len(chosen) == 20 or args.aggregate_only:
        records = []
        for ad in concepts:
            stem = f'{ad["id"]:02}-{ad["slug"]}'
            record = json.loads((ROOT/'review'/f'{stem}.json').read_text())
            metadata = json.loads((ROOT/'manifests'/f'{stem}.json').read_text())
            assert metadata['concept_sha256'] == hashlib.sha256(json.dumps(ad, ensure_ascii=False, sort_keys=True).encode()).hexdigest()
            assert record['technical_review'] == 'PASS'
            assert sha(ROOT/record['file']) == record['sha256'] == metadata['sha256']
            assert sha(ROOT/metadata['poster']) == metadata['poster_sha256']
            if metadata['music'].get('master_file'):
                assert sha(ROOT/metadata['music']['master_file']) == metadata['music']['master_sha256']
            for source in metadata['source_assets']:
                assert sha(REPO/source['file']) == source['sha256']
            records.append(record)
        assert len({r['sha256'] for r in records}) == 20, 'Duplicate videos'
        (ROOT/'audit.json').write_text(json.dumps(records, ensure_ascii=False, indent=2)+'\n')
        # A separate contact sheet checks the actual poster files rather than substituted frames.
        for page in range(5):
            canvas = Image.new('RGB', (720, 1340), (12, 16, 24))
            draw = ImageDraw.Draw(canvas)
            files = []
            for n, ad in enumerate(concepts[page*4:page*4+4]):
                stem = f'{ad["id"]:02}-{ad["slug"]}'
                path = ROOT/'posters'/f'{stem}.jpg'
                with Image.open(path) as image:
                    image = image.resize((360, 640), Image.Resampling.LANCZOS)
                    canvas.paste(image, (n % 2 * 360, n // 2 * 670))
                draw.text((n % 2 * 360 + 7, n // 2 * 670 + 644), stem,
                          font=ImageFont.truetype(FONT, 13), fill='white')
                files.append({'file': str(path.relative_to(ROOT)), 'sha256': sha(path)})
            sheet = f'posters-{page+1:02}.jpg'
            canvas.save(ROOT/'review'/sheet, quality=90)
            p = ROOT/'review'/f'posters-{page+1:02}.json'
            prev = json.loads(p.read_text()) if p.exists() else {}
            result = {'sheet': sheet, 'posters': files, 'visual_review': 'PENDING'}
            if prev.get('posters') == files and prev.get('visual_review') == 'PASS':
                result.update(visual_review='PASS', findings=prev['findings'])
            p.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
        print('20 distinct ads verified. Visual review must be completed explicitly.', flush=True)


if __name__ == '__main__':
    main()
