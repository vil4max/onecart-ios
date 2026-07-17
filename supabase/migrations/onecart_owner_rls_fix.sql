-- Owners must be able to see their own family row before the AFTER INSERT
-- trigger creates the matching family_members record. PostgreSQL evaluates
-- SELECT policies for INSERT ... ON CONFLICT, so this owner branch is also
-- required for public.ensure_family() to create a new family safely.

drop policy if exists families_select_member_or_invitee on public.families;

create policy families_select_member_or_invitee
on public.families for select
to authenticated
using (
    owner_id = (select auth.uid())
    or (select private.is_family_member(id))
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

