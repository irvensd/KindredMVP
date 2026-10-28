import Foundation

struct OnboardingDraft: Sendable {
    var acknowledgedAdult = false
    var name = ""
    var birthDate = Calendar(identifier: .gregorian).date(byAdding: .year, value: -25, to: Date())!
    var gender: Gender?
    var genders: Set<Gender> = []
    var city = ""
    var radiusMiles = 75
    var intention: Intention?
    var faith = FaithPreferences()
    var interests: Set<Interest> = []
    var prompts: [ProfilePrompt] = [
        .init(id: "own-1", question: "My ideal Sabbath afternoon…", answer: ""),
        .init(id: "own-2", question: "A little thing that makes me happy…", answer: ""),
        .init(id: "own-3", question: "I'm looking for someone who…", answer: "")
    ]
    var photos: [ProfilePhoto] = []
    static let stepCount = 4
    static func age(on date: Date, birthDate: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        // Compare civil dates explicitly. For February 29 birthdays in a non-leap
        // year, the prototype conservatively waits until March 1.
        let birth = calendar.dateComponents([.year, .month, .day], from: birthDate)
        let current = calendar.dateComponents([.year, .month, .day], from: date)
        guard let by = birth.year, let bm = birth.month, let bd = birth.day,
              let cy = current.year, let cm = current.month, let cd = current.day else { return -1 }
        return cy - by - ((cm < bm || (cm == bm && cd < bd)) ? 1 : 0)
    }
    static func isEligible(birthDate: Date, now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        birthDate <= now && age(on: now, birthDate: birthDate, calendar: calendar) >= 18
    }
    func validationError(step: Int, now: Date = Date()) -> String? {
        switch step {
        case 0:
            guard (1...40).contains(name.trimmed.count) else { return "Tell us your first name (1–40 characters)." }
            guard acknowledgedAdult else { return "Please confirm that you are at least 18 to continue." }
            return Self.isEligible(birthDate: birthDate, now: now) ? nil : "Kindred is for adults 18 and older. Check your birth date."
        case 1:
            guard gender != nil else { return "Choose Male or Female to continue." }
            return genders.isEmpty ? "Choose who you'd like to meet." : nil
        case 2:
            guard (2...60).contains(city.trimmed.count), (5...250).contains(radiusMiles) else { return "Add a general city or area (2–60 characters) and a radius of 5–250 miles." }
            return intention == nil ? "Choose what you're hoping to find." : nil
        case 3:
            return (1...6).contains(photos.count) ? nil : "Add a photo, or choose a clearly labeled demo portrait."
        default: return "Please return to the start of your profile setup."
        }
    }
    func profile(now: Date = Date()) -> MemberProfile {
        .init(id: "me", name: name.trimmed, age: Self.age(on: now, birthDate: birthDate), gender: gender ?? .male,
              city: city.trimmed, distanceMiles: 0, occupation: "A new chapter", bio: "Here for shared faith and genuine connection.",
              intention: intention ?? .intentional, faith: faith, interests: interests, prompts: prompts, photos: photos, isDemo: false)
    }
}
