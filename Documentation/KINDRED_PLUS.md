# Kindred Plus setup

## App configuration

Copy `Kindred.local.xcconfig.example` to `Kindred.local.xcconfig`. Fill in the Supabase project URL, Supabase publishable key, RevenueCat iOS public SDK key, and hosted Privacy Policy URL. Leave the Terms URL blank to use Apple's Standard EULA, or supply the HTTPS URL for your own terms. Use the example's `$(SLASH)` syntax for URLs.

Xcode includes the local file when present. Use the same build settings in CI. Store the RevenueCat webhook secret and Supabase service role key in Supabase only. The iOS app loads public client keys through its Info.plist.

Free accounts receive 12 likes. A 24-hour wait starts when the 12th free like is saved. The paywall shows when the allowance returns in the member’s local time. Likes sent while Plus is active do not consume the free allowance. New profile, photo, and prompt likes count individually. Removing a like does not restore the allowance.

The demo starts on the free plan. Open **You → Kindred Plus** or **Likes → See who likes you**, choose a plan, and confirm the simulated purchase. Use **Return to free demo** to try again. No StoreKit or backend requests are made.

## App Store Connect

1. Enable In-App Purchase for the app and complete the required agreements, tax, and banking setup.
2. Create one auto-renewable subscription group. Add `kindred_plus_monthly` for one month and `kindred_plus_3month` for three months at the same subscription level. Set pricing and localizations for both.
3. Add the privacy and terms links, subscription review screenshot, and review instructions. Test purchase, renewal, cancellation, expiration, and restore with Sandbox or TestFlight before submitting.
4. Connect App Store Server Notifications V2 to RevenueCat for both Sandbox and Production so renewal and cancellation updates reach Supabase promptly.

## RevenueCat

1. Add the iOS app with the same bundle ID as the Xcode build and connect the App Store credentials. Copy its public iOS SDK key into the local Xcode configuration.
2. Import both products, attach them to the `plus` entitlement, and add packages for both to the current offering.
3. Set restore behavior to **Keep with original App User ID**. Purchases are account-bound using the lowercase Supabase UUID and restore uses the original Kindred login. Use a different Apple sandbox tester for each Kindred account when testing purchases.
4. Configure a webhook for the iOS app at `https://<project-ref>.supabase.co/functions/v1/revenuecat-webhook`. Set its Authorization header to `Bearer <your-webhook-secret>` and include `INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `EXPIRATION`, and `BILLING_ISSUE`. Use separate webhook configurations and Supabase projects for Sandbox and Production.

## Supabase

1. Apply the migrations to your staging project, then to production when ready. The migration changes the existing activity endpoint so it returns counts in place of pending incoming-like identities. Coordinate that change with the Plus build if older clients are still in use.
2. Set `REVENUECAT_WEBHOOK_SECRET` to the value used in RevenueCat, without the `Bearer ` prefix. Set `REVENUECAT_APP_ID` to the RevenueCat app ID from the event payload. Set `REVENUECAT_WEBHOOK_ENVIRONMENT` to `SANDBOX` for staging or `PRODUCTION` for production. The function also uses Supabase's provisioned `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.
3. Deploy with `supabase functions deploy revenuecat-webhook --no-verify-jwt`. The function validates the webhook's Authorization header itself.
4. Make a sandbox purchase while signed in with a staging account. Verify the entitlement row, restore on a second device with that same account, and confirm that a free account receives a count without profile data. Verify a canceled subscription retains access until expiration. The app polls briefly after purchase and updates when Supabase receives the webhook.

Run the SQL checks against a disposable database with `psql <local-db-url> -v ON_ERROR_STOP=1 -f supabase/tests/kindred_plus.sql`. Run the webhook parser tests with `deno test supabase/functions/revenuecat-webhook`.
