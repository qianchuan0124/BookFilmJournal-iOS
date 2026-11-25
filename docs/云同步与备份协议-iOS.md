# iOS 云同步与备份协议 v1.3

本文是「书影记录」iOS 端（`BookFilmJournal-iOS`）的云同步与备份协议。

它与桌面端协议兼容：

- 桌面端协议：`BookFilmJournal/docs/云同步与备份协议.md`
- 本协议沿用桌面端的同步目录、快照命名、`latest.json` 清单、SQLite 数据库结构和保留策略。
- iOS 本地仍使用 JSON 存储；备份时**导出为桌面端可读取的 SQLite `.db` 快照**，恢复时可直接读取桌面端或 iOS 生成的 `.db`。

对应实现：

- `BookFilmJournal-iOS/Services/CloudSyncService.swift`
- `BookFilmJournal-iOS/Features/Settings/CloudSyncView.swift`
- `BookFilmJournal-iOS/Models/LibraryStore.swift`

## 1. 设计目标与边界

| 项 | 说明 |
|---|---|
| 同步载体 | 完整 SQLite 数据库快照；不做按条目的增量同步 |
| 同步目录 | 用户通过系统文件夹选择器选择的目录；建议 iCloud Drive |
| 云 SDK | 不使用 CloudKit、OneDrive SDK 或自建服务；依赖系统文件同步 |
| 冲突策略 | 整库覆盖；不做字段级合并 |
| iOS 本地格式 | JSON（`Application Support/BookFilmJournal/library.json`） |
| 桌面兼容 | 读写桌面端当前 SQLite schema；共用 `latest.json` 和快照命名 |
| 不同步内容 | Cookie、豆瓣头像 URL、探索空间远程配置源、同步目录簿记、自动开关、封面图片缓存、字数解析缓存、报告产物 |

> iOS 不把正在使用的 JSON 数据库直接放进同步目录；每次备份生成一个独立 SQLite 快照，避免 iCloud 异步上传或多设备并发写损坏数据库。

## 2. 同步目录

用户在「设置 → 云同步 → 文件夹卡片」中选择一个文件夹。App 保存 security-scoped bookmark，后续通过 bookmark 重新获取访问权限。

写入位置：

```text
<用户选择的根目录>/书影记录/
├── douban_trace_20261123_200347_2a0a_manual.db
├── douban_trace_20261123_200347_2a0a_manual.db.ios.json
├── douban_trace_20261122_090000_2a0a_auto.db
├── latest.json
└── devices.json
```

规则：

- 如果用户直接选择了名为 `书影记录` 的文件夹，则直接在其中读写；
- 否则在所选根目录下创建 `书影记录/` 子目录；
- 读取时会同时扫描所选根目录和其下的 `书影记录/`，兼容用户选择根目录或桌面端默认子目录两种情况；
- 文件夹访问权限失效时，界面提示重新选择，不自动清空任何数据。

## 3. 命名与设备标记

```text
douban_trace_<YYYYmmdd_HHMMSS>_<设备标记>_<auto|manual>[_序号].db
```

| 字段 | 说明 |
|---|---|
| `YYYYmmdd_HHMMSS` | 快照生成时间（本地时区） |
| 设备标记 | `SHA1(UIDevice.current.name)` 前 4 位十六进制 |
| `auto` / `manual` | 自动备份 / 手动备份；旧文件缺少标记时按 `manual` 处理 |
| `序号` | 同秒生成多个快照时追加 `_2`、`_3`… |

设备标记只用于区分设备与按设备保留，不包含 UDID、序列号、IMEI、账号或广告标识。

iOS 备份时还会在同一同步目录写入/合并 `devices.json`，并在快照列表读取设备标记对应的可读名称、平台与最后出现时间；该文件只用于列表展示，不参与快照校验、恢复或保留策略。

## 4. SQLite 快照结构

iOS 生成的 `.db` 使用桌面端当前 schema 的全部业务表：

- `records`
- `doulists`
- `doulist_items`
- `plan_folders`
- `plan_items`
- `book_words`
- `book_meta`
- `settings`
- `ignored_subjects`
- `purged_records`

快照生成时：

1. 不写入本机专属设置（Cookie、书库路径、同步目录、自动开关、上次同步簿记）；
2. 写入记录、豆列、计划、书籍字数与页数；
3. 在 `settings` 表写入 `ios_explore_sites`，值为探索空间站点数组的 JSON；
4. 写入 `ignored_subjects` / `purged_records` 的全部行，并在 `settings` 写入 `snapshot_marks_version = '1'`，声明这两张表由本快照完整维护；
5. 生成后执行 `PRAGMA integrity_check`，必须返回 `ok`。

### 4.1 iOS 扩展 sidecar

为了在 iOS 设备之间保留桌面 schema 没有的展示字段，iOS 会在快照旁写一个可选文件：

```text
<快照名>.db.ios.json
```

内容示例：

```json
{
  "version": 1,
  "records": [
    {
      "mediaType": "movie",
      "subjectID": "1298661",
      "status": "done",
      "durationMinutes": 209,
      "pages": null,
      "year": "1991",
      "releaseDate": "1991-07-01",
      "art": "war",
      "coverURL": "https://img.example/poster.jpg",
      "coverSource": "link",
      "coverData": "…base64…"
    }
  ],
  "doulistItems": [
    {
      "listKey": "douban:123456",
      "mediaType": "movie",
      "subjectID": "1298661",
      "durationMinutes": 209,
      "pages": null,
      "wordCount": null,
      "year": "1991",
      "releaseDate": "1991-07-01",
      "rating": 5,
      "comment": "…",
      "intro": "…",
      "createdAt": 817329600.0
    }
  ],
  "planItems": [
    {
      "folderKey": "local:movie:2026 补完",
      "mediaType": "movie",
      "subjectID": "1298661",
      "isRead": false,
      "statsText": "3 小时 29 分",
      "releaseDate": "1991-07-01",
      "note": "优先 IMAX",
      "source": "douban",
      "sourceID": "1298661"
    }
  ]
}
```

用途：

- 保留 `durationMinutes`、`pages`、`year`、`releaseDate`、`art`、封面来源等 iOS 展示字段；
- 链接封面以 base64 写入 `coverData`，避免恢复时丢失自定义封面；
- `doulistItems` 保存数据库表没有的条目展示字段（时长、页数、字数、年份、上映日期、评分、短评、简介、创建时间）；
- `planItems` 保存计划条目的阅读状态、统计文本、上映日期、用户备注、来源与来源 ID；统计文本不作为 `plan_items.note` 使用；
- 日期字段使用 `JSONEncoder` 默认的「2001-01-01 UTC 起秒数」（如 `817329600.0`），桌面端按秒数写入；iOS 读取时先按默认策略，失败再用 ISO8601 兜底；
- 恢复时若 sidecar 存在则合并，不存在则使用数据库字段；
- 桌面端会读取 `records` 中的时长/封面等兼容字段，忽略未知字段；不影响桌面端读取 `.db`；
- sidecar 不参与 `latest.json` 的 `sha256` 和 `size` 计算。

### 4.2 探索空间站点

探索空间站点不是桌面 schema 的独立业务表，iOS 使用 `settings` 表中的 JSON 值保存：

| key | 内容 |
|---|---|
| `ios_explore_sites` | `ExploreSite` 数组 JSON：名称、URL、搜索模板、媒体类型、是否本地 |

规则：

- 手动备份与自动备份都会写入该键；
- 旧快照没有该键时，恢复不覆盖本机探索站点；
- 恢复新快照时，站点列表、搜索模板和本地站点会整体回填；
- 桌面端可忽略该 key，不影响桌面端读取；
- GitHub / Gitee 配置源属于 App 内置 `ExploreSources.json`，不写入快照，也不随云同步覆盖。


### 4.3 豆列身份、排序与去重

- `doulists.douban_id` 写入真实豆瓣豆列 ID；没有豆瓣来源的本地豆列写入 `ios-local-<UUID>`，保证列非空且唯一；
- 恢复时真实豆瓣 ID 会映射为稳定 UUID（与豆瓣同步使用同一套 ID），本地占位 ID 按快照内顺序映射；
- 旧快照若曾把 UUID 写入 `douban_id`，恢复时按本地豆列处理，不当作真实豆瓣 ID；
- 豆列、计划文件夹、计划条目的 `deleted_at` 随快照保留，用于恢复回收站内容；
- 「我的豆列」和豆列详情支持长按拖拽排序；
- 本地顺序保存在 `doulists` / `doulist_items` 数组顺序中；
- 写入快照时分别写入 `doulists.position`、`doulist_items.position`；
- 豆瓣同步更新已有豆列/条目时保留本地顺序，新条目追加到末尾；
- 恢复快照时按 `position, id` 排序，保证顺序不被同步覆盖；
- 启动、云恢复、Excel 导入和豆瓣同步后都会合并重复豆列：
  - 优先按豆瓣 ID 判定同一豆列；
  - 没有豆瓣 ID 时，使用「媒体类型 + 归一化标题」判定（去首尾空白、压缩空白、全半角归一化）；
  - 合并时把条目迁移到保留的豆列，并合并同一条目的已读/时长/页数/字数等字段；
  - 豆瓣 ID 不同、仅标题相同的两个真实豆列会保留，不误合并。

### 4.4 换源忽略与彻底删除墓碑

iOS 从 v1.3 起维护桌面协议中的两张抑制表，并随快照同步：

| 表 | 字段 | 用途 |
|---|---|---|
| `ignored_subjects` | `media_type`、`subject_id`、`created_at` | 记录换到另一个豆瓣条目后，抑制旧条目再次同步回来 |
| `purged_records` | `media_type`、`subject_id`、`status`、`title`、`purged_at` | 回收站彻底删除后留下墓碑，避免被豆瓣同步或旧 Excel 重新加回 |

行为：

- 记录编辑时如果 `subjectID` 发生变化，把旧 `(media_type, subject_id)` 写入 `ignored_subjects`，同时解除新条目的忽略；
- 手动新增同一条目时，解除 `ignored_subjects` 并移除对应 `purged_records`；
- 回收站「彻底删除」和「清空回收站」会写入 `purged_records`；
- 豆瓣同步、豆列生成的隐藏记录和 Excel 导入遇到命中条目时跳过；
- 这两张表不写 sidecar，直接使用 SQLite 表；桌面端与 iOS 共用同一语义；
- 快照 `settings.snapshot_marks_version = '1'` 表示这两张表完整权威，空表就是用户主动清空；
- Excel 导出/导入增加「彻底删除记录」「忽略条目」两个 Sheet，列名与桌面端一致；
- Excel 同时覆盖桌面端 5 张回收站表：「回收站记录」「回收站豆列」「回收站豆列条目」「回收站计划文件夹」「回收站计划条目」；豆列、计划文件夹、计划条目删除在 iOS 本地使用 `deletedAt` 软删除；
- 豆列条目的「评分/短评/简介/创建时间」、计划条目的「来源/来源ID/备注」与 iOS 原字段合并导出，桌面端可读取，iOS 回导也能保留；
- `plan_items.note` 只保存用户备注，统计文本由记录实时计算；计划条目的 `status`、`release_date` 同时写入数据库列和 sidecar 兼容旧快照。

### 4.5 旧快照兼容

- 没有 `snapshot_marks_version` 的旧快照视为老客户端生成：
  - 老桌面快照同样可能带 `.ios.json` sidecar；没有 `snapshot_marks_version` 且两张表为空时，同样保留本机标记（保守行为，不代表桌面端主动清空）；
  - 带非空标记的旧快照按快照内容覆盖；
- 带 `snapshot_marks_version = '1'` 的快照（桌面端、iOS v1.3+）按快照整表覆盖，空表代表确实清空；
- 恢复后下一次豆瓣同步立即按标记跳过相应条目。

## 5. 清单 `latest.json`

与桌面端字段一致：

```json
{
  "snapshot": "douban_trace_20261123_200347_2a0a_manual.db",
  "created_at": "2026-11-23 20:03:47",
  "created_ts": 1795435427,
  "tag": "a1b2",
  "platform": "iOS",
  "arch": "arm64",
  "device": "iPhone 18 Pro",
  "app_version": "1.0",
  "sha256": "…",
  "size": 106496,
  "kind": "manual",
  "records_updated": "2026-11-20 00:00:00",
  "counts": {
    "records": 24,
    "records_movie": 15,
    "records_book": 9,
    "doulists": 7,
    "doulist_items": 14,
    "plan_folders": 6,
    "plan_items": 13,
    "book_words": 9,
    "book_meta": 9,
    "ignored_subjects": 0,
    "purged_records": 0
  }
}
```

说明：

- `snapshot` 指向最近一次快照文件名；
- `sha256` / `size` 只描述 `.db` 文件，不包含 sidecar；
- `counts` 为数据库实际行数（包含软删除记录）；
- `records_updated` 取本地记录日期最大值；
- 写入使用临时文件 + 原子替换，避免同步过程中读到半写清单。

## 6. 保留策略

按（设备标记, 备份类型）分组，互不干扰：

| 类型 | 每台设备保留 |
|---|---:|
| 自动备份 `auto` | 最近 3 份 |
| 手动备份 `manual` | 最近 2 份 |

排序按「时间戳 + 同秒序号」倒序，避免同秒基础名复用后误删最新快照。删除旧快照时同步删除对应的 `.ios.json` sidecar 和 `.name.db.icloud` 占位。iOS 只清理自己命名规则下的文件，不删除文件夹里的其他内容。

## 7. 备份流程

### 7.1 手动备份

用户在「云同步」页点击「立即备份到文件夹」：

1. 确认已选择且可访问同步目录；
2. 计算当前 JSON 数据的逻辑状态指纹；
3. 生成唯一快照名；
4. 在 `.part` 临时文件中创建 SQLite 数据库并写入业务表及 `ios_explore_sites`；
5. 执行完整性校验；
6. 原子改名为正式 `.db`；
7. 写入 `.ios.json` sidecar；
8. 计算 SHA-256、文件大小与行数；
9. 原子写入 `latest.json`；
10. 执行保留策略；
11. 记录本机簿记（状态指纹、时间、快照名）。

手动备份始终生成新快照，不因内容未变而跳过。

### 7.2 自动备份

开关：`bookfilm.sync.autoBackup`（本机设置，默认关）。

- App 回到前台（`scenePhase == .active`）时检查；
- 已选择同步目录且开关开启；
- 内容状态指纹与上次备份相同，且 `latest.json` 指向的快照仍存在时跳过；
- 否则生成 `auto` 快照；
- 不做后台定时任务；App 被系统杀死时不会补备份。

## 8. 校验与恢复流程

### 8.1 列表

扫描同步目录，展示：

- 时间、自动/手动、来源设备；
- 记录总数与影视/读书拆分；
- 豆列/计划规模；
- 文件大小、是否为最新快照。

桌面端生成的 `.db` 和 iOS 生成的 `.db` 都会出现在同一列表。iOS 也会展示只有 `.name.db.icloud` 占位的快照，标记为「未下载」；点击后调用系统下载并在完成后重新打开列表恢复，未下载完成前不会进入恢复确认。

### 8.2 校验

恢复前必须满足：

1. 文件存在且已下载；列表中的「未下载」占位只提供下载入口，不能直接恢复，需先完成 iCloud 下载；
2. `PRAGMA integrity_check` 返回 `ok`；
3. 至少包含 `records`、`settings`、`doulists`、`plan_folders` 四张表；
4. 读取过程不修改源快照。

### 8.3 恢复

1. 先把当前本机 JSON 数据写入 `Application Support/BookFilmJournal/backups/`，保留最近 5 份；
2. 读取快照业务表，映射为 iOS 模型；
3. 若存在 `.ios.json` sidecar，合并时长、页数、年份、上映日期、海报风格、封面来源等 iOS 展示字段；
4. 读取 `ignored_subjects` / `purged_records` 和 `settings.snapshot_marks_version`；无标记、带 iOS 侧车或探索站点键的旧快照、两表为空时保留本机标记；有标记时按快照覆盖；
5. 按豆瓣 ID 优先、归一化标题兜底合并重复豆列，并迁移条目；
6. 保留本机报告产物和本机设置（文件夹 bookmark、自动开关、外观、头像 URL 等）；
7. 从快照 `settings.ios_explore_sites` 回填探索空间站点；旧快照缺少该键时保留本机探索站点；
8. 覆盖本机记录、豆列、计划、换源忽略与彻底删除墓碑；
9. 更新本机簿记：上次快照名、上次备份时间、当前状态指纹。

恢复是整库覆盖，不做逐条合并。

## 9. 自动同步

开关：`bookfilm.sync.autoSync`（本机设置，默认关）。

App 回到前台时检查，满足以下全部条件才恢复：

1. 已选择同步目录，`latest.json` 可读，快照存在；
2. 清单快照名 ≠ 本机上次恢复/备份的快照名；
3. 本机状态指纹（含记录、豆列、计划、探索空间站点）与上次备份指纹一致，或本机为空库（新设备首次使用）。

任一条件不满足则跳过，不修改本机数据。自动同步同样先写本机 JSON 备份。

当前 iOS 的自动同步不轮询、不合并字段；与自动备份互不串联。

## 10. 与桌面端兼容性

| 项目 | 桌面端 | iOS |
|---|---|---|
| 同步目录 | `书影记录/` | 同目录，兼容直接选择该目录或根目录 |
| 快照格式 | SQLite `.db` | SQLite `.db`（同 schema） |
| 命名 | `douban_trace_…` | 同命名规则 |
| 清单 | `latest.json` | 同字段、同位置 |
| 保留 | 每设备 auto 3 / manual 2 | 相同 |
| 备份方向 | 桌面写 `.db` | iOS 读写 `.db` |
| 恢复方向 | 桌面读 `.db` | iOS 读桌面/iOS `.db` |
| iOS sidecar | 忽略 | 合并展示字段 |
| 设备名 | `devices.json` + `latest.json` | 写入并读取 |
| 换源忽略/彻底删除墓碑 | `ignored_subjects` / `purged_records` | 同表读写，`snapshot_marks_version` 标记权威 |
| 报告 | 不支持同步 | 仅本机保留，不进快照 |
| 探索空间 | 可忽略 `settings.ios_explore_sites` | 写入并从快照恢复 |
| 封面 | 不进入快照 | 不进入快照，依赖侧车/豆瓣补全 |

两端都使用整库覆盖，不做字段级合并。

## 11. 本机设置与隐私

不进入快照的本机设置：

- `bookfilm.sync.folderBookmark`
- `bookfilm.sync.folderName`
- `bookfilm.sync.lastState`
- `bookfilm.sync.lastTime`
- `bookfilm.sync.lastSnapshot`
- `bookfilm.sync.autoBackup`
- `bookfilm.sync.autoSync`
- 外观、豆瓣 Cookie（Keychain）
- 探索空间连通性检测结果（`reachability`，仅本机缓存）

探索空间站点列表会写入快照的 `settings.ios_explore_sites`，仅排除检测结果。

快照包含记录、短评、豆列、计划、书籍字数/页数、探索空间站点等敏感数据，为明文 SQLite。安全性依赖用户选择的存储位置和系统文件保护；App 不额外加密。不要把快照发到未授权的第三方服务。

## 12. 已知限制

1. 不做三向合并；两台设备同时改动时只有整库覆盖的一方生效。
2. 封面图片缓存、字数解析缓存、报告产物不随快照迁移；链接封面以 base64 写入 sidecar，内置封面仅保留风格字段。
3. iOS ≤ v1.2 的旧快照不维护 `ignored_subjects` 与 `purged_records`；v1.3+ 已读写并维护这两张表。
4. 无豆瓣来源的本地豆列写入 `douban_id = ios-local-<UUID>`；有豆瓣来源的豆列写入真实豆瓣 ID。桌面端按本地豆列处理本地占位 ID。
5. 桌面 schema 不包含 iOS 的时长/年份/上映日期/海报字段，依赖 `.ios.json` sidecar；删除 sidecar 后这些字段会回退为默认值。
6. 时钟偏差会影响快照排序；保留策略按设备分组不受影响。
7. 自动同步只在 App 回到前台时检查，不后台轮询。
8. 探索空间只备份站点定义，不备份连通性检测结果；恢复后需要重新检测。

## 13. 代码位置

- 文件夹 bookmark、快照读写、清单、保留、恢复：`BookFilmJournal-iOS/Services/CloudSyncService.swift`
- SQLite schema 与模型映射：同上 `DesktopSnapshotBridge`
- 云同步界面：`BookFilmJournal-iOS/Features/Settings/CloudSyncView.swift`
- 本地数据与快照模型：`BookFilmJournal-iOS/Models/LibraryStore.swift`
- 自动备份/同步触发：`BookFilmJournal-iOS/MyApp.swift`

## 变更记录

- v1.2：快照保留真实豆瓣豆列 ID；恢复/导入/同步后按豆瓣 ID 优先、归一化标题兜底去重；明确头像 URL、探索空间远程配置源不参与同步。
- v1.3：iOS 实现 `ignored_subjects` / `purged_records`；快照读写、恢复覆盖、换源/彻底删除维护、同步/导入消费，写入 `snapshot_marks_version` 并兼容旧 iOS 快照的标记保护；Excel 补齐 5 张回收站表、豆列真实 ID 和桌面端字段合并；sidecar 时间字段统一为 2001 起秒数并兼容 ISO8601 读取。
