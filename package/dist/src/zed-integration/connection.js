/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import { z } from 'zod';
import { coreEvents } from '@google/gemini-cli-core';
import {} from './schema.js';
export class RequestError extends Error {
    code;
    data;
    constructor(code, message, details) {
        super(message);
        this.code = code;
        this.name = 'RequestError';
        if (details) {
            this.data = { details };
        }
    }
    static parseError(details) {
        return new RequestError(-32700, 'Parse error', details);
    }
    static invalidRequest(details) {
        return new RequestError(-32600, 'Invalid request', details);
    }
    static methodNotFound(details) {
        return new RequestError(-32601, 'Method not found', details);
    }
    static invalidParams(details) {
        return new RequestError(-32602, 'Invalid params', details);
    }
    static internalError(details) {
        return new RequestError(-32603, 'Internal error', details);
    }
    static authRequired(details) {
        return new RequestError(-32000, 'Authentication required', details);
    }
    toResult() {
        return {
            error: {
                code: this.code,
                message: this.message,
                data: this.data,
            },
        };
    }
}
export class Connection {
    #pendingResponses = new Map();
    #nextRequestId = 0;
    #handler;
    #peerInput;
    #writeQueue = Promise.resolve();
    #textEncoder;
    constructor(handler, peerInput, peerOutput) {
        this.#handler = handler;
        this.#peerInput = peerInput;
        this.#textEncoder = new TextEncoder();
        this.#receive(peerOutput);
    }
    async #receive(output) {
        let content = '';
        const decoder = new TextDecoder();
        for await (const chunk of output) {
            content += decoder.decode(chunk, { stream: true });
            const lines = content.split('\n');
            content = lines.pop() || '';
            for (const line of lines) {
                const trimmedLine = line.trim();
                if (trimmedLine) {
                    const message = JSON.parse(trimmedLine);
                    this.#processMessage(message);
                }
            }
        }
    }
    async #processMessage(message) {
        if ('method' in message && 'id' in message) {
            // It's a request
            const response = await this.#tryCallHandler(message.method, message.params);
            await this.#sendMessage({
                jsonrpc: '2.0',
                id: message.id,
                ...response,
            });
        }
        else if ('method' in message) {
            // It's a notification
            await this.#tryCallHandler(message.method, message.params);
        }
        else if ('id' in message) {
            // It's a response
            this.#handleResponse(message);
        }
    }
    async #tryCallHandler(method, params) {
        try {
            const result = await this.#handler(method, params);
            return { result: result ?? null };
        }
        catch (error) {
            if (error instanceof RequestError) {
                return error.toResult();
            }
            if (error instanceof z.ZodError) {
                return RequestError.invalidParams(JSON.stringify(error.format(), undefined, 2)).toResult();
            }
            let details;
            if (error instanceof Error) {
                details = error.message;
            }
            else if (typeof error === 'object' &&
                error != null &&
                'message' in error &&
                typeof error.message === 'string') {
                details = error.message;
            }
            return RequestError.internalError(details).toResult();
        }
    }
    #handleResponse(response) {
        const pendingResponse = this.#pendingResponses.get(response.id);
        if (pendingResponse) {
            if ('result' in response) {
                pendingResponse.resolve(response.result);
            }
            else if ('error' in response) {
                pendingResponse.reject(response.error);
            }
            this.#pendingResponses.delete(response.id);
        }
    }
    async sendRequest(method, params) {
        const id = this.#nextRequestId++;
        const responsePromise = new Promise((resolve, reject) => {
            this.#pendingResponses.set(id, { resolve, reject });
        });
        await this.#sendMessage({ jsonrpc: '2.0', id, method, params });
        return responsePromise;
    }
    async sendNotification(method, params) {
        await this.#sendMessage({ jsonrpc: '2.0', method, params });
    }
    async #sendMessage(json) {
        const content = JSON.stringify(json) + '\n';
        this.#writeQueue = this.#writeQueue
            .then(async () => {
            const writer = this.#peerInput.getWriter();
            try {
                await writer.write(this.#textEncoder.encode(content));
            }
            finally {
                writer.releaseLock();
            }
        })
            .catch((error) => {
            // Continue processing writes on error
            coreEvents.emitFeedback('error', 'ACP write error.', error);
        });
        return this.#writeQueue;
    }
}
//# sourceMappingURL=connection.js.map