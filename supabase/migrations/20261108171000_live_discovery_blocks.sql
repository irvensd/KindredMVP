create table public.member_blocks (
    user_id uuid not null references auth.users(id) on delete cascade,
    blocked_id uuid not null references auth.users(id) on delete cascade,
    primary key (user_id, blocked_id),
    check (user_id <> blocked_id)
);
alter table public.member_blocks enable row level security;
revoke all on public.member_blocks from anon, authenticated;
grant select, insert, delete on public.member_blocks to authenticated;
create policy "Read own blocks" on public.member_blocks for select to authenticated
    using ((select auth.uid()) = user_id);
create policy "Create own blocks" on public.member_blocks for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy "Delete own blocks" on public.member_blocks for delete to authenticated
    using ((select auth.uid()) = user_id);

create or replace function private.discover_profiles()
returns setof jsonb language sql stable security definer set search_path = '' as $$
    select jsonb_build_object(
        'id', candidate.user_id::text,
        'name', candidate.profile->'name', 'age', candidate.profile->'age', 'gender', candidate.profile->'gender',
        'city', case when (candidate.privacy->>'showCity')::boolean then candidate.profile->>'city' else 'Location private' end,
        'distanceMiles', distance.miles, 'occupation', candidate.profile->'occupation', 'bio', candidate.profile->'bio',
        'intention', candidate.profile->'intention', 'faith', candidate.profile->'faith', 'interests', candidate.profile->'interests',
        'prompts', candidate.profile->'prompts', 'photos', candidate.profile->'photos', 'isDemo', false,
        'locationStatus', case when (candidate.privacy->>'showCity')::boolean then candidate.profile->>'locationStatus' else 'None' end,
        'destination', case when (candidate.privacy->>'showCity')::boolean then candidate.profile->>'destination' else 'Atlanta, GA' end,
        'distanceOpenness', candidate.profile->'distanceOpenness', 'openToRelocating', candidate.profile->'openToRelocating'
    )
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
        and distance.miles <= (viewer.preferences->>'radiusMiles')::int
    order by distance.miles, candidate.user_id
    limit 20
$$;
