/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import type { ConfirmationRequest } from '../../ui/types.js';
import type { ExtensionConfig } from '../extension.js';
export declare const INSTALL_WARNING_MESSAGE = "**The extension you are about to install may have been created by a third-party developer and sourced from a public repository. Google does not vet, endorse, or guarantee the functionality or security of extensions. Please carefully inspect any extension and its source code before installing to understand the permissions it requires and the actions it may perform.**";
/**
 * Requests consent from the user to perform an action, by reading a Y/n
 * character from stdin.
 *
 * This should not be called from interactive mode as it will break the CLI.
 *
 * @param consentDescription The description of the thing they will be consenting to.
 * @returns boolean, whether they consented or not.
 */
export declare function requestConsentNonInteractive(consentDescription: string): Promise<boolean>;
/**
 * Requests consent from the user to perform an action, in interactive mode.
 *
 * This should not be called from non-interactive mode as it will not work.
 *
 * @param consentDescription The description of the thing they will be consenting to.
 * @param setExtensionUpdateConfirmationRequest A function to actually add a prompt to the UI.
 * @returns boolean, whether they consented or not.
 */
export declare function requestConsentInteractive(consentDescription: string, addExtensionUpdateConfirmationRequest: (value: ConfirmationRequest) => void): Promise<boolean>;
/**
 * Requests consent from the user to install an extension (extensionConfig), if
 * there is any difference between the consent string for `extensionConfig` and
 * `previousExtensionConfig`.
 *
 * Always requests consent if previousExtensionConfig is null.
 *
 * Throws if the user does not consent.
 */
export declare function maybeRequestConsentOrFail(extensionConfig: ExtensionConfig, requestConsent: (consent: string) => Promise<boolean>, previousExtensionConfig?: ExtensionConfig): Promise<void>;
