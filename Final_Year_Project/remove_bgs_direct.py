import os
from rembg import remove
from PIL import Image

images = [
    "assets/products/hair colors/permanent_cream.png",
    "assets/products/hair colors/vivid_fantasy.png",
    "assets/products/hair colors/gloss_toner.png",
    "assets/products/hair colors/highlight_kit.png",
    "assets/products/hair colors/colour_mask.png",
    "assets/images/mens_one_twist.png"
]

for img_path in images:
    if os.path.exists(img_path):
        print(f"Processing {img_path}...")
        try:
            with open(img_path, 'rb') as i:
                input_data = i.read()
            output_data = remove(input_data)
            with open(img_path, 'wb') as o:
                o.write(output_data)
            print(f"Saved {img_path}")
        except Exception as e:
            print(f"Failed to process {img_path}: {e}")
    else:
        print(f"Not found: {img_path}")

print("All backgrounds removed!")
