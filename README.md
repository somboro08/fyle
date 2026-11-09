# Fyface

Application Flutter de coffre-fort documentaire et de partage sélectif, inspirée du thème, des cartes, de la navigation basse et des transitions de Shor (`C:\Users\LENOVO\shorty\shor`).

## Démarrage

```sh
flutter pub get
flutter run
```

L'application comprend les vues Accueil, Documents, Accès et Profil, une navigation avec fondu, un écran connexion/inscription Supabase, l'import PDF/JPG/PNG (10 Mo maximum) et l'enregistrement local des fichiers et métadonnées dans l'espace privé et SQLite. Quand Supabase est configuré et qu'une session est ouverte, les documents en attente sont envoyés au Storage privé et aux métadonnées Postgres ; en cas d'échec, ils restent en attente localement et la synchronisation réessaie au retour du réseau.

Les documents initiaux, les consultations, et le code affiché (`FY-8K2M-94`) sont des éléments de démonstration. La création de vrais codes partageables, la consultation de documents par code et les journaux d'accès réels nécessitent encore les Edge Functions décrites plus bas. La base SQLite locale est dans `lib/core/local_store.dart` ; le schéma et les politiques RLS sont dans `supabase/schema.sql`.

Pour configurer Supabase, crée un projet, exécute le schéma, puis fournis les valeurs publiques au lancement :

```sh
flutter run --dart-define=SUPABASE_URL=https://...supabase.co --dart-define=SUPABASE_ANON_KEY=...
```

La résolution d'un code de partage doit passer par une Supabase Edge Function : elle vérifiera le code (stocké sous forme de hash), les pièces autorisées et l'expiration, puis écrira le journal de consultation. Le rôle `service_role` ne doit jamais être intégré à l'application mobile.

## Fonctions à terminer

- Création et révocation de codes aléatoires avec expiration, liste de pièces autorisées et Edge Function de consultation.
- Remplacement des cartes et journaux de démonstration par les consultations et données réelles.
- Chiffrement local des fichiers et ajout de la gestion de clés avant une mise en production.

La clé Supabase publique est fournie au build via `--dart-define`; ne mets jamais la clé `service_role` dans l'application. Le partage par code doit être assuré côté serveur par une Edge Function, avec des codes aléatoires stockés sous forme de hash, une expiration/révocation et des URL temporaires vers le bucket privé.
