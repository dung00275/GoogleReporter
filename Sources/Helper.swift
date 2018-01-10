//
//  Helper.swift
//  GoogleReporterPackageDescription
//
//  Created by Dung Vu on 1/10/18.
//

import Foundation

infix operator +
func +<T, V>(lhs: [T: V], rhs: [T: V]) -> [T: V] {
    var lhs = lhs
    rhs.forEach({ lhs[$0.key] = $0.value })
    return lhs
}

extension URLQueryItem {
    var query: String {
        return "\(self.name)=\(self.value ?? "")"
    }
}

extension Array {
    subscript(from maxItem: Int) -> [Element] {
        let nItems = Swift.min(self.count, maxItem)
        return Array(self[0..<nItems])
    }
}

func -=<E: Hashable>(lhs: inout [E], rhs:[E]) {
    guard lhs.count > 0, rhs.count > 0 else {
        return
    }
    var n = Set(lhs)
    defer {
        autoreleasepool { () -> () in
            n.removeAll()
        }
    }
    n.subtract(rhs)
    lhs = Array(n)
}

extension URL: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        guard let url = URL(string: value) else {
            fatalError("Invalid value \(value)")
        }
        self = url
    }
}
