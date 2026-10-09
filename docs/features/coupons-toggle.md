# Coupons on/off switch

An admin can turn the whole coupons feature off and back on with the backend App Setting `coupons.enabled` (backend ADR 119). While it's off, the backend gives out, lists and accepts claims for no coupons. The app hides every coupon screen and entry point.

## How the app knows

`AppConfigService.instance.couponsEnabled` is a `ValueNotifier<bool>` (`lib/core/services/app_config_service.dart`) fed by the public `GET /app/config` → `features.coupons`.

- It is fetched on launch (`MyApp.initState`) and again every time the app returns to the foreground (`AppLifecycleListener.onResume`).
- The last value is saved in SharedPreferences, so a cold start while coupons are off never flashes coupon UI.
- A failed fetch keeps the last known value. On a fresh install the default is on, and the backend still refuses coupons while they're off.

## What's hidden while off

| Surface | Behaviour |
| --- | --- |
| Profile → **Rewards & Vouchers** row (entry point to `RewardsScreen`) | Hidden; reappears when switched on (`ValueListenableBuilder`). |
| "You won a coupon!" sheet after a submission (`preview_screen.dart`) | Not shown. The backend grants none anyway. |
| Level-up sheet "Unlocked: …" perk line | Hidden. |
| Notification preferences → "Offers & Rewards" | Hidden. |

**Not affected:** AI ad campaign prize codes (`AiRewardsScreen`), which are a brand's paid prize. Coupons already won are kept by the backend and show again once switched on.

## Tests

- `test/core/services/app_config_service_test.dart`
- `test/features/account/screens/my_account_screen_coupons_off_test.dart`
- `test/shared/widgets/level_up_sheet_coupons_off_test.dart`
