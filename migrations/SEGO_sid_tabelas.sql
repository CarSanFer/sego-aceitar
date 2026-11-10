-- SEGO — tabelas que vêm do SID (obras, utilizadores, …) + Entidades e Fases
-- Correr no SQL Editor do Supabase do SEGO. Idempotente.
create table if not exists public.obras (
  id text primary key, codigo text, sigla text, nome text, estado text default 'Em Preparação',
  morada text, codigo_postal text, localidade text, tipo_obra text, subtipo text, area numeric,
  pisos_acima integer, pisos_abaixo integer, ambito text, principais_desafios text,
  rel_mensal boolean default false, valor numeric, valor_obra numeric,
  inicio_previsto date, inicio_real date, fim_previsto date, prazo integer,
  prorrogacoes jsonb default '[]'::jsonb, docs jsonb default '[]'::jsonb,
  intervenientes_do text[] default '{}', intervenientes_fisc text[] default '{}',
  intervenientes_emp text[] default '{}', intervenientes_proj text[] default '{}',
  created_at timestamptz default now(), updated_at timestamptz default now(),
  data_consignacao date, empresa_dono_obra text not null default '', empresa_empreiteiro text not null default '',
  fim_contratual date, adiantamento_pct numeric, garantia_pct numeric, retencao text, retencao_garantia text, fim_real date,
  -- novos (SEGO)
  com_fases boolean not null default false,        -- obra-mãe com fases
  obra_mae_id text,                                -- preenchido nas fases
  entidade_do_id text, entidade_emp_id text        -- ligação às Entidades
);
create index if not exists obras_mae_idx on public.obras(obra_mae_id);

create table if not exists public.entidades (
  id text primary key default (gen_random_uuid())::text,
  nome text not null, nif text,
  created_at timestamptz default now()
);
create unique index if not exists entidades_nome_uq on public.entidades (lower(nome));
create unique index if not exists entidades_nif_uq on public.entidades (nif) where coalesce(nif,'')<>'';

create table if not exists public.utilizadores (
  id text primary key, nome text not null, email text not null, contacto text, funcao text,
  role text default 'fiscalizacao', obras text[] default '{}', ativo boolean default true,
  pwd text, pwd_hash text, apps text[] default '{sid}', foto text, created_at timestamptz default now(),
  obras_afetacoes jsonb default '{}'::jsonb, empresa_id text, short_name text,
  especialidades jsonb default '[]'::jsonb, obras_especialidades jsonb not null default '{}'::jsonb
);
create table if not exists public.subempreiteiros (
  id text primary key, nome text not null, especialidade text, responsavel text, email text, contacto text,
  obras text[] default '{}', created_at timestamptz default now()
);
create table if not exists public.especialidades (
  id text primary key, codigo text not null, nome text not null, created_at timestamptz default now()
);
create table if not exists public.tipos_doc (
  id text primary key, codigo text not null, nome text not null, fase text,
  tem_validade boolean default true, tem_versao boolean default true, sigla text, is_default boolean default false
);
create table if not exists public.auditoria (
  id text primary key default (gen_random_uuid())::text, entidade text, entidade_nome text, acao text,
  utilizador_email text, utilizador_nome text, data text, detalhes text, created_at timestamptz default now()
);

do $$ declare t text; begin
  foreach t in array array['obras','entidades','utilizadores','subempreiteiros','especialidades','tipos_doc','auditoria'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t||'_anon_all', t);
    execute format('create policy %I on public.%I for all using (true) with check (true)', t||'_anon_all', t);
  end loop;
end $$;
