"""Pure parts of tests/tools/uinput_keys.py. Never opens /dev/uinput."""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
import uinput_keys  # noqa: E402


class KeycodeTest(unittest.TestCase):
    def test_modifiers(self):
        self.assertEqual(uinput_keys.keycode("LEFTCTRL"), 29)
        self.assertEqual(uinput_keys.keycode("LEFTALT"), 56)
        self.assertEqual(uinput_keys.keycode("LEFTSHIFT"), 42)
        self.assertEqual(uinput_keys.keycode("LEFTMETA"), 125)

    def test_digits_letters_arrows(self):
        self.assertEqual(uinput_keys.keycode("1"), 2)
        self.assertEqual(uinput_keys.keycode("3"), 4)
        self.assertEqual(uinput_keys.keycode("0"), 11)
        self.assertEqual(uinput_keys.keycode("Q"), 16)
        self.assertEqual(uinput_keys.keycode("LEFT"), 105)
        self.assertEqual(uinput_keys.keycode("RIGHT"), 106)

    def test_case_and_prefix_insensitive(self):
        self.assertEqual(uinput_keys.keycode("key_leftctrl"), 29)
        self.assertEqual(uinput_keys.keycode("left"), 105)

    def test_unknown_key(self):
        with self.assertRaises(ValueError):
            uinput_keys.keycode("NOSUCHKEY")


class ParseArgsTest(unittest.TestCase):
    def test_returns_codes_in_order(self):
        self.assertEqual(uinput_keys.parse_args(["LEFTCTRL", "LEFTALT", "RIGHT"]), [29, 56, 106])

    def test_empty_is_error(self):
        with self.assertRaises(ValueError):
            uinput_keys.parse_args([])

    def test_unknown_is_error(self):
        with self.assertRaises(ValueError):
            uinput_keys.parse_args(["LEFTCTRL", "BOGUS"])


class MainTest(unittest.TestCase):
    def test_main_calls_press_with_argv(self):
        with mock.patch.object(uinput_keys, "press") as press:
            self.assertEqual(uinput_keys.main(["LEFTCTRL", "3"]), 0)
        press.assert_called_once_with("LEFTCTRL", "3")

    def test_main_rejects_bad_args_without_pressing(self):
        with mock.patch.object(uinput_keys, "press") as press, mock.patch("sys.stderr"):
            self.assertEqual(uinput_keys.main(["BOGUS"]), 2)
        press.assert_not_called()


class EventPackingTest(unittest.TestCase):
    def test_event_sequence_presses_then_releases_in_reverse(self):
        seq = uinput_keys.event_sequence([29, 4])
        # (type, code, value): ctrl down, 3 down, SYN, 3 up, ctrl up, SYN
        self.assertEqual(seq, [(1, 29, 1), (1, 4, 1), (0, 0, 0), (1, 4, 0), (1, 29, 0), (0, 0, 0)])

    def test_setup_struct_size_matches_ioctl(self):
        self.assertEqual(len(uinput_keys.setup_struct("rice-test")), 92)


if __name__ == "__main__":
    unittest.main()
