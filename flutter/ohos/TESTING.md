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
| **V1** | 设置 → 系统信息 | **核心版本** 显示 `1.5.0`（非 `—`） | 证明 `librustdesk_ohos.so` **已加载**且 NAPI 调用通 |
| **V2** | 设置 → 系统信息 | **桥接版本** 显示 `1.5.0` | 证明桥接 crate 自身可用 |
| **V3** | 远程页 → 本机设备 ID | 显示**9 位真实 ID**（形如 `123 456 789`），且**冷启动后保持不变** | 这是从核心读的 `mainGetMyId()`；**旧代码是本地随机数，每次都会变** |
| **V4** | 首页任一操作 | 不闪退 | 证明没有跨 NAPI 边界 panic |
| **V5** | 折叠屏（若有）/ 平板 / 横屏 | 旋转或折叠（展开↔折叠）时，导航**从底栏切到侧栏**、内容重排且**不重建页面** | 断点自适应（`sm<600 / md 840 / lg 1440`） |
| **V6** | 系统切**深色模式** | 全界面跟随（背景/文字/卡片） | `dark` 限定词资源生效 |
| **V7** | 系统语言切换 / 英文机 | 界面文案跟随（中文 base / `en_US`） | i18n 资源生效 |

**失败时最有用的一条**：若 V1 显示 `—`，说明 `.so` 没装载 —— 先查
HAP 里有没有它：

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z=[System.IO.Compression.ZipFile]::OpenRead("<hap路径>")
$z.Entries | Where-Object { $_.FullName -match "\.so$" } | Select-Object FullName, Length
```

必须能看到 `libs/arm64-v8a/librustdesk_ohos.so`（约 2100 KB）。
**历史坑**：预编译 `.so` 必须放**模块根 `entry/libs/<abi>/`**；放
`entry/src/main/libs/<abi>/` 会**编译通过但被静默排除出 HAP**。

---

## 5. ⚠️ 尚未实现 —— 不要当 BUG 报

本次交付的是**核心可编译 + 桥接可用 + UI 按鸿蒙规范重写**，以下**有意未做**（计划见 `PLAN.md`）：

| 项 | 现状 |
|---|---|
| **真正的远程连接** | 未接通。`连接` 目前只走地址簿 + 密码对话框，**没有发起 rendezvous/relay 会话** |
| 视频画面 / XComponent 渲染 | 未实现 |
| 触摸→鼠标/键盘输入注入 | 未实现 |
| 剪贴板同步 | 未实现（Rust 侧是占位门控） |
| 文件传输 | 未实现（按钮存在，无通道） |
| 音频 | 未实现（Rust 侧门控掉） |
| 被控端 / 屏幕共享 | 未实现，且鸿蒙侧受限（对标 iOS 同为后置） |
| 登录 | 走 HTTP 登录接口，但未接入业务状态 |
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
