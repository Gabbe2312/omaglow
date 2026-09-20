"""Tests for bin/omaglow. Hardware calls are replaced with recorders.

    python3 -m unittest discover tests
"""

import importlib.machinery
import importlib.util
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parent.parent / "bin" / "omaglow"

GPU = "openrgb:GPU"
FANS = "openrgb:Fans"
RAM = "fury"

THEME_A = {"accent": "#12a870", "foreground": "#dcd6d6", "red": "#b39a98"}
THEME_B = {"accent": "#e05070", "foreground": "#d8d4b4", "red": "#aa3030"}


def load():
    loader = importlib.machinery.SourceFileLoader("omaglow", str(HELPER))
    spec = importlib.util.spec_from_loader("omaglow", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class Rig(unittest.TestCase):
    def setUp(self):
        self.o = load()
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.o.CONFIG_DIR = root / "config"
        self.o.CONFIG_FILE = root / "config" / "config.json"
        self.o.CACHE_DIR = root / "cache"
        self.theme = "theme-a"
        self.o.current_theme = lambda: self.theme
        self.palette = dict(THEME_A)
        self.sent = {}
        self.o.theme_colors = lambda: dict(self.palette)
        self.o.all_devices = lambda wait=3, fresh=False: [
            {"id": GPU, "name": "GPU", "type": "GPU", "index": 0, "mode": "Direct"},
            {"id": FANS, "name": "Fans", "type": "Cooler", "index": 1, "mode": "Direct"},
            {"id": RAM, "name": "RAM", "type": "DRAM", "bus": "8", "sticks": [0x61]},
        ]
        self.o.openrgb_client = self.record_openrgb
        self.o.fury_apply = lambda bus, sticks, rgb, brightness: self.sent.__setitem__(RAM, rgb)
        # skip LED correction so colours compare as chosen
        self.o.led_color = lambda color, brightness, vivid: color.lstrip("#").upper()

    def tearDown(self):
        self.tmp.cleanup()

    def record_openrgb(self, *args):
        ids = {0: GPU, 1: FANS}
        args = list(args)
        for i, arg in enumerate(args):
            if arg == "-d":
                self.sent[ids[int(args[i + 1])]] = args[args.index("-c", i) + 1]
        return ""

    def lit(self):
        self.sent = {}
        self.o.apply(self.o.load_config())
        return {k: "#" + v.lower() for k, v in self.sent.items()}


class Colours(Rig):
    def test_all_sets_every_device(self):
        self.o.set_value("color", "#ff0000")
        self.assertEqual(self.lit(), {GPU: "#ff0000", FANS: "#ff0000", RAM: "#ff0000"})

    def test_single_device_override(self):
        self.o.set_value("color", "#ff0000")
        self.o.set_device_color(RAM, "#0000ff")
        self.assertEqual(self.lit(), {GPU: "#ff0000", FANS: "#ff0000", RAM: "#0000ff"})

    def test_all_clears_overrides(self):
        self.o.set_device_color(RAM, "#0000ff")
        self.o.set_value("color", "#00ff00")
        self.assertEqual(self.lit(), {GPU: "#00ff00", FANS: "#00ff00", RAM: "#00ff00"})
        self.assertEqual(self.o.load_config()["colors"], {})

    def test_disabled_device_is_skipped(self):
        self.o.set_device(FANS, "off")
        self.assertNotIn(FANS, self.lit())
        self.o.set_device(FANS, "on")
        self.assertIn(FANS, self.lit())


class Off(Rig):
    def test_single_device_off(self):
        self.o.set_value("color", "#ff0000")
        self.o.set_device_color(RAM, "#000000")
        self.assertEqual(self.lit(), {GPU: "#ff0000", FANS: "#ff0000", RAM: "#000000"})

    def test_off_survives_theme_change(self):
        self.o.set_value("themeKey", "accent")
        self.o.set_device_color(FANS, "#000000")
        self.palette = dict(THEME_B)
        self.assertEqual(self.lit(), {GPU: "#e05070", FANS: "#000000", RAM: "#e05070"})

    def test_legacy_off_key(self):
        self.o.save_config(dict(self.o.DEFAULTS, follow=True, themeKeys={RAM: "off"}))
        self.assertEqual(self.lit()[RAM], "#000000")

    def test_black_is_not_corrected(self):
        self.assertEqual(load().led_color("#000000", 100, True), "000000")


class FixedWhileFollowing(Rig):
    def test_fixed_colour_survives_theme_change(self):
        self.o.set_value("themeKey", "accent")
        self.o.set_device_color(RAM, "#ff00ff")
        self.assertTrue(self.o.load_config()["follow"])
        self.assertEqual(self.lit(), {GPU: "#12a870", FANS: "#12a870", RAM: "#ff00ff"})
        self.palette = dict(THEME_B)
        self.assertEqual(self.lit(), {GPU: "#e05070", FANS: "#e05070", RAM: "#ff00ff"})

    def test_fixed_colour_not_used_in_own_mode(self):
        self.o.set_value("color", "#ffffff")
        self.o.set_value("themeKey", "accent")
        self.o.set_device_color(RAM, "#ff00ff")
        self.o.set_value("follow", "off")
        self.assertEqual(self.lit(), {GPU: "#ffffff", FANS: "#ffffff", RAM: "#ffffff"})

    def test_fixed_colour_for_all_in_follow_mode(self):
        self.o.set_value("themeKey", "accent")
        self.o.set_device_color(RAM, "theme:red")
        self.o.set_value("color", "#00ffff")
        self.assertTrue(self.o.load_config()["follow"])
        self.assertEqual(self.lit(), {GPU: "#00ffff", FANS: "#00ffff", RAM: "#00ffff"})
        self.o.set_device_color(GPU, "theme:accent")
        self.palette = dict(THEME_B)
        self.assertEqual(self.lit(), {GPU: "#e05070", FANS: "#00ffff", RAM: "#00ffff"})


class Theme(Rig):
    def test_pattern_survives_theme_change(self):
        self.o.set_value("themeKey", "foreground")
        self.o.set_device_color(RAM, "theme:accent")
        self.assertEqual(self.lit(), {GPU: "#dcd6d6", FANS: "#dcd6d6", RAM: "#12a870"})
        self.palette = dict(THEME_B)
        self.assertEqual(self.lit(), {GPU: "#d8d4b4", FANS: "#d8d4b4", RAM: "#e05070"})

    def test_all_clears_theme_overrides(self):
        self.o.set_device_color(RAM, "theme:accent")
        self.o.set_value("themeKey", "red")
        self.assertEqual(self.lit(), {GPU: "#b39a98", FANS: "#b39a98", RAM: "#b39a98"})

    def test_modes_keep_separate_patterns(self):
        self.o.set_value("color", "#ffffff")
        self.o.set_device_color(GPU, "#ff0000")
        self.o.set_value("themeKey", "foreground")
        self.o.set_device_color(RAM, "theme:accent")
        self.assertEqual(self.lit(), {GPU: "#dcd6d6", FANS: "#dcd6d6", RAM: "#12a870"})
        self.o.set_value("follow", "off")
        self.assertEqual(self.lit(), {GPU: "#ff0000", FANS: "#ffffff", RAM: "#ffffff"})
        self.o.set_value("follow", "on")
        self.assertEqual(self.lit(), {GPU: "#dcd6d6", FANS: "#dcd6d6", RAM: "#12a870"})

    def test_missing_key_falls_back_to_shared(self):
        self.o.set_value("themeKey", "foreground")
        self.o.set_device_color(RAM, "theme:purple")
        self.assertEqual(self.lit()[RAM], "#dcd6d6")

    def test_status_reports_device_keys(self):
        self.o.systemctl = lambda *a: type("R", (), {"stdout": ""})()
        self.o.set_value("themeKey", "foreground")
        self.o.set_device_color(RAM, "theme:accent")
        report = {d["id"]: d for d in self.o.status()["devices"]}
        self.assertEqual(report[RAM]["themeKey"], "accent")
        self.assertTrue(report[RAM]["own"])
        self.assertEqual(report[GPU]["themeKey"], "foreground")
        self.assertFalse(report[GPU]["own"])


class Profiles(Rig):
    def switch(self, slug, palette):
        self.theme, self.palette = slug, dict(palette)

    def test_profile_applies_to_its_theme_only(self):
        self.o.set_value("themeKey", "foreground")
        self.switch("theme-b", THEME_B)
        self.o.set_value("themeKey", "accent")
        self.o.set_device_color(RAM, "theme:red")
        self.o.profile_command("save", "", "")
        self.o.set_value("follow", "on")
        self.switch("theme-a", THEME_A)
        self.o.set_value("themeKey", "foreground")
        self.assertEqual(self.lit(), {GPU: "#dcd6d6", FANS: "#dcd6d6", RAM: "#dcd6d6"})
        self.switch("theme-b", THEME_B)
        self.assertEqual(self.lit(), {GPU: "#e05070", FANS: "#e05070", RAM: "#aa3030"})

    def test_save_restores_general_pattern(self):
        self.o.set_value("themeKey", "foreground")
        self.switch("theme-b", THEME_B)
        self.lit()  # what the theme hook does
        self.o.set_value("themeKey", "accent")
        self.o.set_device_color(RAM, "theme:red")
        self.o.profile_command("save", "", "")
        self.assertEqual(self.lit(), {GPU: "#e05070", FANS: "#e05070", RAM: "#aa3030"})
        self.switch("theme-a", THEME_A)
        self.assertEqual(self.lit(), {GPU: "#dcd6d6", FANS: "#dcd6d6", RAM: "#dcd6d6"})

    def test_edits_go_to_active_profile(self):
        self.o.set_value("themeKey", "foreground")
        self.o.profile_command("save", "", "")
        self.o.set_device_color(RAM, "theme:accent")
        config = self.o.load_config()
        self.assertEqual(config["profiles"]["theme-a"]["themeKeys"], {RAM: "accent"})
        self.assertEqual(config["themeKeys"], {})

    def test_disabled_profile_is_kept(self):
        self.o.set_value("themeKey", "foreground")
        self.o.set_value("themeKey", "accent")
        self.o.profile_command("save", "", "")
        self.o.profile_command("use", "off", "")
        self.o.set_value("themeKey", "red")
        self.assertEqual(self.lit()[GPU], "#b39a98")
        self.o.profile_command("use", "on", "")
        self.assertEqual(self.lit()[GPU], "#12a870")

    def test_delete_falls_back_to_general(self):
        self.o.set_value("themeKey", "red")
        self.o.profile_command("save", "", "")
        self.o.set_value("themeKey", "accent")
        self.o.profile_command("delete", "", "")
        self.assertEqual(self.lit()[GPU], "#b39a98")

    def test_own_mode_ignores_profiles(self):
        self.o.set_value("themeKey", "accent")
        self.o.profile_command("save", "", "")
        self.o.set_value("follow", "off")
        self.o.set_value("color", "#ffffff")
        self.assertEqual(self.lit()[GPU], "#ffffff")


class Leds(unittest.TestCase):
    def setUp(self):
        self.o = load()

    def test_white_unchanged(self):
        self.assertEqual(self.o.led_color("#ffffff", 100, True), "FFFFFF")

    def test_brightness_scales(self):
        self.assertEqual(self.o.led_color("#ffffff", 50, False), "808080")

    def test_vivid_keeps_peak_channel(self):
        red, green, blue = (int(self.o.led_color("#12a870", 100, True)[i:i + 2], 16) for i in (0, 2, 4))
        self.assertEqual(green, 168)
        self.assertLess(blue, 112)
        self.assertLess(red, 18)


if __name__ == "__main__":
    unittest.main()
