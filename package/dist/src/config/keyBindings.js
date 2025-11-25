/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
/**
 * Command enum for all available keyboard shortcuts
 */
export var Command;
(function (Command) {
    // Basic bindings
    Command["RETURN"] = "return";
    Command["ESCAPE"] = "escape";
    // Cursor movement
    Command["HOME"] = "home";
    Command["END"] = "end";
    // Text deletion
    Command["KILL_LINE_RIGHT"] = "killLineRight";
    Command["KILL_LINE_LEFT"] = "killLineLeft";
    Command["CLEAR_INPUT"] = "clearInput";
    Command["DELETE_WORD_BACKWARD"] = "deleteWordBackward";
    // Screen control
    Command["CLEAR_SCREEN"] = "clearScreen";
    // Scrolling
    Command["SCROLL_UP"] = "scrollUp";
    Command["SCROLL_DOWN"] = "scrollDown";
    Command["SCROLL_HOME"] = "scrollHome";
    Command["SCROLL_END"] = "scrollEnd";
    Command["PAGE_UP"] = "pageUp";
    Command["PAGE_DOWN"] = "pageDown";
    // History navigation
    Command["HISTORY_UP"] = "historyUp";
    Command["HISTORY_DOWN"] = "historyDown";
    Command["NAVIGATION_UP"] = "navigationUp";
    Command["NAVIGATION_DOWN"] = "navigationDown";
    // Dialog navigation
    Command["DIALOG_NAVIGATION_UP"] = "dialogNavigationUp";
    Command["DIALOG_NAVIGATION_DOWN"] = "dialogNavigationDown";
    // Auto-completion
    Command["ACCEPT_SUGGESTION"] = "acceptSuggestion";
    Command["COMPLETION_UP"] = "completionUp";
    Command["COMPLETION_DOWN"] = "completionDown";
    // Text input
    Command["SUBMIT"] = "submit";
    Command["NEWLINE"] = "newline";
    // External tools
    Command["OPEN_EXTERNAL_EDITOR"] = "openExternalEditor";
    Command["PASTE_CLIPBOARD"] = "pasteClipboard";
    // App level bindings
    Command["SHOW_ERROR_DETAILS"] = "showErrorDetails";
    Command["SHOW_FULL_TODOS"] = "showFullTodos";
    Command["TOGGLE_IDE_CONTEXT_DETAIL"] = "toggleIDEContextDetail";
    Command["TOGGLE_MARKDOWN"] = "toggleMarkdown";
    Command["TOGGLE_COPY_MODE"] = "toggleCopyMode";
    Command["QUIT"] = "quit";
    Command["EXIT"] = "exit";
    Command["SHOW_MORE_LINES"] = "showMoreLines";
    // Shell commands
    Command["REVERSE_SEARCH"] = "reverseSearch";
    Command["SUBMIT_REVERSE_SEARCH"] = "submitReverseSearch";
    Command["ACCEPT_SUGGESTION_REVERSE_SEARCH"] = "acceptSuggestionReverseSearch";
    Command["TOGGLE_SHELL_INPUT_FOCUS"] = "toggleShellInputFocus";
    // Suggestion expansion
    Command["EXPAND_SUGGESTION"] = "expandSuggestion";
    Command["COLLAPSE_SUGGESTION"] = "collapseSuggestion";
})(Command || (Command = {}));
/**
 * Default key binding configuration
 * Matches the original hard-coded logic exactly
 */
export const defaultKeyBindings = {
    // Basic bindings
    [Command.RETURN]: [{ key: 'return' }],
    [Command.ESCAPE]: [{ key: 'escape' }],
    // Cursor movement
    [Command.HOME]: [{ key: 'a', ctrl: true }, { key: 'home' }],
    [Command.END]: [{ key: 'e', ctrl: true }, { key: 'end' }],
    // Text deletion
    [Command.KILL_LINE_RIGHT]: [{ key: 'k', ctrl: true }],
    [Command.KILL_LINE_LEFT]: [{ key: 'u', ctrl: true }],
    [Command.CLEAR_INPUT]: [{ key: 'c', ctrl: true }],
    // Added command (meta/alt/option) for mac compatibility
    [Command.DELETE_WORD_BACKWARD]: [
        { key: 'backspace', ctrl: true },
        { key: 'backspace', command: true },
    ],
    // Screen control
    [Command.CLEAR_SCREEN]: [{ key: 'l', ctrl: true }],
    // Scrolling
    [Command.SCROLL_UP]: [{ key: 'up', shift: true }],
    [Command.SCROLL_DOWN]: [{ key: 'down', shift: true }],
    [Command.SCROLL_HOME]: [{ key: 'home' }],
    [Command.SCROLL_END]: [{ key: 'end' }],
    [Command.PAGE_UP]: [{ key: 'pageup' }],
    [Command.PAGE_DOWN]: [{ key: 'pagedown' }],
    // History navigation
    [Command.HISTORY_UP]: [{ key: 'p', ctrl: true, shift: false }],
    [Command.HISTORY_DOWN]: [{ key: 'n', ctrl: true, shift: false }],
    [Command.NAVIGATION_UP]: [{ key: 'up', shift: false }],
    [Command.NAVIGATION_DOWN]: [{ key: 'down', shift: false }],
    // Dialog navigation
    // Navigation shortcuts appropriate for dialogs where we do not need to accept
    // text input.
    [Command.DIALOG_NAVIGATION_UP]: [
        { key: 'up', shift: false },
        { key: 'k', shift: false },
    ],
    [Command.DIALOG_NAVIGATION_DOWN]: [
        { key: 'down', shift: false },
        { key: 'j', shift: false },
    ],
    // Auto-completion
    [Command.ACCEPT_SUGGESTION]: [{ key: 'tab' }, { key: 'return', ctrl: false }],
    // Completion navigation (arrow or Ctrl+P/N)
    [Command.COMPLETION_UP]: [
        { key: 'up', shift: false },
        { key: 'p', ctrl: true, shift: false },
    ],
    [Command.COMPLETION_DOWN]: [
        { key: 'down', shift: false },
        { key: 'n', ctrl: true, shift: false },
    ],
    // Text input
    // Must also exclude shift to allow shift+enter for newline
    [Command.SUBMIT]: [
        {
            key: 'return',
            ctrl: false,
            command: false,
            paste: false,
            shift: false,
        },
    ],
    // Split into multiple data-driven bindings
    // Now also includes shift+enter for multi-line input
    [Command.NEWLINE]: [
        { key: 'return', ctrl: true },
        { key: 'return', command: true },
        { key: 'return', paste: true },
        { key: 'return', shift: true },
        { key: 'j', ctrl: true },
    ],
    // External tools
    [Command.OPEN_EXTERNAL_EDITOR]: [
        { key: 'x', ctrl: true },
        { sequence: '\x18', ctrl: true },
    ],
    [Command.PASTE_CLIPBOARD]: [{ key: 'v', ctrl: true }],
    // App level bindings
    [Command.SHOW_ERROR_DETAILS]: [{ key: 'f12' }],
    [Command.SHOW_FULL_TODOS]: [{ key: 't', ctrl: true }],
    [Command.TOGGLE_IDE_CONTEXT_DETAIL]: [{ key: 'g', ctrl: true }],
    [Command.TOGGLE_MARKDOWN]: [{ key: 'm', command: true }],
    [Command.TOGGLE_COPY_MODE]: [{ key: 's', ctrl: true }],
    [Command.QUIT]: [{ key: 'c', ctrl: true }],
    [Command.EXIT]: [{ key: 'd', ctrl: true }],
    [Command.SHOW_MORE_LINES]: [{ key: 's', ctrl: true }],
    // Shell commands
    [Command.REVERSE_SEARCH]: [{ key: 'r', ctrl: true }],
    // Note: original logic ONLY checked ctrl=false, ignored meta/shift/paste
    [Command.SUBMIT_REVERSE_SEARCH]: [{ key: 'return', ctrl: false }],
    [Command.ACCEPT_SUGGESTION_REVERSE_SEARCH]: [{ key: 'tab' }],
    [Command.TOGGLE_SHELL_INPUT_FOCUS]: [{ key: 'f', ctrl: true }],
    // Suggestion expansion
    [Command.EXPAND_SUGGESTION]: [{ key: 'right' }],
    [Command.COLLAPSE_SUGGESTION]: [{ key: 'left' }],
};
/**
 * Presentation metadata for grouping commands in documentation or UI.
 */
export const commandCategories = [
    {
        title: 'Basic Controls',
        commands: [Command.RETURN, Command.ESCAPE],
    },
    {
        title: 'Cursor Movement',
        commands: [Command.HOME, Command.END],
    },
    {
        title: 'Editing',
        commands: [
            Command.KILL_LINE_RIGHT,
            Command.KILL_LINE_LEFT,
            Command.CLEAR_INPUT,
            Command.DELETE_WORD_BACKWARD,
        ],
    },
    {
        title: 'Screen Control',
        commands: [Command.CLEAR_SCREEN],
    },
    {
        title: 'Scrolling',
        commands: [
            Command.SCROLL_UP,
            Command.SCROLL_DOWN,
            Command.SCROLL_HOME,
            Command.SCROLL_END,
            Command.PAGE_UP,
            Command.PAGE_DOWN,
        ],
    },
    {
        title: 'History & Search',
        commands: [
            Command.HISTORY_UP,
            Command.HISTORY_DOWN,
            Command.REVERSE_SEARCH,
            Command.SUBMIT_REVERSE_SEARCH,
            Command.ACCEPT_SUGGESTION_REVERSE_SEARCH,
        ],
    },
    {
        title: 'Navigation',
        commands: [
            Command.NAVIGATION_UP,
            Command.NAVIGATION_DOWN,
            Command.DIALOG_NAVIGATION_UP,
            Command.DIALOG_NAVIGATION_DOWN,
        ],
    },
    {
        title: 'Suggestions & Completions',
        commands: [
            Command.ACCEPT_SUGGESTION,
            Command.COMPLETION_UP,
            Command.COMPLETION_DOWN,
            Command.EXPAND_SUGGESTION,
            Command.COLLAPSE_SUGGESTION,
        ],
    },
    {
        title: 'Text Input',
        commands: [Command.SUBMIT, Command.NEWLINE],
    },
    {
        title: 'External Tools',
        commands: [Command.OPEN_EXTERNAL_EDITOR, Command.PASTE_CLIPBOARD],
    },
    {
        title: 'App Controls',
        commands: [
            Command.SHOW_ERROR_DETAILS,
            Command.SHOW_FULL_TODOS,
            Command.TOGGLE_IDE_CONTEXT_DETAIL,
            Command.TOGGLE_MARKDOWN,
            Command.TOGGLE_COPY_MODE,
            Command.SHOW_MORE_LINES,
            Command.TOGGLE_SHELL_INPUT_FOCUS,
        ],
    },
    {
        title: 'Session Control',
        commands: [Command.QUIT, Command.EXIT],
    },
];
/**
 * Human-readable descriptions for each command, used in docs/tooling.
 */
export const commandDescriptions = {
    [Command.RETURN]: 'Confirm the current selection or choice.',
    [Command.ESCAPE]: 'Dismiss dialogs or cancel the current focus.',
    [Command.HOME]: 'Move the cursor to the start of the line.',
    [Command.END]: 'Move the cursor to the end of the line.',
    [Command.KILL_LINE_RIGHT]: 'Delete from the cursor to the end of the line.',
    [Command.KILL_LINE_LEFT]: 'Delete from the cursor to the start of the line.',
    [Command.CLEAR_INPUT]: 'Clear all text in the input field.',
    [Command.DELETE_WORD_BACKWARD]: 'Delete the previous word.',
    [Command.CLEAR_SCREEN]: 'Clear the terminal screen and redraw the UI.',
    [Command.SCROLL_UP]: 'Scroll content up.',
    [Command.SCROLL_DOWN]: 'Scroll content down.',
    [Command.SCROLL_HOME]: 'Scroll to the top.',
    [Command.SCROLL_END]: 'Scroll to the bottom.',
    [Command.PAGE_UP]: 'Scroll up by one page.',
    [Command.PAGE_DOWN]: 'Scroll down by one page.',
    [Command.HISTORY_UP]: 'Show the previous entry in history.',
    [Command.HISTORY_DOWN]: 'Show the next entry in history.',
    [Command.NAVIGATION_UP]: 'Move selection up in lists.',
    [Command.NAVIGATION_DOWN]: 'Move selection down in lists.',
    [Command.DIALOG_NAVIGATION_UP]: 'Move up within dialog options.',
    [Command.DIALOG_NAVIGATION_DOWN]: 'Move down within dialog options.',
    [Command.ACCEPT_SUGGESTION]: 'Accept the inline suggestion.',
    [Command.COMPLETION_UP]: 'Move to the previous completion option.',
    [Command.COMPLETION_DOWN]: 'Move to the next completion option.',
    [Command.SUBMIT]: 'Submit the current prompt.',
    [Command.NEWLINE]: 'Insert a newline without submitting.',
    [Command.OPEN_EXTERNAL_EDITOR]: 'Open the current prompt in an external editor.',
    [Command.PASTE_CLIPBOARD]: 'Paste from the clipboard.',
    [Command.SHOW_ERROR_DETAILS]: 'Toggle detailed error information.',
    [Command.SHOW_FULL_TODOS]: 'Toggle the full TODO list.',
    [Command.TOGGLE_IDE_CONTEXT_DETAIL]: 'Toggle IDE context details.',
    [Command.TOGGLE_MARKDOWN]: 'Toggle Markdown rendering.',
    [Command.TOGGLE_COPY_MODE]: 'Toggle copy mode when the terminal is using the alternate buffer.',
    [Command.QUIT]: 'Cancel the current request or quit the CLI.',
    [Command.EXIT]: 'Exit the CLI when the input buffer is empty.',
    [Command.SHOW_MORE_LINES]: 'Expand a height-constrained response to show additional lines.',
    [Command.REVERSE_SEARCH]: 'Start reverse search through history.',
    [Command.SUBMIT_REVERSE_SEARCH]: 'Insert the selected reverse-search match.',
    [Command.ACCEPT_SUGGESTION_REVERSE_SEARCH]: 'Accept a suggestion while reverse searching.',
    [Command.TOGGLE_SHELL_INPUT_FOCUS]: 'Toggle focus between the shell and Gemini input.',
    [Command.EXPAND_SUGGESTION]: 'Expand an inline suggestion.',
    [Command.COLLAPSE_SUGGESTION]: 'Collapse an inline suggestion.',
};
//# sourceMappingURL=keyBindings.js.map