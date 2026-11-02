do $$
declare t text;
begin
  foreach t in array array['profiles','roles','user_roles','tools','paths','path_enrollments','modules','chapters','lessons','quizzes','questions',
    'quiz_attempts','exercises','submissions','progress','user_badges','certificates','assignments','experts','comments','sessions','resources',
    'notifications','folders','folder_paths','user_folders','ai_generations'] loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- Annuaire interne lisible par toute l'équipe ; chacun modifie son profil, l'admin gère tout
create policy profiles_read  on profiles for select to authenticated using (true);
create policy profiles_self  on profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_admin on profiles for all    to authenticated using (has_role('admin')) with check (has_role('admin'));
create policy roles_list     on roles for select to authenticated using (true);
create policy uroles_read    on user_roles for select to authenticated using (true);
create policy uroles_admin   on user_roles for all    to authenticated using (has_role('admin')) with check (has_role('admin'));

-- Contenu et organisation : lecture pour l'équipe, écriture admin
do $$
declare t text;
begin
  foreach t in array array['tools','paths','modules','chapters','lessons','quizzes','exercises','resources','assignments','experts',
    'path_enrollments','folders','folder_paths','user_folders'] loop
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_read', t);
    execute format('create policy %I on %I for all to authenticated using (has_role(''admin'')) with check (has_role(''admin''))', t || '_admin', t);
  end loop;
end $$;

-- Questions (contiennent les bonnes réponses) : admin et référents ; les consultants passent par get_quiz()
create policy questions_admin on questions for all    to authenticated using (has_role('admin')) with check (has_role('admin'));
create policy questions_ref   on questions for select to authenticated using (has_role('referent'));

-- Tentatives de quiz : écriture via submit_quiz()
create policy attempts_read on quiz_attempts for select to authenticated
  using (user_id = auth.uid() or is_referent_of(user_id) or has_role('admin'));

-- Progression : un consultant valide lui-même les leçons de contenu, pas les quiz ni les exercices
create policy progress_self   on progress for all to authenticated using (user_id = auth.uid())
  with check (user_id = auth.uid() and (status = 'in_progress' or is_content_lesson(lesson_id)));
create policy progress_follow on progress for select to authenticated using (is_referent_of(user_id) or has_role('admin'));

-- Exercices rendus
create policy subm_self_read   on submissions for select to authenticated using (user_id = auth.uid());
create policy subm_self_insert on submissions for insert to authenticated with check (user_id = auth.uid() and status = 'submitted');
create policy subm_review      on submissions for select to authenticated using (is_referent_of(user_id) or has_role('admin'));
create policy subm_review_upd  on submissions for update to authenticated using (is_referent_of(user_id) or has_role('admin'))
  with check (is_referent_of(user_id) or has_role('admin'));

-- Badges et certificats
create policy badges_read on user_badges  for select to authenticated using (true);
create policy badges_adm  on user_badges  for all    to authenticated using (has_role('admin')) with check (has_role('admin'));
create policy certs_read  on certificates for select to authenticated using (user_id = auth.uid() or is_referent_of(user_id) or has_role('admin'));
create policy certs_adm   on certificates for all    to authenticated using (has_role('admin')) with check (has_role('admin'));

-- Questions posées sur les leçons
create policy comments_read   on comments for select to authenticated using (true);
create policy comments_insert on comments for insert to authenticated with check (author_id = auth.uid());
create policy comments_update on comments for update to authenticated
  using (author_id = auth.uid() or is_expert_of_lesson(lesson_id) or has_role('admin'));

-- Planning
create policy sessions_read  on sessions for select to authenticated
  using (consultant_id = auth.uid() or host_id = auth.uid() or is_referent_of(consultant_id) or has_role('admin'));
create policy sessions_write on sessions for all to authenticated
  using (has_role('admin') or is_referent_of(consultant_id)) with check (has_role('admin') or is_referent_of(consultant_id));

-- Notifications
create policy notif_self   on notifications for select to authenticated using (user_id = auth.uid());
create policy notif_mark   on notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notif_insert on notifications for insert to authenticated with check (has_role('admin') or has_role('referent') or user_id = auth.uid());

-- Historique des générations IA
create policy ai_generations_admin on ai_generations for all to authenticated using (has_role('admin')) with check (has_role('admin'));

-- Stockage privé des exercices : chaque personne dépose dans <son id>/...
insert into storage.buckets (id, name, public) values ('submissions', 'submissions', false) on conflict do nothing;
create policy subm_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'submissions' and (storage.foldername(name))[1] = auth.uid()::text);
create policy subm_download on storage.objects for select to authenticated
  using (bucket_id = 'submissions' and ((storage.foldername(name))[1] = auth.uid()::text
    or is_referent_of(((storage.foldername(name))[1])::uuid) or has_role('admin')));

-- Outils de départ
insert into tools (slug, name, color) values
  ('catchup', 'Catch Up', '#266DF0'), ('bizzy', 'Bizzy', '#2f4dcb'), ('clay', 'Clay', '#126b76'),
  ('fullenrich', 'Fullenrich', '#1f7a3e'), ('salesnav', 'Sales Navigator', '#2f4dcb'),
  ('snitcher', 'Snitcher', '#8a6500'), ('gtm', 'Google Tag Manager', '#6b6b75')
on conflict (slug) do nothing;

-- Dossiers de départ
insert into folders (name, description, color, position) values
  ('Consultant', 'Recherche, enrichissement et personnalisation de listes de prospection.', '#266DF0', 1),
  ('Business developer', 'Prospection téléphonique, prise de rendez-vous et suivi client.', '#1f7a3e', 2),
  ('Référent', 'Accompagner les nouveaux consultants : suivi, corrections, sessions.', '#8a6500', 3);
