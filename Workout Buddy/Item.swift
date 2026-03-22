//
//  Item.swift
//  Workout Buddy
//
//  Created by PETE MOUNTANOS on 3/22/26.
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
