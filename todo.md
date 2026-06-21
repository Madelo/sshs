# Code Review — sshs.sh

## 🔴 Sévère

- [x] **L29-30 : `:=` au lieu de `:-`** — `SSHS_MENU` et `SSHS_CONFIG` sont modifiées globalement si vides. Remplacer `:=` par `:-`.
- [x] **L34 : Pas de check du code retour de `ssh`** — « Disconnected » affiché même si la connexion échoue. Vérifier `$?` après `ssh`.
- [x] **L67-68 : Prompt menu ambigu** — Le comportement (touche hors menu = annulation) est volontaire, mais le prompt ne l'indique pas. Ajouter `(other key to cancel)` au message.

## 🟡 Mineur

- [x] **L32,37 : Fonctions imbriquées redéfinies à chaque appel** — Extraire `sshs_connect` et `sshs_strindex` hors de `sshs()`.
- [x] **L42 : `$search` non échappé dans une regex** — Les métacaractères (`[`, `.`, `*`) sont interprétés. Échapper ou passer en matching shell (`==`).
- [x] **L59 : Message d'erreur mentionne `~/.ssh/config` en dur** — Utiliser `$config` pour refléter `SSHS_CONFIG`.
- [x] **L45 : `$i` non quoté dans `(( ))`** — `"$i"` plus robuste. → Faux problème : `(( ))` est un contexte arithmétique, pas de word splitting.
- [x] **L53 : Variable `line` réutilisée pour le padding** — Renommer en `padding` pour lisibilité.
- [x] **L68 : `tblHost[-1]` implicite** — `sshs_strindex` retourne `-1`, protégé uniquement par la garde au-dessus. Rendre explicite. → Commentaire ajouté.
- [x] **Variables `tblCom`/`tblHost` cryptiques** — Renommer `comments`/`hostnames`. → Accepté, noms cohérents pour le contexte.
