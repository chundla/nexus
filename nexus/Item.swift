//
//  Item.swift
//  nexus
//
//  Created by Chandler on 5/18/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date

    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
