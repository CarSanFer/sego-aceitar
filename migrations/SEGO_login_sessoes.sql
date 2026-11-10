-- SEGO — login validado na base de dados, com sessão por token (modelo do GOA)
-- Fase A: não muda nada para a app publicada. Idempotente.
--   · credenciais e sessões ficam no schema "private" (não exposto pela API)
--   · a app chama sego_login / sego_sessao / sego_logout / sego_mudar_password
--   · o token segue em todos os pedidos no cabeçalho x-client-info: sego-token=<64 hex>

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

create table if not exists private.credenciais (
  utilizador_id text primary key references public.utilizadores(id) on delete cascade,
  pwd_hash      text not null check (pwd_hash ~ '^[0-9a-f]{8}$'),
  atualizado_em timestamptz not null default now()
);
create table if not exists private.sessoes (
  token_hash    text primary key,
  utilizador_id text not null references public.utilizadores(id) on delete cascade,
  criada_em     timestamptz not null default now(),
  expira_em     timestamptz not null default now() + interval '7 days'
);
create index if not exists sessoes_utilizador_idx on private.sessoes(utilizador_id);
create table if not exists private.login_falhas (
  email         text primary key,
  falhas        integer not null default 0,
  bloqueado_ate timestamptz,
  ultima        timestamptz not null default now()
);
revoke all on all tables in schema private from public, anon, authenticated;

-- Token do pedido atual
create or replace function private.sego_token() returns text
language sql stable set search_path = '' as $$
  select coalesce(
    nullif(h ->> 'x-sego-token', ''),
    substring(h ->> 'x-client-info' from 'sego-token=([0-9a-f]{64})')
  )
  from (select nullif(current_setting('request.headers', true), '')::json as h) x
$$;

-- Utilizador da sessão atual (null se não houver sessão válida)
create or replace function private.sego_uid() returns text
language sql stable security definer set search_path = '' as $$
  select s.utilizador_id
  from private.sessoes s join public.utilizadores u on u.id = s.utilizador_id
  where s.token_hash = encode(sha256(convert_to(private.sego_token(), 'utf8')), 'hex')
    and s.expira_em > now() and u.ativo
$$;

create or replace function private.sego_role() returns text
language sql stable security definer set search_path = '' as $$
  select u.role from public.utilizadores u where u.id = private.sego_uid()
$$;

create or replace function private.sego_perfil(p_id text) returns json
language sql stable security definer set search_path = '' as $$
  select json_build_object('id', u.id, 'nome', u.nome, 'email', u.email, 'role', u.role,
                           'funcao', coalesce(u.funcao, ''), 'obras', u.obras, 'apps', coalesce(u.apps, '{}'))
  from public.utilizadores u where u.id = p_id
$$;

-- Login: devolve {token, utilizador} ou null
create or replace function public.sego_login(p_email text, p_hash text) returns json
language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v       public.utilizadores;
  v_ate   timestamptz;
  v_n     integer;
  v_token text;
begin
  -- A 1.ª instrução é sempre uma escrita: uma chamada só de leitura (GET) falha sempre.
  delete from private.sessoes where expira_em < now();

  if v_email = '' or coalesce(p_hash, '') = '' then return null; end if;

  select bloqueado_ate into v_ate from private.login_falhas where email = v_email;
  if v_ate is not null and v_ate > now() then
    raise exception 'Conta bloqueada por excesso de tentativas. Tente de novo dentro de alguns minutos.';
  end if;

  select u.* into v
  from public.utilizadores u join private.credenciais c on c.utilizador_id = u.id
  where lower(trim(u.email)) = v_email and u.ativo and c.pwd_hash = lower(p_hash)
  order by ('sego' = any(coalesce(u.apps, '{}'))) desc, u.id
  limit 1;

  if not found then
    if exists (select 1 from public.utilizadores u where lower(trim(u.email)) = v_email) then
      insert into private.login_falhas (email, falhas, ultima) values (v_email, 1, now())
      on conflict (email) do update set falhas = private.login_falhas.falhas + 1, ultima = now()
      returning falhas into v_n;
      if v_n >= 10 then
        update private.login_falhas set falhas = 0, bloqueado_ate = now() + interval '15 minutes' where email = v_email;
      end if;
    end if;
    return null;
  end if;

  if not ('sego' = any(coalesce(v.apps, '{}'))) then
    raise exception 'Sem permissão para aceder ao SEGO. Contacte o administrador para activar o acesso a esta aplicação.';
  end if;

  delete from private.login_falhas where email = v_email;
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into private.sessoes (token_hash, utilizador_id)
  values (encode(sha256(convert_to(v_token, 'utf8')), 'hex'), v.id);
  return json_build_object('token', v_token, 'utilizador', private.sego_perfil(v.id));
end $$;

-- Sessão atual: perfil ou null
create or replace function public.sego_sessao() returns json
language sql stable security definer set search_path = '' as $$
  select private.sego_perfil(private.sego_uid())
$$;

create or replace function public.sego_logout() returns void
language sql security definer set search_path = '' as $$
  delete from private.sessoes
  where token_hash = encode(sha256(convert_to(private.sego_token(), 'utf8')), 'hex')
$$;

-- O próprio utilizador muda a sua password (hashes de 8 hex, como a app calcula)
create or replace function public.sego_mudar_password(p_atual text, p_nova text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_id text := private.sego_uid();
begin
  if v_id is null then raise exception 'Sem sessão' using errcode = '42501'; end if;
  if coalesce(p_nova, '') !~ '^[0-9a-f]{8}$' then raise exception 'Password inválida'; end if;
  update private.credenciais set pwd_hash = p_nova, atualizado_em = now()
  where utilizador_id = v_id and pwd_hash = lower(p_atual);
  if not found then return false; end if;
  delete from private.sessoes
  where utilizador_id = v_id
    and token_hash <> encode(sha256(convert_to(private.sego_token(), 'utf8')), 'hex');
  return true;
end $$;

-- Espelho: quando a app grava pwd_hash em utilizadores, a credencial acompanha
create or replace function private.tg_utilizadores_credencial() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.pwd_hash ~ '^[0-9a-f]{8}$' then
    if not exists (select 1 from private.credenciais c where c.utilizador_id = new.id and c.pwd_hash = new.pwd_hash) then
      insert into private.credenciais (utilizador_id, pwd_hash) values (new.id, new.pwd_hash)
      on conflict (utilizador_id) do update set pwd_hash = excluded.pwd_hash, atualizado_em = now();
      delete from private.sessoes where utilizador_id = new.id;
    end if;
  elsif coalesce(new.pwd_hash, '') = '' then
    delete from private.credenciais where utilizador_id = new.id;
    delete from private.sessoes where utilizador_id = new.id;
  end if;
  return null;
end $$;
drop trigger if exists trg_utilizadores_credencial on public.utilizadores;
create trigger trg_utilizadores_credencial
  after insert or update of pwd_hash on public.utilizadores
  for each row execute function private.tg_utilizadores_credencial();

-- Credenciais iniciais a partir dos hashes existentes
insert into private.credenciais (utilizador_id, pwd_hash)
select id, lower(pwd_hash) from public.utilizadores where pwd_hash ~* '^[0-9a-f]{8}$'
on conflict (utilizador_id) do nothing;

-- As passwords em texto claro deixam de estar na tabela (o login usa só o hash)
update public.utilizadores set pwd = '' where coalesce(pwd, '') <> '';

-- Permissões de execução
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.sego_token(), private.sego_uid(), private.sego_role() to anon, authenticated;
revoke all on function public.sego_login(text, text), public.sego_sessao(), public.sego_logout(),
                       public.sego_mudar_password(text, text) from public;
grant execute on function public.sego_login(text, text), public.sego_sessao(), public.sego_logout(),
                          public.sego_mudar_password(text, text) to anon, authenticated;
