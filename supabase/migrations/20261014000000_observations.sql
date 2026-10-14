-- Christman Field Observations - database update 2 (Oct 14, 2026).
-- Run in Supabase > SQL Editor after the first setup script. Safe to run more than once.
--
-- Adds: project & category abbreviations, observation numbers (e.g. NCMC-MEP-001),
-- observation type, location, due date, voice messages, the new status workflow,
-- per-project access (members only, optional read-only guests), and member invitations.

-- =====================================================================
-- Projects
-- =====================================================================
alter table public.projects add column if not exists abbr text not null default '';
alter table public.projects add column if not exists category_abbrs jsonb not null default '{}'::jsonb;
alter table public.projects add column if not exists guest_visible boolean not null default false;

-- Default project abbreviation: initials of the name, skipping the word "Project".
update public.projects p
set abbr = coalesce(nullif(upper((
  select string_agg(left(w, 1), '')
  from regexp_split_to_table(p.name, '\s+') w
  where w ~ '^[A-Za-z0-9]' and lower(w) <> 'project'
)), ''), 'PRJ')
where p.abbr = '';

-- Default category abbreviations.
update public.projects p
set category_abbrs = (
  select coalesce(jsonb_object_agg(c, case c
      when 'Safety' then 'SAF' when 'MEP' then 'MEP' when 'Steel' then 'STL'
      when 'Structure' then 'STR' when 'Architecture' then 'ARC'
      else upper(left(regexp_replace(c, '[^A-Za-z0-9]', '', 'g'), 3)) end), '{}'::jsonb)
  from unnest(p.categories) c)
where p.category_abbrs = '{}'::jsonb;

-- New or renamed projects: fill in a missing project abbreviation and any missing
-- category abbreviations automatically (the app normally asks for them).
create or replace function public.project_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if coalesce(new.abbr, '') = '' then
    new.abbr := coalesce(nullif(upper((
      select string_agg(left(w, 1), '')
      from regexp_split_to_table(new.name, '\s+') w
      where w ~ '^[A-Za-z0-9]' and lower(w) <> 'project'
    )), ''), 'PRJ');
  end if;
  new.abbr := upper(new.abbr);
  if new.category_abbrs is null then new.category_abbrs := '{}'::jsonb; end if;
  foreach c in array coalesce(new.categories, '{}') loop
    if coalesce(new.category_abbrs ->> c, '') = '' then
      new.category_abbrs := new.category_abbrs || jsonb_build_object(c, case c
        when 'Safety' then 'SAF' when 'MEP' then 'MEP' when 'Steel' then 'STL'
        when 'Structure' then 'STR' when 'Architecture' then 'ARC'
        else upper(left(regexp_replace(c, '[^A-Za-z0-9]', '', 'g'), 3)) end);
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists projects_defaults on public.projects;
create trigger projects_defaults before insert or update on public.projects
  for each row execute function public.project_defaults();

-- =====================================================================
-- People: company / trade (e.g. "Mechanical Contractor")
-- =====================================================================
alter table public.profiles add column if not exists company text not null default '';

-- =====================================================================
-- Observations: new fields
-- =====================================================================
alter table public.notes add column if not exists obs_type text not null default 'general';
alter table public.notes add column if not exists location text not null default '';
alter table public.notes add column if not exists due_at timestamptz;
alter table public.notes add column if not exists number int;
alter table public.notes add column if not exists code text not null default '';
alter table public.notes add column if not exists audio text[] not null default '{}';
alter table public.replies add column if not exists audio text[] not null default '{}';

alter table public.notes drop constraint if exists notes_obs_type_check;
alter table public.notes add constraint notes_obs_type_check check (obs_type in
  ('field_observation','construction_issue','safety_concern','coordination_request','instruction','follow_up','general'));

-- New status workflow. Old values are converted:
-- active -> open, suspended -> on_hold, solved -> resolved, deactivated -> voided.
alter table public.notes drop constraint if exists notes_status_check;
alter table public.notes disable trigger notes_guard;
update public.notes set status = case status
  when 'active' then 'open' when 'suspended' then 'on_hold'
  when 'solved' then 'resolved' when 'deactivated' then 'voided' else status end
where status in ('active','suspended','solved','deactivated');
alter table public.notes enable trigger notes_guard;
alter table public.notes alter column status set default 'open';
alter table public.notes add constraint notes_status_check check (status in
  ('open','in_progress','pending_verification','resolved','on_hold','voided'));

-- =====================================================================
-- Observation numbers: PROJECT-CATEGORY-001, counted per project and category
-- =====================================================================
create or replace function public.observation_code(pid uuid, cat text, num int) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(p.abbr, ''), 'PRJ') || '-' ||
         coalesce(nullif(p.category_abbrs ->> cat, ''), upper(left(regexp_replace(cat, '[^A-Za-z0-9]', '', 'g'), 3))) || '-' ||
         lpad(num::text, 3, '0')
  from projects p where p.id = pid;
$$;

create or replace function public.number_observation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.number is null then
    perform pg_advisory_xact_lock(hashtext(new.project_id::text || '/' || new.category));
    select coalesce(max(number), 0) + 1 into new.number
    from notes where project_id = new.project_id and category = new.category;
  end if;
  if coalesce(new.code, '') = '' then
    new.code := public.observation_code(new.project_id, new.category, new.number);
  end if;
  return new;
end;
$$;

drop trigger if exists notes_number on public.notes;
create trigger notes_number before insert on public.notes
  for each row execute function public.number_observation();

-- Number the observations that already exist (oldest first).
alter table public.notes disable trigger notes_guard;
with n as (
  select id, row_number() over (partition by project_id, category order by created_at) rn
  from public.notes where number is null
)
update public.notes set number = n.rn from n where notes.id = n.id;
update public.notes set code = public.observation_code(project_id, category, number) where code = '';
alter table public.notes enable trigger notes_guard;

-- Observation updates: issuer, project and number never change; stamp updated_at.
-- (Only the admin or the reporter can update at all - see the notes_update policy.)
create or replace function public.guard_note_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.issuer_id <> old.issuer_id or new.project_id <> old.project_id then
    raise exception 'The reporter and project of an observation cannot change.';
  end if;
  new.number := old.number;
  new.code := old.code;
  new.updated_at := now();
  return new;
end;
$$;

-- =====================================================================
-- Access: each project is visible to its members (and admins) only,
-- unless an admin turns on "guests can view" for that project.
-- =====================================================================
create or replace function public.can_read_project(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_member(pid) or exists (select 1 from projects where id = pid and guest_visible);
$$;

create or replace function public.can_read_note(nid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from notes n where n.id = nid and public.can_read_project(n.project_id));
$$;

drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects for select to anon, authenticated
  using (public.can_read_project(id));

drop policy if exists notes_select on public.notes;
create policy notes_select on public.notes for select to anon, authenticated
  using (public.can_read_project(project_id));

drop policy if exists notes_insert on public.notes;
create policy notes_insert on public.notes for insert to authenticated
  with check (public.is_member(project_id) and issuer_id = auth.uid() and status = 'open');

drop policy if exists replies_select on public.replies;
create policy replies_select on public.replies for select to anon, authenticated
  using (public.can_read_note(note_id));

drop policy if exists photos_read on storage.objects;
create policy photos_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'photos' and public.can_read_project(((storage.foldername(name))[1])::uuid));

-- Guests may read names and companies, never email addresses.
revoke select on public.profiles from anon;
grant select (id, name, is_admin, status, created_at, company) on public.profiles to anon;

-- =====================================================================
-- Member invitations: any project member can suggest someone; an admin approves.
-- =====================================================================
create table if not exists public.project_invites (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects (id) on delete cascade,
  email       text not null,
  name        text not null default '',
  company     text not null default '',
  invited_by  uuid references public.profiles (id) on delete set null,
  status      text not null default 'pending' check (status in ('pending', 'approved', 'declined')),
  created_at  timestamptz not null default now()
);
create unique index if not exists project_invites_pending_idx
  on public.project_invites (project_id, lower(email)) where status = 'pending';

alter table public.project_invites enable row level security;
drop policy if exists invites_select on public.project_invites;
create policy invites_select on public.project_invites for select to authenticated
  using (public.is_admin() or invited_by = auth.uid() or public.is_member(project_id));
drop policy if exists invites_insert on public.project_invites;
create policy invites_insert on public.project_invites for insert to authenticated
  with check (public.is_member(project_id) and invited_by = auth.uid() and status = 'pending');
drop policy if exists invites_admin on public.project_invites;
create policy invites_admin on public.project_invites for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Admin approves an invitation: the person is approved and added to the project.
-- If they have no account yet, it happens automatically when they first sign in.
create or replace function public.approve_invite(invite_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  inv project_invites;
  uid uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can approve invitations.';
  end if;
  select * into inv from project_invites where id = invite_id;
  if inv.id is null then
    raise exception 'Invitation not found.';
  end if;
  update project_invites set status = 'approved' where id = invite_id;
  select id into uid from profiles where lower(email) = lower(inv.email);
  if uid is not null then
    update profiles
      set status = case when status = 'removed' then status else 'approved' end,
          company = case when company = '' then inv.company else company end
      where id = uid;
    insert into project_members (project_id, user_id) values (inv.project_id, uid) on conflict do nothing;
  end if;
end;
$$;

-- New sign-ups: first account is admin; people with an approved invitation are
-- approved and added to their projects right away; everyone else waits for approval.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  first_user boolean;
  invited boolean;
  inv_name text;
  inv_company text;
begin
  select not exists (select 1 from profiles) into first_user;
  select exists (select 1 from project_invites where lower(email) = lower(new.email) and status = 'approved') into invited;
  select name, company into inv_name, inv_company from project_invites
    where lower(email) = lower(new.email) and status = 'approved' order by created_at desc limit 1;
  insert into profiles (id, name, email, is_admin, status, company)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), nullif(inv_name, ''), split_part(new.email, '@', 1)),
    lower(new.email),
    first_user,
    case when first_user or invited then 'approved' else 'pending' end,
    coalesce(inv_company, '')
  );
  if invited then
    insert into project_members (project_id, user_id)
      select project_id, new.id from project_invites
      where lower(email) = lower(new.email) and status = 'approved'
    on conflict do nothing;
  end if;
  return new;
end;
$$;

-- =====================================================================
-- Live updates for invitations too.
-- =====================================================================
do $$
begin
  begin
    alter publication supabase_realtime add table public.project_invites;
  exception when duplicate_object then null;
  end;
end $$;
