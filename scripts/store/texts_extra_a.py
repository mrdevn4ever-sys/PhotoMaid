"""Store-Texte, Paket A (10.11.2026): Regionalvarianten und weitere Sprachen. Quelle: en-US/de-DE (einfacher Stil).
Felder wie in metadata_texts.py, zusätzlich notes (Neuerungen 1.0.1) und iap (≤ 55 Zeichen)."""

_EN_DESC = """Too many photos, not enough storage? GaleriQ helps you tidy up your library – one relaxed swipe at a time.

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
Every feature is free to use. The free version shows ads and lets you delete up to 100 items a day. Watch an optional video once a day to unlock 100 more. GaleriQ Pro is a one-time purchase, not a subscription: no ads, unlimited deleting, and new vault folders without watching videos."""

_EN_PROMO = ("Swipe up to keep, left to the trash, right for later. Nothing is deleted until you confirm, "
             "and GaleriQ never uploads your photos.")
_EN_NOTES = ("The vault is now tidier, with more room for your photos. You can rate GaleriQ right from Settings. "
             "If no ad is available, you now see a short note instead of nothing. Plus small improvements.")
_EN_IAP = "No ads, unlimited deleting, free vault folders"

S = {}

# Englisch (UK, Australien, Kanada): gleiche Beschreibung (keine abweichenden Schreibweisen im Text),
# eigene Untertitel und Keywords, damit die Länder-Stores zusätzliche Suchbegriffe abdecken.
S["en-GB"] = dict(name="GaleriQ: Photo Cleaner & Vault", subtitle="Free up storage with a swipe",
                  keywords="cleanup,declutter,gallery,duplicate,memory,screenshots,videos,secret,lock,folder,organiser,tidy",
                  promo=_EN_PROMO, description=_EN_DESC, notes=_EN_NOTES, iap=_EN_IAP)
S["en-AU"] = dict(name="GaleriQ: Photo Cleaner & Vault", subtitle="Declutter your camera roll",
                  keywords="cleanup,storage,space,duplicate,gallery,memory,screenshots,secret,lock,folder,organiser,tidy",
                  promo=_EN_PROMO, description=_EN_DESC, notes=_EN_NOTES, iap=_EN_IAP)
S["en-CA"] = dict(name="GaleriQ: Photo Cleaner & Vault", subtitle="Swipe to free up storage",
                  keywords="cleanup,declutter,gallery,duplicate,memory,screenshots,videos,secret,lock,folder,organizer",
                  promo=_EN_PROMO, description=_EN_DESC, notes=_EN_NOTES, iap=_EN_IAP)

S["fr-CA"] = dict(
    name="GaleriQ : Nettoyer vos photos", subtitle="Libérez l’espace en glissant",
    keywords="coffre-fort,doublons,supprimer,galerie,album,mémoire,privé,cacher,collage,éditeur,vidéos,ménage",
    promo="Vers le haut pour garder, à gauche vers la corbeille, à droite pour plus tard. Rien n’est supprimé sans votre accord et GaleriQ ne téléverse jamais vos photos.",
    description="""Trop de photos, pas assez d’espace ? Avec GaleriQ, vous faites le ménage dans votre photothèque tranquillement, un glissement à la fois.

C’EST TOUT SIMPLE
Glissez vers le haut pour garder une photo. Vers la gauche, elle va dans la corbeille de GaleriQ; vers la droite, vous la revoyez dans quelques jours; vers le bas, vous revenez en arrière. Rien n’est supprimé tant que vous ne videz pas la corbeille et ne confirmez pas une seconde fois. Vos photos restent ensuite un moment dans « Suppressions récentes », dans l’app Photos.

TROUVER DE L’ESPACE RAPIDEMENT
GaleriQ vous montre ce qui prend le plus de place : grosses vidéos, photos en double, rafales et vieilles captures d’écran. Vous pouvez aussi parcourir votre photothèque mois par mois, ou laisser GaleriQ vous proposer des photos floues ou semblables. Ce qui part ou reste, c’est toujours vous qui décidez.

VOTRE COFFRE-FORT PRIVÉ
Ce que personne d’autre ne doit voir, vous le rangez dans le coffre-fort : photos, vidéos, fichiers et notes, protégés par votre code et, si vous le voulez, par Face ID. Tout son contenu est chiffré sur votre iPhone.

PLACE À LA CRÉATIVITÉ
Dans Studio, vous retouchez vos photos et vidéos, créez des collages, montez de petits films ou transformez vos photos en PDF.

UNE PETITE PAUSE ?
Paires, Serpent photo et Foto Blocks : trois petits jeux avec vos propres photos.

SANS COMPTE
Vous n’avez besoin d’aucun compte, et GaleriQ ne téléverse jamais vos photos nulle part.

GRATUIT OU PRO
Toutes les fonctions sont gratuites. La version gratuite affiche de la publicité et permet de supprimer jusqu’à 100 éléments par jour. Une vidéo facultative permet d’en débloquer 100 de plus, une fois par jour. GaleriQ Pro est un achat unique, pas un abonnement : sans publicité, suppressions illimitées et nouveaux dossiers du coffre-fort sans vidéo.""",
    notes="Le coffre-fort est maintenant plus épuré et laisse plus de place à vos photos. Vous pouvez évaluer GaleriQ directement dans les Réglages. Si aucune publicité n’est disponible, un court message s’affiche maintenant. Et quelques petites améliorations.",
    iap="Sans pub, suppressions illimitées, dossiers libres",
)

S["es-MX"] = dict(
    name="GaleriQ: Limpiador de fotos", subtitle="Desliza y libera espacio",
    keywords="caja fuerte,duplicados,borrar,galería,álbum,memoria,privado,ocultar,collage,editor,videos,carrete",
    promo="Arriba para conservar, a la izquierda a la papelera, a la derecha para después. No se borra nada sin tu confirmación y GaleriQ nunca sube tus fotos.",
    description="""¿Demasiadas fotos y poco espacio? Con GaleriQ ordenas tu fototeca con calma, deslizando una foto a la vez.

ASÍ DE FÁCIL
Desliza hacia arriba para conservar una foto. Hacia la izquierda va a la papelera de GaleriQ, hacia la derecha la vuelves a ver en unos días, y hacia abajo regresas. No se borra nada hasta que vacías la papelera y lo confirmas una vez más. Después, todavía encuentras tus fotos por un tiempo en «Eliminado», en la app Fotos.

ENCUENTRA ESPACIO RÁPIDO
GaleriQ te muestra qué ocupa más espacio: videos grandes, fotos repetidas, series y capturas de pantalla viejas. Si quieres, revisa tu fototeca mes por mes o deja que te sugiera fotos borrosas y parecidas. Lo que se queda o se va, siempre lo decides tú.

TU CAJA FUERTE PRIVADA
Lo que nadie más debe ver, guárdalo en la caja fuerte: fotos, videos, archivos y notas, protegidos con tu código y, si quieres, con Face ID. Todo lo que hay dentro se cifra en tu iPhone.

PONTE CREATIVO
En Estudio editas fotos y videos, creas collages, haces pequeñas películas o conviertes tus fotos en un PDF.

¿UN DESCANSO?
Parejas, Serpiente de fotos y Foto Blocks: tres juegos pequeños con tus propias fotos.

SIN CUENTA
No necesitas ninguna cuenta y GaleriQ nunca sube tus fotos a ningún lado.

GRATIS O PRO
Puedes usar todas las funciones gratis. La versión gratuita muestra anuncios y te deja borrar hasta 100 elementos al día. Con un video opcional desbloqueas 100 más, una vez al día. GaleriQ Pro es una compra única, no una suscripción: sin anuncios, borrado ilimitado y carpetas nuevas en la caja fuerte sin ver videos.""",
    notes="La caja fuerte ahora está más ordenada y deja más espacio a tus fotos. Puedes calificar GaleriQ directamente desde Configuración. Si no hay ningún anuncio disponible, ahora ves un aviso breve. Y pequeñas mejoras.",
    iap="Sin anuncios, borrado ilimitado, carpetas libres",
)

S["pt-BR"] = dict(
    name="GaleriQ: Limpar fotos e vídeos", subtitle="Deslize e libere espaço",
    keywords="cofre,duplicadas,apagar,galeria,álbum,armazenamento,privado,ocultar,colagem,editor,memória",
    promo="Para cima para manter, para a esquerda para a lixeira, para a direita para depois. Nada é apagado sem a sua confirmação e o GaleriQ nunca envia suas fotos.",
    description="""Fotos demais e espaço de menos? Com o GaleriQ você organiza sua fototeca com calma, deslizando uma foto de cada vez.

SIMPLES ASSIM
Deslize para cima para manter uma foto. Para a esquerda, ela vai para a lixeira do GaleriQ; para a direita, você a vê de novo em alguns dias; para baixo, você volta. Nada é apagado até você esvaziar a lixeira e confirmar mais uma vez. Depois disso, suas fotos ainda ficam um tempo em "Apagados", no app Fotos.

ACHE ESPAÇO RÁPIDO
O GaleriQ mostra o que ocupa mais espaço: vídeos grandes, fotos duplicadas, sequências e capturas de tela antigas. Se quiser, revise sua fototeca mês a mês ou deixe o GaleriQ sugerir fotos desfocadas e parecidas. O que fica e o que sai é sempre você quem decide.

SEU COFRE PRIVADO
O que ninguém mais deve ver, você guarda no cofre: fotos, vídeos, arquivos e notas, protegidos com o seu código e, se quiser, com Face ID. Tudo dentro do cofre é criptografado no seu iPhone.

SEJA CRIATIVO
No Estúdio você edita fotos e vídeos, cria colagens, faz filminhos ou transforma suas fotos em PDF.

UMA PAUSA?
Pares, Cobrinha de fotos e Foto Blocks: três joguinhos com as suas próprias fotos.

SEM CONTA
Você não precisa de nenhuma conta, e o GaleriQ nunca envia suas fotos para lugar nenhum.

GRÁTIS OU PRO
Você pode usar todos os recursos de graça. A versão gratuita mostra anúncios e permite apagar até 100 itens por dia. Com um vídeo opcional, você libera mais 100, uma vez por dia. O GaleriQ Pro é uma compra única, não uma assinatura: sem anúncios, exclusão ilimitada e novas pastas no cofre sem assistir a vídeos.""",
    notes="O cofre está mais organizado e deixa mais espaço para suas fotos. Você pode avaliar o GaleriQ direto nos Ajustes. Se não houver nenhum anúncio disponível, agora aparece um aviso curto. E pequenas melhorias.",
    iap="Sem anúncios, exclusão ilimitada, pastas livres",
)

S["zh-Hant"] = dict(
    name="GaleriQ：照片清理與私密保險箱", subtitle="滑動整理，釋放空間",
    keywords="相簿,刪除,重複,儲存空間,隱藏,加密,拼貼,編輯,壓縮,影片,截圖,圖庫,大檔案",
    promo="上滑保留，左滑放入垃圾桶，右滑稍後再看。未經你確認不會刪除任何內容，GaleriQ 也從不上傳你的照片。",
    description="""照片太多，空間不夠？有了 GaleriQ，你可以輕鬆整理，每次只需滑一下。

就是這麼簡單
上滑保留照片，左滑放入 GaleriQ 垃圾桶，右滑幾天後再看一次，下滑回到上一張。只有在清空垃圾桶並再次確認後，才會真正刪除。之後你還能在「照片」App 的「最近刪除」裡找到它們一段時間。

輕鬆找到占用空間的內容
GaleriQ 會告訴你哪些內容最占空間：大型影片、重複的照片、連拍系列和舊的截圖。你也可以按月瀏覽圖庫，或讓 GaleriQ 推薦模糊、相似的照片。留下或刪除，永遠由你決定。

你的私密保險箱
不想被別人看到的內容，都可以放進保險箱：照片、影片、檔案和備忘錄，用你自己的密碼保護，也可以加上 Face ID。保險箱裡的一切都會在你的 iPhone 上加密。

創意時間
在工作室裡，你可以編輯照片和影片、製作拼貼、剪輯小短片，或把照片變成 PDF。

想休息一下嗎？
配對、照片貪食蛇和 Foto Blocks：三個用你自己照片玩的小遊戲。

不需要帳號
你不需要任何帳號，GaleriQ 也從不會把你的照片上傳到任何地方。

免費或 Pro
所有功能都可以免費使用。免費版會顯示廣告，每天最多可刪除 100 項。觀看一段選擇性影片後，每天可再解鎖 100 項。GaleriQ Pro 是一次性購買，不是訂閱：無廣告、無限刪除，不必看影片即可新增保險箱檔案夾。""",
    notes="保險箱現在更簡潔，讓照片有更多空間。你可以直接在「設定」中為 GaleriQ 評分。暫時沒有廣告時，現在會顯示一則簡短提示。另有一些小改進。",
    iap="無廣告、無限刪除、自由新增保險箱檔案夾",
)

S["ca"] = dict(
    name="GaleriQ: Netejar fotos", subtitle="Llisca i allibera espai",
    keywords="caixa forta,duplicats,esborrar,galeria,àlbum,emmagatzematge,privat,amagar,collage,editor,vídeos",
    promo="Amunt per conservar, a l’esquerra a la paperera, a la dreta per a després. No s’esborra res sense la teva confirmació i GaleriQ no penja mai les teves fotos.",
    description="""Massa fotos i poc espai? Amb GaleriQ endreces la teva fototeca amb calma, lliscant una foto cada vegada.

AIXÍ DE FÀCIL
Llisca amunt per conservar una foto. A l’esquerra va a la paperera de GaleriQ, a la dreta la tornes a veure d’aquí a uns dies, i avall tornes enrere. No s’esborra res fins que buides la paperera i ho confirmes una altra vegada. Després, encara trobes les fotos durant un temps a «Eliminat recentment», a l’app Fotos.

TROBA ESPAI DE PRESSA
GaleriQ et mostra què ocupa més espai: vídeos grans, fotos repetides, sèries i captures de pantalla antigues. Si vols, revisa la fototeca mes a mes o deixa que et suggereixi fotos borroses i semblants. Què es queda i què marxa, ho decideixes sempre tu.

LA TEVA CAIXA FORTA PRIVADA
El que ningú més ha de veure, ho guardes a la caixa forta: fotos, vídeos, fitxers i notes, protegits amb el teu codi i, si vols, amb Face ID. Tot el que hi ha a dins es xifra al teu iPhone.

SIGUES CREATIU
A l’Estudi edites fotos i vídeos, crees collages, fas petites pel·lícules o converteixes les fotos en un PDF.

UNA PAUSA?
Parelles, Serp de fotos i Foto Blocks: tres jocs petits amb les teves pròpies fotos.

SENSE COMPTE
No necessites cap compte, i GaleriQ no penja mai les teves fotos enlloc.

GRATIS O PRO
Pots fer servir totes les funcions gratis. La versió gratuïta mostra anuncis i et deixa esborrar fins a 100 elements al dia. Amb un vídeo opcional en desbloqueges 100 més, un cop al dia. GaleriQ Pro és una compra única, no una subscripció: sense anuncis, esborrat il·limitat i carpetes noves a la caixa forta sense vídeos.""",
    notes="La caixa forta ara és més endreçada i deixa més espai a les teves fotos. Pots valorar GaleriQ directament des de Configuració. Si no hi ha cap anunci disponible, ara veus un avís breu. I petites millores.",
    iap="Sense anuncis, esborrat il·limitat, carpetes lliures",
)
