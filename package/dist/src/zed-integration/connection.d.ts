/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import { type Result } from './schema.js';
import type { WritableStream, ReadableStream } from 'node:stream/web';
export declare class RequestError extends Error {
    code: number;
    data?: {
        details?: string;
    };
    constructor(code: number, message: string, details?: string);
    static parseError(details?: string): RequestError;
    static invalidRequest(details?: string): RequestError;
    static methodNotFound(details?: string): RequestError;
    static invalidParams(details?: string): RequestError;
    static internalError(details?: string): RequestError;
    static authRequired(details?: string): RequestError;
    toResult<T>(): Result<T>;
}
export type MethodHandler = (method: string, params: unknown) => Promise<unknown>;
export declare class Connection {
    #private;
    constructor(handler: MethodHandler, peerInput: WritableStream<Uint8Array>, peerOutput: ReadableStream<Uint8Array>);
    sendRequest<Req, Resp>(method: string, params?: Req): Promise<Resp>;
    sendNotification<N>(method: string, params?: N): Promise<void>;
}
