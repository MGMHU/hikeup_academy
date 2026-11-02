-- Fonctions d'autorisation
create or replace function has_role(r text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from user_roles where user_id = auth.uid() and role_code = r);
$$;
create or replace function is_referent_of(consultant uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from assignments where referent_id = auth.uid() and consultant_id = consultant);
$$;
create or replace function is_expert_of_lesson(l uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from lessons le join chapters c on c.id = le.chapter_id join modules m on m.id = c.module_id
    join experts e on (e.module_id = m.id or e.tool_id = m.tool_id)
    where le.id = l and e.user_id = auth.uid());
$$;
create or replace function is_content_lesson(l uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from lessons where id = l and kind = 'content');
$$;

-- Quiz : lecture sans les bonnes réponses, correction côté serveur
create or replace function get_quiz(p_quiz uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'quiz', to_jsonb(q),
    'questions', coalesce((
      select jsonb_agg(jsonb_build_object('id', qu.id, 'position', qu.position, 'prompt', qu.prompt,
        'options', (select jsonb_agg(o - 'correct' - 'feedback') from jsonb_array_elements(qu.options) o)) order by qu.position)
      from questions qu where qu.quiz_id = q.id), '[]'::jsonb))
  from quizzes q where q.id = p_quiz;
$$;
create or replace function submit_quiz(p_quiz uuid, p_answers jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_total int; v_ok int := 0; v_score int; v_pass int; v_passed boolean;
  v_feedback jsonb := '[]'::jsonb; v_q record; v_chosen text; v_opt jsonb; v_lesson uuid; v_enrolled boolean;
begin
  select pass_score, lesson_id into v_pass, v_lesson from quizzes where id = p_quiz;
  select count(*) into v_total from questions where quiz_id = p_quiz;
  for v_q in select * from questions where quiz_id = p_quiz order by position loop
    v_chosen := p_answers->>(v_q.id::text);
    select o into v_opt from jsonb_array_elements(v_q.options) o where o->>'id' = v_chosen;
    if coalesce((v_opt->>'correct')::boolean, false) then v_ok := v_ok + 1; end if;
    v_feedback := v_feedback || jsonb_build_object('question_id', v_q.id,
      'correct', coalesce((v_opt->>'correct')::boolean, false), 'feedback', v_opt->>'feedback', 'explanation', v_q.explanation,
      'correct_option', (select o->>'id' from jsonb_array_elements(v_q.options) o where (o->>'correct')::boolean limit 1));
  end loop;
  v_score := case when v_total = 0 then 0 else round(100.0 * v_ok / v_total) end;
  v_passed := v_score >= v_pass;
  -- Essai (référent, admin non inscrit) : correction renvoyée, rien n'est enregistré
  select exists (select 1 from path_enrollments pe join modules m on m.path_id = pe.path_id join chapters c on c.module_id = m.id
                 join lessons l on l.chapter_id = c.id where l.id = v_lesson and pe.user_id = auth.uid()) into v_enrolled;
  if v_enrolled then
    insert into quiz_attempts (quiz_id, user_id, answers, score, passed) values (p_quiz, auth.uid(), p_answers, v_score, v_passed);
    if v_passed then
      insert into progress (user_id, lesson_id, status, completed_at) values (auth.uid(), v_lesson, 'completed', now())
        on conflict (user_id, lesson_id) do update set status = 'completed', completed_at = now();
    end if;
  end if;
  return jsonb_build_object('score', v_score, 'passed', v_passed, 'pass_score', v_pass, 'recorded', v_enrolled, 'feedback', v_feedback);
end $$;

-- Notifications automatiques
create or replace function notify_submission() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_name text; v_lesson uuid;
begin
  select full_name into v_name from profiles where id = new.user_id;
  select lesson_id into v_lesson from exercises where id = new.exercise_id;
  if tg_op = 'INSERT' then
    insert into notifications (user_id, kind, title, body, link)
      select a.referent_id, 'to_review', 'Exercice à corriger', coalesce(v_name, 'Un consultant') || ' a déposé un exercice.', '#/ref-corrections'
      from assignments a where a.consultant_id = new.user_id;
  elsif new.status is distinct from old.status and new.status in ('validated', 'changes_requested') then
    insert into notifications (user_id, kind, title, body, link)
      values (new.user_id, 'reviewed', case when new.status = 'validated' then 'Exercice validé' else 'Correction demandée' end,
              new.review_comment, '#/lesson/' || v_lesson);
    if new.status = 'validated' then
      insert into progress (user_id, lesson_id, status, completed_at) values (new.user_id, v_lesson, 'completed', now())
        on conflict (user_id, lesson_id) do update set status = 'completed', completed_at = now();
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_notify_submission on submissions;
create trigger trg_notify_submission after insert or update on submissions for each row execute function notify_submission();

create or replace function notify_enrollment() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into notifications (user_id, kind, title, body, link)
    select new.user_id, 'assignment', 'Nouveau cursus assigné', p.title, '#/parcours' from paths p where p.id = new.path_id;
  return new;
end $$;
drop trigger if exists trg_notify_enrollment on path_enrollments;
create trigger trg_notify_enrollment after insert on path_enrollments for each row execute function notify_enrollment();

-- Inscription automatique des membres d'un dossier à ses cursus publiés
create or replace function sync_folder_enrollments(p_folder uuid) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into path_enrollments (path_id, user_id, start_date, due_date)
    select fp.path_id, uf.user_id, current_date, current_date + 14
    from folder_paths fp join user_folders uf on uf.folder_id = fp.folder_id join paths p on p.id = fp.path_id and p.published
    where fp.folder_id = p_folder
    on conflict (path_id, user_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
create or replace function trg_sync_folder() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform sync_folder_enrollments(new.folder_id); return new; end $$;
drop trigger if exists trg_user_folders_sync on user_folders;
create trigger trg_user_folders_sync after insert on user_folders for each row execute function trg_sync_folder();
drop trigger if exists trg_folder_paths_sync on folder_paths;
create trigger trg_folder_paths_sync after insert on folder_paths for each row execute function trg_sync_folder();
create or replace function trg_path_published() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.published and not coalesce(old.published, false) then
    perform sync_folder_enrollments(fp.folder_id) from folder_paths fp where fp.path_id = new.id;
  end if;
  return new;
end $$;
drop trigger if exists trg_paths_published on paths;
create trigger trg_paths_published after update of published on paths for each row execute function trg_path_published();

-- Vues (respectent les droits de la personne connectée)
create or replace view module_progress with (security_invoker = on) as
select pe.user_id, m.id as module_id, m.path_id, m.position,
       count(l.id) as lessons_total,
       count(pr.lesson_id) filter (where pr.status = 'completed') as lessons_done,
       case when count(l.id) = 0 then 0 else round(100.0 * count(pr.lesson_id) filter (where pr.status = 'completed') / count(l.id)) end as pct
from path_enrollments pe join modules m on m.path_id = pe.path_id join chapters c on c.module_id = m.id
join lessons l on l.chapter_id = c.id left join progress pr on pr.lesson_id = l.id and pr.user_id = pe.user_id
group by pe.user_id, m.id, m.path_id, m.position;
create or replace view common_paths with (security_invoker = on) as
  select path_id, count(*) as folders_count from folder_paths group by path_id having count(*) > 1;
