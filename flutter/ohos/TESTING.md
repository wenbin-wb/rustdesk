# 鸿蒙真机验证指引

本文件给**在另一台机器上做真机测试**用。本仓库当前环境是云主机（OpenStack），
`VirtualizationFirmwareEnabled=False`、`SecondLevelAddressTranslation=False`、`WHPX` 未安装，
而 DevEco 模拟器需要 WHPX + SLAT，且模拟器镜像是 **x86_64** 而真机是 **arm64** —— 所以模拟器不可用，
必须真机。

---

## 1. 前提

| 项 | 要求 |
|---|---|
| DevEco Studio | 已安装（脚本默认 `D:\Program Files\Huawei\DevEco Studio`，可用 `-DevEco` 改） |
| Rust | 已装 rustup，**GNU host**：`rustup-init.exe -y --default-host x86_64-pc-windows-gnu --profile minimal` |
| Node.js | v22+（脚本用它解 `.tar.zst`） |
| 真机 | 开启**开发者模式**与 USB 调试，`hdc list targets` 能看到序列号 |
| 网络 | 能访问 TUNA MSYS2 镜像、crates.io（已配 rsproxy 国内镜像）、GitHub |

> ⚠️ **本仓库的 `libs/hbb_common` 是子模块**，其鸿蒙改动以**补丁**形式放在
> `flutter/ohos/patches/hbb_common/`（不是 pin 到本地提交），因为本地提交别人 fetch 不到。
> `setup_ohos_toolchain.ps1` 会自动初始化子模块并应用补丁 —— 不用手工处理。

---

## 2. 三条命令跑完

```powershell
# 在仓库根目录执行

# ① 重建交叉编译工具链 + 应用 hbb_common 补丁（一次性，幂等，可重复跑）
pwsh -File flutter/ohos/setup_ohos_toolchain.ps1

# ② 编译 Rust 核心 + N-API 桥接，并部署 .so 到 HAP 的 native 库目录
pwsh -File flutter/ohos/build_bridge.ps1

# ③ 打包 HAP
cd flutter/ohos
.\hvigorw.bat assembleHap --mode module -p product=default -p module=entry@default
```

产物：`flutter/ohos/entry/build/default/outputs/default/entry-default-signed.hap`

①会做的事（每步都会先检查是否已有，可断点续跑）：
init 子模块并应用补丁 → 装 rust target → 装 mingw-w64 工具链 → 建 `C:\ohos-ndk` junction →
下载 prebuilt OpenSSL → 交叉编译 libopus → 建 vcpkg 布局 junction → **用一个 `cargo check` 自检**。

---

## 3. 安装与启动

```powershell
$hdc = "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
& $hdc list targets                       # 先确认真机可见
& $hdc install -r flutter\ohos\entry\build\default\outputs\default\entry-default-signed.hap
& $hdc shell aa start -b com.carriez.flutter_hbb -m entry -a EntryAbility
```

看日志（含 Rust 侧）：

```powershell
& $hdc hilog | Select-String -Pattern "RustDesk|rustdesk|napi"
```

---

## 4. 验收点（这几条是本次要验的核心）

| # | 位置 | 期望 | 说明 |
|---|---|---|---|
| **V1** | 设置 → 系统信息 | **核心版本** 显示 `1.5.0`（非 `—`） | ✅ **可靠的加载测试**：`mainGetVersion()` 返回编译期常量 `VERSION`，与核心是否初始化无关。显示 `—` 就说明 `.so` 没装载 |
| **V2** | 设置 → 系统信息 | **桥接版本** 显示 `1.5.0` | 证明桥接 crate 自身可用 |
| **V3** | 远程页 → 本机设备 ID | **9 位数字，且关闭重开后完全不变** | ⭐ **本轮最重要的验证点**。核心生命周期已接通，且修掉了 `Config::path()` 在 ohos 上返回空路径的缺陷，ID 现在应能持久化。**若仍每次变化，说明写入仍失败**，请看 §4.2 |
| **V3b** | 远程页 → 一次性密码 | 显示**真实临时密码**（非 `------`） | 已改为从核心读取（`mainGetTemporaryPassword`），此前读的是一个从未被写入的本地键 |
| **V4** | 首页任一操作 | 不闪退 | 已修复"点连接闪退"（`this.controller` 为 undefined）。连接流程应能走完：远程 → 连接 → 弹密码框 → 输入 → 连接 |
| **V5** | 折叠屏 / 平板 / 横屏 | 旋转或折叠时导航从**底栏切到侧栏**、内容重排 | 断点自适应（`sm<600 / md 840 / lg 1440`） |
| **V6** | 系统切**深色模式** | 全界面跟随，**弹窗内文字与占位符清晰可读** | 三个弹窗此前全硬编码（49 处 hex），已全部改为资源令牌 |
| **V7** | 系统语言切换 / 英文机 | 界面文案跟随（中文 base / `en_US`） | i18n 资源生效 |
| **V8** | 手机形态下看底栏 | **悬浮药丸**：左右留白、离底抬起、内容可透出、毛玻璃 | 关键是 `barOverlap(true)`。实测底部内容区 `225→1051`（满宽为 0→1276）、底边 `2666`（离底 182px） |
| **V9** | 顶部/底部边缘 | **无窗口色条**，内容不被状态栏/手势条遮挡 | 已 `setWindowLayoutFullScreen(true)` 并应用真实安全区内缩 |
| **V10** | 设置 → 服务器设置：填自建地址 → 保存 → 关闭 → **重开** | 字段**显示刚才填的值** | 此前弹窗只在创建时读一次配置，重开为空；现由页面持有状态并在打开前刷新 |
| **V11** | 填密码勾选"记住"→ 断开 → 再连同一设备 | **不再弹密码框** | 密码存取此前因存储未初始化而全程失效（三个函数都早退），已修 |
| **V12** | 连到新设备后看"设备"/"最近" | **新设备出现在列表** | 列表此前只在首次构建时加载且不会刷新，现由页面通知重载 |

### 4.2 若 V3 失败（ID 仍变）该看什么

ID 的持久化链路是：`mainInit` 设 `APP_DIR` → 首次访问配置时 `Config::load()` →
`path()` 解析出 `<filesDir>/RustDesk.toml` → 不存在则 `gen_id()` 生成随机 ID 并**写回该文件**。
若仍每次变化，说明**写入失败**。检查顺序：

```powershell
$hdc = "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
# ① 核心日志是否在写（此前 ohos 完全没有日志初始化）
& $hdc shell hilog -x | Select-String "RustDeskCore|Failed to (load|store)|confy"
# ② 配置文件是否真的落盘
& $hdc shell "run-as com.carriez.flutter_hbb ls -la files/ 2>&1"
& $hdc shell "run-as com.carriez.flutter_hbb cat files/RustDesk.toml 2>&1"
```

> **注意**：`Config::store_` 写入失败**只记日志、不报错**（上游行为），`get_id()` 仍会返回内存里的 ID
> —— 所以"界面上有 ID"**不能**证明已持久化，必须重开应用再比对。

> ### ⚠️ 已修复的历史说明（保留以免误解）
>
> 此前的判定是"核心未初始化"，那只是**一半**原因。真正的根因是 `libs/hbb_common` 里
> `Config::path()` / `get_home()` 的平台分支**只列了 android/ios**，而 ohos 是
> `target_os="linux"` + `target_env="ohos"`，于是走了桌面回退：`path()` 经 `ProjectDirs`
> **返回空路径** ⇒ 配置写不进去 ⇒ 每次启动重新生成 ID。现已归入移动端分支（`APP_DIR` / `APP_HOME_DIR`）。

## 5. ⚠️ 尚未实现 —— 不要当 BUG 报

本次交付的是**核心可编译且已启动 + 桥接可用 + UI 按鸿蒙规范重写（HDS）**，以下**有意未做**（计划见 `PLAN.md`）：

| 项 | 现状 |
|---|---|
| **真正的远程连接** | ❌ **未接通**。点"连接"只走"记入地址簿 + 密码对话框"，**不会发起 rendezvous/relay 会话**，因此**看不到对方画面是预期行为**。此前的网页版/假桌面已删除，现在的会话页只显示核心真实状态并明确标注未接通 |
| 视频画面 / XComponent 渲染 | 未实现（需消费核心的 `EventToUI::Rgba`） |
| 核心→界面的事件通道 | 未实现（`StreamSink` 需改为 NAPI ThreadsafeFunction） |
| 触摸→鼠标/键盘输入注入 | 未实现 |
| 剪贴板同步 | 未实现（Rust 侧是占位门控） |
| 文件传输 | 未实现（按钮存在，无通道） |
| 音频 | 未实现（Rust 侧门控掉） |
| 被控端 / 屏幕共享 | 未实现；`AVScreenCaptureRecorder` **API 确实存在**，但需授权流程与 syscap 检查，对标 iOS 同为后置 |
| 登录 | 走 HTTP 登录接口，未接入业务状态 |
| 折叠屏**铰链避让**（悬停态分区） | 未实现（已做的是断点重排） |

另外两项环境层面的已知事项：

- Rust 侧 `portable-pty`（wezterm fork）**临时停用**：cargo 会拉取 lockfile 里全部 git 依赖，
  而该 fork 在慢网络下反复停滞。它**只影响桌面端终端功能**，对 ohos 无影响；正式 PR 前需恢复。
- `flutter/ohos/build-profile.json5` **明文含签名 keystore 密码**（既有问题，本次未动）。
  建议改为环境变量或本地未跟踪文件。

---

## 6. 出问题怎么定位

| 现象 | 先看 |
|---|---|
| `setup` 卡在下载 | 重跑即可（幂等）；下载步骤会跳过已完成的 |
| `git am` 失败 | 按提示在 `libs/hbb_common` 里 `git am --continue`，再重跑 setup |
| `cargo` 报找不到 `dlltool`/`gcc` | mingw 没装全，重跑 setup |
| `--sysroot` 报 no such file | `C:\ohos-ndk` junction 丢了，重跑 setup |
| `openssl-sys` 找不到 OpenSSL | 缺 `AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_DIR`；用 `rust_ohos_build.ps1`，它已封装 |
| bindgen 报 `stddef.h`/`stdint.h` | 同上：必须用 `rust_ohos_build.ps1`，它带 `-resource-dir` 与 sysroot `-isystem` |
| HAP 里没有 `.so` | 见 §4 的坑 |
| 应用启动即崩 | `hdc hilog` 找 napi/panic 关键字 |
