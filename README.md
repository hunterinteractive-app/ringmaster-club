# RingMaster Club

Flutter app for club memberships, member cards, communications, sanctions, and sweepstakes.

The signed-in home provides a personal member workspace. My clubs and Account settings stay inside its persistent navigation. Club cards include linked memberships, applications, sanction requests, and club management links. Account settings groups linked accounts, sign-in details, and policies, with the existing account editor and primary-account controls. Club management is offered only for clubs returned with staff access by `get_my_clubs`. Members without linked clubs can still use their personal card wallet and account settings. The Supabase API remains responsible for authorization.

## Development

CI uses Flutter 3.41.4. Install dependencies with `flutter pub get`, then run `flutter run -d chrome`. The public Supabase defaults are in `lib/config/supabase_config.dart`; deployment overrides can be supplied through `SUPABASE_URL` and `SUPABASE_ANON_KEY` Dart defines. Server credentials belong in Supabase secrets.

The app version in `pubspec.yaml` and the visible label in `lib/config/app_versions.dart` must be updated together for each member-facing release.

## Verification

```sh
flutter test --no-pub
flutter build web --release --no-pub --pwa-strategy=none
npx --yes deno@2.5.6 test --allow-env supabase/functions/_shared/club_billing_pricing_test.ts supabase/functions/stripe-club-billing-create-checkout/index_test.ts supabase/functions/read-sweepstakes-report/easy2show_awards_test.ts
```

Run the Flutter analyzer on changed Dart files before releasing. Billing checks use fixtures and mocked Stripe requests; they do not charge customers.

## Publishing

Pushing `main` runs `.github/workflows/deploy.yml`, which builds the app and publishes it to the `ringmaster-club` Cloudflare Pages project at https://club.ringmasterone.com/. Verify the successful Actions run and the deployed version label after pushing.

Supabase function source is kept in `supabase/functions/`. Backend deployments are separate from the web workflow. Preserve the deployed function's JWT settings, run its checks, and deploy only functions whose source differs from production.

The active annual billing formula and migration notes are in [docs/club-billing-pricing.md](docs/club-billing-pricing.md). Superseded, unapplied SQL is retained under `docs/superseded/` and must not be applied as a migration.

Generated previews, pricing exports, private roster workbooks, environment files, and local service caches are excluded from Git.
