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
    description="""Too many photos, not enough storage? GaleriQ helps you tidy up your library – one relaxed swipe at a time.

IT'S THIS SIMPLE
Swipe up to keep a photo. Swipe left and it goes to GaleriQ's trash, swipe right to see it again in a few days, and swipe down to go back. Nothing is deleted until you empty the trash and confirm once more. After that, you'll still find your photos under "Recently Deleted" in the Photos app for a while.

FIND SPACE, FAST
GaleriQ shows you what's taking up the most room: big videos, duplicate photos, photo series and old screenshots. If you like, go through your library month by month, or let GaleriQ suggest blurry and similar photos for you. What goes is always your call.

YOUR PRIVATE VAULT
Keep what no one else should see in the vault: photos, videos, files and notes, protected with your own code and optional Face ID. Everything inside the vault is encrypted on your iPhone.

GET CREATIVE
In Studio you can edit photos and videos, design collages, make short movies, or turn your pictures into a PDF.

TIME FOR A BREAK?
Pairs, Photo Snake and Foto Blocks: three small games with your own photos.

NO ACCOUNT NEEDED
You don't need an account, and GaleriQ never uploads your photos anywhere.

FREE OR PRO
Every feature is free to use. The free version shows ads and lets you delete up to 100 items a day. Watch an optional video once a day to unlock 100 more. GaleriQ Pro is a one-time purchase, not a subscription: no ads, unlimited deleting, and new vault folders without watching videos.""",
)

T["de-DE"] = dict(
    name="GaleriQ: Fotos aufräumen",
    subtitle="Per Wisch Speicher freimachen",
    keywords="tresor,duplikate,löschen,galerie,album,bilder,video,verstecken,collage,bearbeiten,komprimieren",
    promo="Nach oben behalten, nach links in den Papierkorb, nach rechts auf später. Gelöscht wird erst nach deiner Bestätigung – und deine Fotos bleiben auf dem iPhone.",
    description="""Zu viele Fotos und zu wenig Speicher? Mit GaleriQ räumst du deine Mediathek entspannt auf – mit einem Wisch pro Bild.

SO EINFACH GEHT’S
Wische nach oben, um ein Foto zu behalten. Nach links landet es im GaleriQ-Papierkorb, nach rechts siehst du es in ein paar Tagen noch einmal, und nach unten geht es zurück. Gelöscht wird erst, wenn du den Papierkorb leerst und es noch einmal bestätigst. Danach findest du die Bilder noch eine Zeit lang unter „Zuletzt gelöscht“ in der Fotos-App.

PLATZ FINDEN, OHNE LANGE ZU SUCHEN
GaleriQ zeigt dir, was am meisten Speicher braucht: große Videos, doppelte Fotos, Serien und alte Bildschirmfotos. Auf Wunsch gehst du deine Fotos Monat für Monat durch oder lässt dir unscharfe und ähnliche Bilder vorschlagen. Was weg soll, entscheidest immer du.

DEIN PRIVATER TRESOR
Was niemand sehen soll, legst du in den Tresor: Fotos, Videos, Dateien und Notizen, geschützt mit deinem Code und auf Wunsch mit Face ID. Die Inhalte im Tresor werden auf deinem iPhone verschlüsselt.

KREATIV WERDEN
Im Studio bearbeitest du Fotos und Videos, gestaltest Collagen, machst kleine Filme oder ein PDF aus deinen Bildern.

ZEIT FÜR EINE PAUSE?
Paare, Foto-Snake und Foto Blocks: drei kleine Spiele mit deinen eigenen Fotos.

OHNE KONTO
Du brauchst kein Konto, und GaleriQ lädt deine Fotos nirgendwohin hoch.

GRATIS ODER PRO
Alle Funktionen kannst du kostenlos nutzen. Die Gratisversion zeigt Werbung und erlaubt bis zu 100 Löschungen pro Tag. Mit einem freiwilligen Video schaltest du einmal täglich 100 weitere frei. GaleriQ Pro ist ein einmaliger Kauf, kein Abo: keine Werbung, unbegrenzt löschen und neue Tresor-Ordner ohne Videos.""",
)

T["es-ES"] = dict(
    name="GaleriQ: Limpiador de fotos",
    subtitle="Desliza y libera espacio",
    keywords="caja fuerte,duplicados,borrar,galería,álbum,almacenamiento,privado,ocultar,collage,editor,comprimir",
    promo="Arriba para conservar, a la izquierda a la papelera, a la derecha para después. Nada se borra sin tu confirmación y tus fotos nunca salen del iPhone.",
    description="""¿Demasiadas fotos y poco espacio? Con GaleriQ ordenas tu fototeca sin complicarte, con un simple gesto por foto.

ASÍ DE FÁCIL
Desliza hacia arriba para conservar una foto. Hacia la izquierda va a la papelera de GaleriQ, hacia la derecha la vuelves a ver en unos días, y hacia abajo retrocedes. No se borra nada hasta que vacías la papelera y lo confirmas una vez más. Después, sigues encontrando tus fotos durante un tiempo en «Eliminado», dentro de la app Fotos.

ENCUENTRA ESPACIO SIN BUSCAR TANTO
GaleriQ te muestra qué ocupa más sitio: vídeos grandes, fotos repetidas, series y capturas de pantalla antiguas. Si quieres, revisa tu fototeca mes a mes, o deja que te sugiera fotos borrosas y parecidas. Lo que se queda o se va, lo decides siempre tú.

TU CAJA FUERTE PRIVADA
Lo que nadie más debe ver, lo guardas en la caja fuerte: fotos, vídeos, archivos y notas, protegidos con tu código y, si quieres, con Face ID. Todo lo que hay dentro se cifra en tu iPhone.

PARA SER CREATIVO
En Estudio editas fotos y vídeos, creas collages, haces pequeñas películas o conviertes tus fotos en un PDF.

¿UN MOMENTO DE DESCANSO?
Parejas, Serpiente de fotos y Foto Blocks: tres juegos pequeños con tus propias fotos.

SIN CUENTA
No necesitas ninguna cuenta, y GaleriQ no sube tus fotos a ningún sitio.

GRATIS O PRO
Puedes usar todas las funciones gratis. La versión gratuita muestra publicidad y te deja borrar hasta 100 elementos al día. Con un vídeo opcional, desbloqueas 100 más, una vez al día. GaleriQ Pro es una compra única, no una suscripción: sin publicidad, borrado ilimitado y nuevas carpetas en la caja fuerte sin vídeos.""",
)

T["fr-FR"] = dict(
    name="GaleriQ : Nettoyer vos photos",
    subtitle="Un geste pour libérer l’espace",
    keywords="coffre-fort,doublons,supprimer,galerie,album,stockage,privé,cacher,collage,éditeur,compresser,vidéos",
    promo="Vers le haut pour garder, à gauche vers la corbeille, à droite pour plus tard. Rien n’est supprimé sans votre accord et vos photos restent sur l’iPhone.",
    description="""Trop de photos, pas assez de place ? Avec GaleriQ, vous rangez votre photothèque tranquillement, d'un geste à la fois.

C'EST TOUT SIMPLE
Glissez vers le haut pour garder une photo. Vers la gauche, elle part dans la corbeille de GaleriQ ; vers la droite, vous la revoyez dans quelques jours ; vers le bas, vous revenez en arrière. Rien n'est supprimé avant que vous ne vidiez la corbeille et confirmiez une seconde fois. Vos photos restent ensuite un moment dans « Suppressions récentes », dans l'app Photos.

TROUVER DE LA PLACE SANS CHERCHER LONGTEMPS
GaleriQ vous montre ce qui prend le plus de place : grosses vidéos, photos en double, rafales et anciennes captures d'écran. Vous pouvez aussi parcourir votre photothèque mois par mois, ou laisser GaleriQ vous proposer des photos floues ou similaires. Ce qui part ou qui reste, c'est toujours vous qui décidez.

VOTRE COFFRE-FORT PRIVÉ
Ce que personne d'autre ne doit voir, vous le rangez dans le coffre-fort : photos, vidéos, fichiers et notes, protégés par votre code et, si vous le souhaitez, par Face ID. Tout son contenu est chiffré sur votre iPhone.

PLACE À LA CRÉATIVITÉ
Dans Studio, vous retouchez vos photos et vidéos, créez des collages, montez de petits films ou transformez vos photos en PDF.

UNE PETITE PAUSE ?
Paires, Serpent photo et Foto Blocks : trois petits jeux avec vos propres photos.

SANS COMPTE
Vous n'avez besoin d'aucun compte, et GaleriQ n'envoie jamais vos photos où que ce soit.

GRATUIT OU PRO
Toutes les fonctions sont utilisables gratuitement. La version gratuite affiche de la publicité et permet de supprimer jusqu'à 100 éléments par jour. Une vidéo facultative permet d'en débloquer 100 de plus, une fois par jour. GaleriQ Pro est un achat unique, pas un abonnement : sans publicité, suppressions illimitées et nouveaux dossiers du coffre-fort sans vidéo.""",
)

T["it"] = dict(
    name="GaleriQ: Pulizia foto e video",
    subtitle="Scorri e libera spazio",
    keywords="cassaforte,duplicati,eliminare,galleria,album,memoria,privato,nascondere,collage,editor,comprimere",
    promo="Su per conservare, a sinistra nel cestino, a destra per più tardi. Nulla viene eliminato senza la tua conferma e le foto restano sul tuo iPhone.",
    description="""Troppe foto e poco spazio? Con GaleriQ riordini la tua libreria con calma, uno swipe alla volta.

COSÌ SEMPLICE
Scorri verso l'alto per conservare una foto. A sinistra finisce nel cestino di GaleriQ, a destra la rivedi tra qualche giorno, in basso torni indietro. Non viene eliminato nulla finché non vuoti il cestino e confermi un'altra volta. Dopo, le foto restano ancora per un po' in «Eliminati di recente», nell'app Foto.

TROVA SPAZIO SENZA PERDERE TEMPO
GaleriQ ti mostra cosa occupa più spazio: video grandi, foto doppie, serie e vecchi screenshot. Se vuoi, scorri la libreria mese per mese, oppure lasciati suggerire foto sfocate o simili. Cosa tenere e cosa no, lo decidi sempre tu.

LA TUA CASSAFORTE PRIVATA
Quello che nessun altro deve vedere lo metti nella cassaforte: foto, video, file e note, protetti dal tuo codice e, se vuoi, da Face ID. Tutto il contenuto viene cifrato sul tuo iPhone.

SPAZIO ALLA CREATIVITÀ
Nello Studio modifichi foto e video, crei collage, realizzi piccoli filmati o trasformi le tue foto in un PDF.

UNA PAUSA?
Coppie, Snake fotografico e Foto Blocks: tre giochini con le tue foto.

SENZA ACCOUNT
Non ti serve nessun account, e GaleriQ non carica le tue foto da nessuna parte.

GRATIS O PRO
Puoi usare tutte le funzioni gratis. La versione gratuita mostra pubblicità e permette di eliminare fino a 100 elementi al giorno. Con un video facoltativo ne sblocchi altri 100, una volta al giorno. GaleriQ Pro è un acquisto unico, non un abbonamento: niente pubblicità, eliminazioni illimitate e nuove cartelle nella cassaforte senza video.""",
)

T["ja"] = dict(
    name="GaleriQ：写真整理・プライベート保管庫",
    subtitle="スワイプで容量を空ける",
    keywords="削除,重複,写真,動画,アルバム,カメラロール,非表示,プライバシー,コラージュ,編集,圧縮,スクショ,ストレージ,掃除",
    promo="上で残す、左でゴミ箱へ、右で「あとで」。確認するまで何も削除されず、写真が iPhone の外に出ることはありません。",
    description="""写真が多すぎて、容量が足りない？GaleriQ なら、ひとつずつスワイプするだけで、ゆったり整理できます。

とってもシンプル
上にスワイプすると写真を残せます。左へスワイプすると GaleriQ のゴミ箱へ、右へスワイプすると数日後にもう一度表示され、下へスワイプすると前に戻ります。ゴミ箱を空にしてもう一度確認するまでは、何も削除されません。そのあとも「写真」アプリの「最近削除した項目」で、しばらく見つけることができます。

探さなくても容量が見つかる
GaleriQ が、特に容量を使っているものを教えてくれます。大きな動画、重複した写真、連続写真、古いスクリーンショットなど。月ごとにライブラリを見直したり、ぼやけた写真や似ている写真を提案してもらうこともできます。残すか消すかは、いつもあなたが決めます。

あなたのプライベート保管庫
他の人に見られたくないものは、保管庫に入れておきましょう。写真、動画、ファイル、メモを、自分のコードと、使いたければ Face ID で守ります。保管庫の中身は iPhone 上で暗号化されます。

創作タイムに
スタジオでは、写真や動画を編集したり、コラージュを作ったり、短い動画を作ったり、写真を PDF にしたりできます。

少し休憩？
ペア、フォトスネーク、Foto Blocks。自分の写真で遊べる、3つの小さなゲームです。

アカウント不要
アカウントは不要です。GaleriQ が写真をどこかにアップロードすることもありません。

無料か Pro か
すべての機能は無料で使えます。無料版には広告が表示され、1日に100件まで削除できます。任意の動画を見れば、1日1回、さらに100件解放できます。GaleriQ Pro は買い切りで、サブスクリプションではありません。広告なし、削除は無制限、動画なしで保管庫に新しいフォルダを作れます。""",
)

T["ko"] = dict(
    name="GaleriQ: 사진 정리 및 개인 금고",
    subtitle="스와이프로 저장 공간 확보",
    keywords="삭제,용량,중복,동영상,앨범,갤러리,숨기기,비밀,콜라주,편집,압축,스크린샷,사진첩,클리너",
    promo="위로 밀면 보관, 왼쪽은 휴지통, 오른쪽은 나중에. 확인하기 전에는 아무것도 삭제되지 않으며 사진은 iPhone 밖으로 나가지 않습니다.",
    description="""사진은 많은데 저장 공간이 부족하신가요? GaleriQ와 함께라면 한 장씩 느긋하게 스와이프하면서 정리할 수 있어요.

이렇게 간단해요
위로 스와이프하면 사진을 보관해요. 왼쪽으로 스와이프하면 GaleriQ 휴지통으로 가고, 오른쪽으로 하면 며칠 후 다시 보여주고, 아래로 하면 이전으로 돌아가요. 휴지통을 비우고 한 번 더 확인하기 전까지는 아무것도 삭제되지 않아요. 그 후에도 사진 앱의 '최근 삭제된 항목'에서 한동안 찾을 수 있어요.

오래 찾지 않아도 공간이 보여요
GaleriQ가 가장 공간을 많이 차지하는 것들을 알려줘요: 큰 동영상, 중복된 사진, 연속 사진, 오래된 스크린샷까지. 원한다면 월별로 보관함을 살펴보거나, 흐리거나 비슷한 사진을 추천받을 수도 있어요. 남길지 지울지는 언제나 당신이 정해요.

나만의 금고
다른 사람이 보면 안 되는 것들은 금고에 넣어두세요. 사진, 동영상, 파일, 메모를 나만의 코드로, 원하면 Face ID로도 보호할 수 있어요. 금고 안의 모든 것은 iPhone에서 암호화돼요.

창작의 시간
스튜디오에서는 사진과 동영상을 편집하고, 콜라주를 만들고, 짧은 영상을 만들거나 사진을 PDF로 바꿀 수 있어요.

잠깐 쉬어갈까요?
짝맞추기, 포토 스네이크, Foto Blocks. 내 사진으로 즐기는 세 가지 작은 게임이에요.

계정이 필요 없어요
계정 없이도 사용할 수 있고, GaleriQ는 사진을 어디에도 올리지 않아요.

무료 또는 Pro
모든 기능을 무료로 사용할 수 있어요. 무료 버전에는 광고가 나오고, 하루 최대 100개까지 삭제할 수 있어요. 선택형 동영상을 보면 하루 한 번 100개를 더 풀 수 있어요. GaleriQ Pro는 구독이 아니라 한 번만 결제하면 돼요: 광고 없음, 무제한 삭제, 동영상 없이 새 금고 폴더 만들기.""",
)

T["nl-NL"] = dict(
    name="GaleriQ: Foto's opruimen",
    subtitle="Swipe en maak ruimte vrij",
    keywords="kluis,duplicaten,verwijderen,galerij,album,opslag,privé,verbergen,collage,bewerken,comprimeren,video",
    promo="Omhoog om te bewaren, naar links naar de prullenbak, naar rechts voor later. Er wordt niets verwijderd zonder jouw bevestiging en je foto's blijven op je iPhone.",
    description="""Te veel foto's en te weinig opslag? Met GaleriQ ruim je je bibliotheek lekker rustig op, met één swipe per keer.

ZO MAKKELIJK GAAT HET
Swipe omhoog om een foto te bewaren. Naar links gaat hij naar de prullenbak van GaleriQ, naar rechts zie je hem over een paar dagen opnieuw, omlaag ga je terug. Er wordt niets verwijderd tot je de prullenbak leegt en het nog een keer bevestigt. Daarna vind je je foto's nog een tijdje terug bij 'Recent verwijderd' in de Foto's-app.

RUIMTE VINDEN ZONDER LANG TE ZOEKEN
GaleriQ laat zien wat de meeste ruimte inneemt: grote video's, dubbele foto's, reeksen en oude schermafbeeldingen. Je kunt ook je bibliotheek maand voor maand doorlopen, of onscherpe en gelijkende foto's laten voorstellen. Wat weg mag, bepaal jij altijd zelf.

JOUW PRIVÉKLUIS
Wat niemand anders mag zien, bewaar je in de kluis: foto's, video's, bestanden en notities, beveiligd met je eigen code en desgewenst met Face ID. Alles in de kluis wordt versleuteld op je iPhone.

CREATIEF AAN DE SLAG
In Studio bewerk je foto's en video's, maak je collages, kleine films of een pdf van je foto's.

EVEN PAUZE?
Paren, Foto-Snake en Foto Blocks: drie kleine spelletjes met je eigen foto's.

GEEN ACCOUNT NODIG
Je hebt geen account nodig, en GaleriQ stuurt je foto's nooit ergens naar op.

GRATIS OF PRO
Je kunt alle functies gratis gebruiken. De gratis versie toont advertenties en laat je tot 100 items per dag verwijderen. Met een vrijwillige video ontgrendel je één keer per dag 100 extra. GaleriQ Pro is een eenmalige aankoop, geen abonnement: geen advertenties, onbeperkt verwijderen en nieuwe kluismappen zonder video's.""",
)

T["pl"] = dict(
    name="GaleriQ: Czyszczenie zdjęć",
    subtitle="Przesuń i zwolnij miejsce",
    keywords="sejf,duplikaty,usuwanie,galeria,album,pamięć,prywatne,ukryj,kolaż,edytor,kompresja,wideo,zrzuty",
    promo="W górę – zachowaj, w lewo – do kosza, w prawo – na później. Nic nie zostanie usunięte bez Twojego potwierdzenia, a zdjęcia nie opuszczają iPhone'a.",
    description="""Zdjęć za dużo, a miejsca za mało? Z GaleriQ porządkujesz swoją bibliotekę bez pośpiechu – jedno przesunięcie na zdjęcie.

TO PROSTE
Przesuń w górę, aby zachować zdjęcie. W lewo trafia do kosza GaleriQ, w prawo zobaczysz je znowu za kilka dni, w dół wracasz. Nic nie zostaje usunięte, dopóki nie opróżnisz kosza i nie potwierdzisz jeszcze raz. Potem zdjęcia są jeszcze jakiś czas w „Ostatnio usunięte” w aplikacji Zdjęcia.

ZNAJDŹ MIEJSCE BEZ DŁUGIEGO SZUKANIA
GaleriQ pokazuje, co zajmuje najwięcej miejsca: duże filmy, powtarzające się zdjęcia, serie i stare zrzuty ekranu. Możesz też przeglądać bibliotekę miesiąc po miesiącu albo pozwolić podpowiedzieć sobie rozmazane i podobne zdjęcia. To, co zostaje, a co odchodzi, zawsze decydujesz Ty.

TWÓJ PRYWATNY SEJF
To, czego nikt inny nie powinien widzieć, trzymasz w sejfie: zdjęcia, filmy, pliki i notatki, chronione Twoim kodem i opcjonalnie Face ID. Wszystko w sejfie jest szyfrowane na Twoim iPhonie.

CZAS NA KREATYWNOŚĆ
W Studio edytujesz zdjęcia i filmy, tworzysz kolaże, montujesz krótkie filmy albo zmieniasz zdjęcia w PDF.

CHWILA PRZERWY?
Pary, Foto-Snake i Foto Blocks: trzy małe gry z Twoimi własnymi zdjęciami.

BEZ KONTA
Nie potrzebujesz żadnego konta, a GaleriQ nigdy nigdzie nie wysyła Twoich zdjęć.

ZA DARMO ALBO PRO
Możesz korzystać ze wszystkich funkcji bezpłatnie. Wersja bezpłatna wyświetla reklamy i pozwala usunąć do 100 elementów dziennie. Dzięki dobrowolnemu filmowi odblokowujesz raz dziennie 100 kolejnych. GaleriQ Pro to jednorazowy zakup, nie subskrypcja: bez reklam, bez limitu usuwania i nowe foldery w sejfie bez filmów.""",
)

T["pt-PT"] = dict(
    name="GaleriQ: Limpar fotos e vídeos",
    subtitle="Deslize e liberte espaço",
    keywords="cofre,duplicados,apagar,galeria,álbum,armazenamento,privado,ocultar,colagem,editor,comprimir,arrumar",
    promo="Para cima para manter, para a esquerda para o lixo, para a direita para mais tarde. Nada é apagado sem a sua confirmação e as fotos nunca saem do iPhone.",
    description="""Demasiadas fotos e pouco espaço? Com o GaleriQ arruma a sua fototeca com calma, um gesto de cada vez.

É TÃO SIMPLES ASSIM
Deslize para cima para manter uma foto. Para a esquerda vai para o lixo do GaleriQ, para a direita volta a vê-la dentro de alguns dias, para baixo volta atrás. Nada é apagado até esvaziar o lixo e confirmar mais uma vez. Depois, continua a encontrar as fotos por um tempo em «Apagados recentemente», na app Fotografias.

ENCONTRAR ESPAÇO SEM PROCURAR MUITO
O GaleriQ mostra o que ocupa mais espaço: vídeos grandes, fotos repetidas, séries e capturas de ecrã antigas. Se quiser, percorra a fototeca mês a mês, ou deixe sugerir fotos desfocadas e semelhantes. O que fica ou sai é sempre uma decisão sua.

O SEU COFRE PRIVADO
O que mais ninguém deve ver, guarda-se no cofre: fotos, vídeos, ficheiros e notas, protegidos com o seu código e, se quiser, com Face ID. Todo o conteúdo é encriptado no seu iPhone.

PARA SER CRIATIVO
No Estúdio edita fotos e vídeos, cria colagens, faz pequenos filmes ou transforma fotos num PDF.

UMA PAUSA?
Pares, Serpente de fotos e Foto Blocks: três jogos pequenos com as suas próprias fotos.

SEM CONTA
Não precisa de nenhuma conta, e o GaleriQ nunca envia as suas fotos para lado nenhum.

GRÁTIS OU PRO
Pode usar todas as funções gratuitamente. A versão grátis mostra publicidade e permite apagar até 100 elementos por dia. Com um vídeo opcional, desbloqueia mais 100, uma vez por dia. O GaleriQ Pro é uma compra única, não uma subscrição: sem publicidade, apagar sem limites e novas pastas no cofre sem vídeos.""",
)

T["ro"] = dict(
    name="GaleriQ: Curățare poze",
    subtitle="Glisează și eliberează spațiu",
    keywords="seif,duplicate,ștergere,galerie,album,memorie,privat,ascunde,colaj,editor,comprimare,fotografii",
    promo="În sus păstrezi, la stânga în coș, la dreapta pentru mai târziu. Nimic nu se șterge fără confirmarea ta, iar pozele nu părăsesc niciodată iPhone-ul.",
    description="""Prea multe poze și prea puțin spațiu? Cu GaleriQ îți pui biblioteca în ordine în tihnă, cu o singură mișcare pe poză.

ATÂT DE SIMPLU
Glisează în sus ca să păstrezi o poză. La stânga ajunge în coșul GaleriQ, la dreapta o revezi peste câteva zile, în jos te întorci. Nu se șterge nimic până nu golești coșul și confirmi încă o dată. După aceea, pozele rămân o vreme la „Șterse recent”, în aplicația Poze.

GĂSEȘTI SPAȚIU FĂRĂ SĂ CAUȚI MULT
GaleriQ îți arată ce ocupă cel mai mult spațiu: videoclipuri mari, poze duplicate, serii și capturi de ecran vechi. Dacă vrei, parcurgi biblioteca lună de lună sau lași să ți se sugereze poze neclare și asemănătoare. Ce rămâne și ce pleacă decizi mereu tu.

SEIFUL TĂU PRIVAT
Ce nu trebuie să vadă nimeni altcineva pui în seif: poze, videoclipuri, fișiere și notițe, protejate cu codul tău și, dacă vrei, cu Face ID. Tot ce e în seif este criptat pe iPhone-ul tău.

TIMP PENTRU CREATIVITATE
În Studio editezi poze și videoclipuri, creezi colaje, faci filmulețe scurte sau transformi pozele într-un PDF.

O PAUZĂ?
Perechi, Șarpele foto și Foto Blocks: trei jocuri mici cu propriile tale poze.

FĂRĂ CONT
Nu ai nevoie de niciun cont, iar GaleriQ nu îți încarcă niciodată pozele nicăieri.

GRATUIT SAU PRO
Poți folosi toate funcțiile gratuit. Versiunea gratuită are reclame și îți permite să ștergi până la 100 de elemente pe zi. Cu un videoclip opțional, mai deblochezi 100 o dată pe zi. GaleriQ Pro este o achiziție unică, nu un abonament: fără reclame, ștergere nelimitată și dosare noi în seif fără videoclipuri.""",
)

T["ru"] = dict(
    name="GaleriQ: очистка фото и сейф",
    subtitle="Свайп — и память свободна",
    keywords="удаление,дубликаты,галерея,альбом,хранилище,скрыть,приватный,коллаж,редактор,сжатие,видео,уборка",
    promo="Вверх — оставить, влево — в корзину, вправо — на потом. Ничего не удаляется без вашего подтверждения, а фото никогда не покидают iPhone.",
    description="""Слишком много фото и мало места? С GaleriQ вы наведёте порядок в медиатеке спокойно, одним движением за раз.

ВСЁ ПРОСТО
Смахните вверх, чтобы оставить фото. Влево — оно попадёт в корзину GaleriQ, вправо — вы увидите его снова через пару дней, вниз — вернётесь назад. Ничего не удаляется, пока вы не очистите корзину и не подтвердите ещё раз. После этого фото ещё какое-то время можно найти в «Недавно удалённые» в приложении «Фото».

НАЙТИ МЕСТО БЕЗ ДОЛГИХ ПОИСКОВ
GaleriQ показывает, что занимает больше всего места: большие видео, повторяющиеся фото, серии и старые скриншоты. Можно также просматривать медиатеку месяц за месяцем или смотреть предложенные размытые и похожие фото. Что оставить, а что убрать — решаете только вы.

ВАШ ЛИЧНЫЙ СЕЙФ
То, что не должен видеть никто другой, вы храните в сейфе: фото, видео, файлы и заметки — под защитой вашего кода и, если хотите, Face ID. Всё содержимое сейфа шифруется на вашем iPhone.

ВРЕМЯ ДЛЯ ТВОРЧЕСТВА
В Студии вы редактируете фото и видео, создаёте коллажи, монтируете короткие ролики или превращаете фото в PDF.

НУЖНА ПАУЗА?
«Пары», «Фото-змейка» и Foto Blocks — три маленькие игры с вашими собственными фото.

БЕЗ АККАУНТА
Аккаунт не нужен, а GaleriQ никогда никуда не загружает ваши фото.

БЕСПЛАТНО ИЛИ PRO
Все функции доступны бесплатно. В бесплатной версии показывается реклама, и можно удалять до 100 элементов в день. Посмотрев необязательное видео, можно разблокировать ещё 100 — раз в день. GaleriQ Pro — это разовая покупка, а не подписка: без рекламы, неограниченное удаление и новые папки в сейфе без видео.""",
)

T["tr"] = dict(
    name="GaleriQ: Fotoğraf Temizleyici",
    subtitle="Kaydır, yer aç, kasada sakla",
    keywords="kopya,silme,galeri,albüm,depolama,gizli,gizle,kolaj,düzenleyici,sıkıştırma,video,ekran görüntüsü",
    promo="Yukarı kaydır sakla, sola çöpe at, sağa sonraya bırak. Onaylamadan hiçbir şey silinmez ve fotoğrafların iPhone'undan asla çıkmaz.",
    description="""Fazla fotoğraf, az yer mi var? GaleriQ ile arşivini rahatça düzenlersin, her fotoğrafta tek bir kaydırmayla.

ÇOK BASİT
Bir fotoğrafı saklamak için yukarı kaydır. Sola kaydırınca GaleriQ'nun çöp kutusuna gider, sağa kaydırınca birkaç gün sonra tekrar görürsün, aşağı kaydırınca geri dönersin. Çöp kutusunu boşaltıp bir kez daha onaylamadan hiçbir şey silinmez. Fotoğraflarını daha sonra bir süre Fotoğraflar uygulamasındaki "Son Silinenler"de bulabilirsin.

UZUN UZUN ARAMADAN YER BUL
GaleriQ en çok yer kaplayanları gösterir: büyük videolar, aynı fotoğraflar, seriler ve eski ekran görüntüleri. İstersen arşivini ay ay gözden geçir, ya da bulanık ve birbirine benzeyen fotoğrafları önermesine izin ver. Neyin kalıp neyin gideceğine her zaman sen karar verirsin.

ÖZEL KASAN
Başka kimsenin görmemesi gerekenleri kasana koyarsın: fotoğraflar, videolar, dosyalar ve notlar; kendi kodunla, istersen Face ID ile korunur. Kasadaki her şey iPhone'unda şifrelenir.

YARATICI OLMA ZAMANI
Stüdyo'da fotoğraf ve videolarını düzenler, kolajlar yaparsın, kısa filmler çeker ya da fotoğraflarını PDF'e çevirirsin.

ARA VERME ZAMANI MI?
Çiftler, Fotoğraf yılanı ve Foto Blocks: kendi fotoğraflarınla oynayabileceğin üç küçük oyun.

HESAP GEREKMEZ
Hesaba ihtiyacın yok, GaleriQ fotoğraflarını hiçbir yere yüklemez.

ÜCRETSİZ VEYA PRO
Tüm özellikleri ücretsiz kullanabilirsin. Ücretsiz sürümde reklam gösterilir ve günde 100 öğeye kadar silebilirsin. İsteğe bağlı bir videoyla günde bir kez 100 öğe daha açarsın. GaleriQ Pro tek seferlik bir satın almadır, abonelik değildir: reklamsız, sınırsız silme ve video izlemeden yeni kasa klasörleri.""",
)

T["uk"] = dict(
    name="GaleriQ: очищення фото і сейф",
    subtitle="Свайп — і пам’ять вільна",
    keywords="видалення,дублікати,галерея,альбом,сховище,приховати,приватний,колаж,редактор,стиснення,відео",
    promo="Угору — залишити, ліворуч — у кошик, праворуч — на потім. Нічого не видаляється без вашого підтвердження, а фото ніколи не залишають iPhone.",
    description="""Забагато фото й мало місця? З GaleriQ ви спокійно впорядкуєте медіатеку — по одному руху за раз.

ВСЕ ДУЖЕ ПРОСТО
Проведіть вгору, щоб залишити фото. Ліворуч — воно потрапляє в кошик GaleriQ, праворуч — побачите його знову через кілька днів, вниз — повернетеся назад. Нічого не видаляється, доки ви не очистите кошик і не підтвердите ще раз. Потім фото ще якийсь час можна знайти в «Нещодавно видалені» у застосунку «Фото».

ЗНАЙТИ МІСЦЕ, НЕ ШУКАЮЧИ ДОВГО
GaleriQ показує, що займає найбільше місця: великі відео, однакові фото, серії та старі знімки екрана. Можна також переглядати медіатеку місяць за місяцем або отримувати пропозиції розмитих і схожих фото. Що залишити, а що прибрати — завжди вирішуєте ви.

ВАШ ОСОБИСТИЙ СЕЙФ
Те, що не повинен бачити ніхто інший, зберігається в сейфі: фото, відео, файли й нотатки — під захистом вашого коду і, за бажанням, Face ID. Весь вміст сейфа шифрується на вашому iPhone.

ЧАС ДЛЯ ТВОРЧОСТІ
У Студії ви редагуєте фото й відео, створюєте колажі, монтуєте короткі ролики або перетворюєте фото на PDF.

ХОЧЕТЕ ПЕРЕРВУ?
«Пари», «Фото-змійка» і Foto Blocks — три невеликі гри з вашими власними фото.

БЕЗ АКАУНТА
Акаунт не потрібен, а GaleriQ ніколи нікуди не завантажує ваші фото.

БЕЗКОШТОВНО АБО PRO
Усі функції доступні безкоштовно. У безкоштовній версії є реклама, і можна видаляти до 100 елементів на день. Переглянувши необов'язкове відео, можна розблокувати ще 100 — раз на день. GaleriQ Pro — це одноразова покупка, а не підписка: без реклами, необмежене видалення і нові папки в сейфі без відео.""",
)

T["zh-Hans"] = dict(
    name="GaleriQ：照片清理与私密保险箱",
    subtitle="滑动整理，释放空间",
    keywords="相册,删除,重复,存储,隐藏,加密,拼图,编辑,压缩,视频,截图,图库,瘦身,大文件",
    promo="上滑保留，左滑放入回收站，右滑稍后再看。未经你确认不会删除任何内容，照片也永远不会离开你的 iPhone。",
    description="""照片太多，空间不够？有了 GaleriQ，你可以轻松整理，每次只需一个滑动动作。

就是这么简单
上滑保留一张照片，左滑放入 GaleriQ 回收站，右滑则几天后再看一次，下滑回到上一张。只有在清空回收站并再次确认后，才会真正删除。之后你还能在"照片"App 的"最近删除"里找到它们一段时间。

轻松找到占用空间的内容
GaleriQ 会告诉你哪些内容占用空间最多：大视频、重复的照片、连拍系列和旧截图。你也可以按月浏览图库，或者看看它推荐的模糊、相似照片。留下还是删除，始终由你决定。

你的私密保险箱
不想被别人看到的内容，都可以放进保险箱：照片、视频、文件和备忘，用你自己的密码保护，也可以加上面容 ID。保险箱里的一切都会在你的 iPhone 上加密。

创意时间
在工作室里，你可以编辑照片和视频、制作拼图、剪辑小短片，或者把照片变成 PDF。

想休息一下吗？
配对、照片贪吃蛇和 Foto Blocks：三个用你自己照片玩的小游戏。

无需账户
你不需要任何账户，GaleriQ 也从不会把你的照片上传到任何地方。

免费或 Pro
所有功能都可以免费使用。免费版会显示广告，每天最多可删除 100 项。观看一次可选视频后，每天可以再解锁 100 项。GaleriQ Pro 是一次性购买，不是订阅：无广告、无限删除，无需看视频即可新建保险箱文件夹。""",
)

T["ar-SA"] = dict(
    name="GaleriQ: تنظيف الصور والخزنة",
    subtitle="اسحب لتحرير مساحة التخزين",
    keywords="حذف,مكررة,معرض,ألبوم,خاص,إخفاء,كولاج,محرر,ضغط,فيديو,لقطات الشاشة,ترتيب",
    promo="اسحب لأعلى للاحتفاظ، ولليسار إلى سلة المهملات، ولليمين لوقت لاحق. لا يُحذف شيء دون تأكيدك، ولا تغادر صورك جهاز iPhone أبدًا.",
    description="""كثير من الصور، ومساحة قليلة؟ مع GaleriQ تُرتّب مكتبة الصور بهدوء، بسحبة واحدة لكل صورة.

بهذه البساطة
اسحب لأعلى للاحتفاظ بالصورة. لليسار تذهب إلى سلة مهملات GaleriQ، ولليمين تراها مرة أخرى بعد أيام قليلة، ولأسفل تعود للخلف. لا يُحذف شيء حتى تُفرغ السلة وتؤكد مرة أخرى. بعد ذلك، تبقى صورك لفترة في «المحذوفة مؤخرًا» بتطبيق الصور.

اعثر على مساحة دون بحث طويل
يُظهر لك GaleriQ ما يشغل أكبر مساحة: الفيديوهات الكبيرة، الصور المتكررة، السلاسل ولقطات الشاشة القديمة. يمكنك أيضًا تصفّح مكتبتك شهرًا بشهر، أو ترك GaleriQ يقترح عليك صورًا ضبابية أو متشابهة. القرار فيما يبقى وما يُحذف لك دائمًا.

خزنتك الخاصة
ما لا يجب أن يراه أحد غيرك، تضعه في الخزنة: صور، فيديوهات، ملفات وملاحظات، محمية برمزك الخاص ومع Face ID إن أردت. كل ما في الخزنة يُشفَّر على جهاز iPhone.

وقت الإبداع
في الاستوديو، تُحرّر صورك وفيديوهاتك، وتُصمّم كولاجات، وتصنع مقاطع قصيرة أو تُحوّل صورك إلى PDF.

وقت الاستراحة؟
أزواج وثعبان الصور وFoto Blocks: ثلاث ألعاب صغيرة بصورك الخاصة.

بدون حساب
لا تحتاج إلى أي حساب، وGaleriQ لا يرفع صورك إلى أي مكان أبدًا.

مجاني أو Pro
يمكنك استخدام كل الميزات مجانًا. تعرض النسخة المجانية إعلانات وتتيح حذف ما يصل إلى 100 عنصر يوميًا. بمشاهدة فيديو اختياري، تفتح 100 عنصر إضافي مرة في اليوم. GaleriQ Pro عملية شراء واحدة، لا اشتراك: بلا إعلانات، وحذف غير محدود، ومجلدات خزنة جديدة دون فيديوهات.""",
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


# „Neuerungen in dieser Version“ (Pflicht bei Updates, höchstens 4000 Zeichen). Version 1.0.1.
RELEASE_NOTES = {
    "en-US": "The vault is now tidier, with more room for your photos. You can rate GaleriQ right from Settings. If no ad is available, you now see a short note instead of nothing. Plus small improvements.",
    "de-DE": "Der Tresor ist jetzt aufgeräumter und lässt deinen Fotos mehr Platz. In den Einstellungen kannst du GaleriQ direkt bewerten. Ist gerade keine Werbung verfügbar, siehst du jetzt einen kurzen Hinweis. Dazu kleine Verbesserungen.",
    "es-ES": "La caja fuerte ahora está más ordenada y deja más espacio a tus fotos. Puedes valorar GaleriQ directamente desde Ajustes. Si no hay ningún anuncio disponible, ahora verás un breve aviso. Y pequeñas mejoras.",
    "fr-FR": "Le coffre-fort est désormais plus épuré et laisse plus de place à vos photos. Vous pouvez noter GaleriQ directement depuis les Réglages. Si aucune publicité n'est disponible, un court message s'affiche désormais. Et quelques petites améliorations.",
    "it": "La cassaforte ora è più ordinata e lascia più spazio alle tue foto. Puoi valutare GaleriQ direttamente dalle Impostazioni. Se non è disponibile nessuna pubblicità, ora vedi un breve avviso. E piccoli miglioramenti.",
    "ja": "保管庫がすっきりして、写真をより広く表示できるようになりました。設定から GaleriQ を直接評価できます。広告がないときは、短いお知らせが表示されるようになりました。そのほか細かな改善を行いました。",
    "ko": "금고가 더 깔끔해져서 사진을 더 넓게 볼 수 있어요. 설정에서 GaleriQ를 바로 평가할 수 있어요. 광고가 없을 때는 이제 짧은 안내가 표시돼요. 그 밖의 작은 개선도 있어요.",
    "nl-NL": "De kluis is nu overzichtelijker en geeft je foto's meer ruimte. Je kunt GaleriQ direct beoordelen via Instellingen. Is er even geen advertentie beschikbaar, dan zie je nu een korte melding. Plus kleine verbeteringen.",
    "pl": "Sejf jest teraz bardziej przejrzysty i zostawia więcej miejsca na zdjęcia. GaleriQ możesz ocenić bezpośrednio w Ustawieniach. Gdy żadna reklama nie jest dostępna, zobaczysz teraz krótką informację. Do tego drobne poprawki.",
    "pt-PT": "O cofre está agora mais arrumado e deixa mais espaço às suas fotos. Pode avaliar o GaleriQ diretamente nas Definições. Se não houver nenhum anúncio disponível, aparece agora um aviso curto. E pequenas melhorias.",
    "ro": "Seiful este acum mai ordonat și lasă mai mult loc pozelor tale. Poți evalua GaleriQ direct din Configurări. Dacă nu este disponibilă nicio reclamă, acum vezi un scurt mesaj. Plus mici îmbunătățiri.",
    "ru": "Сейф стал аккуратнее, и для фото теперь больше места. Оценить GaleriQ можно прямо в Настройках. Если реклама сейчас недоступна, вы увидите короткое сообщение. А также небольшие улучшения.",
    "tr": "Kasa artık daha sade ve fotoğraflarına daha fazla yer bırakıyor. GaleriQ'yu doğrudan Ayarlar'dan değerlendirebilirsin. Şu anda reklam yoksa artık kısa bir bilgi görürsün. Ayrıca küçük iyileştirmeler.",
    "uk": "Сейф став охайнішим, і для фото тепер більше місця. Оцінити GaleriQ можна прямо в Параметрах. Якщо реклама зараз недоступна, ви побачите коротке повідомлення. А також невеликі покращення.",
    "zh-Hans": "保险箱现在更简洁，给照片留出更多空间。你可以直接在设置中为 GaleriQ 评分。暂时没有广告时，现在会显示一条简短提示。另有一些小改进。",
    "ar-SA": "أصبحت الخزنة أكثر ترتيبًا وتترك مساحة أكبر لصورك. يمكنك تقييم GaleriQ مباشرة من الإعدادات. إذا لم يتوفر أي إعلان، تظهر لك الآن رسالة قصيرة. بالإضافة إلى تحسينات صغيرة.",
}

# Werbetext ohne Pauschalversprechen „Fotos verlassen nie das iPhone“ (10.11.2026): GaleriQ lädt nichts hoch,
# die Gratisversion zeigt aber Werbung. Überschreibt die Werte oben.
PROMO = {
    "en-US": "Swipe up to keep, left to the trash, right for later. Nothing is deleted until you confirm, and GaleriQ never uploads your photos.",
    "de-DE": "Nach oben behalten, nach links in den Papierkorb, nach rechts auf später. Gelöscht wird erst nach deiner Bestätigung – und GaleriQ lädt deine Fotos nirgendwohin hoch.",
    "es-ES": "Arriba para conservar, a la izquierda a la papelera, a la derecha para después. Nada se borra sin tu confirmación y GaleriQ nunca sube tus fotos.",
    "fr-FR": "Vers le haut pour garder, à gauche vers la corbeille, à droite pour plus tard. Rien n’est supprimé sans votre accord et GaleriQ n’envoie jamais vos photos.",
    "it": "Su per conservare, a sinistra nel cestino, a destra per più tardi. Nulla viene eliminato senza la tua conferma e GaleriQ non carica mai le tue foto.",
    "ja": "上で残す、左でゴミ箱へ、右で「あとで」。確認するまで何も削除されず、GaleriQ が写真をアップロードすることもありません。",
    "ko": "위로 밀면 보관, 왼쪽은 휴지통, 오른쪽은 나중에. 확인하기 전에는 아무것도 삭제되지 않으며 GaleriQ는 사진을 어디에도 올리지 않습니다.",
    "nl-NL": "Omhoog om te bewaren, naar links naar de prullenbak, naar rechts voor later. Er wordt niets verwijderd zonder jouw bevestiging en GaleriQ uploadt je foto's nooit.",
    "pl": "W górę – zachowaj, w lewo – do kosza, w prawo – na później. Nic nie zostanie usunięte bez Twojego potwierdzenia, a GaleriQ nigdzie nie wysyła Twoich zdjęć.",
    "pt-PT": "Para cima para manter, para a esquerda para o lixo, para a direita para mais tarde. Nada é apagado sem a sua confirmação e o GaleriQ nunca envia as suas fotos.",
    "ro": "În sus păstrezi, la stânga în coș, la dreapta pentru mai târziu. Nimic nu se șterge fără confirmarea ta, iar GaleriQ nu îți încarcă niciodată pozele.",
    "ru": "Вверх — оставить, влево — в корзину, вправо — на потом. Ничего не удаляется без вашего подтверждения, а GaleriQ никуда не загружает ваши фото.",
    "tr": "Yukarı kaydır sakla, sola çöpe at, sağa sonraya bırak. Onaylamadan hiçbir şey silinmez ve GaleriQ fotoğraflarını hiçbir yere yüklemez.",
    "uk": "Угору — залишити, ліворуч — у кошик, праворуч — на потім. Нічого не видаляється без вашого підтвердження, а GaleriQ нікуди не завантажує ваші фото.",
    "zh-Hans": "上滑保留，左滑放入回收站，右滑稍后再看。未经你确认不会删除任何内容，GaleriQ 也从不上传你的照片。",
    "ar-SA": "اسحب لأعلى للاحتفاظ، ولليسار إلى سلة المهملات، ولليمين لوقت لاحق. لا يُحذف شيء دون تأكيدك، ولا يرفع GaleriQ صورك إلى أي مكان."
}
for _loc, _promo in PROMO.items():
    T[_loc]["promo"] = _promo

# Weitere Store-Sprachen aus scripts/store/texts_extra_*.py (Felder wie oben plus notes und iap).
import importlib.util as _ilu
for _path in sorted(pathlib.Path(__file__).resolve().parent.glob("texts_extra_*.py")):
    _spec = _ilu.spec_from_file_location(_path.stem, _path)
    _mod = _ilu.module_from_spec(_spec)
    _spec.loader.exec_module(_mod)
    for _loc, _t in _mod.S.items():
        if _loc in T:
            raise SystemExit(f"{_loc} doppelt ({_path.name})")
        T[_loc] = {k: _t[k] for k in ("name", "subtitle", "keywords", "promo", "description")}
        RELEASE_NOTES[_loc] = _t["notes"]
        IAP[_loc] = _t["iap"]

# Alle 50 Sprachen, die App Store Connect anbietet (Apple, „locale shortcodes“, Stand 2026).
APPLE_LOCALES = ["ar-SA", "bn-BD", "ca", "zh-Hans", "zh-Hant", "hr", "cs", "da", "nl-NL", "en-AU", "en-CA", "en-GB",
                 "en-US", "fi", "fr-FR", "fr-CA", "de-DE", "el", "gu-IN", "he", "hi", "hu", "id", "it", "ja", "kn-IN",
                 "ko", "ms", "ml-IN", "mr-IN", "no", "or-IN", "pl", "pt-BR", "pt-PT", "pa-IN", "ro", "ru", "sk", "sl-SI",
                 "es-MX", "es-ES", "sv", "ta-IN", "te-IN", "th", "tr", "uk", "ur-PK", "vi"]

LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promo": 170, "description": 4000}
FILES = {"name": "name.txt", "subtitle": "subtitle.txt", "keywords": "keywords.txt",
         "promo": "promotional_text.txt", "description": "description.txt"}


def check() -> list[str]:
    errors = []
    unknown = set(T) - set(APPLE_LOCALES)
    if unknown:
        errors.append(f"keine App-Store-Sprache: {sorted(unknown)}")
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
    if set(RELEASE_NOTES) != set(T):
        errors.append("Neuerungen: Sprachen passen nicht")
    for loc, text in RELEASE_NOTES.items():
        if not text.strip() or len(text) > 4000 or "PhotoMaid" in text:
            errors.append(f"Neuerungen {loc}: leer, zu lang oder alter Name")
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
        (folder / "release_notes.txt").write_text(RELEASE_NOTES[loc] + "\n", encoding="utf-8")
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
