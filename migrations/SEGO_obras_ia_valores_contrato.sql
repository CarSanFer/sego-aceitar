-- IA (Valores/Prazo): data do contrato; % de retenção (Adiantamento e Garantia continuam em adiantamento_pct / garantia_pct; o € é calculado)
alter table public.obras
  add column if not exists data_contrato date,
  add column if not exists retencao_pct numeric,
  add column if not exists retencao_garantia_pct numeric;
alter table public.obras drop column if exists adiantamento_valor, drop column if exists garantia_valor;
notify pgrst, 'reload schema';
