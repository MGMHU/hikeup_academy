-- Personne d'extérieur (anon) ne peut appeler les fonctions ; les fonctions internes (triggers, synchronisation) ne sont pas appelables depuis l'API
revoke execute on function get_quiz(uuid), submit_quiz(uuid, jsonb), has_role(text), is_referent_of(uuid), is_expert_of_lesson(uuid),
  is_content_lesson(uuid), handle_new_user(), notify_submission(), notify_enrollment(), sync_folder_enrollments(uuid),
  trg_sync_folder(), trg_path_published() from public, anon;
revoke execute on function handle_new_user(), notify_submission(), notify_enrollment(), sync_folder_enrollments(uuid),
  trg_sync_folder(), trg_path_published() from authenticated;
grant execute on function get_quiz(uuid), submit_quiz(uuid, jsonb), has_role(text), is_referent_of(uuid), is_expert_of_lesson(uuid),
  is_content_lesson(uuid) to authenticated;
alter default privileges in schema public revoke execute on functions from public, anon;
