# GitHub 接入指南（一次性）

> 目的：让代码能在云端编译成 iOS 安装包，装到你的 iPhone 上。
> 全程约 15–20 分钟，之后每次更新都是一条命令。

---

## 零、先说结论：你只需要做 1 件事

> 状态更新：GitHub 账号已注册并在浏览器登录（2026-11-11）。
> 方向已定：**继续做 iOS 原生 App**，不走小程序。

| # | 事项 | 耗时 |
|---|---|---|
| 1 | 生成一个访问令牌，把 `ghp_...` 发我 | 约 30 秒 |

**不用手动建仓库、不用填仓库地址、不用管分支名。** 脚本会自动读取你的用户名、
创建 Public 仓库、把 `master` 改成 `main`、推送全部提交。

剩下（推送、CI 编译、签名安装）我来做。

### 为什么不能免令牌

我试过 GitHub 的设备授权流程（浏览器点一下授权即可），但本机网络下
`github.com/login/device/code` 返回 `Not Found`（换 client_id 也是），走不通。
个人访问令牌是唯一可用通道，且可以推完立刻吊销。

---

## 一、为什么要仓库

Codemagic 和 GitHub Actions 都是**云端构建机** —— 它们需要一台 Mac 跑 Xcode 编译你的代码。
代码必须放在它们能取到的地方。

我查过 Codemagic 官方 CLI：它只提供签名和构建辅助命令（`xcode-project`、`app-store-connect`），
**没有「从本地目录直接上传并构建」的接口**。所以 Git 仓库是唯一通道。

---

## 二、仓库不用你建

`Tools/setup-github.sh` 会用令牌调 GitHub API 自动完成：

1. `GET /user` 取你的用户名（**不用告诉我账号叫什么**）
2. `POST /user/repos` 创建 `FamilyWardrobe`（Public，不初始化任何文件）
3. 若同名仓库已存在（HTTP 422）则直接复用

> 之前本机配置里出现过 `cq-tyl` 这个账号名，但那是历史记录。
> 新账号叫什么完全不影响，脚本自己读。

### 为什么必须是 Public

GitHub Actions 的 **macOS runner 在公开仓库上免费无限**；
私有仓库按 **10 倍倍率**扣免费额度（免费版约每月 200 分钟 macOS）。

本项目代码不含任何密钥：
- 签名证书、ASC API key 都在 CI 控制台，不进仓库
- 数据库和照片是运行时数据，不进仓库
- 访问令牌不写进任何文件、不写入 git remote

所以公开仓库是安全的。**仍想私有也能用**，一次构建约 8–12 分钟，每月 200 分钟够用。

---

## 三、生成访问令牌（唯一需要你做的）

**直接打开这个链接**（权限和用途已预填，浏览器里已登录所以会直接显示表单）：

```
https://github.com/settings/tokens/new?scopes=repo,workflow&description=FamilyWardrobe
```

然后：

| 检查项 | 要求 |
|---|---|
| 页面标题 | 必须是 **Tokens (classic)**。若显示 Fine-grained tokens，点左侧「Tokens (classic)」 |
| Note | `FamilyWardrobe`（链接已预填） |
| Expiration | 建议 `7 days` —— 只用一次，够短更安全 |
| Scopes | **`repo`** 必须勾上（链接已预填）；`workflow` 用于触发 Actions |

滚到最底点 **Generate token**，复制 `ghp_...`（**只显示这一次**）。

---

## 四、发给我

只要这一行：

```
ghp_xxxxxxxxxxxxxxxxxxxx
```

**令牌安全**：
- 只用于本次推送，不写进任何文件、不写入 `.git/config`
- 脚本推完会自检 remote 里是否残留令牌（应为 0 处）
- 推完请立刻吊销：<https://github.com/settings/tokens> → Delete
- 以后需要再次推送时重新生成一个即可

---

## 五、我做的部分

```bash
bash Tools/setup-github.sh ghp_xxxxxxxxxxxxxxxxxxxx
```

脚本依次完成：校验令牌 → 取用户名 → 建 Public 仓库 → `master` 改 `main`
→ 推送 7 个提交 → 设置干净的 remote → 打印 Actions 页面地址。

推送后 `main` 分支会自动触发一次构建（workflow 的 `push` 触发器）。
也可以在 Actions 页面手动点 **Run workflow**，把「是否运行测试」设为 false 先快出包。

---

## 六、触发云端编译

推完之后你可以在 GitHub 页面点：

**Actions → iOS Unsigned Build → Run workflow → 绿色 Run**

约 10–15 分钟后，产物出现在页面底部：

| 产物 | 用途 |
|---|---|
| `FamilyWardrobe-unsigned-ipa` | **未签名 ipa**，供本机 Sideloadly 签名后安装 |
| `FamilyWardrobe-simulator-app` | 模拟器 .app，可在浏览器里预览（App Preview） |
| `build-logs` | 编译日志，失败时先看这个 |

---

## 七、装到 iPhone（方案 A · 免费侧载）

### 1. 下载并安装 Sideloadly

- 官网 <https://sideloadly.io/> → 下载 Windows 版
- 免费，无需注册

### 2. 取你的设备 UDID

- 用数据线连上 iPhone
- 打开 Sideloadly，点右下角 **Refresh**，它会自动读取 UDID
- 或访问 <https://udid.co/>

### 3. 签名安装

在 Sideloadly 里：

| 字段 | 填什么 |
|---|---|
| iDevice | 选你的 iPhone |
| Bundle ID | `com.familywardrobe.app`（保持不变） |
| Source IPA | 下载的 `FamilyWardrobe-unsigned.ipa` |
| Apple ID | 你的 Apple ID 邮箱 |

点 **Start**，输入 Apple ID 密码 → 装好。

### 4. 关于 7 天有效期

免费 Apple ID 签出来的证书只能 7 天。**到期重新跑一次 Sideloadly 即可，数据不会丢** ——
因为 bundle id 没变，数据容器是同一个。这跟「升级丢数据」完全是两回事。

> 如果你想彻底摆脱 7 天限制，走下面的方案 B。

---

## 八、方案 B · 正式分发（TestFlight / Ad Hoc）

适合「确定要长期用、家里人多设备、不想每周重签」的情况。

### 额外准备

| # | 事项 | 位置 | 判定标准 |
|---|---|---|---|
| 1 | 付费开发者账号（99 美元/年） | developer.apple.com | 有 App ID 页面 |
| 2 | 注册 bundle id `com.familywardrobe.app` | developer.apple.com → Identifiers → + | 列表里能看到 |
| 3 | ASC 创建 App | appstoreconnect.apple.com/apps → + | 拿到 App ID |
| 4 | 创建 Apple Distribution 证书 | developer.apple.com → Keys | 导出 `.p12` + 密码 |
| 5 | 创建 Ad Hoc profile | developer.apple.com → Profiles | 导出 `.mobileprovision` |
| 6 | 登记设备 UDID | developer.apple.com → Devices → + | 2 台设备都在列表 |
| 7 | 上传签名实体到 Codemagic | Codemagic → Teams → Settings → Code signing identities | profile 行的 **Certificate 字段出现绿色对勾** |
| 8 | 录 ASC API key（两个集成位） | Codemagic → Teams → Team integrations | App Store Connect + Developer Portal 都变绿 |

### 分发方式

| 方式 | 有效期 | 适合 |
|---|---|---|
| **TestFlight 内部测试** | 每构建 90 天过期 | 开发迭代，一键装，不用收集 UDID |
| **Ad Hoc 分发** | 证书一年 | 日常主力，不想每 3 个月重装 |

`codemagic.yaml` 里两个 workflow 都配好了，随时可切：

```bash
python cm_build.py start --app familywardrobe --workflow release   # TestFlight
python cm_build.py start --app familywardrobe --workflow adhoc     # Ad Hoc
```

---

## 九、bundle id 的重要提醒

**`com.familywardrobe.app` 一旦用在真机上，就永远不能改。**

改了 = 系统认为是新 App = 数据容器不跟随 = 你录入的所有衣服和记录全部看不到。
这是「升级不丢数据」最容易踩的坑，比代码 bug 严重得多。

> 侧载时如果不小心改了这个值，App 也能装上，但会是「全新 App」，看不到旧数据。

---

## 十、成本参考

| 项目 | 方案 A（侧载） | 方案 B（Codemagic） |
|---|---|---|
| GitHub Actions macOS | 公开仓库免费无限 | — |
| Codemagic | — | 按分钟计费，约 $0.095/分钟 |
| Apple 开发者账号 | 不需要 | 99 美元/年 |
| 签名方式 | 本机 Sideloadly | 证书自动管理 |
| 重签频率 | 每 7 天 | Ad Hoc 一年 |

**建议**：先用方案 A 快速验证 App 真的能用（今天就能装上手机），
功能稳定、确定长期用了，再走方案 B。

---

## 十一、常见问题

**Q：公开仓库会不会泄露代码？**
本项目仓库里只有 Swift 源码、测试和文档。签名证书、ASC 密钥都在 Codemagic 控制台；
数据库和照片是 App 运行时的数据，在手机沙盒里。都没有敏感信息。

**Q：私有仓库能用吗？**
能。GitHub Actions 每月给免费额度（私有仓库约等于 200 分钟 macOS 分钟），
一次构建 8–12 分钟，够用。只是构建日志和产物仍需手动下载。

**Q：推送需要网络代理吗？**
`api.github.com` 直连正常（实测 200）。`github.com` 网页直连偶有波动，
但推送走 API 通道，不受影响。

**Q：构建失败怎么办？**
`build-logs` 产物里有完整日志。把日志发我，我按报错修。
大概率是 Xcode 版本差异导致的 API 可用性问题，改起来很快。
