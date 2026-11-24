# Vidéo de la bêta : la nouvelle île et l'app iPhone

Plan de tournage du 24 novembre 2026, pour annoncer la `0.1.0-beta.1`. Le plan d'origine (`video.md`) reste la base : format vertical 9:16, compréhensible sans le son, Yumi qui vit plutôt qu'une liste de fonctions. Ici, deux nouveautés à montrer : **l'île toute neuve** et **Yumi sur l'iPhone, relié au Mac**.

## Préparer les deux appareils

- **Mac** : lancer la bêta en mode tournage. Rien de réel ne démarre, rien de personnel n'est lu.
  `open -n --env YUMI_STUDIO=1 build/release-0.1.0-beta.1/Yumi.app`
- **iPhone** (version installée depuis Xcode) : Réglages › App › « Mode tournage au prochain lancement », puis rouvrir l'app. Données fictives : Camille à 14 h, sport à 18 h 30, Paris 17°, la demande « pousser sur le serveur git ».
- Pour la scène de connexion, en vrai : sur l'iPhone, Mon Mac › « Maintenir pour délier », puis « Maintenir pour relier ». L'animation « C'est bon, on est connectés » se rejoue des deux côtés.
- Mettre l'iPhone en mode Ne pas déranger, batterie pleine, 9:41 si possible.

## Le Reel (25 à 30 secondes)

| Temps | Image | Texte à l'écran |
|---|---|---|
| 0 à 2 s | L'iPhone dans le noir : la Dynamic Island gonfle, deux yeux s'ouvrent (l'ouverture de l'app) | « Il se réveille. » |
| 2 à 4 s | « Bonjour Esteban », étoiles filantes, il tombe dans le rond du bas | « Sur ton iPhone. » |
| 4 à 7 s | Le Mac : l'île neuve, ses oreilles, puis elle s'ouvre au survol | « Et dans ton Mac. » |
| 7 à 10 s | Relier : les deux appareils se rapprochent, onde de choc, confettis sur l'île | « Les deux se parlent. » |
| 10 à 14 s | Claude Code demande `git push` : la Dynamic Island s'ouvre, Refuser / Autoriser, un toucher sur le vert | « Tes agents te demandent. Tu réponds de ta poche. » |
| 14 à 18 s | On touche Yumi, on lui parle, il répond (« Mon Mac · Claude Code » sous la réponse) | « Il réfléchit avec ton Claude Code. » |
| 18 à 21 s | Aujourd'hui en bento, Modifier : une carte passe en demi, une autre s'agrandit | « Ta journée, à ta façon. » |
| 21 à 24 s | La Météo : les ambiances défilent (pluie, neige, nuit…), Yumi avec son bonnet | « Il a son caractère. » |
| 24 à 27 s | Les widgets et l'écran verrouillé | « Partout où tu regardes. » |
| 27 à 30 s | Yumi en grand, clin d'œil | « Yumi bêta. Gratuit. » |

## Ce qui a été vérifié avant le tournage

- Builds Mac, App Store et iPhone sans avertissement ; 1102 tests au vert ; trois tests de l'île rendus insensibles à la lenteur des machines de GitHub.
- Chaque écran iPhone en mode tournage, en français et en anglais : Aujourd'hui (bento), Parler (historique), Agents, Agenda, Modules, Météo, Réglages, Yumi, Mon Mac, Mail, Notes, GitHub.
- La liaison réelle Mac ↔ iPhone avec la bêta notarisée, en production iCloud : « En ligne », le « bonjour » sur l'île, une question posée de l'iPhone et répondue par le Claude Code du Mac.
- La Dynamic Island : une demande ouverte (Refuser rouge, Autoriser vert), la journée, la température quand il n'y a rien d'autre.
- Les widgets : à revoir sur le téléphone (le petit restait gris au premier chargement) avant de les filmer.
- Le mode tournage n'affiche aucune donnée personnelle : adresse Gmail fictive, mémoire fictive.
