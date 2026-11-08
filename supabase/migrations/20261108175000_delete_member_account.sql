create function private.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
declare
    viewer uuid := auth.uid();
    current_session uuid := (auth.jwt()->>'session_id')::uuid;
begin
    if viewer is null or current_session is null or not exists (
        select 1 from auth.sessions
        where id = current_session and user_id = viewer
            and created_at >= clock_timestamp() - interval '5 minutes'
    ) then
        raise exception 'Sign in again before deleting your account' using errcode = '42501';
    end if;
    delete from auth.users where id = viewer;
end
$$;
create function public.delete_my_account() returns void
language sql security invoker set search_path = '' as $$
    select private.delete_my_account()
$$;
revoke execute on function private.delete_my_account(), public.delete_my_account() from public, anon;
grant execute on function private.delete_my_account(), public.delete_my_account() to authenticated;
