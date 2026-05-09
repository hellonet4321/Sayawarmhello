# 📹 ربات تلگرام → گیت (فیلم‌پوشر)

فیلم بفرست به ربات، اتوماتیک به ریپازیتوری گیت پوش میشه.  
بعد از همون لینک **دانلود ZIP** گیتهاب/گیتلب فیلمت رو داری.

---

## ⚡ نصب سریع (یه دستور)

```bash
git clone <this-repo> && cd tg-to-git
sudo bash setup.sh
```

اسکریپت خودش همه چیز رو میپرسه و نصب میکنه.

---

## 📋 پیش‌نیازها

| چی | چرا |
|---|---|
| Ubuntu 20.04+ | سیستم‌عامل |
| Python 3.9+ | برای ربات |
| SSH key | دسترسی به ریپازیتوری |
| توکن ربات تلگرام | از [@BotFather](https://t.me/BotFather) بگیر |

---

## 🔧 کانفیگ دستی (اگه نخوای setup.sh اجرا کنی)

### ۱. فایل `/opt/tg-video-bot/.env` رو بساز:

```env
BOT_TOKEN=123456:ABC-your-token-here
ALLOWED_USER_IDS=123456789,987654321
REPO_DIR=/opt/video-repo
VIDEOS_SUBDIR=videos
GIT_USER_NAME=VideoBot
GIT_USER_EMAIL=bot@server.local
MAX_VIDEO_SIZE_MB=100
```

### ۲. ریپو رو کلون کن:

```bash
git clone git@github.com:username/repo.git /opt/video-repo
```

### ۳. سرویس رو ران کن:

```bash
systemctl start tg-video-bot
```

---

## 📥 دانلود فیلم‌ها

بعد از push شدن، فیلم‌ها داخل پوشه `videos/` ریپازیتوری هستن.

### روش دانلود (بدون فیلتر):

۱. روی ریپازیتوری در گیتهاب برو  
۲. دکمه سبز **Code** رو بزن  
۳. **Download ZIP** رو انتخاب کن  
۴. ZIP رو extract کن، فیلم‌ها داخل پوشه `videos/` هستن

---

## 🛠 دستورات مفید

```bash
# وضعیت سرویس
systemctl status tg-video-bot

# لاگ آنی
journalctl -fu tg-video-bot

# ریستارت
systemctl restart tg-video-bot

# ویرایش تنظیمات
nano /opt/tg-video-bot/.env
systemctl restart tg-video-bot
```

---

## ⚠️ محدودیت حجم تلگرام

| نوع | حداکثر |
|---|---|
| آپلود کاربر عادی | 2 GB |
| دانلود توسط ربات | 20 MB (بات API) |

> اگه فیلمت بزرگتر از 20 MB هست، باید از **Bot API Local Server** استفاده کنی یا فیلم رو به صورت **document** (نه video) ارسال کنی — ربات هر دو رو پشتیبانی میکنه.

---

## 🔒 امنیت

- `ALLOWED_USER_IDS` رو حتماً تنظیم کن تا فقط خودت بتونی فایل بفرستی  
- فایل `.env` رو با `chmod 600` محافظت کن (setup.sh خودش اینو میکنه)
