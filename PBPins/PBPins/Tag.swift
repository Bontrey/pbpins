//
//  Tag.swift
//  PBPins
//
//  Created by Long Wei on 23.01.2026.
//

import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var name: String
    var count: Int

    init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}
