# AI Assistant

自用的面试 AI 助手（macOS）。面试时实时识别面试官语音，结合个人背景信息，即时生成口语化、自然的回答建议。

## 功能

- 系统音频（面试官）+ 麦克风（自己）双路采集，ScreenCaptureKit + AVAudioEngine
- 实时语音识别：AssemblyAI Universal-Streaming
- 回答生成：Claude Haiku，注入个人背景 + 公司信息 + 预设问答范例
- 悬浮窗 UI：常驻置顶显示实时问题与建议回答
- 面试问答记录：按公司/岗位/轮次归档到本地日志

## 目录结构

- `InterviewAssistant/` — Swift Package，主程序源码
- `plan.txt` — 项目可行性分析
- `PROGRESS.md` — 开发进度与技术决策记录

## 运行

```bash
cd InterviewAssistant
./run.sh
```

需要在 `InterviewAssistant/.env` 中配置 AssemblyAI 与 Anthropic 的 API Key（`.env` 不提交到仓库）。

个人资料、公司信息、问答记录等数据文件固定存放于 `~/Documents/InterviewAssistant/`。

## 说明

仅个人使用，未做通用化设计。
