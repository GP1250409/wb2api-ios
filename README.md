# WB2API iOS

[![CI](https://github.com/chenyynx/wb2api-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/chenyynx/wb2api-ios/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-iOS%2026%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

[WorkBuddy2API](https://github.com/misakano7545/workbuddy2api-panel) 面板的 **iOS 原生客户端**。SwiftUI + Swift 6 零第三方依赖，面向 iOS 26（Liquid Glass），紫色 `#7C5CFF` 单强调色。

> 后端是独立的 Go 面板项目（账号池网关 + 运维面板），本 App 只做客户端——通过面板的 HTTP API 管理账号池，不直接接触上游。

## 功能

| 模块 | 说明 |
|---|---|
| **概览** | 健康度环、今日消耗 tokens、模型锁池（限流状态与解锁倒计时）、批量签到/巡检/上报/保活、24h 用量趋势（可按住拖动逐小时查看） |
| **账号** | 搜索/筛选、状态（可用/冷却/禁用）与恢复倒计时、20s 自动刷新、详情（用量/模型成本/到期/最近错误）、单号操作（签到/余额/旅行/暂停/禁用/复活/移除）、**模型开关**（按账号启停模型） |
| **任务** | 扫描全部账号成长任务、逐账号/逐任务勾选执行（账号间并发、账号内串行）、队列状态与逐项明细、暂停队列、单任务直接执行（接受→执行→回读→领奖全自动） |
| **数据** | 用量区间统计（3 天/7 天/30 天/总计，B/M 大数）、按账号/模型/域聚合、积分历史（刷新即同步上游余额）、余额趋势折线 |
| **模型** | 模型目录（82+）、能力字段、按账号探测 |
| **日志** | 实时日志流（系统/对话/任务三频道，5s 轮询）、请求指标、错误汇总（限流恢复倒计时） |
| **资源** | 礼包明细（含到期）、开学季券码（点码复制）、补偿一键领取 |
| **系统** | 面板全字段配置（原生表单 + JSON 编辑，回显需重启字段）、扫码授权登录 + API Key 直加、Cockpit 账号批量导入、服务器/密钥管理 |

## 后端

本客户端依赖 [workbuddy2api-panel](https://github.com/misakano7545/workbuddy2api-panel)（Go）提供的面板 API。部署面板后：

1. 打开 App → 设置 → 填入面板地址（默认 `https://panel.example.com`）与 `api_key`（面板 `config.json` 中的 `api_key`）；
2. App 全部请求走 `Authorization: Bearer <api_key>`，`401` 统一弹密钥修正。

接口清单以面板源码 `internal/panel/panel.go` 的路由注册为准（47 个端点）；App 侧唯一入口是 [`WB2API/Core/APIClient.swift`](WB2API/Core/APIClient.swift)。测试夹具由真实响应脱敏生成，App 模型与后端契约有对拍脚本兜底（见下文「模型对拍」）。

> 面板自身的部署、账号池、上游网关等问题请到面板仓库提问。

## 构建

工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成，不提交 `.xcodeproj`：

```bash
brew install xcodegen
xcodegen generate
open WB2API.xcodeproj   # Xcode 26+，iPhone 模拟器直接跑
```

命令行：

```bash
xcodebuild test -project WB2API.xcodeproj -scheme WB2API \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## 安装包

CI 每次 push 自动跑双 job：**模拟器单测** + **无签名 IPA**。到 [Actions](https://github.com/chenyynx/wb2api-ios/actions) 最新绿色 run 下载 `WB2API-unsigned-ipa` artifact，用全能签 / SideStore / AltStore 等侧载工具重签安装。

- Bundle ID：`org.example.wb2api`
- 最低系统：iOS 26.0（用了 `.glassEffect` 等 iOS 26 API，不支持降级）

## 测试

40+ 用例，三套：

- **模型解码**：真实接口响应夹具（已脱敏），含模型锁、手动关模型等回归
- **格式化**：数字/积分/大数 tokens/时间/倒计时
- **APIClient**：鉴权头、401 映射、错误分型、取消静默（URLProtocol 桩）

`tools/` 下的脚本：

| 脚本 | 用途 |
|---|---|
| `check_models.py` | 模型 ↔ 真实响应逐字段对拍（防「键名不匹配静默 nil」回归） |
| `sanitize_fixtures.py` | 把抓包响应脱敏成测试夹具 |
| `make_icon_v3.py` | 重新生成 App 图标 |
| `patch_*.py` | 面板侧补丁（暂停队列 / model_off 字段），对应面板仓库使用 |

## 设计

- 设计规范：[docs/brand-spec.md](docs/brand-spec.md)
- 颜色唯一来源：[`WB2API/Design/DesignTokens.swift`](WB2API/Design/DesignTokens.swift)
- 动效 token：[`WB2API/Design/Motion.swift`](WB2API/Design/Motion.swift)（全部带 `value:`，尊重「减弱动态效果」）
- 结构：`Core`（网络/模型/会话）· `Design` · `Components` · `Features/*`（概览/账号/任务/数据/模型/日志/资源/配置/登录/设置），一类型一文件

## 隐私

- `api_key` 只存本机 **Keychain**，地址存 UserDefaults；
- 仓库与测试夹具不含任何真实凭据，夹具由脚本脱敏生成；
- App 不做任何统计/上报，只与你自己部署的面板通信。

## License

MIT
