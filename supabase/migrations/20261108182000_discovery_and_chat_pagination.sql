-- Keep eligibility shared between the feed and actions on individual introductions.
create function private.eligible_discovery_members(target uuid default null)
returns table(member_id uuid, profile jsonb, privacy jsonb, miles int)
language sql stable set search_path = '' as $$
    select candidate.user_id, candidate.profile, candidate.privacy, distance.miles
    from public.discovery_profiles as viewer
    join public.discovery_profiles as candidate on candidate.user_id <> viewer.user_id
    cross join lateral (select private.discovery_distance(
        case when (viewer.preferences->>'useHomeCityForSearch') = 'true'
            then viewer.profile->>'city' else viewer.preferences->>'searchCity' end,
        candidate.profile->>'city'
    ) as miles) as distance
    where viewer.user_id = (select auth.uid())
        and (target is null or candidate.user_id = target)
        and not (viewer.privacy->>'discoveryPaused')::boolean
        and not (candidate.privacy->>'discoveryPaused')::boolean
        and viewer.preferences->'dating'->'genders' ? (candidate.profile->>'gender')
        and candidate.preferences->'dating'->'genders' ? (viewer.profile->>'gender')
        and (candidate.profile->>'age')::int between (viewer.preferences->'dating'->>'minimumAge')::int and (viewer.preferences->'dating'->>'maximumAge')::int
        and (viewer.profile->>'age')::int between (candidate.preferences->'dating'->>'minimumAge')::int and (candidate.preferences->'dating'->>'maximumAge')::int
        and not exists (
            select 1 from public.member_blocks as block
            where (block.user_id = viewer.user_id and block.blocked_id = candidate.user_id)
                or (block.user_id = candidate.user_id and block.blocked_id = viewer.user_id)
        )
        and not exists (
            select 1 from private.member_connections as connection
            where connection.first_member = least(viewer.user_id, candidate.user_id)
                and connection.second_member = greatest(viewer.user_id, candidate.user_id)
        )
        and distance.miles <= (viewer.preferences->>'radiusMiles')::int
$$;

create or replace function private.discover_profiles()
returns setof jsonb language sql stable security definer set search_path = '' as $$
    select private.shared_member_profile(d.member_id, d.profile, d.privacy, d.miles)
    from private.eligible_discovery_members() d
    order by d.miles, d.member_id
    limit 20
$$;

create function private.discovery_page(after_miles int, after_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
    if not private.has_active_session() then
        raise exception 'Sign-in session ended' using errcode = 'PT401';
    end if;
    if (after_miles is null) <> (after_id is null) then
        raise exception 'Invalid discovery cursor' using errcode = '22023';
    end if;

    return (
        with candidates as materialized (
            select d.*
            from private.eligible_discovery_members() d
            where after_id is null or (d.miles, d.member_id) > (after_miles, after_id)
            order by d.miles, d.member_id
            limit 21
        ), page as (
            select * from candidates order by miles, member_id limit 20
        )
        select jsonb_build_object(
            'profiles', coalesce((select jsonb_agg(
                private.shared_member_profile(member_id, profile, privacy, miles)
                order by miles, member_id) from page), '[]'::jsonb),
            'next', case when (select count(*) from candidates) > 20 then (
                select jsonb_build_object('miles', miles, 'id', member_id)
                from page order by miles desc, member_id desc limit 1
            ) end
        )
    );
end
$$;

create function public.discovery_page(after_miles int default null, after_id uuid default null)
returns jsonb language sql stable security invoker set search_path = '' as $$
    select private.discovery_page(after_miles, after_id)
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
                where (i.sender = target and i.recipient = viewer) or (i.sender = viewer and i.recipient = target))
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
            and not exists (select 1 from private.member_interests as i where i.sender = target and i.recipient = viewer)
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

-- The database resolves the cursor UUID so clients never round message timestamps.
create function private.message_page(thread_id uuid, viewer uuid, page_size int, before_id uuid default null)
returns jsonb language sql stable set search_path = '' as $$
    with cursor_row as (
        select m.created_at, m.id
        from private.member_messages m where m.connection_id = thread_id and m.id = before_id
    ), candidates as materialized (
        select m.id, m.sender, m.body, m.created_at
        from private.member_messages m
        where m.connection_id = thread_id
            and (before_id is null or (m.created_at, m.id) < (select c.created_at, c.id from cursor_row c))
        order by m.created_at desc, m.id desc
        limit page_size + 1
    ), page as (
        select * from candidates order by created_at desc, id desc limit page_size
    )
    select jsonb_build_object(
        'messages', coalesce((select jsonb_agg(jsonb_build_object(
            'id', id, 'text', body,
            'senderID', case when sender = viewer then 'me' else sender::text end,
            'createdAt', created_at
        ) order by created_at, id) from page), '[]'::jsonb),
        'hasMore', (select count(*) from candidates) > page_size
    )
$$;

create function private.conversation_history(thread_id uuid, before_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := auth.uid();
begin
    if not private.has_active_session() then
        raise exception 'Sign-in session ended' using errcode = 'PT401';
    end if;
    if before_id is null or not exists (
        select 1 from private.member_connections c
        where c.id = thread_id and c.ended_at is null
            and viewer in (c.first_member, c.second_member)
            and not private.members_blocked(c.first_member, c.second_member)
    ) or not exists (
        select 1 from private.member_messages m where m.connection_id = thread_id and m.id = before_id
    ) then
        raise exception 'Conversation unavailable' using errcode = '42501';
    end if;

    return private.message_page(thread_id, viewer, 50, before_id);
end
$$;

create function public.conversation_history(thread_id uuid, before_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
    select private.conversation_history(thread_id, before_id)
$$;

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
    ),
    peers as (select peer from active_pairs union select peer from interests)
    select jsonb_build_object(
        'members', coalesce((select jsonb_agg(private.shared_member_profile(d.user_id, d.profile, d.privacy, 0))
            from peers join public.discovery_profiles d on d.user_id = peer), '[]'::jsonb),
        'likes', coalesce((select jsonb_agg(jsonb_build_object(
            'id', id, 'senderID', case when sender = viewer_id then 'me' else sender::text end,
            'recipientID', case when recipient = viewer_id then 'me' else recipient::text end,
            'promptID', prompt_id, 'photoID', photo_id, 'createdAt', created_at
        ) order by created_at, id) from interests), '[]'::jsonb),
        'unseenLikeIDs', coalesce((select jsonb_agg(id order by id)
            from interests where recipient = viewer_id and seen_at is null
            and not exists (select 1 from active_pairs p where p.peer = interests.peer)), '[]'::jsonb),
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


revoke execute on function private.eligible_discovery_members(uuid),
    private.message_page(uuid,uuid,int,uuid) from public, anon, authenticated;
revoke execute on function private.discovery_page(int,uuid), public.discovery_page(int,uuid),
    private.conversation_history(uuid,uuid), public.conversation_history(uuid,uuid) from public, anon;
grant execute on function private.discovery_page(int,uuid), public.discovery_page(int,uuid),
    private.conversation_history(uuid,uuid), public.conversation_history(uuid,uuid) to authenticated;
