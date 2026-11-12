alter table public.utilizadores add column if not exists obras_saida jsonb not null default '{}'::jsonb;
-- {obra_id: 'AAAA-MM-DD'}: obras de onde o utilizador saiu (histórico; já não está em obras)
