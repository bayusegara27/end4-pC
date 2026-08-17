#!/usr/bin/env python3
import os
import glob

def sync_steam_icons():
    steam_cache = os.path.expanduser("~/.local/share/Steam/appcache/librarycache")
    hicolor_dir = os.path.expanduser("~/.local/share/icons/hicolor/256x256/apps")
    
    if not os.path.exists(steam_cache):
        return
        
    os.makedirs(hicolor_dir, exist_ok=True)
    
    for app_dir in glob.glob(f"{steam_cache}/*"):
        if not os.path.isdir(app_dir):
            continue
        app_id = os.path.basename(app_dir)
        if not app_id.isdigit():
            continue
            
        logo = os.path.join(app_dir, "logo.png")
        header = os.path.join(app_dir, "library_header.jpg")
        hash_icons = [f for f in glob.glob(f"{app_dir}/*.jpg") if "library_" not in os.path.basename(f)]
        
        src = None
        if os.path.exists(logo):
            src = logo
        elif hash_icons:
            src = hash_icons[0]
        elif os.path.exists(header):
            src = header
            
        if src:
            for target_name in [f"steam_icon_{app_id}.png", f"steam_app_{app_id}.png"]:
                dst = os.path.join(hicolor_dir, target_name)
                if not os.path.exists(dst):
                    try:
                        os.symlink(src, dst)
                    except:
                        pass

if __name__ == "__main__":
    sync_steam_icons()
