#!/usr/bin/env bash
# 地震ライブ配信サーバー インストーラー（Ubuntu 22.04 / 24.04 用）
#   新規:  curl -fsSL https://raw.githubusercontent.com/tsao1989-rgb/tsao1989-rgb.github.io/quake-live/install.sh | sudo bash
#   更新:  sudo quake-live update
set -euo pipefail

TARBALL="${QL_TARBALL:-https://github.com/tsao1989-rgb/tsao1989-rgb.github.io/archive/refs/heads/quake-live.tar.gz}"
APP=/opt/quake-live
CONF=/etc/quake-live
UPDATE=0; [[ "${1:-}" == "--update" ]] && UPDATE=1

say() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
[[ $EUID -eq 0 ]] || { echo "root で実行してください（先頭に sudo を付ける）"; exit 1; }

if [[ $UPDATE -eq 0 ]]; then
  say "1/6 必要なソフトをインストールしています（数分かかります）"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq xvfb pulseaudio ffmpeg python3 fonts-noto-cjk fonts-noto-color-emoji \
    curl wget ca-certificates tzdata >/dev/null

  say "2/6 ブラウザ（Google Chrome）をインストールしています"
  if ! command -v google-chrome >/dev/null; then
    if [[ "$(dpkg --print-architecture)" == "amd64" ]]; then
      wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
      apt-get install -y -qq /tmp/chrome.deb >/dev/null && rm -f /tmp/chrome.deb
    else
      apt-get install -y -qq chromium >/dev/null || apt-get install -y -qq chromium-browser >/dev/null
    fi
  fi
  mkdir -p /etc/opt/chrome/policies/managed /etc/chromium/policies/managed
  POLICY='{"TranslateEnabled": false, "BackgroundModeEnabled": false, "MetricsReportingEnabled": false, "DefaultBrowserSettingEnabled": false, "PromotionalTabsEnabled": false}'
  echo "$POLICY" > /etc/opt/chrome/policies/managed/quake-live.json
  echo "$POLICY" > /etc/chromium/policies/managed/quake-live.json

  timedatectl set-timezone Asia/Tokyo 2>/dev/null || true

  # メモリが少ないVPSでも落ちにくいように、スワップがなければ2GB作る
  if ! swapon --show | grep -q .; then
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi

  id quake >/dev/null 2>&1 || useradd --system --create-home --home-dir /var/lib/quake --shell /usr/sbin/nologin quake
fi

say "3/6 配信プログラムを取得しています"
TMP=$(mktemp -d)
curl -fsSL "$TARBALL" | tar -xz -C "$TMP" --strip-components=1
mkdir -p "$APP"
rm -rf "$APP/bin" "$APP/web" "$APP/systemd"
cp -r "$TMP/bin" "$TMP/web" "$TMP/systemd" "$TMP/config" "$APP/"
chmod +x "$APP"/bin/*
ln -sf "$APP/bin/quake-live" /usr/local/bin/quake-live
rm -rf "$TMP"

say "4/6 設定ファイルを準備しています"
mkdir -p "$CONF"
[[ -f "$CONF/main.env" ]] || cp "$APP/config/example.env" "$CONF/main.env"
chown -R root:quake "$CONF" && chmod 750 "$CONF" && chmod 640 "$CONF"/*.env

say "5/6 自動起動を設定しています"
cp "$APP"/systemd/*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now quake-web >/dev/null 2>&1
systemctl enable quake-stream@main >/dev/null 2>&1

if [[ $UPDATE -eq 0 ]] && ! grep -q '^YT_KEY="..*"' "$CONF/main.env"; then
  say "6/6 YouTubeのストリームキーを入力してください"
  echo "  YouTube Studio →「ライブ配信を開始」→「ストリーム」→「ストリームキー」をコピーして貼り付け"
  echo "  （今は飛ばす場合はそのままEnter。あとで sudo quake-live setkey で設定できます）"
  KEY=""
  { read -r -p "  ストリームキー: " KEY </dev/tty; } 2>/dev/null || true
  if [[ -n "$KEY" ]]; then sed -i "s|^YT_KEY=.*|YT_KEY=\"${KEY}\"|" "$CONF/main.env"; fi
fi

if grep -q '^YT_KEY="..*"' "$CONF/main.env"; then
  systemctl restart quake-stream@main
  sleep 15
  echo
  quake-live status
  echo
  echo "✅ 配信を開始しました。YouTube Studio の画面に映像が届いているか確認してください。"
else
  echo
  echo "⚠ ストリームキーが未設定のため、まだ配信していません。"
  echo "   次のコマンドでキーを設定すると配信が始まります:  sudo quake-live setkey"
fi
echo "   操作方法の一覧:  quake-live help"
