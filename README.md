<p align="center">
  <img src="Resources/LumaAppIcon.png" width="120" alt="Luma 应用图标">
</p>

<h1 align="center">Luma</h1>

<p align="center"><strong>轻量、原生、随叫随到的 macOS 工具启动器。</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.4%2B-000000?logo=apple&amp;logoColor=white" alt="macOS 14.4+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-333333?logo=apple&amp;logoColor=white" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-6.0%2B-F05138?logo=swift&amp;logoColor=white" alt="Swift 6.0+">
</p>

<p align="center">
  <a href="#快速开始">快速开始</a> ·
  <a href="#核心体验">核心体验</a> ·
  <a href="#内置插件">内置插件</a> ·
  <a href="#权限隐私与本地数据">隐私与数据</a> ·
  <a href="#开发">开发</a>
</p>

Luma 使用 Swift、SwiftUI、AppKit 与 macOS 系统框架构建，把 App、Spotlight 文件、算式和常用工具聚合到同一个浮动面板中。

项目不包含 Electron、Chromium、WebView 或 JavaScript 运行时，专注于低干扰、低资源占用和键盘优先的原生体验。

## 快速开始

### 环境要求

- macOS 14.4 或更高版本
- Apple Silicon Mac
- Swift 6.0 或更高版本（Xcode 16 或 Command Line Tools 16）

### 从源码安装

```bash
git clone https://github.com/Gnatnaituy/luma.git
cd luma
./scripts/install-app.sh
```

安装脚本会完成 Release 构建与代码签名，验证暂存副本、备份旧版本并替换 `/Applications/Luma.app`，然后启动新版本。新副本移动失败时会恢复备份。

安装完成后，按 `⌥ Space` 唤起或隐藏 Luma。首次使用粘贴、读取选中文本或窗口管理前，请在“系统设置 → 隐私与安全性 → 辅助功能”中启用 Luma。

> 当前安装包由本机源码构建并使用 ad-hoc 签名，不是 Developer ID 签名或 Apple 公证的发行包。

## 核心体验

- **统一搜索**：同时查找插件、已安装的 macOS App、Spotlight 文件和算式结果。
- **键盘优先**：使用方向键、`Enter`、`Esc` 和右方向键完成选择、执行、返回与结果操作。
- **随焦点出现**：面板显示在当前聚焦屏幕，并在本次运行期间记住位置和页面高度。
- **按需直达**：可为关键词绑定独立全局快捷键；唯一命中时直接进入对应插件。
- **原生双语**：设置页支持中文与 English 即时切换，并保留语言选择。
- **可配置首页**：最近使用记录支持竖向混排，或按插件与 App 分组的横向布局。

Luma 启动后会低优先级扫描标准 Applications 目录，为本机 App 建立轻量索引。文件搜索复用 macOS Spotlight，不维护另一份文件数据库。

搜索结果统一支持打开或复制；App 和文件还可复制路径并在 Finder 中显示。按右方向键可展开操作栏，鼠标右键可打开当前结果的上下文菜单。

## 内置插件

| 插件 | 能力 |
| --- | --- |
| 剪贴板 | 文本、图片、文件和链接历史；搜索、过滤、收藏与快速粘贴 |
| 计算器 | 安全解析四则运算、括号、幂和常用函数，并保存最近结果 |
| JSON 编辑器 | 语法高亮、格式化、压缩、校验、转义与去转义 |
| 随机密码 | 使用系统安全随机数生成 6–32 位密码 |
| 翻译 | Apple Translation 或用户配置的 AI 模型翻译 |
| 编码小助手 | Base64、URL 编解码与 SHA-256 |
| 股票盯盘 | 查询 A 股、港股、美股的公网延迟行情与多周期走势 |
| 天气 | 多地点天气、逐小时预报与七日预报 |
| 日历 | 查看公历、农历、节气、传统节日和内置年份的节假日安排 |
| 窗口管理 | 将当前窗口排列到左半屏、右半屏、最大化或居中 |

### 剪贴板

剪贴板历史支持文本、图片、文件和链接。双击条目或按 `Enter` 会隐藏 Luma、恢复原窗口并粘贴；收藏、复制、删除和图片预览也可直接完成。

文本与链接全局去重，文件避免连续重复，图片按内容哈希去重。默认保留 3 个月，可改为 3 天、7 天、1 个月、3 个月、6 个月或 1 年；收藏不受自动过期限制。

### 翻译与 AI

翻译会优先读取唤起前 App 中选中的文本，没有选中文本时再读取剪贴板。输入中文时默认译为英语，其他语言默认译为简体中文；`Enter` 翻译，`Shift Enter` 换行。

AI 管理支持自定义供应商、Base URL、多个模型，以及 OpenAI Chat Completions 和 Anthropic Messages 两种接口格式。API Key 只保存在 macOS 钥匙串中。

### 股票与天气

股票支持 `600115.SS`、`002594.SZ`、`0700.HK` 和 `AAPL` 等代码格式，并提供分时、五日、日 K、周 K 和月 K 走势。

股票与天气均可自动切换数据源，也可在设置中手动指定。数据只在使用对应功能时请求，不下载全市场数据，也不在后台持续轮询。

## 基本操作

| 操作 | 按键或方式 |
| --- | --- |
| 唤起或隐藏 Luma | `⌥ Space` |
| 移动选择 | `↑` / `↓` |
| 打开或执行 | `Enter` |
| 返回上一层 | `Esc` |
| 展开结果操作 | `→` |
| 打开上下文菜单 | 鼠标右键 |
| 翻译输入换行 | `Shift Enter` |
| 粘贴剪贴板条目 | `Enter` 或双击 |

全局唤起快捷键与插件关键词都可以在设置中修改。全局快捷键使用 Carbon Hot Key，本身不需要辅助功能权限。

## 设置

设置页分为两组：

- **应用设置**：通用设置、快捷键管理。
- **插件设置**：插件管理、剪贴板、AI、翻译、股票和天气。

可以启用或停用插件、修改搜索关键词、绑定关键词快捷键，并配置菜单栏图标、最近使用布局、登录时启动、语言和配置导入导出。

## 权限、隐私与本地数据

Luma 只在使用对应能力时访问系统服务或网络。

| 能力 | 用途 |
| --- | --- |
| 辅助功能 | 粘贴、读取选中文本、恢复目标窗口和窗口管理 |
| 钥匙串 | 保存并读取 AI API Key |
| 登录项 | 可选地在登录 macOS 后启动 Luma |
| 网络 | 按需请求股票、天气或用户配置的 AI 服务 |

辅助功能授权与应用的代码身份和安装路径相关。日常运行请保持使用 `/Applications/Luma.app`，避免重复授权或权限失效。

| 数据 | 存储位置 |
| --- | --- |
| 剪贴板历史 | `~/Library/Application Support/Luma/Clipboard` |
| 剪贴板图片 | `~/Library/Application Support/Luma/Clipboard/images` |
| 插件与应用设置 | `UserDefaults` |
| AI API Key | macOS 钥匙串 |

剪贴板历史在本地持久化，其目录被标记为不参与系统备份。配置导出包含快捷键、插件设置、自选股票和天气地点等数据，但不包含钥匙串中的 API Key。

Apple Translation 复用系统能力。只有选择 AI 翻译时，Luma 才会向用户配置的接口发送待翻译文本。

## 开发

### 构建与测试

```bash
# 运行完整测试套件
./scripts/test-core.sh

# 生成本地签名的应用目录
./scripts/build-app.sh
```

构建产物位于 `dist/Luma.build`。项目使用 Swift Package Manager，当前不依赖第三方软件包。

测试脚本等价于在项目根目录执行 `swift test`。

### 项目结构

```text
Sources/Luma/
├── AppDelegate.swift              # 生命周期、窗口与依赖装配
├── Launcher*.swift                # 启动器状态、搜索、会话与界面
├── Plugin.swift                   # 插件类型与统一元数据
├── *PluginView*.swift             # 各插件的原生 SwiftUI 界面
├── *Service.swift                 # 日历、股票、天气与 AI 服务
├── Clipboard*.swift               # 剪贴板采集、粘贴与本地存储
├── SettingsView.swift             # 分类设置界面
└── Localization.swift             # 中文与 English 本地化

Tests/LumaTests/                   # 核心、日历、性能与功能测试
scripts/                           # 构建、安装与测试脚本
Resources/                         # Info.plist 与应用图标
```

`CommandCatalog` 是插件元数据的唯一来源。插件均为编译期原生模块，不加载第三方网页或运行时插件代码。

## 数据源与限制

- 股票和天气依赖公网服务，可能出现延迟、中断或上游字段变化；自动模式会在请求失败时尝试其他来源。
- 股票行情仅用于信息展示，不构成投资建议。
- 日历中的法定节假日与调休安排目前内置 2025、2026 年。其他年份仍显示周末、农历和传统节日；节气计算覆盖 2000–2099 年，且不会推测调休。
- 当前构建脚本只生成 Apple Silicon（`arm64`）版本。
