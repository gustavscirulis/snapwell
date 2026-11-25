import Foundation

struct SpaceSymbol: Identifiable, Hashable, Sendable {
    let name: String
    let title: String
    let category: String
    let keywords: [String]

    var id: String { name }

    init(_ name: String, _ title: String, category: String, keywords: [String] = []) {
        self.name = name
        self.title = title
        self.category = category
        self.keywords = keywords
    }
}

enum SpaceSymbolCatalog {
    static let fallbackName = "folder"

    static let symbols: [SpaceSymbol] = [
        SpaceSymbol("folder", "Folder", category: "General", keywords: ["collection", "files"]),
        SpaceSymbol("star", "Favorites", category: "General", keywords: ["favorite", "saved", "best"]),
        SpaceSymbol("heart", "Loved", category: "General", keywords: ["love", "likes"]),
        SpaceSymbol("bookmark", "Bookmarks", category: "General", keywords: ["saved", "later"]),
        SpaceSymbol("archivebox", "Archive", category: "General", keywords: ["archive", "storage"]),
        SpaceSymbol("tray", "Inbox", category: "General", keywords: ["inbox", "incoming"]),
        SpaceSymbol("tag", "Tags", category: "General", keywords: ["tag", "label"]),
        SpaceSymbol("flag", "Flagged", category: "General", keywords: ["flag", "important"]),
        SpaceSymbol("pin", "Pinned", category: "General", keywords: ["pin", "location"]),
        SpaceSymbol("sparkles", "Inspiration", category: "General", keywords: ["inspiration", "ideas", "magic"]),
        SpaceSymbol("lightbulb", "Ideas", category: "General", keywords: ["idea", "concept", "inspiration"]),
        SpaceSymbol("checkmark.circle", "Completed", category: "General", keywords: ["done", "complete", "approved"]),

        SpaceSymbol("photo", "Photos", category: "Media", keywords: ["photo", "image", "photography"]),
        SpaceSymbol("photo.on.rectangle.angled", "Gallery", category: "Media", keywords: ["gallery", "images", "moodboard"]),
        SpaceSymbol("camera", "Camera", category: "Media", keywords: ["camera", "shoot"]),
        SpaceSymbol("video", "Videos", category: "Media", keywords: ["video", "movie", "film"]),
        SpaceSymbol("play.rectangle", "Watch", category: "Media", keywords: ["watch", "video", "youtube"]),
        SpaceSymbol("music.note", "Music", category: "Media", keywords: ["music", "audio", "song"]),
        SpaceSymbol("waveform", "Audio", category: "Media", keywords: ["audio", "podcast", "sound"]),
        SpaceSymbol("paintpalette", "Art", category: "Media", keywords: ["art", "color", "creative"]),
        SpaceSymbol("theatermasks", "Entertainment", category: "Media", keywords: ["theater", "entertainment"]),
        SpaceSymbol("book", "Reading", category: "Media", keywords: ["book", "read", "reading"]),

        SpaceSymbol("paintbrush", "Design", category: "Design", keywords: ["design", "visual", "brand"]),
        SpaceSymbol("square.on.square", "UI Design", category: "Design", keywords: ["ui", "interface", "screens"]),
        SpaceSymbol("rectangle.3.group", "Layouts", category: "Design", keywords: ["layout", "wireframe", "dashboard"]),
        SpaceSymbol("textformat", "Typography", category: "Design", keywords: ["type", "typography", "font"]),
        SpaceSymbol("swatchpalette", "Colors", category: "Design", keywords: ["color", "palette", "theme"]),
        SpaceSymbol("scribble.variable", "Sketches", category: "Design", keywords: ["sketch", "drawing"]),
        SpaceSymbol("cube", "3D", category: "Design", keywords: ["3d", "model", "object"]),
        SpaceSymbol("app.dashed", "Apps", category: "Design", keywords: ["app", "product"]),
        SpaceSymbol("iphone", "Mobile", category: "Design", keywords: ["mobile", "ios", "iphone"]),
        SpaceSymbol("desktopcomputer", "Desktop", category: "Design", keywords: ["desktop", "mac", "computer"]),

        SpaceSymbol("briefcase", "Work", category: "Work", keywords: ["work", "business", "job"]),
        SpaceSymbol("building.2", "Company", category: "Work", keywords: ["company", "office", "business"]),
        SpaceSymbol("person.2", "Team", category: "Work", keywords: ["team", "people", "collaboration"]),
        SpaceSymbol("person.crop.circle", "People", category: "Work", keywords: ["person", "profile", "portrait"]),
        SpaceSymbol("bubble.left.and.bubble.right", "Communication", category: "Work", keywords: ["chat", "message", "communication"]),
        SpaceSymbol("calendar", "Planning", category: "Work", keywords: ["calendar", "plan", "schedule"]),
        SpaceSymbol("list.bullet.clipboard", "Tasks", category: "Work", keywords: ["task", "todo", "checklist"]),
        SpaceSymbol("chart.bar", "Analytics", category: "Work", keywords: ["analytics", "chart", "metrics", "data"]),
        SpaceSymbol("doc.text", "Documents", category: "Work", keywords: ["document", "report", "writing"]),
        SpaceSymbol("hammer", "Projects", category: "Work", keywords: ["project", "build", "tools"]),

        SpaceSymbol("airplane", "Travel", category: "Places", keywords: ["travel", "flight", "vacation"]),
        SpaceSymbol("map", "Places", category: "Places", keywords: ["map", "place", "location"]),
        SpaceSymbol("globe", "World", category: "Places", keywords: ["world", "global", "web"]),
        SpaceSymbol("house", "Home", category: "Places", keywords: ["home", "house", "interior"]),
        SpaceSymbol("building.columns", "Culture", category: "Places", keywords: ["museum", "culture", "architecture"]),
        SpaceSymbol("mountain.2", "Outdoors", category: "Places", keywords: ["mountain", "outdoor", "nature"]),
        SpaceSymbol("beach.umbrella", "Vacation", category: "Places", keywords: ["beach", "holiday", "vacation"]),
        SpaceSymbol("car", "Cars", category: "Places", keywords: ["car", "automotive", "vehicle"]),
        SpaceSymbol("bicycle", "Cycling", category: "Places", keywords: ["bike", "bicycle", "cycling"]),

        SpaceSymbol("leaf", "Nature", category: "Life", keywords: ["nature", "plant", "garden"]),
        SpaceSymbol("fork.knife", "Food", category: "Life", keywords: ["food", "restaurant", "recipe"]),
        SpaceSymbol("cup.and.saucer", "Coffee", category: "Life", keywords: ["coffee", "cafe", "drink"]),
        SpaceSymbol("figure.run", "Fitness", category: "Life", keywords: ["fitness", "run", "sport"]),
        SpaceSymbol("dumbbell", "Training", category: "Life", keywords: ["gym", "workout", "training"]),
        SpaceSymbol("tshirt", "Fashion", category: "Life", keywords: ["fashion", "clothing", "style"]),
        SpaceSymbol("bag", "Shopping", category: "Life", keywords: ["shopping", "store", "product"]),
        SpaceSymbol("gift", "Gifts", category: "Life", keywords: ["gift", "present"]),
        SpaceSymbol("pawprint", "Pets", category: "Life", keywords: ["pet", "animal", "dog", "cat"]),
        SpaceSymbol("gamecontroller", "Games", category: "Life", keywords: ["game", "gaming", "play"]),

        SpaceSymbol("curlybraces", "Code", category: "Technology", keywords: ["code", "development", "programming"]),
        SpaceSymbol("terminal", "Terminal", category: "Technology", keywords: ["terminal", "command", "developer"]),
        SpaceSymbol("network", "Network", category: "Technology", keywords: ["network", "system", "infrastructure"]),
        SpaceSymbol("server.rack", "Servers", category: "Technology", keywords: ["server", "backend", "cloud"]),
        SpaceSymbol("cpu", "Hardware", category: "Technology", keywords: ["cpu", "hardware", "chip"]),
        SpaceSymbol("lock", "Security", category: "Technology", keywords: ["security", "privacy", "password"]),
        SpaceSymbol("shippingbox", "Products", category: "Technology", keywords: ["product", "package", "commerce"]),
        SpaceSymbol("wrench.and.screwdriver", "Tools", category: "Technology", keywords: ["tool", "utility", "settings"])
    ]

    static let names = Set(symbols.map(\.name))

    static func search(_ query: String) -> [SpaceSymbol] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return symbols }
        return symbols.filter { symbol in
            let haystack = ([symbol.name, symbol.title, symbol.category] + symbol.keywords)
                .joined(separator: " ")
                .lowercased()
            return terms.allSatisfy(haystack.contains)
        }
    }

    static func fallbackSymbol(for title: String) -> String {
        let normalized = title.lowercased()
        let ranked = symbols.compactMap { symbol -> (String, Int)? in
            let terms = [symbol.title.lowercased()] + symbol.keywords.map { $0.lowercased() }
            let score = terms.reduce(into: 0) { result, term in
                if normalized == term { result += 10 }
                else if normalized.contains(term) { result += 3 }
            }
            return score > 0 ? (symbol.name, score) : nil
        }
        return ranked.max { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0 > rhs.0 : lhs.1 < rhs.1
        }?.0 ?? fallbackName
    }
}
