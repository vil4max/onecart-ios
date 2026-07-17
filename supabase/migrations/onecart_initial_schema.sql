-- OneCart primary Supabase backend.
-- The iOS client keeps Core Data as an offline cache and exchanges complete,
-- timestamped family snapshots through the RPC functions at the end of this file.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

create table public.profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null,
    email text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint profiles_display_name_length
        check (char_length(btrim(display_name)) between 1 and 80),
    constraint profiles_email_normalized
        check (email is null or email = lower(btrim(email)))
);

create unique index profiles_email_unique_idx
    on public.profiles (email)
    where email is not null;

create table public.families (
    id uuid primary key,
    name text not null,
    owner_id uuid not null references public.profiles(user_id) on delete cascade,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint families_name_length
        check (char_length(btrim(name)) between 1 and 100),
    constraint families_family_id_unique unique (id, owner_id)
);

create index families_owner_id_idx on public.families (owner_id);
create index families_active_updated_idx
    on public.families (updated_at desc)
    where deleted_at is null;

create table public.family_members (
    family_id uuid not null references public.families(id) on delete cascade,
    user_id uuid not null references public.profiles(user_id) on delete cascade,
    role text not null default 'member',
    joined_at timestamptz not null default now(),
    primary key (family_id, user_id),
    constraint family_members_role_check check (role in ('owner', 'member'))
);

create index family_members_user_family_idx
    on public.family_members (user_id, family_id);

create table public.family_invitations (
    id uuid primary key default gen_random_uuid(),
    family_id uuid not null references public.families(id) on delete cascade,
    email text not null,
    role text not null default 'member',
    status text not null default 'pending',
    invited_by uuid not null references public.profiles(user_id) on delete cascade,
    accepted_by uuid references public.profiles(user_id) on delete set null,
    expires_at timestamptz not null default (now() + interval '14 days'),
    accepted_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint family_invitations_email_normalized
        check (email = lower(btrim(email))),
    constraint family_invitations_email_shape
        check (email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
    constraint family_invitations_role_check check (role = 'member'),
    constraint family_invitations_status_check
        check (status in ('pending', 'accepted', 'revoked', 'expired'))
);

create unique index family_invitations_pending_unique_idx
    on public.family_invitations (family_id, email)
    where status = 'pending';
create index family_invitations_email_status_idx
    on public.family_invitations (email, status, expires_at);
create index family_invitations_family_status_idx
    on public.family_invitations (family_id, status, created_at desc);
create index family_invitations_invited_by_idx
    on public.family_invitations (invited_by);
create index family_invitations_accepted_by_idx
    on public.family_invitations (accepted_by)
    where accepted_by is not null;

create table public.stores (
    id uuid primary key,
    family_id uuid not null references public.families(id) on delete cascade,
    name text not null,
    icon text not null default '',
    color_hex text not null default '#34785B',
    address text,
    latitude double precision,
    longitude double precision,
    external_app_url text,
    is_pinned boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint stores_family_id_unique unique (family_id, id),
    constraint stores_name_length check (char_length(btrim(name)) between 1 and 160),
    constraint stores_color_hex_check check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
    constraint stores_latitude_check check (latitude is null or latitude between -90 and 90),
    constraint stores_longitude_check check (longitude is null or longitude between -180 and 180)
);

create index stores_family_updated_idx on public.stores (family_id, updated_at desc);
create index stores_family_active_idx
    on public.stores (family_id, is_pinned desc, name)
    where deleted_at is null;

create table public.shopping_lists (
    id uuid primary key,
    family_id uuid not null references public.families(id) on delete cascade,
    store_id uuid,
    title text not null,
    status text not null default 'active',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint shopping_lists_family_id_unique unique (family_id, id),
    constraint shopping_lists_store_fkey
        foreign key (family_id, store_id)
        references public.stores(family_id, id),
    constraint shopping_lists_title_length
        check (char_length(btrim(title)) between 1 and 180),
    constraint shopping_lists_status_check
        check (status in ('active', 'completed', 'archived'))
);

create index shopping_lists_family_updated_idx
    on public.shopping_lists (family_id, updated_at desc);
create index shopping_lists_family_store_idx
    on public.shopping_lists (family_id, store_id)
    where store_id is not null;
create index shopping_lists_family_active_idx
    on public.shopping_lists (family_id, status, updated_at desc)
    where deleted_at is null;

create table public.products (
    id uuid primary key,
    family_id uuid not null references public.families(id) on delete cascade,
    list_id uuid not null,
    store_id uuid,
    name text not null,
    quantity numeric(12, 3) not null default 1,
    unit text not null default 'piece',
    category text not null default 'other',
    estimated_price numeric(12, 2) not null default 0,
    original_price numeric(12, 2),
    image_url text,
    source_url text,
    note text not null default '',
    is_purchased boolean not null default false,
    purchased_at timestamptz,
    purchased_by_name text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint products_family_id_unique unique (family_id, id),
    constraint products_list_fkey
        foreign key (family_id, list_id)
        references public.shopping_lists(family_id, id),
    constraint products_store_fkey
        foreign key (family_id, store_id)
        references public.stores(family_id, id),
    constraint products_name_length check (char_length(btrim(name)) between 1 and 240),
    constraint products_quantity_check check (quantity > 0),
    constraint products_unit_check check (unit in ('piece', 'kg', 'g', 'l', 'ml', 'pack')),
    constraint products_category_check
        check (category in ('produce', 'dairy', 'meat', 'drinks', 'household', 'other')),
    constraint products_estimated_price_check check (estimated_price >= 0),
    constraint products_original_price_check check (original_price is null or original_price >= 0)
);

create index products_family_updated_idx on public.products (family_id, updated_at desc);
create index products_family_list_idx on public.products (family_id, list_id);
create index products_family_store_idx
    on public.products (family_id, store_id)
    where store_id is not null;
create index products_family_active_idx
    on public.products (family_id, is_purchased, created_at)
    where deleted_at is null;

create table public.purchase_history (
    id uuid primary key,
    family_id uuid not null references public.families(id) on delete cascade,
    store_id uuid,
    total numeric(12, 2) not null default 0,
    purchased_at timestamptz not null,
    member_names text not null default 'Семья',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint purchase_history_family_id_unique unique (family_id, id),
    constraint purchase_history_store_fkey
        foreign key (family_id, store_id)
        references public.stores(family_id, id),
    constraint purchase_history_total_check check (total >= 0)
);

create index purchase_history_family_updated_idx
    on public.purchase_history (family_id, updated_at desc);
create index purchase_history_family_store_idx
    on public.purchase_history (family_id, store_id)
    where store_id is not null;
create index purchase_history_family_active_idx
    on public.purchase_history (family_id, purchased_at desc)
    where deleted_at is null;

create table public.history_items (
    id uuid primary key,
    family_id uuid not null references public.families(id) on delete cascade,
    history_id uuid not null,
    name text not null,
    quantity numeric(12, 3) not null default 1,
    unit text not null default 'piece',
    category text not null default 'other',
    estimated_price numeric(12, 2) not null default 0,
    note text not null default '',
    purchased_at timestamptz,
    purchased_by_name text,
    store_name text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint history_items_family_id_unique unique (family_id, id),
    constraint history_items_history_fkey
        foreign key (family_id, history_id)
        references public.purchase_history(family_id, id),
    constraint history_items_name_length check (char_length(btrim(name)) between 1 and 240),
    constraint history_items_quantity_check check (quantity > 0),
    constraint history_items_unit_check check (unit in ('piece', 'kg', 'g', 'l', 'ml', 'pack')),
    constraint history_items_category_check
        check (category in ('produce', 'dairy', 'meat', 'drinks', 'household', 'other')),
    constraint history_items_estimated_price_check check (estimated_price >= 0)
);

create index history_items_family_updated_idx
    on public.history_items (family_id, updated_at desc);
create index history_items_family_history_idx
    on public.history_items (family_id, history_id);
create index history_items_family_active_idx
    on public.history_items (family_id, history_id, name)
    where deleted_at is null;

create or replace function private.is_family_member(p_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select (select auth.uid()) is not null
       and exists (
           select 1
           from public.family_members member
           where member.family_id = p_family_id
             and member.user_id = (select auth.uid())
       );
$$;

create or replace function private.is_family_owner(p_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select (select auth.uid()) is not null
       and exists (
           select 1
           from public.families family
           where family.id = p_family_id
             and family.owner_id = (select auth.uid())
             and family.deleted_at is null
       );
$$;

create or replace function private.can_view_profile(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select p_user_id = (select auth.uid())
        or exists (
            select 1
            from public.family_members mine
            join public.family_members other_member
              on other_member.family_id = mine.family_id
            where mine.user_id = (select auth.uid())
              and other_member.user_id = p_user_id
        )
        or exists (
            select 1
            from public.family_invitations invitation
            where invitation.invited_by = p_user_id
              and invitation.status = 'pending'
              and invitation.expires_at > now()
              and invitation.email = (
                  select lower(user_record.email)
                  from auth.users user_record
                  where user_record.id = (select auth.uid())
              )
        );
$$;

create or replace function private.current_user_email()
returns text
language sql
stable
security definer
set search_path = ''
as $$
    select lower(user_record.email)
    from auth.users user_record
    where user_record.id = (select auth.uid());
$$;

revoke all on function private.is_family_member(uuid) from public, anon;
revoke all on function private.is_family_owner(uuid) from public, anon;
revoke all on function private.can_view_profile(uuid) from public, anon;
revoke all on function private.current_user_email() from public, anon;
grant execute on function private.is_family_member(uuid) to authenticated, service_role;
grant execute on function private.is_family_owner(uuid) to authenticated, service_role;
grant execute on function private.can_view_profile(uuid) to authenticated, service_role;
grant execute on function private.current_user_email() to authenticated, service_role;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create or replace function private.handle_auth_user_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_metadata_name text;
    v_display_name text;
begin
    v_metadata_name := nullif(btrim(new.raw_user_meta_data ->> 'display_name'), '');
    v_display_name := coalesce(
        v_metadata_name,
        nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
        'Пользователь'
    );

    insert into public.profiles (user_id, display_name, email)
    values (new.id, v_display_name, lower(new.email))
    on conflict (user_id) do update
    set email = excluded.email,
        display_name = case
            when v_metadata_name is not null then excluded.display_name
            else public.profiles.display_name
        end,
        updated_at = now();

    return new;
end;
$$;

create or replace function private.handle_new_family()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.family_members (family_id, user_id, role, joined_at)
    values (new.id, new.owner_id, 'owner', new.created_at)
    on conflict (family_id, user_id) do nothing;
    return new;
end;
$$;

revoke all on function private.set_updated_at() from public, anon, authenticated;
revoke all on function private.handle_auth_user_change() from public, anon, authenticated;
revoke all on function private.handle_new_family() from public, anon, authenticated;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger family_invitations_set_updated_at
before update on public.family_invitations
for each row execute function private.set_updated_at();

create trigger auth_users_sync_profile
after insert or update of email, raw_user_meta_data on auth.users
for each row execute function private.handle_auth_user_change();

create trigger families_add_owner_member
after insert on public.families
for each row execute function private.handle_new_family();

insert into public.profiles (user_id, display_name, email)
select
    auth_user.id,
    coalesce(
        nullif(btrim(auth_user.raw_user_meta_data ->> 'display_name'), ''),
        nullif(split_part(coalesce(auth_user.email, ''), '@', 1), ''),
        'Пользователь'
    ),
    lower(auth_user.email)
from auth.users auth_user
on conflict (user_id) do nothing;

alter table public.profiles enable row level security;
alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.family_invitations enable row level security;
alter table public.stores enable row level security;
alter table public.shopping_lists enable row level security;
alter table public.products enable row level security;
alter table public.purchase_history enable row level security;
alter table public.history_items enable row level security;

create policy profiles_select_related
on public.profiles for select
to authenticated
using ((select private.can_view_profile(user_id)));

create policy profiles_update_self
on public.profiles for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy families_select_member_or_invitee
on public.families for select
to authenticated
using (
    (select private.is_family_member(id))
    or exists (
        select 1
        from public.family_invitations invitation
        where invitation.family_id = families.id
          and invitation.status = 'pending'
          and invitation.expires_at > now()
          and invitation.email = lower(
              coalesce((select auth.jwt()) ->> 'email', '')
          )
    )
);

create policy families_insert_owner
on public.families for insert
to authenticated
with check (owner_id = (select auth.uid()));

create policy families_update_owner
on public.families for update
to authenticated
using ((select private.is_family_owner(id)))
with check (
    owner_id = (select auth.uid())
);

create policy family_members_select_family
on public.family_members for select
to authenticated
using ((select private.is_family_member(family_id)));

create policy family_invitations_select_owner_or_invitee
on public.family_invitations for select
to authenticated
using (
    (select private.is_family_owner(family_id))
    or email = lower(coalesce((select auth.jwt()) ->> 'email', ''))
);

create policy stores_select_member
on public.stores for select to authenticated
using ((select private.is_family_member(family_id)));
create policy stores_insert_member
on public.stores for insert to authenticated
with check ((select private.is_family_member(family_id)));
create policy stores_update_member
on public.stores for update to authenticated
using ((select private.is_family_member(family_id)))
with check ((select private.is_family_member(family_id)));

create policy shopping_lists_select_member
on public.shopping_lists for select to authenticated
using ((select private.is_family_member(family_id)));
create policy shopping_lists_insert_member
on public.shopping_lists for insert to authenticated
with check ((select private.is_family_member(family_id)));
create policy shopping_lists_update_member
on public.shopping_lists for update to authenticated
using ((select private.is_family_member(family_id)))
with check ((select private.is_family_member(family_id)));

create policy products_select_member
on public.products for select to authenticated
using ((select private.is_family_member(family_id)));
create policy products_insert_member
on public.products for insert to authenticated
with check ((select private.is_family_member(family_id)));
create policy products_update_member
on public.products for update to authenticated
using ((select private.is_family_member(family_id)))
with check ((select private.is_family_member(family_id)));

create policy purchase_history_select_member
on public.purchase_history for select to authenticated
using ((select private.is_family_member(family_id)));
create policy purchase_history_insert_member
on public.purchase_history for insert to authenticated
with check ((select private.is_family_member(family_id)));
create policy purchase_history_update_member
on public.purchase_history for update to authenticated
using ((select private.is_family_member(family_id)))
with check ((select private.is_family_member(family_id)));

create policy history_items_select_member
on public.history_items for select to authenticated
using ((select private.is_family_member(family_id)));
create policy history_items_insert_member
on public.history_items for insert to authenticated
with check ((select private.is_family_member(family_id)));
create policy history_items_update_member
on public.history_items for update to authenticated
using ((select private.is_family_member(family_id)))
with check ((select private.is_family_member(family_id)));

revoke all on table public.profiles from anon, authenticated;
revoke all on table public.families from anon, authenticated;
revoke all on table public.family_members from anon, authenticated;
revoke all on table public.family_invitations from anon, authenticated;
revoke all on table public.stores from anon, authenticated;
revoke all on table public.shopping_lists from anon, authenticated;
revoke all on table public.products from anon, authenticated;
revoke all on table public.purchase_history from anon, authenticated;
revoke all on table public.history_items from anon, authenticated;

grant select on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;
grant select, insert on table public.families to authenticated;
grant update (name, updated_at, deleted_at) on table public.families to authenticated;
grant select on table public.family_members to authenticated;
grant select on table public.family_invitations to authenticated;
grant select, insert, update on table public.stores to authenticated;
grant select, insert, update on table public.shopping_lists to authenticated;
grant select, insert, update on table public.products to authenticated;
grant select, insert, update on table public.purchase_history to authenticated;
grant select, insert, update on table public.history_items to authenticated;

create or replace function public.ensure_family(
    p_id uuid,
    p_name text,
    p_created_at timestamptz,
    p_updated_at timestamptz
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_name text := btrim(p_name);
    v_created_at timestamptz := coalesce(p_created_at, now());
    v_updated_at timestamptz := coalesce(p_updated_at, v_created_at);
begin
    if (select auth.uid()) is null then
        raise exception 'Authentication required';
    end if;
    if p_id is null or v_name is null or char_length(v_name) not between 1 and 100 then
        raise exception 'Invalid family';
    end if;

    insert into public.families (id, name, owner_id, created_at, updated_at)
    values (p_id, v_name, (select auth.uid()), v_created_at, v_updated_at)
    on conflict (id) do nothing;

    if not (select private.is_family_member(p_id)) then
        raise exception 'Family is unavailable';
    end if;

    if (select private.is_family_owner(p_id)) then
        update public.families
        set name = v_name,
            updated_at = v_updated_at
        where id = p_id
          and v_updated_at > updated_at;
    end if;

    return p_id;
end;
$$;

create or replace function public.create_family_invitation(
    p_family_id uuid,
    p_email text
)
returns public.family_invitations
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := (select auth.uid());
    v_email text := lower(btrim(p_email));
    v_invitation public.family_invitations;
begin
    if v_user_id is null then
        raise exception 'Authentication required';
    end if;
    if not (select private.is_family_owner(p_family_id)) then
        raise exception 'Only the family owner can invite members';
    end if;
    if v_email is null
       or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'Invalid email';
    end if;
    if v_email = (select private.current_user_email()) then
        raise exception 'You are already the family owner';
    end if;
    if exists (
        select 1
        from public.profiles profile
        join public.family_members member on member.user_id = profile.user_id
        where member.family_id = p_family_id
          and profile.email = v_email
    ) then
        raise exception 'This person is already a family member';
    end if;

    insert into public.family_invitations (
        family_id,
        email,
        role,
        status,
        invited_by,
        expires_at
    )
    values (
        p_family_id,
        v_email,
        'member',
        'pending',
        v_user_id,
        now() + interval '14 days'
    )
    on conflict (family_id, email) where status = 'pending'
    do update set
        invited_by = excluded.invited_by,
        expires_at = excluded.expires_at,
        updated_at = now()
    returning * into v_invitation;

    return v_invitation;
end;
$$;

create or replace function public.accept_family_invitation(p_invitation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := (select auth.uid());
    v_email text;
    v_invitation public.family_invitations;
begin
    if v_user_id is null then
        raise exception 'Authentication required';
    end if;

    v_email := (select private.current_user_email());
    if v_email is null then
        raise exception 'Email is unavailable';
    end if;

    select *
    into v_invitation
    from public.family_invitations invitation
    where invitation.id = p_invitation_id
    for update;

    if not found then
        raise exception 'Invitation is unavailable';
    end if;
    if v_invitation.status = 'accepted' and v_invitation.accepted_by = v_user_id then
        return v_invitation.family_id;
    end if;
    if v_invitation.status <> 'pending'
       or v_invitation.expires_at <= now()
       or v_invitation.email <> v_email then
        raise exception 'Invitation is unavailable';
    end if;
    if not exists (
        select 1 from public.families family
        where family.id = v_invitation.family_id
          and family.deleted_at is null
    ) then
        raise exception 'Family is unavailable';
    end if;

    insert into public.family_members (family_id, user_id, role)
    values (v_invitation.family_id, v_user_id, 'member')
    on conflict (family_id, user_id) do nothing;

    update public.family_invitations
    set status = 'accepted',
        accepted_by = v_user_id,
        accepted_at = now()
    where id = p_invitation_id;

    return v_invitation.family_id;
end;
$$;

create or replace function public.revoke_family_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_family_id uuid;
begin
    if (select auth.uid()) is null then
        raise exception 'Authentication required';
    end if;

    select invitation.family_id
    into v_family_id
    from public.family_invitations invitation
    where invitation.id = p_invitation_id;

    if v_family_id is null or not (select private.is_family_owner(v_family_id)) then
        raise exception 'Invitation is unavailable';
    end if;

    update public.family_invitations
    set status = 'revoked'
    where id = p_invitation_id
      and status = 'pending';
end;
$$;

create or replace function public.leave_family(p_family_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := (select auth.uid());
begin
    if v_user_id is null then
        raise exception 'Authentication required';
    end if;
    if (select private.is_family_owner(p_family_id)) then
        raise exception 'The owner cannot leave the family';
    end if;
    if not (select private.is_family_member(p_family_id)) then
        raise exception 'Family is unavailable';
    end if;

    delete from public.family_members
    where family_id = p_family_id
      and user_id = v_user_id;
end;
$$;

create or replace function public.remove_family_member(
    p_family_id uuid,
    p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if (select auth.uid()) is null then
        raise exception 'Authentication required';
    end if;
    if not (select private.is_family_owner(p_family_id)) then
        raise exception 'Only the family owner can remove members';
    end if;
    if p_user_id = (select auth.uid()) then
        raise exception 'The owner cannot remove themselves';
    end if;

    delete from public.family_members
    where family_id = p_family_id
      and user_id = p_user_id
      and role = 'member';
end;
$$;

create or replace function public.get_my_families()
returns table (
    id uuid,
    name text,
    owner_id uuid,
    role text,
    created_at timestamptz,
    updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
    select
        family.id,
        family.name,
        family.owner_id,
        member.role,
        family.created_at,
        family.updated_at
    from public.family_members member
    join public.families family on family.id = member.family_id
    where member.user_id = (select auth.uid())
      and family.deleted_at is null
    order by family.updated_at desc;
$$;

create or replace function public.get_family_members(p_family_id uuid)
returns table (
    user_id uuid,
    display_name text,
    email text,
    role text,
    joined_at timestamptz,
    is_current_user boolean
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
    if not (select private.is_family_member(p_family_id)) then
        raise exception 'Family is unavailable';
    end if;

    return query
    select
        profile.user_id,
        profile.display_name,
        profile.email,
        member.role,
        member.joined_at,
        profile.user_id = (select auth.uid())
    from public.family_members member
    join public.profiles profile on profile.user_id = member.user_id
    where member.family_id = p_family_id
    order by
        case when member.role = 'owner' then 0 else 1 end,
        lower(profile.display_name);
end;
$$;

create or replace function public.get_pending_invitations()
returns table (
    id uuid,
    family_id uuid,
    family_name text,
    invited_by_name text,
    email text,
    expires_at timestamptz,
    created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
    select
        invitation.id,
        invitation.family_id,
        family.name,
        inviter.display_name,
        invitation.email,
        invitation.expires_at,
        invitation.created_at
    from public.family_invitations invitation
    join public.families family on family.id = invitation.family_id
    join public.profiles inviter on inviter.user_id = invitation.invited_by
    where invitation.email = lower(coalesce((select auth.jwt()) ->> 'email', ''))
      and invitation.status = 'pending'
      and invitation.expires_at > now()
      and family.deleted_at is null
    order by invitation.created_at desc;
$$;

create or replace function public.get_family_snapshot(p_family_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
    v_snapshot jsonb;
begin
    if not (select private.is_family_member(p_family_id)) then
        raise exception 'Family is unavailable';
    end if;

    select jsonb_build_object(
        'family', (
            select to_jsonb(family_row)
            from public.families family_row
            where family_row.id = p_family_id
        ),
        'stores', coalesce((
            select jsonb_agg(to_jsonb(store_row) order by store_row.updated_at, store_row.id)
            from public.stores store_row
            where store_row.family_id = p_family_id
        ), '[]'::jsonb),
        'shopping_lists', coalesce((
            select jsonb_agg(to_jsonb(list_row) order by list_row.updated_at, list_row.id)
            from public.shopping_lists list_row
            where list_row.family_id = p_family_id
        ), '[]'::jsonb),
        'products', coalesce((
            select jsonb_agg(to_jsonb(product_row) order by product_row.updated_at, product_row.id)
            from public.products product_row
            where product_row.family_id = p_family_id
        ), '[]'::jsonb),
        'purchase_history', coalesce((
            select jsonb_agg(to_jsonb(history_row) order by history_row.updated_at, history_row.id)
            from public.purchase_history history_row
            where history_row.family_id = p_family_id
        ), '[]'::jsonb),
        'history_items', coalesce((
            select jsonb_agg(to_jsonb(item_row) order by item_row.updated_at, item_row.id)
            from public.history_items item_row
            where item_row.family_id = p_family_id
        ), '[]'::jsonb)
    ) into v_snapshot;

    return v_snapshot;
end;
$$;

create or replace function public.sync_family_snapshot(
    p_family_id uuid,
    p_snapshot jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
    if not (select private.is_family_member(p_family_id)) then
        raise exception 'Family is unavailable';
    end if;
    if jsonb_typeof(coalesce(p_snapshot, '{}'::jsonb)) <> 'object' then
        raise exception 'Invalid snapshot';
    end if;
    if jsonb_typeof(coalesce(p_snapshot -> 'stores', '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_snapshot -> 'shopping_lists', '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_snapshot -> 'products', '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_snapshot -> 'purchase_history', '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_snapshot -> 'history_items', '[]'::jsonb)) <> 'array' then
        raise exception 'Invalid snapshot';
    end if;
    if jsonb_array_length(coalesce(p_snapshot -> 'stores', '[]'::jsonb))
       + jsonb_array_length(coalesce(p_snapshot -> 'shopping_lists', '[]'::jsonb))
       + jsonb_array_length(coalesce(p_snapshot -> 'products', '[]'::jsonb))
       + jsonb_array_length(coalesce(p_snapshot -> 'purchase_history', '[]'::jsonb))
       + jsonb_array_length(coalesce(p_snapshot -> 'history_items', '[]'::jsonb)) > 5000 then
        raise exception 'Snapshot is too large';
    end if;

    insert into public.stores (
        id, family_id, name, icon, color_hex, address, latitude, longitude,
        external_app_url, is_pinned, created_at, updated_at, deleted_at
    )
    select
        incoming.id,
        p_family_id,
        coalesce(nullif(btrim(incoming.name), ''), 'Магазин'),
        coalesce(incoming.icon, ''),
        coalesce(incoming.color_hex, '#34785B'),
        incoming.address,
        incoming.latitude,
        incoming.longitude,
        incoming.external_app_url,
        coalesce(incoming.is_pinned, false),
        coalesce(incoming.created_at, now()),
        coalesce(incoming.updated_at, incoming.created_at, now()),
        incoming.deleted_at
    from jsonb_to_recordset(coalesce(p_snapshot -> 'stores', '[]'::jsonb)) as incoming(
        id uuid,
        name text,
        icon text,
        color_hex text,
        address text,
        latitude double precision,
        longitude double precision,
        external_app_url text,
        is_pinned boolean,
        created_at timestamptz,
        updated_at timestamptz,
        deleted_at timestamptz
    )
    where incoming.id is not null
    on conflict (id) do update
    set name = excluded.name,
        icon = excluded.icon,
        color_hex = excluded.color_hex,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        external_app_url = excluded.external_app_url,
        is_pinned = excluded.is_pinned,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at
    where public.stores.family_id = excluded.family_id
      and excluded.updated_at > public.stores.updated_at;

    insert into public.shopping_lists (
        id, family_id, store_id, title, status, created_at, updated_at, deleted_at
    )
    select
        incoming.id,
        p_family_id,
        incoming.store_id,
        coalesce(nullif(btrim(incoming.title), ''), 'Список покупок'),
        coalesce(incoming.status, 'active'),
        coalesce(incoming.created_at, now()),
        coalesce(incoming.updated_at, incoming.created_at, now()),
        incoming.deleted_at
    from jsonb_to_recordset(coalesce(p_snapshot -> 'shopping_lists', '[]'::jsonb)) as incoming(
        id uuid,
        store_id uuid,
        title text,
        status text,
        created_at timestamptz,
        updated_at timestamptz,
        deleted_at timestamptz
    )
    where incoming.id is not null
    on conflict (id) do update
    set store_id = excluded.store_id,
        title = excluded.title,
        status = excluded.status,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at
    where public.shopping_lists.family_id = excluded.family_id
      and excluded.updated_at > public.shopping_lists.updated_at;

    insert into public.products (
        id, family_id, list_id, store_id, name, quantity, unit, category,
        estimated_price, original_price, image_url, source_url, note,
        is_purchased, purchased_at, purchased_by_name,
        created_at, updated_at, deleted_at
    )
    select
        incoming.id,
        p_family_id,
        incoming.list_id,
        incoming.store_id,
        coalesce(nullif(btrim(incoming.name), ''), 'Товар'),
        coalesce(incoming.quantity, 1),
        coalesce(incoming.unit, 'piece'),
        coalesce(incoming.category, 'other'),
        coalesce(incoming.estimated_price, 0),
        incoming.original_price,
        incoming.image_url,
        incoming.source_url,
        coalesce(incoming.note, ''),
        coalesce(incoming.is_purchased, false),
        incoming.purchased_at,
        incoming.purchased_by_name,
        coalesce(incoming.created_at, now()),
        coalesce(incoming.updated_at, incoming.created_at, now()),
        incoming.deleted_at
    from jsonb_to_recordset(coalesce(p_snapshot -> 'products', '[]'::jsonb)) as incoming(
        id uuid,
        list_id uuid,
        store_id uuid,
        name text,
        quantity numeric,
        unit text,
        category text,
        estimated_price numeric,
        original_price numeric,
        image_url text,
        source_url text,
        note text,
        is_purchased boolean,
        purchased_at timestamptz,
        purchased_by_name text,
        created_at timestamptz,
        updated_at timestamptz,
        deleted_at timestamptz
    )
    where incoming.id is not null
      and incoming.list_id is not null
    on conflict (id) do update
    set list_id = excluded.list_id,
        store_id = excluded.store_id,
        name = excluded.name,
        quantity = excluded.quantity,
        unit = excluded.unit,
        category = excluded.category,
        estimated_price = excluded.estimated_price,
        original_price = excluded.original_price,
        image_url = excluded.image_url,
        source_url = excluded.source_url,
        note = excluded.note,
        is_purchased = excluded.is_purchased,
        purchased_at = excluded.purchased_at,
        purchased_by_name = excluded.purchased_by_name,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at
    where public.products.family_id = excluded.family_id
      and excluded.updated_at > public.products.updated_at;

    insert into public.purchase_history (
        id, family_id, store_id, total, purchased_at, member_names,
        created_at, updated_at, deleted_at
    )
    select
        incoming.id,
        p_family_id,
        incoming.store_id,
        coalesce(incoming.total, 0),
        coalesce(incoming.purchased_at, incoming.created_at, now()),
        coalesce(nullif(btrim(incoming.member_names), ''), 'Семья'),
        coalesce(incoming.created_at, now()),
        coalesce(incoming.updated_at, incoming.created_at, now()),
        incoming.deleted_at
    from jsonb_to_recordset(coalesce(p_snapshot -> 'purchase_history', '[]'::jsonb)) as incoming(
        id uuid,
        store_id uuid,
        total numeric,
        purchased_at timestamptz,
        member_names text,
        created_at timestamptz,
        updated_at timestamptz,
        deleted_at timestamptz
    )
    where incoming.id is not null
    on conflict (id) do update
    set store_id = excluded.store_id,
        total = excluded.total,
        purchased_at = excluded.purchased_at,
        member_names = excluded.member_names,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at
    where public.purchase_history.family_id = excluded.family_id
      and excluded.updated_at > public.purchase_history.updated_at;

    insert into public.history_items (
        id, family_id, history_id, name, quantity, unit, category,
        estimated_price, note, purchased_at, purchased_by_name, store_name,
        created_at, updated_at, deleted_at
    )
    select
        incoming.id,
        p_family_id,
        incoming.history_id,
        coalesce(nullif(btrim(incoming.name), ''), 'Товар'),
        coalesce(incoming.quantity, 1),
        coalesce(incoming.unit, 'piece'),
        coalesce(incoming.category, 'other'),
        coalesce(incoming.estimated_price, 0),
        coalesce(incoming.note, ''),
        incoming.purchased_at,
        incoming.purchased_by_name,
        incoming.store_name,
        coalesce(incoming.created_at, now()),
        coalesce(incoming.updated_at, incoming.created_at, now()),
        incoming.deleted_at
    from jsonb_to_recordset(coalesce(p_snapshot -> 'history_items', '[]'::jsonb)) as incoming(
        id uuid,
        history_id uuid,
        name text,
        quantity numeric,
        unit text,
        category text,
        estimated_price numeric,
        note text,
        purchased_at timestamptz,
        purchased_by_name text,
        store_name text,
        created_at timestamptz,
        updated_at timestamptz,
        deleted_at timestamptz
    )
    where incoming.id is not null
      and incoming.history_id is not null
    on conflict (id) do update
    set history_id = excluded.history_id,
        name = excluded.name,
        quantity = excluded.quantity,
        unit = excluded.unit,
        category = excluded.category,
        estimated_price = excluded.estimated_price,
        note = excluded.note,
        purchased_at = excluded.purchased_at,
        purchased_by_name = excluded.purchased_by_name,
        store_name = excluded.store_name,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at
    where public.history_items.family_id = excluded.family_id
      and excluded.updated_at > public.history_items.updated_at;

    return public.get_family_snapshot(p_family_id);
end;
$$;

revoke all on function public.ensure_family(uuid, text, timestamptz, timestamptz)
    from public, anon;
revoke all on function public.create_family_invitation(uuid, text)
    from public, anon;
revoke all on function public.accept_family_invitation(uuid)
    from public, anon;
revoke all on function public.revoke_family_invitation(uuid)
    from public, anon;
revoke all on function public.leave_family(uuid)
    from public, anon;
revoke all on function public.remove_family_member(uuid, uuid)
    from public, anon;
revoke all on function public.get_my_families()
    from public, anon;
revoke all on function public.get_family_members(uuid)
    from public, anon;
revoke all on function public.get_pending_invitations()
    from public, anon;
revoke all on function public.get_family_snapshot(uuid)
    from public, anon;
revoke all on function public.sync_family_snapshot(uuid, jsonb)
    from public, anon;

grant execute on function public.ensure_family(uuid, text, timestamptz, timestamptz)
    to authenticated;
grant execute on function public.create_family_invitation(uuid, text)
    to authenticated;
grant execute on function public.accept_family_invitation(uuid)
    to authenticated;
grant execute on function public.revoke_family_invitation(uuid)
    to authenticated;
grant execute on function public.leave_family(uuid)
    to authenticated;
grant execute on function public.remove_family_member(uuid, uuid)
    to authenticated;
grant execute on function public.get_my_families()
    to authenticated;
grant execute on function public.get_family_members(uuid)
    to authenticated;
grant execute on function public.get_pending_invitations()
    to authenticated;
grant execute on function public.get_family_snapshot(uuid)
    to authenticated;
grant execute on function public.sync_family_snapshot(uuid, jsonb)
    to authenticated;

do $$
declare
    v_table text;
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        foreach v_table in array array[
            'families',
            'family_members',
            'family_invitations',
            'stores',
            'shopping_lists',
            'products',
            'purchase_history',
            'history_items'
        ] loop
            if not exists (
                select 1
                from pg_publication_tables
                where pubname = 'supabase_realtime'
                  and schemaname = 'public'
                  and tablename = v_table
            ) then
                execute format(
                    'alter publication supabase_realtime add table public.%I',
                    v_table
                );
            end if;
        end loop;
    end if;
end;
$$;
