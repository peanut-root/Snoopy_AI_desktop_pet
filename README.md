# Snoopy AI Desktop Pet · 史努比 AI 桌宠

**目前仅支持 macOS（13 或更新版本）。** 史努比会在桌面上陪你：平时和糊涂塌克在狗屋顶休息；本机 GPT 工作时坐在屋顶打字；工作结束后，查理布朗送晚饭，史努比跳起晚饭之舞。点击睡着的史努比肚子，还能唤醒它们的小互动。

![待机、工作和晚饭动作](docs/overview.png)

## 动作一览

- 待机：史努比在屋顶睡觉，32 帧呼吸带动肚子、耳朵和手的轻微起伏；糊涂塌克停在肚子上。
- 工作：史努比坐在红房子屋顶用打字机打字；检测到任务结束后，查理布朗送来晚饭，史努比跳晚饭之舞，再回屋顶休息。
- 点击肚子：糊涂塌克飞开，史努比坐起眨眼，再躺下，鸟慢慢飞回。
- 天气剧场：晴天戴墨镜看杂志并翻页；下雨时糊涂塌克带伞飞来；多云时史努比穿飞行员装；下雪时屋顶与身体逐渐积雪。

## 下载与启动

| 你的 Mac | 方式 |
| --- | --- |
| Apple Silicon（M 系列芯片） | 下载 [`dist/SnoopyDesktop-macOS-arm64.zip`](dist/SnoopyDesktop-macOS-arm64.zip)，解压，把 `Snoopy Desktop.app` 拖进「应用程序」，双击打开。 |
| Intel Mac 或想从源码构建 | 先安装 Xcode Command Line Tools，然后运行下面的命令；构建脚本会为当前 Mac 的架构编译 App。 |

```bash
xcode-select --install  # 如果此前已安装，系统会提示无需重复安装
git clone https://github.com/peanut-root/Snoopy_AI_desktop_pet.git
cd Snoopy_AI_desktop_pet
./build.sh
open "Snoopy Desktop.app"
```

此 App 使用本地临时签名，尚未经过 Apple 公证。若 macOS 首次阻止打开，请在 Finder 中按住 Control 点击 App，选择「打开」；如系统仍提示阻止，前往「系统设置 → 隐私与安全性」，对这份 App 选择「仍要打开」。只需对你确认从本仓库下载的文件这样操作。

## 首次选择天气地区

首次打开时，桌宠会请你输入城市或地区（例如「上海」「北京」「Tokyo」），并让你从搜索结果中确认具体地点。同名城市可通过省份、国家区分。天气地区会保存在这台 Mac 上，以后可从桌宠右键菜单 **「天气小剧场 → 选择天气地区…」** 修改；无需授予定位权限。

桌宠使用 [Open-Meteo 地点搜索](https://open-meteo.com/en/docs/geocoding-api)和[天气预报](https://open-meteo.com/en/docs)。它约每 10 分钟检查一次天气，**只在待机时**播放约 30 秒的晴天、下雨、多云或下雪动画；工作和晚饭动作期间不会插播。天气配置通常保存在 App 同目录的 `weather.json`；如果该目录不可写（例如 App 放在「应用程序」中），则保存在 `~/Library/Application Support/Snoopy Desktop/weather.json`。可参考 [`weather.example.json`](weather.example.json) 了解格式。

![晴天有太阳和墨镜](docs/sunny.png) ![雨天糊涂塌克撑伞](docs/rain.png)

**下雪天气的史努比形象仍在优化。** 目前可以预览和播放下雪场景，但积雪覆盖的造型还会继续调整。

## 让桌宠跟随 GPT

- **Codex 桌面版：** 桌宠读取这台 Mac 上的 Codex 任务状态；开始运行会打字，完成后播放晚饭动作。
- **ChatGPT 桌面版及可访问的可见窗口：** 右键桌宠，选「启用 ChatGPT 桌面检测…」。再到「系统设置 → 隐私与安全性 → 辅助功能」，打开 **Snoopy Desktop**。若更新 App 后检测失效，先关闭再重新打开这个开关，并重启桌宠。
- **Chrome / Edge 的 ChatGPT 网页：** 安装可选的 [`BrowserExtension`](BrowserExtension/README.md)。首次使用须在桌宠右键菜单点「复制网页连接口令」，在扩展弹窗中粘贴并保存。这样后台网页也能通知桌宠。Safari 暂不支持加载此扩展。

桌宠监测的是**这台 Mac 上**的任务和网页生成状态；同一账号在其他设备上的活动不会自动传到这里。桌宠和浏览器扩展只在本机 `127.0.0.1:47831` 配对通信，不上传提问或回答内容。连接口令由每台 Mac 首次运行时生成，保存在该用户的应用支持目录；仓库和下载包不包含你的口令。

## 右键菜单

右键桌宠可以预览各天气场景、开关天气、选择地区、手动开始/完成打字、调整大小、隐藏或退出桌宠。退出后，再次从「应用程序」中打开 **Snoopy Desktop** 即可。

## 开发检查

核心程序使用 Swift 和 macOS AppKit，构建脚本不下载第三方依赖。改动源码后运行：

```bash
./build.sh
"./Snoopy Desktop.app/Contents/MacOS/SnoopyDesktop" --self-test
node --test BrowserExtension/tests/*.test.cjs  # 仅检查网页扩展；需要 Node.js
```

## 说明

这是非官方的个人同人项目，与 Peanuts Worldwide、Apple 或 OpenAI 无关联。史努比、糊涂塌克及查理布朗等角色的相关权利归原权利人。天气资料由 Open-Meteo 提供。
