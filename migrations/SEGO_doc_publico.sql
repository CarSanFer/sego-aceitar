-- SEGO — link público (?doc=<id>): devolve só o documento pedido, a sua obra e a checklist associada.
-- Não exige sessão; as tabelas ficam fechadas e o acesso é limitado ao documento do link. Idempotente.
create or replace function public.sego_doc_publico(p_id text) returns json
language sql stable security definer set search_path = '' as $$
  select json_build_object(
    'relatorio', to_jsonb(r),
    'obra',      (select to_jsonb(o) from public.obras o where o.id = r.obra_id),
    'checklist', (select c.payload from public.checklists_amb_seg c
                  where c.obra_id = r.obra_id and c.rvt = r.id limit 1)
  )
  from public.relatorios r
  where r.id = p_id and coalesce(p_id, '') <> ''
$$;
revoke all on function public.sego_doc_publico(text) from public;
grant execute on function public.sego_doc_publico(text) to anon, authenticated;
