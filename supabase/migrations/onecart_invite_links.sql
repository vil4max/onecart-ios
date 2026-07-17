-- One-time family invite links. Tokens live in the non-exposed private schema;
-- authenticated clients can only use the narrow public RPC wrappers below.

create table if not exists private.family_invite_links (
    token uuid primary key default gen_random_uuid(),
    family_id uuid not null references public.families(id) on delete cascade,
    created_by uuid not null references public.profiles(user_id) on delete cascade,
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '14 days'),
    used_by uuid references public.profiles(user_id) on delete set null,
    used_at timestamptz,
    revoked_at timestamptz,
    constraint family_invite_links_expiry_check
        check (expires_at > created_at),
    constraint family_invite_links_usage_check
        check (
            (used_by is null and used_at is null)
            or used_at is not null
        )
);

create index if not exists family_invite_links_family_active_idx
    on private.family_invite_links (family_id, expires_at desc)
    where used_at is null and revoked_at is null;

alter table private.family_invite_links enable row level security;
revoke all on table private.family_invite_links from public, anon, authenticated;

create or replace function private.create_family_invite_link(p_family_id uuid)
returns table (
    invite_token uuid,
    expires_at timestamptz,
    family_name text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := (select auth.uid());
    v_token uuid := gen_random_uuid();
    v_expires_at timestamptz := now() + interval '14 days';
    v_family_name text;
begin
    if v_user_id is null then
        raise exception 'Authentication required';
    end if;
    if not (select private.is_family_owner(p_family_id)) then
        raise exception 'Only the family owner can invite members';
    end if;

    select family.name
    into v_family_name
    from public.families family
    where family.id = p_family_id
      and family.deleted_at is null;

    if v_family_name is null then
        raise exception 'Family is unavailable';
    end if;

    insert into private.family_invite_links (
        token,
        family_id,
        created_by,
        expires_at
    )
    values (
        v_token,
        p_family_id,
        v_user_id,
        v_expires_at
    );

    return query select v_token, v_expires_at, v_family_name;
end;
$$;

create or replace function private.get_family_invite_preview(p_token uuid)
returns table (
    family_id uuid,
    family_name text,
    member_count integer,
    expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    if (select auth.uid()) is null then
        raise exception 'Authentication required';
    end if;

    return query
    select
        link.family_id,
        family.name,
        (
            select count(*)::integer
            from public.family_members member
            where member.family_id = link.family_id
        ),
        link.expires_at
    from private.family_invite_links link
    join public.families family on family.id = link.family_id
    where link.token = p_token
      and link.used_at is null
      and link.revoked_at is null
      and link.expires_at > now()
      and family.deleted_at is null;
end;
$$;

create or replace function private.accept_family_invite_link(p_token uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := (select auth.uid());
    v_family_id uuid;
    v_expires_at timestamptz;
    v_used_by uuid;
    v_used_at timestamptz;
    v_revoked_at timestamptz;
begin
    if v_user_id is null then
        raise exception 'Authentication required';
    end if;

    select
        link.family_id,
        link.expires_at,
        link.used_by,
        link.used_at,
        link.revoked_at
    into
        v_family_id,
        v_expires_at,
        v_used_by,
        v_used_at,
        v_revoked_at
    from private.family_invite_links link
    where link.token = p_token
    for update;

    if not found
       or v_revoked_at is not null
       or v_expires_at <= now() then
        raise exception 'Invitation is unavailable';
    end if;

    if v_used_at is not null then
        if v_used_by = v_user_id
           and (select private.is_family_member(v_family_id)) then
            return v_family_id;
        end if;
        raise exception 'Invitation is unavailable';
    end if;

    if not exists (
        select 1
        from public.families family
        where family.id = v_family_id
          and family.deleted_at is null
    ) then
        raise exception 'Family is unavailable';
    end if;

    if (select private.is_family_member(v_family_id)) then
        return v_family_id;
    end if;

    insert into public.family_members (family_id, user_id, role)
    values (v_family_id, v_user_id, 'member')
    on conflict (family_id, user_id) do nothing;

    update private.family_invite_links
    set used_by = v_user_id,
        used_at = now()
    where token = p_token;

    return v_family_id;
end;
$$;

revoke all on function private.create_family_invite_link(uuid)
    from public, anon;
revoke all on function private.get_family_invite_preview(uuid)
    from public, anon;
revoke all on function private.accept_family_invite_link(uuid)
    from public, anon;

grant execute on function private.create_family_invite_link(uuid)
    to authenticated, service_role;
grant execute on function private.get_family_invite_preview(uuid)
    to authenticated, service_role;
grant execute on function private.accept_family_invite_link(uuid)
    to authenticated, service_role;

create or replace function public.create_family_invite_link(p_family_id uuid)
returns table (
    invite_token uuid,
    expires_at timestamptz,
    family_name text
)
language sql
security invoker
set search_path = ''
as $$
    select * from private.create_family_invite_link(p_family_id);
$$;

create or replace function public.get_family_invite_preview(p_token uuid)
returns table (
    family_id uuid,
    family_name text,
    member_count integer,
    expires_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
    select * from private.get_family_invite_preview(p_token);
$$;

create or replace function public.accept_family_invite_link(p_token uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $$
    select private.accept_family_invite_link(p_token);
$$;

revoke all on function public.create_family_invite_link(uuid)
    from public, anon;
revoke all on function public.get_family_invite_preview(uuid)
    from public, anon;
revoke all on function public.accept_family_invite_link(uuid)
    from public, anon;

grant execute on function public.create_family_invite_link(uuid)
    to authenticated;
grant execute on function public.get_family_invite_preview(uuid)
    to authenticated;
grant execute on function public.accept_family_invite_link(uuid)
    to authenticated;

