#!/usr/bin/env bash
# 地震ライブ配信：仮想画面でダッシュボードを開き、ffmpegでYouTubeへ送る
# 使い方: stream.sh <設定ファイル>
set -uo pipefail

ENV_FILE="${1:-/etc/quake-live/main.env}"
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${YT_KEY:=}"
: "${RTMP_URL:=rtmp://a.rtmp.youtube.com/live2}"
: "${OUTPUT:=}"                 # テスト用: ファイル名を入れるとYouTubeではなくファイルに保存
: "${PAGE_LANG:=ja}"
: "${CHANNEL_NAME:=}"
: "${RESOLUTION:=1920x1080}"
: "${FPS:=30}"
: "${VIDEO_BITRATE:=4500k}"
: "${PRESET:=veryfast}"
: "${DISPLAY_NUM:=99}"
: "${WEB_PORT:=8080}"
: "${AUDIO:=pulse}"             # pulse = 通知音を配信に乗せる / silent = 無音
: "${CHROME_BIN:=$(command -v google-chrome || command -v google-chrome-stable || command -v chromium || command -v chromium-browser)}"

if [[ -z "$OUTPUT" && -z "$YT_KEY" ]]; then
  echo "[quake-live] YouTubeのストリームキーが設定されていません: $ENV_FILE" >&2
  exit 2
fi

W="${RESOLUTION%x*}"; H="${RESOLUTION#*x}"
RUN_DIR="/tmp/quake-live-${DISPLAY_NUM}"
mkdir -p "$RUN_DIR" && chmod 700 "$RUN_DIR"
rm -rf "$RUN_DIR/chrome"   # 毎回まっさらなブラウザで起動
export XDG_RUNTIME_DIR="$RUN_DIR"
export DISPLAY=":${DISPLAY_NUM}"

PIDS=()
cleanup() {
  for p in "${PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null; done
  [[ "$AUDIO" == "pulse" ]] && pulseaudio --kill 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT INT TERM

# 1) 仮想画面
rm -f "/tmp/.X${DISPLAY_NUM}-lock"
Xvfb "$DISPLAY" -screen 0 "${W}x${H}x24" -nolisten tcp >"$RUN_DIR/xvfb.log" 2>&1 &
PIDS+=($!)
for _ in $(seq 1 50); do [[ -e "/tmp/.X11-unix/X${DISPLAY_NUM}" ]] && break; sleep 0.1; done

# 2) 音声（ブラウザの通知音を拾う仮想スピーカー）
AUDIO_IN=(-f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100")
if [[ "$AUDIO" == "pulse" ]] && command -v pulseaudio >/dev/null; then
  pulseaudio --kill 2>/dev/null
  pulseaudio -D --exit-idle-time=-1 --disallow-exit -n \
    --load="module-native-protocol-unix" \
    --load="module-null-sink sink_name=quake rate=44100" \
    --load="module-always-sink" >"$RUN_DIR/pulse.log" 2>&1
  sleep 1
  pactl set-default-sink quake 2>/dev/null
  AUDIO_IN=(-thread_queue_size 1024 -f pulse -i quake.monitor)
fi

# 3) ダッシュボードを全画面で開く
QS="obs&lang=${PAGE_LANG}"
[[ -n "$CHANNEL_NAME" ]] && QS="${QS}&name=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$CHANNEL_NAME")"
[[ "${SHOW_WAVES:-1}" == "0" ]] && QS="${QS}&waves=0"
[[ "${EEW_FORECAST:-1}" == "0" ]] && QS="${QS}&eewfc=0"
QS="${QS}${PAGE_QUERY_EXTRA:-}"   # テスト専用（例: &demo）。本番では使わない
URL="http://127.0.0.1:${WEB_PORT}/index.html?${QS}"
case "$PAGE_LANG" in en) UI_LANG=en-US ;; zh) UI_LANG=zh-TW ;; *) UI_LANG=ja ;; esac
"$CHROME_BIN" --kiosk "$URL" \
  --lang="$UI_LANG" --disable-translate \
  --user-data-dir="$RUN_DIR/chrome" --no-first-run --no-default-browser-check \
  --disable-infobars --noerrdialogs --disable-session-crashed-bubble --disable-features=Translate,MediaRouter \
  --autoplay-policy=no-user-gesture-required --hide-scrollbars --force-device-scale-factor=1 \
  --window-position=0,0 --window-size="${W},${H}" --disable-gpu --disable-dev-shm-usage \
  --password-store=basic --no-sandbox --test-type ${CHROME_EXTRA_FLAGS:-} >"$RUN_DIR/chrome.log" 2>&1 &
PIDS+=($!)
sleep 8   # 地図とデータの読み込み待ち

# 4) 映像＋音声をエンコードして送信
if [[ -n "$OUTPUT" ]]; then DEST=(-f flv "$OUTPUT"); else DEST=(-f flv "${RTMP_URL}/${YT_KEY}"); fi
GOP=$(( FPS * 2 ))
echo "[quake-live] 配信開始 ${RESOLUTION} ${FPS}fps ${VIDEO_BITRATE} lang=${PAGE_LANG}"
ffmpeg -hide_banner -loglevel warning -nostdin \
  -thread_queue_size 1024 -f x11grab -draw_mouse 0 -video_size "${W}x${H}" -framerate "$FPS" -i "$DISPLAY" \
  "${AUDIO_IN[@]}" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset "$PRESET" -pix_fmt yuv420p -r "$FPS" -g "$GOP" -keyint_min "$GOP" -sc_threshold 0 \
  -b:v "$VIDEO_BITRATE" -maxrate "$VIDEO_BITRATE" -bufsize "$(( ${VIDEO_BITRATE%k} * 2 ))k" \
  -c:a aac -b:a 128k -ar 44100 -ac 2 \
  ${FFMPEG_EXTRA:-} "${DEST[@]}" &
FF=$!
PIDS+=($FF)

# どれか1つでも止まったら全体を終了（systemdが自動で再起動する）
while true; do
  for p in "${PIDS[@]}"; do
    if ! kill -0 "$p" 2>/dev/null; then
      echo "[quake-live] プロセスが停止したため再起動します (pid $p)" >&2
      exit 1
    fi
  done
  sleep 5
done
