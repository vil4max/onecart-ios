-- Equal timestamps already represent the same client mutation. Avoid issuing
-- no-op updates for them so Realtime does not echo an unchanged snapshot back
-- into another synchronization cycle.

do $migration$
declare
    v_definition text;
begin
    select pg_get_functiondef(
        'public.sync_family_snapshot(uuid,jsonb)'::regprocedure
    ) into v_definition;

    v_definition := replace(
        v_definition,
        'excluded.updated_at >= public.stores.updated_at',
        'excluded.updated_at > public.stores.updated_at'
    );
    v_definition := replace(
        v_definition,
        'excluded.updated_at >= public.shopping_lists.updated_at',
        'excluded.updated_at > public.shopping_lists.updated_at'
    );
    v_definition := replace(
        v_definition,
        'excluded.updated_at >= public.products.updated_at',
        'excluded.updated_at > public.products.updated_at'
    );
    v_definition := replace(
        v_definition,
        'excluded.updated_at >= public.purchase_history.updated_at',
        'excluded.updated_at > public.purchase_history.updated_at'
    );
    v_definition := replace(
        v_definition,
        'excluded.updated_at >= public.history_items.updated_at',
        'excluded.updated_at > public.history_items.updated_at'
    );

    execute v_definition;
end;
$migration$;
