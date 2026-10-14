# AgentAsk

供本机 Windows / WSL agent 调用的提问工具。每次调用启动独立 Windows 窗口，使用独立 UUID 目录保存问题和回答；多个进程、多个 agent 可以同时调用，无需端口、服务或第三方 Python 包。

安装位置：`/mnt/e/_Codex/AgentAsk`（Windows：`E:\_Codex\AgentAsk`）。要求 Python 3.8+、Windows PowerShell 5.1 和已登录的交互式 Windows 桌面。WSL 需启用 Windows 程序互操作。调用进程需要能够写入工具的 `requests` 目录并启动 `powershell.exe`；agent 自身的沙箱权限仍需允许这些操作。

## 等待回答

WSL：

```bash
# Windows 对应入口：E:\_Codex\AgentAsk\ask.py
python3 /mnt/e/_Codex/AgentAsk/ask.py --agent "agent-planner" --question "这次优先处理哪个任务？"
```

Windows PowerShell（已安装 Python）：

```powershell
python E:\_Codex\AgentAsk\ask.py --agent "agent-planner" --question "这次优先处理哪个任务？"
```

程序立即将请求 ID 和文件位置写到 stderr，等待窗口提交或取消，然后把完整回答 JSON 写到 stdout。输出和文件均为 UTF-8。Enter 在回答框中换行，Ctrl+Enter 提交；Esc、Cancel 或关闭窗口记录为取消。空回答可以提交，状态仍为 `answered`。

退出码：`0` 已回答；`2` 已取消；`1` 错误；`130` 调用者中断。调用者中断不保证关闭已打开的窗口，窗口仍可能写出回答。

复杂问题可使用 `--question-file` 从 UTF-8 文本读取，避免把包含引号、换行或 shell 特殊字符的问题拼接进命令。`--question` 与 `--question-file` 只能选择一个。`--title` 可指定窗口标题；窗口标题始终包含 agent 名和请求 ID 前缀。

## 立即返回，之后读取文件

```bash
# Windows 对应入口：E:\_Codex\AgentAsk\ask.py
python3 /mnt/e/_Codex/AgentAsk/ask.py --agent "agent-coder" --question "请描述你希望的行为。" --detach
```

此模式把文件位置 JSON 写到 stdout，随后立即退出，窗口继续运行：

```json
{
  "request_id": "唯一的32位ID",
  "request_file": "…/requests/<ID>/request.json",
  "response_file": "…/requests/<ID>/response.json",
  "log_file": "…/requests/<ID>/ui.log"
}
```

保存本次返回的 `response_file` 并定期检查。文件存在时读取完整 JSON；不要扫描其他 agent 的目录或用“最近修改的文件”匹配回答。后台启动成功不代表用户已经回答。

## 文件协议

```text
requests/
  <request_id>/
    request.json      # schema_version、request_id、agent、title、question、created_at
    response.json     # 用户提交/取消后生成；错误时也可能生成
    ui.log            # Windows UI 进程的标准输出和错误
```

回答示例：

```json
{
  "schema_version": 1,
  "request_id": "唯一的32位ID",
  "agent": "agent-coder",
  "status": "answered",
  "answer": "先实现基础功能。",
  "answered_at": "2026-10-14T06:00:00.0000000Z"
}
```

所有时间使用 UTC。`status` 有 `answered`、`cancelled`、`error` 三种；取消或错误时 `answer` 为 `null`，错误另含 `error` 字段。**取消、错误、尚无回答都不代表同意。** 回答通过同目录临时文件重命名提交，避免读取到半个 JSON。文件会保留，便于追溯；不自动清理。

等待模式会监测 UI 进程退出，无回答时记录错误。后台模式下，如果 Windows 进程被强制结束、电脑关机或启动失败，可能一直没有回答文件；调用方应根据自己的任务生命周期检查日志或决定停止等待。本版没有自动超时。

## Python API

把工具目录加入 `sys.path` 后：

```python
from agentask import ask, start_question, read_response

result = ask("请选择下一步。", agent="agent-reviewer")
if result["status"] == "answered":
    print(result["answer"])

# 后台调用：保留元信息和进程对象，可继续做其他工作。
metadata, process = start_question("请提供补充信息。", agent="agent-reviewer")
result = read_response(metadata["response_file"])  # 暂无回答时返回 None
```

## 项目结构与扩展

```text
ask.py                  # 稳定的命令行入口
agentask/cli.py          # 参数与输出、退出码
agentask/service.py      # 请求存储、进程启动、Python API
ui/ask-window.ps1        # 原生 WinForms 窗口、回答落盘
tests/test_service.py   # 并发隔离与故障测试
tests/test-ui.ps1       # 自动提交/取消/关闭的真实窗口测试
MEMORY.md               # 可复制给其他 agent 的使用约定
```

本版未实现配置文件、总开关、置顶、超时或 UI 美化。后续可在 service 层增加配置和生命周期策略，在 UI 层独立调整布局，保持入口和 JSON 协议稳定。

测试（在项目根目录运行）：

```bash
python3 -m unittest discover -s tests -v
```

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\test-ui.ps1
```

窗口测试会短暂打开三个窗口并自动关闭，不需要人工输入。
