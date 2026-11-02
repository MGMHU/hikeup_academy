# Hike UP Academy

Plateforme interne d'onboarding des consultants Hike UP. Une seule page (`index.html`) reliée au projet Supabase « Hike UP Academy » (`gmepwukdefzzflkpywdd`, Francfort).

- Version de démonstration (données fictives, rien n'est enregistré) : ajouter `?demo` à l'adresse.
- La clé présente dans `index.html` est la clé publique Supabase : elle est faite pour être visible. Les droits sont appliqués par la base (règles d'accès par rôle).
- La clé Claude du Studio IA n'est jamais dans la page : elle est lue côté serveur dans le secret `ANTHROPIC_API_KEY`.

## Contenu du dépôt

| Élément | Rôle |
|---|---|
| `index.html` | L'application |
| `supabase/migrations/` | Structure de la base, règles d'accès, fonctions (déjà appliquées au projet) |
| `supabase/functions/invite-user` | Invitation d'un utilisateur par e-mail (réservé aux administrateurs) |
| `supabase/functions/generate-course` | Studio IA : génération de cursus avec Claude (réservé aux administrateurs) |

## Mise en ligne, une seule fois

1. **Hébergement** : Netlify ou Cloudflare Pages, relié à ce dépôt, sans étape de build (dossier publié : la racine). GitHub Pages fonctionne aussi si le dépôt est public ou sur un plan payant.
2. **Adresses autorisées** dans Supabase, Authentication, URL Configuration :
   - Site URL : l'adresse de l'Academy (ex. `https://academy-hikeup.netlify.app`)
   - Redirect URLs : la même adresse suivie de `/**`
3. **Clé Claude** : Supabase, Edge Functions, Secrets, ajouter `ANTHROPIC_API_KEY`.
4. **Premier administrateur** : Supabase, Authentication, Users, « Invite user » avec votre e-mail. Ouvrez le lien reçu, choisissez votre mot de passe, puis dans SQL Editor :
   ```sql
   insert into user_roles (user_id, role_code)
   select id, 'admin' from profiles where email = 'votre.email@hike-up.be';
   ```
5. **Cours de départ** : connecté en administrateur, page « Vue globale », bouton « Charger les cours de départ » (5 cursus, 95 leçons, quiz et ressources, modifiables ensuite).

## Ajouter l'équipe

Administration, Utilisateurs, « Nouvel utilisateur » : la personne reçoit un e-mail d'invitation, choisit son mot de passe et arrive sur ses cursus. Placez-la dans un dossier (Consultant, Business developer, Référent) : elle est inscrite automatiquement aux cursus publiés de ce dossier.

L'envoi d'e-mails par défaut de Supabase est limité à quelques messages par heure. Pour inviter toute l'équipe d'un coup, branchez un SMTP (Authentication, Emails, SMTP Settings), par exemple celui de Google Workspace ou Brevo.

## Qui décide de quoi

- Quiz : corrigés par la base, les bonnes réponses ne sont jamais envoyées au navigateur d'un consultant.
- Badges de module et certificats : attribués par la base quand toutes les leçons sont validées.
- Exercices : fichiers dans un stockage privé (lisibles par l'auteur, son référent et les administrateurs) ; la validation par le référent valide la leçon.
