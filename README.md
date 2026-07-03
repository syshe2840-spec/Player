# Vezoo — پلیر ویدیو هوشمند اندروید

یک پلیر ویدیوی متن‌باز برای اندروید با تمرکز روی زیرنویس، هوش مصنوعی آفلاین و رمزگذاری محتوا.

---

## ✨ ویژگی‌های اصلی

### پلیر
- پخش تمام فرمت‌های رایج (MKV, MP4, AVI و...) با MediaKit/libmpv
- کنترل روشنایی و صدا با کشیدن انگشت
- fast-seek با نگه‌داشتن چپ/راست + تغییر سرعت + قفل seek
- تغییر سرعت پخش، حالت شب، تکرار A-B
- Picture-in-Picture (PiP) + notification کنترل پخش
- Playlist، پوشه‌های ذخیره‌شده

### زیرنویس
- پشتیبانی از SRT, ASS, VTT + زیرنویس Embedded (سافت ساب)
- دو زیرنویس همزمان (Sub1 و Sub2) با تنظیمات کاملاً مستقل
- تنظیم فونت، اندازه، رنگ، سایه، پس‌زمینه، چینش، دیلی
- Drag جداگانه برای جابجایی هر زیرنویس
- ویرایشگر دستی SRT داخل اپ

### زیرنویس AI (آفلاین)
- موتور V1: whisper_ggml_plus (پایدار)
- موتور V2: whisper.cpp بومی با NDK (سریع‌تر)
- ۱۱ مدل quantized از tiny تا large-v3-turbo
- تشخیص خودکار زبان، ترجمه همزمان
- زیرنویس زنده: chunk به chunk در حین پخش
- همگام‌سازی اختیاری ترجمه آنلاین با زیرنویس زنده
- صف دسته‌ای، تاریخچه، بهبود متن فارسی

### زیرنویس آنلاین (OpenSubtitles)
- جستجو با نام — پوستر + سال + نوع (فیلم/سریال)
- انتخاب فصل/قسمت برای سریال
- اعمال روی Sub1، Sub2 یا هر دو
- ۵ دانلود رایگان در روز (بدون نیاز به اکانت)

### ترجمه زیرنویس (Cloudflare AI)
- ترجمه SRT به ۲۳ زبان با Llama 3.1
- پردازش در پس‌زمینه — کاربر فیلم می‌بینه
- بروزرسانی زنده هر ۵۰ خط
- اعمال روی Sub1، Sub2 یا هر دو
- محدودیت: حداکثر ۳۰۰۰ خط (پلن رایگان)

### فرمت VEZ (رمزگذاری ویدیو)
- فرمت `.vez` با AES-256-GCM + HKDF-SHA256
- کلید master از ترکیب App Half + Server Half (Cloudflare)
- اسکریپت `encrypt_vez.py` برای رمزگذاری

---

## معماری سیستم

```
اپ اندروید (Flutter + Kotlin + whisper.cpp NDK)
              │
              │ HTTPS
              ▼
    Cloudflare Workers
    /config | /translate-srt | /master-half | ...
              │
              ▼
    Cloudflare D1 (SQLite)
    config | sponsors | announcements | stats
```

---

## ساختار فایل‌ها

```
lib/
├── main.dart
├── store.dart                   # state + subtitle parsers
├── browser.dart                 # مرور فایل‌ها
├── player.dart                  # پلیر اصلی
├── settings.dart                # تنظیمات (4 تب)
├── whisper_service.dart         # AI زیرنویس (V1+V2+live)
├── ai_subtitle_sheet.dart
├── ai_models_screen.dart
├── ai_history_screen.dart
├── ai_batch_queue_screen.dart
├── live_sub_sheet.dart          # تنظیمات زیرنویس زنده
├── live_translation_sync.dart   # همگام‌سازی ترجمه
├── srt_editor_screen.dart
├── srt_translation_service.dart # ترجمه با Cloudflare AI
├── srt_translate_sheet.dart
├── opensubtitles_service.dart
├── opensubtitles_search_sheet.dart
├── api_service.dart
└── vez_service.dart

android_files/
├── MainActivity.kt              # PiP + Notification + JNI
├── WhisperV2Bridge.kt
├── LiveSubService.kt            # Foreground Service
└── cpp/
    ├── vezoo.h/c/jni.c          # AES-256-GCM Pure C
    └── whisper_v2/              # whisper.cpp v1.9.1

cloudflare/
├── worker.js
├── schema.sql
└── wrangler.toml

vezoo_tools/
└── encrypt_vez.py
```

---

## راه‌اندازی Cloudflare

### ۱. ساخت Worker

```bash
npm install -g wrangler
wrangler login
cd cloudflare
wrangler deploy
```

### ۲. ساخت D1 Database

در Cloudflare Dashboard → D1 → Create database به نام `player-db`

در فایل `wrangler.toml` مقدار `database_id` را با ID دیتابیست عوض کن.

Schema را اجرا کن:
```bash
wrangler d1 execute player-db --file=schema.sql
```

یا در D1 Console این query ها را اجرا کن:
```sql
INSERT OR REPLACE INTO config VALUES ('server_half','YOUR_SERVER_HALF_BASE64');
INSERT OR REPLACE INTO config VALUES ('opensubtitles_api_key','YOUR_OPENSUBTITLES_KEY');
INSERT OR REPLACE INTO config VALUES ('latest_version','1.0.0');
INSERT OR REPLACE INTO config VALUES ('update_url','https://github.com/YOUR/REPO/releases');
```

### ۳. فعال‌سازی Workers AI (برای ترجمه)

Dashboard → Workers & Pages → پروژه → Settings → Bindings:
- Add binding → نوع: **Workers AI**
- Variable name: `AI` (حتماً بزرگ)
- Save → Redeploy

### ۴. Endpoints موجود

| Endpoint | متد | کاربرد |
|----------|-----|---------|
| `/config` | GET | تنظیمات و نسخه اپ |
| `/announce` | GET | اعلان‌های فعال |
| `/sponsors` | GET | لیست اسپانسرها |
| `/master-half` | GET | Server Half برای VEZ |
| `/opensubtitles-key` | GET | کلید API زیرنویس آنلاین |
| `/translate-srt` | POST | ترجمه زیرنویس با AI |
| `/stats` | POST | آمار استفاده |

---

## راه‌اندازی اپ

### پیش‌نیاز
- Flutter SDK (stable)
- Android NDK 28
- Java 17

### تنظیم آدرس Worker

در `lib/api_service.dart`:
```dart
static const _base = 'https://YOUR-WORKER.workers.dev';
```

### Build با GitHub Actions

Push به branch `main` → APK به‌طور خودکار ساخته می‌شود.

### Build دستی
```bash
flutter pub get
flutter build apk --release
```

---

## رمزگذاری VEZ

```bash
pip install pycryptodome
python vezoo_tools/encrypt_vez.py input.mp4 output.vez
```

**App Half** در `android_files/MainActivity.kt` هاردکد شده.
**Server Half** در Cloudflare D1 ذخیره است.

---

## محدودیت پلن رایگان

| سرویس | محدودیت |
|--------|---------|
| Cloudflare Workers | 100,000 request/روز |
| Cloudflare Workers AI | ~17 ترجمه فیلم/روز |
| OpenSubtitles | 5 دانلود/روز |

---

## تکنولوژی‌ها

| بخش | تکنولوژی |
|-----|----------|
| UI | Flutter + Material 3 |
| ویدیو | MediaKit (libmpv) |
| AI زیرنویس | whisper_ggml_plus + whisper.cpp NDK |
| رمزگذاری | AES-256-GCM + HKDF-SHA256 (Pure C) |
| Backend | Cloudflare Workers + D1 |
| ترجمه | Llama 3.1 (Cloudflare AI) |
| زیرنویس آنلاین | OpenSubtitles REST API |

---

## نکته‌های مهم توسعه

- هرگز از `setMethodCallHandler` روی channel مشترک استفاده نکن — channel را کور می‌کند. به‌جایش `EventChannel` جداگانه بساز
- برای پردازش صوت از `ShortArray` primitive استفاده کن نه `MutableList<Short>` (boxing کند است)
- `LiveSubService` Foreground Service است — برای background پردازش ضروری است
- `FOREGROUND_SERVICE` permission در Manifest باید تعریف شده باشد



---
ک---
---

## ❤️ حمایت از توسعه

اگر این پروژه برای شما مفید بوده است، با حمایت مالی از ادامه توسعه آن پشتیبانی کنید.

<p align="center">
  <a href="https://github.com/RezaArbabBot/Donate">
    <img src="https://img.shields.io/badge/☕_حمایت_مالی-orange?style=for-the-badge">
  </a>
  &nbsp;
  <a href="https://t.me/ForYouTillEnd">
    <img src="https://img.shields.io/badge/📢_کانال_توسعه‌دهنده-26A5E4?style=for-the-badge&logo=telegram&logoColor=white">
  </a>
  &nbsp;
  <a href="https://t.me/VezooTM">
    <img src="https://img.shields.io/badge/🎬_کانال_Vezoo-26A5E4?style=for-the-badge&logo=telegram&logoColor=white">
  </a>
</p>

---

## 🔗 لینک‌ها

- **کانال توسعه‌دهنده:** https://t.me/ForYouTillEnd
- **کانال Vezoo:** https://t.me/VezooTM
- **حمایت مالی:** https://github.com/RezaArbabBot/Donate

---

<p align="center">
  ساخته شده با ❤️ توسط RezaArbabBot
</p>
