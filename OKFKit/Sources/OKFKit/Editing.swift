import Foundation

/// Text-level edits to OKF files. Only the touched key or line changes; comments, order and unknown keys survive.
public enum OKFEditing {
    // MARK: Frontmatter

    /// Replaces a top-level key and its nested lines with `entry` (one or more lines, key included),
    /// appends it when the key is absent, and removes it when `entry` is nil.
    public static func setting(_ key: String, to entry: String?, in yaml: String) -> String {
        var lines = yaml.components(separatedBy: "\n")
        let hadTrailingNewline = lines.last == ""
        if hadTrailingNewline { lines.removeLast() }
        let replacement = entry.map { $0.components(separatedBy: "\n") } ?? []
        if let span = span(of: key, in: lines) {
            lines.replaceSubrange(span, with: replacement)
        } else {
            lines += replacement
        }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? "" : text + "\n"
    }

    /// True when the YAML sets `key` at the top level.
    public static func hasKey(_ key: String, in yaml: String) -> Bool {
        span(of: key, in: yaml.components(separatedBy: "\n")) != nil
    }

    /// Adds a verification event, keeping earlier ones, and writes `verified` as a block list.
    public static func addingVerification(_ stamp: OKFStamp, to yaml: String) throws(OKFConcept.ParseError) -> String {
        let stamps = try OKFConcept(yaml: yaml).verified + [stamp]
        let entry = (["verified:"] + stamps.map { "  - " + render($0) }).joined(separator: "\n")
        return setting("verified", to: entry, in: yaml)
    }

    /// Sets `status`; `stable` removes the key when it was absent, since absent means stable (§5.4).
    public static func settingStatus(_ status: OKFStatus, in yaml: String) -> String {
        if status == .stable && !hasKey("status", in: yaml) { return yaml }
        return setting("status", to: "status: \(status.name)", in: yaml)
    }

    /// `{ by: …, at: … }`, the flow form the spec uses.
    public static func render(_ stamp: OKFStamp) -> String {
        var parts: [String] = []
        if let by = stamp.by { parts.append("by: \(scalar(by.description))") }
        if let at = stamp.atRaw ?? stamp.at.map(OKFTimestamp.format) { parts.append("at: \(scalar(at))") }
        return "{ " + parts.joined(separator: ", ") + " }"
    }

    /// A YAML scalar, quoted only when a plain one would change meaning.
    public static func scalar(_ value: String) -> String {
        let plain = value.range(of: #"^[A-Za-z0-9_./@+-][A-Za-z0-9 _./:@+-]*$"#, options: .regularExpression) != nil
            && !value.contains(": ") && !value.hasSuffix(":") && !value.hasSuffix(" ")
            && !["true", "false", "yes", "no", "null", "on", "off", "~"].contains(value.lowercased())
        if plain { return value }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Lines belonging to a top-level key: its own line plus indented or `- ` continuation lines.
    static func span(of key: String, in lines: [String]) -> Range<Int>? {
        let pattern = "^(\(NSRegularExpression.escapedPattern(for: key))|\"\(NSRegularExpression.escapedPattern(for: key))\"|'\(NSRegularExpression.escapedPattern(for: key))')[ \\t]*:"
        guard let start = lines.firstIndex(where: { $0.range(of: pattern, options: .regularExpression) != nil }) else { return nil }
        var end = start + 1
        var last = start
        while end < lines.count {
            let line = lines[end]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { end += 1; continue }
            guard line.hasPrefix(" ") || line.hasPrefix("\t") || line.hasPrefix("- ") || line == "-" else { break }
            last = end
            end += 1
        }
        return start..<(last + 1)
    }

    // MARK: Templates

    /// Frontmatter for a new concept (§4.1), stamped as written by `author` when given. A nil type leaves `type:` to fill in.
    public static func conceptTemplate(type: String?, title: String? = nil, author: OKFActor? = nil, date: Date = Date()) -> String {
        var lines = ["---", "type: \(type.map(scalar) ?? "")"]
        lines.append("title: \(title.map(scalar) ?? "")")
        lines.append("description: ")
        lines.append("tags: []")
        lines.append("status: draft")
        if let author { lines.append("generated: " + render(OKFStamp(by: author, at: date))) }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Index files

    /// A fresh `index.md` for a directory (§8): one section per concept type, then subdirectories.
    /// The bundle-root index keeps its frontmatter, or declares the current `okf_version`.
    public static func renderIndex(directory: URL, bundle: OKFBundle, existing: String? = nil) -> String {
        let isRoot = OKFBundle.key(directory) == OKFBundle.key(bundle.root)
        var output = ""
        if isRoot {
            if let existing, let block = FrontmatterBlock.locate(in: existing) {
                output = (existing as NSString).substring(with: NSRange(location: 0, length: block.blockRange.upperBound))
                if !output.hasSuffix("\n") { output += "\n" }
            } else {
                output = "---\nokf_version: \"\(OKF.specVersion)\"\n---\n"
            }
            output += "\n"
        }
        let contents = bundle.contents(of: directory)
        let concepts = contents.documents.filter { $0.kind == .concept }
        let groups = Dictionary(grouping: concepts) { ($0.concept?.type).flatMap { $0.isEmpty ? nil : $0 } ?? "Other" }
        var sections: [String] = []
        for type in groups.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let entries = groups[type]!.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map { document in
                entry(title: document.title, link: OKFLinks.relativePath(to: document.url, from: directory), description: document.concept?.description)
            }
            sections.append("# \(type)\n\n" + entries.joined(separator: "\n"))
        }
        if !contents.subdirectories.isEmpty {
            let entries = contents.subdirectories.map { folder in
                let count = bundle.concepts.filter { OKFBundle.contains(folder, $0.url) }.count
                return entry(title: folder.lastPathComponent, link: folder.lastPathComponent + "/",
                             description: "\(count) \(count == 1 ? "concept" : "concepts")")
            }
            sections.append("# Directories\n\n" + entries.joined(separator: "\n"))
        }
        return output + sections.joined(separator: "\n\n") + "\n"
    }

    private static func entry(title: String, link: String, description: String?) -> String {
        let label = title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        let target = link.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? link
        let summary = description.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return "* [\(label)](\(target))" + (summary.isEmpty ? "" : " - \(summary)")
    }

    // MARK: Log files

    /// Adds `* **label**: text` under today's `## YYYY-MM-DD` heading, creating the log or the heading as needed (§9).
    public static func appendingLogEntry(_ text: String, label: String = "Update", date: Date = Date(),
                                         calendar: Calendar = .current, to existing: String?) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        let line = "* **\(label)**: \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        guard let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "# Directory Update Log\n\n## \(day)\n\(line)\n"
        }
        var lines = existing.components(separatedBy: "\n")
        if let first = lines.firstIndex(where: { $0.hasPrefix("## ") }) {
            if lines[first].dropFirst(3).trimmingCharacters(in: .whitespaces) == day {
                lines.insert(line, at: first + 1)
            } else {
                lines.insert(contentsOf: ["## \(day)", line, ""], at: first)
            }
        } else {
            while lines.last?.isEmpty == true { lines.removeLast() }
            lines += ["", "## \(day)", line]
        }
        let result = lines.joined(separator: "\n")
        return result.hasSuffix("\n") ? result : result + "\n"
    }
}

// MARK: Moving files

extension OKFEditing {
    /// Rewrites the links in one document after a file moves from `old` to `new` (§6).
    ///
    /// Links that pointed at the moved file follow it; when the document itself is the one that moved,
    /// its relative links are recomputed from the new folder. Body links and path-valued frontmatter fields
    /// are both updated, keeping each link's style: bundle-absolute stays absolute, relative stays relative.
    public static func retargetingLinks(in source: String, document: URL, root: URL, movedFrom old: URL, to new: URL) -> String {
        let documentMoved = OKFBundle.key(document) == OKFBundle.key(old)
        let newDocument = documentMoved ? new : document
        func retarget(_ target: String) -> String? {
            guard let resolved = OKFLinks.resolve(target, from: document, bundleRoot: root) else { return nil }
            let pointsAtMoved = OKFBundle.key(resolved) == OKFBundle.key(old)
            guard pointsAtMoved || (documentMoved && !target.hasPrefix("/")) else { return nil }
            let destination = pointsAtMoved ? new : resolved
            let suffix = target.firstIndex(where: { $0 == "#" || $0 == "?" }).map { String(target[$0...]) } ?? ""
            var path: String
            if target.hasPrefix("/") {
                guard let absolute = OKFLinks.bundlePath(of: destination, root: root) else { return nil }
                path = absolute
            } else {
                path = OKFLinks.relativePath(to: destination, from: newDocument.deletingLastPathComponent())
                if target.hasPrefix("./") && !path.hasPrefix("../") { path = "./" + path }
            }
            if target.contains("%") || path.contains(" ") { path = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path }
            let updated = path + suffix
            return updated == target ? nil : updated
        }
        return rewritingTargets(in: source, retarget)
    }

    /// Turns bundle-absolute links into relative ones, for exports that leave the bundle (§6.1).
    public static func relativizingLinks(in source: String, document: URL, root: URL) -> String {
        rewritingTargets(in: source) { target in
            guard target.hasPrefix("/"), let resolved = OKFLinks.resolve(target, from: document, bundleRoot: root) else { return nil }
            let suffix = target.firstIndex(where: { $0 == "#" || $0 == "?" }).map { String(target[$0...]) } ?? ""
            let path = OKFLinks.relativePath(to: resolved, from: document.deletingLastPathComponent())
            return (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path) + suffix
        }
    }

    /// Applies `retarget` to every body link destination and path-valued frontmatter value, back to front so offsets hold.
    static func rewritingTargets(in source: String, _ retarget: (String) -> String?) -> String {
        let text = NSMutableString(string: source)
        let block = FrontmatterBlock.locate(in: source)
        let bodyStart = block?.blockRange.upperBound ?? 0
        let body = text.substring(from: bodyStart)
        for link in OKFLinks.extract(from: body).reversed() {
            guard let updated = retarget(link.target) else { continue }
            let range = NSRange(location: bodyStart + link.range.lowerBound, length: link.range.count)
            let whole = text.substring(with: range) as NSString
            let inner = whole.range(of: link.target, options: .backwards)
            guard inner.location != NSNotFound else { continue }
            text.replaceCharacters(in: NSRange(location: range.location + inner.location, length: inner.length), with: updated)
        }
        if let block, case .success(let concept)? = OKFConcept.parse(source: source) {
            var yaml = block.yaml
            for reference in Set(concept.references.map(\.target)) {
                guard let updated = retarget(reference) else { continue }
                // Only whole scalars change, quoted or plain, so a longer path sharing a prefix is left alone.
                let pattern = #"(?m)(?<=[\s:\[,{-])(["']?)"# + NSRegularExpression.escapedPattern(for: reference) + #"\1(?=\s*(?:[,}\]#]|$))"#
                let regex = try! NSRegularExpression(pattern: pattern)
                yaml = regex.stringByReplacingMatches(in: yaml, range: NSRange(location: 0, length: (yaml as NSString).length),
                                                      withTemplate: "$1" + NSRegularExpression.escapedTemplate(for: updated) + "$1")
            }
            text.replaceCharacters(in: NSRange(location: block.yamlRange.lowerBound, length: block.yamlRange.count), with: yaml)
        }
        return text as String
    }
}
