create extension if not exists pgcrypto;

-- 1. Utilisateurs, droits
create table if not exists profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text not null,
  full_name   text,
  avatar_url  text,
  job_title   text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create table if not exists roles (code text primary key, label text not null);
insert into roles (code, label) values
  ('admin', 'Administrer'), ('referent', 'Accompagner'), ('consultant', 'Consultant (historique, la formation vient des dossiers)')
on conflict do nothing;
create table if not exists user_roles (
  user_id   uuid references profiles(id) on delete cascade,
  role_code text references roles(code),
  primary key (user_id, role_code)
);
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)))
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

-- 2. Outils métier
create table if not exists tools (id uuid primary key default gen_random_uuid(), slug text unique not null, name text not null, color text);

-- 3. Structure pédagogique
create table if not exists paths (
  id uuid primary key default gen_random_uuid(), title text not null, description text,
  unlock_mode text not null default 'sequential' check (unlock_mode in ('sequential', 'free')),
  published boolean not null default false, source text not null default 'manual', created_at timestamptz not null default now()
);
create table if not exists path_enrollments (
  id uuid primary key default gen_random_uuid(),
  path_id uuid references paths(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  assigned_by uuid references profiles(id),
  start_date date not null default current_date, due_date date,
  created_at timestamptz not null default now(),
  unique (path_id, user_id)
);
create table if not exists modules (
  id uuid primary key default gen_random_uuid(),
  path_id uuid references paths(id) on delete cascade,
  position int not null, title text not null, objective text, est_minutes int,
  prerequisites uuid[] not null default '{}',
  tool_id uuid references tools(id), badge_label text, badge_icon text
);
create table if not exists chapters (
  id uuid primary key default gen_random_uuid(),
  module_id uuid references modules(id) on delete cascade,
  position int not null, title text not null
);
create table if not exists lessons (
  id uuid primary key default gen_random_uuid(),
  chapter_id uuid references chapters(id) on delete cascade,
  position int not null, title text not null,
  kind text not null default 'content' check (kind in ('content', 'quiz', 'exercise')),
  est_minutes int, blocks jsonb not null default '[]'::jsonb, updated_at timestamptz not null default now()
);

-- 4. Evaluation
create table if not exists quizzes (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid unique references lessons(id) on delete cascade,
  pass_score int not null default 80, max_attempts int
);
create table if not exists questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid references quizzes(id) on delete cascade,
  position int not null, prompt text not null,
  options jsonb not null default '[]'::jsonb, explanation text
);
create table if not exists quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid references quizzes(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  answers jsonb not null, score int not null, passed boolean not null,
  created_at timestamptz not null default now()
);
create table if not exists exercises (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid unique references lessons(id) on delete cascade,
  instructions text,
  submission_type text not null default 'both' check (submission_type in ('file', 'link', 'both'))
);
create table if not exists submissions (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid references exercises(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  version int not null default 1, file_path text, link_url text, note text,
  status text not null default 'submitted' check (status in ('submitted', 'changes_requested', 'validated')),
  reviewer_id uuid references profiles(id), review_comment text, reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

-- 5. Progression, badges, certificats
create table if not exists progress (
  user_id uuid references profiles(id) on delete cascade,
  lesson_id uuid references lessons(id) on delete cascade,
  status text not null default 'in_progress' check (status in ('in_progress', 'completed')),
  checklist jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(), completed_at timestamptz,
  primary key (user_id, lesson_id)
);
create table if not exists user_badges (
  user_id uuid references profiles(id) on delete cascade,
  module_id uuid references modules(id) on delete cascade,
  awarded_at timestamptz not null default now(),
  primary key (user_id, module_id)
);
create table if not exists certificates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) on delete cascade,
  path_id uuid references paths(id) on delete cascade,
  code text unique not null default upper(substr(md5(gen_random_uuid()::text), 1, 10)),
  issued_at timestamptz not null default now(),
  unique (user_id, path_id)
);

-- 6. Accompagnement
create table if not exists assignments (
  id uuid primary key default gen_random_uuid(),
  consultant_id uuid references profiles(id) on delete cascade,
  referent_id uuid references profiles(id) on delete cascade,
  is_primary boolean not null default true,
  unique (consultant_id, referent_id)
);
create table if not exists experts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) on delete cascade,
  module_id uuid references modules(id) on delete cascade,
  tool_id uuid references tools(id) on delete cascade,
  check (module_id is not null or tool_id is not null)
);
create table if not exists comments (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid references lessons(id) on delete cascade,
  author_id uuid references profiles(id) on delete cascade,
  parent_id uuid references comments(id) on delete cascade,
  body text not null, resolved boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists sessions (
  id uuid primary key default gen_random_uuid(),
  consultant_id uuid references profiles(id) on delete cascade,
  host_id uuid references profiles(id) on delete cascade,
  module_id uuid references modules(id) on delete set null,
  kind text not null default 'point' check (kind in ('shadowing', 'point', 'atelier')),
  title text, starts_at timestamptz not null, duration_min int not null default 30, done boolean not null default false
);
create table if not exists resources (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('prompt', 'checklist', 'glossary', 'template')),
  title text not null, body text, tool_id uuid references tools(id),
  tags text[] not null default '{}', updated_at timestamptz not null default now()
);
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) on delete cascade,
  kind text not null, title text not null, body text, link text,
  read_at timestamptz, created_at timestamptz not null default now()
);

-- 7. Dossiers par rôle (tronc commun = cursus lié à plusieurs dossiers) et studio IA
create table if not exists folders (
  id uuid primary key default gen_random_uuid(), name text not null, description text,
  color text not null default '#266DF0', position int not null default 1, created_at timestamptz not null default now()
);
create table if not exists folder_paths (
  folder_id uuid references folders(id) on delete cascade,
  path_id uuid references paths(id) on delete cascade,
  position int not null default 1,
  primary key (folder_id, path_id)
);
create table if not exists user_folders (
  user_id uuid references profiles(id) on delete cascade,
  folder_id uuid references folders(id) on delete cascade,
  primary key (user_id, folder_id)
);
create table if not exists ai_generations (
  id uuid primary key default gen_random_uuid(),
  path_id uuid references paths(id) on delete set null,
  engine text not null, kind text, created_by uuid references profiles(id),
  settings jsonb, sources jsonb, result jsonb, created_at timestamptz not null default now()
);
