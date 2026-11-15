create table private.free_like_usage (
    user_id uuid primary key references auth.users(id) on delete cascade,
    used integer not null check (used between 1 and 12),
    resets_at timestamptz,
    check ((used = 12) = (resets_at is not null))
);

alter table private.free_like_usage enable row level security;
revoke all on private.free_like_usage from public, anon, authenticated;

-- Carry forward today's usage. If the last like was removed, the old ledger
-- records the count only, so start an exhausted balance's wait at cutover.
insert into private.free_like_usage (user_id, used, resets_at)
select d.user_id, least(d.used, 12),
    case when d.used >= 12 then coalesce((
        select max(i.created_at)
        from private.member_interests i
        where i.sender = d.user_id and private.like_day(i.created_at) = d.local_day
    ), now()) + interval '24 hours' end
from private.daily_likes d
where d.local_day = private.like_day(now()) and d.used > 0;

create function private.free_like_reset_epoch(uid uuid) returns double precision
language sql stable set search_path = '' as $$
    select extract(epoch from resets_at)::double precision
    from private.free_like_usage
    where user_id = uid and resets_at > now() and not private.is_plus(uid)
$$;
revoke execute on function private.free_like_reset_epoch(uuid) from public, anon, authenticated;

create or replace function private.count_new_like() returns trigger
language plpgsql set search_path = '' as $$
declare
    reset_epoch double precision;
begin
    if private.is_plus(new.sender) then return new; end if;

    -- The unique row serializes concurrent likes. Only a new interest reaches this trigger.
    insert into private.free_like_usage as usage (user_id, used)
    values (new.sender, 1)
    on conflict (user_id) do update set
        used = case when usage.resets_at <= clock_timestamp() then 1 else usage.used + 1 end,
        resets_at = case when usage.used = 11 then clock_timestamp() + interval '24 hours' end
    where usage.used < 12 or usage.resets_at <= clock_timestamp();

    if not found then
        select extract(epoch from resets_at)::double precision into reset_epoch
        from private.free_like_usage where user_id = new.sender;
        raise sqlstate 'PGRST' using
            message = jsonb_build_object('code', 'LIKE_LIMIT_REACHED', 'message', 'Free like limit reached',
                'details', jsonb_build_object('remaining', 0, 'resetsAtEpoch', reset_epoch)::text)::text,
            detail = '{"status":429,"headers":{}}';
    end if;
    return new;
end
$$;

create or replace function private.likes_remaining(uid uuid) returns integer
language sql stable set search_path = '' as $$
    select case when private.is_plus(uid) then null else 12 - coalesce((
        select used from private.free_like_usage
        where user_id = uid and (resets_at is null or resets_at > now())
    ), 0) end
$$;

create or replace function public.likes_remaining_today() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
    if not private.has_active_session() then
        raise exception 'Sign-in session ended' using errcode = 'PT401';
    end if;
    return jsonb_build_object('remaining', private.likes_remaining(auth.uid()),
        'resetsAtEpoch', private.free_like_reset_epoch(auth.uid()));
end
$$;

create or replace function public.member_activity() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
    if not private.has_active_session() then
        raise exception 'Sign-in session ended' using errcode = 'PT401';
    end if;
    return private.member_activity()
        || jsonb_build_object('likesResetAtEpoch', private.free_like_reset_epoch(auth.uid()));
end
$$;
