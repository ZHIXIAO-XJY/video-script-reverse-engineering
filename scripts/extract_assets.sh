#!/usr/bin/env bash
# extract_assets.sh — 视频脚本逆向工程：素材预处理一键脚本
#
# 用法:
#   bash extract_assets.sh <video> <outdir> [模式]
#
# 模式:
#   fast   (默认) 快拆模式 — 生成 filmstrip 拼贴网格 + 字幕网格，约 10 分钟出成品
#   deep   精拆模式 — 额外生成单帧序列，用于逐帧复核
#
# 输出:
#   probe.txt / audio.mp3 / fs/fs*.jpg (filmstrip 网格) / sub/grid*.jpg (字幕网格)
#   frame_index.txt / summary.txt
set -uo pipefail

VIDEO="${1:-}"
OUTDIR="${2:-./frames}"
MODE="${3:-fast}"

if [ -z "$VIDEO" ] || [ ! -f "$VIDEO" ]; then
  echo "用法: bash extract_assets.sh <video> <outdir> [fast|deep]" >&2
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
W=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$VIDEO" 2>/dev/null | head -1)
H=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$VIDEO" 2>/dev/null | head -1)
W=${W:-720}; H=${H:-1280}

# ---------- 模式参数表 ----------
# INTERVAL  每隔几秒取一帧
# CELL_W    每格宽度（像素），决定缩放
# TILE      拼图行列
# SUB_ROWS  字幕网格行数
if [ "$MODE" = "deep" ]; then
  if   [ "$DUR" -le 120 ];  then INTERVAL=1;  CELL_W=360; TILE="4x4"
  elif [ "$DUR" -le 600 ];  then INTERVAL=2;  CELL_W=300; TILE="5x4"
  elif [ "$DUR" -le 1800 ]; then INTERVAL=2;  CELL_W=240; TILE="6x4"
  else                           INTERVAL=5;  CELL_W=240; TILE="6x4"
  fi
else
  if   [ "$DUR" -le 120 ];  then INTERVAL=2;  CELL_W=300; TILE="5x4"
  elif [ "$DUR" -le 600 ];  then INTERVAL=4;  CELL_W=240; TILE="6x4"
  elif [ "$DUR" -le 1800 ]; then INTERVAL=5;  CELL_W=240; TILE="6x4"
  else                           INTERVAL=8;  CELL_W=240; TILE="6x4"
  fi
fi
COLS=$(echo "$TILE" | cut -d'x' -f1)
ROWS=$(echo "$TILE" | cut -d'x' -f2)
FS_SECS=$((INTERVAL * COLS * ROWS))

# ---------- 字体 ----------
FONT=""
for fc in "C:/Windows/Fonts/arialbd.ttf" "/System/Library/Fonts/Supplemental/Arial Bold.ttf" "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"; do
  [ -f "$fc" ] && FONT="$fc" && break
done
if [ -n "$FONT" ]; then
  FONT_ESC=${FONT//:/\\:}   # drawtext 选项分隔符是冒号，路径里的冒号必须转义
else
  FONT_ESC=""
fi

# ---------- P1 音频 ----------
if [ -n "$HAS_AUDIO" ]; then
  ffmpeg -y -v error -i "$VIDEO" -vn -ac 1 -ar 16000 -b:a 96k "$OUTDIR/audio.mp3" \
    && echo "[OK] 音频已提取: $OUTDIR/audio.mp3" || echo "[WARN] 音频提取失败，可能需要依口型推断台词"
else
  echo "[WARN] 视频无音轨，跳过音频提取（台词须依口型与字幕推断）"
fi

# ---------- P2 filmstrip 网格（核心提速手段） ----------
# 每格 = 完整画面（自带烧录字幕）+ 时间戳角标；6x4 网格在 240px 下表情/字幕/多人同框均可辨
mkdir -p "$OUTDIR/fs"
rm -f "$OUTDIR"/fs/fs*.jpg
if [ -n "$FONT_ESC" ]; then
  ffmpeg -y -v error -i "$VIDEO" \
    -vf "fps=1/${INTERVAL},scale=${CELL_W}:-1,drawtext=fontfile='$FONT_ESC':text='%{pts\:hms}':x=4:y=4:fontsize=20:fontcolor=yellow:box=1:boxcolor=black@0.75,tile=${TILE}" \
    -q:v 4 "$OUTDIR/fs/fs%02d.jpg" \
    && FS_N=$(ls "$OUTDIR"/fs/fs*.jpg 2>/dev/null | wc -l | tr -d ' ') \
    && echo "[OK] filmstrip 网格: $OUTDIR/fs/ (${FS_N} 张，每张覆盖 ${FS_SECS}s)" \
    || echo "[WARN] filmstrip 生成失败"
else
  echo "[WARN] 未找到可用字体，无法叠加时间戳角标"
fi

# ---------- P3.5 字幕网格（逐秒台词基准表素材） ----------
# 字幕条纵向位置按比例推算：竖屏片字幕通常在画面 61%-74% 处
# 采样 2 秒/格：台词极少快于 2 秒，1 秒/格会让张数翻倍且文字过密
mkdir -p "$OUTDIR/sub"
rm -f "$OUTDIR"/sub/grid*.jpg
SUB_Y=$((H * 61 / 100))
SUB_CH=$((H * 13 / 100))
SUB_STEP=2
if [ "$MODE" = "deep" ]; then SUB_STEP=1; fi
if [ -n "$FONT_ESC" ]; then
  ffmpeg -y -v error -i "$VIDEO" \
    -vf "fps=1/${SUB_STEP},crop=${W}:${SUB_CH}:0:${SUB_Y},scale=360:-1,drawtext=fontfile='$FONT_ESC':text='%{pts\:hms}':x=4:y=4:fontsize=20:fontcolor=cyan:box=1:boxcolor=black@0.7,tile=6x8" \
    -q:v 3 "$OUTDIR/sub/grid%02d.jpg" \
    && GRID_N=$(ls "$OUTDIR"/sub/grid*.jpg 2>/dev/null | wc -l | tr -d ' ') \
    && echo "[OK] 字幕网格: $OUTDIR/sub/ (${GRID_N} 张，每张48格/覆盖$((48 * SUB_STEP))s)" \
    || echo "[WARN] 字幕网格生成失败（可手动确认字幕区域后重试）"
else
  echo "[WARN] 未找到可用字体，跳过字幕网格"
fi

# ---------- 精拆模式：额外产出单帧序列 ----------
if [ "$MODE" = "deep" ]; then
  rm -f "$OUTDIR"/kf_*.jpg
  ffmpeg -y -v error -i "$VIDEO" -vf "fps=1/${INTERVAL},scale=576:-1" -q:v 4 "$OUTDIR/kf_%03d.jpg"
  KF_N=$(ls "$OUTDIR"/kf_*.jpg 2>/dev/null | wc -l | tr -d ' ')
  echo "[OK] 单帧序列: $OUTDIR/kf_*.jpg (${KF_N} 张，1帧/${INTERVAL}s)"
  : > "$OUTDIR/frame_index.txt"
  i=1
  for f in $(ls "$OUTDIR"/kf_*.jpg 2>/dev/null | sort); do
    printf "kf_%03d.jpg\t%ds\n" "$i" $(( (i-1) * INTERVAL )) >> "$OUTDIR/frame_index.txt"
    i=$((i+1))
  done
fi

# ---------- 汇总 ----------
FS_N=$(ls "$OUTDIR"/fs/fs*.jpg 2>/dev/null | wc -l | tr -d ' ')
GRID_N=$(ls "$OUTDIR"/sub/grid*.jpg 2>/dev/null | wc -l | tr -d ' ')
{
  echo "视频: $VIDEO"
  echo "时长: ${DUR}s ($(printf '%d:%02d' $((DUR/60)) $((DUR%60))))  分辨率: ${W}x${H}"
  echo "模式: ${MODE}  |  抽帧间隔: 1帧/${INTERVAL}s  |  网格: ${TILE} @ ${CELL_W}px"
  echo "filmstrip: ${FS_N} 张（每张 ${FS_SECS}s） | 字幕网格: ${GRID_N} 张（每张48s）"
  echo "音频: $([ -n "$HAS_AUDIO" ] && echo "已提取 audio.mp3" || echo "无音轨")"
  echo "----------------------------------------"
  echo "读图量预估: ${FS_N} 张 filmstrip + ${GRID_N} 张字幕网格 = $((FS_N + GRID_N)) 张（分批并行 ViewImage）"
  echo "----------------------------------------"
  echo "下一步:"
  echo "1) AudioTranscribe $OUTDIR/audio.mp3  【与第2步并行发起】"
  echo "2) 读 $OUTDIR/fs/fs*.jpg —— 逐格记录：人物/表情/动作/场景/字幕（这是画面信息的唯一来源）"
  echo "3) 读 $OUTDIR/sub/grid*.jpg —— 建立台词基准表，逐条对齐 ASR 文本"
  echo "4) 写脚本（引用上面的时间锚点，不回头补看）"
  if [ "$MODE" = "deep" ]; then
    echo "5) 精拆模式：按 $OUTDIR/frame_index.txt 做画面复核，高危段定点抽全帧看口型"
  else
    echo "5) 归属存疑点（≤3处）定点抽 1-2 张全尺寸帧看口型："
    echo "   ffmpeg -y -v error -ss <秒> -i \"$VIDEO\" -frames:v 1 chk.jpg"
  fi
} | tee "$OUTDIR/summary.txt"
