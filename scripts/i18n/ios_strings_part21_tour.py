from ios_strings_part1 import T

# Rundgang auf „Heute“ (Nutzer, 21.10.2026): Schritte für den Tresor („PhotoMaid“ halten) und die Spiele (Kurze Pause).
# Sprachen: en, de, ar, es, fr, it, ja, ko, nl, pl, pt-PT, ro, ru, tr, uk, zh-Hans
S = {
"tour_vault_title": T("Your private vault", "Dein privater Tresor", "خزنتك الخاصة", "Tu caja fuerte privada", "Votre coffre-fort privé", "La tua cassaforte privata", "あなたのプライベート保管庫", "나만의 개인 금고", "Je privékluis", "Twój prywatny sejf", "O seu cofre privado", "Seiful tău privat", "Ваш личный сейф", "Özel kasan", "Ваш особистий сейф", "你的私密保险箱"),
"tour_vault_text": T(
 "Hold “PhotoMaid” at the top for 2 seconds to open the vault – the dial in the “o” turns. Set it up and find more options in Settings.",
 "Halte oben „PhotoMaid“ 2 Sekunden gedrückt, um den Tresor zu öffnen – das Rad im „o“ dreht sich dabei. Einrichten und weitere Optionen findest du in den Einstellungen.",
 "اضغط مطولًا على «PhotoMaid» في الأعلى لمدة ثانيتين لفتح الخزنة – يدور القرص داخل حرف «o». الإعداد والمزيد من الخيارات في الإعدادات.",
 "Mantén pulsado «PhotoMaid» arriba durante 2 segundos para abrir la caja fuerte; el dial de la «o» gira. Configúrala y encuentra más opciones en Ajustes.",
 "Maintenez « PhotoMaid » en haut pendant 2 secondes pour ouvrir le coffre – le cadran du « o » tourne. Configuration et autres options dans Paramètres.",
 "Tieni premuto «PhotoMaid» in alto per 2 secondi per aprire la cassaforte: la manopola nella «o» gira. Configurazione e altre opzioni in Impostazioni.",
 "上部の「PhotoMaid」を2秒間長押しすると保管庫が開き、「o」のダイヤルが回ります。設定やその他のオプションは「設定」にあります。",
 "위쪽의 ‘PhotoMaid’를 2초 동안 길게 누르면 금고가 열리고 ‘o’ 안의 다이얼이 돌아가요. 설정과 추가 옵션은 설정에 있어요.",
 "Houd bovenaan ‘PhotoMaid’ 2 seconden ingedrukt om de kluis te openen – de draaischijf in de ‘o’ draait mee. Instellen en meer opties vind je in Instellingen.",
 "Przytrzymaj „PhotoMaid” u góry przez 2 sekundy, aby otworzyć sejf – pokrętło w „o” się obraca. Konfiguracja i więcej opcji w Ustawieniach.",
 "Mantenha premido «PhotoMaid» no topo durante 2 segundos para abrir o cofre – o marcador no «o» roda. Configuração e mais opções em Definições.",
 "Ține apăsat „PhotoMaid” sus timp de 2 secunde ca să deschizi seiful – discul din „o” se rotește. Configurarea și alte opțiuni sunt în Setări.",
 "Удерживайте «PhotoMaid» вверху 2 секунды, чтобы открыть сейф, — диск в букве «o» повернётся. Настройка и другие параметры — в Настройках.",
 "Kasayı açmak için üstteki “PhotoMaid” yazısına 2 saniye basılı tut – “o” harfindeki kadran döner. Kurulum ve diğer seçenekler Ayarlar’da.",
 "Утримуйте «PhotoMaid» угорі 2 секунди, щоб відкрити сейф, — диск у літері «o» повернеться. Налаштування та інші параметри — у Налаштуваннях.",
 "按住顶部的“PhotoMaid”2 秒即可打开保险箱，“o”中的转盘会随之转动。设置及更多选项请前往“设置”。"),
"tour_games_title": T("Need a break?", "Zeit für eine Pause?", "هل تحتاج إلى استراحة؟", "¿Te hace falta una pausa?", "Besoin d’une pause ?", "Ti serve una pausa?", "ひと休みしませんか？", "잠깐 쉬어 갈까요?", "Even pauze?", "Czas na przerwę?", "Precisa de uma pausa?", "Ai nevoie de o pauză?", "Нужна пауза?", "Mola zamanı mı?", "Потрібна пауза?", "需要休息一下吗？"),
"tour_games_text": T(
 "When you need a break from tidying up: play Pairs, Photo Snake or Foto Blocks with your own photos.",
 "Wenn du eine Pause vom Aufräumen brauchst: Spiel Paare, Foto-Snake oder Foto Blocks mit deinen eigenen Fotos.",
 "عندما تحتاج إلى استراحة من الترتيب: العب أزواج أو ثعبان الصور أو Foto Blocks بصورك الخاصة.",
 "Cuando necesites descansar de ordenar: juega a Parejas, Serpiente de fotos o Foto Blocks con tus propias fotos.",
 "Quand vous avez besoin d’une pause dans le tri : jouez à Paires, Serpent photo ou Foto Blocks avec vos propres photos.",
 "Quando ti serve una pausa dal riordino: gioca a Coppie, Snake fotografico o Foto Blocks con le tue foto.",
 "整理の合間にひと休みしたいときは、自分の写真でペア、フォトスネーク、Foto Blocksを遊べます。",
 "정리하다 쉬고 싶을 때는 내 사진으로 짝맞추기, 포토 스네이크, Foto Blocks를 즐겨 보세요.",
 "Als je even pauze nodig hebt van het opruimen: speel Paren, Foto-Snake of Foto Blocks met je eigen foto’s.",
 "Gdy potrzebujesz przerwy od porządków: zagraj w Pary, Foto-Snake lub Foto Blocks ze swoimi zdjęciami.",
 "Quando precisar de uma pausa da arrumação: jogue Pares, Serpente de fotos ou Foto Blocks com as suas fotografias.",
 "Când ai nevoie de o pauză de la ordonat: joacă Perechi, Șarpele foto sau Foto Blocks cu pozele tale.",
 "Когда захочется отдохнуть от уборки, играйте в Пары, Фото-змейку или Foto Blocks со своими фото.",
 "Temizliğe ara vermek istediğinde kendi fotoğraflarınla Çiftler, Fotoğraf yılanı veya Foto Blocks oyna.",
 "Коли захочеться відпочити від прибирання, грайте в Пари, Фото-змійку чи Foto Blocks зі своїми фото.",
 "想从整理中歇口气时，可以用自己的照片玩配对、照片贪吃蛇或 Foto Blocks。"),
}
