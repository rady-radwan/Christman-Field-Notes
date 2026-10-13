-- Christman Field Notes - shared server setup for Supabase.
-- Run once: Supabase dashboard > SQL Editor > New query > paste this file > Run.
-- Safe to re-run: it uses "if not exists" / "or replace" where possible.

-- =====================================================================
-- Tables
-- =====================================================================

create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  name        text not null default '',
  email       text not null default '',
  is_admin    boolean not null default false,
  status      text not null default 'pending' check (status in ('pending', 'approved', 'removed')),
  created_at  timestamptz not null default now()
);

create table if not exists public.projects (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  categories  text[] not null default array['Safety','MEP','Steel','Structure','Architecture'],
  created_at  timestamptz not null default now()
);

create table if not exists public.project_members (
  project_id  uuid not null references public.projects (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  primary key (project_id, user_id)
);

create table if not exists public.notes (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid not null references public.projects (id) on delete cascade,
  name          text not null,
  comment       text not null default '',
  category      text not null,
  priority      text not null default 'medium' check (priority in ('urgent','critical','high','medium','low')),
  status        text not null default 'active' check (status in ('active','suspended','solved','deactivated')),
  issuer_id     uuid not null references public.profiles (id),
  assigned_ids  uuid[] not null default '{}',
  photos        text[] not null default '{}',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  edited_at     timestamptz
);
create index if not exists notes_project_idx on public.notes (project_id);

create table if not exists public.replies (
  id          uuid primary key default gen_random_uuid(),
  note_id     uuid not null references public.notes (id) on delete cascade,
  author_id   uuid not null references public.profiles (id),
  text        text not null default '',
  photos      text[] not null default '{}',
  created_at  timestamptz not null default now(),
  edited_at   timestamptz
);
create index if not exists replies_note_idx on public.replies (note_id);

-- =====================================================================
-- Helper functions (security definer so policies don't recurse)
-- =====================================================================

create or replace function public.is_approved() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and status = 'approved');
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and status = 'approved' and is_admin);
$$;

create or replace function public.is_member(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() or (
    public.is_approved() and exists (select 1 from project_members where project_id = pid and user_id = auth.uid())
  );
$$;

create or replace function public.can_see_note(nid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from notes n where n.id = nid and public.is_member(n.project_id));
$$;

-- =====================================================================
-- Triggers
-- =====================================================================

-- New sign-up -> profile. The very first account becomes the approved admin;
-- everyone after that waits for an admin to approve them.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  first_user boolean;
begin
  select not exists (select 1 from profiles) into first_user;
  insert into profiles (id, name, email, is_admin, status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)),
    lower(new.email),
    first_user,
    case when first_user then 'approved' else 'pending' end
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Only admins may change roles or approval; people may rename themselves.
create or replace function public.guard_profile_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() and (new.is_admin is distinct from old.is_admin or new.status is distinct from old.status
                                or new.email is distinct from old.email) then
    raise exception 'Only an admin can change roles or approval.';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update on public.profiles
  for each row execute function public.guard_profile_update();

-- Notes: keep the issuer and project fixed, only admins deactivate, stamp updated_at.
create or replace function public.guard_note_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.issuer_id <> old.issuer_id or new.project_id <> old.project_id then
    raise exception 'The issuer and project of a note cannot change.';
  end if;
  if new.status = 'deactivated' and old.status <> 'deactivated' and not public.is_admin() then
    raise exception 'Only an admin can deactivate a note.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists notes_guard on public.notes;
create trigger notes_guard before update on public.notes
  for each row execute function public.guard_note_update();

-- =====================================================================
-- Row level security
-- =====================================================================

alter table public.profiles        enable row level security;
alter table public.projects        enable row level security;
alter table public.project_members enable row level security;
alter table public.notes           enable row level security;
alter table public.replies         enable row level security;

-- profiles
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_approved());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (public.is_admin() or id = auth.uid());

-- projects
drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects for select to authenticated
  using (public.is_member(id));
drop policy if exists projects_admin on public.projects;
create policy projects_admin on public.projects for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- project_members
drop policy if exists members_select on public.project_members;
create policy members_select on public.project_members for select to authenticated
  using (public.is_approved());
drop policy if exists members_admin on public.project_members;
create policy members_admin on public.project_members for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- notes
drop policy if exists notes_select on public.notes;
create policy notes_select on public.notes for select to authenticated
  using (public.is_member(project_id));
drop policy if exists notes_insert on public.notes;
create policy notes_insert on public.notes for insert to authenticated
  with check (public.is_member(project_id) and issuer_id = auth.uid() and status = 'active');
drop policy if exists notes_update on public.notes;
create policy notes_update on public.notes for update to authenticated
  using (public.is_admin() or (issuer_id = auth.uid() and public.is_member(project_id)));
drop policy if exists notes_delete on public.notes;
create policy notes_delete on public.notes for delete to authenticated
  using (
    public.is_admin()
    or (issuer_id = auth.uid() and not exists (select 1 from replies r where r.note_id = notes.id))
  );

-- replies
drop policy if exists replies_select on public.replies;
create policy replies_select on public.replies for select to authenticated
  using (public.can_see_note(note_id));
drop policy if exists replies_insert on public.replies;
create policy replies_insert on public.replies for insert to authenticated
  with check (public.can_see_note(note_id) and author_id = auth.uid());
drop policy if exists replies_update on public.replies;
create policy replies_update on public.replies for update to authenticated
  using (author_id = auth.uid() or public.is_admin());
drop policy if exists replies_delete on public.replies;
create policy replies_delete on public.replies for delete to authenticated
  using (author_id = auth.uid() or public.is_admin());

-- =====================================================================
-- Photo storage: private bucket, folders named <project id>/<note id>/...
-- =====================================================================

insert into storage.buckets (id, name, public)
values ('photos', 'photos', false)
on conflict (id) do nothing;

drop policy if exists photos_read on storage.objects;
create policy photos_read on storage.objects for select to authenticated
  using (bucket_id = 'photos' and public.is_member(((storage.foldername(name))[1])::uuid));

drop policy if exists photos_write on storage.objects;
create policy photos_write on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and public.is_member(((storage.foldername(name))[1])::uuid));

drop policy if exists photos_delete on storage.objects;
create policy photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and public.is_admin());

-- =====================================================================
-- Live updates: tell the app when something changes.
-- =====================================================================

do $$
declare t text;
begin
  foreach t in array array['notes','replies','profiles','projects','project_members'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
