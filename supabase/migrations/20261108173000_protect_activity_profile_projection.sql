create function private.shared_member_profile(member_id uuid, profile jsonb, privacy jsonb, miles int)
returns jsonb language sql immutable set search_path = '' as $$
    select jsonb_build_object(
        'id', member_id::text,
        'name', profile->'name', 'age', profile->'age', 'gender', profile->'gender',
        'city', case when (privacy->>'showCity')::boolean then profile->>'city' else 'Location private' end,
        'distanceMiles', miles, 'occupation', profile->'occupation', 'bio', profile->'bio',
        'intention', profile->'intention', 'faith', profile->'faith', 'interests', profile->'interests',
        'prompts', profile->'prompts', 'photos', profile->'photos', 'isDemo', false,
        'locationStatus', case when (privacy->>'showCity')::boolean then profile->>'locationStatus' else 'None' end,
        'destination', case when (privacy->>'showCity')::boolean then profile->>'destination' else 'Atlanta, GA' end,
        'distanceOpenness', profile->'distanceOpenness', 'openToRelocating', profile->'openToRelocating'
    )
$$;
revoke execute on function private.shared_member_profile(uuid,jsonb,jsonb,int) from public, anon, authenticated;

create or replace function private.discover_profiles()
returns setof jsonb language sql stable security definer set search_path = '' as $$
    select private.shared_member_profile(candidate.user_id, candidate.profile, candidate.privacy, distance.miles)
    from public.discovery_profiles as viewer
    join public.discovery_profiles as candidate on candidate.user_id <> viewer.user_id
    cross join lateral (select private.discovery_distance(
        coalesce(viewer.preferences->>'searchOrigin', viewer.preferences->>'searchCity'), candidate.profile->>'city'
    ) as miles) as distance
    where viewer.user_id = (select auth.uid())
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
    order by distance.miles, candidate.user_id
    limit 20
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
        'matches', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'memberID', peer, 'createdAt', created_at))
            from active_pairs), '[]'::jsonb),
        'endedMemberIDs', coalesce((select jsonb_agg(peer) from pairs where ended_at is not null), '[]'::jsonb),
        'conversations', coalesce((select jsonb_agg(jsonb_build_object(
            'id', p.id, 'memberID', p.peer,
            'unreadCount', (select count(*) from private.member_messages m
                where m.connection_id = p.id and m.sender <> p.viewer_id and m.created_at > p.read_at),
            'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'text', m.body,
                'senderID', case when m.sender = p.viewer_id then 'me' else m.sender::text end,
                'createdAt', m.created_at) order by m.created_at, m.id)
                from (select * from private.member_messages m where m.connection_id = p.id
                    order by m.created_at desc, m.id desc limit 100) m), '[]'::jsonb)
        )) from active_pairs p), '[]'::jsonb)
    )
$$;

