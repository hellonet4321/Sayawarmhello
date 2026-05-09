#!/usr/bin/env python3
"""
Telegram Bot → Git Repository Video Pusher
فیلم رو از تلگرام میگیره و به ریپازیتوری گیت پوش میکنه
"""

import os
import sys
import logging
import subprocess
import asyncio
from pathlib import Path
from datetime import datetime

from telegram import Update
from telegram.ext import Application, MessageHandler, filters, ContextTypes

# ─── تنظیمات ───────────────────────────────────────────────────────────────
BOT_TOKEN   = os.getenv("BOT_TOKEN", "")
ALLOWED_IDS = os.getenv("ALLOWED_USER_IDS", "")   # کاما جدا: 123456,789012  (خالی = همه)
REPO_DIR    = os.getenv("REPO_DIR", "/opt/video-repo")
VIDEOS_DIR  = os.getenv("VIDEOS_SUBDIR", "videos")  # پوشه داخل ریپو
GIT_NAME    = os.getenv("GIT_USER_NAME", "VideoBot")
GIT_EMAIL   = os.getenv("GIT_USER_EMAIL", "bot@localhost")
MAX_SIZE_MB = int(os.getenv("MAX_VIDEO_SIZE_MB", "100"))
# ───────────────────────────────────────────────────────────────────────────

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO,
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("/var/log/tg-video-bot.log", encoding="utf-8"),
    ],
)
log = logging.getLogger(__name__)

ALLOWED_SET: set[int] = set()
if ALLOWED_IDS.strip():
    ALLOWED_SET = {int(x.strip()) for x in ALLOWED_IDS.split(",") if x.strip()}


def run(cmd: list[str], cwd: str = None) -> str:
    """یه دستور shell رو اجرا میکنه و خروجیش رو برمیگردونه"""
    result = subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, check=True
    )
    return result.stdout.strip()


def git_push(filepath: Path, original_filename: str) -> str:
    """فایل رو به ریپو اضافه میکنه و پوش میکنه"""
    repo = Path(REPO_DIR)
    dest_dir = repo / VIDEOS_DIR
    dest_dir.mkdir(parents=True, exist_ok=True)

    # کپی فایل به پوشه ریپو
    dest = dest_dir / filepath.name
    dest.write_bytes(filepath.read_bytes())

    # git config (اگه نیاز باشه)
    run(["git", "config", "user.name", GIT_NAME], cwd=REPO_DIR)
    run(["git", "config", "user.email", GIT_EMAIL], cwd=REPO_DIR)

    # git add + commit + push
    run(["git", "add", str(dest.relative_to(repo))], cwd=REPO_DIR)
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    commit_msg = f"📹 Add video: {original_filename} [{timestamp}]"
    run(["git", "commit", "-m", commit_msg], cwd=REPO_DIR)
    run(["git", "push"], cwd=REPO_DIR)

    log.info(f"✅ Pushed: {dest.name}")
    return dest.name


async def handle_video(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    msg  = update.effective_message

    # بررسی دسترسی
    if ALLOWED_SET and user.id not in ALLOWED_SET:
        await msg.reply_text("⛔ دسترسی ندارید.")
        log.warning(f"Unauthorized: {user.id} ({user.username})")
        return

    # پیدا کردن فایل ویدیو
    video = msg.video or msg.document
    if not video:
        return

    # بررسی سایز
    size_mb = video.file_size / (1024 * 1024)
    if size_mb > MAX_SIZE_MB:
        await msg.reply_text(
            f"❌ فایل خیلی بزرگه ({size_mb:.1f} MB). حداکثر {MAX_SIZE_MB} MB مجازه."
        )
        return

    # اسم فایل اصلی
    original_name = getattr(video, "file_name", None) or f"video_{video.file_unique_id}.mp4"
    # یه اسم یونیک با timestamp
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    ext = Path(original_name).suffix or ".mp4"
    safe_name = f"{ts}_{Path(original_name).stem}{ext}"
    tmp_path = Path("/tmp") / safe_name

    status_msg = await msg.reply_text("⏳ در حال دانلود فایل...")

    try:
        # دانلود از تلگرام
        file = await context.bot.get_file(video.file_id)
        await file.download_to_drive(tmp_path)
        log.info(f"Downloaded: {tmp_path} ({size_mb:.1f} MB)")

        await status_msg.edit_text("📦 در حال پوش به ریپازیتوری...")

        # پوش به گیت
        pushed_name = git_push(tmp_path, original_name)

        await status_msg.edit_text(
            f"✅ موفق!\n"
            f"📁 نام فایل: `{pushed_name}`\n"
            f"📂 مسیر: `{VIDEOS_DIR}/{pushed_name}`\n"
            f"💾 حجم: {size_mb:.1f} MB\n\n"
            f"از ZIP ریپازیتوری دانلود کن 👇",
            parse_mode="Markdown",
        )
        log.info(f"Done: {pushed_name} from user {user.id}")

    except subprocess.CalledProcessError as e:
        err = e.stderr or e.stdout or str(e)
        log.error(f"Git error: {err}")
        await status_msg.edit_text(f"❌ خطای گیت:\n```\n{err[:300]}\n```", parse_mode="Markdown")

    except Exception as e:
        log.error(f"Error: {e}", exc_info=True)
        await status_msg.edit_text(f"❌ خطا: {e}")

    finally:
        if tmp_path.exists():
            tmp_path.unlink()


async def handle_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.effective_message.reply_text(
        "👋 سلام!\n"
        "فیلم بفرست تا به ریپازیتوری پوش بشه.\n"
        f"حداکثر حجم: {MAX_SIZE_MB} MB"
    )


def main():
    if not BOT_TOKEN:
        log.error("BOT_TOKEN تنظیم نشده!")
        sys.exit(1)

    app = Application.builder().token(BOT_TOKEN).build()

    from telegram.ext import CommandHandler
    app.add_handler(CommandHandler("start", handle_start))
    app.add_handler(MessageHandler(filters.VIDEO | filters.Document.VIDEO, handle_video))

    log.info("🤖 Bot started...")
    app.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
