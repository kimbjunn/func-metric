-- Supabase schema for the function-name role-similarity survey.
-- Run this once in the Supabase dashboard: SQL Editor -> paste -> Run.
-- One denormalized table = long-format, analysis-ready (one row per rated pair).

create table if not exists survey_responses (
  id                      bigint generated always as identity primary key,
  submission_uuid         text not null,                  -- groups all rows from one submit
  submitted_at            timestamptz not null default now(),
  -- respondent info (collected with explicit consent)
  rater_id                text,
  email                   text,
  affiliation             text,
  years_experience        int,
  re_experience           text,        -- none | basic | intermediate | expert
  programming_experience  text,        -- basic | intermediate | advanced
  consent                 boolean,
  group_id                int,
  rubric_variant          text,        -- A | B  (anchor wording, for circularity check)
  session_started_at      timestamptz,
  -- one rated pair
  block                   int,
  masked_model            text,        -- A-D ; join to true model offline via 10_human_eval_sample.csv
  gt                      text,
  pred                    text,
  score                   int,         -- 1..5
  client_ts               timestamptz
);

-- Privacy: anon (public) key may INSERT only. No SELECT/UPDATE/DELETE policy ->
-- responses CANNOT be read back with the public key. Read your data from the
-- Supabase dashboard (Table editor / SQL) or via the service_role key (keep secret).
alter table survey_responses enable row level security;

create policy "anon_insert_only"
  on survey_responses for insert to anon
  with check (true);

create index if not exists idx_sr_submission on survey_responses (submission_uuid);
create index if not exists idx_sr_rater on survey_responses (rater_id);
