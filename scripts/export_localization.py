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

# Pattern to detect locale blocks
LOCALE_START = re.compile(
    r'(?:if|elseif)\s+(?:GetLocale\(\)|esLocale)\s*==\s*"(\w+)"'
)


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

            # Check for end of locale block
            if line.strip() == "end":
                current_locale = "enUS"  # Reset (won't match more enUS keys though)
                continue

            # Check for L["KEY"] = "VALUE"
            m = L_PATTERN.match(line)
            if m:
                key = m.group(1) or m.group(3)
                value = m.group(2) or m.group(4)
                if key and value is not None:
                    # Unescape Lua string escapes
                    value = value.replace('\\"', '"').replace("\\'", "'")
                    locales[current_locale][key] = value

    # esES and esMX share the same block — duplicate if only one found
    if "esES" in locales and "esMX" not in locales:
        locales["esMX"] = dict(locales["esES"])
    elif "esMX" in locales and "esES" not in locales:
        locales["esES"] = dict(locales["esMX"])

    return locales


def to_cf_format(strings):
    """Convert {key: value} dict to CurseForge import format."""
    lines = []
    for key in sorted(strings.keys()):
        # CF format: KEY=Value (no quotes)
        lines.append(f"{key}={strings[key]}")
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

    for locale in sorted(locales.keys()):
        strings = locales[locale]
        if not strings:
            continue

        cf_locale = LOCALE_MAP.get(locale, locale)
        is_default = (locale == "enUS")

        metadata = json.dumps({
            "language": cf_locale,
            "namespace": "",
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


def main():
    locales = parse_localization(LOCALIZATION_FILE)

    if "--upload" in sys.argv:
        print("Uploading localization to CurseForge...")
        upload_to_curseforge(locales)
    elif "--export" in sys.argv:
        print("Exporting localization files...")
        export_files(locales)
    else:
        print_summary(locales)


if __name__ == "__main__":
    main()
