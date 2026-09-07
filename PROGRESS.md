# 面试 AI 助手 - 进度跟踪

## 已确认决策
- 不做屏幕共享隐藏功能
- STT + LLM 走云端 API（不做本地部署）
- 用户背景资料收集方式：暂缓，后续需要时再问

## 技术方案（待细化）
- 音频：ScreenCaptureKit / Core Audio Process Taps 抓系统音频（面试官）+ 麦克风（自己）
- STT：AssemblyAI Universal-Streaming（备选 Deepgram Nova-3/Flux）
- LLM：Claude Haiku，system prompt 注入背景信息 + few-shot 语气样本
- UI：macOS 原生悬浮窗

## 阶段
- [x] 可行性分析（见 plan.txt 分析结论：可行，无硬 blocker）
- [x] 音频分流验证：`InterviewAssistant/` Swift 包，ScreenCaptureKit 抓系统音频 + AVAudioEngine 抓麦克风，实测两路均采集成功（mic 55 / 系统音频 268 缓冲区/5秒）
- [x] STT 接入验证：AssemblyAI v3 WebSocket 流式识别，麦克风单路测试通过（临时+最终转写、end_of_turn 判断均正常）
- [x] LLM 接入验证：Anthropic Messages API 原生 HTTP+SSE 流式调用（Swift 无官方SDK），Claude Haiku 4.5 生成回答，效果自然、口语化
- [x] MVP 核心闭环打通：系统音频 → STT → end_of_turn 触发 LLM → 生成回答，全部验证成功（用 `say` 命令模拟面试官提问，回答自然、贴题）
- [x] 悬浮窗 UI：SwiftUI App（`App.swift`+`ContentView.swift`+`PipelineViewModel.swift`），常驻置顶显示实时问题+AI建议，验证可用
- [x] 麦克风 STT 接回主链路 + 对话历史：面试官(user)/我方(assistant)交替记录，追问时把完整历史发给 LLM（`ChatTurn`+`coalesce`合并连续同角色发言，避免 API 400），用户实测追问场景确认 AI 回答顾及了之前的发言
- [x] 打包成正式 .app：`InterviewAssistant.app`（ad-hoc签名，双击启动）。所有数据文件（profile.md/company_context.md/questions.md/interview_log.jsonl/.env）固定放到 `~/Documents/InterviewAssistant/`（不再用相对路径，双击app时当前目录不可靠）。项目文件夹里的旧文件已清理，唯一数据源就是这个固定目录
- [x] 个人信息投喂：`profile.md`（简历+待补充的Playbook/项目详情），启动时读取拼进system prompt，用 prompt caching（`cache_control: ephemeral`）降低重复调用成本
- [x] 面试问答记录：`interview_log.jsonl`，公司/岗位/轮次/问题/回答，每次麦克风识别到我的最终回答就记一条
- [x] few-shot 范例改为手动维护：不再自动取 `interview_log.jsonl` 最近N条，改为用户在 `profile.md` 的 "Best Answer Examples" 区块自己精选5条左右（`interview_log.jsonl` 的记录功能还在，只是不再自动拿来当范例）
- [x] 公司/岗位背景注入：UI新增"公司简介+为什么想加入"输入框，system prompt 改成每次提问时动态构建（company/position会变，profile.md部分不变时缓存仍命中）

## 语言约定
- UI文字/状态提示/代码注释：中文
- 面试问答内容（识别的问题、AI建议回答）：英文（systemPrompt 里约束）

- [x] 系统音频采集自动重连（锁屏/息屏等会中断 ScreenCaptureKit 流，中断后自动重试，最多5次）

## 已解决问题
- 麦克风"我方回答"识别不到：根因是 `swift run` 的 Ctrl+C 有时杀不干净进程，多个僵尸进程抢麦克风资源。加了独立诊断字段（`myStatus`/`micEngineStatus`/`micBufferCount`）定位到，之后 `pkill -f InterviewAssistant` 清理即可
- 没戴耳机时"你:"混入面试官说的话：acoustic bleed（喇叭声音被麦克风录回去），戴耳机后解决，符合预期，非代码bug

## 已修复问题（本轮）
- 窗口输入框无法输入：裸跑的 SwiftUI app 没有自动激活/拿到键盘焦点，加了 `NSApp.activate` + `makeKeyAndOrderFront`
- 多行输入框（公司简介）不显示：`TextField(axis: .vertical)` 渲染有问题，换成 `TextEditor`
- 回答被切成碎片记录：改成攒到下一个问题出现（或app退出）才合并成一条完整记录写入 `interview_log.jsonl`
- `interview_log.jsonl` 测试数据已清空
- 最后一条回答依赖"下一个问题/正常退出"才保存，不够可靠：加了静默5秒自动保存（不依赖后续事件）
- `company_context.md` 新增：公司专属信息（跟公司走，换公司要换文件），启动时自动读进"公司简介"输入框，跟 `profile.md`（跨公司通用）分开
- `profile.md` 补充了用户提供的 "Tell me about yourself"、EDI项目详情、真实回答范例
- `questions.md` 新增：预写好的问答对，问到就原文照抄（不改写），system prompt 里明确指示"完全匹配就逐字照搬"；同时兼职当风格参考（`profile.md` 的 Best Answer Examples 已清空，避免重复）
- UI 上的公司/岗位/轮次输入框去掉了，改成从 `company_context.md` 顶部的 `Company:`/`Position:`/`Round:` 结构化行解析（仍用于给 `interview_log.jsonl` 打标签）
- "原文照搬不改写"的规则从 `questions.md` 扩展到 `company_context.md`（比如"Why This Company"这段命中"为什么加入我们"类问题时也原文照搬）
- UI 简化：公司/岗位/轮次 + "公司简介"文本框都从界面上去掉了（改文件就行，不用在 UI 里重复编辑）
- 区分问题类型：行为类问题（讲经历/项目/动机）走口语化2-3句；技术定义类问题（GET和POST区别、idempotent是什么）走简洁直接、只答问到的部分，不额外扩展

## 已知限制
- ad-hoc 签名（没有付费Apple开发者证书）：每次重新打包，签名指纹都会变，系统会当作"新app"，之前的屏幕录制/麦克风权限会失效。重新打包后如果报权限错误，需要：`tccutil reset ScreenCapture com.hanmowang.interviewassistant` + `tccutil reset Microphone com.hanmowang.interviewassistant`，然后完全退出（Cmd+Q）重新打开app，重新走一遍系统权限弹窗
- 单窗口限制：已禁用 Cmd+N 新建窗口，且后台流水线（`start()`）加了防重复启动保护，避免多窗口/意外重复触发导致麦克风/系统音频被初始化两遍

## 备注
- Anthropic key 如果是 identity-linked 账号创建的，会报错要求 anthropic-workspace-id；换一个普通 key 即可
- AssemblyAI 要求单个音频包 50-1000ms，太小会被断开（close code 3007）；用 `PCMChunkAggregator` 攒够 100ms 再发
- Anthropic API 额度和 Claude.ai Pro 订阅是两套独立计费，充值后生效
- [ ] UI：悬浮窗显示问题+建议答案
- [ ] 打磨：延迟、回答自然度

## 当前状态
悬浮窗 UI 版本用户已验证正常（问题+回答都是英文，UI是中文）。下一步待定：麦克风识别接回主链路 / 打包成正式 .app。
