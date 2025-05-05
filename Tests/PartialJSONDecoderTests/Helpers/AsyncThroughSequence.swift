// A simple async sequence for testing
actor AsyncThroughSequence<Element: Sendable>: AsyncSequence {
    typealias AsyncIterator = Iterator

    private var values: [Element] = []
    private var continuations: [CheckedContinuation<Element?, Never>] = []
    private var isFinished = false

    func send(_ value: Element) {
        values.append(value)
        if let continuation = continuations.first {
            continuations.removeFirst()
            continuation.resume(returning: value)
        }
    }

    func finish() {
        isFinished = true
        for continuation in continuations {
            continuation.resume(returning: nil)
        }
        continuations.removeAll()
    }

    nonisolated func makeAsyncIterator() -> Iterator {
        return Iterator(sequence: self)
    }

    struct Iterator: AsyncIteratorProtocol {
        let sequence: AsyncThroughSequence<Element>

        func next() async -> Element? {
            return await sequence.next()
        }
    }

    private func next() async -> Element? {
        if !values.isEmpty {
            return values.removeFirst()
        }

        if isFinished {
            return nil
        }

        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}
