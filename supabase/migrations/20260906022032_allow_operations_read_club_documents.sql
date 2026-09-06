-- RingMaster support users can review a private Sweepstakes report without
-- being added to each club's visible staff roster. Keep the exception
-- read-only and restrict it to objects explicitly referenced by a report
-- package; unrelated private club documents remain inaccessible.
drop policy if exists "RingMaster support can read sweepstakes report files"
  on storage.objects;

create policy "RingMaster support can read sweepstakes report files"
  on storage.objects for select to authenticated
  using (
    public.is_ringmaster_support_user()
    and exists (
      select 1
      from public.club_sweepstakes_report_packages package
      join public.clubs club on club.id = package.club_id
      where club.document_storage_bucket = storage.objects.bucket_id
        and (
          package.storage_path = storage.objects.name
          or exists (
            select 1
            from jsonb_array_elements(package.attachment_manifest) attachment
            where attachment ->> 'storage_path' = storage.objects.name
          )
        )
    )
  );
