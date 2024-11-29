//
//  TagCode.swift
//  ARTest
//
//  Created by Ben Visness on 11/29/24.
//

import Foundation

var alphabet: [String] = ["B", "F", "K", "L", "M", "R", "S", "T"]

func tagIDToCode(_ id: Int) -> String {
    let b0 = (id >> 0) & 0b111
    let b1 = (id >> 3) & 0b111
    let b2 = (id >> 6) & 0b111
    let b3 = (id >> 9) & 0b111

    let c0 = alphabet[b0]
    let c1 = alphabet[b1]
    let c2 = alphabet[b2]
    let c3 = alphabet[b3]

    return c0 + c1 + c2 + c3
}
