#!/usr/bin/env python3
"""Wrap already rendered PNG icon sizes in the standard ICNS container."""
from pathlib import Path
import struct
import sys

iconset = Path(sys.argv[1])
output = Path(sys.argv[2])
chunks = [
    (b"icp4", "icon_16x16.png"),
    (b"icp5", "icon_32x32.png"),
    (b"icp6", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
]
body = b"".join(kind + struct.pack(">I", len(data) + 8) + data
                for kind, filename in chunks
                for data in [(iconset / filename).read_bytes()])
output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
