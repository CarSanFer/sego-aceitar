-- SEGO — tabela de configuração geral (Módulos por Obra, visibilidade do Guia)
-- Correr no SQL Editor do Supabase do SEGO (não no SID).
create table if not exists public.sego_config (
  chave       text primary key,
  valor       jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now(),
  updated_by  text
);

alter table public.sego_config enable row level security;

drop policy if exists "sego_config_anon_all" on public.sego_config;
create policy "sego_config_anon_all"
  on public.sego_config
  for all
  using (true)
  with check (true);

-- valores iniciais: todos os módulos visíveis; Guia só para o Superadmin
insert into public.sego_config (chave, valor) values
  ('modulos_obra', '{}'::jsonb),
  ('guia', '{"publico": false}'::jsonb)
on conflict (chave) do nothing;
