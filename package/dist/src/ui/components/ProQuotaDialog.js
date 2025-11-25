import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Box, Text } from 'ink';
import { RadioButtonSelect } from './shared/RadioButtonSelect.js';
import { theme } from '../semantic-colors.js';
import { DEFAULT_GEMINI_FLASH_LITE_MODEL, DEFAULT_GEMINI_FLASH_MODEL, PREVIEW_GEMINI_MODEL, UserTierId, } from '@google/gemini-cli-core';
export function ProQuotaDialog({ failedModel, fallbackModel, message, isTerminalQuotaError, isModelNotFoundError, onChoice, userTier, }) {
    // Use actual user tier if available; otherwise, default to FREE tier behavior (safe default)
    const isPaidTier = userTier === UserTierId.LEGACY || userTier === UserTierId.STANDARD;
    let items;
    // flash and flash lite don't have options to switch or upgrade.
    if (failedModel === DEFAULT_GEMINI_FLASH_MODEL ||
        failedModel === DEFAULT_GEMINI_FLASH_LITE_MODEL) {
        items = [
            {
                label: 'Keep trying',
                value: 'retry_once',
                key: 'retry_once',
            },
            {
                label: 'Stop',
                value: 'retry_later',
                key: 'retry_later',
            },
        ];
    }
    else if (isModelNotFoundError || (isTerminalQuotaError && isPaidTier)) {
        // out of quota
        items = [
            {
                label: `Switch to ${fallbackModel}`,
                value: 'retry_always',
                key: 'retry_always',
            },
            {
                label: `Stop`,
                value: 'retry_later',
                key: 'retry_later',
            },
        ];
    }
    else if (isTerminalQuotaError && !isPaidTier) {
        // free user gets an option to upgrade
        items = [
            {
                label: `Switch to ${fallbackModel}`,
                value: 'retry_always',
                key: 'retry_always',
            },
            {
                label: 'Upgrade for higher limits',
                value: 'upgrade',
                key: 'upgrade',
            },
            {
                label: `Stop`,
                value: 'retry_later',
                key: 'retry_later',
            },
        ];
    }
    else {
        // capacity error
        items = [
            {
                label: 'Keep trying',
                value: 'retry_once',
                key: 'retry_once',
            },
            {
                label: `Switch to ${fallbackModel}`,
                value: 'retry_always',
                key: 'retry_always',
            },
            {
                label: 'Stop',
                value: 'retry_later',
                key: 'retry_later',
            },
        ];
    }
    const handleSelect = (choice) => {
        onChoice(choice);
    };
    return (_jsxs(Box, { borderStyle: "round", flexDirection: "column", padding: 1, children: [_jsx(Box, { marginBottom: 1, children: _jsx(Text, { children: message }) }), _jsx(Box, { marginTop: 1, marginBottom: 1, children: _jsx(RadioButtonSelect, { items: items, onSelect: handleSelect }) }), _jsx(Text, { color: theme.text.primary, children: failedModel === PREVIEW_GEMINI_MODEL && !isModelNotFoundError
                    ? 'Note: We will periodically retry Preview Model to see if congestion has cleared.'
                    : 'Note: You can always use /model to select a different option.' })] }));
}
//# sourceMappingURL=ProQuotaDialog.js.map