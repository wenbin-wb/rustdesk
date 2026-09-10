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
| B3 | `ScreenCaptureBridge.ets` | `AVScreenCaptureRecorder` 在 SDK 中不存在 |
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
- [ ] `cargo build --release` 链接并产出 `librustdesk.so`（验证链接阶段）
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
- [ ] C++ napi 包装 `src/flutter_ffi.rs` C ABI
- [ ] 事件回调（连接状态/剪贴板/会话）→ ArkTS
- [ ] 视频帧 → XComponent surface/纹理
- [ ] `librustdesk.so` 放入 `entry/src/main/libs/arm64-v8a`

### P3 · ArkUI 重写
- [ ] 鸿蒙设计规范重写（系统 Tabs/List/Dialog/SettingItem）
- [ ] i18n（资源化，对齐 `src/lang/*.rs` key）
- [ ] 深色模式 / 无障碍 / safe area
- [ ] 页面：首页 / 地址簿 / 设置 / 登录 / 服务器 / 远程会话

### P4 · 控制端核心链路
- [ ] 真实连接/鉴权（rendezvous → relay/P2P → 会话）
- [ ] 视频渲染（XComponent + 硬解）
- [ ] 输入（触摸→鼠标/键盘、缩放、虚拟键鼠）
- [ ] 剪贴板双向同步
- [ ] 文件传输

### P5 · 收尾
- [ ] 权限对齐 `module.json5`
- [ ] 被控/屏幕共享评估（AVScreenCapture 系统级）
- [ ] 签名/发布（HAP、AGC）
- [ ] UxTestService 回归

---

## 5. 关键技术难点

1. **屏幕采集/被控**：本机 SDK 无 `@ohos.multimedia.avScreenCapture`（system 级），对标 iOS ReplayKit，需特殊权限，后置。
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
