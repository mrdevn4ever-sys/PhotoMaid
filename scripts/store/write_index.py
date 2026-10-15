#!/usr/bin/env python3
"""Write a browseable German index from actually captured assets, without claiming review."""
import argparse,json
from pathlib import Path

GROUPS={'01-introduction':'Einführung','02-today-and-review':'Heute und Feed','03-photos':'Fotos','04-cleanup':'Aufräumen','05-studio':'Studio','06-vault':'Tresor','07-settings':'Einstellungen und Pro','08-history':'Verlauf'}
THEMES={'01-review':'Aufräumen – Behalten, Papierkorb, Später und Zurück','02-studio':'Studio – Anpassen, Filter, Zeichnen und Rahmen','03-vault':'Tresor – Medien, Betrachter und Zoom'}
GAPS='Kamera/Scanner und echtes Face ID brauchen ein physisches iPhone. Videoeditor und Video-Wiedergabe sind mit dem ausschließlich aus Fotos bestehenden Bildsatz nicht aufgenommen. Wiederherstellungsschlüssel werden nicht veröffentlicht. Leere Ansichten bleiben ehrlich leer; Analyseergebnisse stammen aus dem tatsächlichen lokalen Lauf.'

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path('app-store'));args=parser.parse_args();root=args.root
 mapping=json.loads((root/'localizations.json').read_text());rows=[]
 for code,info in mapping.items():
  locale=root/'locales'/code
  if not (locale/'screenshots.json').exists():rows.append(f'| {info["name_de"]} | `{code}` → `{info["app_store_locale"]}` | ausstehend | ausstehend |');continue
  screenshots=json.loads((locale/'screenshots.json').read_text());selected=sorted((locale/'app-store-selection').glob('*.png'));videos=sorted((locale/'previews').glob('*.mp4'))
  review_path=locale/'review/manifest.json';review=json.loads(review_path.read_text())if review_path.exists()else[]
  reviewed=bool(review)and all(item['review']=='PASS'for item in review)
  provenance=json.loads((locale/'provenance.json').read_text())
  text=f'# {info["name_de"]} – PhotoMaid\n\nApp Store Connect: `{info["app_store_locale"]}` · Dark Mode · iPhone 17 Pro Max.\n\n'
  text+=f'{len(screenshots)} unveränderte native Seitenaufnahmen, {len(selected)} Bilder in der Store-Auswahl, {len(videos)} Vorschauvideos. Sichtprüfung: **{"PASS" if reviewed else "ausstehend"}**.\n\n'
  text+=f'[Aufnahmelauf {provenance["workflow_run"]}](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/{provenance["workflow_run"]}) · [Herkunft und Testergebnis](provenance.json) · [Prüfbögen](review/).\n\n'
  text+='## Vorschlag für die Store-Seite\n\nDie Originaldatei öffnet sich beim Anklicken. Apple erlaubt bis zu zehn Screenshots pro Gerätegröße und Lokalisierung.\n\n'
  for path in selected:text+=f'<a href="app-store-selection/{path.name}"><img src="app-store-selection/{path.name}" width="180" alt="{path.stem}" /></a>\n'
  text+='\n## Vorschauvideos zur Auswahl\n\n'
  for path in videos:
   text+=f'- [{THEMES.get(path.stem,path.stem)}](previews/{path.name})'
   poster=locale/'previews'/(path.stem+'-poster.png')
   if poster.exists():text+=f' · [Poster](previews/{poster.name})'
   text+='\n'
  if not videos:text+='Noch ausstehend.\n'
  text+='\n## Vollständiges Seitenarchiv\n\n'
  for group,label in GROUPS.items():
   paths=sorted((locale/'all-pages'/group).glob('*.png'))
   if not paths:continue
   text+=f'### {label}\n\n'
   text+=' · '.join(f'[{p.stem}](all-pages/{group}/{p.name})'for p in paths)+'\n\n'
  text+='## Grenzen des Bildsatzes\n\n'+GAPS+'\n'
  (locale/'README.md').write_text(text)
  rows.append(f'| [{info["name_de"]}](locales/{code}/README.md) | `{code}` → `{info["app_store_locale"]}` | {len(screenshots)} / Auswahl {len(selected)} | {len(videos)} / 3 |')
 index='# PhotoMaid – Sprachindex\n\nAlle Aufnahmen in Dark Mode. Je Sprache liegen vollständiges Seitenarchiv, eine Auswahl von zehn Originalen und drei echte App-Store-Vorschauen getrennt bereit.\n\n'
 index+='| Sprache | App → App Store Connect | Screenshots | Videos |\n|---|---|---:|---:|\n'+'\n'.join(rows)+'\n\n'
 index+='[55 Hochkantfotos und CC0-Quellen](media/SOURCES.md) · [Formate und Wiederholung](README.md) · [Maschinenprüfung](audit.json)\n\n'+GAPS+'\n'
 (root/'INDEX.md').write_text(index)
 print('Wrote index and',sum((root/'locales'/code/'README.md').exists()for code in mapping),'locale pages')

if __name__=='__main__':main()
