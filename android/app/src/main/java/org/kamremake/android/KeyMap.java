package org.kamremake.android;

import android.view.KeyEvent;

/** Android key codes -> Windows virtual key codes used by the game */
final class KeyMap {
    static int toVK(int keyCode) {
        if (keyCode >= KeyEvent.KEYCODE_A && keyCode <= KeyEvent.KEYCODE_Z) return 'A' + (keyCode - KeyEvent.KEYCODE_A);
        if (keyCode >= KeyEvent.KEYCODE_0 && keyCode <= KeyEvent.KEYCODE_9) return '0' + (keyCode - KeyEvent.KEYCODE_0);
        if (keyCode >= KeyEvent.KEYCODE_F1 && keyCode <= KeyEvent.KEYCODE_F12) return 112 + (keyCode - KeyEvent.KEYCODE_F1);
        if (keyCode >= KeyEvent.KEYCODE_NUMPAD_0 && keyCode <= KeyEvent.KEYCODE_NUMPAD_9) return 96 + (keyCode - KeyEvent.KEYCODE_NUMPAD_0);
        switch (keyCode) {
            case KeyEvent.KEYCODE_DEL: return 8;
            case KeyEvent.KEYCODE_TAB: return 9;
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER: return 13;
            case KeyEvent.KEYCODE_SHIFT_LEFT:
            case KeyEvent.KEYCODE_SHIFT_RIGHT: return 16;
            case KeyEvent.KEYCODE_CTRL_LEFT:
            case KeyEvent.KEYCODE_CTRL_RIGHT: return 17;
            case KeyEvent.KEYCODE_ALT_LEFT:
            case KeyEvent.KEYCODE_ALT_RIGHT: return 18;
            case KeyEvent.KEYCODE_BREAK: return 19;
            case KeyEvent.KEYCODE_CAPS_LOCK: return 20;
            case KeyEvent.KEYCODE_ESCAPE: return 27;
            case KeyEvent.KEYCODE_SPACE: return 32;
            case KeyEvent.KEYCODE_PAGE_UP: return 33;
            case KeyEvent.KEYCODE_PAGE_DOWN: return 34;
            case KeyEvent.KEYCODE_MOVE_END: return 35;
            case KeyEvent.KEYCODE_MOVE_HOME: return 36;
            case KeyEvent.KEYCODE_DPAD_LEFT: return 37;
            case KeyEvent.KEYCODE_DPAD_UP: return 38;
            case KeyEvent.KEYCODE_DPAD_RIGHT: return 39;
            case KeyEvent.KEYCODE_DPAD_DOWN: return 40;
            case KeyEvent.KEYCODE_INSERT: return 45;
            case KeyEvent.KEYCODE_FORWARD_DEL: return 46;
            case KeyEvent.KEYCODE_NUMPAD_MULTIPLY: return 106;
            case KeyEvent.KEYCODE_NUMPAD_ADD: return 107;
            case KeyEvent.KEYCODE_NUMPAD_SUBTRACT: return 109;
            case KeyEvent.KEYCODE_NUMPAD_DOT: return 110;
            case KeyEvent.KEYCODE_NUMPAD_DIVIDE: return 111;
            case KeyEvent.KEYCODE_SEMICOLON: return 186;
            case KeyEvent.KEYCODE_EQUALS: return 187;
            case KeyEvent.KEYCODE_COMMA: return 188;
            case KeyEvent.KEYCODE_MINUS: return 189;
            case KeyEvent.KEYCODE_PERIOD: return 190;
            case KeyEvent.KEYCODE_SLASH: return 191;
            case KeyEvent.KEYCODE_GRAVE: return 192;
            case KeyEvent.KEYCODE_LEFT_BRACKET: return 219;
            case KeyEvent.KEYCODE_BACKSLASH: return 220;
            case KeyEvent.KEYCODE_RIGHT_BRACKET: return 221;
            case KeyEvent.KEYCODE_APOSTROPHE: return 222;
            default: return 0;
        }
    }

    static int shiftFlags(KeyEvent e) {
        int s = 0;
        if (e.isShiftPressed()) s |= 1;
        if (e.isCtrlPressed()) s |= 2;
        if (e.isAltPressed()) s |= 4;
        return s;
    }

    private KeyMap() {}
}
