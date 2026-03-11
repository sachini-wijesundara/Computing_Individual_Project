#!/bin/bash
set -e

BRAIN="/Users/sachiniwijesundara/.gemini/antigravity/brain/84b7c557-8a7a-4499-b6f2-2b18a0c2aad1"
BASE="/Users/sachiniwijesundara/development/StudioProjects/final year project/Final_Year_Project/assets/products"

echo "Creating folders..."
mkdir -p "$BASE/lipsticks"
mkdir -p "$BASE/eye products/mascara"
mkdir -p "$BASE/eye products/eyeliner"
mkdir -p "$BASE/eye products/eyeshadows"
mkdir -p "$BASE/eye products/eyebrow"

echo "Copying lipsticks..."
cp -v "$BRAIN/lip_satin_1771912770546.png"          "$BASE/lipsticks/satin.png"
cp -v "$BRAIN/lip_hyaluron_oil_1771912830182.png"   "$BASE/lipsticks/Hyaluron lip oil.png"
cp -v "$BRAIN/lip_intense_matte_1771912879301.png"  "$BASE/lipsticks/intense volume matte.png"
cp -v "$BRAIN/lip_matte_resistance_1771912958389.png" "$BASE/lipsticks/matte resistance.png"
cp -v "$BRAIN/lip_balm_in_1771913016826.png"        "$BASE/lipsticks/balm-in lipstick.png"
cp -v "$BRAIN/lip_8hr_gloss_1771913084437.png"      "$BASE/lipsticks/8 hours pro lip gloss.png"
cp -v "$BRAIN/lip_less_nus_1771913141086.png"       "$BASE/lipsticks/less nus by colour.png"
cp -v "$BRAIN/lip_reds_worth_1771913450172.png"     "$BASE/lipsticks/reds of worth satin.png"
cp -v "$BRAIN/lip_balm_gloss_1771913630290.png"     "$BASE/lipsticks/lip balm-in gloss.png"
cp -v "$BRAIN/lip_liner_1771913870741.png"          "$BASE/lipsticks/lip liner.png"

echo "Copying mascaras..."
cp -v "$BRAIN/mascara_big_deal_1771914126273.png"       "$BASE/eye products/mascara/big deal .png"
cp -v "$BRAIN/mascara_extensionist_1771914422614.png"   "$BASE/eye products/mascara/extensionist masacra.png"
cp -v "$BRAIN/mascara_washable_1771915119758.png"       "$BASE/eye products/mascara/extensionist mascara washable.png"
cp -v "$BRAIN/mascara_bold_eye_1771915425674.png"       "$BASE/eye products/mascara/original washable bold eye.png"

echo ""
echo "✅ Done! Copied 14 images to assets/products/"
echo ""
ls -R "$BASE"
