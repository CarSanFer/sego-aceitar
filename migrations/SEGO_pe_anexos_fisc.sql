-- Anexos da Fiscalização (Observações) nos PE — corrido no Supabase SEGO em 2026-11-11
alter table public.pedidos_esclarecimento add column if not exists anexos_fisc jsonb default '[]'::jsonb;
