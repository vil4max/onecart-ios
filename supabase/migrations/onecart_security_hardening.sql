-- Keep privileged implementations outside the Data API exposed schema.
-- Public RPCs are SECURITY INVOKER wrappers; their private callees still
-- enforce auth.uid(), ownership, membership, and invitation-email checks.

alter function public.create_family_invitation(uuid, text) set schema private;
alter function public.accept_family_invitation(uuid) set schema private;
alter function public.revoke_family_invitation(uuid) set schema private;
alter function public.leave_family(uuid) set schema private;
alter function public.remove_family_member(uuid, uuid) set schema private;

revoke all on function private.create_family_invitation(uuid, text)
    from public, anon;
revoke all on function private.accept_family_invitation(uuid)
    from public, anon;
revoke all on function private.revoke_family_invitation(uuid)
    from public, anon;
revoke all on function private.leave_family(uuid)
    from public, anon;
revoke all on function private.remove_family_member(uuid, uuid)
    from public, anon;

grant execute on function private.create_family_invitation(uuid, text)
    to authenticated;
grant execute on function private.accept_family_invitation(uuid)
    to authenticated;
grant execute on function private.revoke_family_invitation(uuid)
    to authenticated;
grant execute on function private.leave_family(uuid)
    to authenticated;
grant execute on function private.remove_family_member(uuid, uuid)
    to authenticated;

create function public.create_family_invitation(
    p_family_id uuid,
    p_email text
)
returns public.family_invitations
language sql
security invoker
set search_path = ''
as $$
    select * from private.create_family_invitation(p_family_id, p_email);
$$;

create function public.accept_family_invitation(p_invitation_id uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $$
    select private.accept_family_invitation(p_invitation_id);
$$;

create function public.revoke_family_invitation(p_invitation_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
    select private.revoke_family_invitation(p_invitation_id);
$$;

create function public.leave_family(p_family_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
    select private.leave_family(p_family_id);
$$;

create function public.remove_family_member(
    p_family_id uuid,
    p_user_id uuid
)
returns void
language sql
security invoker
set search_path = ''
as $$
    select private.remove_family_member(p_family_id, p_user_id);
$$;

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

-- Supabase creates this event-trigger function to enable RLS automatically.
-- It does not need to be directly callable through PostgREST.
revoke execute on function public.rls_auto_enable()
    from public, anon, authenticated;
