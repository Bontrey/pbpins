//
//  Bookmark.swift
//  PBPins
//
//  Created by Long Wei on 22.01.2026.
//

import Foundation
import SwiftData

@Model
final class Bookmark {
    @Attribute(.unique) var id: String
    var url: String
    var title: String
    var desc: String
    var tags: [String]
    var created: Date
    var updated: Date
    var isPrivate: Bool

    init(id: String, url: String, title: String, desc: String, tags: [String], created: Date, updated: Date, isPrivate: Bool) {
        self.id = id
        self.url = url
        self.title = title
        self.desc = desc
        self.tags = tags
        self.created = created
        self.updated = updated
        self.isPrivate = isPrivate
    }
}
