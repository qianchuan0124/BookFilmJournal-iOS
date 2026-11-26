# 书影记录 · iOS App 原型 v2

把桌面端（PySide6 + QFluentWidgets 的「书影记录」）重构为 iPhone 原生应用。
原型共 **29 屏**，覆盖记录、豆列、计划、报告、设置与探索空间，沿用 `Record-iOS/prototype` 的构建与评审方式。v2 重做了配色与封面：暖纸 / 墨蓝金双主题，13 套内嵌 SVG 电影海报与手工排版的书籍封面；并新增「探索空间」站点配置与详情页「资源」搜索；页面统一 30/70 固定头 + 滚动区、正文 16px。

## 怎么看

```bash
open prototype/index.html
```

- 分六组排布：记录 / 豆列 / 计划 / 报告 / 报告样式 / 设置，每屏下方是交互说明；「报告样式」内可直接切换 V1 Noir / V2 Paper / V3 Compact / V4 Book Dark / V5 Book Light。
- 末尾是「方案已确认」，记录信息架构、设计决策与数据模型；所有方案均已确认。
- 右下角可切换深浅色；也可用 `?theme=dark`、`?only=records|doulist|plan|report|reportstyles|settings|decisions` 单独渲染一组。
- 分组截图在 `shots/`（`-dark` 为暗色）：

| 文件 | 内容 |
| --- | --- |
| `shots/board.png` | 画板总览（浅色） |
| `shots/board-dark.png` | 画板总览（深色） |
| `shots/records.png` | 观影记录、读书记录、想看、资源、搜索、详情（已看）、详情（想看）、编辑、补录、同步、登录 |
| `shots/doulist.png` | 豆列列表、豆列详情、条目信息 |
| `shots/plan.png` | 计划列表、计划详情、从想读添加、从豆列添加、新建计划 |
| `shots/report.png` | 报告中心、报告预览、批量生成 |
| `shots/reportstyles.png` | 报告样式切换：电影 V1–V3，书籍 V4–V5 |
| `shots/settings.png` | 设置、探索空间、新增本地站点、云同步、选择同步版本、字数统计、回收站 |
| `shots/decisions.png` | 信息架构、设计决策、数据模型、已确认方案 |

重新生成截图（需要本机 Chrome）：

```bash
./prototype/capture.sh
```

## 结构

```
prototype/
├── index.html            # 构建产物（浏览器打开这个）
├── build.py              # src/ → index.html
├── capture.sh            # 用 headless Chrome 输出分组截图
├── assets/icon.png       # 桌面端应用图标（画板品牌位）
├── assets/covers/        # 取自当前 App 沙盘的真实封面样张
├── report-styles/        # 五版移动端报告样式样本与对比图
├── config/sites.json     # 探索空间示例配置（实际部署到 GitHub）
├── src/
│   ├── style.css         # 设计 token、手机壳、海报墙、报告版式
│   ├── layout.html       # 画板、图标、Tab 栏、海报 SVG 素材
│   ├── part-records.html
│   ├── part-doulist.html
│   ├── part-plan.html
│   ├── part-report.html
│   ├── part-settings.html
│   └── part-decisions.html
└── shots/
```

修改 `src/` 后重新生成：

```bash
python3 prototype/build.py
```

## 信息架构

```
TabView（5 Tab）
├── 记录        观影 / 读书（分段切换）
│   ├── 已看 / 想看     海报墙（按生效日期分组）
│   ├── 搜索            半屏搜索（标题 / 短评 / 简介高亮）
│   ├── 详情            半屏：封面、评分、日期、时长/字数、感想
│   ├── 编辑            日期、评分、状态、页数/字数/时长、短评
│   ├── 新增            封面、标题、状态、日期、评分、豆瓣链接、短评
│   ├── 资源            记录详情 → 站点搜索（已看 / 想看共用）
│   └── 同步豆瓣        ID、Cookie、三种同步方式、同步范围
├── 豆列        影视 / 书籍；列表 → 详情 → 条目信息（页数/字数/时长）
├── 计划        观影 / 读书；文件夹网格 → 详情（排序）→ 从想读/豆列添加
├── 报告        月报 / 年报 / 自定义 / 全部；预览、批量生成、分享
└── 设置        账号、外观、Excel、云同步、字数统计、登录、探索空间、回收站
```

## 视觉系统

- **浅色**：暖纸底 + 墨色文字 + 香槟金；卡片接近未涂布纸，适合白天长时间浏览。
- **深色**：App 图标同源的墨蓝底 + 香槟金，避免纯黑死板；封面保留原色。
- **海报**：主体仍由内嵌 SVG 与 CSS 生成；记录、豆列、计划、报告与回收站均取自当前书库/当前快照的近期数据；记录页使用真实封面样张，其余未覆盖条目保留插画——战争片（剪影与夕阳）、科幻（行星与轨道）、公路（车灯与地平线）、海（船与琴键）、森林、城市、星云、火山、舞台等 13 套；书籍封面用纸张纹理、衬线字与烫金线单独设计。
- **字体**：界面用系统 SF / PingFang，电影与书籍标题用宋体，形成「界面现代、内容古典」的对比。

## 布局与字号规范

### 30 / 70 页面骨架

- 全屏页面统一「固定头 + 滚动区」：`.page-head` 基准 **250pt**（iPhone 844 高度约 30%），放状态栏、页面标题、分段控件、筛选与摘要，**不随内容滚动**；记录页使用紧凑头部（`#g-records .page-head` 不设最小高度），避免筛选与海报墙之间留白。
- 下方为剩余约 **70%** 的区域：`.body.scroll` 占据固定底部栏之外的剩余空间；滚动区底部统一 **24pt** 留白——tabbar 页留到 tabbar 上沿，push 页留到 homebar 上方。
- 浮层（详情、编辑、搜索、同步、登录、新增本地站点等）用固定 `.sheet-head` + 可滚动 `.sheet-body`，底部同样 24pt；浮层不强行套 30/70。
- 新页面必须复用这套骨架；不要把筛选器或摘要放进滚动区。

### 字号阶梯

| 层级 | 字号 | 字重 | 用途 |
| --- | --- | --- | --- |
| Display | 30 | 700 | 页面主标题（观影记录 / 设置 / 报告中心） |
| H1 | 21 | 600 | 详情标题、报告数字 |
| H2 | 17 | 600 | 导航标题、卡片大标题 |
| Title | 16 | 600 | 行标题、条目名、按钮 |
| Body | 16 | 400 | 正文、短评、表单输入，行高 1.65 |
| Body S | 14 | 400 | 辅助说明、次级信息 |
| Caption | 12.5 | 400 | 元信息、日期、备注 |
| Micro | 10.5–12 | 600 | 标签、徽章、Tab 文案 |
| Numbers | 30 / 21 / 16 | 700 | 统计数字，tabular-nums |

- 正文统一 16px；3 列海报墙的卡片标题用 13.5px，是唯一为密度保留的例外；书籍封面文字属于插画排版，不参与界面字号。
- 按钮：大 16 / 中 14 / 小 12.5；标签与徽章 10.5–12。

## 关键交互约定

1. **5 Tab，不做中央「＋」**：唯一需要新建的是记录，但「同步豆瓣」才是核心动作；新增放在记录页标题栏，同步固定在记录页右上。
2. **海报墙 3 列**：390pt 宽度下同时保留日期分组、2 行标题、时长/字数与星级；封面 2:3，评分角标在右上。
3. **详情、编辑、同步、添加都用半屏浮层**：浏览不跳页，关闭后保留列表滚动位置；只有豆列详情、计划详情、报告预览、设置二级页是 push。
4. **本地优先要显式可见**：封面右上金点 = 本地修改；编辑页有「恢复豆瓣原始时间」开关；同步浮层常驻说明。
5. **同步一次选全**：默认「增量同步（新增并移除）」，观影 / 读书 / 豆列分别勾选，结果在同一浮层展示新增 / 更新 / 移除与耗时。
6. **报告复用桌面 HTML**：不重写图表，WKWebView 打开桌面报告模板，PNG 由 WebView 快照导出；超过 12000px 自动分段，HTML 始终保留；批量生成按月份网格展示进度。
7. **云同步走「文件」里的 iCloud Drive**：与桌面共用「同步目录 + latest.json + 3 自动 + 2 手动快照」逻辑，恢复前先备份本机。
8. **字数统计不依赖 Calibre**：直接解析文件 App 中的 EPUB / TXT / DOCX；MOBI / AZW3 提示先转换。
9. **回收站放设置内（已确认）**：不做一级入口；记录 / 豆列 / 计划共用；彻底删除留标记，避免同步加回，并可随 Excel 导入到其他设备。
10. **深色优先但跟随系统**：海报本身保留原色，暗色只换界面、描边与浮层。
11. **登录：WKWebView + Keychain**：App 内用 WKWebView 承载豆瓣登录（扫码 / 账号密码），成功后读取 Cookie 存本机 Keychain；Safari 打开与粘贴 Cookie 仅作兜底，无法自动回传。
12. **探索空间**：远端配置由 GitHub 下发，本地可新增站点并标「本地」，拉取不覆盖；左上角「拉取」更新列表、「刷新」检测连通性（绿勾 / 红叉），点击链接复制完整地址并 Toast，长链接按可用宽度自动省略。
13. **详情页「资源」入口**：已看和想看的记录详情都能进入站点搜索；有 `searchUrl` 模板就带标题直达站内结果页，没有模板或站点异常则打开站点首页，豆瓣条目作为备用入口。

## 设计 token

| Token | 浅色 | 深色 |
| --- | --- | --- |
| 背景 | `#F7F3EA` | `#12161F` |
| 卡片 | `#FFFCF6` | `#1A1F2A` |
| 浮起 / 次表面 | `#FBF7EF` | `#1F2430` |
| 描边 | `#E7DFD2` | `#2A3140` |
| 主文字 | `#211E18` | `#F2EBDD` |
| 次文字 | `#5E574A` | `#C3BBA9` |
| 品牌金 | `#9A6211` | `#E9BE70` |
| 品牌金亮（按钮） | `#E8B65C` | `#E9BE70` |
| 统计 / 进度 | `#2E8775` | `#5CBBA7` |
| 已读 | `#688A4A` | `#94C477` |
| 想看 / 待读 | `#B86F30` | `#E2A46C` |
| 危险 | `#C54949` | `#FF7F87` |

主色是香槟金 `#E8B65C`，浅色下按钮文字用 `#241804`，避免金底白字对比不足。浅色是「暖纸 + 墨字 + 香槟金」，深色改为 App 图标同源的「墨蓝 + 香槟金」，比纯黑/暖炭黑更接近私人档案馆与胶片的气质。

## 探索空间配置

原型里用静态数据示意；仓库内的 `config/sites.json` 是示例配置，实际部署到 GitHub 仓库后由 App 启动或点「拉取」时读取：

```json
{
  "version": 3,
  "updatedAt": "2026-11-22T10:30:00+08:00",
  "movie": [
    {
      "name": "豆瓣电影",
      "url": "https://movie.douban.com",
      "searchUrl": "https://movie.douban.com/subject_search?search_text={title}"
    }
  ],
  "book": [
    {
      "name": "豆瓣读书",
      "url": "https://book.douban.com",
      "searchUrl": "https://book.douban.com/subject_search?search_text={title}"
    }
  ]
}
```

- **拉取**：读取 `raw.githubusercontent.com/<owner>/<repo>/main/sites.json`，校验 `version` 与字段后写本地缓存；失败保留旧配置并提示。
- **刷新**：对每个 `url` 做 HEAD/GET 探测，5 秒超时、并发 ≤ 4；绿勾 / 红叉只代表连通性，不代表内容可访问。
- **复制**：点站点行把完整 `url` 写入剪贴板，弹 Toast「链接已复制」。
- **搜索**：有 `searchUrl` 时把 `{title}` 做 URL 编码后交给系统浏览器；没有则打开 `url`，由用户在站内搜索。示例模板需按站点当前参数实测，站点改版时只改配置。
- **本地站点**：本地新增写入 `LocalExploreSite`（name / type / url / searchUrl），与远端列表合并展示并带「本地」标签；拉取只替换远端部分，不覆盖本地项。

## 数据模型建议

| 桌面 SQLite | iOS SwiftData | 说明 |
| --- | --- | --- |
| `records` | `@Model Record` | mediaType、status、subjectId、markedDate、effectiveDate、rating、comment、coverPath、wordCount、bookFile、各类 overridden 标记 |
| `doulists` / `doulist_items` | `Doulist` / `DoulistItem` | 条目按 mediaType 过滤；本地时长、页数、字数写在 item 上 |
| `plan_folders` / `plan_items` | `PlanFolder` / `PlanItem` | folder 带 note 与 sort；item 带 position、source（wish / doulist / manual） |
| `settings` | `@AppStorage` + `Settings` | 豆瓣 ID、同步方式、外观；Cookie 建议存 Keychain |
| `ignored_subjects` / `book_meta` / `book_words` | 同表或 Record 字段 | 换源忽略、页数固化、豆列字数，随快照与 Excel 迁移 |
| SQLite 快照 + `latest.json` | 文件包快照 | 写入用户选择的 iCloud Drive 目录，含类型 / 时间 / 设备 / 条数 / 校验值 |
| GitHub `sites.json` | `ExploreConfig` / `ExploreSite` / `LocalExploreSite` | 版本、更新时间、movie / book 分组、name / url / searchUrl；远端缓存只读，本地站点合并展示 |

## 已确认的边界

- **不做账户 / 多用户**：沿用桌面单豆瓣 ID，登录 Cookie 存本机 Keychain。
- **不做 CloudKit**：快照是整库文件，与桌面共用同一套同步目录协议。
- **报告不重写 SwiftUI 版式**：统一走 WKWebView，避免两端版式漂移。
- **不引入 Calibre**：iOS 只做 EPUB / TXT / DOCX 原生统计。
- **探索空间**：远端配置只读（GitHub 维护），本地可新增站点并与远端合并展示；拉取失败沿用本地缓存，拉取不覆盖本地项。
- **不做网页内嵌搜索**：只通过 `searchUrl` 的 `{title}` 占位符跳系统浏览器；站点不支持查询参数就打开首页。
- **不做小组件 / 通知**：v2 专注记录、整理、探索与导出闭环。

## 下一步

按「数据层 → 记录闭环 → 豆列 / 计划 → 报告 → 设置 / 同步 → Excel」推进 SwiftUI 实现（iOS 18+ / SwiftUI / SwiftData / WebKit / UniformTypeIdentifiers）：

1. `Record` / `Doulist` / `PlanFolder` 模型与迁移，导入现有 SQLite 做验证。
2. 记录页：海报墙、搜索、详情 / 编辑 / 新增浮层、同步结果。
3. 豆列与计划：多选添加、排序、导出 PNG（WebView 或 ImageRenderer）。
4. 报告：复用桌面模板，WKWebView 预览 + 快照导出；超过 12000px 自动分段。
5. 设置：云同步目录（UIDocumentPicker）、字数统计（FileManager + ZIP 解压 EPUB）、回收站。
6. 探索空间：GitHub 配置拉取 / 校验 / 缓存、HEAD 连通性检测、UIPasteboard 复制 + Toast。
7. 资源入口：根据 searchUrl 模板做 URL 编码并打开浏览器；无模板回退站点首页。
8. Excel 导入 / 导出与桌面互通。
