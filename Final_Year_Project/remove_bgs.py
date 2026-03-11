import os
import subprocess

images = [
    "assets/products/hair colors/permanent_cream.png",
    "assets/products/hair colors/vivid_fantasy.png",
    "assets/products/hair colors/gloss_toner.png",
    "assets/products/hair colors/highlight_kit.png",
    "assets/products/hair colors/colour_mask.png",
    "assets/images/mens_one_twist.png"
]

for img in images:
    if os.path.exists(img):
        print(f"Processing {img}...")
        subprocess.run(["rembg", "i", img, img + ".tmp.png"], check=True)
        os.rename(img + ".tmp.png", img)
    else:
        print(f"Not found: {img}")
        
print("All backgrounds removed!")
