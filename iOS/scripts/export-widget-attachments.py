"""Copy named XCTest PNG evidence; preserve gallery/placed/rendered provenance."""
import json
import shutil
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:3])
appearance = sys.argv[3] if len(sys.argv) > 3 else None
destination.mkdir(parents=True, exist_ok=True)
for test in json.loads((source / "manifest.json").read_text()):
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", "")
        if not name.endswith(".png"):
            continue
        prefix = name.split("_0_")[0]
        if not prefix.startswith(("rendered-", "gallery-", "daily-challenge-gallery", "widget-gallery", "widget-search", "home-placed-", "home-customize", "lock-", "app-")):
            continue
        if appearance and not prefix.startswith("rendered-"):
            prefix += "-" + appearance
        shutil.copyfile(source / attachment["exportedFileName"], destination / (prefix + ".png"))
        print(prefix)
