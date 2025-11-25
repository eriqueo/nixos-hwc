import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useCallback, useContext, useMemo } from 'react';
import { Box, Text } from 'ink';
import { PREVIEW_GEMINI_MODEL, DEFAULT_GEMINI_MODEL, DEFAULT_GEMINI_FLASH_MODEL, DEFAULT_GEMINI_FLASH_LITE_MODEL, DEFAULT_GEMINI_MODEL_AUTO, GEMINI_MODEL_ALIAS_FLASH, GEMINI_MODEL_ALIAS_FLASH_LITE, GEMINI_MODEL_ALIAS_PRO, ModelSlashCommandEvent, logModelSlashCommand, } from '@google/gemini-cli-core';
import { useKeypress } from '../hooks/useKeypress.js';
import { theme } from '../semantic-colors.js';
import { DescriptiveRadioButtonSelect } from './shared/DescriptiveRadioButtonSelect.js';
import { ConfigContext } from '../contexts/ConfigContext.js';
import Gradient from 'ink-gradient';
export function ModelDialog({ onClose }) {
    const config = useContext(ConfigContext);
    // Determine the Preferred Model (read once when the dialog opens).
    const preferredModel = config?.getModel() || DEFAULT_GEMINI_MODEL_AUTO;
    useKeypress((key) => {
        if (key.name === 'escape') {
            onClose();
        }
    }, { isActive: true });
    const options = useMemo(() => [
        {
            value: DEFAULT_GEMINI_MODEL_AUTO,
            title: 'Auto',
            description: 'Let the system choose the best model for your task.',
            key: DEFAULT_GEMINI_MODEL_AUTO,
        },
        {
            value: GEMINI_MODEL_ALIAS_PRO,
            title: config?.getPreviewFeatures()
                ? `Pro (${PREVIEW_GEMINI_MODEL}, ${DEFAULT_GEMINI_MODEL})`
                : `Pro (${DEFAULT_GEMINI_MODEL})`,
            description: 'For complex tasks that require deep reasoning and creativity',
            key: GEMINI_MODEL_ALIAS_PRO,
        },
        {
            value: GEMINI_MODEL_ALIAS_FLASH,
            title: `Flash (${DEFAULT_GEMINI_FLASH_MODEL})`,
            description: 'For tasks that need a balance of speed and reasoning',
            key: GEMINI_MODEL_ALIAS_FLASH,
        },
        {
            value: GEMINI_MODEL_ALIAS_FLASH_LITE,
            title: `Flash-Lite (${DEFAULT_GEMINI_FLASH_LITE_MODEL})`,
            description: 'For simple tasks that need to be done quickly',
            key: GEMINI_MODEL_ALIAS_FLASH_LITE,
        },
    ], [config]);
    // Calculate the initial index based on the preferred model.
    const initialIndex = useMemo(() => options.findIndex((option) => option.value === preferredModel), [preferredModel, options]);
    // Handle selection internally (Autonomous Dialog).
    const handleSelect = useCallback((model) => {
        if (config) {
            config.setModel(model);
            const event = new ModelSlashCommandEvent(model);
            logModelSlashCommand(config, event);
        }
        onClose();
    }, [config, onClose]);
    const header = config?.getPreviewFeatures()
        ? 'Gemini 3 is now enabled.'
        : 'Gemini 3 is now available.';
    const subheader = config?.getPreviewFeatures()
        ? `To disable Gemini 3, disable "Preview features" in /settings.\nLearn more at https://goo.gle/enable-preview-features\n\nWhen you select Auto or Pro, Gemini CLI will attempt to use ${PREVIEW_GEMINI_MODEL} first, before falling back to ${DEFAULT_GEMINI_MODEL}.`
        : `To use Gemini 3, enable "Preview features" in /settings.\nLearn more at https://goo.gle/enable-preview-features`;
    return (_jsxs(Box, { borderStyle: "round", borderColor: theme.border.default, flexDirection: "column", padding: 1, width: "100%", children: [_jsx(Text, { bold: true, children: "Select Model" }), _jsxs(Box, { marginTop: 1, marginBottom: 1, flexDirection: "column", children: [_jsx(Gradient, { colors: theme.ui.gradient, children: _jsx(Text, { children: header }) }), _jsx(Text, { children: subheader })] }), _jsx(Box, { marginTop: 1, children: _jsx(DescriptiveRadioButtonSelect, { items: options, onSelect: handleSelect, initialIndex: initialIndex, showNumbers: true }) }), _jsx(Box, { marginTop: 1, flexDirection: "column", children: _jsx(Text, { color: theme.text.secondary, children: 'To use a specific Gemini model on startup, use the --model flag.' }) }), _jsx(Box, { marginTop: 1, flexDirection: "column", children: _jsx(Text, { color: theme.text.secondary, children: "(Press Esc to close)" }) })] }));
}
//# sourceMappingURL=ModelDialog.js.map