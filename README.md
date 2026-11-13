# 视频脚本高精度逆向工程 · Video Script Reverse Engineering

> 把一个带货视频 / 剧情短剧，逐帧还原成**可直接复刻拍摄的完整脚本**——说什么、怎么说、脸上怎么变、眼睛在看谁、为什么这么说。
>
> A [WorkBuddy](https://www.workbuddy.cn) Skill that reverse-engineers any video into a film-grade shooting script with timing, dialogue, voice quality, facial-expression trajectories and named eye-contact targets.

## 它解决什么问题

普通 ASR 只能给你一段扁平的文字稿。而真正拿去复刻拍摄时，你需要知道的是：

- 这句话是**谁**说的（多人混杂段落，ASR 的 diarization 几乎必错）
- 这声"**哼**"是冷笑还是认输，是鼻腔气音还是喉音——它决定了这句归谁
- 说到"**他也配？**"时，音量是压低后爆出，还是拔高——同一个字的演法完全不同
- 眼神从**谁**投向**谁**的**哪个部位**，停留几秒
- 表情从 `[起]` 到 `[末]` 怎么走（瞪圆 → 瞳孔放大 → 眉舒展抿唇）

本技能把这套"摄像机 + 导演"双视角的拆解方法固化成一条可重复执行的流水线。

## 交付物长什么样

一份 Markdown 脚本，包含：

| 章节 | 内容 |
|---|---|
| 📋 角色档案 | 每个角色的性格、造型、身份对应关系（化名 / 童年 / 成年必须分开建档） |
| 🎭 语气·神态总表 | 每个角色 × 音色音高 / 语速节奏 / 气息特征 / 招牌微表情 / 情绪外化方式 |
| 🎬 分段脚本 | 按 `⏱️ [mm:ss - mm:ss] 事件名` 切段，每句台词下挂五维标签 |
| 💰 带货结构拆解 | 钩子 → 痛点 → 共鸣 → 实证 → 报价 → 行动指令的节点标注 |
| 🎯 表演提示单 | 主角完整情绪曲线 + 每个角色的表演核心要点 |
| 🔍 校验记录 | 二轮交叉校验的差异表 + 重合度 + 遗留不确定项 |

每句台词下的五个标签：

- **🎙️ 声音质感** — 音高走向 / 音量 / 语速 / 气息（气声·破音·抽气）/ 重音落点 / 停顿长度
- **😐 表情变化轨迹** — `[起] → [中] → [末]` 三段，写到眉、眼、嘴、鼻翼、下颌
- **👀 眼神交互** — 【主语】的眼神投向【宾语具名】，停留时长 + 视线移动路径
- **🙌 动作细节** — 手部姿态、身体朝向、道具互动（指节发白 / 攥紧 / 指尖发抖）
- **🫧 神态气场** — 一句话定性此刻心理状态（导演视角，不是复述表情）

## 安装

### 方式一：下载即用（推荐）

```bash
git clone https://github.com/ZHIXIAO-XJY/video-script-reverse-engineering.git
```

把整个目录放到 WorkBuddy 的**用户级技能目录**（跨项目可用）：

| 系统 | 路径 |
|---|---|
| Windows | `C:\Users\<你的用户名>\.workbuddy\skills\video-script-reverse-engineering\` |
| macOS / Linux | `~/.workbuddy/skills/video-script-reverse-engineering/` |

放好后目录结构应该是这样（`SKILL.md` 必须直接在该目录下，不要多层嵌套）：

```
.workbuddy/skills/video-script-reverse-engineering/
├── SKILL.md
├── references/
│   ├── script-template.md
│   ├── qc-checklist.md
│   └── pitfalls.md
└── scripts/
    └── extract_assets.sh
```

重启 WorkBuddy 后，在「设置 → 技能」里能看到 `video-script-reverse-engineering` 即安装成功。

### 方式二：一键安装脚本

```bash
# macOS / Linux
bash scripts/install.sh

# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File scripts/install.ps1
```

（在仓库根目录执行，脚本会把技能复制到用户级技能目录）

## 依赖

| 依赖 | 用途 | 安装 |
|---|---|---|
| **ffmpeg / ffprobe** | 探针、抽帧、音频提取、片段切分 | `brew install ffmpeg` / `winget install ffmpeg` / `apt install ffmpeg` |
| **WorkBuddy** | 提供 `AudioTranscribe`（语音转录）与 `ViewImage`（看帧）工具 | https://www.workbuddy.cn |
| **bash** | 运行 `extract_assets.sh` | Windows 用 Git Bash 或 WSL |

检查依赖：

```bash
ffmpeg -version && ffprobe -version
```

> 没有 `AudioTranscribe` 的话，可以换用任何带说话人分离（diarization）的 ASR（WhisperX、阿里云、腾讯云等），只要产出 `[起,止,说话人ID]` 时间戳即可，后续流程不变。

## 使用

安装后在 WorkBuddy 里直接说：

```
帮我拆解这个视频的脚本：/path/to/video.mp4
```

或显式指定技能：

```
用 video-script-reverse-engineering 跑一遍 ./短视频.mp4
```

**触发词**：拆脚本、还原脚本、逐帧分析、拉片、视频转脚本、带货脚本还原、短剧脚本、这个视频怎么拍的

### 手动跑预处理

```bash
# 探针 → 音频 → 场景检测 → 均匀抽帧 → 高危段切片
bash scripts/extract_assets.sh ./video.mp4 ./frames [帧间隔秒数]

# 例：10 分钟的视频，每 10 秒一帧
bash scripts/extract_assets.sh ./video.mp4 ./frames 10
```

输出：

```
frames/
├── probe.txt          # 时长/分辨率/码率/音轨信息
├── audio.mp3          # 16kHz 单声道，供 ASR
├── kf_001.jpg ...     # 关键帧
├── frame_index.txt    # 帧序号 ↔ 秒数对照表
├── scene_log.txt      # 场景检测原始日志
└── summary.txt        # 工作量表（时长/帧数/建议密度）
```

## 工作流（P0–P7）

```
P0 素材探针    ffprobe 拿时长/分辨率 → 按时长定抽帧密度
P1 音频转录    AudioTranscribe 全量转录 → 带时间戳的台词骨架
P2 抽帧        场景检测优先，命中<10帧则回退均匀抽帧
P3 批量看帧    每批 8 张并行，抄字幕/水印/价格/品牌名
P4 建骨架      按场景切段，每段命名 + 场景描述
P5 五维填充    台词下挂 声音/表情/眼神/动作/神态 五标签
P6 二轮校验    ★ 高危段切片重转录，比对修正说话人与代词
P7 交付自检    过 qc-checklist，present_files 呈现
```

### 为什么 P6 最关键

整片一次性转录会把相邻两人的话合并成一段、把"他/她"写成同一个字、把问句写成陈述句。所以必须挑 4–6 个**高危段**（多人混杂 / 代词易混 / 叠句抢话 / 语气词孤立成句 / 长时间戳未换人）切成 70–90 秒重转录，逐句比对。

实战中，一个 14 分钟视频的二轮校验修正了 **10 处**实质错误，包括：

- 一声"哼"从男主划给母亲（下一句"笑话，我不懂"才是真凶）
- "你竟然给了**他**？**他**也配？" → 女主是女性，应为"她"
- 4:15 整段 3 句问答漏录
- 9:10 三连问的说话人前后完全颠倒

修正后 137 个话语单元里 129 条一致（重合度 94.2%）。

## 目录结构

```
video-script-reverse-engineering/
├── SKILL.md                      # 主流程 P0–P7 + 五条铁律
├── references/
│   ├── script-template.md        # 交付物完整骨架模板
│   ├── qc-checklist.md           # 13 项交付前自检
│   └── pitfalls.md               # 8 类高频错误 + 真实案例
├── scripts/
│   ├── extract_assets.sh         # 一键预处理
│   ├── install.sh                # macOS/Linux 安装
│   └── install.ps1               # Windows 安装
└── README.md
```

## 适用与不适用

**适用**：带货短视频、剧情短剧、口播、访谈、广告片、需要反推分镜节奏的对标视频

**不适用**：纯字幕提取（用普通 ASR 就够）、视频剪辑本身、音乐扒谱

## 许可

[MIT License](LICENSE) — 自由使用、修改、商用，保留版权声明即可。

## 致谢

方法沉淀自真实项目：一支 14 分 18 秒的 AI 短剧带货片，经过"全量转录 + 86 帧逐帧视觉分析 + 6 段分片重转录交叉校验"三轮打磨后固化而成。
