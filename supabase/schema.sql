-- Bookshelf backup & sync schema.
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Safe to re-run.

-- Books: one row per book, owned by the signed-in user.
create table if not exists public.books (
  id                  uuid primary key,
  user_id             uuid not null default auth.uid() references auth.users on delete cascade,
  title               text not null,
  authors             text[] not null default '{}',
  isbn                text,
  page_count          int,
  published_year      int,
  is_read             boolean not null default false,
  is_reading          boolean not null default false,
  date_started        timestamptz,
  date_read           timestamptz,
  date_added          timestamptz not null default now(),
  notes               text not null default '',
  rating              int check (rating between 1 and 5),
  categories          text[] not null default '{}',
  favorite_rank       int,
  recommendation_note text,
  cover_path          text,
  cover_hash          text,
  deleted             boolean not null default false,
  updated_at          timestamptz not null default now()
);

create index if not exists books_user_updated on public.books (user_id, updated_at);

-- The finish date's day is unknown; only its year (stored as 1 Jan) is meaningful.
alter table public.books add column if not exists date_read_year_only boolean not null default false;

-- The publisher's description of the book.
alter table public.books add column if not exists summary text;

-- Lending history: [{id, borrower_name, contact_id, lent_at, returned_at}, ...]
alter table public.books add column if not exists loans jsonb not null default '[]';

-- Profile: name and photo.
create table if not exists public.profiles (
  user_id    uuid primary key default auth.uid() references auth.users on delete cascade,
  name       text not null default '',
  photo_path text,
  photo_hash text,
  updated_at timestamptz not null default now()
);

-- The server stamps updated_at, so "what changed since" never depends on a phone's clock.
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists books_touch on public.books;
create trigger books_touch before insert or update on public.books
  for each row execute function public.touch_updated_at();

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before insert or update on public.profiles
  for each row execute function public.touch_updated_at();

-- Row-level security: each account can only see and change its own rows.
alter table public.books enable row level security;
alter table public.profiles enable row level security;

drop policy if exists "own books" on public.books;
create policy "own books" on public.books
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Private storage for covers and the profile photo, one folder per account:
--   library/<user id>/covers/<book id>.jpg
--   library/<user id>/profile.jpg
insert into storage.buckets (id, name, public)
values ('library', 'library', false)
on conflict (id) do nothing;

drop policy if exists "own library files" on storage.objects;
create policy "own library files" on storage.objects
  for all to authenticated
  using (bucket_id = 'library' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'library' and (storage.foldername(name))[1] = auth.uid()::text);
