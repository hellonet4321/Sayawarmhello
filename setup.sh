#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  setup.sh  —  نصب خودکار ربات تلگرام → گیت
#  اجرا: sudo bash setup.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "با sudo اجرا کن: sudo bash setup.sh"

# ─── 1. خواندن اطلاعات از کاربر ─────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Telegram → Git Video Bot  Setup        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

read -rp "🤖 توکن ربات تلگرام: " BOT_TOKEN
[[ -z "$BOT_TOKEN" ]] && error "توکن خالیه!"

read -rp "📁 آدرس ریپازیتوری گیت (مثل git@github.com:user/repo.git): " REPO_URL
[[ -z "$REPO_URL" ]] && error "آدرس ریپو خالیه!"

read -rp "👤 User ID(های مجاز تلگرام (کاما جدا، خالی=همه): " ALLOWED_IDS

read -rp "📦 حداکثر حجم فیلم (MB) [پیش‌فرض: 100]: " MAX_MB
MAX_MB=${MAX_MB:-100}

read -rp "📂 نام پوشه ویدیوها داخل ریپو [پیش‌فرض: videos]: " VIDEOS_SUBDIR
VIDEOS_SUBDIR=${VIDEOS_SUBDIR:-videos}

REPO_DIR="/opt/video-repo"
BOT_DIR="/opt/tg-video-bot"
SERVICE_USER="tgbot"

# ─── 2. نصب dependencies ─────────────────────────────────────────────────────
info "نصب پکیج‌های سیستم..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv git curl openssh-client

# ─── 3. ساخت یوزر سیستمی ───────────────────────────────────────────────────
if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -m -d /home/$SERVICE_USER -s /bin/bash $SERVICE_USER
    success "یوزر $SERVICE_USER ساخته شد"
else
    info "یوزر $SERVICE_USER از قبل وجود داره"
fi

# ─── 4. تنظیم SSH key برای git ───────────────────────────────────────────────
SSH_DIR="/home/$SERVICE_USER/.ssh"
mkdir -p "$SSH_DIR"
if [[ ! -f "$SSH_DIR/id_ed25519" ]]; then
    info "ساخت SSH key..."
    sudo -u $SERVICE_USER ssh-keygen -t ed25519 -C "tgbot@server" -f "$SSH_DIR/id_ed25519" -N ""
    echo ""
    echo -e "${YELLOW}══════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}🔑 کلید عمومی SSH رو به ریپازیتوریت اضافه کن:${NC}"
    echo -e "${YELLOW}══════════════════════════════════════════════════════${NC}"
    cat "$SSH_DIR/id_ed25519.pub"
    echo -e "${YELLOW}══════════════════════════════════════════════════════${NC}"
    echo ""
    read -rp "بعد از اضافه کردن کلید، Enter بزن تا ادامه بدیم..."
fi
chown -R $SERVICE_USER:$SERVICE_USER "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR"/id_ed25519 2>/dev/null || true

# GitHub/GitLab رو به known_hosts اضافه کن
sudo -u $SERVICE_USER ssh-keyscan github.com    >> "$SSH_DIR/known_hosts" 2>/dev/null || true
sudo -u $SERVICE_USER ssh-keyscan gitlab.com    >> "$SSH_DIR/known_hosts" 2>/dev/null || true
chmod 644 "$SSH_DIR/known_hosts"

# ─── 5. کلون ریپو ────────────────────────────────────────────────────────────
info "کلون ریپازیتوری..."
if [[ -d "$REPO_DIR/.git" ]]; then
    warn "ریپو از قبل کلون شده، skip"
else
    sudo -u $SERVICE_USER git clone "$REPO_URL" "$REPO_DIR"
    chown -R $SERVICE_USER:$SERVICE_USER "$REPO_DIR"
fi
success "ریپو آماده‌ست: $REPO_DIR"

# ─── 6. ساخت محیط پایتون ─────────────────────────────────────────────────────
info "ساخت محیط Python..."
mkdir -p "$BOT_DIR"
python3 -m venv "$BOT_DIR/venv"
"$BOT_DIR/venv/bin/pip" install -q --upgrade pip
"$BOT_DIR/venv/bin/pip" install -q "python-telegram-bot>=20.0"
chown -R $SERVICE_USER:$SERVICE_USER "$BOT_DIR"

# ─── 7. کپی فایل bot.py ──────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/bot.py" "$BOT_DIR/bot.py"
chown $SERVICE_USER:$SERVICE_USER "$BOT_DIR/bot.py"

# ─── 8. فایل env ─────────────────────────────────────────────────────────────
cat > "$BOT_DIR/.env" <<EOF
BOT_TOKEN=$BOT_TOKEN
ALLOWED_USER_IDS=$ALLOWED_IDS
REPO_DIR=$REPO_DIR
VIDEOS_SUBDIR=$VIDEOS_SUBDIR
GIT_USER_NAME=VideoBot
GIT_USER_EMAIL=bot@server.local
MAX_VIDEO_SIZE_MB=$MAX_MB
EOF
chmod 600 "$BOT_DIR/.env"
chown $SERVICE_USER:$SERVICE_USER "$BOT_DIR/.env"

# ─── 9. git config داخل ریپو ─────────────────────────────────────────────────
sudo -u $SERVICE_USER git -C "$REPO_DIR" config user.name  "VideoBot"
sudo -u $SERVICE_USER git -C "$REPO_DIR" config user.email "bot@server.local"

# ─── 10. فایل systemd service ─────────────────────────────────────────────────
info "ساخت systemd service..."
cat > /etc/systemd/system/tg-video-bot.service <<EOF
[Unit]
Description=Telegram Video → Git Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$BOT_DIR
EnvironmentFile=$BOT_DIR/.env
ExecStart=$BOT_DIR/venv/bin/python bot.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tg-video-bot
systemctl restart tg-video-bot

# ─── 11. تنظیم لاگ ───────────────────────────────────────────────────────────
touch /var/log/tg-video-bot.log
chown $SERVICE_USER:$SERVICE_USER /var/log/tg-video-bot.log

# ─── اتمام ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✅  نصب کامل شد!               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}وضعیت سرویس:${NC}  systemctl status tg-video-bot"
echo -e "  ${CYAN}لاگ آنی:${NC}      journalctl -fu tg-video-bot"
echo -e "  ${CYAN}ریستارت:${NC}      systemctl restart tg-video-bot"
echo -e "  ${CYAN}فایل env:${NC}     $BOT_DIR/.env"
echo ""
