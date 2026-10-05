import Foundation
import Network
import Darwin

struct OpenAIRequestPayload: Sendable {
    let model: String
    let systemPrompt: String
    let userPrompt: String
    let images: [OpenAIImageInput]
    let imageOrdering: OpenAIImageOrdering
    let maxTokens: Int
    let temperature: Double
    let topP: Double
    let seed: Int
    let stream: Bool
    let includeUsage: Bool
    let reasoningEffort: String

    var imageCount: Int {
        images.count
    }

    var imageData: Data? {
        images.first?.data
    }

    var imageExtension: String {
        images.first?.fileExtension ?? "jpg"
    }
}

struct OpenAIHandlerResult: Sendable {
    let text: String
    let promptTokens: Int
    let completionTokens: Int
    let finishReason: String
}

private struct OpenAINormalizedChatMessage: Sendable {
    let role: String
    let text: String
    let images: [OpenAIImageInput]
    let ordering: OpenAIImageOrdering
}

struct OpenAIHandlerHTTPError: LocalizedError, Sendable {
    let status: Int
    let code: String
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct OpenAIStreamSession: Sendable {
    let id: String
    let created: Int
    let model: String
    let includeUsage: Bool
}

private final class OpenAILazyStreamState: @unchecked Sendable {
    let session: OpenAIStreamSession
    var started = false

    init(session: OpenAIStreamSession) {
        self.session = session
    }
}

final class LocalOpenAIServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "已停止"
    @Published private(set) var port: UInt16 = 8080
    @Published private(set) var requestCount = 0
    @Published private(set) var lastError = ""

    let modelID = "bonsai-2-27b-local"
    private var advertisedContextWindow = 512
    private var advertisedMaxOutputTokens = 256

    func configureModelMetadata(
        contextWindow: Int,
        maxOutputTokens: Int
    ) {
        advertisedContextWindow = contextWindow
        advertisedMaxOutputTokens = maxOutputTokens
    }

    private let queue = DispatchQueue(
        label: "local.bonsai.openai.server"
    )
    private var listener: NWListener?
    private var listenerGeneration: UInt64 = 0
    private var handler: (
        @Sendable (
            OpenAIRequestPayload,
            (@Sendable (String) -> Void)?
        ) async throws -> OpenAIHandlerResult
    )?

    private static let keyDefaults = "BonsaiLocalAPIKey"

    var apiKey: String {
        if let existing = UserDefaults.standard.string(
            forKey: Self.keyDefaults
        ), !existing.isEmpty {
            return existing
        }

        let created = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
        UserDefaults.standard.set(
            created,
            forKey: Self.keyDefaults
        )
        return created
    }

    var baseURL: String {
        let ip = Self.localIPv4Address() ?? "iPad-IP"
        return "http://\(ip):\(port)/v1"
    }

    var canResumePreservedRuntime: Bool {
        handler != nil
    }

    func regenerateKey() {
        let created = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
        UserDefaults.standard.set(
            created,
            forKey: Self.keyDefaults
        )
        objectWillChange.send()
    }

    func start(
        port requestedPort: UInt16 = 8080,
        handler: @escaping @Sendable (
            OpenAIRequestPayload,
            (@Sendable (String) -> Void)?
        ) async throws -> OpenAIHandlerResult
    ) throws {
        stop()
        try installListener(
            port: requestedPort,
            handler: handler
        )
    }

    func stopListenerPreservingHandler() async {
        guard handler != nil else {
            stop()
            return
        }

        await cancelListenerForRestart()

        await MainActor.run {
            self.isRunning = false
            self.status = "已停止 · Runtime 常驻"
            self.lastError = ""
        }
    }

    func restartListenerPreservingHandler(
        port requestedPort: UInt16 = 8080
    ) async throws {
        let preservedHandler = handler
        guard let preservedHandler else {
            throw APIServerError.handlerUnavailable
        }

        await cancelListenerForRestart()
        try installListener(
            port: requestedPort,
            handler: preservedHandler
        )
    }

    func stop() {
        listenerGeneration &+= 1
        let stopGeneration = listenerGeneration
        let oldListener = listener
        listener = nil
        handler = nil
        oldListener?.cancel()

        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                self.listenerGeneration == stopGeneration
            else {
                return
            }

            self.isRunning = false
            self.status = "已停止"
        }
    }

    private func cancelListenerForRestart() async {
        guard let oldListener = listener else {
            await MainActor.run {
                self.isRunning = false
                self.status = "重启中"
                self.lastError = ""
            }
            return
        }

        listenerGeneration &+= 1
        listener = nil

        await MainActor.run {
            self.isRunning = false
            self.status = "重启中"
            self.lastError = ""
        }

        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in

            oldListener.stateUpdateHandler = { state in
                if case .cancelled = state {
                    continuation.resume()
                }
            }

            oldListener.cancel()
        }
    }

    private func installListener(
        port requestedPort: UInt16,
        handler: @escaping @Sendable (
            OpenAIRequestPayload,
            (@Sendable (String) -> Void)?
        ) async throws -> OpenAIHandlerResult
    ) throws {
        guard let nwPort = NWEndpoint.Port(
            rawValue: requestedPort
        ) else {
            throw APIServerError.invalidPort
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let newListener = try NWListener(
            using: parameters,
            on: nwPort
        )

        listenerGeneration &+= 1
        let generation = listenerGeneration

        self.port = requestedPort
        self.handler = handler
        self.listener = newListener

        newListener.stateUpdateHandler = {
            [weak self] state in
            guard let self else { return }

            DispatchQueue.main.async {
                guard
                    self.listenerGeneration == generation
                else {
                    return
                }

                switch state {
                case .ready:
                    self.isRunning = true
                    self.status = "运行中"
                    self.lastError = ""

                case .failed(let error):
                    self.isRunning = false
                    self.status = "启动失败"
                    self.lastError =
                        error.localizedDescription

                case .cancelled:
                    self.isRunning = false
                    self.status = "已停止"

                default:
                    break
                }
            }
        }

        newListener.newConnectionHandler = {
            [weak self] connection in
            self?.accept(connection)
        }

        newListener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(
            connection,
            buffer: Data()
        )
    }

    private func receive(
        _ connection: NWConnection,
        buffer: Data
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var next = buffer
            if let data {
                next.append(data)
            }

            if next.count > 25 * 1024 * 1024 {
                self.sendJSON(
                    connection,
                    status: 413,
                    object: Self.errorObject(
                        "request_too_large",
                        "Request body exceeds 25 MiB."
                    )
                )
                return
            }

            if let request = HTTPRequest.parseIfComplete(next) {
                self.process(
                    request,
                    connection: connection
                )
                return
            }

            if let error {
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                }
                connection.cancel()
                return
            }

            if isComplete {
                self.sendJSON(
                    connection,
                    status: 400,
                    object: Self.errorObject(
                        "bad_request",
                        "Incomplete HTTP request."
                    )
                )
                return
            }

            self.receive(
                connection,
                buffer: next
            )
        }
    }

    private func process(
        _ request: HTTPRequest,
        connection: NWConnection
    ) {
        if request.method == "OPTIONS" {
            sendRaw(
                connection,
                status: 204,
                contentType: "text/plain",
                body: Data()
            )
            return
        }

        if request.path == "/health" {
            sendJSON(
                connection,
                status: 200,
                object: [
                    "status": "ok",
                    "model": modelID,
                    "streaming": "chunked_sse",
                    "resource_governor": "v1",
                    "default_reasoning_effort": "none",
                    "context_window": advertisedContextWindow,
                    "max_output_tokens": advertisedMaxOutputTokens,
                    "capabilities": [
                        "chat": true,
                        "vision": true,
                        "streaming": true,
                        "tools": false,
                        "reasoning": false,
                        "responses_api": false,
                        "max_images_per_request": 3
                    ]
                ]
            )
            return
        }

        guard authorized(request) else {
            sendJSON(
                connection,
                status: 401,
                object: Self.errorObject(
                    "invalid_api_key",
                    "Use Authorization: Bearer <API key>."
                )
            )
            return
        }

        if request.method == "GET",
           request.path == "/v1/models" {
            sendJSON(
                connection,
                status: 200,
                object: [
                    "object": "list",
                    "data": [
                        Self.modelObject(
                            modelID,
                            contextWindow: advertisedContextWindow,
                            maxOutputTokens: advertisedMaxOutputTokens
                        )
                    ]
                ]
            )
            return
        }

        if request.method == "GET",
           request.path.hasPrefix("/v1/models/") {
            let requested = String(
                request.path.dropFirst("/v1/models/".count)
            )
            guard requested == modelID else {
                sendJSON(
                    connection,
                    status: 404,
                    object: Self.errorObject(
                        "model_not_found",
                        "The model '\(requested)' does not exist."
                    )
                )
                return
            }

            sendJSON(
                connection,
                status: 200,
                object: Self.modelObject(
                    modelID,
                    contextWindow: advertisedContextWindow,
                    maxOutputTokens: advertisedMaxOutputTokens
                )
            )
            return
        }

        guard
            request.method == "POST",
            request.path == "/v1/chat/completions"
        else {
            sendJSON(
                connection,
                status: 404,
                object: Self.errorObject(
                    "not_found",
                    "Supported endpoints: /v1/models and /v1/chat/completions."
                )
            )
            return
        }

        guard let handler else {
            sendJSON(
                connection,
                status: 503,
                object: Self.errorObject(
                    "server_not_ready",
                    "The inference handler is not ready."
                )
            )
            return
        }

        let payload: OpenAIRequestPayload
        do {
            payload = try Self.parseChatPayload(
                request.body,
                defaultModel: modelID
            )
        } catch let error as OpenAIMultimodalError {
            sendJSON(
                connection,
                status: error.status,
                object: Self.errorObject(
                    error.code,
                    error.localizedDescription
                )
            )
            return
        } catch {
            sendJSON(
                connection,
                status: 400,
                object: Self.errorObject(
                    "invalid_request_error",
                    error.localizedDescription
                )
            )
            return
        }

        guard payload.model == modelID else {
            sendJSON(
                connection,
                status: 404,
                object: Self.errorObject(
                    "model_not_found",
                    "The model '\(payload.model)' does not exist."
                )
            )
            return
        }

        DispatchQueue.main.async {
            self.requestCount += 1
            self.status = "正在处理 API 请求…"
        }

        if payload.stream {
            let state = OpenAILazyStreamState(
                session: makeStreamSession(
                    model: payload.model,
                    includeUsage: payload.includeUsage
                )
            )

            Task {
                do {
                    let result = try await handler(
                        payload,
                        { [weak self, weak connection] delta in
                            guard
                                let self,
                                let connection,
                                !delta.isEmpty
                            else {
                                return
                            }

                            self.queue.async {
                                if !state.started {
                                    self.beginStream(
                                        connection,
                                        session: state.session
                                    )
                                    state.started = true
                                }

                                self.sendStreamDelta(
                                    connection,
                                    session: state.session,
                                    delta: delta
                                )
                            }
                        }
                    )

                    self.queue.async {
                        if !state.started {
                            self.beginStream(
                                connection,
                                session: state.session
                            )
                            state.started = true
                        }

                        self.finishStream(
                            connection,
                            session: state.session,
                            result: result
                        )
                    }

                    DispatchQueue.main.async {
                        self.status = "运行中"
                        self.lastError = ""
                    }
                } catch {
                    self.queue.async {
                        let mapped = Self.mapHandlerError(error)

                        if state.started {
                            self.failStream(
                                connection,
                                code: mapped.code,
                                message: mapped.message
                            )
                        } else {
                            self.sendJSON(
                                connection,
                                status: mapped.status,
                                object: Self.errorObject(
                                    mapped.code,
                                    mapped.message
                                )
                            )
                        }
                    }

                    DispatchQueue.main.async {
                        self.status = "最近一次请求失败"
                        self.lastError = error.localizedDescription
                    }
                }
            }
            return
        }

        Task {
            do {
                let result = try await handler(payload, nil)
                self.sendCompletion(
                    connection,
                    model: payload.model,
                    result: result
                )
                DispatchQueue.main.async {
                    self.status = "运行中"
                    self.lastError = ""
                }
            } catch {
                let mapped = Self.mapHandlerError(error)
                self.sendJSON(
                    connection,
                    status: mapped.status,
                    object: Self.errorObject(
                        mapped.code,
                        mapped.message
                    )
                )

                DispatchQueue.main.async {
                    self.status = "最近一次请求失败"
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private func authorized(
        _ request: HTTPRequest
    ) -> Bool {
        guard let value = request.headers["authorization"] else {
            return false
        }

        let expected = "Bearer \(apiKey)"
        return value == expected
    }

    private func sendCompletion(
        _ connection: NWConnection,
        model: String,
        result: OpenAIHandlerResult
    ) {
        let completionID = "chatcmpl-\(UUID().uuidString)"
        let created = Int(Date().timeIntervalSince1970)

        sendJSON(
            connection,
            status: 200,
            object: [
                "id": completionID,
                "object": "chat.completion",
                "created": created,
                "model": model,
                "choices": [
                    [
                        "index": 0,
                        "message": [
                            "role": "assistant",
                            "content": result.text
                        ],
                        "finish_reason": result.finishReason
                    ]
                ],
                "usage": [
                    "prompt_tokens": result.promptTokens,
                    "completion_tokens": result.completionTokens,
                    "total_tokens":
                        result.promptTokens
                        + result.completionTokens
                ]
            ]
        )
    }

    private func makeStreamSession(
        model: String,
        includeUsage: Bool
    ) -> OpenAIStreamSession {
        OpenAIStreamSession(
            id: "chatcmpl-\(UUID().uuidString)",
            created: Int(Date().timeIntervalSince1970),
            model: model,
            includeUsage: includeUsage
        )
    }

    private func beginStream(
        _ connection: NWConnection,
        session: OpenAIStreamSession
    ) {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/event-stream; charset=utf-8",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "Transfer-Encoding: chunked",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Headers: Authorization, Content-Type",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "",
            ""
        ]
        connection.send(
            content: Data(headers.joined(separator: "\r\n").utf8),
            completion: .idempotent
        )
        sendStreamObject(connection, object: [
            "id": session.id,
            "object": "chat.completion.chunk",
            "created": session.created,
            "model": session.model,
            "choices": [[
                "index": 0,
                "delta": ["role": "assistant"],
                "finish_reason": NSNull()
            ]]
        ])
    }

    private func sendStreamDelta(
        _ connection: NWConnection,
        session: OpenAIStreamSession,
        delta: String
    ) {
        sendStreamObject(connection, object: [
            "id": session.id,
            "object": "chat.completion.chunk",
            "created": session.created,
            "model": session.model,
            "choices": [[
                "index": 0,
                "delta": ["content": delta],
                "finish_reason": NSNull()
            ]]
        ])
    }

    private func finishStream(
        _ connection: NWConnection,
        session: OpenAIStreamSession,
        result: OpenAIHandlerResult
    ) {
        guard let finalData = streamEventData(object: [
            "id": session.id,
            "object": "chat.completion.chunk",
            "created": session.created,
            "model": session.model,
            "choices": [[
                "index": 0,
                "delta": [:],
                "finish_reason": result.finishReason
            ]]
        ]) else {
            failStream(connection, message: "Unable to encode final stream chunk.")
            return
        }

        var body = finalData

        if session.includeUsage,
           let usageData = streamEventData(object: [
                "id": session.id,
                "object": "chat.completion.chunk",
                "created": session.created,
                "model": session.model,
                "choices": [],
                "usage": [
                    "prompt_tokens": result.promptTokens,
                    "completion_tokens": result.completionTokens,
                    "total_tokens":
                        result.promptTokens + result.completionTokens
                ]
           ]) {
            body.append(usageData)
        }

        body.append(Data("data: [DONE]\n\n".utf8))
        sendChunked(connection, data: body, final: true)
    }

    private func failStream(
        _ connection: NWConnection,
        code: String = "inference_error",
        message: String
    ) {
        let event = streamEventData(
            object: Self.errorObject(code, message)
        ) ?? Data("data: {\"error\":{\"message\":\"stream failure\"}}\n\n".utf8)
        var body = event
        body.append(Data("data: [DONE]\n\n".utf8))
        sendChunked(connection, data: body, final: true)
    }

    private func sendStreamObject(
        _ connection: NWConnection,
        object: Any
    ) {
        guard let event = streamEventData(object: object) else { return }
        sendChunked(connection, data: event, final: false)
    }

    private func streamEventData(object: Any) -> Data? {
        guard let json = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        var event = Data("data: ".utf8)
        event.append(json)
        event.append(Data("\n\n".utf8))
        return event
    }

    private func sendChunked(
        _ connection: NWConnection,
        data: Data,
        final: Bool
    ) {
        var framed = Data(String(data.count, radix: 16).utf8)
        framed.append(Data("\r\n".utf8))
        framed.append(data)
        framed.append(Data("\r\n".utf8))
        if final {
            framed.append(Data("0\r\n\r\n".utf8))
            connection.send(
                content: framed,
                completion: .contentProcessed { _ in connection.cancel() }
            )
        } else {
            connection.send(content: framed, completion: .idempotent)
        }
    }

    private func sendJSON(
        _ connection: NWConnection,
        status: Int,
        object: Any
    ) {
        let body: Data

        do {
            body = try JSONSerialization.data(
                withJSONObject: object,
                options: []
            )
        } catch {
            let fallback =
                "{\"error\":{\"message\":\"serialization failure\"}}"
            body = Data(fallback.utf8)
        }

        sendRaw(
            connection,
            status: status,
            contentType: "application/json; charset=utf-8",
            body: body
        )
    }

    private func sendRaw(
        _ connection: NWConnection,
        status: Int,
        contentType: String,
        body: Data,
        extraHeaders: [String: String] = [:]
    ) {
        let reason = Self.reasonPhrase(status)

        var headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Headers: Authorization, Content-Type",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS"
        ]

        for (key, value) in extraHeaders {
            headers.append("\(key): \(value)")
        }

        headers.append("")
        headers.append("")

        var response = Data(
            headers.joined(separator: "\r\n").utf8
        )
        response.append(body)

        connection.send(
            content: response,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    private static func parseChatPayload(
        _ body: Data,
        defaultModel: String
    ) throws -> OpenAIRequestPayload {
        guard
            let root = try JSONSerialization.jsonObject(
                with: body
            ) as? [String: Any]
        else {
            throw APIServerError.invalidJSON
        }

        guard
            let messages = root["messages"]
                as? [[String: Any]],
            !messages.isEmpty
        else {
            throw APIServerError.missingMessages
        }

        if let n = (root["n"] as? NSNumber)?.intValue, n != 1 {
            throw APIServerError.unsupportedCandidateCount
        }

        let tools = root["tools"] as? [Any] ?? []
        let rawToolChoice = root["tool_choice"]
        let toolChoiceName =
            (rawToolChoice as? String)?
                .lowercased()

        if let rawToolChoice,
           !(rawToolChoice is NSNull),
           toolChoiceName != "none" {
            throw APIServerError.unsupportedTools
        }

        // OpenAI tool_choice="none" explicitly disables tool calls. In that
        // case tool schemas are harmless compatibility metadata and can be
        // ignored. Any request that may actually invoke a tool remains rejected.
        if !tools.isEmpty && toolChoiceName != "none" {
            throw APIServerError.unsupportedTools
        }

        var normalizedMessages:
            [OpenAINormalizedChatMessage] = []
        var totalImages = 0
        var bindingSummaries: [OpenAIMessageBindingSummary] = []

        for message in messages {
            let role =
                (message["role"] as? String ?? "")
                    .lowercased()

            guard [
                "system",
                "developer",
                "user",
                "assistant"
            ].contains(role) else {
                throw APIServerError
                    .unsupportedMessageRole(role)
            }

            if let toolCalls = message["tool_calls"],
               !(toolCalls is NSNull) {
                throw APIServerError.unsupportedTools
            }

            let parsed =
                try OpenAIMultimodalNormalizer
                    .normalizeContent(
                        message["content"]
                    )

            bindingSummaries.append(
                OpenAIMessageBindingSummary(
                    role: role,
                    hasText: !parsed.text.isEmpty,
                    imageCount: parsed.imageCount
                )
            )

            if parsed.imageCount > 0 && role != "user" {
                throw OpenAIMultimodalError
                    .invalidContentPart
            }

            // RC1.25.2 supports visual follow-up chats. Historical user
            // turns may each carry images, but any one visual turn remains
            // bounded to the certified 1–3 image adapter.
            totalImages = max(
                totalImages,
                parsed.imageCount
            )
            if totalImages > 3 {
                throw OpenAIMultimodalError
                    .tooManyImages
            }

            normalizedMessages.append(
                OpenAINormalizedChatMessage(
                    role: role,
                    text: parsed.text,
                    images: parsed.images,
                    ordering: parsed.ordering
                )
            )
        }

        guard let currentUserIndex =
            normalizedMessages.lastIndex(
                where: {
                    $0.role == "user"
                    && !$0.text.isEmpty
                }
            )
        else {
            throw APIServerError.missingUserText
        }

        let imageMessageIndices =
            normalizedMessages.indices.filter {
                !normalizedMessages[$0].images.isEmpty
            }

        // Preserve the frozen Build 60 same-turn validator whenever the
        // request already matches it exactly. RC1.25.2 additionally accepts
        // ordinary follow-up chats where the most recent image is in a prior
        // user turn and the latest user turn is text-only.
        if imageMessageIndices.allSatisfy({
            $0 == currentUserIndex
        }) {
            _ = try OpenAIMultimodalMessageBindingValidator
                .validate(bindingSummaries)
        }

        let visualUserIndex =
            normalizedMessages.indices
                .reversed()
                .first(
                    where: {
                        $0 <= currentUserIndex
                        && normalizedMessages[$0].role
                            == "user"
                        && !normalizedMessages[$0]
                            .images.isEmpty
                    }
                )

        let currentUser =
            normalizedMessages[currentUserIndex]
        let visualUser =
            visualUserIndex.map {
                normalizedMessages[$0]
            }

        var instructionParts: [String] = []
        var historyParts: [String] = []

        for (index, message) in
            normalizedMessages.enumerated() {
            switch message.role {
            case "system", "developer":
                if !message.text.isEmpty {
                    instructionParts.append(message.text)
                }

            case "user":
                if index < currentUserIndex,
                   !message.text.isEmpty {
                    var entry =
                        "User: " + message.text

                    if index == visualUserIndex {
                        entry +=
                            "\n[The image(s) from this turn are attached "
                            + "as the active visual context for the "
                            + "current follow-up.]"
                    }

                    historyParts.append(entry)
                }

            case "assistant":
                if index < currentUserIndex,
                   !message.text.isEmpty {
                    historyParts.append(
                        "Assistant: " + message.text
                    )
                }

            default:
                break
            }
        }

        var systemPrompt =
            instructionParts.isEmpty
                ? "You are a helpful assistant."
                : instructionParts.joined(
                    separator: "\n\n"
                )

        if !historyParts.isEmpty {
            systemPrompt +=
                "\n\nConversation history:\n"
                + historyParts.joined(
                    separator: "\n"
                )
        }

        let userPrompt = currentUser.text
        let images =
            visualUser?.images ?? []
        let imageOrdering =
            visualUser?.ordering ?? .none

        let requested =
            (root["max_completion_tokens"] as? NSNumber)?.intValue
            ?? (root["max_tokens"] as? NSNumber)?.intValue
            ?? (root["max_output_tokens"] as? NSNumber)?.intValue
            ?? 256

        let maxTokens = min(
            2048,
            max(1, requested)
        )

        let temperature =
            (root["temperature"] as? NSNumber)?
                .doubleValue
            ?? 0.7
        guard temperature >= 0,
              temperature <= 5
        else {
            throw APIServerError.invalidParameter(
                "temperature must be in 0...5."
            )
        }

        let topP =
            (root["top_p"] as? NSNumber)?
                .doubleValue
            ?? 0.8
        guard topP > 0,
              topP <= 1
        else {
            throw APIServerError.invalidParameter(
                "top_p must be in (0, 1]."
            )
        }

        let seed =
            (root["seed"] as? NSNumber)?
                .intValue
            ?? 1234
        guard seed >= 0 else {
            throw APIServerError.invalidParameter(
                "seed must be >= 0."
            )
        }

        let streamOptions =
            root["stream_options"] as? [String: Any]
        let includeUsage =
            streamOptions?["include_usage"] as? Bool ?? false

        let reasoningEffort = (
            root["reasoning_effort"] as? String
            ?? "none"
        ).lowercased()

        guard [
            "none",
            "minimal",
            "low",
            "medium",
            "high",
            "xhigh"
        ].contains(reasoningEffort) else {
            throw APIServerError.unsupportedReasoningEffort
        }

        return OpenAIRequestPayload(
            model: root["model"] as? String ?? defaultModel,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            images: images,
            imageOrdering: imageOrdering,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            seed: seed,
            stream: root["stream"] as? Bool ?? false,
            includeUsage: includeUsage,
            reasoningEffort: reasoningEffort
        )
    }

    private static func mapHandlerError(
        _ error: Error
    ) -> OpenAIHandlerHTTPError {
        if let mapped = error as? OpenAIHandlerHTTPError {
            return mapped
        }

        return OpenAIHandlerHTTPError(
            status: 500,
            code: "inference_error",
            message: error.localizedDescription
        )
    }

    private static func modelObject(
        _ modelID: String,
        contextWindow: Int,
        maxOutputTokens: Int
    ) -> [String: Any] {
        [
            "id": modelID,
            "object": "model",
            "created": 0,
            "owned_by": "local",
            // Common OpenAI-compatible/OpenRouter-style discovery metadata.
            // Chatbox consumes context_length and architecture.input_modalities.
            "context_length": contextWindow,
            "max_output_tokens": maxOutputTokens,
            "architecture": [
                "input_modalities": ["text", "image"],
                "output_modalities": ["text"]
            ],
            "supported_parameters": [
                "max_tokens",
                "max_completion_tokens",
                "max_output_tokens",
                "temperature",
                "top_p",
                "seed",
                "stream",
                "stream_options"
            ],
            "capabilities": [
                "chat": true,
                "vision": true,
                "streaming": true,
                "tools": false,
                "reasoning": false,
                "responses_api": false,
                "max_images_per_request": 3
            ]
        ]
    }

    private static func errorObject(
        _ code: String,
        _ message: String
    ) -> [String: Any] {
        [
            "error": [
                "message": message,
                "type": "invalid_request_error",
                "code": code
            ]
        ]
    }

    private static func reasonPhrase(
        _ status: Int
    ) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 422: return "Unprocessable Entity"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "OK"
        }
    }

    private static func localIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0,
              let first = ifaddr else {
            return nil
        }

        defer {
            freeifaddrs(ifaddr)
        }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer {
            let interface = current.pointee

            if let addr = interface.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(
                    cString: interface.ifa_name
                )

                if name == "en0" {
                    var host = [CChar](
                        repeating: 0,
                        count: Int(NI_MAXHOST)
                    )

                    let length = socklen_t(
                        addr.pointee.sa_len
                    )

                    let result = getnameinfo(
                        addr,
                        length,
                        &host,
                        socklen_t(host.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )

                    if result == 0 {
                        address = String(cString: host)
                        break
                    }
                }
            }

            pointer = interface.ifa_next
        }

        return address
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parseIfComplete(
        _ data: Data
    ) -> HTTPRequest? {
        let delimiter = Data("\r\n\r\n".utf8)

        guard let range = data.range(of: delimiter) else {
            return nil
        }

        let headerData = data[
            data.startIndex..<range.lowerBound
        ]

        guard
            let headerText = String(
                data: headerData,
                encoding: .utf8
            )
        else {
            return nil
        }

        let lines = headerText.components(
            separatedBy: "\r\n"
        )

        guard
            let requestLine = lines.first
        else {
            return nil
        }

        let parts = requestLine.split(separator: " ")

        guard parts.count >= 2 else {
            return nil
        }

        let method = String(parts[0]).uppercased()
        let pathWithQuery = String(parts[1])
        let path = pathWithQuery
            .split(separator: "?", maxSplits: 1)
            .first
            .map(String.init)
            ?? pathWithQuery

        var headers: [String: String] = [:]

        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else {
                continue
            }

            let key = line[..<colon]
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()
            let value = line[
                line.index(after: colon)...
            ]
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            headers[key] = value
        }

        let contentLength = Int(
            headers["content-length"] ?? "0"
        ) ?? 0

        let bodyStart = range.upperBound
        let available = data.count - bodyStart

        guard available >= contentLength else {
            return nil
        }

        let body = data.subdata(
            in: bodyStart..<(bodyStart + contentLength)
        )

        return HTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: body
        )
    }
}

enum APIServerError: LocalizedError {
    case invalidPort
    case handlerUnavailable
    case invalidJSON
    case missingMessages
    case missingUserText
    case imageMustBeDataURL
    case invalidImageDataURL
    case unsupportedCandidateCount
    case unsupportedTools
    case unsupportedMessageRole(String)
    case invalidParameter(String)
    case unsupportedReasoningEffort

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "无效的 API 端口。"
        case .handlerUnavailable:
            return "API handler 尚未初始化，无法仅重启 listener。"
        case .invalidJSON:
            return "请求体不是有效 JSON。"
        case .missingMessages:
            return "OpenAI 请求缺少 messages。"
        case .missingUserText:
            return "请求中没有可用的 user 文本。"
        case .imageMustBeDataURL:
            return "局域网 API 的图片当前请使用 data:image/...;base64,... 格式。"
        case .invalidImageDataURL:
            return "图片 data URL 无效。"
        case .unsupportedCandidateCount:
            return "当前本地 API 仅支持 n=1。"
        case .unsupportedTools:
            return "当前本地 API 尚不支持实际 tool calls；tool_choice=none 可作为兼容模式使用。"
        case .unsupportedMessageRole(let role):
            return "当前本地 API 不支持消息角色：\(role)。支持 system、developer、user、assistant。"
        case .invalidParameter(let message):
            return message
        case .unsupportedReasoningEffort:
            return "reasoning_effort 仅支持 none、minimal、low、medium、high、xhigh。"
        }
    }
}
