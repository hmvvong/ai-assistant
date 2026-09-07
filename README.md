# AI Assistant

A personal macOS interview assistant. It transcribes the interviewer's speech in real time and, using your own background info, instantly generates natural, conversational answer suggestions.

## Features

- Dual audio capture: system audio (interviewer) + microphone (you), via ScreenCaptureKit + AVAudioEngine
- Real-time speech-to-text: AssemblyAI Universal-Streaming
- Answer generation: Claude Haiku, with personal background + company context + preset Q&A examples injected
- Floating always-on-top window showing the live question and suggested answer
- Interview logging, tagged by company/position/round

## Structure

- `InterviewAssistant/` — Swift Package, main app source
- `plan.txt` — project feasibility analysis
- `PROGRESS.md` — development log and technical decisions

## Run

```bash
cd InterviewAssistant
./run.sh
```

Requires AssemblyAI and Anthropic API keys in `InterviewAssistant/.env` (not committed to the repo).

Profile, company context, and interview logs are stored under `~/Documents/InterviewAssistant/`.

## Note

Built for personal use only, not intended as a general-purpose tool.
