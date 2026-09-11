# RustDesk 鸿蒙端开发计划（对标 iOS）

> 目标平台：HarmonyOS API 26（本机 DevEco Studio 6.0 / SDK "HarmonyOS 26.0.0"，用户称"鸿蒙7"）
> 目标产物：可安装运行的 HAP，功能对标 iOS 端（`flutter/lib/mobile/`）

---

## 1. 架构

```
┌─────────────────────────────────────────────────┐
│  ArkUI (ArkTS) 原生 UI  —— 对标 iOS 界面/交互    │
│  首页·地址簿·设置·登录·远程会话工具栏·虚拟键鼠·文件  │
└───────────────────────┬─────────────────────────┘
                        │ N-API (C++ 桥接层，包一层 flutter_ffi.rs 的 C ABI)
┌───────────────────────▼─────────────────────────┐
│  librustdesk.so  (Rust 核心, aarch64-linux-ohos) │
│  协议/编解码/会话/文件传输/加密/地址簿             │
└───────────────────────┬─────────────────────────┘
                        │ 鸿蒙系统能力
   视频渲染 XComponent · 触摸采集 · Pasteboard · FilePicker · Audio
```

**决策（已采用默认，可随时调整）**
1. UI 层 = 纯 ArkTS 原生，放弃 Flutter（Flutter 本机未安装，现有 `flutter/ohos` 已是纯 ArkTS）。
2. 方向优先级 = 先「控制端」（对标 iOS 主要能力），「被控/屏幕共享」受系统级限制后置。
3. 「鸿蒙7」映射为本机 SDK 的 API 26 / HarmonyOS 26.0.0。

---

## 2. 环境实测

| 项 | 状态 | 位置 |
|---|---|---|
| DevEco Studio 26.0.0.821 | ✅ | `D:\Program Files\Huawei\DevEco Studio` |
| SDK HarmonyOS 26.0.0 / API 26 | ✅ | `sdk\default` |
| ohpm 26.0.0.630 | ✅ | `tools\ohpm\bin\ohpm.bat` |
| devecocli 1.3.0-stable | ✅ | `tools\node\devecocli.cmd` |
| hdc 3.2.0f | ✅（无设备） | `sdk\default\openharmony\toolchains\hdc.exe` |
| OHOS NDK clang 15.0.4 + sysroot | ✅ | `sdk\default\openharmony\native` |
| 离线 API `.d.ts`（677 个） | ✅ | `sdk\default\openharmony\ets\api` |
| arktsdoc 离线文档 | ✅ | `tools\arktsdoc` |
| 签名材料（debug） | ✅ | `C:\Users\Administrator\.ohos\config` |
| Rust 工具链 | ❌ 未安装 | — |
| Flutter | ❌ 未安装 | 已放弃 |

---

## 3. 现有代码问题清单

现有 `flutter/ohos` 为纯 ArkTS 原型壳，全部为 mock，未接真实 Rust 核心。

| # | 文件 | 问题 |
|---|---|---|
| B1 | `AuthService.ets:58` | `interface` 写在函数体内，编译错误 |
| B2 | `AuthService.ets:36` | 登录协议与 RustDesk API 不符 |
| B3 | `ScreenCaptureBridge.ets` | ~~`AVScreenCaptureRecorder` 在 SDK 中不存在~~ **此判断有误，已更正**：该 API **存在**于 `@ohos.multimedia.media`（自 API 12），文件可编译。实际问题是其 `init` 配置用了 `fd: 0`，且未处理屏幕采集授权流程与 syscap 检查。见 §5 第 1 条 |
| B4 | `RemoteStreamReceiver.ets` | AVPlayer 无法解 RustDesk 私有协议 |
| B5 | `Index.ets` | ID/密码/连接/会话全 mock |
| B6 | `DesktopCanvas.ets` | Canvas 画假桌面 |
| B7 | `RemoteSessionPage.ets` | 默认 WebView 加载网页 |
| B8 | 全部页面 | 硬编码中文/颜色、iOS 风格、无 i18n |
| B9 | `module.json5` | 权限不全，KEEP_BACKGROUND_RUNNING reason 用错 |
| B10 | `LiquidTabBar.ets` | 自绘拖拽 tab，应改用系统 Tabs |

---

## 4. 分期计划

### P0 · 环境补齐
- [x] 安装 Rust 工具链（rustup）+ `rust-ohos` 目标 `aarch64-unknown-linux-ohos`
- [x] 确认 hdc 设备/模拟器（`hdc 3.2.0f` 可用，`Emulator.exe` 在，当前无设备连接）
- [x] 确认「鸿蒙7 ↔ API 26」映射（本机 SDK `HarmonyOS 26.0.0 / API 26`）

### P1 · Rust 核心 ohos 移植（最大工作量）
- [x] 打通构建环境（见下方「进展日志」的 4 个构建阻塞）
- [x] `hbb_common` 编译通过（共享核心：proto/网络/config/加密）✅
- [x] `base` 编译通过（客户端核心）✅
- [x] `scrap` 编译通过（方案 A：门控 VPX/AOM + libyuv + 采集后端 + camera）
- [x] 根 crate **编译通过** ✅ `cargo check --lib --target aarch64-unknown-linux-ohos --features flutter` → **exit 0**（143 warnings，无 error）
- [x] **P1 完成：`cargo build --release` 链接并产出动态库** ✅
  - 命令：`cargo build --release --target aarch64-unknown-linux-ohos --lib --features flutter` → `Finished release ... in 3m 00s`
  - 产物：`target/aarch64-unknown-linux-ohos/release/liblibrustdesk.so`
  - **已验证为真 aarch64 OHOS 动态库**：`ELF 7F454C46` / 64-bit / LE / `e_machine=183`(AArch64)，且导出真实 FFI 符号 `session_get_rgba`
- [ ] 产物改名：cargo 输出 `liblibrustdesk.so`（因 `[lib] name = "librustdesk"`），而 App 侧 `DynamicLibrary.open('librustdesk.so')` 期望 `librustdesk.so` → 打包时需重命名（Android 构建同样处理）
- [ ] 平台实现：设备信息 / 剪贴板 / 文件系统 / 音频 / 屏幕采集(占位)

> **待清理（P1 收尾统一处理）**：`scrap` 在 ohos 下产生 8 条 warning（5 处 unused import、1 处 unused_mut、2 处 unused 变量），
> 均为上述门控的连带产物（这些符号在非 ohos 平台仍被使用）。因本机无法编译校验桌面端（scrap 桌面构建需 vcpkg 的
> libyuv/vpx/aom），故暂不清理，待 P1 收尾集中处理，避免误伤非 ohos 路径。
>
> **P4 解码后端落点（已核实）**：iOS 的 H.264/H.265 解码是走 **`hwcodec` 特性**（VideoToolbox 后端），而非在
> `codec.rs` 里写平台分支。⇒ ohos 的 `AVCodec` 后端应加在 **`hwcodec` crate** 内，这样 `codec.rs` 的
> H264/H265 路径无需改动，与 iOS 架构一致。

> **关键发现（P1 实测）**：`scrap` 与 libvpx/aom/libyuv 是**深度耦合**，不能只靠 cfg 门掉：
> - `common/codec.rs`（1161 行）直接 `use crate::{aom::{AomDecoder,AomEncoder,AomEncoderConfig}, vpxcodec::{VpxDecoder,...}}`，`Decoder`/`Encoder`/`EncoderCfg` 都带 VPX/AOM 分支；
> - `common/mod.rs` 的 `Frame::to()` 与 `GoogleImage::to()` 直接调用 libyuv 的 `I420ToRAW/I420ToARGB/I420ToABGR/I444ToARGB/I444ToABGR`；
> - `PixelBuffer` 是**按平台**定义的（x11/dxgi/quartz/android 各一份），ohos 没有 → 需自建；
> - 而**客户端**必须用到 `scrap::codec::Decoder`（`src/client.rs:3683`、`src/ui_session_interface.rs:536`、`src/ui_interface.rs:1168`）。
>
> ⇒ **ohos 必须提供一个 codec 后端**（镜像 android 的 `mediacodec` 模式，新建 `ohoscodec`），否则根 crate 无法编译。
> 执行策略：**先最小实现（打通编译）→ P4 填入 HarmonyOS `AVCodec` 硬解 H.264/H.265**。

> **架构对标（重要，已核实）**：**iOS 是纯控制端**——`src/lib.rs` 把 `mod server` 与 `mod rendezvous_mediator` 都用
> `#[cfg(not(any(target_os = "ios")))]` 排除，且 `flutter_ffi.rs` 中所有 `rendezvous_mediator` 调用都带
> `#[cfg(target_os = "android")]`。ohos 应对齐 iOS：**先做纯控制端**（无 host/被控）。
> 连带影响：`Encoder`/`EncoderCfg` 与 `server/video_service.rs`、`server/connection.rs` 是 host 侧使用者，
> 因此 codec 门控必须与 `server` 门控配套决策（二者耦合）。

> **VPX/AOM 符号的替代方案权衡（执行时择优）**：
> - 方案 A-1「门控 `codec.rs`」：约 14 处 VPX/AOM 分支需加 cfg，并连带决定 `server` 是否排除（iOS 先例支持排除）。
> - 方案 A-2「shim 模块」：新增 `ohos` 版 `vpxcodec`/`aom`，但需复刻 ~28 个公开项 ×2，重复面大、易漂移。
> - 结论：**采用 A-1**（改 `codec.rs` + 对齐 iOS 的 `server` 门控），shim 仅保留最小必要（若 EncoderCfg 形状需要）。

### P2 · N-API 桥接层
> **方案已定（§7.3）**：不用手写 C++，改用 **`ohos-rs`**（napi-rs 的 OpenHarmony fork）。
> crates.io 上的名字是 `napi-ohos` / `napi-derive-ohos` / `napi-build-ohos`（1.2.0）。
> crate 位置：`flutter/ohos/native/`，`[lib] name = "rustdesk_ohos"` → 产出 `librustdesk_ohos.so`，
> ArkTS 侧 `import bridge from 'librustdesk_ohos.so'`。构建需设 `OHOS_NDK_HOME`。
- [x] 搭建 `flutter/ohos/native/` 骨架并**验证工具链打通** ✅
  - `cargo build --release --target aarch64-unknown-linux-ohos` → Finished
  - 产物 `librustdesk_ohos.so`（0.59 MB）验证为 AArch64 ELF，且导出 **`napi_register_module_v1`**（HarmonyOS NAPI 加载器入口）
- [x] **接入 RustDesk 核心** ✅ `rustdesk`（lib target 名 `librustdesk`）作为 path 依赖，**首批 15 个导出**已包成 `#[napi]`
  - 产物 `librustdesk_ohos.so` **1.89 MB**，AArch64 ELF，**16/16 导出符号实测全部在位**
  - 已接入：`bridgeVersion`、`mainGetVersion`、`mainGetBuildDate`、`mainGetMyId`、`mainGetUuid`、`mainIsUsingPublicServer`、`mainGetProxyStatus`、`mainGetAppName`、`mainGetLicense`、`mainGetConnectStatus`、`mainGetApiServer`、`mainGetLastRemoteId`、`mainGetLanPeers`、`mainGetNewStoredPeers`、`mainGetOptions`
  - ⚠️ **仅限"朴素类型"导出**（参数/返回为 String/bool 等）。其余三类需专项决策：
    - 返回 `SyncReturn<T>` → 需**拆包**（它是 flutter_rust_bridge 的"同步返回"标记，NAPI 无对应物）
    - 收 `StreamSink` → 是事件通道，ohos 改用自带投递路径（见 `push_ui_event` 预留分支）
    - 收 `SessionID`(UUID 串) → 需定 ArkTS 侧会话标识方式
- [x] **第二批导出：`SyncReturn<T>` 族** ✅
  - 关键认知：`SyncReturn<T>` 是 `pub struct SyncReturn<T>(pub T)` —— flutter_rust_bridge 的"同步返回而非 Future"**标记**，本身不承载额外数据；NAPI 里"返回朴素值"本来就是同步的，**故用 `.0` 拆包即可**
  - 已接入：`mainGetOptionsSync`、`mainGetAppNameSync`、`mainUriPrefixSync`、`mainGetLoginDeviceInfo`、`getLocalKbLayoutType`、`mainGetOptionSync(key)`、`mainGetPeerSync(id)`、`getNextTextureKey`、`peerGetSessionsCount(id, connType)`
  - 产物 `librustdesk_ohos.so` **2.05 MB**，实测 **25/25 导出符号全部在位**
- [ ] 第三批：`SessionID` 族（`session_*`）—— 需先定 ArkTS 侧会话标识（建议透传 UUID 串，与 Flutter 侧一致）
- [x] **第三批：`SessionID` 族** ✅
  - **约定**：核心的 `SessionID` 是 `uuid::Uuid`；ArkTS 无此类型，故**以标准连字符 UUID 串传递**（与 Flutter 侧一致，便于日志/交叉引用统一）
  - 解析失败**不 panic**（跨 NAPI 边界 panic 会终止应用），而是走"会话不存在"的负结果分支
  - 已接入：`sessionIsMultiUiSession`、`sessionGetIsRecording`、`sessionGetEnableTrustedDevices`、`willSessionCloseCloseSession`、`sessionIsKeyboardModeSupported(id,mode)`、`sessionGetToggleOptionSync(id,arg)`、`sessionGetReverseMouseWheelSync(id)`
  - 产物 `librustdesk_ohos.so` **2.07 MB**，实测 **32/32 导出符号全部在位**
- [x] 🔴→✅ **核心生命周期已接通**（真机验证待做）
  - 桥接新增导出 `mainSetHomeDir` / `mainDeviceId` / `mainDeviceName` / `mainInit` / `mainGetAsyncStatus` / `mainGetError`，
    `EntryAbility.onCreate` 最先调用（用沙盒 `context.filesDir`），顺序对齐 Flutter 的 `native_model.dart`
  - **但仅接通生命周期还不够** —— 真正的根因在 `hbb_common`：`Config::path()` 与 `Config::get_home()` 的平台分支
    只列了 android/ios，而 **ohos 是 `target_os="linux"` + `target_env="ohos"`**，于是两者都走了桌面回退：
    - `path()` → `ProjectDirs`，**无 ohos 条目 → 返回空路径** ⇒ 核心写的配置全落在进程工作目录
    - `get_home()` → `dirs_next::home_dir()`，沙盒内无有效值
  - `Config::get_id()` 在存储为空时会**生成随机 ID 并持久化**；路径不可解析 ⇒ 写入无效 ⇒
    **每次启动都重新生成** ⇒ 这正是"设备 ID 每次冷启动都变"的真正根因（此前被误当作独立问题）
  - 已在 `libs/hbb_common` 修复（第 4 个补丁），并顺带把 `gen_id()` 归入移动端分支（原本在 ohos 上走桌面分支去读 hostname 选项）
  - 另补：**ohos 上核心此前完全没有日志**（android/ios 各有一块，ohos 两者都不进），已接入文件日志
- [x] **NAPI 模块的 `.d.ts` 类型声明**（应做，但**不是**闪退根因 —— 见下一条）
  - hvigor 警告 *"module for 'librustdesk_ohos.so' is not verified ... make sure the corresponding
    `.d.ts` file is provided"*，且说明后续 SDK 会强制校验
  - 已新增 `entry/src/main/types/librustdesk_ohos/{index.d.ts, oh-package.json5}`，并在 `entry/oh-package.json5` 声明依赖
  - ⚠️ **坑**：类型声明**不能放 `entry/src/main/cpp/` 下** —— 该目录一旦存在，hvigor 会认为有 CMake 原生工程，
    报 `externalNativeOptions/path does not exist`。放 `src/main/types/` 即可
  - ❌ **更正**：此处曾写"真机闪退的根因就是缺这个文件"，**该结论是错的**。加完 `.d.ts` 后应用**仍然闪退**，
    报错完全相同。真正根因见下条（libsodium），而 `nativeModule === undefined` 只是"原生模块加载失败"的表象
- [x] **真机闪退真正根因：libsodium 链接了错误架构的库** ✅ 已修复
  - 决定性证据来自 **hilog**（`.d.ts` 那条 TypeError 只是表象，hilog 才有底层原因）：
    ```
    MUSL-LDSO: relocating failed: symbol not found.
      dso=/data/storage/el1/bundle/libs/arm64/librustdesk_ohos.so s=sodium_base642bin
    MMG: [NMM:1439]key:default/rustdesk_ohos First: failed Error relocating ... symbol not found.
      Second: load module default/rustdesk_ohos failed.
    ArkCompiler: export objects of native so is undefined, so name is @normalized:Y&&&librustdesk_ohos.so&
    ```
  - **根因**：`hbb_common → sodiumoxide → libsodium-sys` 是协议核心加密（secretbox/sign/base64），
    **无法按特性裁剪**。而 `libsodium-sys 0.2.7` **只提供桌面三元的预编译归档**，对它不认识的目标会
    **回退到打包内的 Windows 构建**——构建输出直接写着：
    `cargo:rustc-link-search=native=.../libsodium-sys-0.2.7/mingw/win64/`
    那些是 **x86 目标文件**（`ssse3`/`avx2`/`avx512f`），lld 无法用于 aarch64，于是
    `sodium_base642bin` 等符号悬空 → 设备上 `dlopen` 失败 → 模块为 `undefined` → ArkTS 抛 TypeError
  - ⚠️ **线索其实早就出现过**：链接期那条 `archive member '...ssse3.o' is neither ET_REL nor LLVM bitcode`
    警告就是它，当时未深究
  - **修复**：`flutter/ohos/build_libsodium_ohos.ps1` 用 clang 直接交叉编译 libsodium
    （libsodium 无 CMake 工程、Windows 侧无 sh/make/perl 故 autotools 不可用；
    源文件清单**以 libsodium 官方 `src/libsodium/Makefile.am` 为准**解析，只取可移植实现），
    产出 `libsodium.a`（94 个源文件，0.43 MB），并校验 `sodium_base642bin` 已定义
  - ⚠️ **链接方式的关键选择**：**不能**用 `SODIUM_LIB_DIR` —— 它是**全局**变量，会把 **host** 也重定向到
    aarch64 归档，而 **host 的 build script 也需要 libsodium**（`build.rs:89` 调 `hbb_common::gen_version()`，
    而 hbb_common 依赖 sodiumoxide）→ host 链接报 `undefined reference to sodium_base642bin`。
    改用 `[target.aarch64-unknown-linux-ohos] rustflags`（**目标专属**）以**完整路径**追加该归档：
    既避开 host，也不与 mingw 那份产生搜索顺序竞争
  - 验证：`.so` 2.07 → **2.22 MB**，`llvm-readelf --dyn-syms` 显示 **sodium 符号已无未定义**
  - 这是本项目第三次遇到**同类 host/target 混淆**（前两次：`machine-uid`、`magnum-opus`）
- [ ] 事件回调（连接状态/剪贴板/会话）→ ArkTS（接上 §「push_ui_event」预留的 ohos 分支，用 NAPI ThreadsafeFunction）
- [ ] 视频帧 → XComponent surface/纹理
- [x] **打包接入 HAP：端到端链路打通** ✅
  - 部署脚本 `flutter/ohos/build_bridge.ps1`（构建 + 部署；`.so` 为构建产物、已 gitignore）
  - ArkTS 门面 `entry/src/main/ets/platform/RustDeskBridge.ets`：以带类型的 `interface` 镜像 NAPI 成员，页面不直接碰原始 import
  - `hvigorw assembleHap` → **BUILD SUCCESSFUL**，`CompileArkTS` 通过（即 `.so` import 被接受并类型检查）
  - HAP 实测 **2.54 MB**，内含 `libs/arm64-v8a/librustdesk_ohos.so`（2118 KB）
  - ⚠️ **关键坑（已修正并写入脚本注释）**：预编译 `.so` 必须放在**模块根 `entry/libs/<abi>/`**；放在 `entry/src/main/libs/<abi>/` 会**编译通过但被静默排除出 HAP**，导致"构建成功、真机加载失败"
- [x] **打包接入 HAP：端到端链路打通** ✅
  - 部署脚本 `flutter/ohos/build_bridge.ps1`（构建 + 部署；`.so` 为构建产物、已 gitignore）
  - ArkTS 门面 `entry/src/main/ets/platform/RustDeskBridge.ets`：以带类型的 `interface` 镜像 NAPI 成员，页面不直接碰原始 import
  - `hvigorw assembleHap` → **BUILD SUCCESSFUL**，`CompileArkTS` 通过（即 `.so` import 被接受并类型检查）
  - HAP 实测 **2.54 MB**，内含 `libs/arm64-v8a/librustdesk_ohos.so`（2118 KB）
  - ⚠️ **关键坑（已修正并写入脚本注释）**：预编译 `.so` 必须放在**模块根 `entry/libs/<abi>/`**；放在 `entry/src/main/libs/<abi>/` 会**编译通过但被静默排除出 HAP**，导致"构建成功、真机加载失败"

### P3 · ArkUI 重写
- [x] **鸿蒙设计规范重写** ✅ 构建通过（`hvigorw assembleHap` → BUILD SUCCESSFUL，HAP 2.62 MB）
  - **系统 `Tabs` 取代自绘 `LiquidTabBar`**（已删除）：同一个 `Tabs` 按断点切换 `vertical`/`barPosition` —— **手机=底栏，折叠屏展开/平板/2in1=侧栏**，一处组件覆盖全部形态，无 per-device 分支
  - 断点自适应：`common/Breakpoint.ets` 基于 `mediaquery` 的 `sm/md/lg/xl`（600/840/1440vp），并派生侧栏判定、页边距、内容最大宽度；`aboutToAppear` 订阅、`aboutToDisappear` 退订（否则监听会让页面无法释放）
  - 组件拆分：`components/SectionCard.ets`（统一卡片）+ `RemoteTab` / `DevicesTab` / `SettingsTab`
  - **本机 ID 改从真实核心读取**（`getMyId()` 经 NAPI），**替换掉原先本地生成的假 9 位随机数**
  - 设置页新增「核心版本 / 桥接版本 / 构建日期」行 —— 真机上可**一眼确认加载了哪个产物**（这是最省事的"原生模块是否装载"验证）
- [x] **i18n 资源化** ✅ 中文为 base、英文 `en_US` 限定词；全部字面量（含 Tab/对话框/空态/错误提示）入 `string.json`
- [x] **设计令牌 + 深色模式** ✅ `color.json`（base + `dark/` 限定词）与 `float.json`（字号/圆角/间距/最小热区）
  - ⚠️ **坑**：`sys.float.ohos_id_text_size_*` 在本机 SDK 中**不可用**（`Unknown resource name`）。已改为**自建字号令牌** `app.float.font_*` —— 既避开不可核实的系统资源名，也更符合设计令牌原则
- [x] **safe area** ✅ 页面 `expandSafeArea` 处理状态栏/手势条，内容自带内边距
- [ ] 折叠屏铰链避让（悬停态 half-fold 分区）—— 需 `display.getFoldStatus()` + `WindowAvoidArea`，尚未实现
- [ ] 无障碍细化：`accessibilityText`、焦点顺序、随系统字体缩放（当前字号用 `fp`，已可随缩放）
- [x] 页面：首页 / 设备簿 / 设置（登录、服务器、密码对话框沿用既有实现并已资源化）

#### P3b · 对齐官方组件示例（用户要求"UI 要有鸿蒙原生感觉"）

**基准**：[HarmonyOSComponentUXExamples](https://gitcode.com/HarmonyOS_Samples/HarmonyOSComponentUXExamples)（官方 ArkUI 组件示例集）。
它逐组件给出官方推荐用法，正好暴露了本项目**手搓**的地方。逐项对照如下：

| 位置 | 现状（手搓） | **应改用** | 官方示例路径 |
|---|---|---|---|
| **子页签**（最近/局域网） | `Text` + `onClick` + 手改字重/颜色 | **`ChipGroup`**（胶囊样式） | `components/navigation` 子页签 |
| **标题栏** | `Row{Image+Column+Button}` 手搓 | **`HdsNavDestination` / `EditableTitleBar`** | `components/navigation` 标题栏 |
| **列表**（设备/最近/局域网） | `Column` + `HdsListItemCard` | **`List`/`ListItem`/`ListItemGroup`**（效率型列表） | `components/container` 列表 |
| **对话框**（登录/密码/服务器） | `@CustomDialog` + `customStyle` | **`CustomContentDialog` / `SelectDialog` / `TipsDialog`** | `components/container` 弹出框 |
| **服务器设置** | 普通对话框 | **`bindSheet` 半模态面板**（设置类内容的官方形态） | `components/container` 半模态面板 |
| **设备 ID 分享** | 无 | **`QRCode`**（桌面端即用二维码分享 ID） | `components/presentation` 二维码 |
| **地址簿** | 无索引 | **`AlphabetIndexer`**（大地址簿必备，配合 `List`） | `components/presentation` 索引条 |
| **未读/状态标记** | 无 | **`Badge`** | `components/presentation` 新事件标记 |
| **操作反馈** | ❌ 无任何反馈机制 | **`promptAction.showToast`** + **`HdsSnackBar`** | `components/presentation` 即时反馈/即时操作 |
| **文件传输进度** | 无 | **`Progress`**（线性/胶囊/环形） | `components/presentation` 进度条 |
| **搜索设备** | 无 | **`Search`** | `components/input` 搜索框 |
| **登录输入框** | 裸 `TextInput` | 官方**文本框样式**（错误态/字符计数/密码样式） | `components/input` 文本框 |
| **下拉选择**（画质等） | 无 | **`Select`** | `components/action` 下拉选项 |
| **勾选**（多选删除） | 裸 `Checkbox` | 官方**列表单选/多选**形态 | `components/select` 勾选 |
| **核心操作栏** | 会话页顶部工具条手搓 | **`HdsActionBar`**（横向/垂直） | `components/action` 核心操作栏 |
| **菜单** | 无（会话页缺菜单） | **`Menu`/`MenuItem`**（含长按悬浮菜单） | `components/action` 菜单 |
| **分段按钮** | 无 | **`SegmentButtonV2`** | `components/select` |
| **数据面板** | 无 | **`DataPanel`** | `components/presentation` 数据可视化 |

**多设备形态**：官方示例覆盖 手机 / 小折叠 / 平板 / 智慧屏 / PC / 穿戴，且底栏示例明确包含
**"适配分栏布局"**与**"左右结构"** —— 与本项目 `Breakpoint.ets` 的断点切换方向一致，但其做法用的是
`HdsTabs` 自带的分栏适配能力，应参照替换自绘逻辑。

> **验收口径（用户已明确）**：① **所有功能与 API 全部复刻**（对标 iOS/mobile 端）；
> ② **UI 贴合鸿蒙官方推荐布局与规范**（以本示例集与官方 design-guides 为准）。


> **说明**：`RemoteSessionPage.ets` / `ServerSettingsDialog.ets` / `ConfigStorage.ets` 携带**本次会话之前就存在的未提交改动**（上个 agent 遗留）。因 P3 构建依赖它们，随本次提交一并入库。

### P4 · 控制端核心链路

- [x] **移除伪实现**：`RemoteSessionPage` 原来默认把 `https://rustdesk.com/web/` 装进 WebView，
  另有 `DesktopCanvas` 用 `ctx.arc` **手绘假桌面**并只记录点击 —— 两者都不是会话（网页客户端是另一个产品，
  完全不知道本应用的设备 ID 与目标）。**已全部删除**
- [x] **真实连接** ✅ 已实现，**待真机验证**
  - 桥接导出 `sessionAddSync` / `sessionStart` / `sessionClose`
  - 核心侧新增 `session_start_ohos`：`session_start_` 需要 flutter_rust_bridge 的 `StreamSink`（Dart 通道），
    ohos 无此物，故做同样的事但不带流；`io_loop` **每会话只启动一次**（显式记录，因为 Flutter 靠"流是否附加"判断）
  - `RemoteSessionPage` 生成 UUID（**ArkTS 侧**，id 必须先于注册存在；`crypto.randomUUID` 此处不可用）→ add → start；
    退出时**逆序**关闭
  - 密码从对话框/存储**传给会话**（核心需要它鉴权）
  - ⚠️ **已核实**：`mod client;` **未被门控**（`rendezvous_mediator` 对被控端才需要，ohos 与 iOS 一致地排除）
- [x] **事件通道** ✅ 实现（改用轮询队列，非 ThreadsafeFunction）
  - `push_ui_event` 的 ohos 分支把事件**入队**（上限 256），ArkTS 通过 `pollUiEvents` 取走并解析 JSON
  - ⚠️ **承重细节**：对 `Rgba` 事件**必须返回"已发送"** —— 调用方据此决定帧是否走别的路，
    答"未发送"会让核心**清掉刚解码的帧**，等于丢帧
- [x] **视频渲染** ✅ 实现，**待真机验证**
  - **不用 PixelMap**：它**无法通知内容已变** ⇒ 原地改写不重绘；每帧新建要付 `宽×高×4`（1080p≈8MB/帧）
  - 改为写入 **XComponent 的 surface**（`native/src/surface.rs`）：`OH_NativeWindow_*` 直接写缓冲区，
    **每帧不跨 N-API 边界**；参考项目亦用此路径
  - 逐行拷贝（`stride ≠ width*4`，否则斜切）、失败路径收敛为单值、**绘制失败也释放帧**（否则连解码器一起停）
- [x] **输入（触摸→鼠标）** ✅ 实现，**待真机验证**
  - `RemoteInput` 独占消息构造（核心的 JSON 契约全是字符串，易错）与**坐标映射**
    （触摸是 surface 的 vp，鼠标事件是**对端像素**）⇒ 按 `displaySize / surfaceSize` 缩放并**钳制到显示范围**；
    每手势重算而**不缓存**（旋转/折叠会改变 surface，缓存会让此后每次触摸都错位）
  - 手势：单指拖=移动指针（超过阈值才按下按钮，这样拖窗口/选文字才可用）、点按=左键、长按=右键、双指拖=滚轮
  - 两个细节防"对端卡住"：`Cancel` 释放按住的键；双指手势**抑制抬起时的点击**（第一指的 Down 已移动过指针）
  - ⚠️ `session_enter_or_leave` **有意不导出**：其函数体对移动端被门控掉，导出会"可调用但什么都不做"
- [x] **平台名** ✅ 修：`my_platform` 原本在 ohos 上报 `Linux`（Rust target 保留 `target_os="linux"`），现报 `HarmonyOS`；
  对端只对 Windows/MacOS/iOS 做特判，故新名字走通用分支（与移动端预期一致）
- [ ] **剪贴板双向同步** —— 需先做一次**移植决策**，机制已查清：
  - 现状：`clipboard` 模块对 ohos **被整体排除**（与 iOS 同样处理），故核心侧**没有**剪贴板入口
  - **Android 的做法**（可照搬）：原生侧读系统剪贴板 → 拼 `[isClient 字节][MultiClipboards protobuf]`
    → `FFI.onClipboardUpdate(buf)` → 核心 `send_clipboard_msg` → 对端；
    反向由核心回调原生 `rustUpdateClipboard(clips)`
  - 本端已有 `ClipboardBridge.ets`（读/写系统剪贴板），缺的是**核心侧的收发入口**
  - 可选路径：① 对 ohos 解禁 `clipboard` 模块中需要的部分（`create_multi_clipboards` /
    `handle_msg_multi_clipboards`），桥接加 `clipboardUpdate(buf)` 与"取回对端剪贴板"的导出；
    ② 参照 iOS 的移动端路径
- [ ] **文件传输** —— 需 `sessionAddSync(is_file_transfer=true)` + `sessionSendFiles`，且依赖文件选择器与进度回调
- [ ] **键盘（物理/软键盘）** —— 桥接已导出 `sessionInputKey`（按名）与 `sessionInputString`（整段文本，
  不受对端键盘布局影响）；ArkTS 侧尚未接软键盘与物理键映射

> **P4 的验证边界**：以上四项**均未在真机上跑过**（设备已断开）。连接链路本身已做静态核实
> （`client` 未门控、rendezvous 地址解析走 `custom-rendezvous-server` 选项且有 PROD 回退、
> 5 层依赖与未定义符号检查通过）。**真机上第一件要确认的是状态条是否变成"已连接"**
> —— 那代表有帧到达；若状态条通了而画面黑，问题就落在 surface 写入那一段，而不是连接链路。

### P5 · 收尾
- [ ] 权限对齐 `module.json5`
- [ ] 被控/屏幕共享评估（AVScreenCapture 系统级）
- [ ] 签名/发布（HAP、AGC）
- [ ] UxTestService 回归

---

## 5. 关键技术难点

1. **屏幕采集/被控（已更正，原判断有误）**：
   - 原写「本机 SDK 无 `@ohos.multimedia.avScreenCapture`（system 级），该 API 不存在」——**这是错的**。
     实测：`media.createAVScreenCaptureRecorder()` / `AVScreenCaptureRecorder` **确实存在**，
     定义在 `@ohos.multimedia.media.d.ts`，**自 API 12 起为公开 API**，
     标注 `@syscap SystemCapability.Multimedia.Media.AVScreenCapture`，**函数上没有 `@permission` 标注**；
     权限表中有 `ohos.permission.CAPTURE_SCREEN`(API 7)、`CAPTURE_SCREEN_ALL`(13)、
     `EXEMPT_CAPTURE_SCREEN_AUTHORIZE`(15)，最后一项的存在说明常规流程是**系统授权弹窗**而非仅系统应用可用。
   - 因此**真实的限制**是：① 该 syscap 并非所有设备都有（hvigor 已给出 "not supported on all devices" 警告）；
     ② 需要走屏幕采集授权流程；③ 被控端仍属高风险能力，且对标 iOS 同为后置。
   - 现有 `ScreenCaptureBridge.ets` 的**真实缺陷**是：`init` 用了 `fd: 0`（无意义）、
     未做 syscap 检查、未处理授权与错误分支。
   - 结论不变（**被控/屏幕采集后置**），但**理由要改**：不是"平台没有 API"，而是"需授权流程 + 设备能力差异 + 产品定位裁剪"。
2. **输入注入**：控制端只"发送"输入（走网络），不受限；被控端才需本机注入（受限）。
3. **Rust 交叉编译**：需 `rust-ohos` 目标（OpenHarmony SIG），musl libc，部分 crate 可能需 patch。
4. **后台保活**：`KEEP_BACKGROUND_RUNNING`。

---

## 5.1 进展日志

### 已解决的构建阻塞（Windows 主机 → aarch64-unknown-linux-ohos）

| # | 阻塞 | 现象 | 解决 |
|---|---|---|---|
| 1 | `dlltool.exe` 缺失 | windows-gnu 主机编译 `windows-sys` 报 `error calling dlltool` | 从 TUNA MSYS2 镜像取 `mingw-w64-x86_64-binutils` + 依赖 DLL，置于 `~\mingw-tools\mingw64\bin` 并加入 PATH |
| 2 | `openssl-sys` 找不到 OpenSSL | ohos 目标无系统 openssl | 用 prebuilt `ohos-rs/ohos-openssl`（`prelude/arm64-v8a`），经 `AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_DIR` 注入 |
| 3 | DevEco 路径含空格 | `--sysroot=D:\Program Files\...` 被 cc crate 按空格切分 → clang 报 no such file | 建无空格 junction `C:\ohos-ndk` → DevEco `native` 目录；更新 `.cargo/config.toml` 与构建脚本 |
| 4 | `machine-uid` build.rs 误判 | `#[cfg(target_os="windows")]` 在 build.rs 里判定的是**主机**，交叉编译到 ohos 仍编译 `win.cpp` | hbb_common：把 `machine-uid`/`mac_address`/`default_net` 的 cfg 门从 `not(any(android, ios))` 扩为含 `target_env = "ohos"` |
| 5 | `libs/base` 桌面 Linux 模块 | `platform::linux` 在 ohos 下被编译，引用 `sctk`(Wayland)/`users` 失败 | `libs/base/src/platform/mod.rs`：`#[cfg(all(target_os="linux", not(target_env="ohos")))]` |
| 6 | GStreamer/GTK 被拉入 | 根 `Cargo.toml` 无条件启用 `scrap/wayland` → gstreamer → `glib-sys` 编译失败 | 根 `Cargo.toml` 拆两个 target 段：非 ohos 启 `wayland`，ohos 用无特性 `scrap` |
| 7 | openssl 被迫走 vendored | 根 `Cargo.toml` 对 `any(linux, android)` 启用 `openssl/vendored`，覆盖了 prebuilt，转去编译 openssl 源码（需 perl，本机无） | 该 dep 的 cfg 加 `not(target_env = "ohos")`，ohos 改用 prebuilt + `AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_DIR` |

### ⛔ 当前唯一阻塞：`nix` 0.26.4 无法为 ohos 编译

根 crate 检查的报错集中在 `nix`（51 个错误）：`mq_*` / `aio_*` / `__fsword_t` / `O_FSYNC` / `XFS_SUPER_MAGIC` / `ST_RELATIME` / `FDPIC_FUNCPTRS` / `UNAME26` 在 ohos 的 `libc` 中不存在，另有 2 处类型不匹配与 1 处 `SigevNotify` 非穷尽匹配。

**根因**：`nix` 以 `target_os = "linux"` 判定并按 **glibc** 假设编译 `mqueue`/`aio`/`personality`/`fs`(statfs)/`signal`；ohos 虽是 `target_os = "linux"`，但 libc 是 musl 风格、缺这些 glibc 专有符号。

**依赖链**：`nix@0.26.4` ← `webrtc-util@0.11.0`（rustdesk-org/webrtc fork）← `interceptor` ← `webrtc@0.13.0` ← `hbb_common`。

**关键事实**：`webrtc` 是客户端**核心传输路径**（`client.rs` transport racing、`rendezvous_mediator.rs` answerer），**不能靠关特性绕过**；而 `webrtc-util` 对 `nix` 的使用**仅一处**：`util/src/lib.rs` 的 `nix::ifaddrs::getifaddrs()` 与 `nix::sys::socket::{AddressFamily, SockaddrLike, SockaddrStorage}`。

**候选方案**：
| 方案 | 做法 | 体积 | 评价 |
|---|---|---|---|
| N1 | vendor `nix` 0.26.4，给失败项加 `not(target_env="ohos")` cfg 门，`[patch.crates-io]` 指本地 | 108 文件 / 1426 KB | 改动面小但仓库膨胀大；nix 0.26.4 已冻结，同步负担低 |
| **N2（推荐）** | vendor fork 的 `webrtc-util`（314 KB / 53 文件），把唯一一处 `nix` 用法换成直接 `libc`（对齐既有 Android `platform/android_ifaddrs.c` 做法），现有 `[patch.crates-io] webrtc-util` 改为本地 path | 53 文件 / 314 KB | 体积极小、语义最正确、与既有 Android 先例一致；代价是需跟随 fork rev 同步 |
| N3 | 升 `webrtc` 0.13 → 0.14+（`webrtc-util` 0.12 可能不再依赖 nix） | — | hbb_common 注释说明 0.13 是为兼容 Rust 1.75 而钉住；本机 Rust 1.98 虽满足，但属**跨平台大范围依赖升级**，超出移植 PR 范围 |

> ⚠️ **临时措施（需后续处理）**：根 `Cargo.toml` 中 `portable-pty`（`rustdesk-org/wezterm` 巨型 fork）已临时注释停用。
> 原因：cargo 解析 lockfile 时会拉取全部 git 依赖（即使该依赖对当前 target 已被 cfg 排除），而该 wezterm fork 体积过大且在本机网络上**反复停滞**（已卡在 index-pack 阶段十余分钟）。它仅被**桌面端终端功能**使用，对 ohos 目标本就被 `not(any(android, ios, ohos))` 排除，因此不影响 ohos 构建；但**桌面端构建的终端功能会缺失**，需在正式提 PR 前恢复（或在 CI/良好网络下重新拉取该依赖）。
> 连带影响：`Cargo.lock` 相应移除 `portable-pty` 条目。

### 当前状态
- ✅ `hbb_common` / `base` / `scrap`：`cargo check` **通过**
- ✅ **根 crate：`cargo check --lib --target aarch64-unknown-linux-ohos --features flutter` → exit 0**
  （即 **P1 核心里程碑达成**：依赖图全通 + 根 crate 类型检查通过）
- 🔄 待验证：`cargo build --release` 的**链接**阶段能否产出 `librustdesk.so`
- ⏳ 待清理：143 条 warning（多为门控工作留下的 unused import）
- 构建脚本：`flutter/ohos/rust_ohos_build.ps1`（封装全部交叉编译环境变量）

### scrap 的处理方案（已定：方案 A）
**方案 A（采纳，符合"尽量用鸿蒙原生组件和 SDK"）**：ohos 不引入 libvpx/aom/libyuv，采集与解码改走 HarmonyOS 原生能力（`AVCodec` 硬解 H.264/H.265、`AVScreenCapture`/系统屏幕共享能力）；scrap 对 ohos 只保留最小面（convert/record + ohos 原生 codec 后端）。
- 理由：与鸿蒙原生硬解一致、HAP 体积小、免去 3 个 C 库的交叉编译与长期维护成本。
- 代价：ohos 端需在 P4 实现原生 codec 后端；VP8/VP9/AV1 软解不作为 ohos 目标（由会话协商保证使用 H.264/H.265）。
- 备选方案 B（不采纳）：交叉编译 libvpx/aom/libyuv（OpenHarmony SIG 有 `third_party_*` 移植），完整沿用现有软解链路。

---

## 6. UI/UX 规范要求（鸿蒙官方规范，强制）

> 目标：**一多（One-Many）自适应**——手机 / 折叠屏（展开-折叠）/ 平板 / 2in1，全部按 HarmonyOS 官方设计与开发规范实现。

### 6.1 设备形态与断点
- `module.json5` 的 `deviceTypes` 已含 `phone` / `tablet` / `2in1`，需补齐折叠屏相关适配。
- 采用**断点（breakpoint）驱动**的自适应布局（`sm` / `md` / `lg` / `xl`），而非 if-else 写死尺寸：
  - `sm`（手机竖屏）：单列，底部 `Tabs`。
  - `md`（手机横屏 / 折叠屏展开 / 小折叠）：双栏（列表 + 详情）。
  - `lg` / `xl`（平板 / 2in1）：分栏（侧边导航 + 内容 + 可选详情面板）。

### 6.2 折叠屏专项
- 使用 `display` / `window` 能力监听**折叠状态与形态变化**（`windowSizeChange`、折叠态 `foldStatus`），状态变化时重排而非重建。
- **避让折痕/铰链区**（悬停态 half-fold）：内容不跨越铰链，用 `WindowAvoidArea` / `display.getFoldStatus()` 布局。
- 悬停态（half-fold）考虑"上屏预览 + 下屏操作"的分区交互。
- 窗口尺寸变化需保持会话状态不丢失（远端会话不因折叠而断开）。

### 6.3 官方设计规范落地
- **ArkUI 声明式范式**：系统组件（`Tabs`/`List`/`Grid`/`Navigation`/`SideBarContainer`/`Search`/`Dialog`）优先，不手绘可替代控件（现有 `LiquidTabBar` 自绘拖拽胶囊需替换为系统 `Tabs` + 规范动效）。
- **设计令牌**：颜色/字号/圆角/间距一律走 `resources/base/element/*`（含 `dark/` 深色限定词目录），禁止硬编码 `#RRGGBB` 与裸 `fontSize(14)`。
- **多语言**：全量资源化到 `resources/*/element/string.json`（含 `en_US` / `zh_CN` 等限定词），对齐 `src/lang/*.rs` 的 key 集合，禁止中文字面量写在代码里。
- **深色模式 / 主题**：支持 `dark` 限定词资源与主题切换。
- **无障碍**：`accessibilityText` / 焦点顺序 / `fontScale` 跟随系统字体缩放 / 最小点击热区（≥ 40vp）。
- **动效**：遵循规范时长与曲线（`Curve.Friction`/`EaseInOut`，≤ 300ms），避免自造夸张动效。
- **安全区**：使用 `expandSafeArea` / `WindowAvoidArea` 处理状态栏、挖孔、手势条。
- 视口单位优先 `vp`/`fp`，避免 `px`；栅格用 `GridRow`/`GridCol`。

### 6.4 现有 UI 需改造的点（对应 §3 BUG 清单）
- `LiquidTabBar.ets`：自绘拖拽 → 系统 `Tabs`（自适应底栏/侧栏切换）。
- 所有页面：硬编码颜色/中文/尺寸 → 资源化 + 断点自适应。
- 各 `CustomDialogController` 弹窗 → 规范组件与统一动效。

---

## 6. 本地参考资源

- SDK 接口：`D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\ets\api\*.d.ts`
- 离线文档：`tools\arktsdoc`
- NDK：`sdk\default\openharmony\native\{llvm,sysroot}`
- 调试：`hdc.exe` / `ohpm` / `devecocli` / `tools\UxTestService` / `tools\emulator`

---

## 7. 参考项目调研（重要，已核实）

**参考工程**：`https://atomgit.com/OpenHarmonyPCDeveloper/ohos_rustdesk`（OpenHarmonyPCDeveloper 组织，AGPL-3.0，已 clone 到 `C:\Users\Administrator\ref-ohos-rustdesk`）

### 7.1 结论：架构与本方案一致（互相印证）

其 README 原文：「**HarmonyOS 原生壳工程 + RustDesk Rust 内核 HAR** 的混合架构」——
ArkTS/ArkUI 原生壳 + `rustdesk-ohrs.har`（Rust 内核以 HAR 形式嵌入）。**与本计划 §1 架构完全一致**（原生 UI + Rust 核心 + NAPI 桥接）。

其目标 SDK：`targetSdkVersion 6.1.0(23)`（即 HarmonyOS 6.1.0 / API 23）。可见华为版本命名是 `HarmonyOS <X.Y.Z> (<API>)`，本机 `26.0.0 / API 26` 属另一条发布线，均可用。

### 7.2 范围印证：纯控制端，且主动裁剪

其 T0/T1/T2 分级中 **明确标注"未落地"**：摄像头、**被控端**、文件传输、语音通话，并说明理由是「平台安全策略的主动裁剪」。
⇒ **印证本计划 §8 决策 2**（先做纯控制端、被控/屏幕共享后置），且被控受限是平台既有事实，不是我们能力问题。

### 7.3 🔑 关键收获：`ohos-rs` 才是 P2 桥接层的正确工具

**`https://github.com/ohos-rs/ohos-rs`**（243★）：*"A framework for building compiled OpenHarmony SDK in Rust via Node-API (Forked from napi-rs)"*。

⇒ **P2 方案调整**：原计划「手写 C++ N-API 层包装 `flutter_ffi.rs` 的 C ABI」**改为直接用 `ohos-rs`**——在 Rust 里写 NAPI 导出（`#[napi]`），产出 HAR 供 ArkTS `import`。
- 优势：无需手写 C++；Rust 侧类型/事件可直接暴露；是参考项目走通的成熟路径（其 HAR 名为 `rustdesk-ohrs`）。
- 影响：P2 从「高不确定度的手工桥接」降级为「按框架约定导出函数」，大幅降低风险。

### 7.4 ArkTS ↔ Rust 契约（从其公开 ArkTS 代码逆推，可直接借鉴）

| 观察 | 内容 | 对本项目的意义 |
|---|---|---|
| **渲染** | `RustDeskSurfaceController extends XComponentController`，`onSurfaceCreated(surfaceId)` 把 `surfaceId` 交给 Rust | 印证 P2/P4「视频帧 → XComponent surface」，最小实现仅 17 行 |
| **桥接风格** | **轮询式**：`EVENT_POLL_INTERVAL_MS = 50`；`ActionResponse { ok, action, message?, session?, events?, stats? }` | 比回调/threadsafe function 简单得多，建议照搬 |
| **事件协议** | `NativeEvent` 字段即 RustDesk 原生事件名（`name/content/type/secure/direct/stream_type/id/hostname/platform/version/displays/resolutions/current_display/title/fps/delay/codec_format/x/y/hotx/hoty/colors/gpu_texture/file_num/finished_size/err/read_path/is_upload...`） | 说明其 Rust 侧直接复用了 RustDesk 既有 `push_event` 事件流；我们亦可复用 `src/flutter.rs` 的事件机制 |
| **解码能力** | `DecoderCapability { codec, mime, mimeAvailable, recommendedIsHardware, hardwareAvailable, softwareAvailable, ... }` | **`mime` 字段 = HarmonyOS AVCodec 的 MIME（video/avc、video/hevc）** ⇒ **证实方案 A**：他们确实实现了鸿蒙原生 codec 后端 |
| **GPU** | `NativeEvent.gpu_texture?: boolean` | 存在 GPU 纹理渲染路径（对应 `sessionRegisterGpuTexture`） |
| **自研 API** | `RenderStatsSnapshot { fps, totalFrames, lastFrameAgeMs, hasRenderedFrame, decodeLatencyMs, avgDecodeLatencyMs }` | 上游 RustDesk 无此 API，系其自行扩展 ⇒ 统计面板需在 Rust 侧新增导出 |

### 7.5 可借鉴的 ArkTS 模块清单（P3/P4 直接参考）

`entry/src/main/ets/pages/rustdesk/`（约 40 个文件）：
- 桥接：`RustDeskMainBridge.ets`(14.4KB)、`NativeSessionBridge.ets`(7.1KB)、`RustDeskTypes.ets`
- 输入：`RustDeskInputController.ets`(33.8KB)、`RustDeskInputMapper.ets`(16.8KB)、`RustDeskTouchGestureState.ets`、`RustDeskPressedButtonState.ets`
- 显示：`RustDeskViewportModel.ets`(7KB, 分辨率适配)、`RustDeskCursorModel.ets`(5.1KB)、`RustDeskSurfaceController.ets`、`SessionDisplayController.ets`
- 系统能力：`RustDeskClipboardController.ets`、`TransferManager.ets`(17KB)、`services/DataTransferBackgroundService.ets`
- UI：`components/`（`SettingsTab`(32.5KB)、`ConnectTab`、`PeerCard`、`SessionToolbar`(20.3KB)、`FloatingSegmentedControl`、`AmbientOrbitBackdrop` 等）
- **资源已有 `resources/dark/element`（深色模式限定词）** ⇒ 印证 §6.3 设计令牌/深色模式要求
- README 明确「采用 **HDS（HarmonyOS Design System）** 视觉规范与动效体系」⇒ 与 §6「全按鸿蒙官方规范」一致

### 7.6 本参考项目**不能**解决的部分

- **其 Rust 内核源码未公开**（`OpenHarmonyPCDeveloper/rustdesk_native_har` 等均 404/403），因此**看不到他们如何解决 nix / webrtc / scrap / glibc 兼容问题** ⇒ 本计划 §「当前唯一阻塞」及后续 Rust 侧工作仍需自行完成。
- 但反过来说：**存在一个可运行的成品，证明这条路是通的**，且其暴露出的 API 形状可作为我们 Rust 侧接口设计的验收参照。
- 该组织另有 `lycium_plusplus`（OpenHarmony 三方库移植构建框架），若将来需交叉编译 libvpx/aom 等 C 库（方案 B）可参考。

### 7.7 对计划的净影响

- **P2 重构**（改为 `ohos-rs`）：风险显著下降、工作量下降。
- **P3/P4**：有可直接参考的成品实现（输入映射、视口适配、光标、剪贴板、UI 结构与深色模式）。
- **P1 不变**：Rust 核心交叉编译仍需我们自行攻坚（参考项目未公开该部分）。
