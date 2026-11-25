import Foundation

@MainActor
enum ExcelExportService {
    private struct Sheet {
        let name: String
        let rows: [[String]]
    }

    static func makeWorkbook(store: LibraryStore) -> URL? {
        let records = store.activeRecords().sorted { $0.effectiveDate > $1.effectiveDate }
        let movies = records.filter { $0.mediaType == .movie }
        let books = records.filter { $0.mediaType == .book }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let markerStamp = DateFormatter()
        markerStamp.locale = Locale(identifier: "en_US_POSIX")
        markerStamp.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let recordHeaders = ["状态", "豆瓣ID", "标题", "链接", "评分", "标记日期", "生效日期", "短评", "简介", "时长", "页数", "字数", "年份", "上映日期", "来源"]
        func recordRows(_ list: [MediaRecord]) -> [[String]] {
            list.map { record in
                [
                    statusText(record),
                    record.subjectID,
                    record.title,
                    record.doubanURL ?? "",
                    "\(record.rating)",
                    day.string(from: record.markedDate),
                    day.string(from: record.effectiveDate),
                    record.comment,
                    record.intro,
                    record.durationMinutes.map(String.init) ?? "",
                    record.pages.map(String.init) ?? "",
                    record.wordCount.map(String.init) ?? "",
                    record.year ?? "",
                    record.releaseDate ?? "",
                    record.isLocalEdited ? "local" : "douban"
                ]
            }
        }

        let recycleRecordHeaders = ["类型", "状态", "豆瓣ID", "标题", "链接", "评分", "豆瓣标记日期", "本地生效日期", "本地已调整", "评分已调整", "短评已调整", "短评", "简介", "封面URL", "封面路径", "时长", "页数", "字数", "电子书文件", "来源", "删除时间", "删除来源"]
        func recycleRecordRow(_ record: MediaRecord) -> [String] {
            [
                record.mediaType.rawValue,
                statusText(record),
                record.subjectID,
                record.title,
                record.doubanURL ?? "",
                "\(record.rating)",
                day.string(from: record.markedDate),
                day.string(from: record.effectiveDate),
                record.isLocalEdited ? "是" : "否",
                "否",
                "否",
                record.comment,
                record.intro,
                record.coverURL ?? "",
                "",
                record.durationMinutes.map(String.init) ?? "",
                record.pages.map(String.init) ?? "",
                record.wordCount.map(String.init) ?? "",
                "",
                record.isLocalEdited ? "local" : "douban",
                record.deletedAt.map { markerStamp.string(from: $0) } ?? "",
                record.deleteSource == .sync ? "豆瓣同步" : "手动删除"
            ]
        }
        let recycleRecordRows = store.deletedRecords.map(recycleRecordRow)

        let doulistItemHeaders = ["豆列ID", "类型", "条目ID", "标题", "链接", "封面URL", "封面路径", "评分", "短评", "简介", "位置", "创建时间", "状态", "时长", "页数", "字数", "年份", "上映日期"]
        let planHeaders = ["计划名称", "顺序", "类型", "条目ID", "标题", "链接", "封面URL", "封面路径", "来源", "来源ID", "备注", "状态", "上映日期"]

        func doulistItemRow(_ doulistID: String, _ item: DoulistItem, _ index: Int) -> [String] {
            [
                doulistID, item.mediaType.rawValue, item.subjectID, item.title,
                "", item.coverURL ?? "", "",
                item.rating.map(String.init) ?? "",
                item.comment ?? "", item.intro ?? "",
                "\(index)", item.createdAt.map { markerStamp.string(from: $0) } ?? "",
                item.isRead ? "已读/已看" : "未读/未看",
                item.durationMinutes.map(String.init) ?? "",
                item.pages.map(String.init) ?? "",
                item.wordCount.map(String.init) ?? "",
                item.year ?? "", item.releaseDate ?? ""
            ]
        }

        func planRow(_ folder: PlanFolder, _ item: PlanItem) -> [String] {
            [
                folder.title, "\(item.position)", folder.mediaType.rawValue,
                item.subjectID, item.title, "", item.coverURL ?? "", "",
                item.source ?? "", item.sourceID ?? "", item.note,
                item.isRead ? "已读/已看" : "未读/未看", item.releaseDate ?? ""
            ]
        }

        var doulistRows: [[String]] = []
        var doulistItemRows: [[String]] = []
        for (index, doulist) in store.activeDoulists.enumerated() {
            let exportID = doulist.doubanID.flatMap { $0.isEmpty ? nil : $0 } ?? "ios-local-\(doulist.id.uuidString)"
            doulistRows.append([
                doulist.mediaType.rawValue, exportID, doulist.title, "",
                "\(doulist.itemCount)", doulist.isFollowing ? "followed" : "created",
                "\(index)", ""
            ])
            for (itemIndex, item) in store.doulistItems(for: doulist.id).enumerated() {
                doulistItemRows.append(doulistItemRow(exportID, item, itemIndex))
            }
        }

        var recycleDoulistRows: [[String]] = []
        var recycleDoulistItemRows: [[String]] = []
        for (index, doulist) in store.deletedDoulists.enumerated() {
            let exportID = doulist.doubanID.flatMap { $0.isEmpty ? nil : $0 } ?? "ios-local-\(doulist.id.uuidString)"
            recycleDoulistRows.append([
                doulist.mediaType.rawValue, exportID, doulist.title, "",
                "\(doulist.itemCount)", doulist.isFollowing ? "followed" : "created",
                "\(index)", "", markerStamp.string(from: doulist.deletedAt ?? Date())
            ])
            for (itemIndex, item) in store.doulistItems.filter({ $0.doulistID == doulist.id }).enumerated() {
                recycleDoulistItemRows.append(doulistItemRow(exportID, item, itemIndex))
            }
        }

        var folderRows: [[String]] = []
        var planRows: [[String]] = []
        for (index, folder) in store.activePlanFolders.enumerated() {
            folderRows.append([folder.mediaType.rawValue, folder.title, folder.note, "\(index)"])
            for item in store.planItems(for: folder.id) {
                planRows.append(planRow(folder, item))
            }
        }

        let recycleFolderRows = store.deletedPlanFolders.enumerated().map { index, folder in
            [folder.mediaType.rawValue, folder.title, folder.note, "\(index)", markerStamp.string(from: folder.deletedAt ?? Date())]
        }
        var recyclePlanRows: [[String]] = []
        var seenPlanItemIDs = Set<UUID>()
        for folder in store.deletedPlanFolders {
            for item in store.planItems.filter({ $0.folderID == folder.id }) {
                recyclePlanRows.append(planRow(folder, item) + [item.deletedAt.map { markerStamp.string(from: $0) } ?? ""])
                seenPlanItemIDs.insert(item.id)
            }
        }
        for item in store.deletedPlanItems where !seenPlanItemIDs.contains(item.id) {
            guard let folder = store.planFolder(id: item.folderID) else { continue }
            recyclePlanRows.append(planRow(folder, item) + [item.deletedAt.map { markerStamp.string(from: $0) } ?? ""])
        }

        let words = books.filter { ($0.wordCount ?? 0) > 0 }.map {
            [$0.subjectID, "\($0.wordCount ?? 0)", ""]
        }

        let purgedRows = store.purgedRecords
            .sorted { $0.purgedAt > $1.purgedAt }
            .map { record in
                [
                    record.mediaType.rawValue,
                    statusText(record.mediaType, record.status),
                    record.subjectID,
                    record.title,
                    markerStamp.string(from: record.purgedAt)
                ]
            }
        let ignoredRows = store.ignoredSubjects
            .sorted { $0.createdAt > $1.createdAt }
            .map { subject in
                [
                    subject.mediaType.rawValue,
                    subject.subjectID,
                    markerStamp.string(from: subject.createdAt)
                ]
            }

        let sheets: [Sheet] = [
            Sheet(name: "观影记录", rows: [recordHeaders] + recordRows(movies)),
            Sheet(name: "读书记录", rows: [recordHeaders] + recordRows(books)),
            Sheet(name: "豆列", rows: [["类型", "豆列ID", "标题", "链接", "条目数", "关系", "顺序", "同步时间"]] + doulistRows),
            Sheet(name: "豆列条目", rows: [doulistItemHeaders] + doulistItemRows),
            Sheet(name: "计划文件夹", rows: [["类型", "计划名称", "备注", "顺序"]] + folderRows),
            Sheet(name: "计划", rows: [planHeaders] + planRows),
            Sheet(name: "书籍字数", rows: [["豆瓣ID", "字数", "电子书文件"]] + words),
            Sheet(name: "回收站记录", rows: [recycleRecordHeaders] + recycleRecordRows),
            Sheet(name: "回收站豆列", rows: [["类型", "豆列ID", "标题", "链接", "条目数", "关系", "顺序", "同步时间", "删除时间"]] + recycleDoulistRows),
            Sheet(name: "回收站豆列条目", rows: [doulistItemHeaders] + recycleDoulistItemRows),
            Sheet(name: "回收站计划文件夹", rows: [["类型", "计划名称", "备注", "顺序", "删除时间"]] + recycleFolderRows),
            Sheet(name: "回收站计划条目", rows: [planHeaders + ["删除时间"]] + recyclePlanRows),
            Sheet(name: "彻底删除记录", rows: [["类型", "状态", "豆瓣ID", "标题", "彻底删除时间"]] + purgedRows),
            Sheet(name: "忽略条目", rows: [["类型", "豆瓣ID", "记录时间"]] + ignoredRows)
        ]

        var zip = MiniZipWriter()
        zip.add("[Content_Types].xml", data: contentTypes(sheets: sheets))
        zip.add("_rels/.rels", data: rootRels())
        zip.add("xl/workbook.xml", data: workbook(sheets: sheets))
        zip.add("xl/_rels/workbook.xml.rels", data: workbookRels(count: sheets.count))
        zip.add("xl/styles.xml", data: styles())
        for (index, sheet) in sheets.enumerated() {
            zip.add("xl/worksheets/sheet\(index + 1).xml", data: worksheet(sheet))
        }
        let data = zip.finalize()
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "书影记录_\(stamp.string(from: Date())).xlsx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func statusText(_ record: MediaRecord) -> String {
        statusText(record.mediaType, record.status)
    }

    private static func statusText(_ media: MediaType, _ status: RecordStatus) -> String {
        switch (media, status) {
        case (.movie, .done): "看过"
        case (.movie, .wish): "想看"
        case (.book, .done): "读过"
        case (.book, .wish): "想读"
        }
    }

    private static func contentTypes(sheets: [Sheet]) -> Data {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#
        for index in sheets.indices {
            xml += #"<Override PartName="/xl/worksheets/sheet\#(index + 1).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }
        xml += "</Types>"
        return Data(xml.utf8)
    }

    private static func rootRels() -> Data {
        Data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#.utf8)
    }

    private static func workbook(sheets: [Sheet]) -> Data {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>"#
        for (index, sheet) in sheets.enumerated() {
            xml += #"<sheet name="\#(escape(sheet.name))" sheetId="\#(index + 1)" r:id="rId\#(index + 1)"/>"#
        }
        xml += "</sheets></workbook>"
        return Data(xml.utf8)
    }

    private static func workbookRels(count: Int) -> Data {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        for index in 0..<count {
            xml += #"<Relationship Id="rId\#(index + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#(index + 1).xml"/>"#
        }
        xml += #"<Relationship Id="rId\#(count + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>"#
        return Data(xml.utf8)
    }

    private static func styles() -> Data {
        Data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="1"><xf/></cellXfs></styleSheet>"#.utf8)
    }

    private static func worksheet(_ sheet: Sheet) -> Data {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>"#
        for (rowIndex, row) in sheet.rows.enumerated() {
            xml += #"<row r="\#(rowIndex + 1)">"#
            for (columnIndex, value) in row.enumerated() {
                let ref = "\(columnName(columnIndex))\(rowIndex + 1)"
                xml += #"<c r="\#(ref)" t="inlineStr"><is><t xml:space="preserve">\#(escape(value))</t></is></c>"#
            }
            xml += "</row>"
        }
        xml += "</sheetData></worksheet>"
        return Data(xml.utf8)
    }

    private static func columnName(_ index: Int) -> String {
        var value = index + 1
        var result = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            result = String(UnicodeScalar(65 + remainder)!) + result
            value = (value - 1) / 26
        }
        return result
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
