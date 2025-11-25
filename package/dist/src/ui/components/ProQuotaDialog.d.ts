/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import type React from 'react';
import { UserTierId } from '@google/gemini-cli-core';
interface ProQuotaDialogProps {
    failedModel: string;
    fallbackModel: string;
    message: string;
    isTerminalQuotaError: boolean;
    isModelNotFoundError?: boolean;
    onChoice: (choice: 'retry_later' | 'retry_once' | 'retry_always' | 'upgrade') => void;
    userTier: UserTierId | undefined;
}
export declare function ProQuotaDialog({ failedModel, fallbackModel, message, isTerminalQuotaError, isModelNotFoundError, onChoice, userTier, }: ProQuotaDialogProps): React.JSX.Element;
export {};
