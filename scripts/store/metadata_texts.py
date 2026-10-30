#!/usr/bin/env python3
"""App-Store-Texte für GaleriQ (16 Sprachen) im fastlane-deliver-Format schreiben und Längen prüfen.

Quelle der Wahrheit für Name, Untertitel, Keywords, Werbetext und Beschreibung je App-Store-Sprache.
Begriffe wie in der App (Localizable.xcstrings): Tresor, Papierkorb, Später, Paare, Foto-Snake, Foto Blocks,
„Zuletzt gelöscht“. Keine Preise, keine fremden App-Namen, keine Versprechen, die die App nicht hält.

    python3 scripts/store/metadata_texts.py            # schreibt app-store/metadata/<locale>/*.txt
    python3 scripts/store/metadata_texts.py --check    # prüft nur
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "app-store" / "metadata"
PRIVACY_URL = "https://mrdevn4ever-sys.github.io/galeriq/"
SUPPORT_URL = "https://mrdevn4ever-sys.github.io/galeriq/"
MARKETING_URL = "https://mrdevn4ever-sys.github.io/"
COPYRIGHT = "2026 Michael Spiess"

T = {}

T["en-US"] = dict(
    name="GaleriQ: Photo Cleaner & Vault",
    subtitle="Swipe to clean up your gallery",
    keywords="storage,space,duplicates,delete,organize,album,camera roll,private,hide,collage,editor,compress",
    promo="Swipe up to keep, left to the trash, right for later. Nothing is deleted until you confirm – and your photos never leave your iPhone.",
    description="""GaleriQ makes cleaning up your photo library as easy as a swipe.

SWIPE THROUGH YOUR PHOTOS AND VIDEOS
• Up: keep
• Left: into GaleriQ's own trash – nothing is deleted yet
• Right: later – it comes back in 2 days
• Down: back to the previous item
Items are only deleted when you empty the trash and confirm the iOS dialog. They then go to "Recently Deleted" in the Photos app.

FIND WHAT TAKES UP SPACE
• Large files and videos, sorted by size
• Exact duplicates, photo series and screenshots
• Go through your library month by month
• On-device analysis suggests blurry and similar photos and photos with text – the decision is always yours

PRIVATE VAULT
Keep private photos, videos, files and notes behind a PIN or password, with optional Face ID. The content is encrypted on your iPhone.

STUDIO
Photo and video editor (saves a copy by default), collage, movie from your clips, resize and convert, remove location, GIF, PDF from photos and document scanner.

GAMES WITH YOUR PHOTOS
Take a break with Pairs, Photo Snake and Foto Blocks – played with your own pictures.

PRIVACY FIRST
No account, no server of our own, no upload. Your photos stay on your device.

FREE AND PRO
All tools are free. The free version shows ads from Google and lets you delete up to 100 items a day, plus 100 more once a day after an optional video. GaleriQ Pro is a one-time purchase: no ads, unlimited deleting and new vault folders without videos.""",
)

T["de-DE"] = dict(
    name="GaleriQ: Fotos aufräumen",
    subtitle="Per Wisch Speicher freimachen",
    keywords="tresor,duplikate,löschen,galerie,album,bilder,video,verstecken,collage,bearbeiten,komprimieren",
    promo="Nach oben behalten, nach links in den Papierkorb, nach rechts auf später. Gelöscht wird erst nach deiner Bestätigung – und deine Fotos bleiben auf dem iPhone.",
    description="""Mit GaleriQ räumst du deine Mediathek so einfach auf wie mit einem Wisch.

FOTOS UND VIDEOS PER WISCH DURCHGEHEN
• Nach oben: behalten
• Nach links: in den GaleriQ-Papierkorb – noch wird nichts gelöscht
• Nach rechts: später – kommt in 2 Tagen wieder
• Nach unten: zurück zum vorherigen Medium
Gelöscht wird erst, wenn du den Papierkorb leerst und den iOS-Dialog bestätigst. Danach liegen die Medien in „Zuletzt gelöscht“ der Fotos-App.

FINDEN, WAS PLATZ BRAUCHT
• Große Dateien und Videos, nach Größe sortiert
• Exakte Duplikate, Fotoserien und Bildschirmfotos
• Deine Mediathek Monat für Monat durchgehen
• Die Analyse auf dem Gerät schlägt unscharfe und ähnliche Fotos sowie Fotos mit Text vor – entscheiden tust immer du

PRIVATER TRESOR
Private Fotos, Videos, Dateien und Notizen hinter PIN oder Passwort, auf Wunsch mit Face ID. Der Inhalt wird auf deinem iPhone verschlüsselt.

STUDIO
Foto- und Video-Editor (speichert standardmäßig als Kopie), Collage, Film aus deinen Clips, Größe ändern und umwandeln, Standort entfernen, GIF, PDF aus Fotos und Dokumentenscanner.

SPIELE MIT DEINEN FOTOS
Mach eine Pause mit Paare, Foto-Snake und Foto Blocks – gespielt mit deinen eigenen Bildern.

PRIVATSPHÄRE ZUERST
Kein Konto, kein eigener Server, kein Upload. Deine Fotos bleiben auf deinem Gerät.

GRATIS UND PRO
Alle Werkzeuge sind gratis. Die Gratis-Version zeigt Werbung von Google und erlaubt bis zu 100 Löschungen pro Tag, einmal täglich 100 weitere nach einem freiwilligen Video. GaleriQ Pro ist ein Einmalkauf: keine Werbung, unbegrenzt löschen und neue Tresor-Ordner ohne Videos.""",
)

T["es-ES"] = dict(
    name="GaleriQ: Limpiador de fotos",
    subtitle="Desliza y libera espacio",
    keywords="caja fuerte,duplicados,borrar,galería,álbum,almacenamiento,privado,ocultar,collage,editor,comprimir",
    promo="Arriba para conservar, a la izquierda a la papelera, a la derecha para después. Nada se borra sin tu confirmación y tus fotos nunca salen del iPhone.",
    description="""GaleriQ hace que ordenar tu fototeca sea tan fácil como deslizar el dedo.

DESLIZA POR TUS FOTOS Y VÍDEOS
• Arriba: conservar
• Izquierda: a la papelera de GaleriQ – todavía no se borra nada
• Derecha: después – vuelve en 2 días
• Abajo: volver al elemento anterior
Solo se borra cuando vacías la papelera y confirmas el diálogo de iOS. Después, los elementos pasan a «Eliminado» en la app Fotos.

ENCUENTRA LO QUE OCUPA ESPACIO
• Archivos grandes y vídeos, ordenados por tamaño
• Duplicados exactos, series de fotos y capturas de pantalla
• Recorre tu fototeca mes a mes
• El análisis en el dispositivo sugiere fotos borrosas, similares y con texto – la decisión siempre es tuya

CAJA FUERTE PRIVADA
Guarda fotos, vídeos, archivos y notas privados tras un PIN o una contraseña, con Face ID opcional. El contenido se cifra en tu iPhone.

ESTUDIO
Editor de fotos y vídeos (guarda una copia por defecto), collage, película con tus clips, cambiar tamaño y formato, quitar la ubicación, GIF, PDF a partir de fotos y escáner de documentos.

JUEGOS CON TUS FOTOS
Tómate una pausa con Parejas, Serpiente de fotos y Foto Blocks, jugados con tus propias imágenes.

PRIVACIDAD ANTE TODO
Sin cuenta, sin servidor propio y sin subidas. Tus fotos se quedan en tu dispositivo.

GRATIS Y PRO
Todas las herramientas son gratuitas. La versión gratuita muestra anuncios de Google y permite borrar hasta 100 elementos al día, y 100 más una vez al día tras un vídeo opcional. GaleriQ Pro es una compra única: sin anuncios, borrado ilimitado y nuevas carpetas en la caja fuerte sin vídeos.""",
)

T["fr-FR"] = dict(
    name="GaleriQ : Nettoyer vos photos",
    subtitle="Un geste pour libérer l’espace",
    keywords="coffre-fort,doublons,supprimer,galerie,album,stockage,privé,cacher,collage,éditeur,compresser,vidéos",
    promo="Vers le haut pour garder, à gauche vers la corbeille, à droite pour plus tard. Rien n’est supprimé sans votre accord et vos photos restent sur l’iPhone.",
    description="""Avec GaleriQ, faire le tri dans votre photothèque devient aussi simple qu’un geste du doigt.

PARCOUREZ VOS PHOTOS ET VIDÉOS
• Vers le haut : garder
• Vers la gauche : dans la corbeille de GaleriQ – rien n’est encore supprimé
• Vers la droite : plus tard – l’élément revient dans 2 jours
• Vers le bas : revenir à l’élément précédent
La suppression n’a lieu que lorsque vous videz la corbeille et confirmez la fenêtre d’iOS. Les éléments vont ensuite dans « Suppressions récentes » de l’app Photos.

TROUVEZ CE QUI PREND DE LA PLACE
• Gros fichiers et vidéos, triés par taille
• Doublons exacts, rafales de photos et captures d’écran
• Parcourez votre photothèque mois par mois
• L’analyse sur l’appareil suggère les photos floues, similaires ou contenant du texte – la décision vous revient toujours

COFFRE-FORT PRIVÉ
Gardez photos, vidéos, fichiers et notes privés derrière un code ou un mot de passe, avec Face ID en option. Le contenu est chiffré sur votre iPhone.

STUDIO
Éditeur photo et vidéo (enregistre une copie par défaut), collage, film à partir de vos clips, redimensionner et convertir, supprimer la localisation, GIF, PDF à partir de photos et scanner de documents.

JEUX AVEC VOS PHOTOS
Faites une pause avec Paires, Serpent photo et Foto Blocks, joués avec vos propres images.

LA CONFIDENTIALITÉ D’ABORD
Pas de compte, pas de serveur à nous, aucun envoi. Vos photos restent sur votre appareil.

GRATUIT ET PRO
Tous les outils sont gratuits. La version gratuite affiche des publicités Google et permet de supprimer jusqu’à 100 éléments par jour, plus 100 autres une fois par jour après une vidéo facultative. GaleriQ Pro est un achat unique : sans publicité, suppressions illimitées et nouveaux dossiers du coffre-fort sans vidéo.""",
)

T["it"] = dict(
    name="GaleriQ: Pulizia foto e video",
    subtitle="Scorri e libera spazio",
    keywords="cassaforte,duplicati,eliminare,galleria,album,memoria,privato,nascondere,collage,editor,comprimere",
    promo="Su per conservare, a sinistra nel cestino, a destra per più tardi. Nulla viene eliminato senza la tua conferma e le foto restano sul tuo iPhone.",
    description="""Con GaleriQ riordinare la tua libreria foto è facile come scorrere con un dito.

SCORRI TRA FOTO E VIDEO
• Su: conserva
• Sinistra: nel cestino di GaleriQ – non viene ancora eliminato nulla
• Destra: più tardi – torna tra 2 giorni
• Giù: torna all’elemento precedente
Si elimina solo quando svuoti il cestino e confermi la finestra di iOS. Gli elementi passano poi in «Eliminati di recente» nell’app Foto.

TROVA CIÒ CHE OCCUPA SPAZIO
• File grandi e video, ordinati per dimensione
• Duplicati esatti, serie di foto e screenshot
• Sfoglia la libreria mese per mese
• L’analisi sul dispositivo suggerisce foto sfocate, simili e con testo – la decisione è sempre tua

CASSAFORTE PRIVATA
Proteggi foto, video, file e note privati con PIN o password e, se vuoi, con Face ID. Il contenuto viene cifrato sul tuo iPhone.

STUDIO
Editor di foto e video (salva una copia per impostazione predefinita), collage, filmato dai tuoi clip, ridimensiona e converti, rimuovi la posizione, GIF, PDF dalle foto e scanner di documenti.

GIOCHI CON LE TUE FOTO
Fai una pausa con Coppie, Snake fotografico e Foto Blocks, giocati con le tue immagini.

PRIVACY PRIMA DI TUTTO
Nessun account, nessun server nostro, nessun caricamento. Le tue foto restano sul dispositivo.

GRATIS E PRO
Tutti gli strumenti sono gratuiti. La versione gratuita mostra pubblicità di Google e consente di eliminare fino a 100 elementi al giorno, più altri 100 una volta al giorno dopo un video facoltativo. GaleriQ Pro è un acquisto unico: niente pubblicità, eliminazioni illimitate e nuove cartelle nella cassaforte senza video.""",
)

T["ja"] = dict(
    name="GaleriQ：写真整理・プライベート保管庫",
    subtitle="スワイプで容量を空ける",
    keywords="削除,重複,写真,動画,アルバム,カメラロール,非表示,プライバシー,コラージュ,編集,圧縮,スクショ,ストレージ,掃除",
    promo="上で残す、左でゴミ箱へ、右で「あとで」。確認するまで何も削除されず、写真が iPhone の外に出ることはありません。",
    description="""GaleriQ なら、写真ライブラリの整理がスワイプひとつで進みます。

写真とビデオをスワイプで整理
• 上：残す
• 左：GaleriQ のゴミ箱へ（まだ削除されません）
• 右：あとで（2日後にもう一度表示）
• 下：ひとつ前に戻る
ゴミ箱を空にして iOS の確認画面で承認したときだけ削除されます。削除した項目は「写真」アプリの「最近削除した項目」に移動します。

容量を使っているものを見つける
• 大きなファイルやビデオをサイズ順に表示
• 完全に同じ重複ファイル、連続写真、スクリーンショット
• ライブラリを月ごとに見直し
• デバイス上の分析で、ぼやけた写真・似た写真・文字を含む写真を提案（決めるのはいつもあなた）

プライベート保管庫
非公開の写真、ビデオ、ファイル、メモを PIN またはパスワードで保護。Face ID も使えます。内容は iPhone 上で暗号化されます。

スタジオ
写真・ビデオ編集（標準でコピーとして保存）、コラージュ、クリップからのムービー、サイズ変更と変換、位置情報の削除、GIF、写真から PDF、書類スキャナ。

写真で遊べるゲーム
ペア、フォトスネーク、Foto Blocks で、自分の写真を使ってひと休み。

プライバシー第一
アカウント不要、独自サーバーなし、アップロードなし。写真はデバイスの中にとどまります。

無料版と Pro
すべてのツールは無料です。無料版では Google の広告が表示され、1日に100件まで削除できます。任意の動画を見ると1日1回さらに100件追加できます。GaleriQ Pro は買い切り：広告なし、削除無制限、動画なしで新しい保管庫フォルダを作成できます。""",
)

T["ko"] = dict(
    name="GaleriQ: 사진 정리 및 개인 금고",
    subtitle="스와이프로 저장 공간 확보",
    keywords="삭제,용량,중복,동영상,앨범,갤러리,숨기기,비밀,콜라주,편집,압축,스크린샷,사진첩,클리너",
    promo="위로 밀면 보관, 왼쪽은 휴지통, 오른쪽은 나중에. 확인하기 전에는 아무것도 삭제되지 않으며 사진은 iPhone 밖으로 나가지 않습니다.",
    description="""GaleriQ와 함께라면 사진 보관함 정리가 스와이프 한 번으로 끝납니다.

사진과 비디오를 스와이프로 정리
• 위로: 보관
• 왼쪽: GaleriQ 휴지통으로 – 아직 삭제되지 않습니다
• 오른쪽: 나중에 – 2일 후 다시 표시
• 아래로: 이전 항목으로
휴지통을 비우고 iOS 확인 창에서 승인할 때만 삭제됩니다. 삭제된 항목은 사진 앱의 '최근 삭제된 항목'으로 이동합니다.

공간을 차지하는 항목 찾기
• 크기순으로 정렬된 큰 파일과 동영상
• 완전히 같은 중복 파일, 연속 사진, 스크린샷
• 월별로 보관함 살펴보기
• 기기 내 분석이 흐린 사진, 비슷한 사진, 글자가 있는 사진을 제안합니다 – 결정은 언제나 사용자의 몫입니다

개인 금고
개인 사진, 비디오, 파일, 메모를 PIN 또는 암호로 보호하고 원하면 Face ID도 사용할 수 있습니다. 내용은 iPhone에서 암호화됩니다.

스튜디오
사진·비디오 편집기(기본적으로 사본으로 저장), 콜라주, 클립으로 만드는 영상, 크기 조절 및 변환, 위치 정보 제거, GIF, 사진으로 PDF 만들기, 문서 스캐너.

내 사진으로 즐기는 게임
짝맞추기, 포토 스네이크, Foto Blocks를 내 사진으로 즐기며 잠시 쉬어 가세요.

개인정보 보호 우선
계정 없음, 자체 서버 없음, 업로드 없음. 사진은 기기에만 남습니다.

무료 및 Pro
모든 도구는 무료입니다. 무료 버전에는 Google 광고가 표시되며 하루 최대 100개까지 삭제할 수 있고, 선택형 동영상을 보면 하루 한 번 100개를 더 삭제할 수 있습니다. GaleriQ Pro는 한 번만 구매하면 됩니다: 광고 없음, 무제한 삭제, 동영상 없이 새 금고 폴더 만들기.""",
)

T["nl-NL"] = dict(
    name="GaleriQ: Foto's opruimen",
    subtitle="Swipe en maak ruimte vrij",
    keywords="kluis,duplicaten,verwijderen,galerij,album,opslag,privé,verbergen,collage,bewerken,comprimeren,video",
    promo="Omhoog om te bewaren, naar links naar de prullenbak, naar rechts voor later. Er wordt niets verwijderd zonder jouw bevestiging en je foto's blijven op je iPhone.",
    description="""Met GaleriQ ruim je je fotobibliotheek zo makkelijk op als een veeg met je vinger.

SWIPE DOOR JE FOTO'S EN VIDEO'S
• Omhoog: bewaren
• Links: naar de prullenbak van GaleriQ – er wordt nog niets verwijderd
• Rechts: later – komt over 2 dagen terug
• Omlaag: terug naar het vorige item
Er wordt pas verwijderd als je de prullenbak leegt en de iOS-melding bevestigt. Daarna staan de items in 'Recent verwijderd' in de Foto's-app.

VIND WAT RUIMTE INNEEMT
• Grote bestanden en video's, gesorteerd op grootte
• Exacte duplicaten, fotoseries en schermafbeeldingen
• Loop je bibliotheek maand voor maand door
• De analyse op het apparaat stelt onscherpe en vergelijkbare foto's en foto's met tekst voor – jij beslist altijd zelf

PRIVÉKLUIS
Bewaar privéfoto's, video's, bestanden en notities achter een pincode of wachtwoord, desgewenst met Face ID. De inhoud wordt op je iPhone versleuteld.

STUDIO
Foto- en video-editor (bewaart standaard een kopie), collage, film van je clips, formaat wijzigen en omzetten, locatie verwijderen, GIF, pdf van foto's en documentscanner.

SPELLEN MET JE FOTO'S
Neem even pauze met Paren, Foto-Snake en Foto Blocks – gespeeld met je eigen foto's.

PRIVACY VOOROP
Geen account, geen eigen server, geen upload. Je foto's blijven op je apparaat.

GRATIS EN PRO
Alle tools zijn gratis. De gratis versie toont advertenties van Google en laat je tot 100 items per dag verwijderen, plus één keer per dag 100 extra na een vrijwillige video. GaleriQ Pro is een eenmalige aankoop: geen advertenties, onbeperkt verwijderen en nieuwe kluismappen zonder video's.""",
)

T["pl"] = dict(
    name="GaleriQ: Czyszczenie zdjęć",
    subtitle="Przesuń i zwolnij miejsce",
    keywords="sejf,duplikaty,usuwanie,galeria,album,pamięć,prywatne,ukryj,kolaż,edytor,kompresja,wideo,zrzuty",
    promo="W górę – zachowaj, w lewo – do kosza, w prawo – na później. Nic nie zostanie usunięte bez Twojego potwierdzenia, a zdjęcia nie opuszczają iPhone'a.",
    description="""Z GaleriQ porządkowanie biblioteki zdjęć jest proste jak przesunięcie palcem.

PRZESUWAJ ZDJĘCIA I FILMY
• W górę: zachowaj
• W lewo: do kosza GaleriQ – nic jeszcze nie jest usuwane
• W prawo: później – wróci za 2 dni
• W dół: wróć do poprzedniego elementu
Usuwanie następuje dopiero wtedy, gdy opróżnisz kosz i potwierdzisz okno iOS. Elementy trafiają wtedy do „Ostatnio usunięte” w aplikacji Zdjęcia.

ZNAJDŹ TO, CO ZAJMUJE MIEJSCE
• Duże pliki i filmy, posortowane według rozmiaru
• Dokładne duplikaty, serie zdjęć i zrzuty ekranu
• Przeglądaj bibliotekę miesiąc po miesiącu
• Analiza na urządzeniu podpowiada rozmazane i podobne zdjęcia oraz zdjęcia z tekstem – decyzja zawsze należy do Ciebie

PRYWATNY SEJF
Chroń prywatne zdjęcia, filmy, pliki i notatki kodem PIN lub hasłem, opcjonalnie z Face ID. Zawartość jest szyfrowana na Twoim iPhonie.

STUDIO
Edytor zdjęć i filmów (domyślnie zapisuje kopię), kolaż, film z Twoich klipów, zmiana rozmiaru i formatu, usuwanie lokalizacji, GIF, PDF ze zdjęć i skaner dokumentów.

GRY Z TWOIMI ZDJĘCIAMI
Zrób sobie przerwę z grami Pary, Foto-Snake i Foto Blocks – z Twoimi własnymi zdjęciami.

PRYWATNOŚĆ PRZEDE WSZYSTKIM
Bez konta, bez własnego serwera, bez wysyłania. Twoje zdjęcia zostają na urządzeniu.

ZA DARMO I PRO
Wszystkie narzędzia są darmowe. Wersja bezpłatna wyświetla reklamy Google i pozwala usunąć do 100 elementów dziennie, a raz dziennie kolejne 100 po obejrzeniu opcjonalnego filmu. GaleriQ Pro to jednorazowy zakup: bez reklam, bez limitu usuwania i nowe foldery w sejfie bez filmów.""",
)

T["pt-PT"] = dict(
    name="GaleriQ: Limpar fotos e vídeos",
    subtitle="Deslize e liberte espaço",
    keywords="cofre,duplicados,apagar,galeria,álbum,armazenamento,privado,ocultar,colagem,editor,comprimir,arrumar",
    promo="Para cima para manter, para a esquerda para o lixo, para a direita para mais tarde. Nada é apagado sem a sua confirmação e as fotos nunca saem do iPhone.",
    description="""Com o GaleriQ, arrumar a fototeca é tão fácil como deslizar o dedo.

DESLIZE PELAS SUAS FOTOS E VÍDEOS
• Para cima: manter
• Para a esquerda: para o lixo do GaleriQ – ainda nada é apagado
• Para a direita: mais tarde – volta daqui a 2 dias
• Para baixo: voltar ao elemento anterior
Só é apagado quando esvazia o lixo e confirma a janela do iOS. Depois, os elementos passam para «Apagados recentemente» na app Fotografias.

ENCONTRE O QUE OCUPA ESPAÇO
• Ficheiros grandes e vídeos, ordenados por tamanho
• Duplicados exatos, séries de fotos e capturas de ecrã
• Percorra a fototeca mês a mês
• A análise no dispositivo sugere fotos desfocadas, semelhantes e com texto – a decisão é sempre sua

COFRE PRIVADO
Guarde fotos, vídeos, ficheiros e notas privados atrás de um PIN ou palavra-passe, com Face ID opcional. O conteúdo é encriptado no seu iPhone.

ESTÚDIO
Editor de fotos e vídeos (guarda uma cópia por predefinição), colagem, filme a partir dos seus clips, redimensionar e converter, remover a localização, GIF, PDF a partir de fotos e digitalizador de documentos.

JOGOS COM AS SUAS FOTOS
Faça uma pausa com Pares, Serpente de fotos e Foto Blocks, jogados com as suas próprias imagens.

PRIVACIDADE EM PRIMEIRO LUGAR
Sem conta, sem servidor próprio, sem envios. As suas fotos ficam no dispositivo.

GRÁTIS E PRO
Todas as ferramentas são gratuitas. A versão gratuita mostra anúncios da Google e permite apagar até 100 elementos por dia, mais 100 uma vez por dia depois de um vídeo opcional. O GaleriQ Pro é uma compra única: sem anúncios, apagar sem limites e novas pastas no cofre sem vídeos.""",
)

T["ro"] = dict(
    name="GaleriQ: Curățare poze",
    subtitle="Glisează și eliberează spațiu",
    keywords="seif,duplicate,ștergere,galerie,album,memorie,privat,ascunde,colaj,editor,comprimare,fotografii",
    promo="În sus păstrezi, la stânga în coș, la dreapta pentru mai târziu. Nimic nu se șterge fără confirmarea ta, iar pozele nu părăsesc niciodată iPhone-ul.",
    description="""Cu GaleriQ, ordinea în biblioteca de poze e la fel de simplă ca o glisare.

GLISEAZĂ PRIN POZE ȘI VIDEOCLIPURI
• În sus: păstrează
• La stânga: în coșul GaleriQ – încă nu se șterge nimic
• La dreapta: mai târziu – revine peste 2 zile
• În jos: înapoi la elementul anterior
Ștergerea are loc doar când golești coșul și confirmi dialogul iOS. Apoi elementele ajung în „Șterse recent” din aplicația Poze.

GĂSEȘTE CE OCUPĂ SPAȚIU
• Fișiere mari și videoclipuri, sortate după mărime
• Duplicate exacte, serii de poze și capturi de ecran
• Parcurge biblioteca lună de lună
• Analiza pe dispozitiv sugerează poze neclare, asemănătoare și poze cu text – decizia îți aparține mereu

SEIF PRIVAT
Păstrează poze, videoclipuri, fișiere și notițe private în spatele unui PIN sau al unei parole, opțional cu Face ID. Conținutul este criptat pe iPhone-ul tău.

STUDIO
Editor foto și video (salvează implicit o copie), colaj, film din clipurile tale, redimensionare și conversie, eliminarea locației, GIF, PDF din poze și scaner de documente.

JOCURI CU POZELE TALE
Ia o pauză cu Perechi, Șarpele foto și Foto Blocks – jucate cu propriile tale imagini.

CONFIDENȚIALITATEA ÎNAINTE DE TOATE
Fără cont, fără server propriu, fără încărcări. Pozele tale rămân pe dispozitiv.

GRATUIT ȘI PRO
Toate instrumentele sunt gratuite. Versiunea gratuită afișează reclame Google și îți permite să ștergi până la 100 de elemente pe zi, plus încă 100 o dată pe zi după un videoclip opțional. GaleriQ Pro este o achiziție unică: fără reclame, ștergere nelimitată și dosare noi în seif fără videoclipuri.""",
)

T["ru"] = dict(
    name="GaleriQ: очистка фото и сейф",
    subtitle="Свайп — и память свободна",
    keywords="удаление,дубликаты,галерея,альбом,хранилище,скрыть,приватный,коллаж,редактор,сжатие,видео,уборка",
    promo="Вверх — оставить, влево — в корзину, вправо — на потом. Ничего не удаляется без вашего подтверждения, а фото никогда не покидают iPhone.",
    description="""С GaleriQ навести порядок в медиатеке так же просто, как провести пальцем.

ЛИСТАЙТЕ ФОТО И ВИДЕО СВАЙПАМИ
• Вверх: оставить
• Влево: в корзину GaleriQ — пока ничего не удаляется
• Вправо: позже — вернётся через 2 дня
• Вниз: назад к предыдущему элементу
Удаление происходит, только когда вы очищаете корзину и подтверждаете диалог iOS. Затем элементы попадают в «Недавно удаленные» в приложении «Фото».

НАЙДИТЕ ТО, ЧТО ЗАНИМАЕТ МЕСТО
• Большие файлы и видео, отсортированные по размеру
• Точные дубликаты, серии снимков и скриншоты
• Просматривайте медиатеку месяц за месяцем
• Анализ на устройстве предлагает размытые и похожие фото, а также фото с текстом — решение всегда за вами

ЛИЧНЫЙ СЕЙФ
Храните личные фото, видео, файлы и заметки под PIN-кодом или паролем, по желанию с Face ID. Содержимое шифруется на вашем iPhone.

СТУДИЯ
Редактор фото и видео (по умолчанию сохраняет копию), коллаж, фильм из ваших клипов, изменение размера и формата, удаление геопозиции, GIF, PDF из фото и сканер документов.

ИГРЫ С ВАШИМИ ФОТО
Сделайте паузу с играми «Пары», «Фото-змейка» и Foto Blocks — на ваших собственных снимках.

КОНФИДЕНЦИАЛЬНОСТЬ ПРЕЖДЕ ВСЕГО
Без аккаунта, без собственного сервера, без загрузок. Ваши фото остаются на устройстве.

БЕСПЛАТНО И PRO
Все инструменты бесплатны. В бесплатной версии показывается реклама Google и можно удалять до 100 элементов в день, а раз в день — ещё 100 после необязательного видео. GaleriQ Pro — разовая покупка: без рекламы, удаление без ограничений и новые папки в сейфе без видео.""",
)

T["tr"] = dict(
    name="GaleriQ: Fotoğraf Temizleyici",
    subtitle="Kaydır, yer aç, kasada sakla",
    keywords="kopya,silme,galeri,albüm,depolama,gizli,gizle,kolaj,düzenleyici,sıkıştırma,video,ekran görüntüsü",
    promo="Yukarı kaydır sakla, sola çöpe at, sağa sonraya bırak. Onaylamadan hiçbir şey silinmez ve fotoğrafların iPhone'undan asla çıkmaz.",
    description="""GaleriQ ile fotoğraf arşivini düzenlemek bir kaydırma kadar kolay.

FOTOĞRAF VE VİDEOLARI KAYDIRARAK GEÇ
• Yukarı: sakla
• Sola: GaleriQ çöp kutusuna – henüz hiçbir şey silinmez
• Sağa: sonra – 2 gün sonra geri gelir
• Aşağı: önceki öğeye dön
Silme işlemi yalnızca çöp kutusunu boşaltıp iOS onay penceresini onayladığında yapılır. Öğeler ardından Fotoğraflar uygulamasındaki "Son Silinenler"e taşınır.

YER KAPLAYANLARI BUL
• Boyuta göre sıralanmış büyük dosyalar ve videolar
• Birebir aynı kopyalar, fotoğraf serileri ve ekran görüntüleri
• Arşivini ay ay gözden geçir
• Cihaz üzerindeki analiz bulanık, benzer ve yazı içeren fotoğrafları önerir – karar her zaman senindir

ÖZEL KASA
Özel fotoğraf, video, dosya ve notlarını PIN veya parolayla, istersen Face ID ile koru. İçerik iPhone'unda şifrelenir.

STÜDYO
Fotoğraf ve video düzenleyici (varsayılan olarak kopya kaydeder), kolaj, kliplerinden film, boyutlandırma ve dönüştürme, konum bilgisini kaldırma, GIF, fotoğraflardan PDF ve belge tarayıcı.

FOTOĞRAFLARINLA OYUNLAR
Çiftler, Fotoğraf yılanı ve Foto Blocks ile kendi fotoğraflarınla kısa bir mola ver.

ÖNCE GİZLİLİK
Hesap yok, kendi sunucumuz yok, yükleme yok. Fotoğrafların cihazında kalır.

ÜCRETSİZ VE PRO
Tüm araçlar ücretsizdir. Ücretsiz sürüm Google reklamları gösterir ve günde 100 öğeye kadar silmene izin verir; isteğe bağlı bir videodan sonra günde bir kez 100 öğe daha. GaleriQ Pro tek seferlik bir satın alımdır: reklam yok, sınırsız silme ve video izlemeden yeni kasa klasörleri.""",
)

T["uk"] = dict(
    name="GaleriQ: очищення фото і сейф",
    subtitle="Свайп — і пам’ять вільна",
    keywords="видалення,дублікати,галерея,альбом,сховище,приховати,приватний,колаж,редактор,стиснення,відео",
    promo="Угору — залишити, ліворуч — у кошик, праворуч — на потім. Нічого не видаляється без вашого підтвердження, а фото ніколи не залишають iPhone.",
    description="""З GaleriQ навести лад у медіатеці так само просто, як провести пальцем.

ГОРТАЙТЕ ФОТО Й ВІДЕО СВАЙПАМИ
• Угору: залишити
• Ліворуч: у кошик GaleriQ — поки нічого не видаляється
• Праворуч: пізніше — повернеться через 2 дні
• Донизу: назад до попереднього елемента
Видалення відбувається лише тоді, коли ви очищаєте кошик і підтверджуєте вікно iOS. Потім елементи потрапляють до «Нещодавно видалених» у програмі «Фото».

ЗНАЙДІТЬ ТЕ, ЩО ЗАЙМАЄ МІСЦЕ
• Великі файли й відео, впорядковані за розміром
• Точні дублікати, серії знімків і знімки екрана
• Переглядайте медіатеку місяць за місяцем
• Аналіз на пристрої пропонує розмиті й схожі фото, а також фото з текстом — рішення завжди за вами

ОСОБИСТИЙ СЕЙФ
Зберігайте особисті фото, відео, файли й нотатки під PIN-кодом або паролем, за бажання з Face ID. Вміст шифрується на вашому iPhone.

СТУДІЯ
Редактор фото й відео (за замовчуванням зберігає копію), колаж, фільм із ваших кліпів, зміна розміру й формату, видалення геопозиції, GIF, PDF із фото та сканер документів.

ІГРИ З ВАШИМИ ФОТО
Відпочиньте з іграми «Пари», «Фото-змійка» та Foto Blocks — на ваших власних знімках.

ПРИВАТНІСТЬ НАСАМПЕРЕД
Без облікового запису, без власного сервера, без вивантаження. Ваші фото залишаються на пристрої.

БЕЗКОШТОВНО І PRO
Усі інструменти безкоштовні. Безкоштовна версія показує рекламу Google і дозволяє видаляти до 100 елементів на день, а раз на день — ще 100 після необов’язкового відео. GaleriQ Pro — разова покупка: без реклами, необмежене видалення та нові папки в сейфі без відео.""",
)

T["zh-Hans"] = dict(
    name="GaleriQ：照片清理与私密保险箱",
    subtitle="滑动整理，释放空间",
    keywords="相册,删除,重复,存储,隐藏,加密,拼图,编辑,压缩,视频,截图,图库,瘦身,大文件",
    promo="上滑保留，左滑放入回收站，右滑稍后再看。未经你确认不会删除任何内容，照片也永远不会离开你的 iPhone。",
    description="""有了 GaleriQ，整理照片图库就像滑动手指一样简单。

滑动浏览照片和视频
• 上滑：保留
• 左滑：放入 GaleriQ 回收站——此时不会删除任何内容
• 右滑：稍后——2 天后再次出现
• 下滑：返回上一项
只有在你清空回收站并在 iOS 对话框中确认后才会删除。删除的项目随后会移到“照片”App 的“最近删除”中。

找出占用空间的内容
• 按大小排序的大文件和视频
• 完全相同的重复项、连拍照片和截屏
• 按月浏览你的图库
• 设备端分析会推荐模糊照片、相似照片和含文字的照片——决定权始终在你

私密保险箱
用密码或口令保护私密照片、视频、文件和备忘，也可选用面容 ID。内容在你的 iPhone 上加密。

工作室
照片和视频编辑器（默认保存为副本）、拼图、用你的片段制作影片、调整大小与格式转换、移除位置信息、GIF、照片生成 PDF 以及文档扫描。

用你的照片玩游戏
用配对、照片贪吃蛇和 Foto Blocks 放松一下——全部使用你自己的照片。

隐私优先
无需账户，没有自有服务器，不上传任何内容。你的照片始终留在设备上。

免费版与 Pro
所有工具均免费。免费版会显示 Google 广告，每天最多可删除 100 项；每天观看一次可选视频后可再删除 100 项。GaleriQ Pro 为一次性购买：无广告、无限删除，无需观看视频即可新建保险箱文件夹。""",
)

T["ar-SA"] = dict(
    name="GaleriQ: تنظيف الصور والخزنة",
    subtitle="اسحب لتحرير مساحة التخزين",
    keywords="حذف,مكررة,معرض,ألبوم,خاص,إخفاء,كولاج,محرر,ضغط,فيديو,لقطات الشاشة,ترتيب",
    promo="اسحب لأعلى للاحتفاظ، ولليسار إلى سلة المهملات، ولليمين لوقت لاحق. لا يُحذف شيء دون تأكيدك، ولا تغادر صورك جهاز iPhone أبدًا.",
    description="""مع GaleriQ يصبح ترتيب مكتبة الصور سهلًا مثل سحبة إصبع.

تصفّح الصور والفيديوهات بالسحب
• لأعلى: احتفاظ
• لليسار: إلى سلة مهملات GaleriQ – لا يُحذف شيء بعد
• لليمين: لاحقًا – يعود بعد يومين
• لأسفل: الرجوع إلى العنصر السابق
لا يتم الحذف إلا عندما تُفرغ السلة وتؤكد نافذة iOS. بعدها تنتقل العناصر إلى «المحذوفة مؤخرًا» في تطبيق الصور.

اعثر على ما يشغل المساحة
• الملفات والفيديوهات الكبيرة مرتبة حسب الحجم
• النسخ المكررة المتطابقة وسلاسل الصور ولقطات الشاشة
• تصفّح مكتبتك شهرًا بشهر
• يقترح التحليل على الجهاز الصور الضبابية والمتشابهة والصور التي تحتوي على نص – والقرار لك دائمًا

الخزنة الخاصة
احمِ صورك وفيديوهاتك وملفاتك وملاحظاتك الخاصة برمز PIN أو كلمة سر، مع Face ID اختياريًا. يُشفَّر المحتوى على جهاز iPhone.

الاستوديو
محرر للصور والفيديو (يحفظ نسخة افتراضيًا)، كولاج، فيلم من مقاطعك، تغيير الحجم والتحويل، إزالة الموقع، GIF، ملف PDF من الصور وماسح المستندات.

ألعاب بصورك
خذ استراحة مع أزواج وثعبان الصور وFoto Blocks – بصورك أنت.

الخصوصية أولًا
بلا حساب، وبلا خادم خاص بنا، وبلا رفع. تبقى صورك على جهازك.

مجاني وPro
جميع الأدوات مجانية. تعرض النسخة المجانية إعلانات من Google وتتيح حذف ما يصل إلى 100 عنصر يوميًا، و100 عنصر إضافي مرة يوميًا بعد مشاهدة فيديو اختياري. GaleriQ Pro شراء لمرة واحدة: بلا إعلانات، وحذف غير محدود، ومجلدات خزنة جديدة دون فيديوهات.""",
)

# In-App-Kauf (Nicht-verbrauchbar, Produkt-ID com.mrdevn4ever.photomaid.pro): Anzeigename ≤ 35, Beschreibung ≤ 55.
IAP_ID = "com.mrdevn4ever.photomaid.pro"
IAP = {
    "en-US": "No ads, unlimited deleting, free vault folders",
    "de-DE": "Ohne Werbung, unbegrenzt löschen, Tresor-Ordner frei",
    "es-ES": "Sin anuncios, borrado ilimitado, carpetas libres",
    "fr-FR": "Sans pub, suppressions illimitées, dossiers libres",
    "it": "Senza pubblicità, eliminazioni illimitate, cartelle",
    "ja": "広告なし・削除無制限・保管庫フォルダ自由",
    "ko": "광고 없음, 무제한 삭제, 금고 폴더 자유",
    "nl-NL": "Geen advertenties, onbeperkt verwijderen, kluismappen",
    "pl": "Bez reklam, usuwanie bez limitu, foldery w sejfie",
    "pt-PT": "Sem anúncios, apagar sem limites, pastas livres",
    "ro": "Fără reclame, ștergere nelimitată, dosare în seif",
    "ru": "Без рекламы, удаление без лимита, папки в сейфе",
    "tr": "Reklamsız, sınırsız silme, serbest kasa klasörleri",
    "uk": "Без реклами, видалення без ліміту, папки в сейфі",
    "zh-Hans": "无广告、无限删除、自由新建保险箱文件夹",
    "ar-SA": "بلا إعلانات، حذف غير محدود، مجلدات خزنة بحرية",
}

LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promo": 170, "description": 4000}
FILES = {"name": "name.txt", "subtitle": "subtitle.txt", "keywords": "keywords.txt",
         "promo": "promotional_text.txt", "description": "description.txt"}


def check() -> list[str]:
    errors = []
    if len(T) != 16:
        errors.append(f"{len(T)} Sprachen statt 16")
    for loc, t in T.items():
        for key, limit in LIMITS.items():
            value = t[key]
            if len(value) > limit:
                errors.append(f"{loc} {key}: {len(value)} > {limit}")
            if "PhotoMaid" in value or "Arrumo" in value:
                errors.append(f"{loc} {key}: alter Name")
        words = [w.strip() for w in t["keywords"].split(",")]
        if any(not w or w != w.strip() for w in words) or " ," in t["keywords"] or ", " in t["keywords"]:
            errors.append(f"{loc} keywords: Leerzeichen um Kommas")
        if len(set(words)) != len(words):
            errors.append(f"{loc} keywords: doppelt")
        title = (t["name"] + " " + t["subtitle"]).lower()
        for w in words:
            if " " not in w and w.lower() in title.replace(",", " ").replace(":", " ").split():
                errors.append(f"{loc} keywords: '{w}' steht schon in Name/Untertitel")
        if not t["name"].startswith("GaleriQ"):
            errors.append(f"{loc} name: beginnt nicht mit GaleriQ")
    if set(IAP) != set(T):
        errors.append("IAP: Sprachen passen nicht")
    for loc, text in IAP.items():
        if len(text) > 55:
            errors.append(f"IAP {loc}: {len(text)} > 55")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    errors = check()
    for loc, t in T.items():
        print(f"{loc:8} name {len(t['name']):2}  subtitle {len(t['subtitle']):2}  keywords {len(t['keywords']):3}  "
              f"promo {len(t['promo']):3}  description {len(t['description']):4}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    if args.check:
        return 0
    for loc, t in T.items():
        folder = OUT / loc
        folder.mkdir(parents=True, exist_ok=True)
        for key, filename in FILES.items():
            (folder / filename).write_text(t[key] + "\n", encoding="utf-8")
        (folder / "privacy_url.txt").write_text(PRIVACY_URL + "\n", encoding="utf-8")
        (folder / "support_url.txt").write_text(SUPPORT_URL + "\n", encoding="utf-8")
        (folder / "marketing_url.txt").write_text(MARKETING_URL + "\n", encoding="utf-8")
    (OUT / "copyright.txt").write_text(COPYRIGHT + "\n", encoding="utf-8")
    rows = [f"| {loc} | GaleriQ Pro | {text} |" for loc, text in IAP.items()]
    (OUT / "iap-pro.md").write_text(
        "# In-App-Kauf „GaleriQ Pro“\n\n"
        f"Produkt-ID `{IAP_ID}` · Typ: Nicht-verbrauchbar · Referenzname: GaleriQ Pro\n\n"
        "| Sprache | Anzeigename | Beschreibung |\n|---|---|---|\n" + "\n".join(rows) + "\n",
        encoding="utf-8")
    print(f"OK: {len(T)} Sprachen nach {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
