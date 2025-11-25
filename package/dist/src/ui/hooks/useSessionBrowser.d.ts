/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import type { HistoryItemWithoutId } from '../types.js';
import type { ConversationRecord } from '@google/gemini-cli-core';
import type { Part } from '@google/genai';
/**
 * Converts session/conversation data into UI history and Gemini client history formats.
 */
export declare function convertSessionToHistoryFormats(messages: ConversationRecord['messages']): {
    uiHistory: HistoryItemWithoutId[];
    clientHistory: Array<{
        role: 'user' | 'model';
        parts: Part[];
    }>;
};
