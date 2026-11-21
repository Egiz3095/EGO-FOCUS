# خادم إشعارات EGO FOCUS (Cloudflare Worker)
يرسل تذكيرات نسخة الويب والتطبيق مغلق عبر Web Push (VAPID + aes128gcm).
- يُنشر تلقائياً بواسطة `.github/workflows/push-server.yml` بعد إضافة السرّين `CLOUDFLARE_API_TOKEN` و`CLOUDFLARE_ACCOUNT_ID`.
- قاعدة D1 باسم `egofocus`: الأجهزة، والتذكيرات القادمة فقط (تُحذف بعد الإرسال)، ومفاتيح VAPID (تُولَّد تلقائياً مرة واحدة).
- يعمل كل دقيقة (Cron) على الخطة المجانية.

اختبار محلي (Node 22): انسخ `worker.js` إلى `tests/worker.mjs` ثم
`cd tests && npm i http_ece@1.2.0 && node --experimental-sqlite push.test.mjs`
