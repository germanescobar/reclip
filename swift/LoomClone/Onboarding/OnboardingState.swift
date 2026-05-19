import Foundation

enum OnboardingState {
    private static let completedKey = "onboarding.completed"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: completedKey)
    }
}
