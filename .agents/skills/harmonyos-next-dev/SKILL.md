---
name: harmonyos-next-dev
description: >-
  Expert guidance, toolchain configurations, build procedures, and platform bridging
  for developing and porting Flutter and Rust applications to HarmonyOS NEXT (API 12+)
  and OpenHarmony. Use when working on HarmonyOS / OpenHarmony compilation, Flutter-OHOS
  integration, ArkTS native shell, or HarmonyOS capability bridging (AVScreenCapture,
  Pasteboard, FilePicker, Permissions).
---

# HarmonyOS NEXT (API 12+) 开发与移植指南

本 Skill 专用于指导在纯血鸿蒙（HarmonyOS NEXT / OpenHarmony 5.x/6.x，API 12+）环境下进行 Rust 底层核心交叉编译、Flutter-OHOS 应用开发及系统原生能力桥接。

---

## 1. 核心技术栈与架构

```
┌────────────────────────────────────────────────────────┐
│               Flutter-OHOS Dart 业务层                  │
│       (复用移动端 UI 界面、手势控制、虚拟键鼠等)            │
└───────────────────────────┬────────────────────────────┘
                            │ MethodChannel / dart:ffi
┌───────────────────────────▼────────────────────────────┐
│              HarmonyOS 原生层 (ArkTS / C++)             │
│   • FlutterAbility (应用入口与生命周期管理)               │
│   • 系统能力桥接 (@ohos.pasteboard, @ohos.file.picker)  │
│   • 屏幕共享 (@ohos.multimedia.avscreencapture)         │
└───────────────────────────┬────────────────────────────┘
                            │ DynamicLibrary.open()
┌───────────────────────────▼────────────────────────────┐
│             librustdesk.so (Rust 跨平台核心)            │
│   • Target: aarch64-unknown-linux-ohos                 │
│   • 协议通信 (Rendezvous / Relay / WebRTC / KCP)        │
│   • 视频解码 / 会话状态机 / 加密鉴权                     │
└────────────────────────────────────────────────────────┘
```

---

## 2. Rust 交叉编译工具链 (OpenHarmony Target)

### 2.1 Rust 目标架构 (Target Triples)
- 真机主流：`aarch64-unknown-linux-ohos`
- 模拟器：`x86_64-unknown-linux-ohos`
- 32 位老旧设备：`armv7-unknown-linux-ohos`

### 2.2 关键环境变量与 Clang Linker 配置
OpenHarmony SDK 内置 LLVM/Clang 工具链。在 `~/.cargo/config.toml` 或项目 `.cargo/config.toml` 中配置：

```toml
[target.aarch64-unknown-linux-ohos]
linker = "<OHOS_NDK_PATH>/native/llvm/bin/clang"
rustflags = [
    "-C", "link-arg=--target=aarch64-linux-ohos",
    "-C", "link-arg=--sysroot=<OHOS_NDK_PATH>/native/sysroot",
    "-C", "link-arg=-D__MUSL__",
]
```

### 2.3 裁剪 Linux 桌面依赖 (Cargo.toml 关键隔离)
OpenHarmony 使用的是 `musl libc`，且**没有** X11、Wayland、GTK、PulseAudio 或 D-Bus。
在 RustDesk 中，编译给鸿蒙时需要确保：
1. `cfg(target_os = "linux")` 分支中涉及桌面特性的依赖（如 `libxdo-sys`、`gtk`、`pulse`、`x11rb`、`evdev` 等）添加 `not(target_env = "ohos")` 过滤。
2. 保持与 Android/iOS 相同的移动端网络与加密配置（使用 `openssl = { version = "0.10", features = ["vendored"] }`）。

---

## 3. Flutter-OHOS 适配与目录结构

Flutter-OHOS 是 OpenHarmony SIG 维护的官方 Flutter 端口。

### 3.1 平台目录规范 (`flutter/ohos`)
```
flutter/ohos/
├── AppScope/
│   ├── app.json5              # 声明 bundleName、vendor、icon 等
│   └── resources/
├── entry/
│   ├── build-profile.json5    # 模块构建配置
│   ├── hvigorfile.ts
│   ├── src/main/
│   │   ├── module.json5       # 声明 Ability、权限 (ohos.permission.*)
│   │   ├── ets/
│   │   │   ├── entryability/
│   │   │   │   └── EntryAbility.ets  # 继承 FlutterAbility
│   │   │   └── pages/
│   │   │       └── Index.ets         # 加载 Flutter 视图
│   │   ├── libs/
│   │   │   └── arm64-v8a/
│   │   │       └── librustdesk.so    # 放入编译好的 Rust 动态库
│   │   └── resources/
├── build-profile.json5
└── hvigorfile.ts
```

### 3.2 EntryAbility 编写规范 (ArkTS)
```typescript
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { MethodChannel } from '@ohos/flutter_ohos';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine): void {
    super.configureFlutterEngine(flutterEngine);
    // 注册鸿蒙原生系统桥接通道 (如剪贴板、系统属性等)
  }
}
```

### 3.3 Dart FFI 动态库加载
在 `flutter/lib/models/native_model.dart` 中：
```dart
DynamicLibrary _openLib() {
  if (Platform.isAndroid || isOHOS) {
    return DynamicLibrary.open('librustdesk.so');
  }
  // ...
}
```

---

## 4. 关键系统能力与权限映射

### 4.1 权限声明 (`module.json5`)
```json5
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },
  { "name": "ohos.permission.GET_NETWORK_INFO" },
  { "name": "ohos.permission.CAPTURE_SCREEN" },          // 屏幕录制与共享
  { "name": "ohos.permission.KEEP_BACKGROUND_RUNNING" } // 后台长时任务保活
]
```

### 4.2 剪贴板同步 (`@ohos.pasteboard`)
- 读取：`pasteboard.getSystemPasteboard().getData()`
- 写入：`pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)`

### 4.3 屏幕录制与广播 (`@ohos.multimedia.avscreencapture`)
- 对标 iOS 的 ReplayKit。
- 创建 `AVScreenCapture` 实例，配置 `AVScreenCaptureConfig`（分辨率、码率、帧率、音频捕获）。
- 启动录制并将编码流或原始 YUV/RGBA 送入 Rust 的采集通道。

---

## 5. 常用构建与调试命令

| 操作 | 对应命令 |
| :--- | :--- |
| **Rust 编译** | `cargo build --target aarch64-unknown-linux-ohos --release --features flutter` |
| **HAP 打包** | `hvigorw --mode module -p module=entry@default -p product=default assembleHap` |
| **查看连接设备** | `hdc list targets` |
| **安装到设备** | `hdc app install path/to/entry-default-signed.hap` |
| **抓取日志** | `hdc hilog` / `hdc hilog -T RustDesk` |
