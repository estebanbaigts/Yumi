> Journal historique des décisions, en français. Pour la structure actuelle du code, voir [architecture.md](architecture.md). Les mentions de `ARCHITECTURE.md` renvoient à l'ancienne analyse du code d'origine, retirée du dépôt.

# Yumi : décisions et répartition du travail

Contrat partagé entre les trois sessions de travail. Lire aussi `ARCHITECTURE.md`. En cas de désaccord entre les deux, ce fichier fait foi.

## Origine du code

- Ce dépôt (`estebanbaigts/Yumi`) est le seul endroit où l'on travaille et où l'on pousse.
- Le code de départ est celui de l'application macOS de Coucou (MIT, Louis Raillé), importé dans `Yumi/` sans ses créations protégées : ni icônes, ni sons, ni médias, ni prototypes. Voir `ATTRIBUTION.md`.
- Le clone local de Coucou (`/Users/thewise/coucou`) sert uniquement de référence en lecture. On n'y modifie rien.
- `ARCHITECTURE.md` décrit Coucou tel qu'il était. Ses chemins `NotchBuddy/...` correspondent ici à `Yumi/...`.
- La première version de Yumi (moteur d'événements typé, sessions multiples, 26 tests) est conservée sur la branche `legacy-v0`. Elle pourra être reprise plus tard pour la gestion multi-session.

## Décisions

| Sujet | Décision |
|---|---|
| Nom de l'application | Yumi |
| Nom du personnage | Yumi |
| Design du personnage | Concept 4, « Le Slime Graphique » (`design/yumi/concepts-4-et-6.webp`, moitié gauche) |
| Cohabitation avec Coucou | Non. Yumi remplace Coucou : à l'installation des hooks, Yumi retire aussi les anciens hooks Coucou et NotchBuddy. |
| Target App Store | Plus tard. Le target et les blocs `#if APPSTORE` restent en place et doivent continuer à compiler, sans travail spécifique. |
| Windows et Linux | Plus tard. Le portage Windows de Coucou n'a pas été importé. |
| Identifiant de bundle | `app.yumi` (repris de la première version de Yumi). Target App Store : `app.yumi.appstore`. |
| Équipe de signature | `J5U6R6ZV6K` (Developer ID Application, Esteban Baigts, valable jusqu'au 18 décembre 2027). Les releases sont construites, signées et notarisées sur le Mac de l'auteur par `scripts/release.sh` (profil notarytool `yumi-notary`), à partir de la 0.1.0-beta.1. Le build Debug n'est pas signé et n'en a pas besoin. |

## Valeurs d'identité (à utiliser telles quelles)

| Élément | Valeur Coucou | Valeur Yumi |
|---|---|---|
| Nom du produit | `Coucou` | `Yumi` |
| Service Keychain | `fr.louisraille.NotchBuddy` | `app.yumi` |
| Dossier de support | `Application Support/NotchBuddy` | `Application Support/Yumi` |
| Socket | `nb.sock` | `yumi.sock` |
| Script de hook | `nb-hook` | `yumi-hook` |
| Script de hook App Store | `~/.claude/coucou/nb-hook` | `~/.claude/yumi/yumi-hook` |
| Dossier de logs | `Logs/NotchBuddy` | `Logs/Yumi` |
| Message de refus | `Denied from Coucou` | `Denied from Yumi` |
| Reconnaissance de ses propres hooks | sous-chaîne `NotchBuddy` ou `coucou` | égalité avec la commande exacte générée par Yumi |
| Hooks hérités à retirer | sans objet | toute commande contenant `NotchBuddy` ou `coucou` |

Le chemin du conteneur sandbox dans le script App Store doit être dérivé de l'identifiant de bundle, pas écrit en dur.

## Design de Yumi (concept 4)

Lecture de la planche, à traduire dans les trois moteurs de rendu (`BotEngine`, `GreetingCanvasView`, `UploadCanvasView`) :

- **Corps** : dôme noir, sommet arrondi, base plus large et presque plate. Ce n'est plus la superellipse symétrique de Mochi.
- **Yeux** : deux grands ovales blancs, pupille noire ronde avec un petit reflet blanc. Les pupilles portent le regard (elles suivent la souris).
- **Lumière de contour** : liseré dégradé bleu, violet, rose le long du bord, plus marqué en bas et sur les côtés.
- **Palette approximative** (relevée à l'œil, à ajuster) : noir `#0B0F1A`, indigo `#2A2A8C`, bleu `#5B8CFF`, violet rosé `#C77DFF`, blanc `#FFFFFF`.
- **Expressions de la planche** : neutre, heureux, curieux, concentré, réfléchi, sommeil, inquiet, confus, agacé, surpris, paniqué, clin d'œil. Elles passent par les paupières et la position des pupilles.
- **Poses** : saut, étirement, écrasement, secousse, célébration (petits bras), sommeil (aplati).

Deux contraintes propres à l'application, absentes de la planche :

1. **L'île est noire.** Un corps noir sur fond noir est invisible : la silhouette doit être portée par la lumière de contour et par les yeux, y compris en mode compact (diamètre 20 pt) et pour les mini-personnages (12 pt).
2. **La couleur d'état.** Mochi change la teinte de son corps selon l'état (bleu au travail, violet en réflexion, ambre pour une approbation, rouge en erreur, vert quand c'est fini). Pour Yumi, le corps reste noir et c'est la lumière de contour qui prend la couleur de l'état. Au repos, elle garde le dégradé bleu, violet, rose. Les mini-personnages des intégrations portent la couleur de leur marque sur le contour.

Correspondance proposée entre les états existants et les expressions de la planche :

| État ou émote du code | Expression Yumi |
|---|---|
| `idle` | neutre |
| `working` | concentré |
| `thinking` | réfléchi |
| `searching` | curieux |
| `approval` | surpris |
| `question` | curieux, tête penchée |
| `error` | inquiet |
| `finished`, émote `happy`, `proud` | heureux, pose célébrer |
| `ratelimit` | paniqué |
| `sleeping`, émote `yawn` | sommeil |
| `dizzy` | confus |
| émote `annoyed` | agacé |
| émote `wink` | clin d'œil |
| émote `love`, `surprised` | à dessiner dans le même style |

## Phase 3 : île repliée vivante, chat sans facture

La phase 2 est terminée et fusionnée : personnage, île et cœur sont dans `main`. La répartition des fichiers de la phase 2 reste valable. Deux chantiers, deux sessions.

Décisions prises en voyant l'app réelle :

- **Taille de l'île** : on garde celle de `main` (échelle 1,4 par rapport à la maquette). La maquette reste la référence pour les proportions et le mouvement, plus pour la taille.
- **L'approbation depuis la notch fonctionne** de bout en bout (testée le 1er octobre 2026 avec le script de hook).

### Chantier A, session Cœur : le chat passe par Claude Code

Aujourd'hui le chat appelle l'API avec une clé facturée à l'usage et ne sait que répondre par du texte. Il doit piloter le Claude Code installé sur le Mac : plus de facture à l'usage (l'abonnement de l'utilisateur), et la capacité d'agir (créer des fichiers, lancer des commandes, coder dans un dossier). Les demandes de permission passent par la notch, jamais contournées.

L'interface vue par l'île ne change pas : `ClaudeService.shared.chat(query:context:state:)`, `clearConversation()`, et les réponses dans `AppState.chatHistory`.

### Chantier B, sessions Cœur puis Île : l'île repliée montre ce qui est vivant

Le contrat `Contracts/ModuleTypes.swift` a gagné `ModuleSnapshot.live` (texte court, priorité, deux boutons au plus). Le cœur le renseigne, l'île repliée affiche le module vivant de plus haute priorité et ses boutons au survol. Priorités : quelqu'un attend une réponse, puis ce qui tourne (musique, focus), puis ce qui est bon à savoir (prochain rendez-vous).

### Chantier C, sessions Cœur puis Île : le chat en direct

Les chantiers A et B sont terminés et fusionnés. Le chat crée des fichiers et lance des commandes, mais on ne le voit pas faire : la réponse arrive d'un bloc. Le contrat `Contracts/ChatLive.swift` et `AppState.chatLive` décrivent la réponse en cours : le texte qui s'écrit mot à mot, l'action en cours (lit, écrit, lance) avec un aperçu, et les actions déjà faites. Le cœur le renseigne en continu, l'île l'affiche en direct, ouverte comme repliée.

Le dossier de travail du chat devient le dossier Téléchargements de l'utilisateur, pour que les fichiers créés y arrivent directement.

## Phase 4 : la nouvelle interface, par activités

La phase 3 est terminée et fusionnée (chat piloté par Claude Code et affiché en direct, île repliée vivante). L'interface de l'île a été jugée moins sérieuse que celle de Coucou et repensée. **La maquette de référence a changé** : `design/yumi/maquette/reference.html` est maintenant la version 13. Là où elle contredit le tableau « Décisions validées » plus haut, c'est elle qui fait foi. Le personnage ne change pas.

Ce qui change :

| Sujet | Nouvelle décision |
|---|---|
| Principe | L'île montre une seule activité à la fois, et chaque activité a sa propre mise en page. Plus de rangée de pastilles, plus de cartes, plus de légende sous Yumi, plus de second carré. |
| Boutons | Gros boutons ronds avec un symbole. Une permission se présente comme un appel entrant : rouge pour refuser, vert pour autoriser, « Toujours autoriser » en petit texte. |
| Activités dessinées | Agenda (un bouton rejoindre), agent au travail (durée et arrêter), alerte, terminé (la coche se dessine), erreur (relancer), musique (onde, barre de lecture, trois commandes), focus (gros chiffres, deux boutons). Les autres modules suivent un modèle commun : chiffre clé en couleur, une phrase, un bouton. |
| Barre du bas | Toujours là : la vue d'ensemble, une icône par module (celui à l'écran déplie son nom, un point signale ce qui est vivant, le nom apparaît en étiquette au survol), puis le chat et les réglages. |
| Vue « Tous » | Tous les modules sur deux colonnes : icône, nom complet, chiffre clé. C'est ce qui s'affiche quand on ouvre l'île et que rien n'est urgent. |
| Chat | Accessible par son icône dans la barre et par un clic sur Yumi. La réponse s'écrit en direct, l'action en cours s'affiche sous le texte. |
| Réglages dans l'île | Sons et volume, délai avant que l'île se replie (5 s, 15 s, 30 s, 1 min, jamais ; 15 s par défaut), ce que Yumi tient quand un agent travaille : Cigarette, Café, Matcha ou Aléatoire (un des trois, tiré à chaque fois qu'un agent se met au travail). La personne choisit entre café, cigarette et matcha au premier lancement, sous la question du prénom ; l'ancien interrupteur est repris (cigarette activée donne Cigarette, sinon Café), et tant que rien n'est choisi c'est Café. Ces réglages doivent réellement agir. |
| Île repliée | Yumi d'un côté de la notch, l'activité principale de l'autre. Une seconde activité vit dans une bulle qui se détache de l'île comme une goutte. |
| Lancement | Yumi seul, sans aucun texte : la goutte, les yeux dans le noir, l'ouverture, la lumière, le salut, le clin d'œil, le repli. Environ 4,5 secondes. |
| Départ | En quittant : il salue, clin d'œil, s'endort, sa lumière s'éteint comme elle s'était allumée, la goutte remonte dans la notch. |
| Typographie | Police du système pour le texte ; la police ronde est réservée aux gros chiffres. |
| Taille | Les proportions de la maquette, à l'échelle déjà retenue dans l'app. |

Contrats ajoutés sur `main` pour cette phase :

- `Contracts/ModuleTypes.swift` : `symbol` (icône du module), `primarySymbol` et `secondarySymbol` (symboles des boutons ronds), `progress` (barre de lecture ou de minuteur).
- `Contracts/AppLifecycle.swift` : `yumiQuitRequested` et `yumiQuitReady`, pour jouer l'animation de départ avant la fin de l'app.

Deux sessions : Cœur renseigne les nouveaux champs et retarde la fin de l'app ; Île porte la maquette.

## Phase 5 : un compagnon, pas un tableau de bord

La phase 4 est terminée et fusionnée (interface par activités). Yumi a un corps de compagnon et un cerveau d'indicateur d'état. Priorité : qu'il connaisse la personne, se souvienne, et parle avec sa propre voix. La référence est `design/yumi/voix.md`.

- **La voix** : tout ce que Yumi dit est réécrit selon la fiche. Les libellés très courts restent neutres.
- **La mémoire** : il retient de lui-même, dans un fichier local lisible. Contrat `Contracts/MemoryTypes.swift`, `AppState.memory` et `AppState.userName`. Le cœur tient la mémoire, l'île la montre et permet de la corriger ou de l'effacer.
- **Le prénom** est demandé au premier lancement, jamais écrit en dur.

Viendront ensuite, dans cet ordre : l'initiative (il parle le premier, rarement et à propos, avec un réglage de discrétion), puis le lien entre les modules (une phrase qui résume la situation).

## Phase 6 : l'initiative

La mémoire et la voix sont en place et fusionnées. Yumi doit maintenant parler le premier, rarement et à propos. La référence est la section « Quand il parle le premier » de `design/yumi/voix.md`.

Contrat `Contracts/RemarkTypes.swift` et `AppState.remark` : le cœur décide quand et quoi dire, l'île l'affiche près de Yumi, replié comme ouvert, et rapporte si la personne a répondu ou ignoré. Le réglage de discrétion (silencieux, discret, bavard) se trouve dans les réglages de l'île.

Reste ensuite le lien entre les modules, et un défaut connu de la mémoire : le résumé de fin de conversation répète parfois un souvenir déjà noté.

## Phase 7 : GitHub en scènes, et le processeur en usage réel

L'initiative et la baisse du processeur au repos sont fusionnées. Deux sujets.

**GitHub.** Un vrai module GitHub, et une petite scène de Yumi pour chaque événement : étoile, fork, pull request ouverte, fusion, push, commit, issue, release, nouvel abonné. Contrat `Contracts/EventAnimations.swift` : un module poste `yumiScene`, le personnage joue la scène une fois. Le cœur détecte les événements et fait dire à Yumi une phrase quand ça compte ; l'île dessine l'activité GitHub.

**Le processeur en usage réel.** Mesuré le 2 octobre en Release : au repos complet, 6,7 % île repliée et 0,6 % île masquée. Mais avec de la musique en lecture et des sessions Claude actives, donc en usage normal, l'app reste entre 12 et 23 %, parce que les habitudes animées (casque, cigarette) tournent à pleine cadence. C'est le prochain objectif : une habitude qui dure ne doit pas coûter plus de 5 %.

## Phase 2 : porter la maquette, répartition des fichiers

Trois sessions en parallèle. Un fichier n'appartient qu'à une seule session. Les fichiers Swift sont dans `Yumi/Sources/App/`. Chaque session peut créer de nouveaux fichiers dans son propre sous-dossier.

| Session | Branche | Fichiers possédés |
|---|---|---|
| Personnage | `yumi/personnage` | `BotEngine.swift`, `BotCanvasView.swift`, nouveau dossier `Character/` |
| Île | `yumi/ile` | `IslandRootView.swift`, `IslandViewContent.swift`, `IslandTypes.swift`, `IslandWindowController.swift`, `IslandStateMachine.swift` et ses tests, `GreetingCanvasView.swift`, `UploadCanvasView.swift`, `UploadSequenceEngine.swift`, `FileDropView.swift`, `SettingsView.swift`, `SoundEngine.swift`, nouveau dossier `Island/` |
| Cœur | `yumi/coeur` | `AppState.swift`, `AppDelegate.swift`, `AppIdentity.swift`, `HookServer.swift`, `ClaudeService.swift`, `WindowContextCapture.swift`, tous les `*Poller.swift`, `Yumi/project.yml`, nouveaux dossiers `Core/` et `Modules/`, nouveaux fichiers de tests |

### Les contrats entre sessions

Deux fichiers dans `Contracts/` sont déjà sur `main` et servent d'interface. **Personne ne les modifie pendant le travail en parallèle** ; si un contrat doit changer, on s'arrête et on le décide ensemble.

- `Contracts/CharacterCommands.swift` : l'île commande le personnage par notifications (`yumiPose`, `yumiHabit`, `yumiMood`, `yumiRim`, `yumiLit`, `yumiGaze`). La session Personnage les écoute, la session Île les émet. L'île ne touche jamais au moteur du personnage, et le place où elle veut à la taille qu'elle veut avec `BotCanvasView`.
- `Contracts/ModuleTypes.swift` : le cœur remplit `AppState.modules` avec des `ModuleSnapshot`, l'île les dessine. Les cinq premiers vont dans l'île, les suivants dans le second carré. L'île signale un clic par la notification `moduleAction`. `AppState.modules` contient des données d'exemple tant que le cœur ne les remplace pas.

- `ModuleSnapshot.rows` (ajouté le 3 octobre 2026, décision de la coordination) : une liste facultative de `ModuleRow` (id, titre, détail, état, libellé, date, section, action), vide par défaut pour les modules qui n'en ont pas. Le module la donne déjà triée ; l'île la dessine sous l'activité. Un clic sur une ligne qui a une `action` poste `moduleRowAction` avec `["module": id, "row": action]`, et le module l'écoute lui-même. Les états (`neutral`, `busy`, `waiting`, `success`, `failure`) laissent la couleur à l'île.

### Premiers modules réels

Claude Code, Agenda, Notes et rappels, Focus, Musique, Météo. Ils se branchent sur le Mac sans compte externe. Notion, n8n, Make et ChatGPT viennent ensuite.

### La maquette est la source

`design/yumi/maquette/reference.html` contient les formules exactes : le contour du corps (`bodyPath`), les ressorts et leurs constantes (`Blob`), chaque pose (`POSE_FX`), chaque habitude (`SCENES`), les visages (`MOODS`), les couleurs de liseré (`RIMS`), les places de Yumi (`SEATS`) et la chronologie du lancement (`launch`). On porte ces valeurs, on ne les réinvente pas.

## Règles communes

- Le `.xcodeproj` et les `Info.plist` sont générés : lancer `cd Yumi && xcodegen` avant de compiler, ne jamais les éditer.
- Compiler en Debug avant chaque commit : `cd Yumi && xcodegen && xcodebuild -scheme Yumi -configuration Debug build`.
- État de référence : le build Debug réussit sur `main` avec 19 avertissements (concurrence et API dépréciées). Ne pas en ajouter.
- Chaque session pousse sur sa propre branche, jamais sur `main`.
- Quand un rendu est porté, le comparer à la maquette ouverte dans un navigateur.
- Ne jamais copier d'icône, de son ou de média depuis Coucou : le dépôt est public.
- Conserver `LICENSE` avec le copyright d'origine.

## Direction produit et maquette de référence

Yumi est un compagnon généraliste, pour le travail comme pour la vie. Trois gestes le définissent : il veille (il ne se manifeste que quand on est concerné), il reçoit (un fichier, une fenêtre, une phrase), il répond (sur place).

La maquette validée est `design/yumi/maquette/reference.html` (à ouvrir dans un navigateur). C'est la référence visuelle et de mouvement pour le portage en Swift. Les essais intermédiaires restent dans l'historique git (supprimés le 3 octobre 2026).

Décisions validées sur cette maquette :

| Sujet | Décision |
|---|---|
| Taille | Île ouverte de 480 points de large, aussi basse que le contenu le permet (environ 150). |
| Mise en page | Yumi à gauche, une seule information à droite, trois boutons (accueil, parler, déposer). |
| Modules | Catalogue de 40, dix au plus. Les cinq premiers dans l'île, les autres dans un second carré détaché sous l'île. |
| Apparence des modules | Par leur nom en toutes lettres, précédé de leur couleur. Pas d'abréviations. |
| Corps | Souple : hauteur et inclinaison sont des ressorts, le contour est recalculé à chaque image. Corps de la couleur exacte de l'île. |
| Volume | Les yeux sont posés sur une sphère (la tête tourne), reflet et éclat mobiles, lumière qui déborde à l'intérieur du contour. |
| État | Porté par la couleur du liseré, jamais par le corps. |
| Poses | Saut, étirer, s'écraser, secouer, célébrer. |
| Habitudes | Clope (agent au travail), épuisé, café, casque (musique), lunettes (réussite), nuage (erreur), sifflote (attente), dodo (inactif), matcha (agent au travail, au choix). Quand un agent travaille, la personne choisit cigarette, café ou matcha : la cigarette peut donc être écartée. |
| Lancement | Une goutte sous la notch, deux yeux endormis dans le noir, ils s'ouvrent et regardent autour, l'île s'ouvre, la lumière s'allume et le contour se dessine, salut, nom, modules, clin d'œil, repli. Environ 5 secondes. |
| Débordement | Yumi est dessiné au-dessus de l'île : gouttes, fumée et poses peuvent dépasser sur les côtés et en bas, jamais au-dessus du bord supérieur de l'écran. |
| Langue et ton | Interface en français, Yumi tutoie et parle court. |

Conséquence pour le code : les sept intégrations câblées en dur et la tâche Claude unique doivent laisser la place à un système de modules. Le moteur d'événements typé de la branche `legacy-v0` est la fondation prévue.

## État de `main` au 3 octobre 2026 (stabilisation avant 0.1.0-alpha)

Les sections par branche plus bas sont un journal : en cas de doute, cette section et le code font foi.

| Sujet | État réel |
|---|---|
| Chemin d'une action | Message du chat → `AgentRequest` (mots, six derniers échanges, snapshot gardé sur le Mac) → `LLMAgentPlanner` (Claude Code sans outil, sinon clé Anthropic) → `PlanProposal` → `PlanValidator` → `ChatRoute` → `AgentExecutor` (revalidation, `check`, `PermissionManager.evaluate` pour chaque étape, exécution avec délai, contrôle de la sortie) → `verify` de chaque outil → `AgentResult` → `AgentLook` dans le chat. |
| Outils (build direct) | `get_current_time`, `get_current_context`, `create_file`, `append_to_file`, `add_reminder`, `add_event`, `start_focus`, `get_today`. Plafond `write`. |
| Outils (build App Store) | `get_current_time`, `get_current_context` seulement, plafond `read`, planification par clé API seulement. Une demande d'action y est refusée sans liste d'outils qu'il n'a pas. |
| Chat | Claude Code avec `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch` seulement ; `Bash`, `Edit`, `Write`, `NotebookEdit`, `Task` refusés, toute demande d'outil qui écrit est refusée sans être montrée. Ses demandes de permission (lecture hors du dossier, web) sont répondues dans la file de l'île, pas décidées par `LocalPermissionManager`, mais chacune est écrite dans le même historique (`ChatPermissionAudit`, outil `chat:WebFetch`…) : autorisée, refusée, expirée, bloquée ou annulée, avec le fichier (depuis `~`) ou l'hôte seulement, jamais la recherche ni le reste de l'adresse. |
| Demande d'accord | Le délai de 60 s part quand la demande est à l'écran (`ApprovalPresenter.present(_:shown:answer:)`), 10 min au plus en file. `create_file` montre le contenu du fichier : les cinq premières lignes puis « … et N lignes de plus », le nombre de lignes et de caractères dans les détails. Une étape qui écrit un texte n'est jamais regroupée avec d'autres : chaque texte est lu avant d'accepter. |
| Ce qui ne s'exécute jamais | Une étape refusée, expirée ou annulée ; un outil inconnu ou au-dessus du plafond ; un outil qui écrit après un délai dépassé (pas de deuxième essai) ; une course dont la vérification échoue est un échec. |
| Processeur (build Debug optimisé, mode studio, 20 s par état) | Repliée au repos 10,7 %, repliée avec musique 11,4 %, compacte au travail 8,2 %, ouverte 10,2 %, session Claude Code 12,8 %, lignes Claude Code 12,2 %, GitHub 6,3 %, module musique 7,7 %, habitude casque 8,6 %, fumée 8,4 %, sommeil profond 1,1 %, chat en direct 21,7 % (seulement pendant qu'une réponse arrive), approbation 13,0 % (20,6 % avant plafonnement). Cachée : 0 % (mesuré sur la copie installée ; le mode studio ne cache jamais l'île). Une approbation en attente tourne désormais à 30 images par seconde hors mouvement : seul le halo pulse, sur 1,1 s. |
| Connu, non corrigé | Un message envoyé pendant une course de l'agent va directement au chat (qui ne peut rien changer). |

## État au 1er octobre 2026

Les trois branches ont été fusionnées dans `main` et les renommages internes sont faits (`YumiApp`, `YumiConst`, `yumiPath`, `drawYumi`, état `.greeting`, préfixe de notifications `yumi.`). Les seules mentions restantes de Coucou dans le code sont les marqueurs des anciens hooks à retirer.

Vérifié sur `main` : build Debug, 26 tests de la machine d'état, build du target App Store, script de hook et socket Yumi de bout en bout.

Les branches `yumi/identite`, `yumi/personnage` et `yumi/build-docs` restent ouvertes et alignées sur `main` : on continue à y travailler, et `main` ne reçoit que du code vérifié. La répartition des fichiers ci-dessus reste valable tant que les trois sessions travaillent en parallèle.

Reste à faire : recette manuelle complète dans la notch (étape 7 de `ARCHITECTURE.md`), sons définitifs (les 28 actuels sont synthétisés et provisoires), équipe de signature, puis les sujets hors migration listés à la fin de `ARCHITECTURE.md`.

## Cœur : moteur et modules (branche `yumi/coeur`)

Le chemin d'un événement : script de hook, socket, `ClaudeHookTranslator`, `EventEngine`, `SessionStore`, puis les modules et la pastille Claude Code. `Core/` et `Modules/` ne dépendent ni des vues, ni d'`AppState`, ni des sons : ils sont compilés tels quels dans les tests.

| Sujet | État |
|---|---|
| `AppState.modules` | Rempli par `ModuleRegistry`, un snapshot par module sélectionné, dans l'ordre de sélection. Les cinq premiers vont dans l'île. La sélection est persistée sous la clé `selectedModules`. |
| Modules livrés | `claude-code`, `agenda`, `notes`, `focus`, `music`, `weather`. Ce sont aussi les modules sélectionnés au premier lancement. |
| `moduleAction` | Reçue par le registre, transmise au module (`primary` ou `secondary`). |
| Claude Code | Tous les terminaux, plusieurs sessions. La pastille `integration_claude` montre la session qui attend une réponse, sinon la dernière active. |
| Approbations | Une file : une demande par session, la plus ancienne à l'écran. Repli vers le terminal après 115 s, ou dès que le script de hook disparaît. |
| Script de hook | Protocole 2 : le script attend un accusé de réception 2 s avant d'attendre la décision. Une app figée ne retient plus Claude Code. Les scripts plus anciens restent acceptés. |
| Permissions | Jamais demandées au lancement, seulement au clic sur le bouton du module. Textes en français dans `project.yml`, entitlements calendrier et position dans `Resources/`. |
| Météo | Open-Meteo, sans clé. Position arrondie au kilomètre, ou ville fixée par la préférence `weatherCity`. |
| Notes | Fichier texte `notes.txt` dans le dossier de support. « Nouvelle note » enregistre le presse-papiers tant que l'île n'a pas de champ de saisie. |
| Pollers hérités | Retirés (branche `yumi/menage`). |

Reste à faire côté île : dessiner `AppState.modules`, remplacer les « VS Code » écrits en dur par le nom de la pastille, proposer le choix des modules et la ville de la météo dans les réglages. Reste à vérifier à la main : Musique et Spotify en lecture, Agenda et rappels après autorisation, Météo par localisation, boutons Deny et Always.

## Cœur, phase 3 : île repliée et chat par Claude Code

| Sujet | État |
|---|---|
| `ModuleSnapshot.live` | Claude Code : attention quand une session attend. Musique : activité en lecture, puis cinq minutes plus discrètement après une pause. Focus : activité pendant le décompte. Agenda : prochain rendez-vous du jour. Notes : seulement un rappel en retard. Météo : rien. |
| Boutons « Voir » | Tous vont là où se trouve la discussion : l'application dans laquelle tourne la session (son terminal, son éditeur ouvert sur le projet, ou l'app Claude). VS Code ne s'ouvre que si la session y tourne. Une approbation en attente se traite dans l'île. Les cartes de l'île passent par `ClaudeTaskMirror.openSession()`. |
| Chat | Un processus `claude -p` par message, entrée et sortie en `stream-json`, session reprise par `--resume`. Dossier de travail : Téléchargements, modifiable par la préférence `chatFolder`. Sans Claude Code : l'API si une clé existe. Build App Store : toujours l'API. |
| Permissions du chat | En mode `-p` simple, Claude Code n'appelle jamais le hook `PermissionRequest` et refuse l'outil. Le mécanisme prévu pour un programme hôte est `--permission-prompt-tool stdio` : la demande arrive sur la sortie du processus (`control_request`), la réponse repart sur son entrée. Yumi l'affiche dans la même file d'approbations que les autres sessions. Les hooks de la session du chat sont ignorés pour ne pas la compter deux fois. Aucune option qui saute les permissions, mode `default` imposé. |
| « Toujours » dans le chat | N'applique que les règles proposées pour ce qui est affiché, jamais un changement de mode ni l'ouverture d'un dossier. |
| Fichier joint | Seul le dossier `inbox` de Yumi est ouvert en lecture au chat. |

Reste à faire côté île : afficher l'état `working` dans la vue du chat (elle ne connaît que `thinking`), montrer la commande entière d'une approbation (une seule ligne tronquée aujourd'hui), distinguer les lignes d'action des réponses.

## Cœur, chantier C : le chat en direct

| Sujet | État |
|---|---|
| `AppState.chatLive` | Renseigné pendant toute la réponse, remis à `nil` à la fin (réponse ajoutée à `chatHistory`, erreur, ou annulation). Dix mises à jour par seconde au plus. |
| `text` | Grandit mot à mot (messages partiels de Claude Code). Repart de zéro à chaque nouveau message de la même réponse : entre deux actions, c'est la phrase en cours qui s'affiche. |
| `activity` | Apparaît dès que l'outil est nommé (« Écrit un fichier »), puis se précise (« Écrit bonjour.txt »). En attente de permission : `kind` vaut `waiting`, libellé « Attend ton accord », `detail` = ce qui est demandé. Si plusieurs actions sont annoncées ensemble, celle qui attend passe devant, sinon la plus ancienne. |
| `detail` | Quatre lignes de 80 caractères au plus : le début du fichier écrit ou du texte modifié, les dernières lignes affichées par une commande terminée. |
| `done` | Une entrée par action finie, `succeeded` faux si elle a échoué ou a été refusée. |
| Île repliée | Le module Claude Code annonce l'action du chat dans `live` (priorité activité, attention pendant une attente de permission). Une session qui attend l'utilisateur reste devant. Rien quand le chat est au repos. |
| Historique | Les lignes d'action (« Fichier créé : … ») sont toujours ajoutées à `chatHistory` : à l'île de choisir entre elles et `done` pendant la réponse. |
| Dossier du chat | Téléchargements par défaut. Un ancien `~/Documents/Yumi` n'est ni déplacé ni supprimé. |

## Cœur, phase 4 : champs de l'interface par activités

| Sujet | État |
|---|---|
| `symbol` | Claude Code `terminal.fill`, Agenda `calendar`, Notes `note.text`, Focus `timer`, Musique `music.note`, Météo selon le ciel (`sun.max.fill`, `cloud.rain.fill`…, `cloud.sun.fill` tant que le temps n'est pas connu). |
| `primarySymbol`, `secondarySymbol` | Déduits du libellé du bouton par une table unique (`Modules/ModuleSymbols.swift`) : chaque libellé a son symbole, `secondarySymbol` est nil quand il n'y a pas de second bouton. |
| `progress` | Focus : avancement de la phase en cours (temps écoulé à gauche, durée de la phase à droite), figé en pause. Musique : position dans le morceau, republiée chaque seconde pendant la lecture. nil ailleurs, et nil pour la musique tant que la durée ou la position ne sont pas connues. |
| Position de la musique | Spotify l'annonce. Pour Musique, elle est demandée au lecteur si l'automatisation est déjà accordée, sinon comptée depuis le début du morceau et figée en pause : elle peut dériver si l'utilisateur déplace la tête de lecture. |
| Départ | `applicationShouldTerminate` annule la fin, poste `yumiQuitRequested`, et termine à la réception de `yumiQuitReady`, après six secondes au plus, ou tout de suite si l'utilisateur quitte une seconde fois. Une fermeture de session, un redémarrage ou une extinction ne sont jamais retardés. |
| Historique du chat | Tout le texte est gardé dans l'ordre : le texte écrit avant une action entre dans `chatHistory` au moment où l'action commence, puis la ligne d'action, puis la suite. `chatLive.text` repart alors de zéro pour ne pas l'afficher deux fois. |

## Cœur, phase 5 : mémoire et voix

| Sujet | État |
|---|---|
| Fichier | `memoire.md` dans le dossier de support de Yumi : Markdown lisible, un prénom puis trois rubriques (Toi, Tes projets, Le fil). Écrit par fichier temporaire, lisible par l'utilisateur seul. Modifiable à la main : il est relu au lancement. |
| `AppState.memory`, `AppState.userName` | Tenus à jour par `Memory/MemoryStore`, qui répond à `memorySetName`, `memoryEdit`, `memoryDelete` et `memoryClear`. |
| Limite | 120 souvenirs. Au-delà, les plus anciens du fil partent d'abord, puis les plus anciens sur les projets ; jamais ceux sur la personne. |
| Apprentissage | C'est la conversation qui trie : elle termine sa réponse par un bloc `<memoire>` que la personne ne voit jamais (ni dans l'historique ni dans `chatLive`). « Oublie ça » retire le souvenir par son identifiant. Un prénom donné dans le chat va dans `userName` (ligne « prénom | … »), pas dans un souvenir. Aucun tiret long, ni dans les réponses ni dans les souvenirs : la consigne le demande et l'app les remplace. Fichier ou fenêtre montrés : elle retient de quoi il s'agissait. |
| Résumé de fin | Quand une conversation d'au moins une réponse se termine (`clearConversation`), elle est résumée en quelques lignes dans le fil. Le résumé reçoit la consigne complète, et ses lignes vont au fil quel que soit le mot qui les commence. Pas de résumé quand on quitte l'app. |
| Filtre | `MemoryGuard` passe sur chaque phrase avant écriture, quelle que soit la décision de la conversation : mot de passe, clé, code, numéro de carte ou de compte, texte plus long qu'une phrase. L'interdit « information sur une autre personne » ne peut pas être garanti par du code : il repose sur la consigne donnée à la conversation. |
| Se souvenir | Chaque message part avec le prénom, tout ce qui concerne la personne et ses projets, et les quinze derniers souvenirs du fil. |
| Voix | Consigne du chat réécrite d'après `design/yumi/voix.md`. Titres, sous-titres, attentes et erreurs des modules réécrits à la première personne ; noms de modules, chiffres clés et boutons restent neutres. `Tests/Modules/VoiceTests.swift` échoue si une formule interdite ou un emoji apparaît. |
| Libellés du chat en direct | À la première personne : « J'écris bonjour.txt », « Je lance swift test », « J'attends ton accord ». |
| Textes de permission | Réécrits à la première personne dans `project.yml`. |

## Cœur, phase 6 : l'initiative

| Sujet | État |
|---|---|
| Moteur | `Initiative/InitiativeEngine` (pur) : une occasion et son contexte entrent, une `YumiRemark` sort, ou rien. `InitiativeWatch` (pur) reconnaît les occasions, `InitiativeDriver` écoute le Mac et pose `AppState.remark`. |
| Occasions | Premier réveil du jour, retour après trente minutes d'absence, deux heures sans pause (puis toutes les deux heures), tâche d'agent de dix minutes ou plus qui se termine, rendez-vous à dix minutes ou moins pendant qu'un agent attend, 23 h 30, batterie à 15 % ou moins sans chargeur, vendredi 18 h. Trois formulations au moins par occasion, écrites à l'avance. |
| Garde-fous | Jamais pendant un focus, un partage d'écran, une présentation, Ne pas déranger. Vingt minutes entre deux remarques, sauf si quelqu'un attend. Un sujet ignoré trois fois de suite est abandonné trois jours. Jamais la même phrase deux jours de suite. |
| Réglage | `YumiTalk` lu à chaque remarque : silencieux rien ; discret ce qui compte, quatre par jour au plus ; bavard ajoute bonjours et encouragements, dix par jour au plus. |
| Remarque | Posée dans `AppState.remark`, retirée à la fin de sa durée (comptée comme ignorée), à `remarkAccepted` ou à `remarkDismissed`. Une seule à la fois. |
| Actions | « Pause » lance une pause de cinq minutes dans le module Focus. « Voir » amène devant l'application de la session de l'agent. |
| Coût au repos | Aucun minuteur répétitif : le pilote réagit aux notifications du système (réveil, verrouillage, batterie) et aux événements de session, et dort jusqu'au prochain moment exact (deux heures, 23 h 30, vendredi 18 h, dix minutes avant un rendez-vous). |
| Limites | Ne pas déranger : lu dans un fichier du système, illisible dans le bac à sable (réponse « non »). Partage d'écran : appel du serveur de fenêtres absent des en-têtes publics, non utilisé dans le build App Store. Présentation : écran recopié, ou diaporama Keynote ou PowerPoint. Sans accès au calendrier, le bonjour ne parle pas de la journée. |

## Cœur, phase 7 : le module GitHub

| Sujet | État |
|---|---|
| Module | `Modules/GitHub`, identifiant `github`. Il remplace `GithubPoller` (supprimé) et rejoint une fois la sélection des installations existantes. |
| Jeton | Jeton personnel lu dans le trousseau sous la clé `github-token`. Sans jeton : « Je ne vois pas ton GitHub. », bouton « Brancher » qui ouvre les réglages. L'action `secondary` de `moduleAction` fait relire le jeton tout de suite. |
| Ce qu'il suit | Étoile, fork, pull request ouverte, fusion, push, issue, release (flux `events` et `received_events` de la personne, limités à ses dépôts pour ce que font les autres) ; nouvel abonné (compteur de `/user`). Le commit local vient des sessions Claude Code (une commande `git commit` qui se termine), sans surveiller le disque. |
| Quota | Chaque requête porte l'`ETag` de la réponse précédente : un flux inchangé ne coûte rien. Les flux sont relus toutes les 60 s au plus tôt, ou moins souvent si `X-Poll-Interval` le demande ; dépôts, abonnés et relectures une fois sur cinq. Quota épuisé : attente jusqu'à l'heure donnée par GitHub. |
| Scènes | `yumiScene` à chaque événement nouveau, une par type, avec `count` quand plusieurs arrivent ensemble. Le premier regard sert de référence : l'historique n'est jamais rejoué. Ce qui a été vu est gardé entre deux lancements. |
| Snapshot | `status` : « étoiles · forks · pull requests ouvertes » du dépôt le plus actif. `subtitle` : le dépôt. `title` : le dernier événement en une phrase. « Ouvrir » ouvre le dépôt. Une pull request qui attend une relecture passe devant : `needsAttention`, bouton « Relire », `live` en priorité attention. |
| Parole | Étoile, fork, fusion et release passent par le moteur d'initiative (`Occasion.repository`), avec tous ses garde-fous. Un mot au plus par lot d'événements. |

## Cœur : mode tournage

`YUMI_STUDIO=1` au lancement, dans tous les builds (Release compris). Rien de réel ne démarre : ni serveur de hooks, ni modules, ni mémoire, ni initiative, ni chat, ni pollers. Le trousseau n'est ni lu ni écrit, le dossier de Yumi non plus, et aucune permission ne peut être demandée par le cœur. `AppState` reste entièrement à la main de l'île, qui sait qu'on tourne par `AppState.isStudio` (ou `StudioMode.isOn`). `ClaudeService.chat` ne fait rien dans ce mode : à l'île de mettre en scène `chatHistory` et `chatLive`.

Reste côté île : le dépôt d'un fichier copie encore dans le dossier `inbox` de Yumi (`FileDropView`).

## Cœur : le Context Engine (branche `yumi/contexte`)

Première fondation de l'intelligence : Yumi sait ce que la personne fait sur son Mac, sans pouvoir agir dessus. `Context/` suit la règle de `Core/` : ni vue, ni `AppState`, ni son, compilé tel quel dans les tests.

| Sujet | État |
|---|---|
| Ce qu'il sait | Application au premier plan et depuis quand, application précédente, applications récentes, fenêtre au premier plan (titre, fichier montré), durée de la session, événements récents, part du temps récent par catégorie d'application (`LSApplicationCategoryType` lu dans chaque application, rien d'écrit en dur). |
| Événements | `ContextMessage.event` : `sessionStarted`, `sessionEnded`, `applicationChanged`, `windowChanged`, lancement et fermeture d'application, veille, réveil, verrouillage, changement d'utilisateur, permission. Puis `contextUpdated` avec le nouveau `ContextSnapshot`. Abonnement par `ContextEngine.messages()` (`AsyncStream`), moteur `@Observable`. |
| Session | Commence au démarrage du moteur, au réveil ou au déverrouillage ; finit à la veille, au verrouillage, à l'extinction des écrans. Un réveil sur écran verrouillé ne compte pas. Le temps d'absence n'est pas compté comme temps passé dans l'application. |
| Déduplication | La même application ou la même fenêtre signalée deux fois ne produit rien ; un signal système répété non plus ; une fenêtre d'une application qui n'est plus devant est ignorée. |
| Historique | En mémoire seulement : 300 événements et 4 heures au plus. Couper le moteur efface tout. |
| Coût | Aucune boucle : notifications de `NSWorkspace`, notifications distribuées du système, et notifications d'accessibilité de l'application au premier plan. Un seul minuteur ponctuel ramène Yumi de `contextChanged` à `observing`. |
| Permissions | Aucune n'est demandée. Le titre des fenêtres n'est lu que si l'Accessibilité est déjà accordée (`AXIsProcessTrusted`, sans invite) ; le changement de permission est suivi. Pas d'enregistrement d'écran. Build App Store : pas de fenêtre. |
| Désactivation | Réglages, section Context : interrupteur persisté sous `contextEngineEnabled`. Mode tournage : le moteur ne démarre pas (`LaunchPlan.context`). |
| Personnage | `ContextPresence` : `idle`, `observing`, `contextChanged`. Quand l'application change, île repliée et rien d'autre en cours, Yumi jette un coup d'œil vers le bas puis reprend le pointeur. Rien de plus : pas d'action, pas de remarque. |
| Confidentialité | Pas de capture d'écran, pas de frappes, rien envoyé à un modèle ni ailleurs. `ClaudeService` joint le snapshot aux demandes d'action du chat pour les outils, sans jamais le montrer au planificateur ; seule la section Agent des réglages peut l'envoyer, case cochée. |

Prochaines étapes possibles : providers de facettes (`ContextFacet` : écran, presse-papiers, fichiers, navigateur, calendrier, git, projet), puis un lien vers l'initiative et le chat, chacun derrière son propre réglage.

## Cœur : l'Agent Runtime (branche `yumi/agent`)

Le cerveau de Yumi, pas encore ses mains : une intention entre, un plan vérifié sort, des étapes s'exécutent sous contrôle, un `AgentResult` termine toujours la course. `AgentRuntime/` suit la règle de `Core/` : ni vue, ni `AppState`, ni son, compilé tel quel dans les tests. Il part de la branche `yumi/contexte`.

| Sujet | État |
|---|---|
| Entrée | `AgentRequest` : l'intention, le `ContextSnapshot` du moment (ou rien), l'heure. Le contexte est joint par celui qui crée la demande, une fois, quand la personne demande : le runtime ne capture rien et ne s'abonne pas au Context Engine. |
| Contexte transmis | `RequestContext` : application, fenêtre, nom du fichier (sans son dossier), application précédente, activité principale. Ni historique d'événements, ni liste d'applications. Dans la consigne du modèle il est entre balises `<context>`, présenté comme des données ; ses chevrons sont neutralisés pour qu'il ne puisse pas fermer le bloc. |
| Modèle | `LLMProvider` (texte en entrée, texte en sortie) : Anthropic, OpenAI, Gemini ou un modèle local s'y branchent sans toucher au runtime. Branchés (build direct) : `ClaudeCodeLLMProvider` (Claude Code utilisé comme modèle, sans aucun outil) puis `AnthropicLLMProvider` (clé des réglages), dans `FallbackLLMProvider`. Build App Store : la clé seulement. Sans modèle, `noProvider` : le runtime n'invente jamais de plan. |
| Planification | `AgentPlanner` propose (`LLMAgentPlanner` lit un objet JSON), `PlanValidator` décide : outil enregistré, sous le plafond de la politique, arguments conformes au schéma, douze étapes au plus. Le risque, les approbations et les identifiants d'étape viennent du registre et de la politique, jamais du modèle. Un modèle peut ajouter une approbation, jamais en retirer. `cannotPlan` permet de dire que ce n'est pas faisable. |
| Outils | `Tool` (descripteur : id, nom, description, schéma d'entrée, risque, clés de sortie promises ; `execute`). `ToolRegistry` construit une fois, au lancement. Livrés : `get_current_time` (risque nul) et `get_current_context` (lecture, ne lit que le snapshot de la demande). |
| Politique | `AgentPolicy` : plafond `read` par défaut, `write` dans le build direct (`AppDelegate.makeAgent`), `read` dans le build App Store. `external` ne tourne jamais. Approbation à partir de `write`, et `write` comme `external` demandent toujours, quel que soit le réglage. |
| Permissions | `PermissionManager` est la seule porte : chaque étape qui le demande y passe, le plan entier est revérifié avant l'exécution, aucun drapeau ne la contourne. Implémentation de l'app : `LocalPermissionManager` (voir Permission System) ; `DenyingPermissionManager`, qui refuse tout ce qui demande un accord, reste le défaut du runtime. Un refus annule la course (ou saute l'étape si elle est facultative). |
| Exécution | `AgentExecutor` : étape par étape, revérifie l'outil, demande l'accord, exécute hors du fil principal avec un délai maximal (30 s), contrôle la sortie, met l'état à jour. Une erreur d'outil devient une valeur, jamais un plantage. |
| Reprise | `RecoveryPolicy` : `retry` pour une panne passagère ou un délai dépassé (3 essais par étape, 6 relances par course, plafonnés à 5 et 20), seulement pour un outil qui ne change rien (risque `none` ou `read`) : un outil qui écrit n'est jamais appelé deux fois, son effet a pu avoir lieu malgré le délai. `skip` pour une étape facultative, `cancel` sur un refus, `fail` sinon. |
| Vérification | `AgentVerifier` : `StructuralVerifier` exige que chaque étape non facultative soit terminée avec un résultat. Un vérificateur futur pourra refuser un résultat, jamais exécuter. |
| États | `ExecutionState` : idle, planning, awaitingApproval, executing, verifying, completed, failed, cancelled. `AgentActivity` les traduit pour le personnage (idle, thinking, planning, working, waiting, success, error), sans rien dire des poses : c'est au personnage de décider. |
| Événements | `AgentEvent` : agentStarted, planCreated, stepStarted, stepCompleted, stepFailed, stepSkipped, approvalRequired, approvalGranted, approvalDenied, verificationStarted, agentCompleted, agentFailed, agentCancelled. Abonnement par `RuntimeAgent.events()`. `suggestedPriority` (`InteractionPriority` : silent, ambient, attention, blocking) n'est qu'une indication : seule une demande d'accord est bloquante, la progression est silencieuse. Aucune notification n'est affichée par le runtime. |
| Historique | `AgentRun` : la tâche et ses événements (200 au plus), sérialisable pour un futur replay. `AgentRunHistory` garde les 20 dernières courses, en mémoire seulement. |
| Interface | Réglages, section Agent : planificateur, outils, but, état, étape en cours, progression, erreur, derniers événements ; un champ pour lancer une demande, « Check tools » (un plan écrit par le développeur, qui passe par les mêmes règles) et « Cancel ». Le contexte n'est joint qu'au clic. Mode tournage : pas de runtime. |
| Nommage | `RuntimeAgent` et `RuntimeTask`, parce que `Agent` (Core/) désigne déjà un produit externe et `AgentTask` une carte de l'île. `AgentPermissionRequest` pour la même raison (`PermissionRequest` est la demande d'un hook Claude Code). |

Fait depuis : providers Claude Code et Anthropic, `LocalPermissionManager` dans la file de l'île, `AgentReaction` (personnage et île), six outils (voir les sections suivantes).

## Cœur : le Permission System (branche `yumi/permissions`)

La frontière entre le cerveau de Yumi et ses actions. `Permissions/` suit la règle de `Core/` (ni vue, ni `AppState`), compilé tel quel dans les tests.

| Sujet | État |
|---|---|
| Porte unique | `AgentExecutor` passe **chaque** étape à `PermissionManager.evaluate` (allow, ask, deny), quel que soit son risque ; une étape sûre revient autorisée sans rien montrer. `finishRun` ferme toujours la course : demandes en attente annulées, accords « une fois » effacés. |
| Action réelle | `Tool.action(for:)` décrit ce que fait un appel (lire, modifier, supprimer, envoyer…) et ce qu'il touche. Le risque vient de là, jamais du planificateur. |
| Risques | `RiskLevel` safe, low, medium, high, critical. `RiskTable` configurable au-dessus de planchers fixes. Plusieurs fichiers modifiés d'un coup : high. Irréversible : high. Secrets et système (`~/.ssh`, `.env`, `/etc`…, sans casse), paiement, plus de 25 ressources : critical. Commandes : medium si connue et locale, high si chaînée ou inconnue, critical avec `sudo`, `security`, `mkfs`… |
| Ordre de décision | règle qui refuse, critical (refus, ou question si une règle le dit), accord de cette course, high (toujours une question), règle ask/allow (allow plafonné à medium), permission donnée avant, puis défauts : safe passe, low passe pour un fichier choisi par la personne ou dans un projet déjà autorisé, sinon question. |
| Portées | `oneTime`, `session` (projet ou ressources, jusqu'à la fin), `project` et `resource` (retenues), `tool` (projet ou compte, session). Jamais au-dessus de medium, jamais tout le Mac. Préfixes de chemins comparés par dossier entier, chemins résolus (`..`, liens). |
| Regroupement | Les étapes suivantes de la même course avec même outil, action, risque et projet sont demandées ensemble : « Je dois modifier 5 fichiers dans le projet Yumi. » Chaque action reste dans l'historique. |
| Approbation | `ApprovalRequest` (pending, approved, denied, expired, cancelled), expire 60 s après être apparue à l'écran (une demande qui attend derrière une demande Claude Code n'use pas ce temps ; jamais affichée, elle expire après 10 min), ne se résout qu'une fois : une réponse tardive ou rejouée ne change rien. Montrée dans la file de l'île (`HookServer.presentAgentApproval`) : une phrase, « Voir les détails » (outil, fichiers, portée, risque, raison de l'agent étiquetée comme telle, conséquence), Refuser, Autoriser, « Pour cette session » si le risque le permet. |
| Injection | Les permissions ne viennent que d'un clic (closure donnée au présentateur) ou des réglages. `AgentPermissionRequest` ne contient pas le contexte. Une règle trop large est refusée, et ignorée si écrite à la main dans le fichier. |
| Stockage | `permissions.json` (règles et accords retenus) et `permissions-audit.jsonl` dans le dossier de Yumi, 0600. Aucun secret : ils restent dans le trousseau. Historique nettoyé : ni arguments, ni contenu, ni texte de l'agent, jetons masqués (`AuditRedactor`). |
| Personnage | `PermissionEvent` décrit ; `ApprovalReaction` (app) fait regarder Yumi, puis `pop` et `working` à l'accord. |
| Réglages | Section « Autorisations de Yumi » : accords à retirer, règles, historique effaçable. Distinct des autorisations macOS (`Modules/Permission.swift`). |

Reste à faire : appeler `personChose(file:)` au dépôt d'un fichier dans l'île, une interface pour écrire des règles. Les outils qui écrivent existent (plafond `write` dans le build direct).

Depuis la stabilisation : un clic sur Autoriser ou Refuser répond à la demande affichée et à aucune autre (`ApprovalInfo.requestID`) ; si la file a changé entre l'affichage et le clic, le clic est ignoré. Un `permissions.json` illisible est mis de côté (`permissions.unreadable-<secondes>.json`) au lieu d'être écrasé à la sauvegarde suivante.

## Cœur : trois outils pour l'agent (branche `yumi/outils`)

Trois outils sur le modèle de `create_file` : `check` avant `PermissionManager`, action décrite par `action(for:)`, vérification après exécution, raison exacte en français en cas d'échec. Enregistrés dans `AppDelegate.makeAgent` (build direct seulement ; le build App Store garde ses outils de lecture). Le plafond `AgentPolicy` reste `write`.

| Outil | Ce qu'il fait | Accord | Vérification |
|---|---|---|---|
| `add_reminder` | Ajoute un rappel à la liste par défaut de Rappels (EventKit) : titre d'une ligne (120 caractères), date `AAAA-MM-JJ` et heure `HH:mm` facultatives, une heure seule vaut pour aujourd'hui, jamais dans le passé. Une alarme à l'heure dite, pour que Rappels notifie. | Toujours demandé. La demande montre « Je dois créer le rappel « titre », demain à 10:00, dans la liste Rappels. » La ressource est de type `unknown` : aucun accord retenu ne la couvre. | Le rappel relu par son identifiant a ce titre et cette date. |
| `start_focus` | Lance une session du module Focus : une seule manche, 5 à 180 minutes, 25 par défaut. Jamais si une session tourne, est en pause ou en pause café ; jamais si le module est coupé. | Aucun (risque `none`, rien ne sort du Mac). | Le Focus tourne, en phase de travail, avec la durée demandée. |
| `get_today` | Résume la journée en une ou deux phrases dans la voix de Yumi : prochains rendez-vous du jour, rappels du jour, météo actuelle. Seulement ce que les modules tiennent déjà ; un module coupé ou sans accès est omis. | Aucun : il lit les modules de Yumi (`yumi:modules`), ce que l'île montre déjà. | La réponse tient en deux phrases au plus, sans liste. |

| Sujet | Décision |
|---|---|
| Accès Rappels | Si macOS n'a jamais posé la question, le `check` la pose (`requestAccess`) avant la demande d'accord de Yumi ; refusé, il renvoie vers Réglages Système. Jamais redemandé ensuite (branche `yumi/outils-fix`). |
| Risque d'un rappel | Le cahier demandait « low ». Le plancher de `RiskTable` pour `create` est `medium` et n'a pas été abaissé : le comportement voulu (toujours demander) est le même. |
| Planificateur | Ne voit que les descripteurs, plus une ligne `<now>` (date, jour, heure du Mac) pour comprendre « demain ». Aucun rendez-vous, rappel ni météo avant que la personne demande, et jamais ensuite : le résumé est composé par le code de l'outil. |
| Chat | `ChatRoute.runtimeTools` (`start_focus`, `get_today`) envoie aussi au runtime les plans sans écriture qui les utilisent. « Je m'en occupe… je te demande avant » n'est dit que si une étape demande un accord. |
| Réponse | Un outil peut rendre `reply` : quand chaque étape terminée en a une, Yumi dit ces phrases à la place de « C'est fait, et j'ai vérifié ». Écrites par le code de l'outil après vérification, jamais par le modèle. |
| Modules | `ModuleBridge` (Modules/AgentBridges.swift) lit Focus, Agenda, Notes et Météo sur le fil principal, à la demande. `FocusTimer.start(now:minutes:)` ; le bouton Démarrer remet les quatre manches de 25 minutes. |

Hors périmètre, non commencés : suppression, terminal, mails, mémoire. Aucun outil ne supprime, n'invite ni n'envoie ; seul `append_to_file` modifie un fichier existant, et seulement un fichier que Yumi a créé.

## Cœur : deux outils de plus (branche `yumi/outils-2`)

| Outil | Ce qu'il fait | Accord | Vérification |
|---|---|---|---|
| `add_event` | Ajoute un événement au calendrier par défaut (EventKit) : titre d'une ligne (120 caractères), jour `AAAA-MM-JJ` et heure de début `HH:mm` obligatoires, durée 5 à 720 minutes (60 par défaut), lieu facultatif. Jamais d'invités, jamais un calendrier en lecture seule, abonné ou d'anniversaires, jamais la modification d'un événement existant. | Toujours demandé. La demande montre « Je dois créer l'événement « Réunion client », jeudi 8 octobre, 14 h à 15 h, dans le calendrier Travail. » Ressource `unknown` : aucun accord retenu ne la couvre. | L'événement relu par son identifiant a ce titre, ces heures, et aucun invité. |
| `append_to_file` | Ajoute du texte (4 000 caractères au plus, sur sa propre ligne) à la fin d'un fichier texte que `create_file` a créé, et seulement ceux-là : leur liste est dans `created-files.json` (dossier de Yumi), écrite par le code de `create_file`. Le fichier doit être encore là, à sa place, dans Téléchargements, sur le Bureau ou dans Documents, un fichier ordinaire et pas un lien (écriture en `O_APPEND | O_NOFOLLOW`), en UTF-8, de 1 Mo au plus. | Toujours demandé. La demande montre le chemin exact (`~/Downloads/todo.md`) et le texte ajouté (`ToolAction.content`, montré sous le titre et dans les détails). | Le début du fichier a la même empreinte SHA-256 qu'avant, et la fin est exactement le texte ajouté. |

| Sujet | Décision |
|---|---|
| Accès Calendrier | Comme pour Rappels : la question macOS est posée par le `check` si elle ne l'a jamais été, avant la demande d'accord ; refusé, renvoi vers Réglages Système, Calendriers. |
| Date ambiguë | Le jour et l'heure sont exigés, au format exact : « jeudi » seul, une heure seule ou un moment passé sont refusés par le `check`, sans demande d'accord, avec la raison. Le planificateur calcule la date depuis `<now>`. |
| Risque | Le cahier demandait « low ». Les planchers de `RiskTable` (`create` et `modify` à `medium`) n'ont pas été abaissés : la demande d'accord est la même. |
| Fichiers connus du planificateur | La description de `append_to_file` liste les dix derniers fichiers créés par Yumi (chemins sous `~`), pour que « ma todo » désigne le bon. Rien d'autre du disque. |
| Affichage des accords | Un fichier hors d'un projet s'affiche depuis le dossier personnel (`~/Downloads/todo.md`) et plus seulement par son nom. |

Hors périmètre, non commencés : suppression, terminal, mails, mémoire. Aucun outil ne supprime, n'invite ni n'envoie ; seul `append_to_file` modifie un fichier existant, et seulement un fichier que Yumi a créé.

## Île : sessions Claude Code et GitHub en lignes (branche `yumi/ile`)

Fait par la session Île sur décision de la coordination, qui l'a autorisée à toucher `Contracts/ModuleTypes.swift` (le champ `rows` seulement), `Modules/ClaudeCode` et `Modules/GitHub`.

- Claude Code : `SessionBoard` (dans `ClaudeSessions.swift`) liste toutes les sessions, celles qui attendent un accord puis une réponse en premier, puis celles qui travaillent, en erreur, ouvertes, terminées. Chaque ligne dit le projet, ce que fait la session, son état et depuis quand. Une session terminée ou fermée reste 90 secondes avec son résultat puis part. Un clic ramène son terminal ou son éditeur quand l'hôte est connu, sinon la ligne n'est pas un bouton.
- Île repliée : avec plusieurs sessions, « 3 sessions » (priorité ambiante), et « 3 sessions · accord sur api » quand une attend (priorité attention, elle reste devant).
- GitHub : les trois dépôts du compte poussés le plus récemment (hors forks et archives) sont suivis. À chaque regard lent (toutes les cinq minutes, comme les dépôts), leurs pull requests ouvertes (quatre au plus par dépôt) et les checks de leur dernier commit, toujours en requêtes conditionnelles avec ETag. Lignes : ta review, CI rouge, CI en cours, CI verte, puis les quatre derniers événements avec l'heure.
- Une CI qui passe au rouge (vue d'abord en cours ou verte) met GitHub devant dans l'île repliée jusqu'à ce qu'on ouvre la PR ou qu'elle repasse au vert. Une nouvelle demande de review joue la scène `pullRequest`. Aucune scène n'existe pour une CI rouge.
- Vues : `Island/IslandRows.swift`. Démo : `YUMI_ISLAND_VIEW=claude-code` et `YUMI_ISLAND_VIEW=github`.

## Île : alpha, version, retours et nouvelles versions (branche `yumi/ile`)

- Version : `CFBundleShortVersionString` 0.1.0, et `YumiDisplayVersion` « 0.1.0-alpha » (project.yml, Yumi et YumiAppStore), affichée dans les réglages de l'île.
- « Envoyer un retour » (réglages de l'île) ouvre le formulaire de bug du dépôt (`issues/new?template=bug.yml`) avec la version de Yumi, la version de macOS, le modèle du Mac et la présence d'une notch déjà remplis. Rien d'autre. La page de choix `issues/new/choose` ne garde pas ce qu'on lui passe : le lien va donc au formulaire, qui permet de revenir aux autres modèles.
- Modèles d'issue en français : `.github/ISSUE_TEMPLATE/bug.yml` et `idee.yml`.
- Nouvelles versions (`Island/IslandUpdates.swift`) : au lancement puis une fois par jour au plus, sans jeton, `releases?per_page=1` (pré-versions comprises). Une version plus récente (comparaison `YumiVersion`, semver) donne une ligne dans les réglages et, une seule fois par version, la remarque « Une nouvelle version de Yumi est là » dans l'île repliée ; « Voir » ouvre la page de la release. Jamais de téléchargement. Désactivable (« Préviens-moi des nouvelles versions »). Aucun appel en mode tournage.

## Cœur : plusieurs moteurs (branche `yumi/moteurs`)

But : que l'on puisse essayer le chat et l'agent sans Claude Code.

| Sujet | Décision |
|---|---|
| Moteurs | `Engine` : Claude Code, Anthropic, OpenAI (Chat Completions, `gpt-4o-mini` par défaut), Google Gemini (`generateContent`, `gemini-2.5-flash` par défaut, clé en en-tête, jamais dans l'URL), Ollama (`127.0.0.1:11434`, modèle choisi parmi ceux installés). Tous derrière `LLMProvider` (AgentRuntime/Providers). Aucun CLI tiers : on ne peut pas prouver qu'ils tournent sans outil. |
| Choix | `EngineSettings` (défauts) : « Automatique » ou un moteur, ordre de repli (Claude Code, Anthropic, OpenAI, Gemini, Ollama par défaut), modèle par moteur. Clés dans le trousseau (`openai-api-key`, `gemini-api-key`, `anthropic-api-key`). |
| Agent | `EngineLLMProvider` relit les réglages à chaque demande et essaie les moteurs dans l'ordre ; un moteur non configuré (`unavailable`) passe la main, un moteur joint qui échoue arrête la demande. Le plan passe ensuite par `PlanValidator`, le registre, `PermissionManager`, l'exécution et la vérification, quel que soit le moteur. |
| Chat | Même ordre. Claude Code garde son chemin (outils de lecture seulement) ; la clé Anthropic garde le sien ; OpenAI, Gemini et Ollama répondent en conversation pure (`ChatPhrases.engineSystemPrompt`), sans aucun outil. Les demandes d'action passent toujours d'abord par le Runtime. |
| Erreurs | Clé refusée (401, 403), quota (429), réseau : dits en une phrase, sans la clé ni le corps de la réponse. Aucun moteur : message qui renvoie à la section Moteurs. Ollama arrêté compte comme absent. |
| Réglages | Section Moteurs : choix, ordre (flèches), clé et modèle par moteur, état détecté (installé, clé présente, Ollama qui répond), bouton « Tester », et ce qui part chez chaque fournisseur avec qui le facture. |

## Île : la fenêtre des réglages refaite (branche `yumi/ile`)

- Une barre latérale (`SettingsPage`, testée) : Général, Yumi, Modules, Moteurs, Claude Code, Autorisations, Mémoire, À propos, et Développeur, cachée tant que « Afficher les outils de développeur » (À propos, clé `settingsDeveloper`) n'est pas coché ou qu'on n'a pas cliqué sur À propos avec Option.
- Chaque page est un `Form` groupé (`Sources/App/Settings/`). Les clés UserDefaults et Trousseau sont celles d'avant (`SettingsPage.settings` les range par page, un test vérifie que chaque ancien réglage a sa place).
- Moteurs : présentation dans `Settings/EnginesSettings.swift`, logique dans `EngineSettings`, `EngineDetector`, `EngineFactory`.
- Les intégrations héritées de Coucou ont été retirées (branche `yumi/menage`). Modules garde GitHub. Mémoire propose « Tout effacer… » avec une confirmation (`memoryClear`).
- Restent en anglais : les panneaux Contexte et Agent (page Développeur) et les mots de l'historique des autorisations (`allowed`, `approved`), qui viennent de fichiers du cœur.
- Captures : `YUMI_SETTINGS_SHOTS=<dossier>` (Debug) ouvre chaque page en clair puis en sombre et écrit `ready` avec le numéro de fenêtre pour `screencapture -l`.

## Ménage : ce qui restait de Coucou (branche `yumi/menage`)

| Retiré | Pourquoi |
|---|---|
| Six intégrations et leurs pollers (Resend, n8n, Vercel, Stripe, Cal.com, Notion), leurs états dans `AppState`, leurs types, leurs filtres, leurs réglages (page Développeur, « Pastilles de l'île »), `IntegrationPollers`, `LaunchPlan.integrationPollers` | Décision : on ajoute nos propres intégrations au fur et à mesure. |
| Leurs clés du trousseau et leurs préférences | Effacées une fois au lancement (`KeychainStore.eraseRetiredKeys`, drapeau `retiredKeysErased`). |
| Pastilles d'intégration (sauf la tâche Claude Code) et `AgentSource.n8n` | L'île ne dessine plus de pastilles ; seule la tâche Claude Code porte l'état des sessions (`ClaudeTaskMirror`). |
| Recherche structurée (`ClaudeService.search`, `SearchResult`, `searchResult`) | Plus appelée ; aucune vue ne la lisait. |
| Vues `IslandView.mail` et `.uploading` | Jamais affichées. |
| Totaux GitHub de l'ancienne carte (`githubStats`, `onTotals`, `GitHubFeed.totals`) | Écrits, jamais lus. |
| `EnginesSettingsView`, `MiniBotCanvasView`, `YumiExpression`, `EyeShape`, `IslandGlyph(View)`, `FlowLayout`, `cgColorFromHex` | Plus utilisés. |

| Gardé | Utilisé par |
|---|---|
| Chat par l'API Anthropic (`chatWithAPI`, `readFileAsBlock`) | Le moteur Anthropic et la build App Store. |
| Dépôt de fichier (`FileDropView`, vues `.upload`, `.choose`) et capture de fenêtre (`WindowContextCapture`) | Glisser un fichier ou une fenêtre vers Yumi, « Résumer ». |
| Tâche Claude Code (`AgentTask.claudeCode`, `focusTask`, badges) | L'état des sessions et du personnage. |
| Retrait des hooks Coucou et NotchBuddy à l'installation | Protège qui avait Coucou. |
| `IslandDemo`, `BotDemo`, mode tournage | Outils de développement et de tournage. |

Correction faite au passage : `openai-api-key` et `gemini-api-key` n'étaient pas lues au lancement par `KeychainStore` : ces clés étaient oubliées à chaque redémarrage.

## Confidentialité : le contexte du chat (branche `yumi/contexte-chat`)

Signalé par un lecteur du code : à l'ouverture du chat, le nom de l'app au premier plan, le titre de sa fenêtre et l'URL complète partaient au moteur avec le premier message, sans geste de la personne, alors que le README disait le contraire.

| Sujet | Décision |
|---|---|
| Phrase exacte | Quand tu ouvres le chat, le nom de l'app au premier plan, le titre de sa fenêtre et le domaine du site sont joints à ton premier message, et affichés dans l'encoche ; un clic les retire. Le contenu de ton écran n'est jamais envoyé. |
| Contrôle | Le bandeau « Avec … » est un bouton (clavier et VoiceOver compris) : un clic détache le contexte, un clic le rattache (`AppState.contextAttached`). Détaché, il ne part nulle part. |
| URL | Sans geste explicite, réduite au domaine (`ChatContextPolicy`). « Résume-moi cette fenêtre », une fenêtre glissée sur Yumi ou un fichier déposé (`AppState.contextExplicit`) gardent le comportement d'avant : adresse complète, fichier. |
| Un seul filtre | `IslandActions.send` applique `PromptContext.outgoing` avant `ClaudeService.chat` : les trois chemins qui suivent reçoivent le même contexte filtré. |
| « Toujours » | Écrit une règle permanente dans les réglages Claude Code de la personne (`updatedPermissions`), qu'elle retire depuis Claude Code (`/permissions`). |

Chemins où un contexte de fenêtre ou de fichier part vers un moteur, vérifiés :
1. Chat par Claude Code : `ChatPhrases.message` préfixe le premier message (fenêtre, ou chemin d'un fichier déposé, lu par Claude Code dans le dossier inbox) ; une seule fois par session (`sentContext`).
2. Chat par la clé Anthropic (`chatWithAPI`) : « Context — App, Window, URL » au premier message ; un fichier déposé y est envoyé en entier (`readFileAsBlock`), seulement après un dépôt.
3. Chat par OpenAI, Gemini, Ollama (`chatWithProvider`) : `ChatPhrases.message` au premier message.
4. Agent depuis le chat : le snapshot du Context Engine accompagne la demande mais n'est jamais transmis au planificateur (`sharesContextWithModel` à false) ; seul le panneau Agent des réglages peut le transmettre, sur case cochée.
5. Mémoire : ce que la personne a fait noter, envoyé au moteur du chat ; jamais le contexte de fenêtre.
6. Résumé de fil (fin de conversation Claude Code) : reprend la session existante, sans contexte nouveau.

## Module Notion (branche `yumi/notion`)

Demandé par plusieurs testeurs.

| Sujet | Décision |
|---|---|
| API | API publique de Notion, version datée `2022-06-28` (toujours prise en charge d'après la doc de versionnement de Notion), en-têtes `Notion-Version` et `Authorization: Bearer`. Recherche des bases partagées, requête d'une base, création de page, lecture de page. Pas de Notion Calendar (pas d'API publique). |
| Clé | Clé d'intégration interne collée dans Réglages, Modules, Notion, rangée dans le trousseau sous `notion-integration-key` (pas `notion-api-key`, le nom de Coucou, effacé une fois au lancement). Lue au lancement avec les autres. |
| Bases | La personne coche les bases partagées avec l'intégration (`NotionBases`, préférence `notion.bases`) et choisit pour chacune la propriété de date et celle de fin (case à cocher, ou statut avec sa valeur « terminé »). Seules ces bases sont lues. |
| Île | Module `notion` : tâches non terminées du jour et en retard, en deux sections (« En retard », « Aujourd'hui »), titre, base, pastille de date (« 15:00 », « aujourd'hui », « en retard · hier », « en retard · 5 oct. »), douze au plus ; un rond à cocher devant chaque tâche (`ModuleRow.check`) la marque terminée par le runtime (voir plus bas) ; un clic sur la ligne ouvre la page (`notion://`, repli https). Live dans l'île repliée seulement si une tâche à heure tombe dans le quart d'heure. Une lecture toutes les 5 minutes ; sur 429, attente du `Retry-After`, jamais moins d'une minute. |
| Agent | `get_today` ajoute les tâches Notion du jour demandé (« deux tâches Notion, dont … »), titres coupés à une ligne. `add_notion_task` (titre, date facultative, base si plusieurs) : action create sur la ressource `.account("notion:<id de la base>")`, donc risque élevé (voir plus bas), accord toujours demandé avec la tâche, le jour et la base ; `check` avant (base connue et accessible) ; vérification après (la page relue a ce titre). Aucune modification ni suppression de page. Build directe seulement. |
| Confidentialité | Rien n'est envoyé au moteur en dehors de la phrase de `get_today`. Les titres de pages sont des données : ils ne changent ni les permissions ni le plan. |

## Notion : risque des écritures et tâches cochées (branche `yumi/notion-risque`)

| Sujet | Décision |
|---|---|
| Constat | Relevé par Laurent : `add_notion_task` déclarait une ressource `.unknown`, évaluée « moyen » comme un ajout local, alors qu'élevé veut dire « quitte le Mac ». Une règle « autoriser » s'appliquait donc sans redemander, et l'historique gardait « moyen ». `RiskAssessor.assess` plafonnait de toute façon le plancher de l'outil à moyen. |
| Plancher général | Dans `RiskAssessor.assess` : toute action autre qu'une lecture sur une ressource `.account` ou `.url` est au moins élevée. Tous les connecteurs en héritent. Les outils locaux (fichiers, Calendrier, Rappels, Focus) ne changent pas. |
| Conséquences | Élevé : demandé à chaque fois, seule la portée « une fois » est proposée, une règle « autoriser » devient une question, rien n'est mémorisé ; une règle peut viser une base (`notion:<id>`), l'historique enregistre « élevé ». Le texte de l'accord (tâche, jour, base) passe dans `ToolAction.content`. |
| Cocher | `complete_notion_task` (page) : action modify sur `notion:<id de la base>`, élevé. Seulement une tâche listée par l'île (`NotionListedTasks`) avec un vrai identifiant Notion (32 chiffres hexadécimaux, rien d'autre n'entre dans le chemin). `check` relit la page (dans une base choisie, pas déjà terminée) ; l'écriture est un `PATCH /v1/pages/{id}` qui n'envoie que la propriété de fin (case cochée, ou statut mis à la valeur « terminé ») ; vérification : la page relue est terminée. Le rond de l'île lance un plan d'une étape (`CompleteNotionTaskTool.plan`) par `RuntimeAgent.execute`, donc validation, accord, écriture, vérification, comme le chat. Build directe seulement. |

## GitHub : toute l'activité (branche `yumi/github`)

| Sujet | Décision |
|---|---|
| Dépôts | `/user/repos?affiliation=owner,collaborator,organization_member` : tous ceux que le jeton voit (organisations si le jeton le permet). Tous suivis par défaut ; Réglages, Modules, GitHub, « Dépôts suivis » pour en masquer (`github.hiddenRepos`). Login et liste gardés pour les réglages (`github.login`, `github.knownRepos`). |
| Flux | `/users/{login}/events` et `/received_events` (ce que d'autres font sur les dépôts de la personne), requêtes conditionnelles avec ETag (une 304 ne coûte rien), au rythme de `X-Poll-Interval` (60 s au moins) ; quota épuisé : attente jusqu'à `x-ratelimit-reset`. Pas de webhook. |
| Commits | La doc GitHub des types d'événements ne liste plus de `commits` dans `PushEvent` (seulement `ref`, `head`, `before`) : les commits sont lus par `/repos/{repo}/compare/{before}...{head}` (ou le commit seul pour une nouvelle branche), une fois par push, six au plus par passage. |
| Île | Fil par dépôt : en-tête « Yumi · 3 aujourd'hui, 12 cette semaine », puis « 3 commits sur main » et chaque commit (message, sha court, auteur), un clic ouvre le commit ; les autres événements ; puis les PR ouvertes et leurs checks (inchangé). Île repliée : CI rouge et relecture d'abord, puis un push de moins de deux minutes. Scènes du personnage inchangées. Les commits ne se replient pas : `ModuleRow` n'a pas de lignes dépliables, et l'île est un chantier à part. |
| Comptes | Calculés sur les pushes vus dans le flux (GitHub en garde 90 jours, 300 événements au plus). |
| Confidentialité | Seulement api.github.com, en lecture. Aucune écriture sur GitHub. |

## Musique : les vidéos et la musique du navigateur (issue #5, branche `feat/5-browser-media`)

| Sujet | Décision |
|---|---|
| Sites | YouTube, SoundCloud, Twitch et Vimeo rejoignent Deezer et YouTube Music, lus dans le titre des fenêtres (Accessibilité, déjà accordée), dans tous les navigateurs connus. Le titre d'une vidéo est gardé entier : l'ordre artiste et morceau n'y est pas fiable. |
| Lecture ou pause | Demandé à Core Audio (`AudioActivity`, `kAudioProcessPropertyIsRunningOutput`), sans aucune permission : le navigateur ou l'un de ses processus auxiliaires envoie-t-il du son. Une page jamais entendue n'est pas un morceau (une vidéo ouverte que personne n'a lancée) ; un morceau entendu puis muet passe en pause. Un bouton de l'île l'emporte sur le son pendant 10 s. Si Core Audio ne répond pas, l'ancien comportement (le dernier bouton décide). |
| Autres pages | Un navigateur qui envoie du son sans aucun site connu dans ses fenêtres (une radio en ligne) donne une entrée `web` : le titre de sa fenêtre de devant, ou de celle déjà montrée si elle est toujours ouverte, et le nom du navigateur en dessous. Plus prudent qu'un site connu : il faut avoir entendu le navigateur à deux regards de suite (un son de notification n'est pas de la musique), rien sans Core Audio, et une page en pause quitte l'île repliée au bout d'une minute au lieu de cinq. Jamais dans Safari, dont le son passe par des processus WebKit partagés avec d'autres apps. Le bouton ouvrir ramène le navigateur devant. |
| Écartés | MediaRemote : réservé aux apps Apple depuis macOS 15.4. Apple Events vers les navigateurs : une autorisation Automatisation par navigateur, et rien sur la lecture sans « JavaScript depuis Apple Events ». |
| Limites | Seul l'onglet au premier plan de chaque fenêtre est vu. Pour une autre page, le titre ne dit pas quel onglet joue : avec plusieurs fenêtres, c'est celle de devant qui est montrée, et un son qui vient d'un autre onglet (un jeu, une visio) peut donc s'afficher sous le titre de la fenêtre de devant. Safari joue par les processus WebKit partagés avec d'autres apps (Mail…). Boutons par les touches média du Mac. Rien dans le build App Store ni en mode tournage. |

## GitHub : l'app GitHub, plusieurs organisations (issue #4)

Un jeton à granularité fine ne voit qu'un seul propriétaire. L'app GitHub de Yumi suit chaque compte où la personne l'installe : le sien et autant d'organisations qu'elle veut. Le jeton personnel reste possible ; quand les deux sont là, le jeton de l'app passe devant.

| Sujet | Décision |
|---|---|
| Connexion | Device flow, sans serveur et sans secret : `POST github.com/login/device/code` avec le Client ID public, la personne tape le code sur `github.com/login/device` (ouvert par Yumi, jamais une autre adresse), Yumi interroge `github.com/login/oauth/access_token` au rythme donné par GitHub (`slow_down` respecté). |
| Jeton | Jeton d'accès utilisateur (`ghu_…`, 8 h) et jeton de renouvellement (`ghr_…`, 6 mois), en JSON dans le trousseau sous `github-app-token`. Renouvelé dans ses cinq dernières minutes, avant un passage du module, sans `client_secret` (permis par GitHub pour un jeton venu du device flow). Renouvellement refusé ou expiré : déconnecté, la personne se reconnecte. |
| Dépôts | Avec l'app : `/user/installations`, puis `/user/installations/{id}/repositories` pour chacune (20 comptes, 300 dépôts par compte au plus), fusionnés en une liste au format de `/user/repos?sort=pushed` (`GitHubApp.mergedRepos`), lue ensuite par le même code. Requêtes conditionnelles, dernière réponse gardée pour les 304. Le reste du module (flux, commits, PR, checks, contributions) ne change pas. |
| Configuration | `YumiGitHubAppClientID` et `YumiGitHubAppSlug` dans `project.yml` (Yumi et YumiAppStore). Vides tant que le mainteneur n'a pas créé l'app : l'option n'apparaît pas. |
| App à créer | Sur github.com, Settings, Developer settings, GitHub Apps : « Enable Device Flow » coché, pas de webhook (Active décoché), « Expire user authorization tokens » coché, installable par n'importe quel compte (Any account). Permissions de dépôt en lecture seule : Metadata, Contents, Pull requests, Checks, Commit statuses, Issues. Aucune permission d'organisation ni de compte. Aucun secret ni clé privée n'est utilisé par Yumi. |
| Réglages | Réglages, Modules, GitHub : « Se connecter avec l'app GitHub », le code à taper (copiable), les comptes où l'app est installée avec, pour chacun, « Choisir les dépôts » (sa page d'installation sur github.com, `html_url`, gardée sous `github.appAccounts`), « Ajouter une organisation » (page d'installation de l'app), « Déconnecter l'app ». Le champ du jeton personnel est masqué pendant que l'app est connectée. |
| Mode tournage | Rien : le trousseau n'est pas lu, la connexion ne démarre pas. |
| Confidentialité | Seulement github.com (connexion) et api.github.com (lecture). Aucune écriture sur GitHub. |

## Temps d'écran (branche `feat/screen-time`)

Inspiré de [temps-ecran](https://github.com/livio-emilio/temps-ecran) de Livio Sanna (MIT) : la même règle de comptage et les mêmes chiffres, refaits en Swift dans Yumi, sans script, sans launchd, sans SwiftBar et sans notification macOS.

| Sujet | Décision |
|---|---|
| Module | `Modules/ScreenTime`, identifiant `screen-time`, onglet Journée. Un regard par minute (tâche avec tolérance de 10 s, rien pendant le sommeil du Mac), seulement quand le module est sélectionné. Comme les autres modules arrivés après coup, il rejoint une fois la sélection des installations existantes, et n'est pas dans la sélection du premier lancement. |
| Règle | Une minute compte si la session est ouverte et si une touche ou la souris a bougé dans les cinq dernières minutes, ou si, écran allumé, un programme le garde allumé (assertion `PreventUserIdleDisplaySleep` : visio, film, présentation). Au-delà de deux heures sans aucune entrée, rien ne compte, même un film. temps-ecran a deux seuils de cinq minutes (écran allumé, écran éteint), ici un seul (`ScreenActivity`). |
| Appels système | Sans aucune autorisation : `CGEventSource.secondsSinceLastEventType` (inactivité), `CGSessionCopyCurrentDictionary` (`CGSSessionScreenIsLocked`), `CGDisplayIsAsleep`, `IOPMCopyAssertionsStatus`. Aucun sous-processus (`ioreg`, `pmset`). Compilés aussi dans le build App Store. |
| Stockage | `screen-time.json` dans le dossier de Yumi : minutes par jour (90 jours), par heure (14 jours), dernier palier dit par jour. Rien ne quitte le Mac. Mode tournage : le module ne démarre pas ; `YUMI_ISLAND_VIEW=screen-time` montre des jours inventés (`ScreenTimeLog.example`). |
| Île | Modèle commun (temps du jour, seuil, barre) en couleur calme, ambre à 80 % du seuil, rouge au-delà ; puis les heures du jour en petites barres, les sept derniers jours (un jour au-delà du seuil en rouge), et « moyenne · médiane · 3 jours sur 4 sous ». Moyenne sur les jours utilisés des sept derniers, médiane et 75e centile (rang le plus proche) sur ceux des quatorze derniers : un jour sans le Mac n'en dit rien. Les nombres passent par `pages` de `ModuleSnapshot` (minutes dans `detail`), sans toucher au contrat. |
| Seuil | Réglages, Modules, Temps d'écran : 4, 6, 8, 10 ou 12 h, 8 h par défaut (une journée de travail en temps vraiment actif ; temps-ecran part de 10 h), et « Me le dire quand je l'atteins » (oui par défaut). |
| Remarques | Au seuil, puis à chaque heure de plus, une fois : occasion `screenTime` du moteur d'initiative, avec l'action Pause. Elle compte comme une remarque qui compte (aussi en discret) et suit toutes les règles : vingt minutes entre deux remarques, limite du jour, jamais pendant un Focus, un partage d'écran, une présentation ou Ne pas déranger. Un palier refusé n'est pas redit plus tard. |
| Pause de deux heures | `InitiativeWatch.rested` : quand le module voit une minute qui compte après une qui ne comptait pas (cinq minutes sans rien toucher, session ouverte), les deux heures repartent de zéro, comme au réveil. Sans le module, l'ancien comportement (seuls le réveil et le déverrouillage après cinq minutes comptent). Les deux heures restent deux heures. |
| Développement | `YUMI_SCREEN_TIME_TICK=1` (Debug) : un regard par seconde, chacun vaut une minute, pour voir passer une heure en une minute. |

## Le bon onglet du terminal (branche `feat/terminal-tab`)

Quand Claude Code demande quelque chose, l'île propose d'aller voir dans la session même, pas seulement dans l'application qui l'héberge.

| Sujet | Décision |
|---|---|
| Où est la session | Le script du hook remonte ses processus parents (`ps -o ppid=,tty=`, quatre niveaux au plus, 0,3 s chacun) jusqu'au `claude` qui a un terminal, et envoie son tty (`/dev/ttys004`). Il envoyait déjà `ITERM_SESSION_ID` : Yumi en garde l'UUID. Les deux vont dans `SessionOrigin` (`tty`, `terminalSessionID`). |
| Aller à l'onglet | `TerminalTab` : l'application passe devant comme avant, puis un AppleScript sélectionne la fenêtre, l'onglet et le volet. iTerm2 par l'UUID ou le tty, Terminal par le tty. Seuls des chiffres, lettres, `/` et `-` entrent dans le script. Onglet introuvable ou Automatisation refusée : l'application reste simplement devant. |
| Autres terminaux | Ghostty, Warp, kitty, WezTerm, tmux : l'application passe devant, sans choisir l'onglet. Éditeurs : inchangé (le dossier du projet est rouvert). |
| Île | La carte d'accord de Claude Code a un bouton à côté de « Toujours autoriser », qui ouvre la session de cette demande. « Voir » sur une question et les lignes de sessions vont aussi au bon onglet. |
| Nom du bouton | Il nomme l'application où tourne la session, jamais « le terminal » en général : « Ouvrir iTerm2 », « Ouvrir Ghostty », « Ouvrir Cursor » (`SessionHost.appName` : une table des hôtes connus, sinon le nom de l'application installée). Un hôte qu'on ne sait pas nommer garde « Ouvrir le terminal », « l'éditeur » ou « la session ». Le bouton d'un terminal garde son symbole de terminal. |
| App Store | Aucun Apple Event (bac à sable) : l'application passe devant, comme avant. |

## Après la 0.1.0-beta.1 (18 novembre 2026)

La bêta est publiée, signée et notarisée. La suite, les points à régler et les décisions en attente sont dans `docs/prochaines-etapes.md`.

## Garde-fou : chaque demande d'accord expliquée (chantier 3, branche `yumi/garde-fou`)

Décision de l'auteur, le 18 novembre 2026 : une demande d'agent de code peut passer sans clic quand elle ne change rien, si la personne l'a activé (Réglages › Claude Code › « Laisser passer tout seul ce qui ne change rien », désactivé par défaut). Ça couvre la lecture de fichiers, l'historique git et les tests. Supprimer, pousser, installer, contacter internet, `sudo` et toute commande inconnue attendent toujours un clic. La règle de `CLAUDE.md` est changée en ce sens.

- `Permissions/AgentRequestReader.swift` lit l'outil et la commande et dit en clair ce que fait la demande (« supprimer build », « pousser sur le serveur git ») et si elle se défait. Une chaîne de commandes parle par sa partie la plus risquée ; une redirection, une substitution, un `| sh`, `sed -i`, `find -delete` ne sont jamais anodins.
- La carte d'accord affiche cette phrase, la commande brute dessous, et « Toujours autoriser » disparaît pour ce qui est risqué (suppression définitive, push, installation, internet, administrateur).
- Une demande laissée passer est notée dans la session (« Laissé passer : lancer les tests »).

## Premier lancement selon la personne (chantier 4, branche `yumi/premier-lancement`)

Après le prénom, une deuxième étape demande « Et tu fais quoi, surtout, sur ton Mac ? ». Validé avec l'auteur le 18 novembre 2026 : une liste large plutôt que cinq profils, plusieurs réponses possibles, et les animations du « je prends… » gardées pour tout le monde (la phrase devient « Quand je bosse pour toi, je prends »).

- `Modules/WorkProfiles.swift` : 12 profils (code, commerce, artisan ou terrain, freelance, équipe, création, vidéo, musique, études, enseignement, vie perso, un peu de tout), leurs modules (les cinq premiers dans l'île), et les mots qui y mènent depuis le champ « Autre ». Plusieurs profils : le premier module de chacun, puis le deuxième, l'activité pro avant la vie perso.
- `ModuleRegistry.adoptProfiles` n'applique ces modules que s'ils n'ont jamais été choisis : une mise à jour ou un prénom redemandé ne les déplace pas.
- Le profil et le mot libre vont dans la mémoire locale, du côté de la personne.
- « Je code » est coché d'avance quand un agent de code est sur le Mac, jamais en mode tournage.

