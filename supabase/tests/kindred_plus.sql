-- Run against a disposable Supabase database after applying the migrations.
begin;

insert into auth.users (id)
select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid from generate_series(1, 19) n;
insert into auth.sessions (id, user_id)
values ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000001');
insert into public.discovery_profiles (user_id, profile, preferences, privacy)
select id, jsonb_build_object('name', 'Member ' || right(id::text, 2), 'age', 30, 'city', 'Chicago, IL',
    'gender', case when right(id::text, 2) = '01' then 'Male' else 'Female' end,
    'photos', '[{"id":"test-photo"}]'::jsonb, 'prompts', '[{"id":"test-prompt","answer":"An answer"}]'::jsonb),
    '{"dating":{"genders":["Male","Female"],"minimumAge":18,"maximumAge":100},"radiusMiles":25,"useHomeCityForSearch":true,"searchCity":"Chicago, IL"}',
    '{"showCity":true,"discoveryPaused":false}'
from auth.users where id::text like '00000000-0000-4000-8000-%';

insert into private.member_interests (sender, recipient)
values ('00000000-0000-4000-8000-000000000018', '00000000-0000-4000-8000-000000000001'),
       ('00000000-0000-4000-8000-000000000019', '00000000-0000-4000-8000-000000000001');
insert into public.member_blocks (user_id, blocked_id)
values ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000019');
set local role authenticated;
select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000001","session_id":"00000000-0000-4000-8000-000000000101","role":"authenticated"}', true);

do $$
declare
    target uuid;
    details text;
begin
    assert public.liked_me() = '{"count":1}'::jsonb, 'Free response must contain only the count';
    assert not (public.member_activity()::text like '%00000000-0000-4000-8000-000000000018%'), 'Activity must not leak pending sender';
    assert public.likes_remaining_today() = '{"remaining":12,"resetsAtEpoch":null}'::jsonb;
    assert not has_table_privilege('authenticated', 'public.entitlements', 'INSERT');
    assert not has_function_privilege('authenticated',
        'public.apply_revenuecat_plus_event(uuid,text,text,text,timestamp with time zone,timestamp with time zone)', 'EXECUTE');
    for n in 2..13 loop
        target := ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
        perform public.member_activity_action('like', target);
    end loop;
    assert public.likes_remaining_today()->>'remaining' = '0';
    assert to_timestamp((public.likes_remaining_today()->>'resetsAtEpoch')::double precision)
        between now() + interval '24 hours' and clock_timestamp() + interval '24 hours';
    assert public.member_activity()->'likesResetAtEpoch' = public.likes_remaining_today()->'resetsAtEpoch';
    perform public.member_activity_action('like', '00000000-0000-4000-8000-000000000002');
    perform public.member_activity_action('remove_like', '00000000-0000-4000-8000-000000000002');
    begin
        perform public.member_activity_action('like', '00000000-0000-4000-8000-000000000014', 'test-prompt');
        raise exception 'The limit did not reject a new prompt like';
    exception when sqlstate 'PGRST' then
        get stacked diagnostics details = PG_EXCEPTION_DETAIL;
        assert sqlerrm::jsonb->>'code' = 'LIKE_LIMIT_REACHED';
        assert (sqlerrm::jsonb->>'details')::jsonb = public.likes_remaining_today() and details::jsonb = '{"status":429,"headers":{}}'::jsonb;
    end;
    begin
        perform public.member_activity_action('like', '00000000-0000-4000-8000-000000000014', null, 'test-photo');
        raise exception 'The limit did not reject a new photo like';
    exception when sqlstate 'PGRST' then
        assert sqlerrm::jsonb->>'code' = 'LIKE_LIMIT_REACHED';
    end;
    begin
        perform public.pass_incoming_like('00000000-0000-4000-8000-000000000018');
        raise exception 'Free member passed a premium card';
    exception when insufficient_privilege then null;
    end;
end $$;

reset role;
do $$
declare
    viewer uuid := '00000000-0000-4000-8000-000000000001';
begin
    perform public.apply_revenuecat_plus_event(viewer,'old','kindred_plus_monthly','INITIAL_PURCHASE',now(),now() + interval '1 month');
    perform public.apply_revenuecat_plus_event(viewer,'old','kindred_plus_monthly','CANCELLATION',now() + interval '2 seconds',now() + interval '1 month');
    assert private.is_plus(viewer), 'Voluntary cancellation retains paid time';
    perform public.apply_revenuecat_plus_event(viewer,'new','kindred_plus_3month','RENEWAL',now() + interval '3 seconds',now() + interval '3 months');
    perform public.apply_revenuecat_plus_event(viewer,'old','kindred_plus_monthly','EXPIRATION',now() + interval '4 seconds',now() + interval '1 month');
    assert private.is_plus(viewer), 'An old plan must not revoke the replacement';
    perform public.apply_revenuecat_plus_event(viewer,'old','kindred_plus_monthly','RENEWAL',now() + interval '1 second',now() + interval '5 months');
    assert (select expires_at from public.entitlements where user_id = viewer) = now() + interval '3 months';
    perform public.apply_revenuecat_plus_event('00000000-0000-4000-8000-000000000018',
        'other','kindred_plus_monthly','INITIAL_PURCHASE',now(),now() + interval '1 month');
end $$;

set local role authenticated;
do $$
begin
    assert public.likes_remaining_today() = '{"remaining":null,"resetsAtEpoch":null}'::jsonb;
    assert (select count(*) from public.entitlements) = 1, 'RLS must hide other members’ entitlements';
    assert not public.is_plus('00000000-0000-4000-8000-000000000018'), 'Helper must hide other members’ status';
    assert public.liked_me()->'profiles'->0->>'id' = '00000000-0000-4000-8000-000000000018';
    perform public.member_activity_action('like', '00000000-0000-4000-8000-000000000014', 'test-prompt');
    perform public.member_activity_action('like', '00000000-0000-4000-8000-000000000014', null, 'test-photo');
    perform public.pass_incoming_like('00000000-0000-4000-8000-000000000018');
    assert public.liked_me() = '{"count":0,"profiles":[]}'::jsonb;
end $$;

reset role;
select public.apply_revenuecat_plus_event('00000000-0000-4000-8000-000000000001',
    'new','kindred_plus_3month','EXPIRATION',now() + interval '5 seconds',now() + interval '3 months');
set local role authenticated;
do $$
begin
    assert public.likes_remaining_today()->>'remaining' = '0';
    assert public.liked_me() = '{"count":0}'::jsonb;
end $$;
reset role;
update private.free_like_usage set resets_at = now() - interval '1 second'
where user_id = '00000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$
begin
    assert public.likes_remaining_today() = '{"remaining":12,"resetsAtEpoch":null}'::jsonb;
    perform public.member_activity_action('like', '00000000-0000-4000-8000-000000000015');
    assert public.likes_remaining_today() = '{"remaining":11,"resetsAtEpoch":null}'::jsonb;
end $$;
rollback;
