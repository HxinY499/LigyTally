#!/bin/zsh

set -euo pipefail

# 把已构建的正式 APK 发到阿里云 OSS。
# notes 必须先给人看过；没确认之前不要跑这个脚本。

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUCKET="ligy-tally-releases"

# 清单和 APK 走**两个不同的域名**，不要合成一个常量。
#
# 清单必须留在 OSS 默认域名：应用把这条地址硬编码在 `kUpdateManifestUrl` 里，
# 换了就等于所有已安装版本都查不到更新。JSON 在这个域名上可以匿名读。
MANIFEST_BASE="https://ligy-tally-releases.oss-cn-hangzhou.aliyuncs.com"

# APK 只能从自定义域名下。OSS 默认域名对 APK 返回 400（ApkDownloadForbidden），
# 而且返回的是一段 XML，浏览器里看不出下到的不是包——1.5.11 就是这么翻车的。
#
# 这一行以前写的是 MANIFEST_BASE，于是每次发版都要手工把清单里的 apk_url 改成
# 自定义域名再重传一次。漏掉这一步的后果是「清单正常、用户一点更新就失败」。
DOWNLOAD_BASE="https://releases.ligezhang.cn"

NOTES="${1:-}"
if [[ -z "$NOTES" ]]; then
  echo "用法: $0 \"\$(cat <<'EOF'" >&2
  echo "## 更新内容" >&2
  echo "" >&2
  echo "- 条目" >&2
  echo "EOF" >&2
  echo ")\"" >&2
  exit 1
fi

if [[ "$NOTES" != $'## 更新内容'$'\n'* ]]; then
  echo "notes 第一行必须是 ## 更新内容" >&2
  exit 1
fi
if ! print -r -- "$NOTES" | grep -qE '^- '; then
  echo "notes 至少要有一条以 - 开头的更新内容" >&2
  exit 1
fi

if ! command -v ossutil >/dev/null; then
  echo "未找到 ossutil。先安装并完成 ossutil config。" >&2
  exit 1
fi
if [[ ! -f "$HOME/.ossutilconfig" ]]; then
  echo "未找到 ~/.ossutilconfig，先登录 ossutil。" >&2
  exit 1
fi

cd "$ROOT_DIR"

VERSION="$(awk '/^version:/ {print $2}' pubspec.yaml)"
VERSION_NAME="${VERSION%%+*}"
DIST_DIR="$ROOT_DIR/dist"
APK_NAME="LigyTally-$VERSION_NAME.apk"
APK_PATH="$DIST_DIR/$APK_NAME"
SHA_PATH="$APK_PATH.sha256"
MANIFEST_PATH="$DIST_DIR/latest.json"

if [[ ! -f "$APK_PATH" || ! -f "$SHA_PATH" ]]; then
  echo "找不到 $APK_PATH 或校验文件，先跑 ./scripts/build_release.sh" >&2
  exit 1
fi

SHA256="$(awk 'NR==1 {print $1}' "$SHA_PATH")"
if [[ ! "$SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "校验文件格式不对: $SHA_PATH" >&2
  exit 1
fi

APK_SIZE="$(stat -f '%z' "$APK_PATH")"
APK_URL="$DOWNLOAD_BASE/$APK_NAME"

python3 - "$MANIFEST_PATH" "$VERSION_NAME" "$APK_NAME" "$APK_URL" "$APK_SIZE" "$SHA256" "$NOTES" <<'PY'
import json
import sys

path, version, name, url, size, sha256, notes = sys.argv[1:]
manifest = {
    "tag_name": f"v{version}",
    "body": notes,
    "apk_name": name,
    "apk_url": url,
    "apk_size": int(size),
    "sha256": sha256.lower(),
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY

ossutil cp "$APK_PATH" "oss://$BUCKET/$APK_NAME" \
  --acl public-read \
  --content-type application/vnd.android.package-archive \
  --force
ossutil cp "$APK_PATH" "oss://$BUCKET/LigyTally-latest.apk" \
  --acl public-read \
  --content-type application/vnd.android.package-archive \
  --force
ossutil cp "$SHA_PATH" "oss://$BUCKET/$APK_NAME.sha256" \
  --acl public-read \
  --content-type text/plain \
  --force
# 清单最后传，避免客户端先看到新版本却还下不到包。
ossutil cp "$MANIFEST_PATH" "oss://$BUCKET/latest.json" \
  --acl public-read \
  --content-type application/json \
  --cache-control "no-cache" \
  --force

REMOTE_TAG="$(curl -fsS "$MANIFEST_BASE/latest.json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
if [[ "$REMOTE_TAG" != "v$VERSION_NAME" ]]; then
  echo "上传后 latest.json 的 tag 是 $REMOTE_TAG，期望 v$VERSION_NAME" >&2
  exit 1
fi

echo "Manifest: $MANIFEST_BASE/latest.json"
echo "APK:      $APK_URL"
echo "Latest:   $DOWNLOAD_BASE/LigyTally-latest.apk"
