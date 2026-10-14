# AgentAsk 调用约定（可复制到 agent memory）

需要向用户提问时，可以调用本机 AgentAsk。用户回答后读取对应输出文件，再继续依赖该回答的工作。无需为使用这个提问工具重复征求确认，但必须遵守当前 agent 的运行权限；工具不会绕过平台的审批机制。

- WSL 入口：`/mnt/e/_Codex/AgentAsk/ask.py`（Windows：`E:\_Codex\AgentAsk\ask.py`）。依赖 Python 3.8+ 和 Windows PowerShell，WSL 需启用 Windows 互操作。
- 每次传入能识别自己的 `--agent` 名称。每个问题有独立 UUID、窗口和文件，不同 agent 可以并发调用。
- 推荐使用 `--detach`，保存 stdout JSON 中的 `request_id` 和 `response_file`。之后读取这个确切的文件；等待期间可以处理不依赖回答的工作。也可省略 `--detach` 等待完成，回答 JSON 将输出到 stdout，文件位置先输出到 stderr。
- 只把 `status == "answered"` 的 `answer` 视为用户回答；`cancelled`、`error` 或文件不存在均不是批准或默认选择。取消后不要立即重复弹窗。
- 问题包含复杂引号或多行文本时，先写 UTF-8 文件，用 `--question-file` 传入，避免 shell 插值。
- `ui.log` 位于同一请求目录。后台模式无超时保证；进程被强制结束时可能没有回答，需结合任务生命周期处理。
- 回答保存在工具目录下的 `requests/<request_id>/response.json`。不要用其他 agent 的文件或“最新文件”推断本次回答，不要未经用户指示清理其他请求。

```bash
# Windows 对应入口：E:\_Codex\AgentAsk\ask.py
python3 /mnt/e/_Codex/AgentAsk/ask.py --agent "自己的agent名称" --question "具体问题" --detach
```

Windows PowerShell 中可使用：

```powershell
python E:\_Codex\AgentAsk\ask.py --agent "自己的agent名称" --question "具体问题" --detach
```
