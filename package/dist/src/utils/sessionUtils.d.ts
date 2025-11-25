/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import type { Config, ConversationRecord, MessageRecord } from '@google/gemini-cli-core';
/**
 * Session information for display and selection purposes.
 */
export interface SessionInfo {
    /** Unique session identifier (filename without .json) */
    id: string;
    /** Filename without extension */
    file: string;
    /** Full filename including .json extension */
    fileName: string;
    /** ISO timestamp when session started */
    startTime: string;
    /** ISO timestamp when session was last updated */
    lastUpdated: string;
    /** Cleaned first user message content */
    firstUserMessage: string;
    /** Whether this is the currently active session */
    isCurrentSession: boolean;
    /** Display index in the list */
    index: number;
}
/**
 * Represents a session file, which may be valid or corrupted.
 */
export interface SessionFileEntry {
    /** Full filename including .json extension */
    fileName: string;
    /** Parsed session info if valid, null if corrupted */
    sessionInfo: SessionInfo | null;
}
/**
 * Result of resolving a session selection argument.
 */
export interface SessionSelectionResult {
    sessionPath: string;
    sessionData: ConversationRecord;
}
/**
 * Extracts the first meaningful user message from conversation messages.
 */
export declare const extractFirstUserMessage: (messages: MessageRecord[]) => string;
/**
 * Formats a timestamp as relative time (e.g., "2 hours ago", "3 days ago").
 */
export declare const formatRelativeTime: (timestamp: string) => string;
/**
 * Loads all session files (including corrupted ones) from the chats directory.
 * @returns Array of session file entries, with sessionInfo null for corrupted files
 */
export declare const getAllSessionFiles: (chatsDir: string, currentSessionId?: string) => Promise<SessionFileEntry[]>;
/**
 * Loads all valid session files from the chats directory and converts them to SessionInfo.
 * Corrupted files are automatically filtered out.
 */
export declare const getSessionFiles: (chatsDir: string, currentSessionId?: string) => Promise<SessionInfo[]>;
/**
 * Utility class for session discovery and selection.
 */
export declare class SessionSelector {
    private config;
    constructor(config: Config);
    /**
     * Lists all available sessions for the current project.
     */
    listSessions(): Promise<SessionInfo[]>;
    /**
     * Finds a session by identifier (UUID or numeric index).
     *
     * @param identifier - Can be a full UUID or an index number (1-based)
     * @returns Promise resolving to the found SessionInfo
     * @throws Error if the session is not found or identifier is invalid
     */
    findSession(identifier: string): Promise<SessionInfo>;
    /**
     * Resolves a resume argument to a specific session.
     *
     * @param resumeArg - Can be "latest", a full UUID, or an index number (1-based)
     * @returns Promise resolving to session selection result
     */
    resolveSession(resumeArg: string): Promise<SessionSelectionResult>;
    /**
     * Loads session data for a selected session.
     */
    private selectSession;
}
