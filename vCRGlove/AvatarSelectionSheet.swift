//
//  AvatarSelectionSheet.swift
//  vCRGlove
//
//  Created by Alexander Wiederhold on 05/06/2026.
//

import SwiftUI

private enum AvatarEmojiTopic: String, CaseIterable, Identifiable {
    case faces
    case animals
    case mobility
    case nature
    case food

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .faces: return "face.smiling"
        case .animals: return "dog"
        case .mobility: return "car"
        case .nature: return "tree"
        case .food: return "birthday.cake"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .faces: return "Faces"
        case .animals: return "Animals"
        case .mobility: return "Mobility"
        case .nature: return "Nature"
        case .food: return "Food"
        }
    }
}

struct AvatarSelectionSheet: View {
    @Binding var avatarStorage: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @State private var selectedTopic: AvatarEmojiTopic = .faces

    private let gridRows = Array(repeating: GridItem(.fixed(46), spacing: 10), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ProfileAvatarView(avatar: currentAvatar, size: 132)
                        .padding(.top, 8)

                    topicControls
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHGrid(rows: gridRows, spacing: 10) {
                            ForEach(filteredEmojis, id: \.self) { emoji in
                                Button {
                                    updateAvatar(emoji: emoji)
                                } label: {
                                    Text(emoji)
                                        .font(.title2)
                                        .frame(width: 46, height: 46)
                                        .background(selectionBackground(isSelected: currentAvatar.emoji == emoji), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 250)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 7), spacing: 14) {
                        ForEach(AvatarColorOption.all) { option in
                            Button {
                                updateAvatar(colorName: option.name)
                            } label: {
                                AvatarColorCircle(option: option, size: 34)
                                    .overlay {
                                        Circle().stroke(Color.primary.opacity(currentAvatar.colorName == option.name ? 0.85 : 0.16), lineWidth: currentAvatar.colorName == option.name ? 3 : 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.name.capitalized)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .background(avatarSheetBackground.ignoresSafeArea())
            .navigationTitle("Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if isSearchExpanded {
                    searchControl
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) {
                            isSearchExpanded = true
                        }
                        isSearchFocused = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Search emojis")
                }
            }
        }
    }

    private var currentAvatar: ProfileAvatarValue {
        ProfileAvatarValue(storageValue: avatarStorage)
    }

    private var avatarSheetBackground: some View {
        LinearGradient(
            colors: backgroundColors(for: currentAvatar.colorOption),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(.ultraThinMaterial.opacity(0.52))
    }

    private func glassCapsule<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .glassCapsuleBackground()
    }

    private var searchControl: some View {
        glassCapsule {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .imageScale(.medium)

                TextField("Search Emoji", text: $searchText)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .onSubmit {
                        isSearchFocused = false
                    }

                Button {
                    withAnimation(.snappy) {
                        searchText = ""
                        isSearchExpanded = false
                    }
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss search")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var topicControls: some View {
        HStack(spacing: 10) {
            ForEach(AvatarEmojiTopic.allCases) { topic in
                Button {
                    withAnimation(.snappy) {
                        selectedTopic = topic
                    }
                } label: {
                    Image(systemName: topic.symbolName)
                        .font(.system(size: 18, weight: selectedTopic == topic ? .semibold : .regular))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTopic == topic ? Color.accentColor : .primary)
                .accessibilityLabel(topic.accessibilityLabel)
                .glassCapsuleBackground(isSelected: selectedTopic == topic)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var filteredEmojis: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return Self.emojis
                .filter { emojiTopic(for: $0) == selectedTopic }
                .map(\.emoji)
        }

        return Self.emojis
            .filter { item in
                item.name.localizedCaseInsensitiveContains(query) || item.emoji == query
            }
            .map(\.emoji)
    }

    private func updateAvatar(emoji: String? = nil, colorName: String? = nil) {
        let avatar = currentAvatar
        avatarStorage = ProfileAvatarValue(
            emoji: emoji ?? avatar.emoji,
            colorName: colorName ?? avatar.colorName
        ).storageValue
    }

    private func selectionBackground(isSelected: Bool) -> Color {
        isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground)
    }

    private func backgroundColors(for option: AvatarColorOption) -> [Color] {
        switch option.name {
        case "green", "mint": return [.yellow.opacity(0.42), .red.opacity(0.30), .green.opacity(0.18)]
        case "blue", "cyan", "teal": return [.orange.opacity(0.36), .pink.opacity(0.28), .blue.opacity(0.20)]
        case "purple", "indigo": return [.yellow.opacity(0.34), .pink.opacity(0.28), .purple.opacity(0.20)]
        case "red", "pink": return [.mint.opacity(0.34), .yellow.opacity(0.30), .red.opacity(0.18)]
        case "orange", "yellow", "brown": return [.blue.opacity(0.30), .purple.opacity(0.24), option.color.opacity(0.20)]
        case "white": return [.cyan.opacity(0.22), .purple.opacity(0.18), .white.opacity(0.34)]
        case "black", "gray": return [.blue.opacity(0.22), .purple.opacity(0.20), .gray.opacity(0.18)]
        case "rainbow": return [.red.opacity(0.26), .yellow.opacity(0.24), .blue.opacity(0.24), .purple.opacity(0.22)]
        default: return [.yellow.opacity(0.30), .red.opacity(0.22), option.color.opacity(0.18)]
        }
    }

    private func emojiTopic(for item: (emoji: String, name: String)) -> AvatarEmojiTopic {
        let name = item.name.lowercased()
        if item.emoji == "🌈" || name.contains("sun") || name.contains("moon") || name.contains("cloud") || name.contains("snow") || name.contains("wave") || name.contains("seedling") || name.contains("herb") || name.contains("flower") || name.contains("blossom") || name.contains("rose") || name.contains("tulip") || name.contains("sunflower") || name.contains("lotus") || name.contains("tree") || name.contains("palm") || name.contains("cactus") || name.contains("leaf") || name.contains("clover") || name.contains("mushroom") || name.contains("earth") || name.contains("star") || name.contains("fire") || name.contains("rain") || name.contains("lightning") || name.contains("comet") {
            return .nature
        }
        if name.contains("animal") || name.contains("dog") || name.contains("cat") || name.contains("mouse") || name.contains("rat") || name.contains("hamster") || name.contains("rabbit") || name.contains("fox") || name.contains("bear") || name.contains("panda") || name.contains("koala") || name.contains("tiger") || name.contains("lion") || name.contains("leopard") || name.contains("horse") || name.contains("donkey") || name.contains("unicorn") || name.contains("zebra") || name.contains("deer") || name.contains("bison") || name.contains("cow") || name.contains("ox") || name.contains("buffalo") || name.contains("pig") || name.contains("boar") || name.contains("ram") || name.contains("sheep") || name.contains("goat") || name.contains("camel") || name.contains("llama") || name.contains("giraffe") || name.contains("elephant") || name.contains("rhino") || name.contains("hippo") || name.contains("frog") || name.contains("monkey") || name.contains("chicken") || name.contains("rooster") || name.contains("penguin") || name.contains("bird") || name.contains("eagle") || name.contains("duck") || name.contains("swan") || name.contains("owl") || name.contains("parrot") || name.contains("butterfly") || name.contains("turtle") || name.contains("whale") || name.contains("dolphin") || name.contains("fish") || name.contains("shark") || name.contains("octopus") || name.contains("crab") || name.contains("lobster") {
            return .animals
        }
        if name.contains("apple") || name.contains("orange fruit") || name.contains("lemon") || name.contains("banana") || name.contains("watermelon") || name.contains("grapes") || name.contains("strawberry") || name.contains("blueberries") || name.contains("cherries") || name.contains("kiwi") || name.contains("pineapple") || name.contains("mango") || name.contains("peach") || name.contains("pear") || name.contains("coconut") || name.contains("tomato") || name.contains("avocado") || name.contains("broccoli") || name.contains("carrot") || name.contains("pepper") || name.contains("corn") || name.contains("bread") || name.contains("cheese") || name.contains("egg") || name.contains("bacon") || name.contains("pizza") || name.contains("burger") || name.contains("fries") || name.contains("coffee") || name.contains("tea") || name.contains("cake") || name.contains("cupcake") || name.contains("cookie") || name.contains("chocolate") {
            return .food
        }
        if name.contains("car") || name.contains("taxi") || name.contains("bus") || name.contains("trolley") || name.contains("truck") || name.contains("tractor") || name.contains("motorcycle") || name.contains("scooter") || name.contains("bike") || name.contains("wheelchair") || name.contains("train") || name.contains("tram") || name.contains("railway") || name.contains("metro") || name.contains("airplane") || name.contains("helicopter") || name.contains("rocket") || name.contains("boat") || name.contains("ship") || name.contains("ferry") || name.contains("canoe") || name.contains("ball") || name.contains("tennis") || name.contains("volleyball") || name.contains("ping pong") || name.contains("target") || name.contains("running") || name.contains("walking") {
            return .mobility
        }
        return .faces
    }

    private static let emojis: [(emoji: String, name: String)] = [
        ("😀", "grinning face happy smile"), ("😃", "smiley face happy"), ("😄", "smile face happy"), ("😁", "beaming face smile"), ("😆", "laughing face"), ("😅", "sweat smile"), ("😂", "joy tears laugh"), ("🙂", "slight smile"), ("🙃", "upside down face"), ("😉", "wink face"), ("😊", "blush smile"), ("😇", "halo face"), ("🥰", "hearts face"), ("😍", "heart eyes"), ("🤩", "star eyes"), ("😘", "kiss face"), ("😋", "yum face"), ("😛", "tongue face"), ("🤗", "hug face"), ("🤔", "thinking face"), ("🤨", "raised eyebrow"), ("😐", "neutral face"), ("😎", "sunglasses cool"), ("🥳", "party face"), ("😴", "sleep face"),
        ("👋", "wave hand"), ("🤚", "raised back hand"), ("🖐", "hand fingers"), ("✋", "raised hand"), ("👌", "ok hand"), ("🤌", "pinched fingers"), ("🤏", "pinching hand"), ("✌️", "victory hand"), ("🤞", "crossed fingers"), ("🤟", "love you hand"), ("🤘", "horns hand"), ("👍", "thumbs up"), ("👎", "thumbs down"), ("✊", "fist"), ("👏", "clap hands"), ("🙌", "raised hands"), ("🫶", "heart hands"), ("🙏", "pray hands"), ("💪", "muscle arm"), ("🦾", "mechanical arm"),
        ("👶", "baby"), ("🧒", "child"), ("👩", "woman"), ("👨", "man"), ("🧑", "person"), ("👩‍⚕️", "doctor woman clinician"), ("👨‍⚕️", "doctor man clinician"), ("🧑‍⚕️", "health worker clinician"), ("👩‍🔬", "scientist woman"), ("👨‍🔬", "scientist man"), ("🧑‍🔬", "scientist"), ("👩‍💻", "technologist woman"), ("👨‍💻", "technologist man"), ("🧑‍💻", "technologist"), ("🧓", "older person"), ("👵", "older woman"), ("👴", "older man"),
        ("🐶", "dog"), ("🐕", "dog animal"), ("🐩", "poodle dog animal"), ("🐺", "wolf animal"), ("🦊", "fox animal"), ("🐱", "cat"), ("🐈", "cat animal"), ("🦁", "lion"), ("🐯", "tiger"), ("🐅", "tiger animal"), ("🐆", "leopard animal"), ("🐴", "horse face"), ("🐎", "horse animal"), ("🫏", "donkey animal"), ("🦄", "unicorn horse animal"), ("🦓", "zebra animal"), ("🦌", "deer animal"), ("🦬", "bison animal"), ("🐮", "cow"), ("🐂", "ox animal"), ("🐃", "buffalo animal"), ("🐄", "cow animal"), ("🐷", "pig"), ("🐗", "boar animal"), ("🐏", "ram animal"), ("🐑", "sheep animal"), ("🐐", "goat animal"), ("🐪", "camel animal"), ("🦙", "llama animal"), ("🦒", "giraffe animal"), ("🐘", "elephant animal"), ("🦏", "rhino animal"), ("🦛", "hippo animal"), ("🐭", "mouse"), ("🐹", "hamster"), ("🐰", "rabbit"), ("🐻", "bear"), ("🐼", "panda"), ("🐨", "koala"), ("🐸", "frog"), ("🐵", "monkey"), ("🐔", "chicken"), ("🐓", "rooster animal"), ("🐧", "penguin"), ("🦅", "eagle bird animal"), ("🦆", "duck bird animal"), ("🦢", "swan bird animal"), ("🦉", "owl bird animal"), ("🦜", "parrot bird animal"), ("🐢", "turtle"), ("🐳", "whale animal"), ("🐬", "dolphin animal"), ("🐟", "fish animal"), ("🦈", "shark animal"), ("🐙", "octopus animal"), ("🦀", "crab animal"), ("🦞", "lobster animal"),
        ("🚗", "car"), ("🚙", "sport utility car"), ("🏎️", "racing car"), ("🚕", "taxi car"), ("🚓", "police car"), ("🚑", "ambulance car"), ("🚒", "fire engine car"), ("🚐", "minibus car"), ("🛻", "pickup truck car"), ("🚚", "delivery truck"), ("🚛", "truck"), ("🚜", "tractor"), ("🏍️", "motorcycle"), ("🛵", "motor scooter"), ("🚲", "bike"), ("🛴", "kick scooter"), ("🦽", "manual wheelchair"), ("🦼", "motorized wheelchair"), ("🚂", "train"), ("🚆", "train railway"), ("🚇", "metro train"), ("🚊", "tram train"), ("🚝", "monorail train"), ("🚠", "mountain cableway"), ("✈️", "airplane"), ("🛫", "airplane departure"), ("🛬", "airplane arrival"), ("🚁", "helicopter"), ("🚀", "rocket"), ("🛸", "flying saucer"), ("⛵️", "sailboat boat"), ("🚤", "speedboat boat"), ("🛳️", "passenger ship"), ("⛴️", "ferry ship"), ("🛶", "canoe boat"), ("🚶", "walking person"), ("🏃", "running person"), ("⚽️", "soccer ball"), ("🏀", "basketball"), ("🏈", "football"), ("⚾️", "baseball"), ("🎾", "tennis"), ("🏐", "volleyball"), ("🏓", "ping pong"), ("🎯", "target"),
        ("🌈", "rainbow"), ("☀️", "sun"), ("🌤️", "sun behind cloud"), ("⛅️", "sun cloud"), ("🌦️", "sun rain cloud"), ("🌧️", "rain cloud"), ("⛈️", "thunder lightning rain"), ("🌩️", "lightning cloud"), ("❄️", "snow"), ("🌊", "wave"), ("🌙", "moon"), ("🌕", "full moon"), ("⭐️", "star"), ("✨", "sparkles"), ("☄️", "comet"), ("🔥", "fire"), ("🌍", "earth globe"), ("🌱", "seedling"), ("🪴", "potted plant"), ("🌲", "evergreen tree"), ("🌳", "deciduous tree"), ("🌴", "palm tree"), ("🌵", "cactus"), ("🌾", "sheaf rice plant"), ("🌿", "herb"), ("☘️", "clover"), ("🍀", "four leaf clover"), ("🍁", "maple leaf"), ("🍂", "fallen leaf"), ("🍃", "leaf wind"), ("🍄", "mushroom"), ("💐", "bouquet flower"), ("🌸", "cherry blossom flower"), ("🪷", "lotus flower"), ("🌹", "rose flower"), ("🌺", "hibiscus flower"), ("🌻", "sunflower"), ("🌼", "blossom flower"), ("🌷", "tulip"),
        ("🍏", "green apple"), ("🍎", "red apple"), ("🍐", "pear"), ("🍊", "orange fruit"), ("🍋", "lemon"), ("🍌", "banana"), ("🍉", "watermelon"), ("🍇", "grapes"), ("🍓", "strawberry"), ("🫐", "blueberries"), ("🍒", "cherries"), ("🍑", "peach"), ("🥭", "mango"), ("🍍", "pineapple"), ("🥥", "coconut"), ("🥝", "kiwi"), ("🍅", "tomato"), ("🥑", "avocado"), ("🥦", "broccoli"), ("🥕", "carrot"), ("🌽", "corn"), ("🌶️", "hot pepper"), ("🥒", "cucumber"), ("🥬", "leafy green"), ("🍞", "bread"), ("🥐", "croissant"), ("🧀", "cheese"), ("🥚", "egg"), ("🥓", "bacon"), ("🍕", "pizza"), ("🍔", "burger"), ("🍟", "fries"), ("☕️", "coffee"), ("🫖", "teapot"), ("🍵", "tea"), ("🎂", "birthday cake"), ("🧁", "cupcake"), ("🍪", "cookie"), ("🍫", "chocolate")
    ]
}

private extension View {
    @ViewBuilder
    func glassCapsuleBackground(isSelected: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: Capsule())
                .overlay {
                    Capsule().stroke(Color.accentColor.opacity(isSelected ? 0.45 : 0), lineWidth: 1.5)
                }
        } else {
            self
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(isSelected ? Color.accentColor.opacity(0.45) : Color(.separator).opacity(0.25), lineWidth: 1)
                }
        }
    }
}
