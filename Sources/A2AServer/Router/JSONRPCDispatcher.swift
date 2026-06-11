// JSONRPCDispatcher.swift
// A2AServer
//
// Hummingbird adapter for the JSON-RPC dispatcher. All A2A operations are
// multiplexed through one POST route (default `/`). The protocol logic
// lives in the framework-neutral `dispatchJSONRPC(body:headers:)`
// (JSONRPCCore.swift); this file only maps its outcome onto a Hummingbird
// `Response`.

import Foundation
import Hummingbird
import NIOCore
import A2AClient

extension A2ADispatcher {
    func jsonrpcDispatch<Context: RequestContext>(
        req: Request,
        ctx: Context
    ) async throws -> Response {
        let buffer = try await req.body.collect(upTo: 10 * 1024 * 1024)
        let outcome = await dispatchJSONRPC(
            body: Data(buffer: buffer),
            headers: req.headerMap()
        )

        switch outcome {
        case .json(let data):
            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            return Response(
                status: .ok,  // JSON-RPC protocol errors still use HTTP 200
                headers: headers,
                body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
            )

        case .unauthenticated(let error):
            // Transport-level auth failure: HTTP 401/403 with an AIP-193
            // body, same shape as the REST binding.
            return try errorResponse(error)

        case .stream(let stream, let rpcID):
            return sseResponse(stream: stream, wrappedInJSONRPC: true, rpcID: rpcID)
        }
    }
}
