/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import { type Settings, type MemoryImportFormat } from './settingsSchema.js';
import type { ExtensionManager } from './extension-manager.js';
export type { Settings, MemoryImportFormat };
export declare const USER_SETTINGS_PATH: string;
export declare const USER_SETTINGS_DIR: string;
export declare const DEFAULT_EXCLUDED_ENV_VARS: string[];
export declare function getSystemSettingsPath(): string;
export declare function getSystemDefaultsPath(): string;
export type { DnsResolutionOrder } from './settingsSchema.js';
export declare enum SettingScope {
    User = "User",
    Workspace = "Workspace",
    System = "System",
    SystemDefaults = "SystemDefaults",
    Session = "Session"
}
/**
 * A type representing the settings scopes that are supported for LoadedSettings.
 */
export type LoadableSettingScope = SettingScope.User | SettingScope.Workspace | SettingScope.System | SettingScope.SystemDefaults;
/**
 * A type guard function that checks if `scope` is a loadable settings scope,
 * and allows promotion to the `LoadableSettingsScope` type based on the result.
 */
export declare function isLoadableSettingScope(scope: SettingScope): scope is LoadableSettingScope;
export interface CheckpointingSettings {
    enabled?: boolean;
}
export interface SummarizeToolOutputSettings {
    tokenBudget?: number;
}
export interface AccessibilitySettings {
    disableLoadingPhrases?: boolean;
    screenReader?: boolean;
}
export interface SessionRetentionSettings {
    /** Enable automatic session cleanup */
    enabled?: boolean;
    /** Maximum age of sessions to keep (e.g., "30d", "7d", "24h", "1w") */
    maxAge?: string;
    /** Alternative: Maximum number of sessions to keep (most recent) */
    maxCount?: number;
    /** Minimum retention period (safety limit, defaults to "1d") */
    minRetention?: string;
}
export interface SettingsError {
    message: string;
    path: string;
}
export interface SettingsFile {
    settings: Settings;
    originalSettings: Settings;
    path: string;
    rawJson?: string;
}
export declare function needsMigration(settings: Record<string, unknown>): boolean;
export declare function migrateSettingsToV1(v2Settings: Record<string, unknown>): Record<string, unknown>;
export declare class LoadedSettings {
    constructor(system: SettingsFile, systemDefaults: SettingsFile, user: SettingsFile, workspace: SettingsFile, isTrusted: boolean, migratedInMemoryScopes: Set<SettingScope>);
    readonly system: SettingsFile;
    readonly systemDefaults: SettingsFile;
    readonly user: SettingsFile;
    readonly workspace: SettingsFile;
    readonly isTrusted: boolean;
    readonly migratedInMemoryScopes: Set<SettingScope>;
    private _merged;
    get merged(): Settings;
    private computeMergedSettings;
    forScope(scope: LoadableSettingScope): SettingsFile;
    setValue(scope: LoadableSettingScope, key: string, value: unknown): void;
}
export declare function setUpCloudShellEnvironment(envFilePath: string | null): void;
export declare function loadEnvironment(settings: Settings): void;
/**
 * Loads settings from user and workspace directories.
 * Project settings override user settings.
 */
export declare function loadSettings(workspaceDir?: string): LoadedSettings;
export declare function migrateDeprecatedSettings(loadedSettings: LoadedSettings, extensionManager: ExtensionManager): void;
export declare function saveSettings(settingsFile: SettingsFile): void;
