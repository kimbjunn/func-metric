-- ============================================================================
-- Supabase schema v3 — self-registration (user-set ID/PW) + recovery
-- Run ONCE: Supabase dashboard -> SQL Editor -> paste all -> Run.
-- ============================================================================
create extension if not exists pgcrypto with schema extensions;  -- bcrypt for passwords

drop table if exists survey_responses cascade;
drop table if exists survey_progress  cascade;
drop table if exists allowed_raters   cascade;
drop function if exists survey_save(text,text,jsonb,jsonb,text,boolean);

-- Accounts + demographics + progress, one row per participant.
create table if not exists raters (
  rater_id       text primary key,                 -- user-chosen
  password_hash  text not null,                    -- bcrypt
  email          text not null,                    -- recovery anchor
  group_id       int  not null,                    -- auto-assigned, balanced
  rubric_variant text not null,                    -- A/B
  personal       jsonb,                            -- {affiliation,years,re_exp,prog_exp,consent}
  ratings        jsonb not null default '{}'::jsonb,
  submitted      boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index if not exists raters_email_lower on raters (lower(email));

-- Optional study-wide invite gate (off unless a row exists).
create table if not exists survey_config (key text primary key, value text);
-- To REQUIRE an invite code for signup:  insert into survey_config values ('invite_code','YOUR-CODE');

alter table raters        enable row level security;
alter table survey_config enable row level security;
revoke all on raters        from anon;
revoke all on survey_config from anon;

-- SIGNUP: create account (checks id/email uniqueness, optional invite, balances group)
create or replace function survey_signup(p_id text, p_pw text, p_email text, p_personal jsonb, p_invite text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_need text; v_g1 int; v_g2 int; v_grp int; v_var text;
begin
  select value into v_need from survey_config where key='invite_code';
  if v_need is not null and coalesce(p_invite,'') <> v_need then return jsonb_build_object('ok',false,'reason','invite'); end if;
  if length(coalesce(p_id,''))<3 or length(coalesce(p_pw,''))<4 then return jsonb_build_object('ok',false,'reason','short'); end if;
  if exists(select 1 from raters where rater_id=p_id) then return jsonb_build_object('ok',false,'reason','id_taken'); end if;
  if exists(select 1 from raters where lower(email)=lower(p_email)) then return jsonb_build_object('ok',false,'reason','email_taken'); end if;
  select count(*) filter (where group_id=1), count(*) filter (where group_id=2) into v_g1,v_g2 from raters;
  v_grp := case when coalesce(v_g1,0) <= coalesce(v_g2,0) then 1 else 2 end;
  v_var := case when (abs(hashtext(p_id))%2)=0 then 'A' else 'B' end;
  insert into raters(rater_id,password_hash,email,group_id,rubric_variant,personal)
    values (p_id, crypt(p_pw, gen_salt('bf')), p_email, v_grp, v_var, p_personal);
  return jsonb_build_object('ok',true,'group_id',v_grp,'rubric_variant',v_var);
end $$;

-- LOGIN
create or replace function survey_login(p_id text, p_pw text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r raters;
begin
  select * into r from raters where rater_id=p_id;
  if r.rater_id is null or r.password_hash <> crypt(p_pw, r.password_hash) then return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',true,'group_id',r.group_id,'rubric_variant',r.rubric_variant,
    'ratings',r.ratings,'personal',r.personal,'submitted',r.submitted);
end $$;

-- SAVE (checkpoint / submit)
create or replace function survey_save(p_id text, p_pw text, p_ratings jsonb, p_submitted boolean)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r raters;
begin
  select * into r from raters where rater_id=p_id;
  if r.rater_id is null or r.password_hash <> crypt(p_pw, r.password_hash) then return jsonb_build_object('ok',false); end if;
  update raters set ratings=coalesce(p_ratings,'{}'::jsonb), submitted=coalesce(p_submitted,false), updated_at=now() where rater_id=p_id;
  return jsonb_build_object('ok',true);
end $$;

-- RECOVERY: find ID by email
create or replace function survey_find_id(p_email text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_id text;
begin
  select rater_id into v_id from raters where lower(email)=lower(p_email) limit 1;
  if v_id is null then return jsonb_build_object('found',false); end if;
  return jsonb_build_object('found',true,'rater_id',v_id);
end $$;

-- RECOVERY: reset password with ID + matching email
create or replace function survey_reset_pw(p_id text, p_email text, p_new_pw text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  if length(coalesce(p_new_pw,''))<4 then return jsonb_build_object('ok',false,'reason','short'); end if;
  if not exists(select 1 from raters where rater_id=p_id and lower(email)=lower(p_email)) then return jsonb_build_object('ok',false,'reason','nomatch'); end if;
  update raters set password_hash=crypt(p_new_pw, gen_salt('bf')), updated_at=now() where rater_id=p_id;
  return jsonb_build_object('ok',true);
end $$;

grant execute on function survey_signup(text,text,text,jsonb,text) to anon;
grant execute on function survey_login(text,text) to anon;
grant execute on function survey_save(text,text,jsonb,boolean) to anon;
grant execute on function survey_find_id(text) to anon;
grant execute on function survey_reset_pw(text,text,text) to anon;

notify pgrst, 'reload schema';
