# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

import ast
import io
import tokenize
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "package" / "contents" / "code" / "usage.py"


def fstring_problems(source):
    """What Python 3.11 rejects in source's f-strings, which 3.12 accepts
    (PEP 701): in a replacement field, the quote that encloses it, a
    backslash or a comment; and a single-quoted f-string over several
    lines. Needs the f-string tokens of Python 3.12 or later.
    """
    problems = []
    quotes = []  # the quote of each f-string the token is inside, outermost first
    starts = []
    for token in tokenize.generate_tokens(io.StringIO(source).readline):
        if token.type == tokenize.FSTRING_END:
            quotes.pop()
            start = starts.pop()
            if len(token.string) == 1 and start.start[0] != token.end[0]:
                problems.append(f"line {start.start[0]}: a single-quoted f-string over several lines")
            continue
        # A literal part belongs to the innermost f-string; anything else
        # sits in a replacement field of every f-string around it.
        fields = quotes[:-1] if token.type == tokenize.FSTRING_MIDDLE else quotes
        if fields:
            line = token.start[0]
            if any(quote in token.string for quote in fields):
                problems.append(f"line {line}: {token.string!r} reuses an enclosing f-string's quote")
            if "\\" in token.string:
                problems.append(f"line {line}: a backslash in a replacement field")
            if token.type == tokenize.COMMENT:
                problems.append(f"line {line}: a comment in a replacement field")
        if token.type == tokenize.FSTRING_START:
            quotes.append(token.string.lstrip("rRfFbBuU"))
            starts.append(token)
    return problems


class Python311(unittest.TestCase):
    """The helper's syntax is Python 3.11's, the oldest the README asks
    for, whichever Python runs these tests."""

    def test_grammar(self):
        ast.parse(HELPER.read_text(encoding="utf-8"), feature_version=(3, 11))

    # The grammar check takes 3.12's f-strings for 3.11's, as both parse to
    # the same tree; their tokens tell them apart.
    @unittest.skipUnless(hasattr(tokenize, "FSTRING_START"), "needs the f-string tokens of Python 3.12")
    def test_fstrings(self):
        self.assertEqual(fstring_problems(HELPER.read_text(encoding="utf-8")), [])

    @unittest.skipUnless(hasattr(tokenize, "FSTRING_START"), "needs the f-string tokens of Python 3.12")
    def test_fstring_check_tells(self):
        rejected = ['f"{x["e"]}"', 'f"{"\\n".join(x)}"', 'f"{x # note\n}"', "f'{x\n}'", 'f"{f"{x}"}"']
        accepted = ['f"{x[\'e\']}"', 'f"a\\n{x}"', 'f"""{"a"}"""', 'f"{x!r:>{width}}"', "f'''{x\n}'''", 'f"{f\'{x}\'}"']
        for source in rejected:
            with self.subTest(rejected=source):
                self.assertNotEqual(fstring_problems(source), [])
        for source in accepted:
            with self.subTest(accepted=source):
                self.assertEqual(fstring_problems(source), [])


if __name__ == "__main__":
    unittest.main()
