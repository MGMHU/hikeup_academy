-- Fichier joint à un rendu d'exercice
alter table submissions add column if not exists file_name text;
alter table submissions add column if not exists file_size text;

-- Notifications : chacun peut prévenir un collègue (question à un expert, session planifiée…)
drop policy if exists notif_insert on notifications;
create policy notif_insert on notifications for insert to authenticated with check (true);

-- Vérifier une réponse de quiz sans rien enregistrer (retour immédiat question par question)
create or replace function check_answer(p_question uuid, p_option text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'correct', coalesce((select (o->>'correct')::boolean from jsonb_array_elements(q.options) o where o->>'id' = p_option), false),
    'feedback', (select o->>'feedback' from jsonb_array_elements(q.options) o where o->>'id' = p_option),
    'correct_option', (select o->>'id' from jsonb_array_elements(q.options) o where (o->>'correct')::boolean limit 1),
    'explanation', q.explanation)
  from questions q where q.id = p_question;
$$;
revoke execute on function check_answer(uuid, text) from public, anon;
grant execute on function check_answer(uuid, text) to authenticated;

-- Badge du module et certificat du cursus attribués côté serveur quand une leçon est validée
create or replace function award_on_progress() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_module uuid; v_path uuid; v_total int; v_done int;
begin
  if new.status <> 'completed' then return new; end if;
  select m.id, m.path_id into v_module, v_path from lessons l join chapters c on c.id = l.chapter_id join modules m on m.id = c.module_id where l.id = new.lesson_id;
  select count(*), count(p.lesson_id) filter (where p.status = 'completed') into v_total, v_done
    from lessons l join chapters c on c.id = l.chapter_id left join progress p on p.lesson_id = l.id and p.user_id = new.user_id
    where c.module_id = v_module;
  if v_total > 0 and v_total = v_done then
    insert into user_badges (user_id, module_id) values (new.user_id, v_module) on conflict do nothing;
    select count(*), count(p.lesson_id) filter (where p.status = 'completed') into v_total, v_done
      from lessons l join chapters c on c.id = l.chapter_id join modules m on m.id = c.module_id
      left join progress p on p.lesson_id = l.id and p.user_id = new.user_id
      where m.path_id = v_path;
    if v_total > 0 and v_total = v_done then
      insert into certificates (user_id, path_id) values (new.user_id, v_path) on conflict do nothing;
    end if;
  end if;
  return new;
end $$;
revoke execute on function award_on_progress() from public, anon;
revoke execute on function award_on_progress() from authenticated;
drop trigger if exists trg_award_on_progress on progress;
create trigger trg_award_on_progress after insert or update of status on progress for each row execute function award_on_progress();
