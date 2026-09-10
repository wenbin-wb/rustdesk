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
| **V3** | 远程页 → 本机设备 ID | ⚠️ **见下方"重要说明"，此项目前不能作为判定依据** | 核心**未初始化**，ID 可能为空或每次冷启动都变 |
| **V4** | 首页任一操作 | 不闪退 | 证明没有跨 NAPI 边界 panic |
| **V5** | 折叠屏（若有）/ 平板 / 横屏 | 旋转或折叠（展开↔折叠）时，导航**从底栏切到侧栏**、内容重排且**不重建页面** | 断点自适应（`sm<600 / md 840 / lg 1440`） |
| **V6** | 系统切**深色模式** | 全界面跟随（背景/文字/卡片） | `dark` 限定词资源生效 |
| **V7** | 系统语言切换 / 英文机 | 界面文案跟随（中文 base / `en_US`） | i18n 资源生效 |

> ### ⚠️ 重要说明：V3 目前不可作为判定依据（审核发现）
>
> ArkTS 侧**只调用了 `mainGetMyId()`，没有调用任何核心生命周期**
> （`mainInit` / `mainDeviceId` / `mainDeviceName` / `mainSetHomeDir` 均未导出、未调用）。
> 而 `mainGetMyId()` → `Config::get_id()` 依赖配置已加载：
>
> ```rust
> // hbb_common/src/config.rs
> pub fn get_id() -> String {
>     let mut id = CONFIG.read().unwrap().id.clone();
>     if id.is_empty() {
>         if let Some(tmp) = Config::gen_id() { id = tmp; Config::set_id(&id); }
>     }
>     id
> }
> ```
>
> 未初始化时 `CONFIG` 为默认空值 → 走 `gen_id()`；而本仓库为 ohos 打的补丁让 `gen_id()`
> 落到**随机数**分支。结果可能是：**ID 为空**，或**每次冷启动都不同**
> —— 后者恰好与"旧代码本地随机数"的症状**无法区分**，会得出错误结论。
>
> **所以请不要用 V3 判断"ID 是否来自核心"。** 真正的判定请看日志：
> `hdc hilog | Select-String "Failed to get machine uid"` 之类，或在 `mainInit` 接通后重测。
> 修复方式是导出并调用核心初始化序列（P2 未完项），见 `PLAN.md`。

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

## 4.1 已实测：闪退根因与修复（2026-09-10 真机 LMR-AL10 / API 26）

**症状**：装上后一启动就闪退，无 native crash，只有 `jscrash` 记录。

**⚠️ 真正的根因在 hilog，不在崩溃堆栈里 —— 两者必须一起看。**

崩溃堆栈只给出**表象**：

```
Reason: TypeError
Error message: Cannot read property mainGetMyId of undefined
    at getMyId (entry/src/main/ets/platform/RustDeskBridge.ets:78:17)
```

hilog 才给出**底层原因**：

```
MUSL-LDSO: relocating failed: symbol not found.
  dso=/data/storage/el1/bundle/libs/arm64/librustdesk_ohos.so s=sodium_base642bin
MMG: [NMM:1439] load module default/rustdesk_ohos failed.
ArkCompiler: export objects of native so is undefined
```

**取日志的正确姿势**：

```powershell
$hdc = "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
# ① ArkTS 层崩溃堆栈
& $hdc shell "hidumper -s 1201 -a '-p Faultlogger'"
& $hdc shell "hidumper -s 1201 -a '-p Faultlogger -f <上面列出的文件名>'"
# ② 动态库加载失败原因（关键！崩溃堆栈里看不到）
& $hdc shell hilog -x | Select-String "relocating failed|load module|export objects of native"
```

**根因**：`hbb_common → sodiumoxide → libsodium-sys`。`libsodium-sys 0.2.7` 没有该目标的
预编译归档，**静默回退到打包内的 Windows 构建**（构建输出写着
`cargo:rustc-link-search=native=.../libsodium-sys-0.2.7/mingw/win64/`）。那些是 **x86 目标文件**，
lld 无法用于 aarch64，于是 `sodium_base642bin` 等符号悬空 → `dlopen` 失败 → 模块为 `undefined`
→ ArkTS 抛 TypeError。

**修复**：`build_libsodium_ohos.ps1` 交叉编译 libsodium；`.cargo/config.toml` 用
**目标专属 rustflags** 以完整路径链入该归档。

> ⚠️ **不要用 `SODIUM_LIB_DIR`**（我第一次就这么做，结果把 host 也弄坏了）。它是**全局**变量，
> 会让 **host** 也去链 aarch64 归档；而 host 的 build script **也需要 libsodium**
> （`build.rs:89` 调 `hbb_common::gen_version()`，hbb_common 依赖 sodiumoxide），
> 于是 host 链接报 `undefined reference to sodium_base642bin`。

**排除掉的假设**（不要再走一遍）：设备缺 `libace_napi.z.so`（SELinux 让 `ls` 对存在与否都报
"No such file"，该检查本身不可靠）；libc++ ABI 不匹配；RUNPATH 含构建机路径；
**以及"缺 `.d.ts`"** —— `.d.ts` 确实该补（hvigor 警告、后续 SDK 会强制校验），
但补完**仍然闪退**，报错完全相同，所以它**不是**根因。

**隔离实验手法**（定位"是原生模块还是 UI"极有效）：临时把 `RustDeskBridge.ets`
换成不导入 `.so` 的同名桩函数，重新打包运行 —— 桩版能跑而真实版崩，即可确定问题在 `.so` 导入。

> **两条通用教训**：
> ① ArkTS 层异常（`jscrash`）在 `hilog` 里**看不到堆栈**，要用
> `hidumper -s 1201 -a '-p Faultlogger'`；反过来，**动态库加载失败在崩溃堆栈里看不到，要看 hilog**。
> ② `aa start` 会因**设备锁屏**失败（`Error Code:10106102`），与代码无关，测试前先解锁。

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
