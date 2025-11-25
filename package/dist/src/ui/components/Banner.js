import { jsx as _jsx } from "react/jsx-runtime";
/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import { Box, Text } from 'ink';
import Gradient from 'ink-gradient';
import { theme } from '../semantic-colors.js';
export const Banner = ({ bannerText, color, width }) => {
    const gradient = theme.ui.gradient;
    return (_jsx(Box, { flexDirection: "column", borderStyle: "round", borderColor: color, width: width, paddingLeft: 1, paddingRight: 1, children: _jsx(Gradient, { colors: gradient, children: _jsx(Text, { children: bannerText }) }) }));
};
//# sourceMappingURL=Banner.js.map