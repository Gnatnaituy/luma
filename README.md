# Luma

Luma 是一款轻量、原生的 macOS 工具启动器，使用 Swift、SwiftUI、AppKit 与系统框架构建。

项目不包含 Electron、Chromium、WebView 或 JavaScript 运行时，目标是在保持低 CPU、低内存占用的同时，让常用工具随时可达。

## 核心体验

- 默认按 `⌥ Space` 唤起或隐藏浮动面板。
- 空白首页只展示搜索框与最近使用记录。
- 输入后统一搜索插件、macOS App、Spotlight 文件、Quicklinks、片段与算式。
- 选中插件后直接展示有效内容，不保留插件侧边栏或介绍区域。
- 支持方向键选择、`Enter` 执行、`Esc` 返回，以及右方向键展开结果操作。
- 面板自动出现在当前聚焦屏幕，并记住本次运行期间的位置与各页面高度。
- 可为不同关键词绑定独立全局快捷键；唯一命中时直接进入对应插件。

首页最近使用支持两种布局：

- 竖向：插件与 App 共用最近 9 条记录。
- 横向：插件和 App 分行展示，各自最多 15 条。

## 搜索能力

### App 与文件

Luma 启动后会在后台低优先级扫描标准 Applications 目录，为本机 App 建立轻量索引。

文件搜索使用 macOS Spotlight 元数据索引。搜索结果支持打开、复制路径，以及在 Finder 中显示。

### 结果操作

在搜索结果中按右方向键可展开操作栏，也可以使用鼠标右键打开上下文菜单。

不同类型的结果可执行打开、复制、粘贴或 Finder 定位等操作。

### Quicklinks

Quicklinks 可通过关键词打开 URL、文件或文件夹，并支持动态占位符：

| 占位符 | 内容 |
| --- | --- |
| `{query}` | Quicklink 关键词后的输入 |
| `{clipboard}` | 当前剪贴板文本 |
| `{selectedText}` | 唤起 Luma 前选中的文本 |
| `{date}` | 当前 ISO 8601 时间 |

例如：

```text
名称：GitHub 搜索
关键词：gh
模板：https://github.com/search?q={query}
```

输入 `gh native swift` 后即可打开对应搜索结果。

## 内置插件

| 插件 | 功能 |
| --- | --- |
| 剪贴板 | 文本、图片、文件和链接历史；搜索、过滤、收藏与粘贴 |
| 计算器 | 安全解析四则运算、括号、幂和常用函数；保存最近 15 条记录 |
| JSON 编辑器 | 语法高亮、格式化、压缩、校验、转义与去转义 |
| 随机密码 | 使用系统安全随机数生成 6–32 位密码 |
| 翻译 | Apple 系统翻译或自定义 AI 模型翻译 |
| 编码小助手 | Base64、URL 编解码和 SHA-256 |
| 股票盯盘 | A 股、港股、美股查询及分时、五日和 K 线走势 |
| 天气 | 多地点天气、逐小时预报与七日预报 |
| Quicklinks | 关键词驱动的 URL、文件和自定义搜索 |
| 片段 | 保存常用文本，从主搜索直接粘贴 |
| 窗口管理 | 左半屏、右半屏、最大化和居中布局 |

## 剪贴板

### 记录与操作

剪贴板支持文本、图片、文件、链接和收藏分类，并提供插件内搜索。

- 单击条目立即选中。
- 双击条目会隐藏 Luma，恢复唤起前的窗口并发送 `⌘V`。
- 上下方向键选择条目，左右方向键切换分类，`Enter` 粘贴当前条目。
- 图片可在列表内展开，也可直接交给 macOS Preview 查看。
- 文本、链接和文件提供复制、收藏、删除等操作。

### 去重规则

- 文本和链接执行全局去重。
- 再次复制已有文本或链接时，旧记录会移动到顶部并刷新时间。
- 合并重复记录时保留收藏状态。
- 文件仅避免连续重复记录。
- 图片内容按 SHA-256 去重，相同图片只保存一份文件。

### 保留与存储

默认保存最近 3 个月，可改为 3 天、7 天、1 个月、3 个月、6 个月或 1 年。

收藏记录不受自动过期限制。图片达到容量上限后，会优先清理最旧的未收藏图片。

剪贴板每 0.8 秒检查一次 `changeCount`，定时器包含 0.25 秒 tolerance，空闲时不会持续读取完整内容。

## 股票与天气

### 股票

支持以下代码形式：

```text
600115.SS
002594.SZ
0700.HK
AAPL
```

走势图包含分时、五日、日 K、周 K 和月 K。分时图使用固定的 `09:15–15:30` 时间范围。

行情源支持自动容灾，也可以手动选择腾讯财经、东方财富或新浪财经。应用不会下载全市场数据，也不会在后台轮询。

### 天气

天气支持多个地点、逐小时预报和七日预报。

数据源支持自动容灾，也可以手动选择 Open-Meteo、MET Norway、中国气象局或中央气象台。

## 翻译与 AI

翻译插件支持 Apple Translation 和自定义 AI 模型。

唤起 Luma 后，翻译会优先读取原 App 中选中的文本；没有选中文本时，再读取剪贴板文本。

输入中文时默认翻译为英语，输入其他语言时默认翻译为简体中文。按 `Enter` 翻译，按 `Shift Enter` 换行。

AI 管理支持：

- 自定义供应商名称与 Base URL。
- OpenAI Chat Completions 和 Anthropic Messages 格式。
- 多模型及上下文窗口配置。
- 供应商启用、停用和连接测试。

API Key 保存在 macOS 钥匙串，不写入 UserDefaults，也不会包含在配置备份中。

## 设置与系统集成

设置页面采用左侧分类、右侧内容的双栏结构，包含：

- 应用设置
- 快捷键管理
- 插件关键词管理
- 剪贴板设置
- AI 管理
- 翻译设置
- 股票设置
- 天气设置

应用设置支持菜单栏图标、最近使用布局、登录时启动，以及配置导入和导出。

插件关键词管理可以启用或停用插件，并修改或新增每个插件的搜索关键词。

## 权限

Luma 只在使用对应功能时请求系统权限。

| 权限 | 用途 |
| --- | --- |
| 辅助功能 | 双击粘贴、读取选中文本、恢复目标窗口和窗口管理 |
| 钥匙串 | 保存并读取 AI API Key |
| 登录项 | 登录 macOS 后自动启动 Luma |

全局唤起快捷键使用 Carbon Hot Key，本身不需要辅助功能权限。

辅助功能授权与应用的代码身份和安装路径相关。日常运行请保持使用 `/Applications/Luma.app`。

## 环境要求

- macOS 14.4 或更高版本
- Apple Silicon
- Swift 5.10 工具链

## 构建

```bash
cd /path/to/luma
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

构建产物位于：

```text
dist/Luma.build
```

`Luma.build` 使用稳定的本地 designated requirement 签名，但不会作为另一个 `.app` 被 LaunchServices 收录。

## 安装与启动

推荐始终使用安装脚本：

```bash
chmod +x scripts/install-app.sh
./scripts/install-app.sh
```

安装脚本会：

1. 执行 Release 构建和固定代码身份签名。
2. 停止正在运行的 Luma。
3. 在 `/Applications` 创建并验证暂存副本。
4. 原子替换 `/Applications/Luma.app`。
5. 重新注册 LaunchServices 并启动新版本。

替换失败时，脚本会恢复上一版本。

## 测试

```bash
chmod +x scripts/test-core.sh
./scripts/test-core.sh
```

测试脚本使用 Swift Package Manager 运行完整 Swift Testing 测试套件，不下载第三方依赖。

也可以直接运行：

```bash
swift test
```

## 本地数据与安全

| 数据 | 存储位置 |
| --- | --- |
| 剪贴板历史 | `~/Library/Application Support/Luma/Clipboard` |
| 图片文件 | `~/Library/Application Support/Luma/Clipboard/images` |
| 插件与应用设置 | `UserDefaults` |
| AI API Key | macOS 钥匙串 |

剪贴板历史索引使用原子 JSON 写入，图片按内容哈希保存。启动时只加载图片文件引用，不会一次性把历史图片全部解码到内存。

剪贴板目录被标记为不参与系统备份。配置导出包含快捷键、插件设置、片段、自选股票和天气地点等数据，但排除钥匙串密钥。

Apple Translation 复用系统能力。只有选择 AI 翻译时，Luma 才会按次请求用户配置的公网接口。

## 项目结构

```text
Sources/Luma/
├── AppDelegate.swift              # 应用生命周期与依赖装配
├── LauncherSession.swift          # 聚焦屏幕、目标窗口、排列与粘贴会话
├── LauncherModel.swift            # 搜索状态与结果执行
├── LauncherView.swift             # 主面板与搜索结果
├── Plugin.swift                   # 插件类型与 CommandCatalog
├── PluginViews.swift              # 插件路由与剪贴板界面
├── ProductivityFeatures.swift     # 文件、Quicklinks、片段等能力
├── StockService.swift             # 股票查询与数据源
├── WeatherService.swift           # 天气查询与数据源
├── ClipboardMonitor.swift         # 剪贴板采集、过滤与去重
└── ClipboardStorage.swift         # 剪贴板持久化与图片文件管理

Tests/LumaTests/
├── CoreTests.swift
└── ProductivityFeatureTests.swift
```

`CommandCatalog` 是插件元数据的唯一来源。`LauncherSession` 隔离唤起前的聚焦屏幕、目标窗口、窗口排列和粘贴恢复顺序。

插件均为编译期原生模块，不加载第三方网页或运行时插件代码。

## 数据声明

股票和天气数据来自公网服务，可能存在延迟、中断或字段变化。自动数据源会在请求失败时尝试其他来源。

股票行情仅用于信息展示，不构成投资建议。
