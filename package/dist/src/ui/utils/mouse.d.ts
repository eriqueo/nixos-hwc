/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
export type MouseEventName = 'left-press' | 'left-release' | 'right-press' | 'right-release' | 'middle-press' | 'middle-release' | 'scroll-up' | 'scroll-down' | 'scroll-left' | 'scroll-right' | 'move';
export interface MouseEvent {
    name: MouseEventName;
    col: number;
    row: number;
    shift: boolean;
    meta: boolean;
    ctrl: boolean;
    button: 'left' | 'middle' | 'right' | 'none';
}
export type MouseHandler = (event: MouseEvent) => void | boolean;
export declare function getMouseEventName(buttonCode: number, isRelease: boolean): MouseEventName | null;
export declare function parseSGRMouseEvent(buffer: string): {
    event: MouseEvent;
    length: number;
} | null;
export declare function parseX11MouseEvent(buffer: string): {
    event: MouseEvent;
    length: number;
} | null;
export declare function parseMouseEvent(buffer: string): {
    event: MouseEvent;
    length: number;
} | null;
export declare function isIncompleteMouseSequence(buffer: string): boolean;
export declare function enableMouseEvents(): void;
export declare function disableMouseEvents(): void;
