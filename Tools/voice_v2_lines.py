#!/usr/bin/env python3
"""Entry point for the v2 voice line export: runs Tools/voice_v2/export_lines.py with the same arguments.

    python Tools/voice_v2_lines.py [--pilot-selection PATH] [--no-full] [--remap-identity ID]

See Tools/voice_v2/export_lines.py for what it reads and writes (MelloUI-BuildData/output/voice_v2/lines.json).
"""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "voice_v2"))
import export_lines  # noqa: E402

if __name__ == "__main__":
    export_lines.main()
