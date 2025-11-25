import { jsx as _jsx, Fragment as _Fragment } from "react/jsx-runtime";
/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import { render as inkRender } from 'ink-testing-library';
import { Box } from 'ink';
import { act } from 'react';
import { LoadedSettings } from '../config/settings.js';
import { KeypressProvider } from '../ui/contexts/KeypressContext.js';
import { SettingsContext } from '../ui/contexts/SettingsContext.js';
import { ShellFocusContext } from '../ui/contexts/ShellFocusContext.js';
import { UIStateContext } from '../ui/contexts/UIStateContext.js';
import { StreamingState } from '../ui/types.js';
import { ConfigContext } from '../ui/contexts/ConfigContext.js';
import { calculateMainAreaWidth } from '../ui/utils/ui-sizing.js';
import { VimModeProvider } from '../ui/contexts/VimModeContext.js';
import { MouseProvider } from '../ui/contexts/MouseContext.js';
import { ScrollProvider } from '../ui/contexts/ScrollProvider.js';
import { StreamingContext } from '../ui/contexts/StreamingContext.js';
import {} from '@google/gemini-cli-core';
// Wrapper around ink-testing-library's render that ensures act() is called
export const render = (tree, terminalWidth) => {
    let renderResult = undefined;
    act(() => {
        renderResult = inkRender(tree);
    });
    if (terminalWidth !== undefined && renderResult?.stdout) {
        // Override the columns getter on the stdout instance provided by ink-testing-library
        Object.defineProperty(renderResult.stdout, 'columns', {
            get: () => terminalWidth,
            configurable: true,
        });
        // Trigger a rerender so Ink can pick up the new terminal width
        act(() => {
            renderResult.rerender(tree);
        });
    }
    const originalUnmount = renderResult.unmount;
    const originalRerender = renderResult.rerender;
    return {
        ...renderResult,
        unmount: () => {
            act(() => {
                originalUnmount();
            });
        },
        rerender: (newTree) => {
            act(() => {
                originalRerender(newTree);
            });
        },
    };
};
const mockConfig = {
    getModel: () => 'gemini-pro',
    getTargetDir: () => '/Users/test/project/foo/bar/and/some/more/directories/to/make/it/long',
    getDebugMode: () => false,
    isTrustedFolder: () => true,
    getIdeMode: () => false,
    getEnableInteractiveShell: () => true,
};
const configProxy = new Proxy(mockConfig, {
    get(target, prop) {
        if (prop in target) {
            return target[prop];
        }
        throw new Error(`mockConfig does not have property ${String(prop)}`);
    },
});
export const mockSettings = new LoadedSettings({ path: '', settings: {}, originalSettings: {} }, { path: '', settings: {}, originalSettings: {} }, { path: '', settings: {}, originalSettings: {} }, { path: '', settings: {}, originalSettings: {} }, true, new Set());
export const createMockSettings = (overrides) => {
    const settings = overrides;
    return new LoadedSettings({ path: '', settings: {}, originalSettings: {} }, { path: '', settings: {}, originalSettings: {} }, { path: '', settings, originalSettings: settings }, { path: '', settings: {}, originalSettings: {} }, true, new Set());
};
// A minimal mock UIState to satisfy the context provider.
// Tests that need specific UIState values should provide their own.
const baseMockUiState = {
    renderMarkdown: true,
    streamingState: StreamingState.Idle,
    mainAreaWidth: 100,
    terminalWidth: 120,
    currentModel: 'gemini-pro',
};
export const renderWithProviders = (component, { shellFocus = true, settings = mockSettings, uiState: providedUiState, width, mouseEventsEnabled = false, config = configProxy, useAlternateBuffer = true, } = {}) => {
    const baseState = new Proxy({ ...baseMockUiState, ...providedUiState }, {
        get(target, prop) {
            if (prop in target) {
                return target[prop];
            }
            // For properties not in the base mock or provided state,
            // we'll check the original proxy to see if it's a defined but
            // unprovided property, and if not, throw.
            if (prop in baseMockUiState) {
                return baseMockUiState[prop];
            }
            throw new Error(`mockUiState does not have property ${String(prop)}`);
        },
    });
    const terminalWidth = width ?? baseState.terminalWidth;
    let finalSettings = settings;
    if (useAlternateBuffer !== undefined) {
        finalSettings = createMockSettings({
            ...settings.merged,
            ui: {
                ...settings.merged.ui,
                useAlternateBuffer,
            },
        });
    }
    const mainAreaWidth = calculateMainAreaWidth(terminalWidth, finalSettings);
    const finalUiState = {
        ...baseState,
        terminalWidth,
        mainAreaWidth,
    };
    return render(_jsx(ConfigContext.Provider, { value: config, children: _jsx(SettingsContext.Provider, { value: finalSettings, children: _jsx(UIStateContext.Provider, { value: finalUiState, children: _jsx(VimModeProvider, { settings: finalSettings, children: _jsx(ShellFocusContext.Provider, { value: shellFocus, children: _jsx(StreamingContext.Provider, { value: finalUiState.streamingState, children: _jsx(KeypressProvider, { children: _jsx(MouseProvider, { mouseEventsEnabled: mouseEventsEnabled, children: _jsx(ScrollProvider, { children: _jsx(Box, { width: terminalWidth, flexShrink: 0, flexGrow: 0, flexDirection: "column", children: component }) }) }) }) }) }) }) }) }) }), terminalWidth);
};
export function renderHook(renderCallback, options) {
    const result = { current: undefined };
    let currentProps = options?.initialProps;
    function TestComponent({ renderCallback, props, }) {
        result.current = renderCallback(props);
        return null;
    }
    const Wrapper = options?.wrapper || (({ children }) => _jsx(_Fragment, { children: children }));
    let inkRerender = () => { };
    let unmount = () => { };
    act(() => {
        const renderResult = render(_jsx(Wrapper, { children: _jsx(TestComponent, { renderCallback: renderCallback, props: currentProps }) }));
        inkRerender = renderResult.rerender;
        unmount = renderResult.unmount;
    });
    function rerender(props) {
        if (arguments.length > 0) {
            currentProps = props;
        }
        act(() => {
            inkRerender(_jsx(Wrapper, { children: _jsx(TestComponent, { renderCallback: renderCallback, props: currentProps }) }));
        });
    }
    return { result, rerender, unmount };
}
//# sourceMappingURL=render.js.map