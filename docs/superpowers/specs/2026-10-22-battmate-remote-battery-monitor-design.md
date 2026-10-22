# BattMate — 远程 Mac 电池监控菜单栏应用 设计文档

日期：2026-10-22
状态：已确认（用户批准）

## 背景

用户有两台 Mac：一台合盖当 SSH 服务器用，另一台主力机。服务器机的充电器接触不良，经常在无人察觉时断开，机器靠电池运行直至耗尽关机，SSH 服务随之中断。需求：在主力机上实时看到服务器机的充电状态，断电时及时提醒。

## 调研结论（2026-10-22）

- GitHub 上没有「跨 Mac 监控充电状态 + 通知中心小组件」的现成开源方案。
- 相关生态：iStat Server/View（商业，形态不符）；若干本机电池 WidgetKit 小组件（可参考代码，不支持跨机）；MQTT→Home Assistant 桥（依赖过重）；社区通用取数方式为 `ssh <机> pmset -g batt`（免 sudo）。
- 关键技术约束：
  1. WidgetKit 通知中心小组件刷新频率受系统预算限制（约 15~60 分钟一次），无法及时发现断电；
  2. 通知中心小组件开发基本必须 Xcode（主力开发机未装，约 7GB+ 下载不现实）；
  3. 菜单栏 app 用 Command Line Tools + SwiftPM 即可构建，轮询可做到秒级。

## 已确认的决策

| 决策点 | 结论 |
|---|---|
| 断电后远端行为 | 服务器机继续运行直到电量耗尽（SSH 持续可达，`pmset` 可精确读到放电状态） |
| 展示形态 | 菜单栏图标（非通知中心小组件，原因见调研约束） |
| 使用环境 | 编译 universal 二进制（arm64+x86_64），部署到 M5 芯片新机；最低兼容 macOS 13 |
| 实现方案 | 方案 A：Swift 原生，swiftc 直编（CLT 14.3.1 的 SwiftPM 存在无法修复的 PlatformPath 构建缺陷且无 CLT 升级可用，已实测 swiftc + CLT SDK 编译 AppKit 正常），零第三方依赖 |
| SSH 免密 | 应用内提供「测试连接」与 `ssh-copy-id` 引导，不阻塞开发 |
| 应用名 | BattMate（可改） |

## 架构

单进程菜单栏应用（LSUIElement，无 Dock 图标）：

```
┌─ 主力 Mac ─────────────────────────────┐
│  BattMate.app                          │
│   ├─ PollScheduler     定时触发轮询     │
│   ├─ SSHBatteryReader  ssh 取数+解析    │
│   ├─ AlertEngine       状态机→告警      │
│   ├─ StatusBarUI       图标+菜单        │
│   └─ SettingsStore     配置持久化       │
└──────────────┬─────────────────────────┘
               │ SSH（ControlMaster 复用，BatchMode）
┌──────────────▼─────────────────────────┐
│ 服务器 Mac — pmset -g batt（系统自带）    │
└────────────────────────────────────────┘
```

### 组件

1. **SSHBatteryReader**
   - 执行：`ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlMaster=auto -o ControlPath=<sock> -o ControlPersist=60 <target> pmset -g batt`
   - 解析输出：电源来源（`AC Power` / `Battery Power`）、电量百分比、`charging` / `discharging` / `charged`、剩余时间。
   - 失败返回 `.error`（区分超时/非零退出）。

2. **PollScheduler**
   - 默认 30 秒（可配 15~300 秒）；提供「立即刷新」。
   - 监听 NSWorkspace 睡眠/唤醒通知：睡眠暂停，唤醒立即补测。

3. **AlertEngine**（状态机）
   - 状态：`charging(AC)` / `onBattery` / `unreachable` / `unknown`。
   - 切换防抖（2026-10-22 用户批准，针对充电器接触不良抖动）：电源来源切换需**连续 2 个同源样例**才确认并发告警（断电与恢复充电同规则，约增加 1 个轮询周期的告警延迟）；失联恢复（reachableAgain）与失败计数不防抖。
   - 转换触发（UNUserNotificationCenter 本地通知，回退 `osascript display notification`；可选声音；同状态只报一次，状态恢复后重置）：
     - AC→Battery：⚠️ 服务器机充电器断开
     - onBattery 且电量 ≤ 阈值（默认 20%，可配）：🟠 低电量
     - 连续 3 次连接失败：⚫ SSH 不可达；连续失败计数在任一次成功后清零
     - Battery→AC：🟢 已恢复充电

4. **StatusBarUI**
   - 图标文本：`⚡98`（绿）/ `🔋45`（橙）/ `⚠︎--`（灰）。
   - 菜单：状态详情（来源/电量/剩余时间/最后检测时间）、立即刷新、设置…、开机自启（勾选）、退出。

5. **SettingsStore**
   - 路径：`~/Library/Application Support/BattMate/config.json`。
   - 字段：sshTarget、intervalSeconds、lowBatteryThreshold、soundEnabled、autostart。
   - 设置窗口：SwiftUI Form；「测试连接」按钮执行一次真实取数，失败时展示可复制的 `ssh-copy-id <target>` 引导。
   - 文件损坏时回落默认值并重建。

## 数据流

```
Timer tick → SSHBatteryReader.fetch() → PowerState(来源,电量,状态,剩余时间)
          → AlertEngine.evaluate(previous, current) → 本地通知 + 可选声音
          → StatusBarUI.update(图标/菜单)
```

## 错误处理

- SSH 超时/非零退出：计入连续失败计数，达到 3 次判失联；期间图标变灰闪烁。
- pmset 输出解析失败：保留上次显示状态，日志追加到 `~/Library/Application Support/BattMate/logs/battmate.log`。
- 主力机睡眠：轮询暂停，唤醒后立即补测。

## 打包与部署

- `build.sh`：`swiftc` 编译 universal（`--arch arm64 --arch x86_64`）→ 生成最小 `.app`（Info.plist 含 LSUIElement）→ ad-hoc codesign。
- 部署：拷贝 `.app` 到 M5 新机「应用程序」，首次右键打开（未公证）；开机自启用 SMAppService（macOS 13+）。

## 测试

- 单元测试（自建轻量断言运行器 `Tests/main.swift`，`./test.sh` 一键编译运行，失败退出码非 0）：pmset 输出解析（AC/电池/充电中/放电中/剩余时间/异常格式）、AlertEngine 状态转换矩阵。
- 集成联调：对 `ssh localhost` 验证 SSH 层；真机拔充电器验证 AC→Battery→低电量→恢复 全链路。

## 明确不做（YAGNI）

- 通知中心小组件（电力状态会落盘 JSON，未来装 Xcode 后可加 WidgetKit target）
- 多台服务器机监控（配置结构预留数组形态）
- 历史曲线 / 日志查看 UI
- 远端控制（阻止睡眠、关机等）
