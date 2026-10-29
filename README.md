# 地震ライブ配信サーバー（quake-live）

気象庁の地震情報（P2P地震情報 API 経由）をリアルタイムで表示する画面を、24時間 YouTube Live に配信するためのセットです。

## インストール（Ubuntu 22.04 / 24.04 の VPS）

```bash
curl -fsSL https://raw.githubusercontent.com/tsao1989-rgb/tsao1989-rgb.github.io/quake-live/install.sh | sudo bash
```

途中で YouTube のストリームキーを聞かれます。貼り付けて Enter を押すと配信が始まります。

## 操作

| やりたいこと | コマンド |
|---|---|
| 状態を見る | `quake-live status` |
| ストリームキーを設定・変更 | `sudo quake-live setkey` |
| 再起動 | `sudo quake-live restart` |
| 言語を変える | `sudo quake-live lang en`（ja / en / zh） |
| 英語の併記を変える | `sudo quake-live sub zh`（en / zh / off） |
| タイトルを変える | `sudo quake-live name "地震速報ライブ"` |
| 画質を下げる | `sudo quake-live quality 720` |
| ログを見る | `quake-live logs` |
| 最新版に更新 | `sudo quake-live update` |

## 緊急地震速報とP波・S波

- 緊急地震速報は P2P地震情報（警報）と Wolfx API（予報・警報）の両方から受信し、同じ地震は1つにまとめて表示します。
- P波・S波の円は、気象庁の震源・発生時刻と走時表 JMA2001 から計算した推定です。走時表はインストール時に気象庁のサイトから取得します（取得できない場合は近似計算）。
- 円を消す: 設定ファイルで `SHOW_WAVES="0"`。予報を出さず警報だけにする: `EEW_FORECAST="0"`。

## 構成

- `web/index.html` 配信画面（1920×1080）。URL の末尾で `?obs&lang=ja` などを指定
- `bin/stream.sh` 仮想画面＋Chrome＋ffmpeg で YouTube に送信
- `bin/make-tt.py` 気象庁の走時表を画面用の tt.json に変換
- `systemd/` 自動起動・自動再起動の設定
- `config/example.env` 設定の見本（実際の設定は `/etc/quake-live/main.env`）

## 1つの配信で多言語に対応する

標準では、日本語の画面に英語を併記します（緊急地震速報・津波・新着地震のバナー、上部の状況表示、テロップ）。併記する言語は `SUB_LANG` で変えられます。

## 言語ごとに別の配信を立てるとき

```bash
sudo cp /etc/quake-live/main.env /etc/quake-live/en.env
sudo nano /etc/quake-live/en.env   # YT_KEY を英語チャンネルのキーに、PAGE_LANG="en"、DISPLAY_NUM="100" に変更
sudo systemctl enable --now quake-stream@en
```

## 注意

- 表示する情報は気象庁の発表をそのまま中継するものです。独自の予測は行いません。
- `?demo` を付けるとデモデータになります。本番の配信では使わないでください。
