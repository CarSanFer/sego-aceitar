-- SEGO — Fase B: fecho das tabelas que vieram do SID e hashes fora da tabela exposta
-- Só correr depois de a app (v26.11.10.1254 ou posterior) estar a entrar com sego_login.
-- A produção (sego.aceitar.pt, ramo main) ainda não lê estas 7 tabelas do SEGO. Idempotente.

-- 1) Os hashes deixam de ficar em public.utilizadores: ficam só em private.credenciais.
--    A coluna pwd_hash passa a guardar apenas a marca 'definida' (a app usa-a para saber se há acesso).
alter table private.credenciais
  alter constraint credenciais_utilizador_id_fkey deferrable initially deferred;

create or replace function private.tg_utilizadores_credencial() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.pwd := '';                                   -- nunca se guarda a password em texto claro
  if new.pwd_hash ~ '^[0-9a-f]{8}$' then           -- a app gravou um hash novo: vai para a zona privada
    if not exists (select 1 from private.credenciais c where c.utilizador_id = new.id and c.pwd_hash = new.pwd_hash) then
      insert into private.credenciais (utilizador_id, pwd_hash) values (new.id, new.pwd_hash)
      on conflict (utilizador_id) do update set pwd_hash = excluded.pwd_hash, atualizado_em = now();
      delete from private.sessoes where utilizador_id = new.id;
    end if;
    new.pwd_hash := 'definida';
  elsif coalesce(new.pwd_hash, '') = '' then       -- acesso revogado
    delete from private.credenciais where utilizador_id = new.id;
    delete from private.sessoes where utilizador_id = new.id;
    new.pwd_hash := '';
  else                                             -- 'definida' (ou outro valor): mantém a credencial que existir
    new.pwd_hash := case when exists (select 1 from private.credenciais c where c.utilizador_id = new.id)
                         then 'definida' else '' end;
  end if;
  return new;
end $$;
drop trigger if exists trg_utilizadores_credencial on public.utilizadores;
create trigger trg_utilizadores_credencial
  before insert or update on public.utilizadores
  for each row execute function private.tg_utilizadores_credencial();

update public.utilizadores set pwd_hash = pwd_hash where coalesce(pwd_hash, '') <> '' or coalesce(pwd, '') <> '';

-- 2) Permissões: sessão válida para ler e escrever; em utilizadores só o superadmin escreve.
do $$ declare t text; begin
  foreach t in array array['obras','entidades','subempreiteiros','especialidades','tipos_doc','auditoria'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_anon_all', t);
    execute format('drop policy if exists %I on public.%I', t || '_sessao', t);
    execute format('create policy %I on public.%I for all to anon, authenticated
                    using ((select private.sego_uid()) is not null)
                    with check ((select private.sego_uid()) is not null)', t || '_sessao', t);
  end loop;
end $$;

alter table public.utilizadores enable row level security;
drop policy if exists utilizadores_anon_all on public.utilizadores;
drop policy if exists utilizadores_ler on public.utilizadores;
drop policy if exists utilizadores_escrever on public.utilizadores;
create policy utilizadores_ler on public.utilizadores for select to anon, authenticated
  using ((select private.sego_uid()) is not null);
create policy utilizadores_escrever on public.utilizadores for all to anon, authenticated
  using ((select private.sego_role()) = 'superadmin')
  with check ((select private.sego_role()) = 'superadmin');
