//
//  UIColor.swift
//  OnlineConsultant
//
//  Created by Yriy Deviataev on 22.07.2026.
//

import UIKit

package extension UIColor {

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    convenience init?(hexString: String?) {
        guard
            let value = hexString?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingPrefix("#"),
            value.count == 6 || value.count == 8,
            let hexValue = UInt32(value, radix: 16)
        else {
            return nil
        }

        if value.count == 6 {
            self.init(hex: hexValue)
        } else {
            self.init(
                red: CGFloat((hexValue >> 16) & 0xFF) / 255,
                green: CGFloat((hexValue >> 8) & 0xFF) / 255,
                blue: CGFloat(hexValue & 0xFF) / 255,
                alpha: CGFloat((hexValue >> 24) & 0xFF) / 255
            )
        }
    }
}
