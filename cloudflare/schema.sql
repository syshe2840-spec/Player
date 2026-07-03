-- اسپانسرها
CREATE TABLE IF NOT EXISTS sponsors (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  link TEXT DEFAULT '',
  gender TEXT DEFAULT 'male',
  avatar_url TEXT DEFAULT '',
  active INTEGER DEFAULT 1,
  sort_order INTEGER DEFAULT 0
);

-- تنظیمات اپ
CREATE TABLE IF NOT EXISTS config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT OR IGNORE INTO config VALUES ('app_version','1.0.0');
INSERT OR IGNORE INTO config VALUES ('force_update','0');
INSERT OR IGNORE INTO config VALUES ('download_url','');
INSERT OR IGNORE INTO config VALUES ('update_message','نسخه جدید منتشر شد!');
INSERT OR IGNORE INTO config VALUES ('update_title','بروزرسانی');

-- اعلان‌ها / تبلیغ کانال
CREATE TABLE IF NOT EXISTS announcements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT DEFAULT '',
  message TEXT DEFAULT '',
  image_url TEXT DEFAULT '',
  link TEXT DEFAULT '',
  link_text TEXT DEFAULT 'مشاهده',
  cancellable INTEGER DEFAULT 1,
  active INTEGER DEFAULT 1,
  max_shows INTEGER DEFAULT 1,  -- چند بار نشون داده بشه (0=بی‌نهایت)
  expires_at TEXT
);

-- آمار
CREATE TABLE IF NOT EXISTS stats (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL,
  app_version TEXT DEFAULT '',
  android_version TEXT DEFAULT '',
  event TEXT DEFAULT 'open',
  value TEXT DEFAULT '',
  created_at TEXT DEFAULT (datetime('now'))
);

-- نمونه اسپانسر (حذف بعد از تست)
INSERT OR IGNORE INTO sponsors (name,description,link,gender,avatar_url,active,sort_order)
VALUES ('تیم ترجمه کالرساب','ترجمه اختصاصی سریال‌های کره‌ای','https://t.me/kalrsab','male','',1,1);

-- لینک‌های اپ (از سرور)
INSERT OR IGNORE INTO config VALUES ('telegram_channel','https://t.me/yourchannel');
INSERT OR IGNORE INTO config VALUES ('telegram_admin','https://t.me/youradmin');
INSERT OR IGNORE INTO config VALUES ('report_text','گزارش مشکل / پیشنهاد');

-- Server Half برای Master Key
INSERT OR IGNORE INTO config VALUES ('server_half','5IGV/ityN91a9Ufvz1DH27O545aWpZKJkEgf8BMPqLc=');

-- کلید API OpenSubtitles — از اینجا هر وقت خواستی عوضش کن (بدون نیاز به آپدیت اپ)
INSERT OR REPLACE INTO config VALUES ('opensubtitles_api_key','0cVNQX84gIY4Nm0VvReFL7DTNMnLeINO');
