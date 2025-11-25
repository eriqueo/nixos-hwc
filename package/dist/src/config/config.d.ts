/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import { Config } from '@google/gemini-cli-core';
import type { Settings } from './settings.js';
export interface CliArgs {
    query: string | undefined;
    model: string | undefined;
    sandbox: boolean | string | undefined;
    debug: boolean | undefined;
    prompt: string | undefined;
    promptInteractive: string | undefined;
    yolo: boolean | undefined;
    approvalMode: string | undefined;
    allowedMcpServerNames: string[] | undefined;
    allowedTools: string[] | undefined;
    experimentalAcp: boolean | undefined;
    extensions: string[] | undefined;
    listExtensions: boolean | undefined;
    resume: string | 'latest' | undefined;
    listSessions: boolean | undefined;
    deleteSession: string | undefined;
    includeDirectories: string[] | undefined;
    screenReader: boolean | undefined;
    useSmartEdit: boolean | undefined;
    useWriteTodos: boolean | undefined;
    outputFormat: string | undefined;
    fakeResponses: string | undefined;
    recordResponses: string | undefined;
}
export declare function parseArguments(settings: Settings): Promise<CliArgs>;
export declare function isDebugMode(argv: CliArgs): boolean;
export declare function loadCliConfig(settings: Settings, sessionId: string, argv: CliArgs, cwd?: string): Promise<Config>;
