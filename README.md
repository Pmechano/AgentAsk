# AgentAsk

供本机 Windows / WSL agent 调用的提问工具。每次调用启动独立 Windows 窗口，使用独立 UUID 目录保存问题和回答；多个进程、多个 agent 可以同时调用，无需端口、服务或第三方 Python 包。

安装位置：`/mnt/e/_Codex/AgentAsk`（Windows：`E:\_Codex\AgentAsk`）。要求 Python 3.8+、Windows PowerShell 5.1 和已登录的交互式 Windows 桌面。WSL 需启用 Windows 程序互操作。调用进程需要能够写入工具的 `requests` 目录并启动 `powershell.exe`；agent 自身的沙箱权限仍需允许这些操作。

## 界面

宽六边形 WPF 窗口采用黑色描边、浅色面板和薄荷色边缘流光。顶部显示 agent 名称，也可拖动窗口；问题可选择、复制和滚动；回答框支持多行。底部左侧“取消”、右侧“提交”，没有额外关闭图标。

左侧齿轮打开偏好设置，修改后点击“保存并应用”持久化到配置文件。动画使用 WPF 原生属性动画（30 FPS 上限），默认尊重 Windows 的客户端区域动画设置；关闭窗口会停止动画。窗口尺寸会按桌面工作区缩小以适应小屏幕。

设置面板的尺寸、文字和控件统一放大至原版的 1.2 倍，不更改个人配置中的主窗口缩放或正文字号。

布局在 `ui/window.xaml`，样式在 `ui/theme.xaml`，事件和原子文件写入在 `ui/ask-window.ps1`。调用入口与并发模型保持兼容；配置版新增 `disabled` 和 `timed_out` 状态，调用者需处理它们。

## 配置

本地配置：`/mnt/e/_Codex/AgentAsk/config.json`（Windows：`E:\_Codex\AgentAsk\config.json`）。UTF-8 JSON，不支持注释。`config.defaults.json` 是纳入 Git 的默认模板；个人 `config.json` 和问答记录不纳入 Git。

| 分组 | 名称 | 字段 | 默认值 / 范围 |
|---|---|---|---|
| 外观 | 窗口缩放 | `appearance.window_scale` | `1.0`，允许 0.7–1.5 |
| 外观 | 正文字号 | `appearance.font_size` | `16`，允许整数 12–28 |
| 外观 | 边框流光 | `appearance.edge_animation` | `true` |
| 行为 | 启用 AgentAsk | `behavior.enabled` | `true` |
| 行为 | 窗口置顶 | `behavior.topmost` | `false` |
| 行为 | 回答超时 | `behavior.timeout_enabled` | `false` |
| 行为 | 等待时长（秒） | `behavior.timeout_seconds` | `120`，允许整数 1–86400 |

窗口缩放按比例改变整个界面，超过桌面工作区时自动缩小；正文字号调整回答框及问题正文，问题字号比回答大 4。流光也尊重 Windows 的客户端区域动画设置。

每次调用重新读取配置。设置面板保存后，对当前窗口和后续新窗口生效；其他已打开窗口保留原来的外观与超时设置。不同窗口保存时，在互斥锁内合并各自修改的字段；同一字段以最后保存为准。仅关闭面板或按 Esc 不会保存修改。

关闭“启用 AgentAsk”并保存后，当前及其他仍在等待的窗口会关闭并记录 `disabled`，后续调用不启动 Windows 界面、不等待用户，立即写出 `disabled` 响应。要恢复，请手动把 `config.json` 的 `behavior.enabled` 改为 `true`；agent 不应自行修改该开关，也不应在禁用后自动换其他弹窗重复追问。

“回答超时”从窗口首次显示后计时；到时保存 `status: "timed_out"`、`answer: "[无回答]"` 并关闭。输入中的未提交文字不会自动提交，输入和打开设置面板不会暂停倒计时。修改超时开关或等待时长并保存会重新计时，单纯更改外观不会重置计时。提前提交或取消的结果不会被超时覆盖。倒计时采用单调时钟，由 UI 消息循环检查；系统繁忙时可能稍晚关闭。

缺失字段从默认模板补齐；缺失整个配置文件会使用默认值。格式错误、未知字段或越界值会报错，不会擅自重置文件。正在运行的窗口遇到配置错误会保留其已加载设置并记日志。

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

程序立即将请求 ID 和文件位置写到 stderr，等待窗口提交或取消，然后把完整回答 JSON 写到 stdout。输出和文件均为 UTF-8。Enter 在回答框中换行，Ctrl+Enter 提交；底部左侧“取消”、Esc 或系统关闭操作记录为取消。设置面板打开时，Esc 先收起面板。空回答可以提交，状态仍为 `answered`。

agent 默认应保持同步等待。运行工具一次只等待数十秒并返回进程会话 ID 时，应继续等待同一进程；这不是 AgentAsk 的超时。回答超时关闭时没有一分钟的自动结束限制。除非用户明确要求只打开窗口或停止等待，否则应读取最终回答后再结束聊天回合；后台模式也遵守此约定。

退出码：`0` 已回答；`2` 已取消；`3` 已禁用；`4` 已超时；`1` 错误；`130` 调用者中断。调用者中断不保证关闭已打开的窗口，窗口仍可能写出回答。

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

保存本次返回的 `response_file` 并定期检查。文件存在时读取完整 JSON；不要扫描其他 agent 的目录或用“最近修改的文件”匹配回答。后台启动成功不代表用户已经回答。禁用时该命令仍立即返回文件位置，另带 `status: "disabled"`，对应响应文件已经存在；后台模式退出码 0 只代表该调用已被处理。

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

所有时间使用 UTC。`status` 有 `answered`、`cancelled`、`error`、`disabled`、`timed_out` 五种；取消、禁用或错误时 `answer` 为 `null`，超时时为 `[无回答]`，错误另含 `error` 字段。**只有 `answered` 是用户主动提交；自动超时、禁用、取消或缺失响应都不代表批准。** 回答通过同目录临时文件重命名提交，避免读取到半个 JSON。文件会保留，便于追溯；不自动清理。

等待模式会监测 UI 进程退出，无回答时记录错误。后台模式下，如果 Windows 进程被强制结束、电脑关机或启动失败，可能一直没有回答文件；调用方应根据自己的任务生命周期检查日志或决定停止等待。配置超时由窗口进程负责，进程被强制结束时无法保证生成超时响应。

## Python API

把工具目录加入 `sys.path` 后：

```python
from agentask import ask, start_question, read_response

result = ask("请选择下一步。", agent="agent-reviewer")
if result["status"] == "answered":
    print(result["answer"])

# 后台调用：保留元信息和进程对象，可继续做其他工作。
metadata, process = start_question("请提供补充信息。", agent="agent-reviewer")
result = read_response(metadata["response_file"])  # 暂无回答时返回 None；禁用时已有响应
# 禁用时 process 为 None；可先检查 metadata.get("status") == "disabled"。
```

## 项目结构与扩展

```text
ask.py                  # 稳定的命令行入口
agentask/cli.py          # 参数与输出、退出码
agentask/service.py      # 请求存储、进程启动、Python API
agentask/config.py       # 配置加载与校验
config.defaults.json     # 默认配置模板
config.json              # 本地用户设置（Git 忽略）
ui/ask-window.ps1        # WPF 窗口事件、动画与回答落盘
ui/window.xaml          # 六边形布局
ui/theme.xaml           # 颜色、按钮与输入框样式
ui/settings.ps1         # 设置保存、合并、应用与倒计时
tests/test_service.py   # 并发隔离与故障测试
tests/test-ui.ps1       # 自动提交/取消/关闭的真实窗口测试
tests/test-settings.ps1 # 持久化、禁用、超时与竞态测试
MEMORY.md               # 可复制给其他 agent 的使用约定
```

布局、样式、持久化配置与调用协议分别维护，方便后续扩展。

测试（在项目根目录运行）：

```bash
python3 -m unittest discover -s tests -v
```

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\test-ui.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\test-settings.ps1
```

窗口测试会短暂打开测试窗口并自动关闭，不需要人工输入，且只读写独立临时配置。
