# Yumi : prochaines étapes après la 0.1.0-beta.1

Point de départ pour la suite. Ce fichier dit où on en est le 18 novembre 2026, ce qui reste à corriger, et les chantiers dans l'ordre où les faire. `docs/journal.md` reste la référence pour les décisions ; les idées lointaines sont dans `docs/backlog.md`, la communication dans `docs/distribution.md`.

## Où on en est

La 0.1.0-beta.1 est publiée (pré-release sur `estebanbaigts/Yumi`). C'est la première version signée avec le Developer ID (équipe `J5U6R6ZV6K`) et notarisée : elle s'ouvre d'un double-clic. Les notes de version, en français et en anglais, listent ce qui marche et ce qui ne marche pas encore.

Fusionné le 18 novembre : GitHub presque en direct (#22, puis le flux d'activité des dépôts dans #24), la détection automatique des agents de code (#23), les corrections après la vérification de `main` (#24), les releases notarisées faites sur le Mac (#25).

Pour faire une release : monter `YumiDisplayVersion` et `CFBundleVersion` dans `Yumi/project.yml`, fusionner dans `main`, puis depuis `main` à jour `YUMI_TEAM_ID=J5U6R6ZV6K ./scripts/release.sh <version> --publish`. Le script crée un brouillon ; on relit les notes, puis on publie. Les mots de pré-version restent en minuscules (`beta`, `rc`) : Yumi compare les versions pour prévenir les testeurs.

## À régler vite

1. Le dépôt local a `origin` qui pointe vers `AlbaNagisa/Yumi`, une ancienne copie en retard de 68 commits. Le vrai dépôt est le remote `esteban`. Remettre `origin` sur `estebanbaigts/Yumi` évitera de retravailler sur une vieille version.
2. Aucune carte n'est enregistrée chez Apple pour renouveler le compte développeur (échéance le 18 novembre 2027). Sans renouvellement, plus de notarisation.
3. La clé privée du certificat Developer ID n'existe que dans le trousseau de ce Mac. En faire une sauvegarde `.p12` protégée par mot de passe, rangée hors du dépôt.
4. Le 4 décembre, quand le quota Codex revient : tester une vraie session Codex (détection, carte d'accord, et surtout « Toujours autoriser », jamais vérifié avec Codex).

## Chantiers, dans l'ordre

### 1. Le nom de l'agent dans la liste des sessions

Petit et visible. Quand plusieurs agents tournent, la liste affiche « site attend ta réponse » sans dire si c'est Codex, Gemini ou Claude.

- Où : `SessionBoard`, dans `Modules/ClaudeCode/ClaudeSessions.swift` (les lignes de sessions). L'agent est déjà dans `Session.agent` ; `AgentCatalog.speaker(of:)` donne son nom court.
- Vérifier : un test qui ouvre deux sessions d'agents différents et lit les lignes, puis un essai en direct avec les faux processus `codex` et `gemini` (voir la PR #23).

### 2. Installer les hooks de Codex et de Gemini CLI depuis les réglages

Aujourd'hui Yumi n'installe que ceux de Claude Code. Codex lit `~/.codex/hooks.json`, Gemini CLI la clé `hooks` de `~/.gemini/settings.json` (événements `BeforeTool`, `AfterTool`, `BeforeAgent`, `AfterAgent`).

- Même règle que pour `~/.claude/settings.json` : copie datée, fusion, différence montrée, écriture seulement après confirmation.
- Où : `Settings/ClaudeCodeSettings.swift` (à généraliser en réglages « Agents »), `Hooks/HookServer.swift` pour le chemin du script.
- Vérifier : fichiers de test dans un dossier temporaire, jamais les vrais fichiers de la personne pendant les tests.

### 3. Le garde-fou : chaque action expliquée avant d'être faite

C'est ce qui sert à la fois au grand public et aux développeurs. Aujourd'hui la carte d'accord montre la commande brute ; elle doit dire ce que l'action change et si elle se défait (« Codex veut supprimer le dossier build. Il se reconstruit. »). Le chat de Yumi le fait déjà pour ses propres outils (`AgentRuntime`, `PermissionManager`).

- Étendre l'explication aux demandes venues des hooks : un classement des commandes courantes (lecture, tests, git, suppression, réseau) dans un fichier pur et testé de `Permissions/`.
- Décision à prendre avant de coder : les règles personnelles (« toujours laisser passer les tests »). `CLAUDE.md` interdit d'approuver une permission sans clic explicite. Une règle peut refuser ou toujours demander sans toucher à cette interdiction ; une règle qui accepte toute seule demande de changer la règle du projet, à décider par écrit dans le journal.

### 4. Le premier lancement selon la personne

Yumi demande ce que la personne fait dans la vie et ne montre que les modules utiles : Mail, Agenda, Rappels, Notes et Météo pour un boulanger ; Agents et GitHub en plus pour quelqu'un qui code. Pas de jargon (hooks, sessions) tant que la personne ne code pas.

- Où : le premier lancement (`Island/IslandWelcome.swift`, `Island/IslandHabitPicker.swift`), `Modules/ModuleSelection.swift` (`defaultIDs`).
- Vérifier : en mode tournage (`YUMI_STUDIO=1`) pour ne rien lire de personnel, et sur un compte macOS neuf.

### 5. La refonte de l'île

Sans doute la dernière avant la 1.0, et à faire après le chantier 4 : le contenu de l'île dépend de qui l'utilise. Repartir de `design/maquette/reference.html`, garder ce qui est validé dans le journal (taille, Yumi à gauche, une information à droite, état porté par la couleur du liseré).

- Les retours des testeurs de la bêta décident de ce qui change.
- Le hook de design du dépôt signale du contraste faible et des lueurs colorées dans `site/` et dans la maquette : à revoir pendant la refonte.

### 6. Yumi sur iPhone

Deux usages à séparer, parce qu'ils ne demandent pas la même chose.

- Yumi seul sur iPhone, sans Mac : chat avec le modèle d'Apple sur l'appareil, agenda, rappels, météo, notes. Le cœur (`Core/`, `Modules/`, `AgentRuntime/`, `Memory/`) est déjà sans vue ni AppKit pour l'essentiel ; il faut vérifier ce qui compile pour iOS et isoler le reste.
- L'iPhone qui répond aux agents du Mac, dans la Dynamic Island (Live Activities). Il faut un lien entre le Mac et l'iPhone. La règle du projet interdit la télémétrie et n'autorise le réseau que vers des services choisis par la personne : iCloud (CloudKit, base privée de la personne) respecte ça ; un serveur à nous non. À décider avant de commencer.
- Une cible iOS dans `project.yml`, et la même règle de signature (équipe `J5U6R6ZV6K`).

## Décisions en attente

- Mémoire : quand un nouveau souvenir dit la même chose qu'un ancien avec d'autres mots, le remplacer ou garder les deux. Le code garde aujourd'hui les deux exprès (`Memory/MemoryNotes.swift`, test `somethingNewIsAddedAndOlderMemoriesAreLeftAlone`). Un essai de fusion à 0,6 de mots communs séparait bien le vrai doublon, mais cassait ce choix.
- Règles d'acceptation automatique (chantier 3).
- Lien Mac et iPhone (chantier 6).
- Faire les releases sur GitHub Actions plutôt que sur le Mac : il faudrait y mettre la clé Developer ID. Pour l'instant, non.

## À mesurer

Le processeur quand un agent travaille. Mesuré à environ 8 % d'un cœur sur un build Debug ; à refaire sur le build signé (`build/release-<version>/Yumi.app`), maintenant possible avec le Developer ID. Au repos, Yumi se cache et ne consomme rien.

## Comment tester avant chaque fusion

- `cd Yumi && xcodegen && xcodebuild -scheme Yumi -configuration Debug test CODE_SIGNING_ALLOWED=NO`, puis les builds Debug et App Store sans warning.
- En direct : `YUMI_TRACE_MODULES=1` (et `YUMI_TRACE_GITHUB=1`, `YUMI_TRACE_AGENT=1` selon le chantier). Pour les agents, lancer le vrai script de hook depuis un processus nommé `codex`, `gemini` ou `claude` (un lien vers `/bin/sh` suffit) : la détection est testée pour de vrai sans abonnement.
- Après une fusion de plusieurs PR qui touchent `Localizable.xcstrings`, relancer le test des traductions : la fusion de #23 en avait inversé deux.
