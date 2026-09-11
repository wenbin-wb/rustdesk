# 交接文档（新会话从这里读起）

> 本文件为跨会话交接用。`PLAN.md` 是完整计划与历史，本文件只讲**当前状态**和**下一步**。

## 一句话现状

RustDesk 鸿蒙端（HarmonyOS API 26，ArkTS + Rust 核心）**基础链路全部打通并在真机验证**；
**唯一的大阻塞是视频解码器** —— 连接成功但黑屏，因为 ohos 上没有任何可用解码后端。

---

## ✅ 已验证可用（真机实测）

| 能力 | 证据 |
|---|---|
| 交叉编译 + N-API 桥接 | `.so` 16.2MB，4 个 NEEDED，1820 符号可解析 |
| **设备 ID 稳定** | `193 043 126 0` 冷启动不变 |
| **直连对端** | 真实会话建立，收到对端质量状态 `delay:40 / bitrate:2010` |
| **视频 surface 挂载** | `render_service: RSSurfaceRenderNodeDrawable::OnDraw name=rustdesk_surfaceSurface` |
| **账号登录 → 核心** | 地址簿 `3 books, 22 peers`，冷启动自动刷新 |
| **地址簿 UI** | 真实别名/平台图标/在线状态点（服务器数据，有在线有离线）|
| **标签** | 7 个标签全部可见，色点与账号色值逐一比对一致（`三墩 #0500FF` 对 `#0400FF` 等）|
| **筛选** | `bindSheet` 半模态；选「项目现场」→ 角标 0→1、列表 22→13 |
| **输入（触摸→鼠标）** | 代码完成、编译通过，**未真机试用** |
| **剪贴板双向** | 代码完成、编译通过，**未真机试用** |

---

## 🔴 最大阻塞：无视频画面

**根因已精确定位**（核心日志，非推测）：

```
ERROR [src/client.rs:3887] handle video frame error, unsupported video frame type!
```

`libs/scrap/src/common/codec.rs` 的 `Decoder::new` 在 ohos 上**没有可用后端**：

| 后端 | ohos 可用性 |
|---|---|
| VP8/VP9/AV1 软解 | ❌ 被 `not(target_env="ohos")` 排除（未链接 vpx/aom）|
| `hwcodec` | ❌ **源码只有 `android.rs`/`ffmpeg.rs`，零处 ohos** |
| `mediacodec` | ❌ Android 专属（依赖 ndk crate）|
| `vram` | ❌ 依赖 hwcodec |

**可行路径（NDK 中已确认存在）**：
```
<sysroot>/usr/include/multimedia/player_framework/native_avcodec_videodecoder.h  (OH_VideoDecoder_*)
libnative_media_vdec.so
native_avcodec_base.h  (MIME/格式)
```
参照 `hwcodec/android.rs` 新增 ohos 后端，解码输出**接到已就绪且已验证的 surface 链路**
（`native/src/surface.rs` 的 `OH_NativeWindow_*` 写入已确认工作）。

⚠️ 这是**一整个子系统**，不是小修补。完成后黑屏即解除。

---

## 下一步建议顺序

1. **视频解码器**（最大价值：解锁"真实画面"）
2. **真机试用手势输入**（代码已就绪，从未实际滑过）
3. **UI 收尾（P3b 剩余）**：
   - 会话页工具条 → 手搓中，应换 `HdsActionBar`
   - `RemoteTab` 子页签 → 仍是 `Text`+`onClick` 手搓，应换 `ChipGroup`
   - 对话框 → `CustomContentDialog`/`TipsDialog`
   - `QRCode` 分享设备 ID、`Progress` 文件传输
   - **硬编码颜色/字号**未令牌化（`RemoteTab` 有 8 处字号）
   - **无障碍标注 0 覆盖**（官方硬要求）

---

## 🧨 必须知道的坑（都是踩过的）

### 编译/链接
1. **`#[cfg(target_os=...)]` 在 `build.rs` 里测的是 HOST**，不是目标。用 `CARGO_CFG_TARGET_ENV`。此坑已**四次**到达设备（libsodium 架构错、libssl 未打包、`OH_NativeWindow_*` 未链接）。
2. **ohos 的 `target_os` 是 `linux`**，只有 `target_env = "ohos"` 能区分。移动端 cfg 一律写 `any(target_os="android", target_os="ios", target_env="ohos")`。
3. `cdylib` **允许未定义符号** ⇒ 构建成功、安装成功，只在 `dlopen` 失败。`build_bridge.ps1` 的依赖检查会抓它（已实测抓到过）。

### 核心契约
4. **核心用 `skip_serializing_if = "String::is_empty"` 序列化地址簿** ⇒ 空字段是**"不存在"而非空串**。接口声明必须全 optional 并 `?? ''` 取默认，否则读 `.length` 抛异常。
5. **`/api/ab/peers` 是扁平结构**（`alias`/`hostname`/`platform`/`password` 都在顶层）。`info` 嵌套属于**另一个端点**（rendezvous sysinfo）—— 混用会得到"有 ID 但全空白"的列表。
6. **地址簿列表接口用 query string**（`ab=<guid>&current=&pageSize=`）返回 `{total, data}` 并**分页**；不是 JSON body。
7. **个人地址簿必须叫 `"My address book"`**（核心与 UI 用此确切字符串识别）。
8. **`push_ui_event` 对 `Rgba` 必须返回 `true`** —— 答 false 会让核心**清掉刚解码的帧**。
9. 核心的 `mainLoadFavPeers`/`mainLoadRecentPeers` **返回值为空**，结果推到 Flutter 全局事件流（鸿蒙无此通道）。改读 `mainGetFav` / `mainLoadRecentPeersForAb`。

### 诊断
10. **核心日志不进 hilog**（那是 Android 分支），写文件：
    `<filesDir>/.local/share/logs/RustDesk/flutter_ffi/rs_rCURRENT.log`
    **`hdc file recv` 可直接读** —— Rust 侧一切问题都靠它。
11. `JSON.stringify(Error)` 是 `{}`（message 不可枚举）—— 日志要用 `e.message`，否则真 bug 被记成"什么都没有"。

### ArkTS
12. **禁止**：静态方法内 `this`、索引类型、按下标访问属性、嵌套未声明对象字面量、`any`/`unknown`。
13. **`List({ space })` 只作用于直接子项** —— 元素包在 `ListItemGroup` 里则**完全失效**。间距要设在 `ListItemGroup` 的 `space` 上。（这就是"列表全挤在一起"的真因）
14. **`ChipGroup` 不能上色**：其 `LabelOptions` 只有 `text`，图标只有 `src`/`size`。带色标签需用 `Circle`+`Text`+`Checkbox` 组合。
15. **`bindSheet` 自带右上角关闭按钮** —— 那里不能再放东西（会重叠）。
16. **悬浮栏要求内容穿透**：底部留白要用 `List.contentEndOffset`，**不是**外层 padding，否则玻璃材质背后是空的、看起来是实心灰块。
17. `@Builder` **只能有一个根节点**。

### 测试手法
18. **`uitest inputText` 是追加而非替换**，且对话框会随键盘上移 —— **每次点击前重新 dump 取坐标**，否则会点空、或把文本拼成一串。
19. `uitest uiInput keyEvent 2050` = 退格，可用于清空输入框。
20. `dumpLayout` 会把**遮挡层下方的节点也导出** —— 判断可见性要靠**截图取色**，不能只信 dump。
21. **`dumpLayout` 无 `-b <bundle>` 时会把系统浮层也混进来**。

---

## 构建与测试

```powershell
# Rust 核心 + 桥接（会做依赖/符号检查，失败即中止）
pwsh -File flutter/ohos/build_bridge.ps1

# HAP
cd flutter/ohos
$env:DEVECO_SDK_HOME = "D:\Program Files\Huawei\DevEco Studio\sdk"
$env:PATH = "D:\Program Files\Huawei\DevEco Studio\tools\node;$env:PATH"
.\hvigorw.bat assembleHap --mode module -p product=default -p module=entry@default --no-daemon

# 设备
$hdc = "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
& $hdc list targets
& $hdc install -r "entry\build\default\outputs\default\entry-default-signed.hap"
& $hdc shell aa start -b com.carriez.flutter_hbb -m entry -a EntryAbility
& $hdc shell "uitest dumpLayout -p /data/local/tmp/d.json -b com.carriez.flutter_hbb"
& $hdc file recv /data/local/tmp/d.json out.json
& $hdc shell "snapshot_display -f /data/local/tmp/s.jpeg"
& $hdc file recv /data/local/tmp/s.jpeg shot.jpeg
```

**导出三层一致性检查**：`native/src/lib.rs` 的 `#[napi(js_name)]` == `index.d.ts` 的 `export const`
== `RustDeskBridge.ets` 的 `interface RustDeskNative` 成员。当前 **81 = 81**。

---

## 环境（不在仓库内）

| 项 | 路径 |
|---|---|
| NDK junction | `C:\ohos-ndk` |
| libs junction | `C:\ohos-libs`（`prefix`=opus, `prefix-sodium`）|
| mingw | `~\mingw-tools\mingw64` |
| OpenSSL | `~\ohos-openssl\...\prelude\arm64-v8a` |
| vcpkg root | `C:\ohos-vcpkg-root\installed\arm64-linux` |
| 一键新机配置 | `pwsh -File flutter/ohos/setup_ohos_toolchain.ps1` |

**设备**：LMR-AL10，arm64-v8a，API 26，serial `4YN0225529016147`。
**注意**：本机是云 VM，**模拟器不可用**（无嵌套虚拟化，且鸿蒙模拟器镜像是 x86_64）。

---

## 用户明确的验收口径

1. **所有功能与 API 全部复刻**（对标 iOS / mobile 端）
2. **UI 贴合鸿蒙官方推荐布局与规范**（以官方 design-guides 与
   [HarmonyOSComponentUXExamples](https://gitcode.com/HarmonyOS_Samples/HarmonyOSComponentUXExamples) 为准）
3. **不希望看到手搓** —— 若官方组件确实无法满足，**先说明原因**，不要默默手搓
   （已知例外：带色标签筛选，`ChipGroup` 类型上不支持）
4. **UI 需适配折叠屏/平板**等形态

## 用户已知问题（截至交接时）

- **中继服务器配置曾被我用 `uitest inputText` 改乱**，用户已自行重填并说"不用管了"
- 用户提到"你一直在输入空格"——**已澄清是输入中继信息时的行为，不必再处理**
