create schema if not exists private;

create table public.discovery_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    profile jsonb not null,
    preferences jsonb not null,
    privacy jsonb not null,
    updated_at timestamptz not null default now(),
    check (coalesce(jsonb_typeof(profile) = 'object' and
        char_length(btrim(profile->>'name')) between 1 and 60 and
        (profile->>'age')::int >= 18 and profile->>'gender' in ('Male', 'Female') and
        char_length(btrim(profile->>'city')) between 2 and 60 and
        jsonb_array_length(profile->'photos') between 1 and 6 and
        octet_length(profile::text) <= 8000000, false)),
    check (coalesce(jsonb_typeof(preferences->'dating'->'genders') = 'array' and
        jsonb_array_length(preferences->'dating'->'genders') between 1 and 2 and
        (preferences->'dating'->>'minimumAge')::int between 18 and 100 and
        (preferences->'dating'->>'maximumAge')::int between (preferences->'dating'->>'minimumAge')::int and 100 and
        (preferences->>'radiusMiles')::int between 5 and 250 and
        char_length(preferences->>'searchCity') between 2 and 60, false)),
    check (coalesce(jsonb_typeof(privacy->'showCity') = 'boolean' and
        jsonb_typeof(privacy->'discoveryPaused') = 'boolean', false))
);
alter table public.discovery_profiles enable row level security;
revoke all on public.discovery_profiles from anon, authenticated;
grant select, insert, update on public.discovery_profiles to authenticated;
create policy "Read own discovery profile" on public.discovery_profiles for select to authenticated
    using ((select auth.uid()) = user_id);
create policy "Create own discovery profile" on public.discovery_profiles for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy "Update own discovery profile" on public.discovery_profiles for update to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create function private.discovery_distance(origin text, destination text)
returns int language sql immutable set search_path = '' as $$
    with cities(name, lat, lon) as (
        values ('chicago, il', 41.88, -87.63), ('evanston, il', 42.04, -87.69),
            ('oak park, il', 41.89, -87.78), ('madison, wi', 43.07, -89.40),
            ('atlanta, ga', 33.75, -84.39), ('dallas, tx', 32.78, -96.80),
            ('new york, ny', 40.71, -74.01), ('loma linda, ca', 34.05, -117.26)
    )
    select case when lower(btrim(origin)) = lower(btrim(destination)) then 0
        else (
            select round(7917.6 * asin(sqrt(least(1.0, greatest(0.0,
                power(sin(radians((b.lat-a.lat)::double precision)/2), 2) +
                cos(radians(a.lat::double precision))*cos(radians(b.lat::double precision))*
                power(sin(radians((b.lon-a.lon)::double precision)/2), 2)
            )))))::int
            from cities a cross join cities b
            where a.name = lower(btrim(origin)) and b.name = lower(btrim(destination))
        ) end
$$;

create function private.discover_profiles()
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
        and distance.miles <= (viewer.preferences->>'radiusMiles')::int
    order by distance.miles, candidate.user_id
    limit 20
$$;
revoke all on function private.discover_profiles() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.discover_profiles() to authenticated;

create function public.discover_profiles()
returns setof jsonb language sql stable security invoker set search_path = '' as $$
    select * from private.discover_profiles()
$$;
revoke all on function public.discover_profiles() from public, anon;
grant execute on function public.discover_profiles() to authenticated;
