#!/usr/bin/env python3
"""Build a German review/download index and an offline video gallery."""
from pathlib import Path
import html
import json

REPO = Path(__file__).resolve().parents[2]
ROOT = REPO/'marketing/de'
ads = json.loads((ROOT/'concepts.json').read_text())['ads']
audit = json.loads((ROOT/'audit.json').read_text())
assert len(audit) == 20 and all(r['technical_review'] == r['visual_review'] == 'PASS' for r in audit)
assert all(json.loads(p.read_text())['visual_review'] == 'PASS' for p in (ROOT/'review').glob('posters-*.json'))
lines = ['# PhotoMaid – 20 deutsche Werbevideos', '',
         '**20/20 PASS** · 1080 × 1920 · 9:16 · 30 fps · je 18 Sekunden · H.264/AAC.', '',
         '[Interaktive Galerie öffnen](index.html) · [Alle Konzepte und Texte](concepts.json) · [Technischer Audit und Sichtprüfung](audit.json).', '',
         'Jede Variante hat einen eigenen Einstieg, drei Inhaltsszenen und eine Schlusskarte mit „PhotoMaid entdecken“. Fünf dunkle Farbwelten und fünf eigens synthetisierte Instrumentalbetten. Deutsche Texte sind im Bild eingeblendet; die Videos kommen ohne Sprecher aus und bleiben stumm verständlich.', '',
         'Zum Einstieg: **01** stellt das Aufräumen vor, **15** die Gratis-Werkzeuge, **20** verbindet Aufräumen, Gestalten und Tresor.', '',
         '| Nr. | Video | Schwerpunkt | Stil | Größe | Prüfung |', '|---:|---|---|---|---:|---|']
cards = []
styles = {'blue':'Blau', 'mint':'Mint', 'violet':'Violett', 'coral':'Koralle', 'amber':'Gold'}
for ad in ads:
    stem = f'{ad["id"]:02}-{ad["slug"]}'
    m = json.loads((ROOT/'manifests'/f'{stem}.json').read_text())
    assert m['technical_review'] == m['visual_review'] == 'PASS'
    size = (ROOT/m['file']).stat().st_size/1024/1024
    lines.append(f'| {ad["id"]:02} | [{ad["title"]}]({m["file"]}) | {ad["theme"]} | {styles[ad["style"]]} | {size:.1f} MiB | PASS |')
    group = 'ueberblick' if ad['id'] == 20 else ('tresor' if ad['id'] in (16,17,18) else ('studio' if ad['id'] in (*range(10,16),19) else 'aufraeumen'))
    title, theme = html.escape(ad['title']), html.escape(ad['theme'])
    cards.append(f'''<article class="card" data-group="{group}" data-id="{ad['id']}">
      <video controls playsinline preload="none" poster="{m['poster']}" aria-label="{title}"><source src="{m['file']}" type="video/mp4">Dein Browser unterstützt dieses Video nicht. Nutze den Download-Link.</video>
      <div class="details"><div class="meta"><span>{ad['id']:02} / {theme}</span><button class="save" aria-pressed="false" aria-label="{title} merken">Merken</button></div>
      <h2>{title}</h2><p>18 Sekunden · {styles[ad['style']]} · {size:.1f} MiB</p>
      <div class="downloads"><a href="{m['file']}" download>Video herunterladen</a><a href="{m['poster']}" download>Poster</a></div></div>
    </article>''')
lines += ['', '## Vorschaubilder', '']
for ad in ads:
    stem = f'{ad["id"]:02}-{ad["slug"]}'
    lines.append(f'<a href="videos/{stem}.mp4"><img src="posters/{stem}.jpg" width="180" alt="{ad["id"]:02}: {html.escape(ad["title"], quote=True)}" /></a>')
lines += ['', '## Verwendung und Quellen', '',
          '- `videos/`: die 20 fertigen Social-Videos für Reels, Shorts und Hochkant-Anzeigen.',
          '- `posters/`: je ein tatsächlich aus dem fertigen Film entnommenes Vorschaubild.',
          '- `subtitles/`: je eine optionale SRT-Datei für eine weitere Schnittbearbeitung. Die Texte stehen bereits im Video; SRT nicht zusätzlich darüberlegen.',
          '- `music/`: fünf verlustfreie FLAC-Master der eigenen Instrumentalbegleitung, ohne Fremdsamples.',
          '- `manifests/`: Herkunft, Schnittzeiten und SHA-256 je Variante.',
          '- `review/`: vier Bildstichproben je Film und gesonderte Posterprüfbögen.', '',
          'App-Szenen: die zuvor geprüften deutschen [Originalaufnahmen](https://github.com/mrdevn4ever-sys/PhotoMaid/blob/claude/fixes-analysis-library-vault-20261014/app-store/locales/de/README.md) mit dem [belegten CC0-Fotobildsatz](https://github.com/mrdevn4ever-sys/PhotoMaid/blob/claude/fixes-analysis-library-vault-20261014/app-store/media/SOURCES.md). Es werden echte native Screenshots und Ausschnitte aus den drei echten Bildschirmaufnahmen kombiniert. Statische Szenen erhalten eine sehr leichte proportionale Kamerafahrt; Texte und Grafik stehen außerhalb des App-Bildes. Medienzahlen, Analyseergebnisse und App-Oberflächen werden nicht ersetzt.', '',
          'Musik wird vollständig mit dem beigelegten Synthese-Code erzeugt. Typografie: DejaVu Sans aus den Systemschriften. Branding: vorhandenes PhotoMaid-App-Icon. Die Handlungsempfehlung lautet bewusst „entdecken“; ein öffentlicher Download oder Store-Preis wird nicht behauptet.', '',
          '## Prüfung', '',
          'Alle 20 Filme vollständig mit FFmpeg dekodiert. Jeweils 540 Frames, exakt 18 Sekunden, quadratische Pixel, 1080 × 1920, H.264/yuv420p, 30 fps, AAC-Stereo mit 48 kHz. Bild-, Ton- und Containerdauer stimmen überein. Lautheit −17,0 bis −17,1 LUFS, True Peak höchstens −4,4 dBTP; keine technische Übersteuerung.', '',
          'Alle 80 Bildstichproben (drei Inhaltsszenen und Schlusskarte je Video) und alle 20 tatsächlichen Poster angesehen. Die Filme wurden nicht jeweils in Echtzeit angesehen; die Tonprüfung war technisch, keine subjektive Hörabnahme. Die Sichtprüfung bewertet Layout, deutsche Texte und die Übereinstimmung mit der gezeigten Funktion. Sie ersetzt keine neue Geräteabnahme der App.', '',
          'Die erste Exportserie ließ das Pixel-Seitenverhältnis ungesetzt. Die Dateien erhielten ohne erneute Kodierung explizite quadratische Pixel; der Renderer setzt diese inzwischen direkt. Die Bildinhalte blieben dabei unverändert. Eine leere Ähnlichkeitsansicht wurde als Werbekonzept verworfen; Variante 08 behandelt stattdessen die frei belegbaren Gesten. Variante 07 zeigt eine tatsächliche Analyse mit Treffer, Variante 17 schließt mit sichtbaren Bedienleisten. Verworfene Fassungen sind nicht Teil der Ablage.', '',
          '## Erneut erstellen', '',
          'Linux: FFmpeg, Python 3, Pillow, NumPy und DejaVu Sans (`fonts-dejavu-core`). Vom Repository-Verzeichnis aus:', '',
          '```sh',
          'python3 scripts/marketing/render_ads.py --ids 1,20 --overwrite',
          'python3 scripts/marketing/audit_ads.py --ids 1,20',
          '# Neue Prüfbögen tatsächlich ansehen und erst dann visual_review auf PASS setzen.',
          'python3 scripts/marketing/audit_ads.py --aggregate-only',
          'python3 scripts/marketing/write_index.py',
          '```', '',
          'Ohne `--ids` werden alle 20 Varianten bearbeitet. Geänderte Konzepte verlangen `--overwrite`. Der vollständige Clip-Audit dekodiert erneut; `--aggregate-only` prüft unveränderte Prüfsummen und baut die Übersicht aus bereits geprüften Ergebnissen. Ein App-Build, Simulatorstart oder TestFlight-Upload ist für diese Exporte nicht nötig.', '']
(ROOT/'README.md').write_text('\n'.join(lines))
css = '''*{box-sizing:border-box}body{margin:0;background:#09111e;color:#f3f6fc;font-family:system-ui,-apple-system,sans-serif}main{max-width:1280px;margin:auto;padding:56px 24px}header{max-width:780px;margin-bottom:36px}.eyebrow{color:#6ab6ff;text-transform:uppercase;letter-spacing:.15em;font-size:13px;font-weight:700}h1{font-size:clamp(36px,6vw,64px);line-height:1.08;letter-spacing:-.04em;margin:16px 0}header p{color:#aebed4;font-size:18px;line-height:1.6}.filters{display:flex;gap:8px;flex-wrap:wrap;margin:28px 0 12px}button{font:inherit;cursor:pointer}.filters button{padding:10px 18px;border-radius:30px;background:#121f33;border:1px solid #293d59;color:#c4d2e5}.filters button[aria-pressed=true]{background:#4ba4fa;color:#071220;border-color:#4ba4fa}#count{color:#8fa5c2;font-size:14px;margin-bottom:24px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,290px),1fr));gap:24px;align-items:start}.card{background:#111d30;border:1px solid #24354f;border-radius:20px;overflow:hidden}.card[hidden]{display:none}.card video{display:block;width:100%;aspect-ratio:9/16;background:#000}.details{padding:20px}.meta{display:flex;justify-content:space-between;align-items:center;gap:10px;color:#91abc9;font-size:12px}.save{border:1px solid #3c5271;border-radius:20px;background:transparent;color:#b8cbe5;padding:6px 10px;font-size:12px}.save[aria-pressed=true]{background:#243f60;color:#86c7ff}h2{font-size:21px;line-height:1.3;margin:14px 0 8px}.details p{color:#94a8c4;font-size:13px}.downloads{display:flex;gap:16px;flex-wrap:wrap;margin-top:20px}a{color:#84c6ff;text-decoration:none}a:hover{text-decoration:underline}.downloads a{font-size:13px;font-weight:650}footer{padding-top:44px;color:#8197b5;font-size:13px;line-height:1.7}:focus-visible{outline:3px solid #a9d7ff;outline-offset:4px}'''
js = '''const buttons=[...document.querySelectorAll('.filters button')],cards=[...document.querySelectorAll('.card')];let selected='alle';const saved=new Set();function refresh(){let shown=0;cards.forEach(card=>{const visible=selected==='alle'||(selected==='gemerkt'?saved.has(card.dataset.id):card.dataset.group===selected);card.hidden=!visible;if(visible)shown++;else card.querySelector('video').pause();});document.querySelector('#count').textContent=shown+' von 20 Videos';document.querySelector('[data-filter="gemerkt"]').textContent='Gemerkt ('+saved.size+')';}buttons.forEach(button=>button.addEventListener('click',()=>{selected=button.dataset.filter;buttons.forEach(b=>b.setAttribute('aria-pressed',String(b===button)));refresh();}));cards.forEach(card=>card.querySelector('.save').addEventListener('click',event=>{const id=card.dataset.id;if(saved.has(id))saved.delete(id);else saved.add(id);event.target.setAttribute('aria-pressed',String(saved.has(id)));event.target.textContent=saved.has(id)?'Gemerkt':'Merken';refresh();}));document.addEventListener('play',event=>{if(event.target.tagName==='VIDEO')document.querySelectorAll('video').forEach(video=>{if(video!==event.target)video.pause();});},true);refresh();'''
filters = ''.join(f'<button data-filter="{key}" aria-pressed="{str(key=="alle").lower()}">{label}</button>' for key,label in [('alle','Alle'),('aufraeumen','Aufräumen'),('studio','Studio'),('tresor','Tresor'),('ueberblick','Überblick'),('gemerkt','Gemerkt (0)')])
page = f'''<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>PhotoMaid – 20 deutsche Werbevideos</title><style>{css}</style></head><body><main>
<header><div class="eyebrow">PhotoMaid · Werbeauswahl</div><h1>20 Ideen.<br>Eine PhotoMaid.</h1><p>Deutsche Hochkantvideos mit echten App-Szenen, klaren Texten und eigener Instrumentalmusik. Je 18 Sekunden in 1080 × 1920. Wähle deine Favoriten und lade die passenden Filme herunter.</p></header>
<nav class="filters" aria-label="Videos filtern">{filters}</nav><p id="count" aria-live="polite"></p><section class="grid" aria-label="Werbevideos">{''.join(cards)}</section>
<footer>Alle Videos und Poster technisch und visuell geprüft. <a href="README.md">Übersicht und Quellen</a> · <a href="concepts.json">Konzepte und Texte</a><br>Die Merkliste gilt für diese geöffnete Galerie. Für iPhone · iOS 26+.</footer>
</main><script>{js}</script></body></html>'''
(ROOT/'index.html').write_text(page)
print('20-video index and offline gallery written')
