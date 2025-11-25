/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import { render as inkRender } from 'ink-testing-library';
import type React from 'react';
import { LoadedSettings, type Settings } from '../config/settings.js';
import { type UIState } from '../ui/contexts/UIStateContext.js';
import { type Config } from '@google/gemini-cli-core';
export declare const render: (tree: React.ReactElement, terminalWidth?: number) => ReturnType<typeof inkRender>;
export declare const mockSettings: LoadedSettings;
export declare const createMockSettings: (overrides: Partial<Settings>) => LoadedSettings;
export declare const renderWithProviders: (component: React.ReactElement, { shellFocus, settings, uiState: providedUiState, width, mouseEventsEnabled, config, useAlternateBuffer, }?: {
    shellFocus?: boolean;
    settings?: LoadedSettings;
    uiState?: Partial<UIState>;
    width?: number;
    mouseEventsEnabled?: boolean;
    config?: Config;
    useAlternateBuffer?: boolean;
}) => ReturnType<typeof render>;
export declare function renderHook<Result, Props>(renderCallback: (props: Props) => Result, options?: {
    initialProps?: Props;
    wrapper?: React.ComponentType<{
        children: React.ReactNode;
    }>;
}): {
    result: {
        current: Result;
    };
    rerender: (props?: Props) => void;
    unmount: () => void;
};
