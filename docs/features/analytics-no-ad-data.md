# Analytics without ad data

App Store 5.1.2(i) privacy label: "Firebase Analytics shares no data with ad networks or data brokers". The app has no ads and no ad SDKs, but `firebase_analytics` on its own collects the Android advertising ID and allows ad-personalization signals. Everything ad-related is switched off in the app:

| Where | Setting |
| --- | --- |
| `android/app/src/main/AndroidManifest.xml` | `google_analytics_adid_collection_enabled`, `google_analytics_default_allow_ad_storage`, `_ad_user_data` and `_ad_personalization_signals` are all `false`. The `AD_ID`, `ACCESS_ADSERVICES_AD_ID` and `ACCESS_ADSERVICES_ATTRIBUTION` permissions, which the measurement library merges in, are removed (`tools:node="remove"`). |
| `ios/Runner/Info.plist` | `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE` / `_AD_USER_DATA` / `_AD_PERSONALIZATION_SIGNALS` are `false`. |
| `ios/Podfile` | `$FirebaseAnalyticsWithoutAdIdSupport = true`: Firebase Analytics without the IDFA, so the AdSupport framework is not linked. |
| `AnalyticsService.applyNoAdsConsent()` (called at start-up) | Consent Mode: analytics storage granted; ad storage, ad user data and ad personalization denied. |

Still to confirm in the **Firebase / Google Analytics console** (can't be set from code):
- Google Signals is off;
- no Google Ads / AdMob / BigQuery-to-ads links;
- the "data sharing settings" for Google products and services are off.

Verify a build with the merged manifest (`build/app/intermediates/merged_manifest/.../AndroidManifest.xml`). It must contain no `AD_ID` or `ADSERVICES_` permission.
