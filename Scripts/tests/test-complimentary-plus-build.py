#!/usr/bin/env python3
"""Hermetic checks for the permanent-entitlement grant's build boundary."""
import json
import os
from pathlib import Path
import subprocess
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
GRANT = "COMPLIMENTARY_PLUS_BETA_GRANT"
MARKER = "NEXTSEASON_BETA_COMPLIMENTARY_CONFIGURATION"


class ComplimentaryPlusBuildTests(unittest.TestCase):
    def guard(self, configuration, conditions="", other_flags=""):
        return subprocess.run(
            ["/bin/sh", str(ROOT / "Scripts/verify-complimentary-plus-build.sh")],
            env={**os.environ, "CONFIGURATION": configuration,
                 "SWIFT_ACTIVE_COMPILATION_CONDITIONS": conditions,
                 "OTHER_SWIFT_FLAGS": other_flags},
            capture_output=True, text=True,
        )

    def test_normal_and_unknown_configurations_reject_injected_flags(self):
        for configuration in ("Debug", "Release", "Profile", "FutureBeta", ""):
            self.assertEqual(self.guard(configuration, "DEBUG").returncode, 0)
            for flag in (GRANT, MARKER):
                for conditions, other in ((flag, ""), ("DEBUG " + flag, ""),
                                          ("", "-D" + flag), ("", "-D " + flag), ("", '-D"' + flag + '"'),
                                          ("", "-D'" + flag + "'"),
                                          ("", "-O -D " + flag + " -whole-module-optimization")):
                    with self.subTest(configuration=configuration, conditions=conditions, other=other):
                        result = self.guard(configuration, conditions, other)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn("error: Complimentary Plus", result.stderr)
        # Both injected markers must still fail in Release.
        self.assertNotEqual(self.guard("Release", GRANT + " " + MARKER).returncode, 0)

    def test_dedicated_beta_configuration_is_allowed(self):
        self.assertEqual(self.guard("BetaComplimentary", GRANT + " " + MARKER).returncode, 0)

    def test_dedicated_beta_requires_both_flags(self):
        for conditions, other in (("", ""), (GRANT, ""), (MARKER, ""),
                                  ("", "-D" + GRANT), ("", "-D " + MARKER),
                                  (GRANT + " " + MARKER + "_DISABLED", ""),
                                  (GRANT + "_DISABLED " + MARKER, "")):
            with self.subTest(conditions=conditions, other=other):
                result = self.guard("BetaComplimentary", conditions, other)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("error: BetaComplimentary requires both", result.stderr)

    def test_dedicated_beta_accepts_both_flags_across_flag_sources(self):
        for conditions, other in ((GRANT, "-D " + MARKER),
                                  (MARKER, "-D" + GRANT),
                                  ("", '-D"' + GRANT + '" -D ' + MARKER)):
            with self.subTest(conditions=conditions, other=other):
                self.assertEqual(self.guard("BetaComplimentary", conditions, other).returncode, 0)

    def test_project_and_archive_schemes_isolate_grant(self):
        project = json.loads(subprocess.check_output([
            "/usr/bin/plutil", "-convert", "json", "-o", "-",
            str(ROOT / "NextSeason.xcodeproj/project.pbxproj"),
        ]))
        objects = project["objects"]
        lists = [obj for obj in objects.values() if obj.get("isa") == "XCConfigurationList"]
        self.assertEqual(len(lists), 4)
        beta_exists = any(obj.get("isa") == "XCBuildConfiguration" and obj.get("name") == "BetaComplimentary"
                          for obj in objects.values())
        expected = {"Debug", "Release", "Profile"}
        if beta_exists:
            expected.add("BetaComplimentary")
        for configuration_list in lists:
            configs = {objects[key]["name"]: objects[key]
                       for key in configuration_list["buildConfigurations"]}
            self.assertEqual(set(configs), expected)
            self.assertEqual(configuration_list["defaultConfigurationName"], "Release")
            # All signing, bundle identity, optimization and test settings match Release.
            if beta_exists:
                self.assertEqual(configs["BetaComplimentary"]["buildSettings"], configs["Release"]["buildSettings"])
            if "baseConfigurationReferenceRelativePath" in configs["Release"]:
                self.assertEqual(configs["Release"]["baseConfigurationReferenceRelativePath"], "Base.xcconfig")
                if beta_exists:
                    self.assertEqual(configs["BetaComplimentary"]["baseConfigurationReferenceRelativePath"], "BetaComplimentary.xcconfig")
            for name in ("Debug", "Release", "Profile"):
                self.assertNotIn(GRANT, json.dumps(configs[name]))
                self.assertNotIn(MARKER, json.dumps(configs[name]))

        base = (ROOT / "Config/Base.xcconfig").read_text()
        self.assertNotIn(GRANT, base)
        self.assertNotIn(MARKER, base)
        beta_config = ROOT / "Config/BetaComplimentary.xcconfig"
        schemes = ROOT / "NextSeason.xcodeproj/xcshareddata/xcschemes"
        beta_scheme_path = schemes / "NextSeason - Final Complimentary Beta.xcscheme"
        normal = ET.parse(schemes / "NextSeason.xcscheme").getroot()
        self.assertEqual(normal.find("ArchiveAction").get("buildConfiguration"), "Release")
        if beta_exists:
            beta = beta_config.read_text()
            self.assertIn('#include "Base.xcconfig"', beta)
            self.assertIn(GRANT, beta)
            self.assertIn(MARKER, beta)
            beta_scheme = ET.parse(beta_scheme_path).getroot()
            self.assertEqual(beta_scheme.find("ArchiveAction").get("buildConfiguration"), "BetaComplimentary")
            self.assertEqual(normal.find("BuildAction").find("BuildActionEntries")[0].find("BuildableReference").attrib,
                             beta_scheme.find("BuildAction").find("BuildActionEntries")[0].find("BuildableReference").attrib)
        else:
            # The same checks remain usable after the documented beta cleanup.
            self.assertFalse(beta_config.exists())
            self.assertFalse(beta_scheme_path.exists())

        app = next(obj for obj in objects.values()
                   if obj.get("isa") == "PBXNativeTarget" and obj.get("name") == "NextSeason")
        guard = objects[app["buildPhases"][0]]
        self.assertEqual(guard["isa"], "PBXShellScriptBuildPhase")
        self.assertEqual(str(guard["alwaysOutOfDate"]), "1")
        self.assertEqual(str(guard["runOnlyForDeploymentPostprocessing"]), "0")
        self.assertIn("$(SRCROOT)/Scripts/verify-complimentary-plus-build.sh", guard["inputPaths"])
        self.assertIn("verify-complimentary-plus-build.sh", guard["shellScript"])


if __name__ == "__main__":
    unittest.main()
