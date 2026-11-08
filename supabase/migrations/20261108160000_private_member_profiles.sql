create table public.member_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null check (char_length(btrim(display_name)) between 1 and 60)
);

alter table public.member_profiles enable row level security;
revoke all on public.member_profiles from anon, authenticated;
grant select, insert, update on public.member_profiles to authenticated;

create policy "Members can read their own profile" on public.member_profiles
    for select to authenticated using ((select auth.uid()) = user_id);
create policy "Members can create their own profile" on public.member_profiles
    for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Members can update their own profile" on public.member_profiles
    for update to authenticated using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);
