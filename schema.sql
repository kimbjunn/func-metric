-- ============================================================================
-- Supabase schema v2 — gated login + per-rater checkpoint/resume
-- Run ONCE: Supabase dashboard -> SQL Editor -> paste all -> Run.
-- (The earlier 404 "Could not find table survey_responses" just meant the
--  schema had not been created yet. This v2 replaces that design.)
-- ============================================================================

drop table if exists survey_responses cascade;   -- remove old insert-only design if present

-- 1) Allowed raters (researcher seeds these). password = study access code.
create table if not exists allowed_raters (
  rater_id  text primary key,
  password  text not null,
  group_id  int  not null default 1            -- 1 or 2; core blocks shown to all
);

-- 2) Per-rater progress (jsonb checkpoint -> resume on any device)
create table if not exists survey_progress (
  rater_id        text primary key references allowed_raters(rater_id),
  personal        jsonb,
  ratings         jsonb not null default '{}'::jsonb,
  rubric_variant  text,
  submitted       boolean not null default false,
  started_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- 3) Lock tables: no direct anon access; all access via password-checked RPCs.
alter table allowed_raters  enable row level security;
alter table survey_progress enable row level security;
revoke all on allowed_raters  from anon;
revoke all on survey_progress from anon;

-- 4) LOGIN: verify (rater,password); return group + saved progress.
create or replace function survey_login(p_rater text, p_pw text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_grp int; v_row survey_progress;
begin
  select group_id into v_grp from allowed_raters where rater_id = p_rater and password = p_pw;
  if v_grp is null then return jsonb_build_object('ok', false); end if;
  select * into v_row from survey_progress where rater_id = p_rater;
  return jsonb_build_object(
    'ok', true, 'group_id', v_grp,
    'ratings',   coalesce(v_row.ratings, '{}'::jsonb),
    'personal',  v_row.personal,
    'rubric_variant', v_row.rubric_variant,
    'submitted', coalesce(v_row.submitted, false));
end $$;

-- 5) SAVE: checkpoint or final submit; verify (rater,password); upsert progress.
create or replace function survey_save(
  p_rater text, p_pw text, p_personal jsonb, p_ratings jsonb, p_variant text, p_submitted boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_grp int;
begin
  select group_id into v_grp from allowed_raters where rater_id = p_rater and password = p_pw;
  if v_grp is null then return jsonb_build_object('ok', false); end if;
  insert into survey_progress(rater_id, personal, ratings, rubric_variant, submitted, updated_at)
    values (p_rater, p_personal, coalesce(p_ratings,'{}'::jsonb), p_variant, coalesce(p_submitted,false), now())
  on conflict (rater_id) do update set
    personal       = coalesce(excluded.personal, survey_progress.personal),
    ratings        = excluded.ratings,
    rubric_variant = coalesce(excluded.rubric_variant, survey_progress.rubric_variant),
    submitted      = excluded.submitted,
    updated_at     = now();
  return jsonb_build_object('ok', true);
end $$;

grant execute on function survey_login(text,text) to anon;
grant execute on function survey_save(text,text,jsonb,jsonb,text,boolean) to anon;

-- 6) Seed your raters (EDIT passwords; add ~10). group_id = 1 or 2.
insert into allowed_raters(rater_id, password, group_id) values
  ('rater01','CHANGE-ME-01',1),
  ('rater02','CHANGE-ME-02',2),
  ('rater03','CHANGE-ME-03',1)
on conflict (rater_id) do nothing;

-- 7) Refresh PostgREST schema cache (so RPCs are visible immediately).
notify pgrst, 'reload schema';
