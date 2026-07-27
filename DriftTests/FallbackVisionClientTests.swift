import Foundation
import Testing
import DriftCore
@testable import Drift

// MARK: - Fakes

private actor CountingClient: CloudVisionClient {
    let result: Result<PhotoLogResponse, CloudVisionError>
    private(set) var callsMade = 0

    init(_ result: Result<PhotoLogResponse, CloudVisionError>) {
        self.result = result
    }

    func analyze(image: Data, prompt: String) async throws -> PhotoLogResponse {
        callsMade += 1
        switch result {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}

private func slot(
    _ provider: CloudVisionProvider,
    _ result: Result<PhotoLogResponse, CloudVisionError>
) -> (FallbackVisionClient.Slot, CountingClient) {
    let fake = CountingClient(result)
    return (.init(provider: provider, client: fake), fake)
}

// MARK: - Tests

@Test func fallbackSingleSlotSucceeds() async throws {
    let (s, _) = slot(.gemini, .success(.stub))
    let fb = FallbackVisionClient(chain: [s])
    let result = try await fb.analyze(image: Data(), prompt: "")
    #expect(result.items.count == PhotoLogResponse.stub.items.count)
}

@Test func fallbackRateLimitedPrimaryTriesSecondary() async throws {
    let (s1, c1) = slot(.anthropic, .failure(.rateLimited))
    let (s2, c2) = slot(.openai, .success(.stub))
    let fb = FallbackVisionClient(chain: [s1, s2])
    _ = try await fb.analyze(image: Data(), prompt: "")
    #expect(await c1.callsMade == 1)
    #expect(await c2.callsMade == 1)
}

@Test func fallbackTimeoutPrimaryTriesSecondary() async throws {
    let (s1, _) = slot(.anthropic, .failure(.timeout))
    let (s2, c2) = slot(.gemini, .success(.stub))
    let fb = FallbackVisionClient(chain: [s1, s2])
    _ = try await fb.analyze(image: Data(), prompt: "")
    #expect(await c2.callsMade == 1)
}

@Test func fallbackTransportErrorTriesSecondary() async throws {
    let (s1, _) = slot(.anthropic, .failure(.transport("err")))
    let (s2, c2) = slot(.openai, .success(.stub))
    let fb = FallbackVisionClient(chain: [s1, s2])
    _ = try await fb.analyze(image: Data(), prompt: "")
    #expect(await c2.callsMade == 1)
}

@Test func fallback5xxProviderErrorTriesSecondary() async throws {
    let (s1, _) = slot(.anthropic, .failure(.providerError(status: 503, message: "overloaded")))
    let (s2, c2) = slot(.openai, .success(.stub))
    let fb = FallbackVisionClient(chain: [s1, s2])
    _ = try await fb.analyze(image: Data(), prompt: "")
    #expect(await c2.callsMade == 1)
}

@Test func fallback5xxBadResponseTriesSecondary() async throws {
    let (s1, _) = slot(.anthropic, .failure(.badResponse(502)))
    let (s2, c2) = slot(.gemini, .success(.stub))
    let fb = FallbackVisionClient(chain: [s1, s2])
    _ = try await fb.analyze(image: Data(), prompt: "")
    #expect(await c2.callsMade == 1)
}

@Test func fallbackUnauthorizedFastFails() async throws {
    let (s1, _) = slot(.anthropic, .failure(.unauthorized))
    let (s2, c2) = slot(.openai, .success(.stub))
    let fb = FallbackVisionClient(chain: [s1, s2])
    do {
        _ = try await fb.analyze(image: Data(), prompt: "")
        Issue.record("Expected throw")
    } catch CloudVisionError.unauthorized {
        #expect(await c2.callsMade == 0)
    }
}

@Test func fallbackMalformedPayloadFastFails() async throws {
    let (s1, _) = slot(.gemini, .failure(.malformedPayload))
    let (s2, c2) = slot(.openai, .success(.stub))
    let fb = FallbackVisionClient(chain: [s1, s2])
    do {
        _ = try await fb.analyze(image: Data(), prompt: "")
        Issue.record("Expected throw")
    } catch CloudVisionError.malformedPayload {
        #expect(await c2.callsMade == 0)
    }
}

@Test func fallbackAllTransientExhaustedThrowsLast() async throws {
    let (s1, _) = slot(.anthropic, .failure(.rateLimited))
    let (s2, _) = slot(.openai, .failure(.timeout))
    let (s3, _) = slot(.gemini, .failure(.rateLimited))
    let fb = FallbackVisionClient(chain: [s1, s2, s3])
    do {
        _ = try await fb.analyze(image: Data(), prompt: "")
        Issue.record("Expected throw")
    } catch CloudVisionError.rateLimited {
        // last error in chain is rateLimited from gemini — correct
    }
}

@Test func fallbackFirstPermanentStopsChain() async throws {
    let (s1, _) = slot(.anthropic, .failure(.unauthorized))
    let (s2, c2) = slot(.openai, .failure(.rateLimited))
    let (s3, c3) = slot(.gemini, .success(.stub))
    let fb = FallbackVisionClient(chain: [s1, s2, s3])
    do {
        _ = try await fb.analyze(image: Data(), prompt: "")
        Issue.record("Expected throw")
    } catch CloudVisionError.unauthorized {
        #expect(await c2.callsMade == 0)
        #expect(await c3.callsMade == 0)
    }
}

@Test func fallbackLastProviderReflectsSuccessfulSlot() async throws {
    let (s1, _) = slot(.anthropic, .failure(.rateLimited))
    let (s2, _) = slot(.openai, .success(.stub))
    let fb = FallbackVisionClient(chain: [s1, s2])
    _ = try await fb.analyze(image: Data(), prompt: "")
    #expect(await fb.lastProvider == .openai)
}

@Test func fallbackLastProviderIsFirstWhenNoFallbackNeeded() async throws {
    let (s1, _) = slot(.gemini, .success(.stub))
    let fb = FallbackVisionClient(chain: [s1])
    _ = try await fb.analyze(image: Data(), prompt: "")
    #expect(await fb.lastProvider == .gemini)
}

@Test func fallbackEmptyChainThrowsOffline() async throws {
    let fb = FallbackVisionClient(chain: [])
    do {
        _ = try await fb.analyze(image: Data(), prompt: "")
        Issue.record("Expected throw")
    } catch CloudVisionError.offline {
        // correct
    }
}
