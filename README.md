# MiniMaxQuota (token-left-minimax)

macOS menu-bar app that shows your [MiniMax](https://platform.minimax.io) Token Plan quota
in real time. Wraps the official [`mmx` CLI](https://www.npmjs.com/package/mmx-cli) and
reads from `mmx quota show`.

<!-- TODO: replace with a real screenshot of the popup + floating card -->

## Features

- 菜单栏图标 + 最低剩余百分比数字(实时)
- 中文 popup:每个 model 的**小时 + 周**两条独立进度条
- 周期起止时间 + 倒计时(小时/分/秒)
- 桌面悬浮小窗(可拖、always-on-top)
- 可配置刷新间隔(15 秒 / 30 秒 / 1 分钟 / 5 分钟)
- 手动立即刷新
- **首次运行自动检测 mmx CLI** —— 没装的话直接在 popup 里给安装命令 + 一键复制,不用翻文档
- **不存储 API key** —— 完全通过 `mmx` 子进程访问,key 由 `mmx` 自己在 `~/.mmx/config.json` 管理

## Install

### 1. 下载 app

从 GitHub **Releases** 页面下载最新的 `MiniMaxQuota-v0.1.0.zip`
([Releases](../../releases))。

### 2. 解压并放到 Applications

```bash
unzip MiniMaxQuota-v0.1.0.zip
# 把 MiniMaxQuota.app 拖到 /Applications/ (或任何你喜欢的位置)
```

### 3. 第一次启动需要绕过 Gatekeeper(ad-hoc 签名)

```bash
xattr -dr com.apple.quarantine /Applications/MiniMaxQuota.app
open /Applications/MiniMaxQuota.app
```

不跑 `xattr` 那行也可以,只是首次启动要右键 → 打开。

### 4. 装 mmx CLI(如果还没装)

第一次打开 app,菜单栏图标会变成 ⚠️ 橙色三角警告,popup 里会直接列出安装命令,带"复制"按钮:

- **Homebrew**:`brew install mmx-cli`
- **npm**:`npm install -g mmx-cli`  (需要 Node.js 18+)

装完点 popup 底部的 **"我已安装,重新检测"** 按钮,app 就会重新扫描磁盘,图标变回条形图,开始拉数据。

### 5. 登录 MiniMax 账号

```bash
# OAuth 浏览器跳转
mmx auth login

# 或直接粘 API key
mmx auth login --api-key sk-xxx...
```

验证能拉到数据(应输出几行 quota):

```bash
mmx quota show
```

装好后菜单栏右上角应出现条形图图标 📊 + 一个数字(最低剩余百分比)。

## Troubleshooting

**菜单栏图标是橙色 ⚠️ 三角**

popup 里会直接列安装命令。如果装完没自动识别,点 **"我已安装,重新检测"**。

**菜单栏图标不出现 / popup 是空的**

- 检查 `mmx quota show` 在终端里有没有输出
- 检查 `mmx auth status` 显示已登录
- 看 popup 里有没有红字"未检测到 mmx CLI"提示

**popup 显示"加载中…"一直不变**

- 等 60 秒(默认刷新周期),或点"立即刷新"
- 看 Console.app,filter 填 `MiniMaxQuota`,看有没有红色错误

**想卸载**

```bash
./uninstall.sh
# 或手动:
rm -rf /Applications/MiniMaxQuota.app
```

**不**会删 `mmx` 或 `~/.mmx/config.json`(那是用户自己管的)。

## Where is my API key stored?

**Nowhere in this app.** MiniMaxQuota never sees, touches, stores, or transmits
your API key. It only shells out to `mmx` and parses the quota JSON it gets back
on stdout.

The key itself is managed entirely by the `mmx` CLI, and lives in:

```
~/.mmx/config.json
```

with permissions `-rw-------` (only your user account can read it). That file is
created the first time you run `mmx auth login` and is owned by the `mmx` CLI —
this app never opens, modifies, or copies it.

### How to log in

```bash
# OAuth flow (browser handoff)
mmx auth login

# or paste a key directly
mmx auth login --api-key <your-api-key>
```

Verify it's wired up:

```bash
mmx auth status    # should print "logged in"
mmx quota show     # should print quota rows
```

### Switching accounts or moving to a new machine

```bash
# log out (deletes ~/.mmx/config.json)
mmx auth logout

# log in again
mmx auth login
```

To copy your login to another machine, just copy `~/.mmx/config.json` over (it
contains the cached token, so treat it like a password).

## Privacy & security

- 本 app **不读、不存、不上送**你的 API key —— 上面那一节是详细说明
- 全部数据流是:`mmx` 子进程 → stdout JSON → Swift `JSONDecoder` → SwiftUI,**不接触 key 字段**
- app 进程不联网,所有网络请求都走 `mmx` 子进程

## Build from source

需要 macOS 13+ 和 Swift 5.9+ (Xcode Command Line Tools 即可,不需要完整 Xcode)。

```bash
git clone <this repo>
cd MiniMaxQuota

# debug build + run
swift build
./bundle.sh
open MiniMaxQuota.app

# release build + zip
./distribute.sh
# 产出: MiniMaxQuota-v0.1.0.zip
```

`distribute.sh` 用 `xcrun swiftc` 直接编译(不走 SwiftPM 驱动),避免在受限环境下 `swift build` 嵌套 `sandbox-exec` 失败 —— 单 target executable package 下二者等价。

## Releasing a new version

1. 改 `MiniMaxQuota.app/Contents/Info.plist` 里的 `CFBundleShortVersionString`
2. 跑 `./distribute.sh` 生成新 zip
3. `git tag v0.2.0 && git push --tags`
4. 在 GitHub 上开 Release,把 zip 作为 binary asset 拖上去

## Distribution note

当前 **ad-hoc 签名**,接收方 macOS 会弹"未识别开发者"警告。两种绕开方式:

- (推荐)接收方跑 `xattr -dr com.apple.quarantine /Applications/MiniMaxQuota.app`
- (不太推荐)接收方右键 app → "打开方式" → 选"打开"

要彻底去除警告,需要 **Apple Developer ID**(年费 $99)。本项目目前未公证。

## License

MIT
