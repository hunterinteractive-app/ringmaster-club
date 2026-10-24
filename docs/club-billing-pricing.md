# Club annual pricing

Pricing version: `base_plus_usage_v1`.

- Membership Plus: $100/year plus $1 per covered active person.
- Optional Sanctions & Sweepstakes: $50/year plus $0.50 per sanction number.
- Each family member counts separately. The primary member counts once; additional linked exhibitors and named manual family members are included. Older imported `additional_people` records are supported.
- Memberships must be active/expiring and within their current term. Pending, inactive, future, and expired memberships are excluded.
- Sanctions are individually counted from approved requests reviewed during the preceding 12 months. Blank numbers and explicit renewal exclusions are omitted.
- The optional suite costs $50 even with zero sanctions, and is charged only when selected. Previous sanction activity never automatically selects it.

The server RPC `get_club_renewal_preview` checks `payments.manage`, counts people and sanctions, and returns both components. Client-supplied amounts and quantities are ignored.

Stripe uses annual licensed quantities and these lookup keys:

| Component | Lookup key | Unit amount in cents |
| --- | --- | ---: |
| Membership base | `rmc_membership_base_annual_v1` | 10000 |
| Active person | `rmc_member_annual_v1` | 100 |
| Sanctions base | `rmc_sanctions_base_annual_v1` | 5000 |
| Sanction number | `rmc_sanction_annual_v1` | 50 |

Amounts, USD currency, and annual licensed recurrence are validated before checkout. Both base fees are separate from usage, so zero quantities cannot remove an annual base fee. Existing catalog tax-inclusive behavior is retained; automatic tax collection is not newly enabled.

New subscriptions are fulfilled by the signed billing webhook after payment. `invoice.upcoming` refreshes quantities before annual renewal. Reviewing an existing Membership Plus subscription updates its next invoice without immediate proration or creating a second subscription. Unrelated storage/email items are retained.

Legacy subscriptions are not silently migrated or repriced. They require an explicit support-assisted switch at renewal; checkout refuses to create a duplicate subscription.

The existing `STRIPE_SECRET_KEY` must address the same account/mode as the catalog. `STRIPE_WEBHOOK_SECRET_CLUB_BILLING` authenticates the Club webhook. The public GET readiness response reports only whether the catalog resolves; it never returns credentials or club data.

## Verification

```sh
npx --yes deno@2.5.6 test --allow-env supabase/functions/_shared/club_billing_pricing_test.ts supabase/functions/stripe-club-billing-create-checkout/index_test.ts
flutter analyze lib/screens/clubs/admin/club_billing_screen.dart
flutter test --no-pub
flutter build web --release --no-pub --pwa-strategy=none
```

The new migrations are `20261024020728_club_base_plus_usage_pricing.sql` and `20261024020829_club_billing_preview_support.sql`. The older local `align_club_pricing_with_flyer` SQL contains superseded tiers and was not applied to production. It is retained in `docs/superseded/20260903153607_align_club_pricing_with_flyer.sql`, outside the runnable migration folder. Production received the new formula plus a schema-only support migration.
