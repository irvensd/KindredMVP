import Foundation

enum DemoData {
    static let people: [MemberProfile] = [
        member(id: "amara", name: "Amara", age: 28, gender: .female, city: "Chicago, IL", miles: 12, job: "Pediatric nurse", image: "amara", bio: "Equal parts big-hearted and quietly adventurous. Usually planning a trail walk, trying a new recipe, or saving you the last slice of mango.", interests: [.hiking, .cooking, .service, .music], answers: ["A long walk by the lake, a table full of friends, and absolutely no rush.", "Someone remembering how I take my tea. And a really good harmony.", "Is kind when no one is watching, and can laugh when the recipe goes wrong."]),
        member(id: "eli", name: "Eli", age: 31, gender: .male, city: "Evanston, IL", miles: 18, job: "Architect & weekend cook", image: "eli", bio: "I design spaces for a living and make room for people for fun. A good conversation beats a perfect itinerary. Ask me about my very ambitious vegetable garden.", interests: [.gardening, .art, .cooking, .travel], answers: ["Cooking enough for whoever drops by after church.", "The first tomato of the season. It never makes it into the kitchen.", "Wants to build a thoughtful life, one ordinary beautiful day at a time."]),
        member(id: "june", name: "June", age: 27, gender: .female, city: "Oak Park, IL", miles: 22, job: "Designer & book collector", image: "june", bio: "My bookshelf is organized by feeling. I love a slow morning, a good museum, and friends who turn errands into adventures. Faith gives my curiosity a home.", interests: [.books, .art, .photography, .games], answers: ["A picnic, a paperback, and a conversation that wanders.", "A handwritten note tucked inside a borrowed book.", "Makes room for both deep questions and very silly jokes."]),
        member(id: "rowan", name: "Rowan", age: 29, gender: .male, city: "Madison, WI", miles: 145, job: "Outdoor educator", image: "rowan", bio: "Most at home under a wide sky. I teach, hike, and keep a running list of little things to be grateful for. Looking for a connection with room to grow.", interests: [.hiking, .nature, .photography, .service], answers: ["Finding a quiet trail and leaving my phone in my bag.", "That moment when the whole room starts singing together.", "Leads with curiosity, kindness, and a little courage."])
    ]
    static func member(id: String, name: String, age: Int, gender: Gender, city: String, miles: Int, job: String, image: String, bio: String, interests: Set<Interest>, answers: [String]) -> MemberProfile {
        let questions = ["My ideal Sabbath afternoon…", "A little thing that makes me happy…", "I'm looking for someone who…"]
        var profile = MemberProfile(id: id, name: name, age: age, gender: gender, city: city, distanceMiles: miles, occupation: job,
                     bio: bio, intention: .lifePartner, faith: .init(sabbath: id == "rowan" ? .outdoors : .community, food: .vegetarian),
                     interests: interests, prompts: zip(questions.indices, answers).map { .init(id: "\(id)-\($0.0)", question: questions[$0.0], answer: $0.1) },
                     photos: [.bundled(image, caption: "AI-generated portrait of fictional member \(name)"), .bundled("weekend", caption: "A little weekend inspiration · shared AI-generated sample photo")])
        if id == "amara" || id == "june" { profile.distanceOpenness = .longDistance }
        if id == "rowan" { profile.distanceOpenness = .local; profile.openToRelocating = true }
        return profile
    }
    static func expandedSnapshot(now: Date) -> SessionSnapshot {
        var state = snapshot(now: now)
        let names = ["Naomi", "Caleb", "Sofia", "Micah", "Grace", "Daniel", "Leah", "Noah"]
        let replies = [
            "Do you have a favorite trail for a quiet afternoon?",
            "I tried your soup idea. The whole table asked for seconds!",
            "Which book would you lend a friend first?",
            "I'd love to hear more about your community garden.",
            "That sounds lovely. What do you usually bring to a picnic?",
            "A museum afternoon sounds like a good plan.",
            "What's a small thing that made you smile this week?",
            "I hope your volunteering day went well."
        ]
        for (index, name) in names.enumerated() {
            let id = "demo-" + name.lowercased()
            var profile = people[index % people.count]
            profile = member(
                id: id, name: name, age: 25 + index, gender: profile.gender,
                city: profile.city, miles: profile.distanceMiles,
                job: profile.occupation, image: profile.photos[0].assetName ?? "weekend",
                bio: profile.bio, interests: profile.interests,
                answers: profile.prompts.map(\.answer)
            )
            state.members.append(profile)
            let date = now.addingTimeInterval(-Double(index + 1) * 30_000)
            state.matches.append(.init(id: "match-" + id, memberID: id, createdAt: date))
            let messages: [Message] = index == 7 ? [] : [
                .init(id: id + "-hello", senderID: "me", text: "Hi " + name + "! It's lovely to connect.", createdAt: date.addingTimeInterval(-90_000)),
                .init(id: id + "-reply", senderID: id, text: replies[index], createdAt: date)
            ]
            state.conversations.append(.init(
                id: "chat-" + id, memberID: id, messages: messages,
                unreadCount: index < 7 && index.isMultiple(of: 2) ? 1 : 0
            ))
        }
        let regionalCities: [SearchCity] = [.atlanta, .dallas, .newYork, .lomaLinda]
        for (index, city) in regionalCities.enumerated() {
            let id = "regional-\(index)"
            let profile = member(id: id, name: ["Rachel", "Isaac", "Esther", "Josiah"][index],
                age: 28 + index, gender: index.isMultiple(of: 2) ? .female : .male,
                city: city.rawValue, miles: 0, job: "Teacher & community volunteer",
                image: people[index].photos[0].assetName ?? "weekend",
                bio: "A generous table, shared faith, and room for a good conversation.",
                interests: [.books, .service, .cooking],
                answers: ["A walk, a shared meal, and time for friends.", "An unexpected act of kindness.", "Makes room for faith and laughter."])
            state.members.append(profile)
        }
        return state
    }

    static func snapshot(now: Date) -> SessionSnapshot {
        let me = MemberProfile(id: "me", name: "Alex", age: 28, gender: .male, city: "Chicago, IL", distanceMiles: 0, occupation: "Making room for connection", bio: "A curious soul, a generous table, and a little adventure. Here to find something meaningful.", intention: .relationship, faith: .init(), interests: [.hiking, .cooking, .books], prompts: people[0].prompts.enumerated().map { .init(id: "own-\($0.offset)", question: $0.element.question, answer: $0.element.answer) }, photos: [.bundled("rowan", caption: "AI-generated sample portrait for Alex")], isDemo: false)
        return .init(currentProfile: me, members: people,
                     likes: [.init(id: "incoming-amara", senderID: "amara", recipientID: "me", promptID: nil, createdAt: now), .init(id: "incoming-june", senderID: "june", recipientID: "me", promptID: nil, createdAt: now)],
                     matches: [.init(id: "match-eli", memberID: "eli", createdAt: now)],
                     conversations: [.init(id: "chat-eli", memberID: "eli", messages: [
                        .init(id: "seed-1", senderID: "eli", text: "Your ideal Sabbath sounds lovely. Do you have a favorite spot by the lake?", createdAt: now.addingTimeInterval(-3600)),
                        .init(id: "seed-2", senderID: "me", text: "Anywhere with a little shade and room for a picnic. How about you?", createdAt: now.addingTimeInterval(-3200)),
                        .init(id: "seed-3", senderID: "eli", text: "That sounds like my kind of afternoon. I'd bring something homemade!", createdAt: now.addingTimeInterval(-1800))], unreadCount: 1)])
    }
}
