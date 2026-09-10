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
- [ ] 根 crate（`librustdesk.so`）编译通过
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

> ⚠️ **临时措施（需后续处理）**：根 `Cargo.toml` 中 `portable-pty`（`rustdesk-org/wezterm` 巨型 fork）已临时注释停用。
> 原因：cargo 解析 lockfile 时会拉取全部 git 依赖（即使该依赖对当前 target 已被 cfg 排除），而该 wezterm fork 体积过大且在本机网络上**反复停滞**（已卡在 index-pack 阶段十余分钟）。它仅被**桌面端终端功能**使用，对 ohos 目标本就被 `not(any(android, ios, ohos))` 排除，因此不影响 ohos 构建；但**桌面端构建的终端功能会缺失**，需在正式提 PR 前恢复（或在 CI/良好网络下重新拉取该依赖）。
> 连带影响：`Cargo.lock` 相应移除 `portable-pty` 条目。

### 当前状态
- ✅ `hbb_common`：`cargo check -p hbb_common --target aarch64-unknown-linux-ohos` **通过**
- ✅ `base`：`cargo check -p base --target aarch64-unknown-linux-ohos` **通过**
- 🔄 `scrap`：build.rs 需要 libyuv/libvpx/aom（vcpkg/pkg-config）+ bindgen，且 unix 下强制 `cfg(x11)` 编译 X11/Wayland 采集后端 → **ohos 下必须改**
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
