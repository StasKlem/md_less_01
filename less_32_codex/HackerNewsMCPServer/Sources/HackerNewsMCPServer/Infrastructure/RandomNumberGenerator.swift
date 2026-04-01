import Foundation

protocol RandomNumberGenerating: Sendable {
    func int(in range: Range<Int>) -> Int
}

struct SystemRandomNumberGeneratorAdapter: RandomNumberGenerating {
    func int(in range: Range<Int>) -> Int {
        Int.random(in: range)
    }
}
