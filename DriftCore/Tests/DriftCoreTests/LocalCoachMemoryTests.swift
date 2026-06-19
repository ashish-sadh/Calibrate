import Foundation
@testable import DriftCore
import Testing

private func tempStore() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("mem_\(UUID().uuidString).json")
}

@Test func memoryRecallReturnsRelevantFact() async {
    let url = tempStore(); defer { try? FileManager.default.removeItem(at: url) }
    let mem = LocalCoachMemory(storeURL: url)
    await mem.remember(MemoryItem(text: "User wants to hit 90g protein daily", kind: .goal))
    await mem.remember(MemoryItem(text: "User is vegetarian", kind: .preference))
    await mem.remember(MemoryItem(text: "User has a knee injury, avoid heavy squats", kind: .fact))
    let hits = await mem.recall(query: "what is my protein goal", limit: 2)
    #expect(hits.contains { $0.text.contains("protein") })
}

@Test func memoryDedupesIdenticalTextCaseInsensitive() async {
    let url = tempStore(); defer { try? FileManager.default.removeItem(at: url) }
    let mem = LocalCoachMemory(storeURL: url)
    await mem.remember(MemoryItem(text: "User is vegetarian", kind: .preference))
    await mem.remember(MemoryItem(text: "user is VEGETARIAN", kind: .preference))
    let all = await mem.all()
    #expect(all.filter { $0.text.lowercased() == "user is vegetarian" }.count == 1)
}

@Test func memoryCapsAtMaxItems() async {
    let url = tempStore(); defer { try? FileManager.default.removeItem(at: url) }
    let mem = LocalCoachMemory(storeURL: url, maxItems: 3)
    for i in 0..<5 { await mem.remember(MemoryItem(text: "durable fact number \(i)", kind: .fact)) }
    #expect(await mem.all().count == 3)
}

@Test func memoryPersistsAcrossInstances() async {
    let url = tempStore(); defer { try? FileManager.default.removeItem(at: url) }
    let mem1 = LocalCoachMemory(storeURL: url)
    await mem1.remember(MemoryItem(text: "User wants to cut sugar this month", kind: .goal))
    let mem2 = LocalCoachMemory(storeURL: url)   // fresh instance, same store file
    #expect(await mem2.all().contains { $0.text.contains("cut sugar") })
}

@Test func cosineMathSanity() {
    #expect(LocalCoachMemory.cosine([1, 0, 0], [1, 0, 0]) == 1.0)
    #expect(LocalCoachMemory.cosine([1, 0], [0, 1]) == 0.0)
    #expect(LocalCoachMemory.cosine([], []) == 0)
    #expect(LocalCoachMemory.cosine([1, 2, 3], [2, 4, 6]) > 0.99)   // parallel → ~1
}
