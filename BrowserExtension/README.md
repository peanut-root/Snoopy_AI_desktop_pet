# ChatGPT 网页连接器（Chrome / Edge）

此文件夹是可选扩展，用来让本机 ChatGPT 网页开始或完成生成时通知史努比桌宠。Codex 和已授权的 ChatGPT 桌面应用可由桌宠直接检测。

1. 先启动 `Snoopy Desktop.app`。
2. 在 Chrome 打开 `chrome://extensions`，或在 Edge 打开 `edge://extensions`。
3. 打开「开发者模式」，选择「加载已解压的扩展程序」，选中本文件夹。
4. 右键桌宠，点「复制网页连接口令」。打开扩展弹窗，在「设置连接口令」里粘贴并保存。
5. 刷新已经打开的 ChatGPT 网页。扩展弹窗应显示「已连接本机桌宠」。

配对口令由每台 Mac 在首次运行时生成，保存在 `~/Library/Application Support/Snoopy Desktop/connection-token.txt`，不包含在公开仓库中。扩展只把生成状态和页面会话标识发送到本机 `127.0.0.1:47831`，不发送提问、回答、账号信息或 Cookie。桌宠退出时本地连接停止。

浏览器休眠、后台标签页冻结或 ChatGPT 网页控件变化可能影响检测；可在桌宠右键菜单使用手动打字/完成。Safari 不能直接加载此扩展，其他设备上的账号活动也不会由这台 Mac 检测。

开发检查：`node --test tests/*.test.cjs`。无第三方依赖。
