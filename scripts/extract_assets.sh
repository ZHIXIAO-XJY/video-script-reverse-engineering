#!/usr/bin/env bash
# extract_assets.sh — 视频脚本逆向工程：素材预处理一键脚本
# 用法: bash extract_assets.sh <video> <outdir> [帧间隔秒数]
# 输出: probe.txt / audio.mp3 / kf_*.jpg / frame_index.txt / scene_log.txt / summary.txt
set -uo pipefail

VIDEO="${1:-}"
OUTDIR="${2:-./frames}"
INTERVAL="${3:-10}"

if [ -z "$VIDEO" ] || [ ! -f "$VIDEO" ]; then
  echo "用法: bash extract_assets.sh <video> <outdir> [帧间隔秒数]" >&2
  echo "错误: 找不到视频文件: $VIDEO" >&2
  exit 1
fi

command -v ffmpeg  >/dev/null 2>&1 || { echo "错误: 未安装 ffmpeg" >&2; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo "错误: 未安装 ffprobe" >&2; exit 1; }

mkdir -p "$OUTDIR"

# ---------- P0 探针 ----------
ffprobe -v error -show_entries format=duration,size:stream=codec_type,codec_name,width,height,r_frame_rate \
  -of default=noprint_wrappers=1 "$VIDEO" > "$OUTDIR/probe.txt" 2>/dev/null

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO" 2>/dev/null | cut -d. -f1)
DUR=${DUR:-0}
HAS_AUDIO=$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$VIDEO" 2>/dev/null | head -1)

# 按时长自动调整抽帧间隔（可用第 3 参数覆盖）
if [ "$#" -lt 3 ]; then
  if   [ "$DUR" -le 120 ];  then INTERVAL=2
  elif [ "$DUR" -le 600 ];  then INTERVAL=5
  elif [ "$DUR" -le 1800 ]; then INTERVAL=10
  else                           INTERVAL=20
  fi
fi

# ---------- P1 音频 ----------
if [ -n "$HAS_AUDIO" ]; then
  ffmpeg -y -v error -i "$VIDEO" -vn -ac 1 -ar 16000 -b:a 96k "$OUTDIR/audio.mp3" \
    && echo "[OK] 音频已提取: $OUTDIR/audio.mp3" || echo "[WARN] 音频提取失败，可能需要依口型推断台词"
else
  echo "[WARN] 视频无音轨，跳过音频提取（台词须依口型与字幕推断）"
fi

# ---------- P2 抽帧：先场景检测，命中过少则回退均匀抽帧 ----------
rm -f "$OUTDIR"/kf_*.jpg "$OUTDIR/scene_log.txt"
ffmpeg -y -v error -i "$VIDEO" -vf "select='gt(scene,0.15)',showinfo" -vsync vfr -q:v 3 \
  "$OUTDIR/scene_%03d.jpg" 2> "$OUTDIR/scene_log.txt"
SCENE_N=$(ls "$OUTDIR"/scene_*.jpg 2>/dev/null | wc -l | tr -d ' ')

MODE=""
if [ "$SCENE_N" -ge 10 ]; then
  MODE="场景检测（阈值 0.15，命中 ${SCENE_N} 帧）"
  for f in "$OUTDIR"/scene_*.jpg; do mv "$f" "${f/scene_/kf_}"; done
else
  rm -f "$OUTDIR"/scene_*.jpg
  # 兜底：阈值 0.08 再试一次
  ffmpeg -y -v error -i "$VIDEO" -vf "select='gt(scene,0.08)',showinfo" -vsync vfr -q:v 3 \
    "$OUTDIR/scene_%03d.jpg" 2> "$OUTDIR/scene_log.txt"
  SCENE_N=$(ls "$OUTDIR"/scene_*.jpg 2>/dev/null | wc -l | tr -d ' ')
  if [ "$SCENE_N" -ge 10 ]; then
    MODE="场景检测（阈值 0.08，命中 ${SCENE_N} 帧）"
    for f in "$OUTDIR"/scene_*.jpg; do mv "$f" "${f/scene_/kf_}"; done
  else
    rm -f "$OUTDIR"/scene_*.jpg
    MODE="均匀抽帧（1 帧/${INTERVAL}s，单机位连续拍摄）"
    ffmpeg -y -v error -i "$VIDEO" -vf "fps=1/${INTERVAL},scale=576:-1" -q:v 4 "$OUTDIR/kf_%03d.jpg"
  fi
fi

FRAME_N=$(ls "$OUTDIR"/kf_*.jpg 2>/dev/null | wc -l | tr -d ' ')

# ---------- P3.5 字幕网格（逐秒台词基准表素材） ----------
# 自动探测字幕条纵向位置：取 3 个采样帧，裁画面下 1/3 拼图供人工确认
mkdir -p "$OUTDIR/sub"
GRID_ROWS=10   # 每张网格 3x10=30 帧（30 秒）
FONT=""
for fc in "C:/Windows/Fonts/arialbd.ttf" "/System/Library/Fonts/Supplemental/Arial Bold.ttf" "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"; do
  [ -f "$fc" ] && FONT="$fc" && break
done
if [ -n "$FONT" ]; then
  FONT_ESC=${FONT//:/\\:}   # drawtext 的选项分隔符是冒号，路径里的冒号必须转义
  ffmpeg -y -v error -i "$VIDEO" -vf "fps=1,crop=576:140:0:710,drawtext=fontfile='$FONT_ESC':text='%{pts\:hms}':x=8:y=6:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.75,tile=3x${GRID_ROWS}" -q:v 3 "$OUTDIR/sub/grid%02d.jpg" \
    && GRID_N=$(ls "$OUTDIR"/sub/grid*.jpg 2>/dev/null | wc -l | tr -d ' ') \
    && echo "[OK] 字幕网格已生成: $OUTDIR/sub/ (${GRID_N} 张，每张30秒)" \
    || echo "[WARN] 字幕网格生成失败（可手动确认字幕区域后重试）"
else
  echo "[WARN] 未找到可用字体，跳过字幕网格（可手抽字幕条帧替代）"
fi

# ---------- 帧序号 ↔ 秒数对照表（写场景描述时必备） ----------
: > "$OUTDIR/frame_index.txt"
i=1
for f in $(ls "$OUTDIR"/kf_*.jpg 2>/dev/null | sort); do
  printf "kf_%03d.jpg\t%s\n" "$i" "$(basename "$f")" >> "$OUTDIR/frame_index.txt"
  i=$((i+1))
done

# 均匀抽帧时序号可直接换算；场景检测时用 showinfo 里的 pts_time
if [[ "$MODE" == 均匀抽帧* ]]; then
  awk -v iv="$INTERVAL" '{printf "%s -> %d:%02d\n", $1, (int((NR-1)*iv))/60, int((NR-1)*iv)%60}' \
    "$OUTDIR/frame_index.txt" > "$OUTDIR/frame_times.txt"
else
  grep -o "pts_time:[0-9.]*" "$OUTDIR/scene_log.txt" | cut -d: -f2 | nl -w3 -nrz > "$OUTDIR/frame_times.txt"
fi

# ---------- 汇总 ----------
{
  echo "视频: $VIDEO"
  echo "时长: ${DUR}s ($(printf '%d:%02d' $((DUR/60)) $((DUR%60))))"
  echo "抽帧方式: $MODE"
  echo "总帧数: $FRAME_N"
  echo "音频: $([ -n "$HAS_AUDIO" ] && echo "已提取 audio.mp3" || echo "无音轨")"
  echo "----------------------------------------"
  echo "下一步:"
  echo "1) AudioTranscribe $OUTDIR/audio.mp3"
  echo "2) 逐张读字幕网格 $OUTDIR/sub/grid*.jpg，建立逐秒台词基准表（说话人归属第一证据）"
  echo "3) 每批 8 张并行 ViewImage，query 统一为:"
  echo "   描述这一竖屏视频帧：人物外貌、表情、动作、场景、服装、字幕文字、构图"
  echo "4) 高危段切片重转录（见 SKILL.md P6）"
  echo "   ffmpeg -y -v error -ss <起> -t 75 -i \"$VIDEO\" -vn -ac 1 -ar 16000 -b:a 96k seg1.mp3"
} | tee "$OUTDIR/summary.txt"
