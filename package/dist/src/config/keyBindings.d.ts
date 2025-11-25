/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
/**
 * Command enum for all available keyboard shortcuts
 */
export declare enum Command {
    RETURN = "return",
    ESCAPE = "escape",
    HOME = "home",
    END = "end",
    KILL_LINE_RIGHT = "killLineRight",
    KILL_LINE_LEFT = "killLineLeft",
    CLEAR_INPUT = "clearInput",
    DELETE_WORD_BACKWARD = "deleteWordBackward",
    CLEAR_SCREEN = "clearScreen",
    SCROLL_UP = "scrollUp",
    SCROLL_DOWN = "scrollDown",
    SCROLL_HOME = "scrollHome",
    SCROLL_END = "scrollEnd",
    PAGE_UP = "pageUp",
    PAGE_DOWN = "pageDown",
    HISTORY_UP = "historyUp",
    HISTORY_DOWN = "historyDown",
    NAVIGATION_UP = "navigationUp",
    NAVIGATION_DOWN = "navigationDown",
    DIALOG_NAVIGATION_UP = "dialogNavigationUp",
    DIALOG_NAVIGATION_DOWN = "dialogNavigationDown",
    ACCEPT_SUGGESTION = "acceptSuggestion",
    COMPLETION_UP = "completionUp",
    COMPLETION_DOWN = "completionDown",
    SUBMIT = "submit",
    NEWLINE = "newline",
    OPEN_EXTERNAL_EDITOR = "openExternalEditor",
    PASTE_CLIPBOARD = "pasteClipboard",
    SHOW_ERROR_DETAILS = "showErrorDetails",
    SHOW_FULL_TODOS = "showFullTodos",
    TOGGLE_IDE_CONTEXT_DETAIL = "toggleIDEContextDetail",
    TOGGLE_MARKDOWN = "toggleMarkdown",
    TOGGLE_COPY_MODE = "toggleCopyMode",
    QUIT = "quit",
    EXIT = "exit",
    SHOW_MORE_LINES = "showMoreLines",
    REVERSE_SEARCH = "reverseSearch",
    SUBMIT_REVERSE_SEARCH = "submitReverseSearch",
    ACCEPT_SUGGESTION_REVERSE_SEARCH = "acceptSuggestionReverseSearch",
    TOGGLE_SHELL_INPUT_FOCUS = "toggleShellInputFocus",
    EXPAND_SUGGESTION = "expandSuggestion",
    COLLAPSE_SUGGESTION = "collapseSuggestion"
}
/**
 * Data-driven key binding structure for user configuration
 */
export interface KeyBinding {
    /** The key name (e.g., 'a', 'return', 'tab', 'escape') */
    key?: string;
    /** The key sequence (e.g., '\x18' for Ctrl+X) - alternative to key name */
    sequence?: string;
    /** Control key requirement: true=must be pressed, false=must not be pressed, undefined=ignore */
    ctrl?: boolean;
    /** Shift key requirement: true=must be pressed, false=must not be pressed, undefined=ignore */
    shift?: boolean;
    /** Command/meta key requirement: true=must be pressed, false=must not be pressed, undefined=ignore */
    command?: boolean;
    /** Paste operation requirement: true=must be paste, false=must not be paste, undefined=ignore */
    paste?: boolean;
}
/**
 * Configuration type mapping commands to their key bindings
 */
export type KeyBindingConfig = {
    readonly [C in Command]: readonly KeyBinding[];
};
/**
 * Default key binding configuration
 * Matches the original hard-coded logic exactly
 */
export declare const defaultKeyBindings: KeyBindingConfig;
interface CommandCategory {
    readonly title: string;
    readonly commands: readonly Command[];
}
/**
 * Presentation metadata for grouping commands in documentation or UI.
 */
export declare const commandCategories: readonly CommandCategory[];
/**
 * Human-readable descriptions for each command, used in docs/tooling.
 */
export declare const commandDescriptions: Readonly<Record<Command, string>>;
export {};
