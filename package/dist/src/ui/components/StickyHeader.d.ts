/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import type React from 'react';
export interface StickyHeaderProps {
    children: React.ReactNode;
    width: number;
    isFirst: boolean;
    borderColor: string;
    borderDimColor: boolean;
}
export declare const StickyHeader: React.FC<StickyHeaderProps>;
