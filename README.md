<div align="center">

# Astra

**本地优先的 API 调试客户端 · A local-first API client for macOS & Windows**

[![Build Windows](https://github.com/compiler-says-no/astra/actions/workflows/build-windows.yml/badge.svg)](https://github.com/compiler-says-no/astra/actions/workflows/build-windows.yml)
[![Build macOS](https://github.com/compiler-says-no/astra/actions/workflows/build-macos.yml/badge.svg)](https://github.com/compiler-says-no/astra/actions/workflows/build-macos.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)
![Platform](https://img.shields.io/badge/macOS%20%7C%20Windows-Desktop-38BDF8)

Postman 的轻量替代品：原生桌面体验，数据只存在你自己的电脑上，不登录、不上云。

</div>

---

## 界面预览

<div align="center">
  <img src="docs/screenshots/main.png" alt="主界面：请求编辑与响应查看" width="100%">
</div>

<p align="center"><sub>请求编辑 + JSON 树形响应，右侧可切响应头 / Cookies / 原始报文 / 事件流 / 脚本日志</sub></p>

<table align="center">
  <tr>
    <td width="50%" align="center">
      <img src="docs/screenshots/variables.png" alt="变量面板" width="100%"><br>
      <sub>变量面板：分层作用域与优先级一目了然</sub>
    </td>
    <td width="50%" align="center">
      <img src="docs/screenshots/runner.png" alt="集合运行器" width="100%"><br>
      <sub>集合运行器：批量执行、数据驱动与运行报告</sub>
    </td>
  </tr>
</table>

---

## 功能特性

### HTTP 调试
- GET / POST / PUT / PATCH / DELETE / HEAD / OPTIONS
- Params、Headers、Cookies 自动管理，重定向与证书校验开关
- 多种 Body：JSON、纯文本、`x-www-form-urlencoded`、`multipart/form-data`（含文件上传）
- 请求 / 响应可拖拽分屏，`⌘/Ctrl + Enter` 发送，`⌘/Ctrl + S` 保存

### 集合与组织
- 集合 / 多级文件夹 / 请求树，拖拽排序与跨集合移动
- 请求备注、复制、跨集合迁移、响应示例（Examples）
- 侧栏搜索过滤，集合与文件夹级备注、变量、认证、前置 / 后置脚本（按 集合 → 外层文件夹 → 内层文件夹 → 请求 顺序继承）

### 导入与导出
- 导入 Postman 集合 / 环境 / 整包备份、Insomnia v4、OpenAPI 3.0（JSON / YAML）、`.http` / `.rest` 文件与 cURL 命令
- 导出 Astra 备份、Postman 集合与环境、Insomnia v4
- 请求一键复制为 cURL / Python / JavaScript / Go / Java / HTTP Client 代码片段

### 变量与脚本
- 全局 / 集合 / 文件夹 / 环境 / 请求级变量分层覆盖，优先级：全局 < 集合 < 文件夹 < 环境 < 请求 < 运行时
- 输入 `{{` 自动补全变量名，变量面板一键查看来源与覆盖关系
- 发送前预览最终请求（URL、Header、Body 全部解析后）
- 前置 / 后置脚本：`pm.environment`、`pm.globals`、`pm.collectionVariables`、断言、`pm.execution.setNextRequest` 请求链路编排
- `pm.jsonPath('$.data.items[*].id')` 读取响应 JSON：支持 `.key`、`['key']`、`[0]`、`[-1]`、`[*]` 与递归 `$..key`，单值返回标量、多值返回数组
- 脚本编辑器带行号、自动缩进、括号自动配对、语法高亮

### 批量与自动化
- **Collection Runner**：按集合层级顺序执行，支持重复 N 次、CSV / JSON 数据驱动
- **运行报告**：通过率、失败项、耗时统计，可导出 JSON / CSV / JUnit XML（JUnit 可直接接入 CI）
- **定时监控**：按间隔自动运行集合并记录结果
- 请求依赖编排：脚本里 `setNextRequest` / `skipRequest` 控制执行流

### 协议与认证
- **GraphQL**（Query + Variables）、**gRPC-Web**（帧编解码）、**SSE 事件流**、**WebSocket**（消息模板库、一键重发）
- Bearer、Basic、API Key、OAuth 2.0（授权码 + PKCE、客户端凭证、密码模式，token 到期自动刷新）
- 请求 / 文件夹 / 集合级认证继承，界面显示实际生效来源

### 网络
- HTTP / SOCKS5 代理，按主机名绕过列表
- mTLS 客户端证书（P12 + 口令）、关闭 TLS 校验、自定义超时

### Mock Server 与抓包
- **Mock Server**：本地 `127.0.0.1` HTTP 服务（默认 `6790`），给没有文档的接口直接造数据
  - 任意方法（含 `ANY`），路径支持静态片段、`:param` 路径参数与尾部 `*` 通配
  - 每条路由可配置状态码、响应头、Body 与延迟；运行中修改即时生效，无需重启
  - 模板占位符：`{{param}}`、`{{query.x}}`、`{{header.x}}`、`{{body.a.b.0}}`
  - 随机数据：`{{$guid}}`、`{{$randomInt}}`、`{{$randomFullName}}`、`{{$randomEmail}}`、`{{$randomCity}}`、`{{$randomBoolean}}`、`{{$timestamp}}`、`{{$isoTimestamp}}`
  - 未匹配的请求返回 404 与当前可用路由列表；自动处理 CORS 与 `OPTIONS` 预检
- **本地抓包代理**：监听 `127.0.0.1:6791`，把真实流量记录下来
  - HTTP 直接转发；HTTPS 通过本地 CA 做 MITM 解密（可关闭为纯隧道模式）
  - 可在界面导出 `astra-ca.pem`，加入系统信任后即可解密 HTTPS
  - 记录请求 / 响应头、Body（超过 512 KB 标记截断）、状态码与耗时
  - 记录一键 **Open as request** 回放到新标签页，或 **Create mock route** 直接生成 Mock
- 集合请求右键 **Create Mock Route…**：优先使用已保存的响应示例作为 Mock 数据
- 入口：顶部工具栏地球图标，或快捷键 `⌘/Ctrl + Shift + M`；Mock 配置随 `workspace.json` 持久化，抓包记录仅保存在内存

### 响应体验
- JSON 树形浏览与键值搜索、展开 / 折叠 / 复制节点
- Cookies 面板、事件流面板、脚本断言日志
- 响应对比（行级 Diff）、响应头过滤 / 排序 / 列宽拖拽
- 大响应虚拟滚动、图片预览、二进制下载
- cURL 一键导入 / 导出
- 集合星标：点击集合行右侧星标即可置顶，搜索框右侧可切换「仅看星标」

### 稳定性与数据安全
- 工作区与草稿带 `schemaVersion`，升级后自动迁移旧文件，不会因为结构变化丢数据
- 保存失败会明确提示；每次写入轮转 `workspace.json.bak` / `.bak1`，主文件损坏时自动从备份恢复
- 未保存的请求标签实时写入 `draft.json`，崩溃、强制退出或重装后重新打开可恢复草稿
- Token、密码、API Key、OAuth Client Secret / Refresh Token 存入 macOS Keychain / Windows Credential Manager，工作区文件只保留 `secure:` 占位符
- 落盘写入串行化，避免异步保存乱序时旧数据覆盖新数据
- 大响应按行虚拟滚动，渲染上限 400 万字符并提示截断；通过「保存响应」仍可导出完整正文
- 按 `Content-Type` 与响应字节自动识别 UTF-8 / GBK / GB18030 / Big5 / ISO-8859-1；缺少 charset 的 GBK 响应会回退解码，不再乱码

### 星标与导入导出的兼容性
- 星标是本地界面偏好，保存在 `workspace.json`；Astra 自身的备份 / 导出会保留它
- Postman / Insomnia 没有星标概念：导出到这两种格式时不写入星标，从它们导入的集合一律为未星标
- 导入以追加方式创建新集合，重复导入不会覆盖已有集合，也不会清掉你本地已设置的星标
- 星标不影响请求执行、Collection Runner、变量解析与导入导出结果

---

## 本次更新（v2.3.0）

- 新增 **Insomnia v4 导入 / 导出**：workspace / request_group / request / environment 与 Astra 集合、多级文件夹、环境一一对应，`{{ _.var }}` 与 `{{var}}` 自动互转
- 新增 **`.http` / `.rest` 文件导入**：支持 `###` 分隔、`@var` 变量、`# @name` 命名、Header / Body 与请求处理器，导入后生成完整集合
- 新增 **Runner 报告 CSV / JUnit XML 导出**：`Export Report` 可选 JSON / CSV / JUnit XML，JUnit 结果可直接接入 CI
- 导入入口现同时识别 Postman / Insomnia / OpenAPI / `.http` / Astra 备份
- `pm.jsonpath()` 作为 `pm.jsonPath()` 的别名保留，与 IDEA 插件脚本 API 完全一致

## 本次更新（v2.2.1）

- 新增 **集合 / 文件夹级脚本**：右键集合或文件夹 → **Scripts**，分别编辑前置与后置脚本；请求发送和 Collection Runner 都按 集合 → 外层文件夹 → 内层文件夹 → 请求 的顺序合并执行
- 新增 **`pm.jsonPath()`**：与插件端共用同一套路径语法，支持 `.key`、`['key']`、`[0]`、`[-1]`、`[*]` 与递归 `$..key`
- 旧版 `workspace.json` 无需迁移，缺少脚本字段时按空脚本处理

## 本次更新（v2.2.0）

- 新增 **Mock Server**：本地建路由、造响应，支持路径参数 / 通配、延迟、CORS 与随机数据模板
- 新增 **本地抓包代理**：HTTP 转发 + HTTPS MITM 解密，支持导出 CA、打开为请求、从抓包生成 Mock
- 新增 **Traffic Studio** 面板（`⌘/Ctrl + Shift + M`），统一管理 Mock 路由与抓包记录
- 集合请求右键菜单新增 **Create Mock Route…**，可直接把响应示例变成 Mock
- Mock 配置随工作区持久化，并纳入 Astra 备份 / 恢复
- 集合星标图标改为自绘五角星（实心 / 描边），端点与侧栏保持一致
- 修复 Astra 备份在集合为空时被误判成 Postman dump、导入走错分支的问题
- 修复导入备份时 Mock 端口未恢复、运行中的 Mock 服务未热更新的问题
- macOS Release 构建补充 `com.apple.security.network.server` 权限，保证沙箱下可监听本地端口

---

## 和 Postman 的差异

| | Astra | Postman |
|---|---|---|
| 数据位置 | 完全本地（`workspace.json`） | 默认云端账号体系 |
| 登录要求 | 无 | 需要账号 |
| 运行占用 | 原生桌面，轻量 | Electron，较重 |
| 协作与云同步 | 暂不支持（规划中） | 支持 |
| 计费 | 免费 | 免费版有限制 |

**适合谁**：后端 / 前端 / 测试日常调接口；内网或涉密环境不能把请求数据传到第三方云；想要开箱即用、不弹登录、不推订阅的桌面工具。

---

## 下载安装

前往 [Releases](https://github.com/compiler-says-no/astra/releases) 下载对应平台压缩包：

| 平台 | 文件 | 说明 |
|---|---|---|
| Windows 10/11 x64 | `Astra-win-x64-*.zip` | 解压后运行 `astra.exe`，需保留同目录 `data\` 与 DLL |
| macOS（Apple Silicon / Intel） | `Astra-macos-*.zip` | 解压后拖入「应用程序」 |

macOS 未签名版本首次打开需右键 → **打开**，或执行：

```bash
xattr -dr com.apple.quarantine /Applications/astra.app
```

数据保存在系统应用支持目录下的 `Astra/`（`workspace.json` 为集合与环境，`draft.json` 为未保存草稿），重装不丢失。写入时会自动保留 `workspace.json.bak` 与 `.bak1` 两份备份；敏感凭据保存在系统凭据库，不写入这两个文件。

---

## 本地开发

### 环境要求
- Flutter 3.x（Dart ≥ 3.13）
- macOS：Xcode Command Line Tools
- Windows：Visual Studio 2022 +「使用 C++ 的桌面开发」工作负载

### 运行

```bash
flutter pub get
flutter run -d macos     # 或 -d windows
```

### 测试与静态检查

```bash
flutter analyze --no-fatal-infos
flutter test
```

### 构建

```bash
# macOS
flutter build macos --release

# Windows（PowerShell）
powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1
```

Windows 脚本会自动完成环境检查、分析、测试、构建，并打包到 `dist\Astra-win-x64-<版本>-<日期>.zip`。

---

## 持续集成

| 工作流 | 触发 | 产物 |
|---|---|---|
| [Build Windows](.github/workflows/build-windows.yml) | push / PR / 手动 / `v*` 标签 | `Astra-win-x64.zip` |
| [Build macOS](.github/workflows/build-macos.yml) | 手动 / `v*` 标签 | `Astra-macos.zip`（配置 Secrets 后自动签名 + 公证；arm64 机池排队失败时自动切换 Intel 机池重试） |

推送 `v*` 标签时两端产物会一起挂到 Releases：

```bash
git tag v2.2.0
git push origin v2.2.0
```

macOS 签名公证需要配置 `MACOS_CERT_P12`、`MACOS_CERT_PASSWORD`、`KEYCHAIN_PASSWORD`、`APPLE_ID`、`APPLE_APP_PASSWORD`、`APPLE_TEAM_ID` 六个 Secrets，未配置时自动跳过签名。

---

## 技术栈

- **Flutter / Dart** 单代码库编译 macOS 与 Windows 原生应用
- **dart:io HttpClient** 实现请求、代理、mTLS、SSE；WebSocket 走 `WebSocketChannel`
- **flutter_js** 运行 `pm.*` 兼容脚本
- 纯本地 JSON 工作区存储，导入 / 导出集合与环境

---

## 路线图

- [ ] 团队协作与云同步
- [ ] 测试断言模板与测试套件视图
- [ ] Linux 构建

---

<div align="center"><sub>Astra v2.3.0 · 用 Flutter 重写的桌面 API 调试工具</sub></div>
