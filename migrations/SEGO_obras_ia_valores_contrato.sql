-- IA (Valores/Prazo): data do contrato; Adiantamento e Garantia introduzidos em € (a % deriva); % de retenção
alter table public.obras
  add column if not exists data_contrato date,
  add column if not exists adiantamento_valor numeric,
  add column if not exists garantia_valor numeric,
  add column if not exists retencao_pct numeric,
  add column if not exists retencao_garantia_pct numeric;
notify pgrst, 'reload schema';
