import { jsx as _jsx, Fragment as _Fragment, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import React from 'react';
import { Box, Text } from 'ink';
import { ToolCallStatus } from '../../types.js';
import { DiffRenderer } from './DiffRenderer.js';
import { MarkdownDisplay } from '../../utils/MarkdownDisplay.js';
import { AnsiOutputText } from '../AnsiOutput.js';
import { GeminiRespondingSpinner } from '../GeminiRespondingSpinner.js';
import { MaxSizedBox } from '../shared/MaxSizedBox.js';
import { ShellInputPrompt } from '../ShellInputPrompt.js';
import { StickyHeader } from '../StickyHeader.js';
import { SHELL_COMMAND_NAME, SHELL_NAME, TOOL_STATUS, } from '../../constants.js';
import { theme } from '../../semantic-colors.js';
import { useUIState } from '../../contexts/UIStateContext.js';
import { useAlternateBuffer } from '../../hooks/useAlternateBuffer.js';
const STATIC_HEIGHT = 1;
const RESERVED_LINE_COUNT = 5; // for tool name, status, padding etc.
const STATUS_INDICATOR_WIDTH = 3;
const MIN_LINES_SHOWN = 2; // show at least this many lines
// Large threshold to ensure we don't cause performance issues for very large
// outputs that will get truncated further MaxSizedBox anyway.
const MAXIMUM_RESULT_DISPLAY_CHARACTERS = 1000000;
export const ToolMessage = ({ name, description, resultDisplay, status, availableTerminalHeight, terminalWidth, emphasis = 'medium', renderOutputAsMarkdown = true, activeShellPtyId, embeddedShellFocused, ptyId, config, isFirst, borderColor, borderDimColor, }) => {
    const { renderMarkdown } = useUIState();
    const isAlternateBuffer = useAlternateBuffer();
    const isThisShellFocused = (name === SHELL_COMMAND_NAME || name === 'Shell') &&
        status === ToolCallStatus.Executing &&
        ptyId === activeShellPtyId &&
        embeddedShellFocused;
    const [lastUpdateTime, setLastUpdateTime] = React.useState(null);
    const [userHasFocused, setUserHasFocused] = React.useState(false);
    const [showFocusHint, setShowFocusHint] = React.useState(false);
    React.useEffect(() => {
        if (resultDisplay) {
            setLastUpdateTime(new Date());
        }
    }, [resultDisplay]);
    React.useEffect(() => {
        if (!lastUpdateTime) {
            return;
        }
        const timer = setTimeout(() => {
            setShowFocusHint(true);
        }, 5000);
        return () => clearTimeout(timer);
    }, [lastUpdateTime]);
    React.useEffect(() => {
        if (isThisShellFocused) {
            setUserHasFocused(true);
        }
    }, [isThisShellFocused]);
    const isThisShellFocusable = (name === SHELL_COMMAND_NAME || name === 'Shell') &&
        status === ToolCallStatus.Executing &&
        config?.getEnableInteractiveShell();
    const shouldShowFocusHint = isThisShellFocusable && (showFocusHint || userHasFocused);
    const availableHeight = availableTerminalHeight
        ? Math.max(availableTerminalHeight - STATIC_HEIGHT - RESERVED_LINE_COUNT, MIN_LINES_SHOWN + 1)
        : undefined;
    // Long tool call response in MarkdownDisplay doesn't respect availableTerminalHeight properly,
    // so if we aren't using alternate buffer mode, we're forcing it to not render as markdown when the response is too long, it will fallback
    // to render as plain text, which is contained within the terminal using MaxSizedBox
    if (availableHeight && !isAlternateBuffer) {
        renderOutputAsMarkdown = false;
    }
    const combinedPaddingAndBorderWidth = 4;
    const childWidth = terminalWidth - combinedPaddingAndBorderWidth;
    const truncatedResultDisplay = React.useMemo(() => {
        if (typeof resultDisplay === 'string') {
            if (resultDisplay.length > MAXIMUM_RESULT_DISPLAY_CHARACTERS) {
                return '...' + resultDisplay.slice(-MAXIMUM_RESULT_DISPLAY_CHARACTERS);
            }
        }
        return resultDisplay;
    }, [resultDisplay]);
    const renderedResult = React.useMemo(() => {
        if (!truncatedResultDisplay)
            return null;
        return (_jsx(Box, { width: childWidth, flexDirection: "column", children: _jsx(Box, { flexDirection: "column", children: typeof truncatedResultDisplay === 'string' &&
                    renderOutputAsMarkdown ? (_jsx(Box, { flexDirection: "column", children: _jsx(MarkdownDisplay, { text: truncatedResultDisplay, terminalWidth: childWidth, renderMarkdown: renderMarkdown, isPending: false }) })) : typeof truncatedResultDisplay === 'string' &&
                    !renderOutputAsMarkdown ? (isAlternateBuffer ? (_jsx(Box, { flexDirection: "column", width: childWidth, children: _jsx(Text, { wrap: "wrap", color: theme.text.primary, children: truncatedResultDisplay }) })) : (_jsx(MaxSizedBox, { maxHeight: availableHeight, maxWidth: childWidth, children: _jsx(Box, { children: _jsx(Text, { wrap: "wrap", color: theme.text.primary, children: truncatedResultDisplay }) }) }))) : typeof truncatedResultDisplay === 'object' &&
                    'fileDiff' in truncatedResultDisplay ? (_jsx(DiffRenderer, { diffContent: truncatedResultDisplay.fileDiff, filename: truncatedResultDisplay.fileName, availableTerminalHeight: availableHeight, terminalWidth: childWidth })) : typeof truncatedResultDisplay === 'object' &&
                    'todos' in truncatedResultDisplay ? (
                // display nothing, as the TodoTray will handle rendering todos
                _jsx(_Fragment, {})) : (_jsx(AnsiOutputText, { data: truncatedResultDisplay, availableTerminalHeight: availableHeight, width: childWidth })) }) }));
    }, [
        truncatedResultDisplay,
        renderOutputAsMarkdown,
        childWidth,
        renderMarkdown,
        isAlternateBuffer,
        availableHeight,
    ]);
    return (_jsxs(_Fragment, { children: [_jsxs(StickyHeader, { width: terminalWidth, isFirst: isFirst, borderColor: borderColor, borderDimColor: borderDimColor, children: [_jsx(ToolStatusIndicator, { status: status, name: name }), _jsx(ToolInfo, { name: name, status: status, description: description, emphasis: emphasis }), shouldShowFocusHint && (_jsx(Box, { marginLeft: 1, flexShrink: 0, children: _jsx(Text, { color: theme.text.accent, children: isThisShellFocused ? '(Focused)' : '(ctrl+f to focus)' }) })), emphasis === 'high' && _jsx(TrailingIndicator, {})] }), _jsxs(Box, { width: terminalWidth, borderStyle: "round", borderColor: borderColor, borderDimColor: borderDimColor, borderTop: false, borderBottom: false, borderLeft: true, borderRight: true, paddingX: 1, flexDirection: "column", children: [renderedResult, isThisShellFocused && config && (_jsx(Box, { paddingLeft: STATUS_INDICATOR_WIDTH, marginTop: 1, children: _jsx(ShellInputPrompt, { activeShellPtyId: activeShellPtyId ?? null, focus: embeddedShellFocused }) }))] })] }));
};
const ToolStatusIndicator = ({ status, name, }) => {
    const isShell = name === SHELL_COMMAND_NAME || name === SHELL_NAME;
    const statusColor = isShell ? theme.ui.symbol : theme.status.warning;
    return (_jsxs(Box, { minWidth: STATUS_INDICATOR_WIDTH, children: [status === ToolCallStatus.Pending && (_jsx(Text, { color: theme.status.success, children: TOOL_STATUS.PENDING })), status === ToolCallStatus.Executing && (_jsx(GeminiRespondingSpinner, { spinnerType: "toggle", nonRespondingDisplay: TOOL_STATUS.EXECUTING })), status === ToolCallStatus.Success && (_jsx(Text, { color: theme.status.success, "aria-label": 'Success:', children: TOOL_STATUS.SUCCESS })), status === ToolCallStatus.Confirming && (_jsx(Text, { color: statusColor, "aria-label": 'Confirming:', children: TOOL_STATUS.CONFIRMING })), status === ToolCallStatus.Canceled && (_jsx(Text, { color: statusColor, "aria-label": 'Canceled:', bold: true, children: TOOL_STATUS.CANCELED })), status === ToolCallStatus.Error && (_jsx(Text, { color: theme.status.error, "aria-label": 'Error:', bold: true, children: TOOL_STATUS.ERROR }))] }));
};
const ToolInfo = ({ name, description, status, emphasis, }) => {
    const nameColor = React.useMemo(() => {
        switch (emphasis) {
            case 'high':
                return theme.text.primary;
            case 'medium':
                return theme.text.primary;
            case 'low':
                return theme.text.secondary;
            default: {
                const exhaustiveCheck = emphasis;
                return exhaustiveCheck;
            }
        }
    }, [emphasis]);
    return (_jsx(Box, { overflow: "hidden", height: 1, flexGrow: 1, flexShrink: 1, children: _jsxs(Text, { strikethrough: status === ToolCallStatus.Canceled, wrap: "truncate", children: [_jsx(Text, { color: nameColor, bold: true, children: name }), ' ', _jsx(Text, { color: theme.text.secondary, children: description })] }) }));
};
const TrailingIndicator = () => (_jsxs(Text, { color: theme.text.primary, wrap: "truncate", children: [' ', "\u2190"] }));
//# sourceMappingURL=ToolMessage.js.map