alter table private.member_interests add column seen_at timestamptz;

create function private.mark_likes_seen(like_ids uuid[]) returns void
language sql security definer set search_path = '' as $$
    update private.member_interests
    set seen_at = clock_timestamp()
    where recipient = (select auth.uid()) and id = any(like_ids) and seen_at is null
$$;
create function public.mark_likes_seen(like_ids uuid[]) returns void
language sql security invoker set search_path = '' as $$
    select private.mark_likes_seen(like_ids)
$$;
revoke execute on function public.mark_likes_seen(uuid[]), private.mark_likes_seen(uuid[]) from public, anon;
grant execute on function public.mark_likes_seen(uuid[]), private.mark_likes_seen(uuid[]) to authenticated;

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
            'messages', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'text', m.body,
                'senderID', case when m.sender = p.viewer_id then 'me' else m.sender::text end,
                'createdAt', m.created_at) order by m.created_at, m.id)
                from (select * from private.member_messages m where m.connection_id = p.id
                    order by m.created_at desc, m.id desc limit 100) m), '[]'::jsonb)
        )) from active_pairs p), '[]'::jsonb)
    )
$$;

