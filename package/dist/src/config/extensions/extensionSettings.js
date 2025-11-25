/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import * as fs from 'node:fs/promises';
import * as fsSync from 'node:fs';
import * as dotenv from 'dotenv';
import { ExtensionStorage } from './storage.js';
import prompts from 'prompts';
import { KeychainTokenStorage } from '@google/gemini-cli-core';
const getKeychainStorageName = (extensionName, extensionId) => `Gemini CLI Extensions ${extensionName} ${extensionId}`;
export async function maybePromptForSettings(extensionConfig, extensionId, requestSetting, previousExtensionConfig, previousSettings) {
    const { name: extensionName, settings } = extensionConfig;
    if ((!settings || settings.length === 0) &&
        (!previousExtensionConfig?.settings ||
            previousExtensionConfig.settings.length === 0)) {
        return;
    }
    const envFilePath = new ExtensionStorage(extensionName).getEnvFilePath();
    const keychain = new KeychainTokenStorage(getKeychainStorageName(extensionName, extensionId));
    if (!settings || settings.length === 0) {
        await clearSettings(envFilePath, keychain);
        return;
    }
    const settingsChanges = getSettingsChanges(settings, previousExtensionConfig?.settings ?? []);
    const allSettings = { ...(previousSettings ?? {}) };
    for (const removedEnvSetting of settingsChanges.removeEnv) {
        delete allSettings[removedEnvSetting.envVar];
    }
    for (const removedSensitiveSetting of settingsChanges.removeSensitive) {
        await keychain.deleteSecret(removedSensitiveSetting.envVar);
    }
    for (const setting of settingsChanges.promptForSensitive.concat(settingsChanges.promptForEnv)) {
        const answer = await requestSetting(setting);
        allSettings[setting.envVar] = answer;
    }
    const nonSensitiveSettings = {};
    for (const setting of settings) {
        const value = allSettings[setting.envVar];
        if (value === undefined) {
            continue;
        }
        if (setting.sensitive) {
            await keychain.setSecret(setting.envVar, value);
        }
        else {
            nonSensitiveSettings[setting.envVar] = value;
        }
    }
    let envContent = '';
    for (const [key, value] of Object.entries(nonSensitiveSettings)) {
        envContent += `${key}=${value}\n`;
    }
    await fs.writeFile(envFilePath, envContent);
}
export async function promptForSetting(setting) {
    const response = await prompts({
        type: setting.sensitive ? 'password' : 'text',
        name: 'value',
        message: `${setting.name}\n${setting.description}`,
    });
    return response.value;
}
export async function getEnvContents(extensionConfig, extensionId) {
    if (!extensionConfig.settings || extensionConfig.settings.length === 0) {
        return Promise.resolve({});
    }
    const extensionStorage = new ExtensionStorage(extensionConfig.name);
    const keychain = new KeychainTokenStorage(getKeychainStorageName(extensionConfig.name, extensionId));
    let customEnv = {};
    if (fsSync.existsSync(extensionStorage.getEnvFilePath())) {
        const envFile = fsSync.readFileSync(extensionStorage.getEnvFilePath(), 'utf-8');
        customEnv = dotenv.parse(envFile);
    }
    if (extensionConfig.settings) {
        for (const setting of extensionConfig.settings) {
            if (setting.sensitive) {
                const secret = await keychain.getSecret(setting.envVar);
                if (secret) {
                    customEnv[setting.envVar] = secret;
                }
            }
        }
    }
    return customEnv;
}
function getSettingsChanges(settings, oldSettings) {
    const isSameSetting = (a, b) => a.envVar === b.envVar && (a.sensitive ?? false) === (b.sensitive ?? false);
    const sensitiveOld = oldSettings.filter((s) => s.sensitive ?? false);
    const sensitiveNew = settings.filter((s) => s.sensitive ?? false);
    const envOld = oldSettings.filter((s) => !(s.sensitive ?? false));
    const envNew = settings.filter((s) => !(s.sensitive ?? false));
    return {
        promptForSensitive: sensitiveNew.filter((s) => !sensitiveOld.some((old) => isSameSetting(s, old))),
        removeSensitive: sensitiveOld.filter((s) => !sensitiveNew.some((neu) => isSameSetting(s, neu))),
        promptForEnv: envNew.filter((s) => !envOld.some((old) => isSameSetting(s, old))),
        removeEnv: envOld.filter((s) => !envNew.some((neu) => isSameSetting(s, neu))),
    };
}
async function clearSettings(envFilePath, keychain) {
    if (fsSync.existsSync(envFilePath)) {
        await fs.writeFile(envFilePath, '');
    }
    if (!keychain.isAvailable()) {
        return;
    }
    const secrets = await keychain.listSecrets();
    for (const secret of secrets) {
        await keychain.deleteSecret(secret);
    }
    return;
}
//# sourceMappingURL=extensionSettings.js.map