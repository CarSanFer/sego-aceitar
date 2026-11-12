-- Permissões e notificações por obra/módulo (só as exceções às regras de origem)
create table if not exists public.obra_permissoes (
  id text primary key,            -- obra_id|modulo
  obra_id text not null,
  modulo text not null,
  regras jsonb not null default '{}'::jsonb,   -- {perm:{userId:{acao:bool}}, notif:{estado:{userId:'para'|'cc'|''}}}
  updated_at timestamptz default now(),
  updated_by text
);
alter table public.obra_permissoes enable row level security;
create policy obra_permissoes_ler on public.obra_permissoes for select to anon, authenticated using ((select private.sego_uid()) is not null);
create policy obra_permissoes_escrever on public.obra_permissoes for all to anon, authenticated using ((select private.sego_role()) = 'superadmin') with check ((select private.sego_role()) = 'superadmin');
