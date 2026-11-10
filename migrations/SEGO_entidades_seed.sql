-- Entidades a partir dos nomes de empresa escritos nas obras (sem NIF) + ligação das obras
insert into public.entidades (nome)
select distinct on (lower(btrim(v))) btrim(v) from (
  select empresa_dono_obra v from public.obras union all select empresa_empreiteiro from public.obras) z
where coalesce(btrim(v),'')<>''
on conflict do nothing;
update public.obras o set entidade_do_id = e.id from public.entidades e
 where coalesce(o.entidade_do_id,'')='' and lower(btrim(o.empresa_dono_obra))=lower(e.nome);
update public.obras o set entidade_emp_id = e.id from public.entidades e
 where coalesce(o.entidade_emp_id,'')='' and lower(btrim(o.empresa_empreiteiro))=lower(e.nome);
select (select count(*) from public.entidades) entidades,
       (select count(*) from public.obras where entidade_do_id is not null) obras_com_do,
       (select count(*) from public.obras where entidade_emp_id is not null) obras_com_emp,
       (select string_agg(nome, ' · ' order by nome) from public.entidades) nomes;
