# AgentAsk 调用约定（可复制到 agent memory）

需要向用户提问时，可以调用本机 AgentAsk。用户回答后读取对应输出文件，再继续依赖该回答的工作。无需为使用这个提问工具重复征求确认，但必须遵守当前 agent 的运行权限；工具不会绕过平台的审批机制。

- WSL 入口：`/mnt/e/_Codex/AgentAsk/ask.py`（Windows：`E:\_Codex\AgentAsk\ask.py`）。依赖 Python 3.8+ 和 Windows PowerShell，WSL 需启用 Windows 互操作。
- 每次传入能识别自己的 `--agent` 名称。每个问题有独立 UUID、窗口和文件，不同 agent 可以并发调用。
- 默认使用同步模式（不加 `--detach`），等待用户提交、取消、配置超时或禁用后再继续。工具调用返回“进程仍在运行”只是本次轮询结束，不代表用户回答超时；保留会话 ID 并持续等待原进程，不要因为过了 30 秒或 1 分钟就结束聊天回合、停止读取或重新弹窗。
- 用户思考期间可以处理不依赖回答的工作。只有需要并行工作时才使用 `--detach`，并保留 stdout JSON 中的 `request_id` 和 `response_file`，持续检查这个确切的文件。除非用户明确要求“只打开，不用等待”或取消等待，否则不能用“窗口已打开”代替读取结果并结束本轮工作。
- 等待时可用不超过 60 秒的单次轮询保持可响应性；单次轮询时长不是回答期限。只有用户配置的超时或明确的新指令可以结束正常等待，不要自行设定一分钟限制。
- 只把 `status == "answered"` 的 `answer` 视为用户回答；`cancelled`、`error`、`disabled`、`timed_out` 或文件不存在均不是批准或默认选择。取消后不要立即重复弹窗。
- `disabled` 表示用户已停用 AgentAsk：停止该提问流程，不等待、不重复调用，不自行开启配置或改用其他弹窗。按现有信息推进可独立完成的工作；真正需要用户授权的操作仍必须等待明确授权。
- `timed_out` 的 `answer` 为 `[无回答]`，这是自动生成的超时标记，不是用户的回答或批准。不要立即重新弹窗。
- 配置位置：`/mnt/e/_Codex/AgentAsk/config.json`（Windows：`E:\_Codex\AgentAsk\config.json`）。用户在齿轮面板保存的设置会持久化；禁用后由用户手动把 `behavior.enabled` 改回 `true` 才恢复。
- 同步 CLI 退出码：0 已回答、1 错误、2 取消、3 禁用、4 超时。`--detach` 处理成功时返回 0；禁用时元信息带 `status: "disabled"`，回答文件已存在。
- 问题包含复杂引号或多行文本时，先写 UTF-8 文件，用 `--question-file` 传入，避免 shell 插值。
- `ui.log` 位于同一请求目录。可配置窗口回答超时；窗口进程被强制结束时仍可能没有回答，需结合任务生命周期处理。
- 回答保存在工具目录下的 `requests/<request_id>/response.json`。不要用其他 agent 的文件或“最新文件”推断本次回答，不要未经用户指示清理其他请求。

```bash
# Windows 对应入口：E:\_Codex\AgentAsk\ask.py
python3 /mnt/e/_Codex/AgentAsk/ask.py --agent "自己的agent名称" --question "具体问题"
```

Windows PowerShell 中可使用：

```powershell
python E:\_Codex\AgentAsk\ask.py --agent "自己的agent名称" --question "具体问题"
```
