/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import { vi, describe, it, expect, beforeEach, afterEach, } from 'vitest';
import {} from 'yargs';
import { handleLink, linkCommand } from './link.js';
import { ExtensionManager } from '../../config/extension-manager.js';
import { loadSettings } from '../../config/settings.js';
import { getErrorMessage } from '../../utils/errors.js';
// Mock dependencies
vi.mock('../../config/extension-manager.js');
vi.mock('../../config/settings.js');
vi.mock('../../utils/errors.js');
vi.mock('@google/gemini-cli-core', async (importOriginal) => {
    const actual = await importOriginal();
    return {
        ...actual,
        debugLogger: {
            log: vi.fn(),
            error: vi.fn(),
        },
    };
});
vi.mock('../../config/extensions/consent.js', () => ({
    requestConsentNonInteractive: vi.fn(),
}));
vi.mock('../../config/extensions/extensionSettings.js', () => ({
    promptForSetting: vi.fn(),
}));
describe('extensions link command', () => {
    const mockLoadSettings = vi.mocked(loadSettings);
    const mockGetErrorMessage = vi.mocked(getErrorMessage);
    const mockExtensionManager = vi.mocked(ExtensionManager);
    let mockDebugLogger;
    beforeEach(async () => {
        vi.clearAllMocks();
        mockDebugLogger = (await import('@google/gemini-cli-core'))
            .debugLogger;
        mockLoadSettings.mockReturnValue({
            merged: {},
        });
        mockExtensionManager.prototype.loadExtensions = vi
            .fn()
            .mockResolvedValue(undefined);
        mockExtensionManager.prototype.installOrUpdateExtension = vi
            .fn()
            .mockResolvedValue({ name: 'my-linked-extension' });
    });
    afterEach(() => {
        vi.restoreAllMocks();
    });
    describe('handleLink', () => {
        it('should link an extension from a local path', async () => {
            const mockCwd = vi.spyOn(process, 'cwd').mockReturnValue('/test/dir');
            await handleLink({ path: '/local/path/to/extension' });
            expect(mockExtensionManager).toHaveBeenCalledWith(expect.objectContaining({
                workspaceDir: '/test/dir',
            }));
            expect(mockExtensionManager.prototype.loadExtensions).toHaveBeenCalled();
            expect(mockExtensionManager.prototype.installOrUpdateExtension).toHaveBeenCalledWith({
                source: '/local/path/to/extension',
                type: 'link',
            });
            expect(mockDebugLogger.log).toHaveBeenCalledWith('Extension "my-linked-extension" linked successfully and enabled.');
            mockCwd.mockRestore();
        });
        it('should log an error message and exit with code 1 when linking fails', async () => {
            const mockProcessExit = vi
                .spyOn(process, 'exit')
                .mockImplementation((() => { }));
            const error = new Error('Link failed');
            mockExtensionManager.prototype.installOrUpdateExtension.mockRejectedValue(error);
            mockGetErrorMessage.mockReturnValue('Link failed message');
            await handleLink({ path: '/local/path/to/extension' });
            expect(mockDebugLogger.error).toHaveBeenCalledWith('Link failed message');
            expect(mockProcessExit).toHaveBeenCalledWith(1);
            mockProcessExit.mockRestore();
        });
    });
    describe('linkCommand', () => {
        const command = linkCommand;
        it('should have correct command and describe', () => {
            expect(command.command).toBe('link <path>');
            expect(command.describe).toBe('Links an extension from a local path. Updates made to the local path will always be reflected.');
        });
        describe('builder', () => {
            let yargsMock;
            beforeEach(() => {
                yargsMock = {
                    positional: vi.fn().mockReturnThis(),
                    check: vi.fn().mockReturnThis(),
                };
            });
            it('should configure positional argument', () => {
                command.builder(yargsMock);
                expect(yargsMock.positional).toHaveBeenCalledWith('path', {
                    describe: 'The name of the extension to link.',
                    type: 'string',
                });
                expect(yargsMock.check).toHaveBeenCalled();
            });
        });
        it('handler should call handleLink', async () => {
            const mockCwd = vi.spyOn(process, 'cwd').mockReturnValue('/test/dir');
            const argv = {
                path: '/local/path/to/extension',
                _: [],
                $0: '',
            };
            await command.handler(argv);
            expect(mockExtensionManager.prototype.installOrUpdateExtension).toHaveBeenCalledWith({
                source: '/local/path/to/extension',
                type: 'link',
            });
            mockCwd.mockRestore();
        });
    });
});
//# sourceMappingURL=link.test.js.map