create table public.entitlements (
    user_id uuid primary key references auth.users(id) on delete cascade,
    is_plus boolean not null default false,
    expires_at timestamptz,
    updated_at timestamptz not null default now()
);

alter table public.entitlements enable row level security;
revoke all on public.entitlements from public, anon, authenticated;
grant select on public.entitlements to authenticated;
create policy "Read own entitlement" on public.entitlements for select to authenticated
    using (user_id = (select auth.uid()));

create function private.is_plus(uid uuid) returns boolean
language sql stable set search_path = '' as $$
    select exists (
        select 1 from public.entitlements e
        where e.user_id = uid and e.is_plus and e.expires_at > now()
    )
$$;

create function public.is_plus(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select coalesce(uid = (select auth.uid()) and private.has_active_session()
        and private.is_plus(uid), false)
$$;

-- Track each subscription chain independently so an old plan cannot revoke a new one.
create table private.plus_subscriptions (
    user_id uuid not null references auth.users(id) on delete cascade,
    original_transaction_id text not null,
    product_id text not null,
    event_at timestamptz not null,
    event_rank integer not null,
    expires_at timestamptz not null,
    is_active boolean not null,
    primary key (user_id, original_transaction_id, product_id)
);
alter table private.plus_subscriptions enable row level security;
revoke all on private.plus_subscriptions from public, anon, authenticated;

create function public.apply_revenuecat_plus_event(
    subscriber uuid, transaction_chain text, product text, event_type text,
    event_time timestamptz, period_end timestamptz
) returns void
language plpgsql security definer set search_path = '' as $$
declare
    effective_end timestamptz;
    incoming_rank integer := case event_type
        when 'EXPIRATION' then 4 when 'BILLING_ISSUE' then 3 when 'CANCELLATION' then 2 else 1 end;
begin
    if event_type not in ('INITIAL_PURCHASE', 'RENEWAL', 'CANCELLATION', 'EXPIRATION', 'BILLING_ISSUE')
        or product not in ('kindred_plus_monthly', 'kindred_plus_3month')
        or transaction_chain is null or event_time is null or period_end is null then
        raise exception 'Invalid subscription event' using errcode = '22023';
    end if;

    -- Serialize entitlement projections for this member, including concurrent plan changes.
    perform 1 from auth.users where id = subscriber for update;
    if not found then return; end if;

    insert into private.plus_subscriptions as current_subscription
        (user_id, original_transaction_id, product_id, event_at, event_rank, expires_at, is_active)
    values (subscriber, transaction_chain, product, event_time, incoming_rank, period_end, event_type <> 'EXPIRATION')
    on conflict (user_id, original_transaction_id, product_id) do update set
        event_at = excluded.event_at,
        event_rank = excluded.event_rank,
        expires_at = case when event_type in ('CANCELLATION', 'BILLING_ISSUE')
            then greatest(current_subscription.expires_at, excluded.expires_at)
            else excluded.expires_at end,
        is_active = excluded.is_active
    where (excluded.event_at, excluded.event_rank) > (current_subscription.event_at, current_subscription.event_rank)
        and (event_type <> 'EXPIRATION' or excluded.expires_at >= current_subscription.expires_at)
        and (event_type <> 'CANCELLATION' or current_subscription.is_active);

    if not found then return; end if;
    select max(expires_at) into effective_end from private.plus_subscriptions
        where user_id = subscriber and is_active and expires_at > now();

    insert into public.entitlements (user_id, is_plus, expires_at, updated_at)
    values (subscriber, effective_end is not null, coalesce(effective_end, period_end), now())
    on conflict (user_id) do update set is_plus = excluded.is_plus,
        expires_at = excluded.expires_at, updated_at = excluded.updated_at;
end
$$;

revoke execute on function public.apply_revenuecat_plus_event(uuid,text,text,text,timestamptz,timestamptz)
    from public, anon, authenticated;
grant execute on function public.apply_revenuecat_plus_event(uuid,text,text,text,timestamptz,timestamptz)
    to service_role;

-- The ledger survives removing a like, a match, or a recipient's account.
create table private.daily_likes (
    user_id uuid not null references auth.users(id) on delete cascade,
    local_day date not null,
    used integer not null check (used >= 0),
    primary key (user_id, local_day)
);
alter table private.daily_likes enable row level security;
revoke all on private.daily_likes from public, anon, authenticated;

create function private.like_day(at_time timestamptz) returns date
language sql immutable set search_path = '' as $$
    select (at_time at time zone 'America/Chicago')::date
$$;

insert into private.daily_likes (user_id, local_day, used)
select sender, private.like_day(created_at), count(*)::int
from private.member_interests
where created_at >= (private.like_day(now())::timestamp at time zone 'America/Chicago')
group by sender, private.like_day(created_at);

create function private.count_new_like() returns trigger
language plpgsql set search_path = '' as $$
declare
    unlimited boolean := private.is_plus(new.sender);
begin
    -- AFTER INSERT runs only for a new row, even on an idempotent retry.
    -- The ledger row serializes concurrent likes to different recipients.
    insert into private.daily_likes as daily (user_id, local_day, used)
    values (new.sender, private.like_day(clock_timestamp()), 1)
    on conflict (user_id, local_day) do update set used = daily.used + 1
        where unlimited or daily.used < 12;
    if not found then
        raise sqlstate 'PGRST' using
            message = '{"code":"LIKE_LIMIT_REACHED","message":"Daily like limit reached","details":"{\"remaining\":0}"}',
            detail = '{"status":429,"headers":{}}';
    end if;
    return new;
end
$$;

create trigger count_new_like after insert on private.member_interests
for each row execute function private.count_new_like();

create function private.likes_remaining(uid uuid) returns integer
language sql stable set search_path = '' as $$
    select case when private.is_plus(uid) then null else greatest(0, 12 - coalesce((
        select used from private.daily_likes where user_id = uid and local_day = private.like_day(now())
    ), 0)) end
$$;

create function public.likes_remaining_today() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
    if not private.has_active_session() then
        raise exception 'Sign-in session ended' using errcode = 'PT401';
    end if;
    return jsonb_build_object('remaining', private.likes_remaining(auth.uid()));
end
$$;

create table private.passed_incoming_likes (
    user_id uuid not null references auth.users(id) on delete cascade,
    sender uuid not null references auth.users(id) on delete cascade,
    primary key (user_id, sender)
);
alter table private.passed_incoming_likes enable row level security;
revoke all on private.passed_incoming_likes from public, anon, authenticated;

create function private.pending_incoming_likes(viewer uuid)
returns table (sender uuid, received_at timestamptz, unseen boolean)
language sql stable set search_path = '' as $$
    select i.sender, max(i.created_at), bool_or(i.seen_at is null)
    from private.member_interests i
    join public.discovery_profiles d on d.user_id = i.sender
    where i.recipient = viewer and not private.members_blocked(viewer, i.sender)
        and not exists (
            select 1 from private.member_connections c
            where c.first_member = least(viewer, i.sender) and c.second_member = greatest(viewer, i.sender)
        )
        and not exists (
            select 1 from private.passed_incoming_likes p where p.user_id = viewer and p.sender = i.sender
        )
    group by i.sender
$$;

create function public.liked_me() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := auth.uid();
begin
    if not private.has_active_session() then
        raise exception 'Sign-in session ended' using errcode = 'PT401';
    end if;
    if not private.is_plus(viewer) then
        return jsonb_build_object('count', (select count(*) from private.pending_incoming_likes(viewer)));
    end if;
    return (
        with incoming as materialized (select * from private.pending_incoming_likes(viewer))
        select jsonb_build_object(
            'count', (select count(*) from incoming),
            'profiles', coalesce((select jsonb_agg(
                private.shared_member_profile(d.user_id, d.profile, d.privacy, 0)
                order by incoming.received_at desc, d.user_id)
                from incoming join public.discovery_profiles d on d.user_id = incoming.sender), '[]'::jsonb)
        )
    );
end
$$;

create function public.pass_incoming_like(target uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare viewer uuid := auth.uid();
begin
    if not private.has_active_session() then
        raise exception 'Sign-in session ended' using errcode = 'PT401';
    end if;
    if not private.is_plus(viewer) then
        raise exception 'Kindred Plus required' using errcode = '42501';
    end if;
    insert into private.passed_incoming_likes (user_id, sender)
    select viewer, sender from private.pending_incoming_likes(viewer) where sender = target
    on conflict do nothing;
end
$$;

-- Mark the count as seen without disclosing or accepting private sender identifiers.
create function public.mark_incoming_likes_seen() returns void
language plpgsql security definer set search_path = '' as $$
declare viewer uuid := auth.uid();
begin
    if not private.has_active_session() then
        raise exception 'Sign-in session ended' using errcode = 'PT401';
    end if;
    update private.member_interests set seen_at = clock_timestamp()
    where recipient = viewer and seen_at is null
        and sender in (select sender from private.pending_incoming_likes(viewer));
end
$$;

revoke execute on function private.is_plus(uuid), private.like_day(timestamptz),
    private.count_new_like(), private.likes_remaining(uuid), private.pending_incoming_likes(uuid)
    from public, anon, authenticated;
revoke execute on function public.is_plus(uuid), public.likes_remaining_today(), public.liked_me(),
    public.pass_incoming_like(uuid), public.mark_incoming_likes_seen() from public, anon;
grant execute on function public.is_plus(uuid), public.likes_remaining_today(), public.liked_me(),
    public.pass_incoming_like(uuid), public.mark_incoming_likes_seen() to authenticated;

-- Gate incoming identities on the legacy activity endpoint as well as liked_me.
create or replace function private.member_activity()
returns jsonb language sql stable security definer set search_path = '' as $$
    with viewer as (select auth.uid() as id),
    pairs as (
        select c.*, v.id as viewer_id,
            case when c.first_member = v.id then c.second_member else c.first_member end as peer,
            case when c.first_member = v.id then c.first_read_at else c.second_read_at end as read_at
        from private.member_connections c join viewer v on v.id in (c.first_member, c.second_member)
    ),
    active_pairs as (
        select * from pairs where ended_at is null and not private.members_blocked(viewer_id, peer)
    ),
    interests as (
        select i.*, v.id as viewer_id, case when i.sender = v.id then i.recipient else i.sender end as peer
        from private.member_interests i join viewer v on v.id in (i.sender, i.recipient)
        where not private.members_blocked(i.sender, i.recipient)
            and (i.sender = v.id or exists (
                select 1 from active_pairs pair where pair.peer = i.sender
            ))
    ),
    peers as (select peer from active_pairs union select peer from interests),
    incoming as materialized (select * from private.pending_incoming_likes(auth.uid()))
    select jsonb_build_object(
        'members', coalesce((select jsonb_agg(private.shared_member_profile(d.user_id, d.profile, d.privacy, 0))
            from peers join public.discovery_profiles d on d.user_id = peer), '[]'::jsonb),
        'likes', coalesce((select jsonb_agg(jsonb_build_object(
            'id', id, 'senderID', case when sender = viewer_id then 'me' else sender::text end,
            'recipientID', case when recipient = viewer_id then 'me' else recipient::text end,
            'promptID', prompt_id, 'photoID', photo_id, 'createdAt', created_at
        ) order by created_at, id) from interests), '[]'::jsonb),
        'incomingLikesCount', (select count(*) from incoming),
        'unseenIncomingCount', (select count(*) from incoming where unseen),
        'likesRemaining', private.likes_remaining(auth.uid()),
        'entitlement', (select to_jsonb(e) - 'user_id' - 'updated_at'
            from public.entitlements e where e.user_id = auth.uid()),
        'matches', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'memberID', peer, 'createdAt', created_at))
            from active_pairs), '[]'::jsonb),
        'endedMemberIDs', coalesce((select jsonb_agg(peer) from pairs where ended_at is not null), '[]'::jsonb),
        'conversations', coalesce((select jsonb_agg(jsonb_build_object(
            'id', p.id, 'memberID', p.peer,
            'unreadCount', (select count(*) from private.member_messages m
                where m.connection_id = p.id and m.sender <> p.viewer_id and m.created_at > p.read_at),
            'messages', recent.page->'messages',
            'hasOlderMessages', recent.page->'hasMore'
        )) from active_pairs p
            cross join lateral (select private.message_page(p.id, p.viewer_id, 100) as page) recent
        ), '[]'::jsonb)
    )
$$;

create or replace function private.member_activity_action(
    action text, target uuid, prompt_id text, photo_id text, message_body text,
    message_id uuid, read_message_id uuid, report_reason text, report_details text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    viewer uuid := auth.uid();
    connection private.member_connections%rowtype;
    read_time timestamptz;
    matched_now boolean := false;
begin
    if not private.has_active_session() then
        raise exception 'Sign-in session ended' using errcode = 'PT401';
    end if;
    if viewer is null or target is null or viewer = target
        or not exists (select 1 from public.discovery_profiles where user_id = viewer)
        or not exists (select 1 from public.discovery_profiles where user_id = target) then
        raise exception 'Profile unavailable' using errcode = '42501';
    end if;

    perform private.lock_member_pair(viewer, target);
    select * into connection from private.member_connections
    where first_member = least(viewer,target) and second_member = greatest(viewer,target);

    if action = 'report' then
        if connection.id is null and not private.members_blocked(viewer, target)
            and not exists (select 1 from private.member_interests as i
                where (i.sender = target and i.recipient = viewer and private.is_plus(viewer))
                    or (i.sender = viewer and i.recipient = target))
            and not exists (select 1 from private.eligible_discovery_members(target)) then
            raise exception 'Profile unavailable' using errcode = '42501';
        end if;
        if not exists (select 1 from private.member_reports where reporter = viewer and reported = target
            and reason = report_reason and details = coalesce(report_details, '')) then
            insert into private.member_reports(reporter, reported, reason, details)
            values (viewer, target, report_reason, coalesce(report_details, ''));
        end if;
    elsif private.members_blocked(viewer, target) then
        raise exception 'Connection unavailable' using errcode = '42501';
    elsif action = 'like' then
        if connection.ended_at is not null or (connection.id is null
            and not (private.is_plus(viewer) and exists (
                select 1 from private.pending_incoming_likes(viewer) where sender = target
            ))
            and not exists (select 1 from private.eligible_discovery_members(target))) then
            raise exception 'Profile unavailable' using errcode = '42501';
        end if;
        if (prompt_id is not null and photo_id is not null)
            or (prompt_id is not null and not exists (
                select 1 from public.discovery_profiles d, jsonb_array_elements(d.profile->'prompts') p
                where d.user_id = target and p->>'id' = prompt_id and btrim(p->>'answer') <> ''))
            or (photo_id is not null and not exists (
                select 1 from public.discovery_profiles d, jsonb_array_elements(d.profile->'photos') p
                where d.user_id = target and p->>'id' = photo_id)) then
            raise exception 'Like target unavailable' using errcode = '22023';
        end if;
        insert into private.member_interests(sender, recipient, prompt_id, photo_id)
        values (viewer, target, prompt_id, photo_id) on conflict do nothing;
        if connection.id is null and exists (
            select 1 from private.member_interests i where i.sender = target and i.recipient = viewer
        ) then
            insert into private.member_connections(first_member, second_member)
            values (least(viewer,target), greatest(viewer,target))
            on conflict do nothing;
            matched_now := found;
        end if;
    elsif action = 'remove_like' then
        delete from private.member_interests where sender = viewer and recipient = target;
    elsif action = 'unmatch' then
        if connection.id is null then raise exception 'Connection unavailable' using errcode = '42501'; end if;
        perform private.end_member_connection(viewer, target);
    elsif action in ('send', 'read') then
        if connection.id is null or connection.ended_at is not null then
            raise exception 'Connection unavailable' using errcode = '42501';
        end if;
        if action = 'send' then
            insert into private.member_messages(id, connection_id, sender, body)
            values (message_id, connection.id, viewer, btrim(message_body))
            on conflict do nothing;
            if not found and not exists (select 1 from private.member_messages m
                where m.id = message_id and m.connection_id = connection.id and m.sender = viewer and m.body = btrim(message_body)) then
                raise exception 'Message identifier unavailable' using errcode = '42501';
            end if;
        else
            select created_at into read_time from private.member_messages
            where id = read_message_id and connection_id = connection.id;
            if read_time is not null then
                update private.member_connections set
                    first_read_at = case when viewer = first_member then greatest(first_read_at, read_time) else first_read_at end,
                    second_read_at = case when viewer = second_member then greatest(second_read_at, read_time) else second_read_at end
                where id = connection.id;
            end if;
        end if;
    else
        raise exception 'Unknown action' using errcode = '22023';
    end if;
    return jsonb_build_object('matched', matched_now);
end
$$;
