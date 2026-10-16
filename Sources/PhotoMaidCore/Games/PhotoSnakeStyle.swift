import Foundation

public enum PhotoSnakeCharacter: String, Codable, CaseIterable, Sendable {
    case snake, dragon, dino, monster
    public var idle: String { self == .snake ? "head_idle_01" : "\(rawValue)_idle" }
    public var blink: String { self == .snake ? "head_idle_04" : "\(rawValue)_blink" }
    public var eat: String { self == .snake ? "head_eat_01" : "\(rawValue)_eat" }
    public var dead: String { self == .snake ? "head_dead_01" : "\(rawValue)_dead" }
}

public enum PhotoSnakeFood: String, Codable, CaseIterable, Sendable {
    case mixed, apple, star, heart, gem, grapes, donut, cheese, cake, pizza
    public func texture(score: Int) -> String {
        let choices = Self.allCases.filter { $0 != .mixed }
        let kind = self == .mixed ? choices[max(0, score) % choices.count] : self
        return "food_\(kind.rawValue)"
    }
}

public struct PhotoSnakePreferences: Codable, Equatable, Sendable {
    public var character = PhotoSnakeCharacter.snake
    public var night = false
    public var sound = true
    public var haptics = true
    public var shufflePhotos = false
    public var food = PhotoSnakeFood.mixed
    public var mode = PhotoSnakeGame.Mode.relaxed
    public var speed = PhotoSnakeSpeed.normal
    public init() {}
    private enum CodingKeys: String, CodingKey { case character, night, sound, haptics, shufflePhotos, food, mode, speed }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        character = (try? c.decode(PhotoSnakeCharacter.self, forKey: .character)) ?? d.character
        night = (try? c.decode(Bool.self, forKey: .night)) ?? d.night
        sound = (try? c.decode(Bool.self, forKey: .sound)) ?? d.sound
        haptics = (try? c.decode(Bool.self, forKey: .haptics)) ?? d.haptics
        shufflePhotos = (try? c.decode(Bool.self, forKey: .shufflePhotos)) ?? d.shufflePhotos
        food = (try? c.decode(PhotoSnakeFood.self, forKey: .food)) ?? d.food
        mode = (try? c.decode(PhotoSnakeGame.Mode.self, forKey: .mode)) ?? d.mode
        speed = (try? c.decode(PhotoSnakeSpeed.self, forKey: .speed)) ?? d.speed
    }
}

/// Deterministic animation schedule: no random actions or texture creation in the render loop.
public enum PhotoSnakeHeadAnimation {
    public struct Frame: Equatable, Sendable {
        public let texture: String
        public let scale: Double
    }
    public static func frame(character: PhotoSnakeCharacter, time: Double, eating: Double? = nil,
                             collision: Double? = nil, sleeping: Bool = false, danger: Bool = false,
                             lookingLeft: Bool? = nil, reduceMotion: Bool = false) -> Frame {
        let t = time.isFinite ? max(0, time) : 0
        if let age = collision, age >= 0 {
            let texture = age < 0.12 && character == .snake ? "head_hurt"
                : (age > 0.45 && character == .snake ? "head_dead_02" : character.dead)
            return Frame(texture: texture, scale: reduceMotion ? 1 : (age < 0.12 ? 0.96 : 1))
        }
        if let age = eating, (0..<0.18).contains(age) {
            let texture = age > 0.09 && character == .snake ? "head_eat_02" : character.eat
            return Frame(texture: texture, scale: reduceMotion ? 1 : 1 + 0.06 * sin(age / 0.18 * .pi))
        }
        if sleeping { return Frame(texture: character == .snake ? "head_sleep" : character.blink, scale: 1) }
        if danger, character == .snake { return Frame(texture: "head_surprised", scale: 1) }
        if let lookingLeft, character == .snake {
            return Frame(texture: lookingLeft ? "head_look_left" : "head_look_right", scale: 1)
        }
        let phase = t.truncatingRemainder(dividingBy: 5.7)
        let texture: String
        if (3.0..<3.15).contains(phase) { texture = character.blink }
        else if character == .snake, (4.6..<4.85).contains(phase) { texture = "head_idle_06" }
        else if character == .snake, (2.94..<3.0).contains(phase) { texture = "head_idle_03" }
        else if character == .snake, (3.15..<3.22).contains(phase) { texture = "head_idle_05" }
        else if character == .snake, (0.8..<1.1).contains(phase) { texture = "head_idle_02" }
        else { texture = character.idle }
        return Frame(texture: texture, scale: reduceMotion ? 1 : 1 + 0.015 * sin(t * 2.3))
    }
    public static func shortestAngle(from: Double, to: Double, fraction: Double) -> Double {
        guard from.isFinite, to.isFinite, fraction.isFinite else { return 0 }
        let delta = atan2(sin(to - from), cos(to - from))
        return from + delta * min(1, max(0, fraction))
    }
}
