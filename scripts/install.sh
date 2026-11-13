#!/usr/bin/env bash
# install.sh — 把本技能安装到 WorkBuddy 用户级技能目录
# 用法: bash scripts/install.sh
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${WORKBUDDY_SKILLS_DIR:-$HOME/.workbuddy/skills}/video-script-reverse-engineering"

echo "源目录: $SRC"
echo "目标目录: $DEST"

if [ ! -f "$SRC/SKILL.md" ]; then
  echo "错误: 在 $SRC 找不到 SKILL.md，请在仓库根目录执行本脚本。" >&2
  exit 1
fi

mkdir -p "$(dirname "$DEST")"

if [ -e "$DEST" ]; then
  BACKUP="$DEST.bak.$(date +%Y%m%d%H%M%S)"
  echo "检测到已安装，备份到: $BACKUP"
  mv "$DEST" "$BACKUP"
fi

mkdir -p "$DEST"
cp "$SRC/SKILL.md" "$DEST/"
cp -r "$SRC/references" "$DEST/"
cp -r "$SRC/scripts" "$DEST/"

chmod +x "$DEST/scripts/"*.sh 2>/dev/null || true

echo ""
echo "✅ 安装完成: $DEST"
echo ""
echo "目录结构:"
find "$DEST" -type f | sed "s|$DEST|.|"
echo ""
command -v ffmpeg  >/dev/null 2>&1 || echo "⚠️  未检测到 ffmpeg，请先安装: brew install ffmpeg / winget install ffmpeg / apt install ffmpeg"
echo "重启 WorkBuddy 后即可使用。试试说：帮我拆解这个视频的脚本 <路径>"
