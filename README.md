# BookFilmJournal-iOS

书影记录 iOS App。

## 本地构建

```bash
xcodebuild \
  -project BookFilmJournal-iOS.xcodeproj \
  -scheme BookFilmJournal-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

## 探索空间配置源

配置文件：

`BookFilmJournal-iOS/Config/ExploreSources.json`

资源构建阶段会把该文件复制到 App Bundle；修改后重新编译即可生效。

配置格式：

```json
{
  "sources": [
    {
      "id": "github",
      "name": "GitHub",
      "description": "优先从 GitHub 拉取远端站点配置。",
      "url": "https://raw.githubusercontent.com/catnine/bookfilm-sites/main/sites.json"
    },
    {
      "id": "gitee",
      "name": "Gitee",
      "description": "GitHub 拉取失败时回退到 Gitee 镜像。",
      "url": "https://gitee.com/catnine/bookfilm-sites/raw/main/sites.json"
    }
  ]
}
```

规则：

- 按 `sources` 数组顺序尝试拉取，默认 **GitHub → Gitee**。
- 某个源请求失败、超时或返回内容无法解析时，自动尝试下一个源。
- 全部源失败时保留本地配置，并提示「拉取失败，已保留本地配置」。
- 成功拉取后会替换远端站点，但保留本地站点。
- `name` 用于探索空间页面展示配置来源；`description` 用于说明；`url` 指向符合 `sites.json` 结构的配置。
- 如果 Gitee 镜像仓库地址不同，直接修改 `url`，不需要改 Swift 代码。
