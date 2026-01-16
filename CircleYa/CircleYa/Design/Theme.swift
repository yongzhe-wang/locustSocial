import SwiftUI

struct Theme {
    static let primary = Color("PrimaryColor")
    static let secondary = Color("SecondaryColor")
    static let background = Color("BackgroundColor")
    
    // Fallback colors if assets aren't set up yet
    // Primary
    static let pplPurple = Color(red: 0.4, green: 0.2, blue: 0.9) // #6633E6
    static let pplPink = Color(red: 0.9, green: 0.2, blue: 0.6) // #E63399
    
    // Backgrounds
    static let warmWhite = Color(red: 0.98, green: 0.98, blue: 1.0) // Cool white
    static let cardWhite = Color.white
    
    // Text
    static let textPrimary = Color(red: 0.1, green: 0.1, blue: 0.2) // Dark Blue-Black
    static let textSecondary = Color(red: 0.5, green: 0.5, blue: 0.6) // Blue-Grey
    static let textHint = Color(red: 0.7, green: 0.7, blue: 0.8) // Light Blue-Grey
    
    // Functional
    static let likeRed = Color(red: 1.0, green: 0.2, blue: 0.4) // Hot Red
    static let successGreen = Color(red: 0.0, green: 0.8, blue: 0.4) // Bright Green

    // Aliases for consistency
    static let primaryBrand = pplPurple
    static let secondaryBrand = pplPink
    static let backgroundMain = warmWhite
    
    static let gradient = LinearGradient(
        gradient: Gradient(colors: [pplPurple, pplPink]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let sunnyGradient = LinearGradient(
        gradient: Gradient(colors: [pplPink, pplPurple]),
        startPoint: .top,
        endPoint: .bottom
    )
}

extension Color {
    static let hiDayOrange = Theme.pplPurple // Mapping old to new
    static let hiDayRed = Theme.likeRed
    static let hiDayYellow = Theme.successGreen
    static let hiDayBackground = Theme.warmWhite
    static let hiDayTextPrimary = Theme.textPrimary
    static let hiDayTextSecondary = Theme.textSecondary
}
