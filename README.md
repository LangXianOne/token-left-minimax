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
- **不存储 API key** —— 完全通过 `mmx` 子进程访问,key 由 `mmx` 自己在 `~/.mmx/config.json` 管理

## What you need first

`mmx` CLI 必须先装(本 app 是它的 GUI 壳):

```bash
# 方式 A:Homebrew
brew install mmx-cli

# 方式 B:npm(需要 Node.js 18+)
npm install -g mmx-cli
```

登录你的 MiniMax 账号:

```bash
# OAuth 浏览器跳转
mmx auth login

# 或直接粘 API key
mmx auth login --api-key sk-xxx...
```

验证能拉到数据:

```bash
mmx quota show
```

## Install

1. 下载 `MiniMaxQuota-v0.1.0.zip`
2. 解压,把 `MiniMaxQuota.app` 拖到 `/Applications/`
3. 第一次启动需要绕过 Gatekeeper(因为是 ad-hoc 签名):

```bash
xattr -dr com.apple.quarantine /Applications/MiniMaxQuota.app
```

4. 启动:

```bash
open /Applications/MiniMaxQuota.app
```

菜单栏右上角应出现条形图图标 📊 + 一个数字(最低剩余百分比)。

## Troubleshooting

**菜单栏图标不出现 / popup 是空的**

- 检查 `mmx quota show` 在终端里有没有输出
- 检查 `mmx auth status` 显示已登录
- 看 popup 里有没有红字"需要安装 mmx CLI"提示

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

## Distribution note

当前 **ad-hoc 签名**,接收方 macOS 会弹"未识别开发者"警告。两种绕开方式:

- (推荐)接收方跑 `xattr -dr com.apple.quarantine /Applications/MiniMaxQuota.app`
- (不太推荐)接收方右键 app → "打开方式" → 选"打开"

要彻底去除警告,需要 **Apple Developer ID**(年费 $99)。本项目目前未公证。

## License

MIT
