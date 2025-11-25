import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Box, Text } from 'ink';
import { useUIState } from '../../contexts/UIStateContext.js';
import { ExtensionUpdateState } from '../../state/extensions.js';
import { debugLogger } from '@google/gemini-cli-core';
export const ExtensionsList = ({ extensions }) => {
    const { extensionsUpdateState } = useUIState();
    if (extensions.length === 0) {
        return _jsx(Text, { children: "No extensions installed." });
    }
    return (_jsxs(Box, { flexDirection: "column", marginTop: 1, marginBottom: 1, children: [_jsx(Text, { children: "Installed extensions:" }), _jsx(Box, { flexDirection: "column", paddingLeft: 2, children: extensions.map((ext) => {
                    const state = extensionsUpdateState.get(ext.name);
                    const isActive = ext.isActive;
                    const activeString = isActive ? 'active' : 'disabled';
                    const activeColor = isActive ? 'green' : 'grey';
                    let stateColor = 'gray';
                    const stateText = state || 'unknown state';
                    switch (state) {
                        case ExtensionUpdateState.CHECKING_FOR_UPDATES:
                        case ExtensionUpdateState.UPDATING:
                            stateColor = 'cyan';
                            break;
                        case ExtensionUpdateState.UPDATE_AVAILABLE:
                        case ExtensionUpdateState.UPDATED_NEEDS_RESTART:
                            stateColor = 'yellow';
                            break;
                        case ExtensionUpdateState.ERROR:
                            stateColor = 'red';
                            break;
                        case ExtensionUpdateState.UP_TO_DATE:
                        case ExtensionUpdateState.NOT_UPDATABLE:
                        case ExtensionUpdateState.UPDATED:
                            stateColor = 'green';
                            break;
                        case undefined:
                            break;
                        default:
                            debugLogger.warn(`Unhandled ExtensionUpdateState ${state}`);
                            break;
                    }
                    return (_jsx(Box, { children: _jsxs(Text, { children: [_jsx(Text, { color: "cyan", children: `${ext.name} (v${ext.version})` }), _jsx(Text, { color: activeColor, children: ` - ${activeString}` }), _jsx(Text, { color: stateColor, children: ` (${stateText})` })] }) }, ext.name));
                }) })] }));
};
//# sourceMappingURL=ExtensionsList.js.map