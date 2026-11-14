-- SEGO — Fase C: fecho das tabelas dos módulos (só com sessão SEGO, como obras/utilizadores).
-- CORRER SÓ NO MOMENTO DA PASSAGEM (main = sid-no-sego): a versão atual de produção grava nestas
-- tabelas sem sessão e deixaria de funcionar. Idempotente.
do $$
declare t text; p record;
begin
  foreach t in array array['am_config','am_faturas','autos_mensais','autos_tcm','checklists_amb_seg','lpu_obra','met_registos',
    'pedidos_aprovacao','pedidos_betonagem','pedidos_esclarecimento','planos_quinzenais','qualidade_execucao','relatorios',
    'sego_config','tcm'] loop
    for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for all to anon, authenticated using ((select private.sego_uid()) is not null) with check ((select private.sego_uid()) is not null)', t||'_sessao', t);
  end loop;
end $$;
