#!/usr/bin/env python3
"""
Export localization strings from Localization.lua for CurseForge import.

Parses the Lua file, extracts L["KEY"] = "VALUE" assignments per locale,
and outputs them in CurseForge's import format (KEY=Value, one per line).

Usage:
  python3 scripts/export_localization.py                    # Print summary
  python3 scripts/export_localization.py --export           # Write .txt files to dist/localization/
  python3 scripts/export_localization.py --upload           # Upload to CurseForge (needs CF_API_KEY env)
"""

import os
import re
import sys
import json

LOCALIZATION_FILE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "QuickRoute", "Localization.lua"
)

# CurseForge project ID
CF_PROJECT_ID = "1461133"

# Map of GetLocale() values to CurseForge locale names
LOCALE_MAP = {
    "enUS": "enUS",
    "deDE": "deDE",
    "frFR": "frFR",
    "esES": "esES",
    "esMX": "esMX",
    "ptBR": "ptBR",
    "ruRU": "ruRU",
    "koKR": "koKR",
    "zhCN": "zhCN",
    "zhTW": "zhTW",
    "itIT": "itIT",
}

# Pattern to match L["KEY"] = "VALUE" or L["KEY"] = 'VALUE'
L_PATTERN = re.compile(
    r'^\s*L\["([^"]+)"\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*$'
    r'|'
    r"^\s*L\[\"([^\"]+)\"\]\s*=\s*'((?:[^'\\]|\\.)*)'\s*$"
)

# Any line that assigns a localization key, whether or not the value parses.
# Used to turn an unreadable value into an error instead of a silent skip.
KEY_PREFIX = re.compile(r'^\s*L\["[^"]+"\]\s*=')

# Pattern to detect locale blocks
LOCALE_START = re.compile(
    r'(?:if|elseif)\s+(?:GetLocale\(\)|esLocale)\s*==\s*"(\w+)"'
)

# Any conditional comparing something to a known locale code is a locale block
# header. LOCALE_START understands only two spellings of the left-hand side and
# only double quotes -- both Lua-legal alternatives exist, and Localization.lua
# already hoists one comparison into a local (esLocale), which is why that name
# is special-cased above. A header it does not match is skipped silently, and
# the block's phrases are then attributed to whatever current_locale happens to
# be: "enUS" right after an `end`. enUS is the only locale uploaded with
# missing-phrase-handling DeletePhrase, so that silent misfiling would overwrite
# the authoritative source phrases with another language and exit 0.
LOCALE_HEADER_HINT = re.compile(
    r'(?:if|elseif)\s+[\w().]+\s*==\s*[\'"](\w{4})[\'"]'
)

# Sanity floor for the enUS upload. Not an exact count -- it exists so that a
# parser that suddenly reads almost nothing cannot delete the phrase set.
MIN_ENUS_PHRASES = 200


def parse_localization(filepath):
    """Parse Localization.lua and return {locale: {key: value}} dict."""
    locales = {}
    current_locale = "enUS"
    locales[current_locale] = {}

    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            # Check for locale block start
            m = LOCALE_START.search(line)
            if m:
                current_locale = m.group(1)
                if current_locale not in locales:
                    locales[current_locale] = {}
                continue

            hint = LOCALE_HEADER_HINT.search(line)
            if hint and hint.group(1) in LOCALE_MAP:
                raise ValueError(
                    "Locale block header in %s that the parser cannot read:\n"
                    "  %s\n"
                    "Its phrases would be filed under %r instead of %r."
                    % (filepath, line.rstrip(), current_locale, hint.group(1))
                )

            # Check for end of locale block
            if line.strip() == "end":
                current_locale = "enUS"  # Reset (won't match more enUS keys though)
                continue

            # Check for L["KEY"] = "VALUE"
            m = L_PATTERN.match(line)
            if m:
                # Pick the value by which key group matched, so an empty string
                # survives: `m.group(2) or m.group(4)` turned "" into the other
                # group's None and silently dropped the entry.
                if m.group(1) is not None:
                    key, value = m.group(1), m.group(2)
                else:
                    key, value = m.group(3), m.group(4)
                # Unescape Lua string escapes
                value = value.replace('\\"', '"').replace("\\'", "'")
                locales[current_locale][key] = value
            elif KEY_PREFIX.match(line):
                # An assignment the value pattern could not read. Silently
                # skipping it is dangerous here: the enUS upload is configured
                # to delete phrases it does not send, so a dropped line removes
                # a translation on CurseForge.
                raise ValueError(
                    "Unparsable localization line in %s:\n  %s" % (filepath, line.rstrip())
                )

    # esES and esMX share the same block — duplicate if only one found
    if "esES" in locales and "esMX" not in locales:
        locales["esMX"] = dict(locales["esES"])
    elif "esMX" in locales and "esES" not in locales:
        locales["esES"] = dict(locales["esMX"])

    return locales


def check_parse(locales, filepath):
    """Refuse to upload a parse that lost or misfiled a locale."""
    found = set(locales)
    expected = set(LOCALE_MAP)
    if found != expected:
        raise ValueError(
            "Locale set from %s does not match LOCALE_MAP.\n"
            "  missing: %s\n"
            "  unexpected: %s"
            % (filepath, sorted(expected - found) or "none",
               sorted(found - expected) or "none")
        )
    count = len(locales["enUS"])
    if count < MIN_ENUS_PHRASES:
        raise ValueError(
            "Only %d enUS phrases parsed from %s, expected at least %d. "
            "enUS uploads with DeletePhrase, so this would delete the rest."
            % (count, filepath, MIN_ENUS_PHRASES)
        )


def to_cf_format(strings):
    """Convert {key: value} dict to CurseForge Lua additive table format."""
    lines = []
    for key in sorted(strings.keys()):
        # Escape backslashes and double quotes in values for Lua string
        value = strings[key].replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'L["{key}"] = "{value}"')
    return "\n".join(lines)


def print_summary(locales):
    """Print a summary of localization coverage."""
    en_keys = set(locales.get("enUS", {}).keys())
    total = len(en_keys)
    print(f"Localization summary ({total} phrases in enUS):\n")
    print(f"  {'Locale':<8} {'Phrases':>8} {'Coverage':>10}")
    print(f"  {'------':<8} {'-------':>8} {'--------':>10}")
    for locale in sorted(locales.keys()):
        count = len(locales[locale])
        if locale == "enUS":
            pct = 100.0
        else:
            pct = (count / total * 100) if total > 0 else 0
        print(f"  {locale:<8} {count:>8} {pct:>9.1f}%")


def export_files(locales):
    """Write locale files to dist/localization/."""
    dist_dir = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "dist", "localization"
    )
    os.makedirs(dist_dir, exist_ok=True)
    for locale, strings in sorted(locales.items()):
        filepath = os.path.join(dist_dir, f"{locale}.txt")
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(to_cf_format(strings))
        print(f"  Wrote {filepath} ({len(strings)} phrases)")


def upload_to_curseforge(locales):
    """Upload localization strings to CurseForge via their import API."""
    import urllib.request
    import urllib.parse

    api_key = os.environ.get("CF_API_KEY")
    if not api_key:
        print("ERROR: CF_API_KEY environment variable not set", file=sys.stderr)
        sys.exit(1)

    url = f"https://wow.curseforge.com/api/projects/{CF_PROJECT_ID}/localization/import"

    failures = []

    for locale in sorted(locales.keys()):
        strings = locales[locale]
        if not strings:
            continue

        cf_locale = LOCALE_MAP.get(locale, locale)
        is_default = (locale == "enUS")

        metadata = json.dumps({
            "language": cf_locale,
            "namespace": "",
            "format-type": "lua_additive_table",
            "missing-phrase-handling": "DeletePhrase" if is_default else "DoNothing",
        })

        localizations = to_cf_format(strings)

        # Build multipart form data
        boundary = "----PythonFormBoundary7MA4YWxkTrZu0gW"
        body = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="metadata"\r\n\r\n'
            f"{metadata}\r\n"
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="localizations"\r\n\r\n'
            f"{localizations}\r\n"
            f"--{boundary}--\r\n"
        )

        req = urllib.request.Request(
            url,
            data=body.encode("utf-8"),
            headers={
                "X-Api-Token": api_key,
                "Content-Type": f"multipart/form-data; boundary={boundary}",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(req) as resp:
                status = resp.status
                print(f"  {cf_locale}: {len(strings)} phrases uploaded (HTTP {status})")
        except urllib.error.HTTPError as e:
            print(f"  {cf_locale}: FAILED (HTTP {e.code}: {e.read().decode()})",
                  file=sys.stderr)
            failures.append(cf_locale)

    return failures


def main():
    locales = parse_localization(LOCALIZATION_FILE)

    if "--upload" in sys.argv:
        check_parse(locales, LOCALIZATION_FILE)
        print("Uploading localization to CurseForge...")
        # A failed upload has to reach the exit code. Printing to stderr and
        # returning 0 made the release workflow and the manual localization
        # workflow both report success while nothing had been uploaded.
        failures = upload_to_curseforge(locales)
        if failures:
            print(f"Localization upload failed for: {', '.join(failures)}",
                  file=sys.stderr)
            sys.exit(1)
    elif "--export" in sys.argv:
        print("Exporting localization files...")
        export_files(locales)
    else:
        print_summary(locales)


if __name__ == "__main__":
    main()
