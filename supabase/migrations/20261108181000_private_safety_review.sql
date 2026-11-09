create table private.safety_reviewers (
    user_id uuid primary key references auth.users(id) on delete cascade,
    granted_at timestamptz not null default clock_timestamp()
);
alter table private.safety_reviewers enable row level security;
revoke all on private.safety_reviewers from public, anon, authenticated;

alter table private.member_reports
    add column assigned_to uuid references private.safety_reviewers(user_id) on delete set null,
    add column reviewed_by uuid references auth.users(id) on delete set null,
    add column resolution text check (char_length(resolution) <= 500);
create index member_reports_queue_idx on private.member_reports (created_at, id) where reviewed_at is null;
create index member_reports_reviewed_idx on private.member_reports (reviewed_at desc, id) where reviewed_at is not null;

create function private.has_active_session() returns boolean
language sql stable security definer set search_path = '' as $$
    select exists (
        select 1 from auth.sessions s
        where s.id = (auth.jwt()->>'session_id')::uuid and s.user_id = (select auth.uid())
    )
$$;

create function private.is_safety_reviewer() returns boolean
language sql stable security definer set search_path = '' as $$
    select private.has_active_session()
        and exists (select 1 from private.safety_reviewers where user_id = (select auth.uid()))
$$;

create function private.safety_report_queue(include_reviewed boolean, page_offset int default 0)
returns table(id uuid, reason text, details text, created_at timestamptz, reported_id uuid,
    reported_name text, assigned_to_me boolean, assigned boolean, reviewed_at timestamptz, resolution text)
language plpgsql stable security definer set search_path = '' as $$
declare viewer uuid := auth.uid();
begin
    if not private.is_safety_reviewer() then
        raise exception 'Safety review access is required' using errcode = '42501';
    end if;

    return query
    select r.id, r.reason, r.details, r.created_at, r.reported, coalesce(d.profile->>'name', p.display_name),
        coalesce(r.assigned_to = viewer, false), r.assigned_to is not null, r.reviewed_at, r.resolution
    from private.member_reports r
    left join public.discovery_profiles d on d.user_id = r.reported
    left join public.member_profiles p on p.user_id = r.reported
    where (r.reviewed_at is not null) = include_reviewed and viewer not in (r.reporter, r.reported)
    order by case when include_reviewed then r.reviewed_at end desc,
        case when not include_reviewed then r.created_at end, r.id
    limit 30 offset greatest(0, coalesce(page_offset, 0));
end
$$;

create function private.review_safety_report(report_id uuid, action text, note text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
    viewer uuid := auth.uid();
    report private.member_reports%rowtype;
begin
    if not private.is_safety_reviewer() then
        raise exception 'Safety review access is required' using errcode = '42501';
    end if;

    select * into report from private.member_reports
    where id = report_id and viewer not in (reporter, reported) for update;
    if not found or report.reviewed_at is not null then
        raise exception 'Report unavailable' using errcode = 'PT409';
    end if;

    if action = 'claim' and (report.assigned_to is null or report.assigned_to = viewer) then
        update private.member_reports set assigned_to = viewer where id = report_id;
    elsif action = 'release' and report.assigned_to = viewer then
        update private.member_reports set assigned_to = null where id = report_id;
    elsif action = 'resolve' and report.assigned_to = viewer
        and char_length(btrim(note)) between 1 and 500 then
        update private.member_reports
        set reviewed_at = clock_timestamp(), reviewed_by = viewer, resolution = btrim(note)
        where id = report_id;
    else
        raise exception 'Report assignment changed or a resolution note is missing' using errcode = 'PT409';
    end if;
end
$$;

create function public.is_safety_reviewer() returns boolean
language sql stable security invoker set search_path = '' as $$ select private.is_safety_reviewer() $$;

create function public.safety_report_queue(include_reviewed boolean, page_offset int default 0)
returns table(id uuid, reason text, details text, created_at timestamptz, reported_id uuid,
    reported_name text, assigned_to_me boolean, assigned boolean, reviewed_at timestamptz, resolution text)
language sql stable security invoker set search_path = '' as $$
    select * from private.safety_report_queue(include_reviewed, page_offset)
$$;

create function public.review_safety_report(report_id uuid, action text, note text default null) returns void
language sql security invoker set search_path = '' as $$
    select private.review_safety_report(report_id, action, note)
$$;

create or replace function public.member_activity() returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
begin
    if not private.has_active_session() then
        raise exception 'Sign-in session ended' using errcode = 'PT401';
    end if;
    return private.member_activity();
end
$$;

create or replace function public.discover_profiles() returns setof jsonb
language plpgsql stable security invoker set search_path = '' as $$
begin
    if not private.has_active_session() then
        raise exception 'Sign-in session ended' using errcode = 'PT401';
    end if;
    return query select * from private.discover_profiles();
end
$$;

revoke execute on function private.has_active_session(),
    private.is_safety_reviewer(), public.is_safety_reviewer(),
    private.safety_report_queue(boolean,int), public.safety_report_queue(boolean,int),
    private.review_safety_report(uuid,text,text), public.review_safety_report(uuid,text,text)
    from public, anon;
grant execute on function private.has_active_session(),
    private.is_safety_reviewer(), public.is_safety_reviewer(),
    private.safety_report_queue(boolean,int), public.safety_report_queue(boolean,int),
    private.review_safety_report(uuid,text,text), public.review_safety_report(uuid,text,text)
    to authenticated;
