#!/usr/bin/env python3
"""Static localization coverage check for app-authored Flutter UI copy."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
UI_PATHS = [
    *sorted((ROOT / "lib/screens").glob("*.dart")),
    *sorted((ROOT / "lib/widgets").glob("*.dart")),
    ROOT / "lib/main.dart",
]
VISIBLE_FIELDS = {
    "tooltip", "semanticsLabel", "labelText", "hintText", "helperText",
    "errorText", "prefixText", "suffixText", "title", "subtitle", "label",
    "message", "hint",
}


class Token:
    def __init__(self, kind, value, start, end):
        self.kind, self.value, self.start, self.end = kind, value, start, end


def skip_interpolation(source, index):
    depth = 1
    index += 1
    while index < len(source) and depth:
        if source.startswith("//", index):
            end = source.find("\n", index + 2)
            index = len(source) if end < 0 else end + 1
            continue
        if source.startswith("/*", index):
            end = source.find("*/", index + 2)
            index = len(source) if end < 0 else end + 2
            continue
        quote_pos = index + 1 if source[index:index + 1].lower() == "r" else index
        raw = quote_pos != index
        if quote_pos < len(source) and source[quote_pos] in "'\"":
            _, index = parse_string(source, quote_pos, raw)
            continue
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return index


def parse_string(source, quote_pos, raw=False):
    quote = source[quote_pos]
    triple = source.startswith(quote * 3, quote_pos)
    delimiter = quote * 3 if triple else quote
    index = quote_pos + len(delimiter)
    content_start = index
    while index < len(source):
        if not raw and source[index] == "\\":
            index += 2
            continue
        if not raw and source.startswith("${", index):
            index = skip_interpolation(source, index + 1)
            continue
        if not raw and source[index] == "$":
            index += 1
            if index < len(source) and re.match(r"[A-Za-z_]", source[index]):
                index += 1
                while index < len(source) and re.match(r"[A-Za-z0-9_]", source[index]):
                    index += 1
            continue
        if source.startswith(delimiter, index):
            value = source[content_start:index]
            if not raw:
                value = (value.replace("\\n", "\n").replace("\\r", "\r")
                         .replace("\\t", "\t").replace("\\\\", "\\")
                         .replace("\\'", "'").replace('\\"', '"'))
            return value, index + len(delimiter)
        index += 1
    return source[content_start:], len(source)


def tokenize(source):
    tokens = []
    index = 0
    while index < len(source):
        if source[index].isspace():
            index += 1
            continue
        if source.startswith("//", index):
            end = source.find("\n", index + 2)
            index = len(source) if end < 0 else end + 1
            continue
        if source.startswith("/*", index):
            end = source.find("*/", index + 2)
            index = len(source) if end < 0 else end + 2
            continue
        start = index
        quote_pos = index + 1 if source[index:index + 1].lower() == "r" and index + 1 < len(source) and source[index + 1] in "'\"" else index
        raw = quote_pos != index
        if source[quote_pos] in "'\"":
            value, end = parse_string(source, quote_pos, raw)
            tokens.append(Token("string", value, start, end))
            index = end
            continue
        if source[index].isalpha() or source[index] in "_$":
            index += 1
            while index < len(source) and (source[index].isalnum() or source[index] in "_$"):
                index += 1
            tokens.append(Token("identifier", source[start:index], start, index))
            continue
        tokens.append(Token("punctuation", source[index], index, index + 1))
        index += 1
    return tokens


def first_argument_end(tokens, start):
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    index = start
    while index < len(tokens):
        token = tokens[index]
        if token.kind == "punctuation":
            if token.value in "([{":
                stack.append(token.value)
            elif token.value in ")]}" :
                if not stack:
                    return index
                if stack[-1] == pairs[token.value]:
                    stack.pop()
            elif token.value == "," and not stack:
                return index
        index += 1
    return index


def expression_end(tokens, start):
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    index = start
    while index < len(tokens):
        token = tokens[index]
        if token.kind == "punctuation":
            if token.value in "([{":
                stack.append(token.value)
            elif token.value in ")]}" :
                if not stack:
                    return index
                if stack[-1] == pairs[token.value]:
                    stack.pop()
            elif token.value == "," and not stack:
                return index
        index += 1
    return index


def has_visible_english(value):
    visible = re.sub(r"\$\{.*?\}|\$[A-Za-z_][A-Za-z0-9_]*", "", value, flags=re.S)
    return bool(re.search(r"[A-Za-z]{2}", visible))


def placeholders(value):
    result = []
    index = 0
    while index < len(value):
        if value[index] != "$":
            index += 1
            continue
        start = index
        index += 1
        if index < len(value) and value[index] == "{":
            depth = 1
            index += 1
            while index < len(value) and depth:
                if value[index] == "{":
                    depth += 1
                elif value[index] == "}":
                    depth -= 1
                index += 1
        else:
            while index < len(value) and (value[index].isalnum() or value[index] == "_"):
                index += 1
        if index > start + 1:
            result.append(value[start:index])
    return sorted(result)


def load_catalog():
    source = (ROOT / "lib/l10n/persian_translations.dart").read_text()
    entries = re.findall(r"r'''(.*?)'''\s*:\s*r'''(.*?)'''\s*,", source, flags=re.S)
    catalog = dict(entries)
    if len(catalog) != len(entries):
        raise AssertionError("Duplicate Persian translation keys found")
    if len(catalog) < 700:
        raise AssertionError(f"Catalog unexpectedly small: {len(catalog)} entries")
    return catalog


def run():
    catalog = load_catalog()
    missing = []
    untranslated = []
    unwrapped_fields = []
    calls = 0

    for path in UI_PATHS:
        source = path.read_text()
        tokens = tokenize(source)
        for index, token in enumerate(tokens):
            if token.kind != "identifier" or token.value not in {"Text", "LocalizedText"}:
                continue
            if index + 1 >= len(tokens) or tokens[index + 1].value != "(":
                continue
            if index and tokens[index - 1].value == ".":
                continue
            start = index + 2
            end = first_argument_end(tokens, start)
            expression = tokens[start:end]
            literals = [item.value for item in expression if item.kind == "string"]
            if not literals:
                continue
            other = [item for item in expression if item.kind != "string"]
            values = ["".join(literals)] if all(item.value == "+" for item in other) else literals
            if token.value == "Text":
                for value in values:
                    if has_visible_english(value):
                        untranslated.append((path, source.count("\n", 0, token.start) + 1, value))
            else:
                calls += 1
                for value in values:
                    if has_visible_english(value) and value not in catalog:
                        missing.append((path, source.count("\n", 0, token.start) + 1, value))

        for index, token in enumerate(tokens):
            if token.kind != "identifier" or token.value not in VISIBLE_FIELDS:
                continue
            if index + 1 >= len(tokens) or tokens[index + 1].value != ":":
                continue
            start = index + 2
            end = expression_end(tokens, start)
            expression = tokens[start:end]
            literals = [item.value for item in expression if item.kind == "string"]
            visible = [value for value in literals if has_visible_english(value)]
            if not visible:
                continue
            for value in visible:
                if value not in catalog:
                    missing.append((path, source.count("\n", 0, token.start) + 1, value))
            has_localizer = any(
                item.kind == "identifier" and item.value == "LocalizedText"
                for item in expression
            ) or any(
                [item.value for item in expression[i:i + 5]] == ["context", ".", "l10n", ".", "text"]
                for i in range(max(0, len(expression) - 4))
            ) or any(
                item.kind == "identifier" and item.value == "Text"
                for item in expression
            )
            if not has_localizer:
                unwrapped_fields.append((path, source.count("\n", 0, token.start) + 1, token.value, visible))

    bad_placeholders = [
        (key, placeholders(key), value, placeholders(value))
        for key, value in catalog.items()
        if placeholders(key) != placeholders(value)
    ]
    errors = []
    if missing:
        errors.append("Missing catalog keys:\n" + "\n".join(f"{p}:{n}: {v!r}" for p, n, v in missing))
    if untranslated:
        errors.append("Hard-coded English Text literals:\n" + "\n".join(f"{p}:{n}: {v!r}" for p, n, v in untranslated))
    if unwrapped_fields:
        errors.append("Visible string fields without a localization wrapper:\n" + "\n".join(f"{p}:{n}: {field}={values!r}" for p, n, field, values in unwrapped_fields))
    if bad_placeholders:
        errors.append("Placeholder mismatches:\n" + "\n".join(repr(item) for item in bad_placeholders))
    if errors:
        print("\n\n".join(errors), file=sys.stderr)
        return 1
    print(f"Localization coverage passed: {len(catalog)} catalog entries; {calls} localized widget calls; no raw English Text literals; all visible named fields wrapped; placeholders preserved.")
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
