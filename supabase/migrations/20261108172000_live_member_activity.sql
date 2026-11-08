create table private.member_interests (
    id uuid primary key default gen_random_uuid(),
    sender uuid not null references auth.users(id) on delete cascade,
    recipient uuid not null references auth.users(id) on delete cascade,
    prompt_id text,
    photo_id text,
    created_at timestamptz not null default clock_timestamp(),
    unique nulls not distinct (sender, recipient, prompt_id, photo_id),
    check (sender <> recipient and (prompt_id is null or photo_id is null))
);
create index member_interests_recipient_idx on private.member_interests (recipient, sender);

create table private.member_connections (
    id uuid primary key default gen_random_uuid(),
    first_member uuid not null references auth.users(id) on delete cascade,
    second_member uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default clock_timestamp(),
    ended_at timestamptz,
    first_read_at timestamptz not null default '-infinity',
    second_read_at timestamptz not null default '-infinity',
    unique (first_member, second_member),
    check (first_member < second_member)
);
create index member_connections_second_idx on private.member_connections (second_member, first_member);

create table private.member_messages (
    id uuid primary key,
    connection_id uuid not null references private.member_connections(id) on delete cascade,
    sender uuid not null references auth.users(id) on delete cascade,
    body text not null check (char_length(btrim(body)) between 1 and 2000),
    created_at timestamptz not null default clock_timestamp()
);
create index member_messages_connection_idx on private.member_messages (connection_id, created_at desc, id desc);

create table private.member_reports (
    id uuid primary key default gen_random_uuid(),
    reporter uuid not null references auth.users(id) on delete cascade,
    reported uuid not null references auth.users(id) on delete cascade,
    reason text not null check (reason in ('Inappropriate content', 'Impersonation', 'Harassment', 'May be under 18', 'Other')),
    details text not null check (char_length(details) <= 1000),
    created_at timestamptz not null default clock_timestamp(),
    reviewed_at timestamptz,
    check (reporter <> reported)
);

alter table private.member_interests enable row level security;
alter table private.member_connections enable row level security;
alter table private.member_messages enable row level security;
alter table private.member_reports enable row level security;
revoke all on private.member_interests, private.member_connections, private.member_messages, private.member_reports
    from public, anon, authenticated;

create function private.members_blocked(a uuid, b uuid) returns boolean
language sql stable set search_path = '' as $$
    select exists (select 1 from public.member_blocks
        where (user_id = a and blocked_id = b) or (user_id = b and blocked_id = a))
$$;

create function private.lock_member_pair(a uuid, b uuid) returns void
language sql set search_path = '' as $$
    select pg_advisory_xact_lock(hashtextextended(least(a,b)::text || ':' || greatest(a,b)::text, 0))
$$;

create function private.end_member_connection(a uuid, b uuid) returns void
language plpgsql set search_path = '' as $$
begin
    update private.member_connections set ended_at = clock_timestamp()
    where first_member = least(a,b) and second_member = greatest(a,b) and ended_at is null;
    delete from private.member_interests
    where (sender = a and recipient = b) or (sender = b and recipient = a);
end
$$;

create function private.end_connection_on_block() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    perform private.lock_member_pair(new.user_id, new.blocked_id);
    perform private.end_member_connection(new.user_id, new.blocked_id);
    return new;
end
$$;
create trigger member_block_ends_connection before insert on public.member_blocks
for each row execute function private.end_connection_on_block();

create function private.member_activity_action(
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
            and not exists (select 1 from private.discover_profiles() as p where p->>'id' = target::text) then
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
            and not exists (select 1 from private.discover_profiles() as p where p->>'id' = target::text)) then
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

create function private.member_activity()
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
        'members', coalesce((select jsonb_agg(d.profile || jsonb_build_object(
            'id', d.user_id::text, 'distanceMiles', 0, 'isDemo', false,
            'city', case when (d.privacy->>'showCity')::boolean then d.profile->>'city' else 'Location private' end,
            'locationStatus', case when (d.privacy->>'showCity')::boolean then d.profile->>'locationStatus' else 'None' end,
            'destination', case when (d.privacy->>'showCity')::boolean then d.profile->>'destination' else 'Atlanta, GA' end
        )) from peers join public.discovery_profiles d on d.user_id = peer), '[]'::jsonb),
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

create function public.member_activity_action(
    action text, target uuid, prompt_id text default null, photo_id text default null,
    message_body text default null, message_id uuid default null, read_message_id uuid default null,
    report_reason text default null, report_details text default null
) returns jsonb language sql security invoker set search_path = '' as $$
    select private.member_activity_action(action, target, prompt_id, photo_id, message_body, message_id, read_message_id, report_reason, report_details)
$$;
create function public.member_activity() returns jsonb
language sql stable security invoker set search_path = '' as $$ select private.member_activity() $$;

revoke execute on function private.members_blocked(uuid,uuid), private.lock_member_pair(uuid,uuid),
    private.end_member_connection(uuid,uuid), private.end_connection_on_block() from public, anon, authenticated;
revoke execute on function public.member_activity(), private.member_activity(),
    public.member_activity_action(text,uuid,text,text,text,uuid,uuid,text,text),
    private.member_activity_action(text,uuid,text,text,text,uuid,uuid,text,text) from public, anon;
grant execute on function public.member_activity(), private.member_activity(),
    public.member_activity_action(text,uuid,text,text,text,uuid,uuid,text,text),
    private.member_activity_action(text,uuid,text,text,text,uuid,uuid,text,text) to authenticated;
