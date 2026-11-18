-- Run after applying all migrations to a disposable Supabase database.
begin;

insert into auth.users(id)
select ('00000000-0000-4000-8000-00000000020' || n)::uuid
from generate_series(1, 4) n;
insert into auth.sessions(id, user_id, created_at) values
    ('00000000-0000-4000-8000-000000000301', '00000000-0000-4000-8000-000000000201', clock_timestamp()),
    ('00000000-0000-4000-8000-000000000302', '00000000-0000-4000-8000-000000000202', clock_timestamp()),
    ('00000000-0000-4000-8000-000000000303', '00000000-0000-4000-8000-000000000203', clock_timestamp()),
    ('00000000-0000-4000-8000-000000000304', '00000000-0000-4000-8000-000000000204', clock_timestamp());
insert into private.safety_reviewers(user_id) values
    ('00000000-0000-4000-8000-000000000201'),
    ('00000000-0000-4000-8000-000000000204');
insert into public.member_profiles(user_id, display_name)
values ('00000000-0000-4000-8000-000000000203', 'Deleted fixture');
insert into private.member_reports(id, reporter, reported, reason, details) values
    ('00000000-0000-4000-8000-000000000401',
     '00000000-0000-4000-8000-000000000204', '00000000-0000-4000-8000-000000000203',
     'Harassment', 'Open test report'),
    ('00000000-0000-4000-8000-000000000402',
     '00000000-0000-4000-8000-000000000203', '00000000-0000-4000-8000-000000000202',
     'Other', 'Report to resolve before deletion');

set local role authenticated;
select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000202","session_id":"00000000-0000-4000-8000-000000000302","role":"authenticated"}', true);
do $$
begin
    assert not public.is_safety_reviewer();
    begin
        perform public.safety_report_queue(false);
        raise exception 'Ordinary member accessed the reviewer queue';
    exception when insufficient_privilege then null;
    end;
    begin
        perform public.review_safety_report('00000000-0000-4000-8000-000000000401', 'claim');
        raise exception 'Ordinary member claimed a report';
    exception when insufficient_privilege then null;
    end;
end $$;

select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000201","session_id":"00000000-0000-4000-8000-000000000301","role":"authenticated"}', true);
select public.review_safety_report('00000000-0000-4000-8000-000000000402', 'claim');
select public.review_safety_report('00000000-0000-4000-8000-000000000402', 'resolve', 'Reviewed by staff');

select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000203","session_id":"00000000-0000-4000-8000-000000000303","role":"authenticated"}', true);
select public.delete_my_account();

select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000204","session_id":"00000000-0000-4000-8000-000000000304","role":"authenticated"}', true);
do $$
begin
    assert not exists (select 1 from public.safety_report_queue(false)
        where id = '00000000-0000-4000-8000-000000000401');
    begin
        perform public.review_safety_report('00000000-0000-4000-8000-000000000401', 'claim');
        raise exception 'Reviewer claimed their own report after subject deletion';
    exception when sqlstate 'PT409' then null;
    end;
end $$;
select public.delete_my_account();

select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000201","session_id":"00000000-0000-4000-8000-000000000301","role":"authenticated"}', true);
do $$
begin
    assert exists (select 1 from public.safety_report_queue(false)
        where id = '00000000-0000-4000-8000-000000000401'
            and reported_id is null and reported_name is null and details = 'Open test report');
    assert exists (select 1 from public.safety_report_queue(true)
        where id = '00000000-0000-4000-8000-000000000402'
            and reported_id = '00000000-0000-4000-8000-000000000202'
            and resolution = 'Reviewed by staff');
    perform public.review_safety_report('00000000-0000-4000-8000-000000000401', 'claim');
    perform public.review_safety_report('00000000-0000-4000-8000-000000000401', 'resolve', 'Closed after deletion');
    assert exists (select 1 from public.safety_report_queue(true)
        where id = '00000000-0000-4000-8000-000000000401' and resolution = 'Closed after deletion');
end $$;

reset role;
do $$
begin
    assert not exists (select 1 from public.member_profiles
        where user_id = '00000000-0000-4000-8000-000000000203');
    assert exists (select 1 from private.member_reports
        where id = '00000000-0000-4000-8000-000000000401' and reporter is null and reported is null);
    assert exists (select 1 from private.member_reports
        where id = '00000000-0000-4000-8000-000000000402' and reporter is null);
end $$;
rollback;
