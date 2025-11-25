/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
/* ACP defines a schema for a simple (experimental) JSON-RPC protocol that allows GUI applications to interact with agents. */
import * as schema from './schema.js';
export * from './schema.js';
import { Connection, RequestError } from './connection.js';
export { RequestError };
export class AgentSideConnection {
    #connection;
    constructor(toAgent, input, output) {
        const agent = toAgent(this);
        const handler = async (method, params) => {
            switch (method) {
                case schema.AGENT_METHODS.initialize: {
                    const validatedParams = schema.initializeRequestSchema.parse(params);
                    return agent.initialize(validatedParams);
                }
                case schema.AGENT_METHODS.session_new: {
                    const validatedParams = schema.newSessionRequestSchema.parse(params);
                    return agent.newSession(validatedParams);
                }
                case schema.AGENT_METHODS.session_load: {
                    if (!agent.loadSession) {
                        throw RequestError.methodNotFound();
                    }
                    const validatedParams = schema.loadSessionRequestSchema.parse(params);
                    return agent.loadSession(validatedParams);
                }
                case schema.AGENT_METHODS.authenticate: {
                    const validatedParams = schema.authenticateRequestSchema.parse(params);
                    return agent.authenticate(validatedParams);
                }
                case schema.AGENT_METHODS.session_prompt: {
                    const validatedParams = schema.promptRequestSchema.parse(params);
                    return agent.prompt(validatedParams);
                }
                case schema.AGENT_METHODS.session_cancel: {
                    const validatedParams = schema.cancelNotificationSchema.parse(params);
                    return agent.cancel(validatedParams);
                }
                default:
                    throw RequestError.methodNotFound(method);
            }
        };
        this.#connection = new Connection(handler, input, output);
    }
    /**
     * Streams new content to the client including text, tool calls, etc.
     */
    async sessionUpdate(params) {
        return await this.#connection.sendNotification(schema.CLIENT_METHODS.session_update, params);
    }
    /**
     * Request permission before running a tool
     *
     * The agent specifies a series of permission options with different granularity,
     * and the client returns the chosen one.
     */
    async requestPermission(params) {
        return await this.#connection.sendRequest(schema.CLIENT_METHODS.session_request_permission, params);
    }
    async readTextFile(params) {
        return await this.#connection.sendRequest(schema.CLIENT_METHODS.fs_read_text_file, params);
    }
    async writeTextFile(params) {
        return await this.#connection.sendRequest(schema.CLIENT_METHODS.fs_write_text_file, params);
    }
}
//# sourceMappingURL=acp.js.map