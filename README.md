# BattMate — 远程 Mac 电池监控菜单栏应用

在菜单栏常驻显示另一台 Mac 的充电状态，充电器断开 / 电量过低 / SSH 失联时弹系统通知。

## 功能

- 菜单栏图标：`⚡98` 绿（电源供电）/ `🔋45` 橙（电池供电）/ `⚠︎--` 灰（失联，1~2 次失败时闪烁）
- 告警：断电、低电量（默认 ≤20%）、SSH 连续 3 次失败、恢复充电
- 轮询 15~300 秒可调（默认 30 秒），SSH 连接复用（ControlMaster），主力机睡眠时自动暂停
- 开机自启动、状态落盘 `~/Library/Application Support/BattMate/status.json`（为将来小组件预留）

## 构建（仅需 Command Line Tools，无需 Xcode/SwiftPM）

```bash
./test.sh    # 跑全部单元测试
./build.sh   # 产物: build/BattMate.app（arm64 + x86_64 universal）
```

## 部署到监控机（如 M5 MacBook）

1. 把 `build/BattMate.app` 拷贝到目标机（AirDrop / U 盘 / scp 均可），拖入「应用程序」
2. 首次打开：右键 → 打开 → 再点「打开」（未公证 app 的 Gatekeeper 流程）
3. 首次启动会自动弹出设置窗口：
   - 填入服务器机的 SSH 目标（如 `ya@192.168.1.50`）
   - 点「测试连接」；若失败，按窗口里给出的命令在终端执行 `ssh-copy-id <目标>` 配置免密登录，再测
4. 保存后菜单栏即开始显示；建议勾选菜单里的「开机自启动」

## 数据文件

| 文件 | 路径 | 说明 |
|---|---|---|
| 配置 | `~/Library/Application Support/BattMate/config.json` | SSH 目标、间隔、阈值 |
| 状态 | `~/Library/Application Support/BattMate/status.json` | 最新一次检测结果 |
| 日志 | `~/Library/Application Support/BattMate/logs/battmate.log` | 每次检测与告警 |

## 故障排查

- 图标一直灰色 `⚠︎--`：先在终端手动 `ssh <目标> pmset -g batt` 验证；Permission denied → 执行 `ssh-copy-id <目标>`
- 通知不弹：系统设置 → 通知 → BattMate → 允许通知
- 服务器机要求：无需安装任何东西（`pmset` 系统自带，免 sudo）

## 测试

```bash
./test.sh
```
