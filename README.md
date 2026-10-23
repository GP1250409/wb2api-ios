# WorkBuddy2API · iOS

WorkBuddy2API 面板的原生 iOS 客户端。SwiftUI，零第三方依赖，iOS 18+。

## 能做什么

把面板的全部 47 个接口搬进原生界面：

- **概览**：账号池健康度环、积分到期、批量签到 / 巡检 / 上报 / 保活
- **账号**：列表（搜索 / 筛选 / 滑动操作）、详情（用量 / 模型成本 / 限流 / 最近错误）、单号全部操作
- **任务**：队列状态、扫描全部、执行队列、任务作业
- **数据**：用量统计（按账号 / 模型 / 域）、积分历史、余额趋势（Swift Charts）
- **模型**：目录、探测、能力字段
- **日志**：实时日志流、请求日志与指标、错误汇总
- **礼包**：礼包明细、券码、补偿
- **配置**：全字段原生表单 + JSON 高级编辑
- **登录**：区域选择、授权链接、轮询取凭据

## 设计与实现

设计遵循 `swiftui-design-skill`：单一暖色强调（赤陶 `#C2542F`）、暖调中性色、New York 衬线标题、8pt 间距网格、SF Symbols、每屏一个 signature detail。全部使用系统原生组件，无自绘控件。

- 设计规范：[docs/brand-spec.md](docs/brand-spec.md)
- 颜色唯一来源：`WB2API/Design/DesignTokens.swift`
- 动效 token：`WB2API/Design/Motion.swift`（全部带 `value:`，尊重减弱动态效果）

## 构建

工程由 XcodeGen 生成，不提交 `.xcodeproj`：

```bash
brew install xcodegen
xcodegen generate
open WB2API.xcodeproj
```

## 单元测试

```bash
xcodebuild test -project WB2API.xcodeproj -scheme WB2API \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

覆盖：模型解码（真实接口响应夹具，已脱敏）、格式化、APIClient（鉴权头、401 映射、错误分型、路径与查询参数）。

## 安装包

CI 会产出未签名 IPA（`WB2API-unsigned-ipa` artifact），用全能签 / SideStore 等侧载工具重签安装。

## 隐私

`api_key` 只存本机 Keychain；仓库内不含任何真实凭据，测试夹具中的账号与密钥均已脱敏。
