-- Fyface initial schema. Run in the Supabase SQL editor after configuring a project.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  category text not null,
  storage_path text not null,
  mime_type text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.share_codes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  code_hash text not null unique,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.share_code_documents (
  share_code_id uuid not null references public.share_codes(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  primary key (share_code_id, document_id)
);

create table if not exists public.access_logs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  share_code_id uuid references public.share_codes(id) on delete set null,
  viewer_label text not null default 'Visiteur',
  document_names text[] not null default '{}',
  viewed_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.documents enable row level security;
alter table public.share_codes enable row level security;
alter table public.share_code_documents enable row level security;
alter table public.access_logs enable row level security;

create policy "profiles are private to owner" on public.profiles for all using (auth.uid() = id) with check (auth.uid() = id);
create policy "documents are private to owner" on public.documents for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "share codes are private to owner" on public.share_codes for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "share documents controlled by owner" on public.share_code_documents for all using (
  exists(select 1 from public.share_codes s where s.id = share_code_id and s.owner_id = auth.uid())
) with check (
  exists(select 1 from public.share_codes s where s.id = share_code_id and s.owner_id = auth.uid())
);
create policy "access logs readable by owner" on public.access_logs for select using (auth.uid() = owner_id);

-- A private Storage bucket is required. Create it as 'fyface-documents';
-- allow authenticated users to manage only files below their own UUID folder.
insert into storage.buckets (id, name, public) values ('fyface-documents', 'fyface-documents', false)
on conflict (id) do nothing;
create policy "private document files owned by user" on storage.objects for all
using (bucket_id = 'fyface-documents' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'fyface-documents' and (storage.foldername(name))[1] = auth.uid()::text);

-- Code lookup and access logging must be implemented with a trusted Edge Function.
-- Store only a hash of the random code; never expose the service role key in the app.
