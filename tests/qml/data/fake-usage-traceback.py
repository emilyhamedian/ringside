# The helper failing with a traceback and no report.
import sys

print("Traceback (most recent call last):\n  File \"usage.py\"\nKeyError: 'weekly'\n", file=sys.stderr)
sys.exit(1)
