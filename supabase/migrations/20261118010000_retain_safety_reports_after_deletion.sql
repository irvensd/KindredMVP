-- Preserve the staff-only report and review outcome while removing deleted
-- account references and profile data. A report can outlive either participant.
alter table private.member_reports
    alter column reporter drop not null,
    alter column reported drop not null,
    drop constraint member_reports_reporter_fkey,
    drop constraint member_reports_reported_fkey,
    add constraint member_reports_reporter_fkey foreign key (reporter)
        references auth.users(id) on delete set null,
    add constraint member_reports_reported_fkey foreign key (reported)
        references auth.users(id) on delete set null;

-- A deleted participant is NULL. Keep excluding any participant who still
-- has an account, including when the other participant has been deleted.
create or replace function private.safety_report_queue(include_reviewed boolean, page_offset int default 0)
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
    where (r.reviewed_at is not null) = include_reviewed and viewer is distinct from r.reporter and viewer is distinct from r.reported
    order by case when include_reviewed then r.reviewed_at end desc,
        case when not include_reviewed then r.created_at end, r.id
    limit 30 offset greatest(0, coalesce(page_offset, 0));
end
$$;

create or replace function private.review_safety_report(report_id uuid, action text, note text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
    viewer uuid := auth.uid();
    report private.member_reports%rowtype;
begin
    if not private.is_safety_reviewer() then
        raise exception 'Safety review access is required' using errcode = '42501';
    end if;

    select * into report from private.member_reports
    where id = report_id and viewer is distinct from reporter and viewer is distinct from reported for update;
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
