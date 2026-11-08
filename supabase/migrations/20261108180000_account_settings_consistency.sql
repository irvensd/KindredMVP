create function private.blocked_member_summaries()
returns table(blocked_id uuid, display_name text)
language sql stable security definer set search_path = '' as $$
    select blocks.blocked_id, coalesce(d.profile->>'name', p.display_name)
    from public.member_blocks as blocks
    left join public.discovery_profiles as d on d.user_id = blocks.blocked_id
    left join public.member_profiles as p on p.user_id = blocks.blocked_id
    where blocks.user_id = (select auth.uid())
    order by coalesce(d.profile->>'name', p.display_name), blocks.blocked_id
$$;
create function public.blocked_member_summaries()
returns table(blocked_id uuid, display_name text)
language sql stable security invoker set search_path = '' as $$
    select * from private.blocked_member_summaries()
$$;
revoke execute on function private.blocked_member_summaries(), public.blocked_member_summaries() from public, anon;
grant execute on function private.blocked_member_summaries(), public.blocked_member_summaries() to authenticated;

create or replace function private.discover_profiles()
returns setof jsonb language sql stable security definer set search_path = '' as $$
    select private.shared_member_profile(candidate.user_id, candidate.profile, candidate.privacy, distance.miles)
    from public.discovery_profiles as viewer
    join public.discovery_profiles as candidate on candidate.user_id <> viewer.user_id
    cross join lateral (select private.discovery_distance(
        case when (viewer.preferences->>'useHomeCityForSearch') = 'true'
            then viewer.profile->>'city' else viewer.preferences->>'searchCity' end,
        candidate.profile->>'city'
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
