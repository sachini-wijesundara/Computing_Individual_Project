#!/usr/bin/env python3
"""
La Vogue Vista — Product Image Generator
Uses gemini-2.0-flash-exp-image-generation (free tier) to generate product images.
Run: python3 generate_product_images.py
"""
import time, pathlib
from google import genai
from google.genai import types

API_KEY = "AIzaSyDTBPPWWZWQjGgf7WZhr8hkdGon1CcmwBg"
client = genai.Client(api_key=API_KEY)
MODEL  = "gemini-2.0-flash-exp-image-generation"

BASE = pathlib.Path(__file__).parent / "assets" / "products"
PLACEHOLDER_THRESHOLD = 20_000

PRODUCTS = [
    (BASE/"lipsticks/satin.png",
     "Product photo of a rose-pink satin lipstick tube, gold and black packaging, white background"),
    (BASE/"lipsticks/Hyaluron lip oil.png",
     "Product photo of a pink glass lip oil serum dropper bottle, rose-gold cap, white background"),
    (BASE/"lipsticks/intense volume matte.png",
     "Product photo of a deep red matte lipstick in black and gold luxury tube, white background"),
    (BASE/"lipsticks/matte resistance.png",
     "Product photo of a berry wine liquid matte lipstick tube with applicator wand, white background"),
    (BASE/"lipsticks/balm-in lipstick.png",
     "Product photo of a sheer coral nude lip balm lipstick hybrid in slim white tube, white background"),
    (BASE/"lipsticks/8 hours pro lip gloss.png",
     "Product photo of a pink shimmer lip gloss tube with doe-foot applicator wand, white background"),
    (BASE/"lipsticks/less nus by colour.png",
     "Product photo of a mauve nude lipstick in elegant cylindrical tube, white background"),
    (BASE/"lipsticks/reds of worth satin.png",
     "Product photo of a classic bold red satin lipstick in black and gold tube, white background"),
    (BASE/"lipsticks/lip balm-in gloss.png",
     "Product photo of a sheer light pink lip gloss tube with applicator, white background"),
    (BASE/"lipsticks/lip liner.png",
     "Product photo of a rose-nude lip liner pencil with cap, slim pencil barrel, white background"),
    (BASE/"eye products/mascara/big deal .png",
     "Product photo of a chunky black mascara bottle with hourglass shape and thick brush wand, white background"),
    (BASE/"eye products/mascara/extensionist masacra.png",
     "Product photo of a slim elongated black mascara tube with fine bristle brush wand, white background"),
    (BASE/"eye products/mascara/extensionist mascara washable.png",
     "Product photo of a slim black mascara tube with fine comb brush wand, white label, white background"),
    (BASE/"eye products/mascara/original washable bold eye.png",
     "Product photo of a classic hourglass-shaped black mascara with wide comb wand, white background"),
    (BASE/"eye products/mascara/panroma water proof masacara.png",
     "Product photo of a curved black waterproof mascara tube with panoramic brush, white background"),
    (BASE/"eye products/mascara/super star water prrof.png",
     "Product photo of a slim black mascara tube with gold band and curved bristle brush, white background"),
    (BASE/"eye products/mascara/superstart.png",
     "Product photo of a sleek curved black mascara tube with volumizing curling brush, white background"),
    (BASE/"eye products/mascara/big deal buildable waterproof mascara.png",
     "Product photo of a bold thick black mascara tube with large volumizing brush, white background"),
    (BASE/"eye products/eyeliner/grip mechanical gel eyeliner.png",
     "Product photo of slim black mechanical gel eyeliner pencil with retractable tip and gold accent, white background"),
    (BASE/"eye products/eyeliner/grip precision felt water proof eye liner.png",
     "Product photo of a felt-tip liquid eyeliner pen with ultra-fine tip, slim black barrel, white background"),
    (BASE/"eye products/eyeliner/matee-matic.png",
     "Product photo of a matte black kohl eyeliner pencil with smudge tip, white background"),
    (BASE/"eye products/eyeliner/new fail eye liner.png",
     "Product photo of a black retractable kajal kohl eyeliner pencil with twist-up and cap, white background"),
    (BASE/"eye products/eyeliner/pro-last waterproof eye liner.png",
     "Product photo of a black waterproof eyeliner pencil with cap and twist mechanism, white background"),
    (BASE/"eye products/eyeliner/smoldering liner.png",
     "Product photo of a chunky black kohl kajal eyeliner crayon with smudge tip, white background"),
    (BASE/"eye products/eyeliner/super slim liquid eye liner.png",
     "Product photo of an ultra-fine precision liquid eyeliner pen with super slim brush tip, white background"),
    (BASE/"eye products/eyeliner/super star liner.png",
     "Product photo of a black liquid eyeliner bottle with fine brush applicator tip, white background"),
    (BASE/"eye products/eyeshadows/24 hr eyeshadow.png",
     "Product photo of a small square open eyeshadow compact with taupe-rose pressed powder, white background"),
    (BASE/"eye products/eyeshadows/le shadow stick.png",
     "Product photo of a chunky twist-up eyeshadow crayon stick in champagne gold shimmer, white background"),
    (BASE/"eye products/eyeshadows/metalic.png",
     "Product photo of a small round compact with bronze metallic pressed eyeshadow powder, white background"),
    (BASE/"eye products/eyeshadows/monos.png",
     "Product photo of a square single-pan eyeshadow compact with matte taupe pressed powder, white background"),
    (BASE/"eye products/eyeshadows/shimeer liquid eye shadow.png",
     "Product photo of a small liquid eyeshadow tube with doe-foot applicator, rose-gold glitter shimmer, white background"),
    (BASE/"eye products/eyebrow/24hr brow lamination.png",
     "Product photo of a brow lamination gel in mascara-style tube with clear spoolie brush wand, white background"),
    (BASE/"eye products/eyebrow/brow gless.png",
     "Product photo of a clear tinted brow gel tube with spoolie brush wand, white background"),
    (BASE/"eye products/eyebrow/definer mechanical water proof eye brow pencil.png",
     "Product photo of an ultra-slim micro brow pencil with tiny spoolie on other end, taupe tip, white background"),
    (BASE/"eye products/eyebrow/shape and fill pencil.png",
     "Product photo of a dual-ended brow pencil with micro pencil one end and angled brush other end, white background"),
    (BASE/"eye products/eyebrow/volumizing 24h wear brow.png",
     "Product photo of a small volumizing brow mascara tube with fiber bristle brush wand, dark brown, white background"),
    (BASE/"face products/foundation.png",
     "Premium cosmetic foundation bottle, isolated product packshot, transparent background PNG, no background, no shadow plate"),
    (BASE/"face products/powder.png",
     "Luxury compact powder case, isolated product packshot, transparent background PNG, no background, no surface"),
    (BASE/"face products/blushes.png",
     "Dual-pan blush compact, isolated product packshot, transparent background PNG, no background, no surface"),
]

def is_placeholder(p: pathlib.Path) -> bool:
    return not p.exists() or p.stat().st_size < PLACEHOLDER_THRESHOLD

def generate_image(prompt: str, output_path: pathlib.Path, retries: int = 3) -> bool:
    for attempt in range(retries):
        try:
            response = client.models.generate_content(
                model=MODEL,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_modalities=["IMAGE", "TEXT"],
                )
            )
            for part in response.candidates[0].content.parts:
                if part.inline_data and part.inline_data.mime_type.startswith("image/"):
                    output_path.parent.mkdir(parents=True, exist_ok=True)
                    output_path.write_bytes(part.inline_data.data)
                    size = output_path.stat().st_size
                    print(f"  ✅ {output_path.name} ({size:,} bytes)")
                    return True
            print(f"  ⚠️  No image part in response")
        except Exception as e:
            wait = 30 * (attempt + 1)
            err_str = str(e)
            print(f"  ⚠️  Attempt {attempt+1} failed: {err_str[:120]}")
            if attempt < retries - 1:
                print(f"      Waiting {wait}s...")
                time.sleep(wait)
    return False

def main():
    print("\n🎨 La Vogue Vista — Product Image Generator\n")
    missing = [(p, pr) for p, pr in PRODUCTS if is_placeholder(p)]
    print(f"   {len(missing)} placeholder images to generate\n")

    failed = []
    for i, (path, prompt) in enumerate(missing, 1):
        print(f"[{i}/{len(missing)}] {path.name}")
        ok = generate_image(prompt, path)
        if not ok:
            failed.append(path.name)
        if i < len(missing):
            time.sleep(4)

    print(f"\n{'✅ All done!' if not failed else '⚠️  Partial success.'}")
    print(f"Generated: {len(missing)-len(failed)}/{len(missing)}")
    if failed:
        print("Failed images:")
        for f in failed:
            print(f"  - {f}")

if __name__ == "__main__":
    main()
