#!/usr/bin/env python3
"""Write and verify Finder icon-view layout (.DS_Store) inside a mounted DMG volume."""

import os
import sys

from ds_store import DSStore
from mac_alias import Alias


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: write_dmg_dsstore.py <mount_point> <app_name>", file=sys.stderr)
        return 2

    mount_point = os.path.abspath(sys.argv[1])
    app_name = sys.argv[2]
    ds_store_path = os.path.join(mount_point, ".DS_Store")
    bg_path = os.path.join(mount_point, ".background", "background.tiff")
    app_entry = f"{app_name}.app"

    if not os.path.isfile(bg_path):
        print(f"ERROR: Missing DMG background image at {bg_path}", file=sys.stderr)
        return 1

    bg_alias = Alias.for_file(bg_path).to_bytes()
    if not bg_alias:
        print("ERROR: Generated backgroundImageAlias is empty", file=sys.stderr)
        return 1

    bwsp = {
        "ContainerShowSidebar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
        "ShowStatusBar": False,
        "ShowTabView": False,
        "ShowToolbar": False,
        "WindowBounds": "{{120, 120}, {660, 448}}",
    }

    icvp = {
        "viewOptionsVersion": 1,
        "backgroundType": 2,
        "backgroundColorRed": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorBlue": 1.0,
        "backgroundImageAlias": bg_alias,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": True,
        "showItemInfo": False,
        "labelOnBottom": True,
        "iconSize": 108.0,
        "textSize": 12.0,
    }

    with DSStore.open(ds_store_path, "w+") as store:
        store["."]["vstl"] = ("type", b"icnv")
        store["."]["bwsp"] = bwsp
        store["."]["icvp"] = icvp
        store[app_entry]["Iloc"] = (180, 196)
        store["Applications"]["Iloc"] = (480, 196)
        store[".background"]["Iloc"] = (180, 560)
        store[".VolumeIcon.icns"]["Iloc"] = (330, 560)
        store[".fseventsd"]["Iloc"] = (480, 560)
        store[".DS_Store"]["Iloc"] = (600, 560)

    if not os.path.isfile(ds_store_path) or os.path.getsize(ds_store_path) <= 0:
        print(f"ERROR: Failed to write {ds_store_path}", file=sys.stderr)
        return 1

    with DSStore.open(ds_store_path, "r") as check:
        vstl = check["."]["vstl"]
        checked_icvp = check["."]["icvp"]
        app_loc = check[app_entry]["Iloc"]
        apps_loc = check["Applications"]["Iloc"]
        alias_len = len(checked_icvp.get("backgroundImageAlias", b""))

        assert vstl[1] in (b"icnv", "icnv"), f"Unexpected vstl: {vstl}"
        assert checked_icvp.get("backgroundType") == 2, "backgroundType != 2"
        assert alias_len > 0, "Empty backgroundImageAlias"
        assert tuple(app_loc) == (180, 196), f"Unexpected app Iloc: {app_loc}"
        assert tuple(apps_loc) == (480, 196), f"Unexpected Applications Iloc: {apps_loc}"

    print(
        f"Verified {ds_store_path} ({os.path.getsize(ds_store_path)} bytes): "
        f"vstl=icnv alias={alias_len}B {app_entry}={tuple(app_loc)} Applications={tuple(apps_loc)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
