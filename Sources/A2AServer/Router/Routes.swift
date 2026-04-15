// Routes.swift
// A2AServer
//
// Hummingbird route registration. Mounts both REST and JSON-RPC routes
// on a single router.
//
// A2A uses AIP-136 custom verbs (`/tasks/{id}:cancel`, `/tasks/{id}:subscribe`)
// which collide with Hummingbird 2's parameterized-path syntax. We work
// around this by routing all `POST /tasks/:idWithVerb` requests through a
// single handler that parses the verb suffix out of the captured segment.

import Foundation
import Hummingbird
import A2ACore

extension A2ADispatcher {
    /// Register all A2A routes on a Hummingbird router.
    public func registerRoutes<Context: RequestContext>(
        on router: Router<Context>,
        rpcPath: String = "/",
        restPrefix: String = ""
    ) {
        let p = restPrefix

        // Discovery — spec §8.2
        router.get("/.well-known/agent-card.json") { [self] req, ctx in
            try await self.respondAgentCard(req: req, ctx: ctx)
        }
        router.get("/.well-known/agent.json") { [self] req, ctx in
            try await self.respondAgentCard(req: req, ctx: ctx)
        }

        // MARK: - Literal verb paths (single segment at root)

        router.post("\(p)/message:send") { [self] req, ctx in
            try await self.restSendMessage(req: req, ctx: ctx)
        }
        router.post("\(p)/message:stream") { [self] req, ctx in
            try await self.restSendStreamingMessage(req: req, ctx: ctx, rpcWrapped: false)
        }

        // MARK: - Tasks

        // GET /tasks — list
        router.get("\(p)/tasks") { [self] req, ctx in
            try await self.restListTasks(req: req, ctx: ctx)
        }

        // GET /tasks/{id} — get
        router.get("\(p)/tasks/:id") { [self] req, ctx in
            try await self.restGetTask(req: req, ctx: ctx)
        }

        // POST /tasks/{id}:cancel or /tasks/{id}:subscribe — parse the verb
        // out of the captured segment and dispatch. Reusing the `id` param
        // name keeps Hummingbird's trie router happy (it complains when
        // different param names land at the same path position).
        router.post("\(p)/tasks/:id") { [self] req, ctx in
            let raw = ctx.parameters.get("id") ?? ""
            guard let colonIdx = raw.firstIndex(of: ":") else {
                return try self.errorResponse(.invalidRequest(
                    message: "Expected /tasks/{id}:cancel or /tasks/{id}:subscribe"
                ))
            }
            let id = String(raw[..<colonIdx])
            let verb = String(raw[raw.index(after: colonIdx)...])
            switch verb {
            case "cancel":
                return try await self.restCancelTaskByID(id: id, req: req, ctx: ctx)
            case "subscribe":
                return try await self.restSubscribeToTaskByID(id: id, req: req, ctx: ctx)
            default:
                return try self.errorResponse(.invalidRequest(
                    message: "Unknown verb \(verb) — expected :cancel or :subscribe"
                ))
            }
        }

        // MARK: - Push notifications (nested under /tasks/{id}/...)

        router.post("\(p)/tasks/:id/pushNotificationConfigs") { [self] req, ctx in
            try await self.restCreatePushNotificationConfig(req: req, ctx: ctx)
        }
        router.get("\(p)/tasks/:id/pushNotificationConfigs") { [self] req, ctx in
            try await self.restListPushNotificationConfigs(req: req, ctx: ctx)
        }
        router.get("\(p)/tasks/:id/pushNotificationConfigs/:configId") { [self] req, ctx in
            try await self.restGetPushNotificationConfig(req: req, ctx: ctx)
        }
        router.delete("\(p)/tasks/:id/pushNotificationConfigs/:configId") { [self] req, ctx in
            try await self.restDeletePushNotificationConfig(req: req, ctx: ctx)
        }

        // MARK: - Extended agent card

        router.get("\(p)/extendedAgentCard") { [self] req, ctx in
            try await self.restGetExtendedAgentCard(req: req, ctx: ctx)
        }

        // MARK: - JSON-RPC

        let rpc = rpcPath.isEmpty ? "/" : rpcPath
        router.post(RouterPath(stringLiteral: rpc)) { [self] req, ctx in
            try await self.jsonrpcDispatch(req: req, ctx: ctx)
        }
    }
}
