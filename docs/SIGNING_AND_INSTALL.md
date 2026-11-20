# التوقيع والتثبيت على الآيفون — EGO FOCUS

## لماذا لا يوجد ملف IPA موقّع جاهز؟
لا يمكن تثبيت أي تطبيق على آيفون حقيقي إلا إذا كان موقّعاً بشهادة Apple صالحة **مرتبطة بحسابك أنت** وملف تعريف (Provisioning Profile) يسمح بجهازك. هذه الشهادة لا يمكن إنشاؤها إلا من حساب Apple Developer الخاص بك، ولم تكن متاحة أثناء العمل. لذلك:

- ✅ تم بناء التطبيق فعلياً بـ Xcode على macOS (GitHub Actions) واختباره على محاكي iPhone.
- ✅ تم إنشاء أرشيف Release للأجهزة الحقيقية، **غير موقّع** — الملف `EGOFocus-UNSIGNED-not-installable.ipa` موجود للتحقق فقط و**لا يمكن تثبيته على الآيفون**.
- ⏳ النسخة الموقّعة تحتاج بيانات حسابك كما هو موضح أدناه، وخط البناء جاهز لإنتاجها تلقائياً.

## الخيار 1 (الأسهل بدون Mac): TestFlight
**المتطلبات:** اشتراك Apple Developer Program (99 دولاراً سنوياً).

1. سجّل في https://developer.apple.com/programs/ وانتظر التفعيل.
2. في https://developer.apple.com/account/resources/identifiers أنشئ App ID بالمعرف `com.egofocus.tasks`.
   - إذا كان المعرف محجوزاً لدى شخص آخر، استخدم معرفاً آخر (مثل `com.<اسمك>.egofocus`) وغيّر `PRODUCT_BUNDLE_IDENTIFIER` في المشروع.
3. في https://appstoreconnect.apple.com ← Apps ← (+) New App: اختر المعرف السابق، الاسم EGO FOCUS، اللغة العربية.
4. في App Store Connect ← Users and Access ← Integrations ← App Store Connect API ← أنشئ مفتاحاً بصلاحية **App Manager** ونزّل ملف `.p8` (يُنزَّل مرة واحدة فقط). سجّل **Key ID** و**Issuer ID**.
5. اعرف **Team ID** من https://developer.apple.com/account (Membership details).
6. في مستودع GitHub ← Settings ← Secrets and variables ← Actions أضف:
   | الاسم | القيمة |
   |---|---|
   | `ASC_KEY_ID` | Key ID |
   | `ASC_ISSUER_ID` | Issuer ID |
   | `ASC_KEY_P8_BASE64` | محتوى ملف ‎.p8 بترميز Base64 |
   | `APPLE_TEAM_ID` | Team ID |
   لترميز الملف: على Mac/Linux `base64 -i AuthKey_XXXX.p8 | pbcopy`، أو على Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8"))`.
7. في GitHub ← Actions ← «iOS build, test & package» ← Run workflow ← اختر `testflight`.
8. بعد 10–30 دقيقة يظهر البناء في App Store Connect ← TestFlight. أضف نفسك كمختبر داخلي، ثم ثبّت تطبيق **TestFlight** على الآيفون وثبّت EGO FOCUS منه.

## الخيار 2: IPA موقّع للتثبيت المباشر (Ad Hoc)
نفس متطلبات الخيار 1، بالإضافة إلى تسجيل جهازك:
1. اعرف UDID الآيفون (من Finder على Mac، أو من iTunes على Windows، أو بخدمات موثوقة مثل udid.tech).
2. أضفه في https://developer.apple.com/account/resources/devices.
3. شغّل الـ workflow مع الخيار `adhoc`؛ يُنتج ملف `.ipa` موقّعاً في Artifacts باسم `egofocus-signed-adhoc`.
4. ثبّته عبر Apple Configurator (Mac) أو Xcode ← Devices، أو عبر Finder بالسحب إلى الجهاز.

## الخيار 3: لديك Mac — بدون اشتراك مدفوع (للاستخدام الشخصي)
1. افتح `EGOFocus.xcodeproj` بـ Xcode 16 أو أحدث.
2. Target `EGOFocus` ← Signing & Capabilities ← Team: اختر Apple ID الشخصي (Personal Team).
3. غيّر Bundle Identifier إلى معرف فريد (مثل `com.<اسمك>.egofocus`).
4. وصّل الآيفون، فعّل **Developer Mode** (الإعدادات ← الخصوصية والأمان)، ثم اضغط Run.
5. في الآيفون: الإعدادات ← عام ← VPN وإدارة الأجهزة ← ثق بالمطوّر.
- ملاحظة: التوقيع المجاني صالح **7 أيام** فقط ثم يجب إعادة التثبيت من Xcode.

## ما الذي لا يصح
- لا يمكن تثبيت IPA غير موقّع على آيفون عادي.
- لا تستخدم شهادات «مشتركة» أو مواقع توقيع مجهولة: تخالف شروط Apple وتُلغى غالباً خلال أيام، وقد تعرّض جهازك للخطر.

## تشغيل المشروع على Mac (للمطورين)
```bash
open EGOFocus.xcodeproj          # Scheme: EGOFocus — iPhone 16 Simulator — Run
xcodebuild test -project EGOFocus.xcodeproj -scheme EGOFocus \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```
