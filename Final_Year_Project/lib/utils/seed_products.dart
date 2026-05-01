// lib/utils/seed_products.dart
//
// Seeds the Firestore `products` collection with the La Vogue Vista catalogue.
// Called once from main() — skips any product that already exists (id-based).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Product seed data
// ─────────────────────────────────────────────────────────────────────────────

const _products = <Map<String, dynamic>>[

  // ── Lip Sticks ──────────────────────────────────────────────────────────────
  {
    'id': 'lip_satin',
    'name': "Satin Lipstick",
    'brand': "La Vogue Vista",
    'category': 'Lip Sticks',
    'price': 2800,
    'rating': 4.5,
    'reviews': 128,
    'colorHex': '#C0392B',
    'imagePath': 'assets/products/lipsticks/satin.png',
    'imageUrl': '',
    'description': "Classic satin finish lipstick with intense colour and comfortable wear.",
    'shades': [
      {'name': 'Classic Red', 'hex': '#C0392B'},
      {'name': 'True Red', 'hex': '#E32636'},
      {'name': 'Ruby Red', 'hex': '#9B111E'},
      {'name': 'Crimson', 'hex': '#DC143C'},
      {'name': 'Cherry', 'hex': '#DE3163'},
      {'name': 'Rose Petal', 'hex': '#D4617A'},
      {'name': 'Dusty Pink', 'hex': '#DCAE96'},
      {'name': 'Hot Pink', 'hex': '#FF69B4'},
      {'name': 'Magenta', 'hex': '#FF00FF'},
      {'name': 'Bubblegum', 'hex': '#FFC1CC'},
      {'name': 'Nude Blush', 'hex': '#EBB4A9'},
      {'name': 'Peachy Nude', 'hex': '#FFCBA4'},
      {'name': 'Cocoa', 'hex': '#D2691E'},
      {'name': 'Mocha', 'hex': '#A0522D'},
      {'name': 'Terracotta', 'hex': '#E2725B'},
      {'name': 'Berry Bliss', 'hex': '#8B2252'},
      {'name': 'Plum Dream', 'hex': '#6A2C5E'},
      {'name': 'Mulberry', 'hex': '#C54B8C'},
      {'name': 'Wine', 'hex': '#722F37'},
      {'name': 'Aubergine', 'hex': '#483248'},
      {'name': 'Coral Kiss', 'hex': '#E8735A'},
      {'name': 'Tangerine', 'hex': '#F28500'},
      {'name': 'Peach', 'hex': '#FFE5B4'},
      {'name': 'Sunset Orange', 'hex': '#FD5E53'},
      {'name': 'Rusty Red', 'hex': '#DA2C43'},
    ],
  },
  {
    'id': 'lip_hyaluron_oil',
    'name': "Hyaluron Lip Oil",
    'brand': "La Vogue Vista",
    'category': 'Lip Sticks',
    'price': 3200,
    'rating': 4.7,
    'reviews': 95,
    'colorHex': '#E87D7D',
    'imagePath': 'assets/products/lipsticks/Hyaluron lip oil.png',
    'imageUrl': '',
    'description': "Nourishing lip oil with hyaluronic acid for plump, glossy lips.",
    'shades': [
      {'name': 'Sheer Blush', 'hex': '#E87D7D'},
      {'name': 'Clear Gloss', 'hex': '#F2B5B5'},
      {'name': 'Light Pink', 'hex': '#F0A0A8'},
      {'name': 'Peach Glow', 'hex': '#F5B89A'},
    ],
  },
  {
    'id': 'lip_intense_matte',
    'name': "Intense Volume Matte",
    'brand': "La Vogue Vista",
    'category': 'Lip Sticks',
    'price': 2500,
    'rating': 4.4,
    'reviews': 210,
    'colorHex': '#8B1A1A',
    'imagePath': 'assets/products/lipsticks/intense volume matte.png',
    'imageUrl': '',
    'description': "Intense matte lip colour with a volumising effect.",
    'shades': [
      {'name': 'Deep Crimson', 'hex': '#8B1A1A'},
      {'name': 'Burgundy', 'hex': '#6D0F1F'},
      {'name': 'Brick Red', 'hex': '#A0311E'},
      {'name': 'Wine Red', 'hex': '#7A1C2E'},
      {'name': 'Dark Plum', 'hex': '#5C1A3A'},
      {'name': 'Oxblood', 'hex': '#4A0E14'},
    ],
  },
  {
    'id': 'lip_matte_resistance',
    'name': "Matte Resistance",
    'brand': "La Vogue Vista",
    'category': 'Lip Sticks',
    'price': 2700,
    'rating': 4.3,
    'reviews': 176,
    'colorHex': '#C94040',
    'imagePath': 'assets/products/lipsticks/matte resistance.png',
    'imageUrl': '',
    'description': "Long-lasting matte lipstick resistant to eating and drinking.",
    'shades': [
      {'name': 'Red Alert', 'hex': '#C94040'},
      {'name': 'Cherry Pop', 'hex': '#B03060'},
      {'name': 'Dusty Rose', 'hex': '#C07070'},
      {'name': 'Sienna', 'hex': '#B85C38'},
      {'name': 'Mocha', 'hex': '#8B5A4A'},
    ],
  },
  {
    'id': 'lip_balm_in',
    'name': "Balm-in Lipstick",
    'brand': "La Vogue Vista",
    'category': 'Lip Sticks',
    'price': 4200,
    'rating': 4.8,
    'reviews': 64,
    'colorHex': '#D46A6A',
    'imagePath': 'assets/products/lipsticks/balm-in lipstick.png',
    'imageUrl': '',
    'description': "Hydrating balm-in-lipstick for all-day moisture and colour.",
    'shades': [
      {'name': 'Blush Nude', 'hex': '#D46A6A'},
      {'name': 'Candy Pink', 'hex': '#E8A0B0'},
      {'name': 'Soft Coral', 'hex': '#E8907A'},
      {'name': 'Rosy Nude', 'hex': '#C89090'},
    ],
  },
  {
    'id': 'lip_8hr_gloss',
    'name': "8 Hours Pro Lip Gloss",
    'brand': "La Vogue Vista",
    'category': 'Lip Sticks',
    'price': 3800,
    'rating': 4.6,
    'reviews': 89,
    'colorHex': '#F4A0A0',
    'imagePath': 'assets/products/lipsticks/8 hours pro lip gloss.png',
    'imageUrl': '',
    'description': "Shiny, long-wear lip gloss with 8-hour hydration.",
    'shades': [
      {'name': 'Gloss Clear', 'hex': '#F4A0A0'},
      {'name': 'Shimmer Pink', 'hex': '#F0B0C0'},
      {'name': 'Ice Rose', 'hex': '#F5C5D0'},
      {'name': 'Peach Shine', 'hex': '#F5B8A0'},
    ],
  },
  {
    'id': 'lip_less_nus',
    'name': "Less Nus by Colour",
    'brand': "La Vogue Vista",
    'category': 'Lip Sticks',
    'price': 2200,
    'rating': 4.2,
    'reviews': 143,
    'colorHex': '#D4B4B4',
    'imagePath': 'assets/products/lipsticks/less nus by colour.png',
    'imageUrl': '',
    'description': "Subtle nude shades for a natural everyday look.",
    'shades': [
      {'name': 'Nude Blush', 'hex': '#D4B4B4'},
      {'name': 'Warm Beige', 'hex': '#C8A888'},
      {'name': 'Pale Rose', 'hex': '#D4A8A8'},
      {'name': 'Sand Nude', 'hex': '#C0A080'},
      {'name': 'Mauve Nude', 'hex': '#B89898'},
    ],
  },
  {
    'id': 'lip_reds_worth',
    'name': "Reds of Worth Satin",
    'brand': "La Vogue Vista",
    'category': 'Lip Sticks',
    'price': 2900,
    'rating': 4.6,
    'reviews': 201,
    'colorHex': '#A00000',
    'imagePath': 'assets/products/lipsticks/reds of worth satin.png',
    'imageUrl': '',
    'description': "Iconic red collection with a luxurious satin finish.",
    'shades': [
      {'name': 'Red Worth', 'hex': '#A00000'},
      {'name': 'True Red', 'hex': '#CC0000'},
      {'name': 'Fire Engine', 'hex': '#CC2200'},
      {'name': 'Crimson', 'hex': '#990022'},
      {'name': 'Ruby', 'hex': '#880033'},
      {'name': 'Scarlet', 'hex': '#BB1122'},
    ],
  },
  {
    'id': 'lip_balm_gloss',
    'name': "Lip Balm-in Gloss",
    'brand': "La Vogue Vista",
    'category': 'Lip Sticks',
    'price': 3600,
    'rating': 4.5,
    'reviews': 77,
    'colorHex': '#F7C5C5',
    'imagePath': 'assets/products/lipsticks/lip balm-in gloss.png',
    'imageUrl': '',
    'description': "Glossy balm hybrid for shiny, cushiony lips.",
    'shades': [
      {'name': 'Sheer Pink', 'hex': '#F7C5C5'},
      {'name': 'Baby Pink', 'hex': '#F5B0C0'},
      {'name': 'Ice Gloss', 'hex': '#FAD5D5'},
    ],
  },
  {
    'id': 'lip_liner',
    'name': "Lip Liner",
    'brand': "La Vogue Vista",
    'category': 'Lip Sticks',
    'price': 1800,
    'rating': 4.3,
    'reviews': 158,
    'colorHex': '#7B1C1C',
    'imagePath': 'assets/products/lipsticks/lip liner.png',
    'imageUrl': '',
    'description': "Precise lip liner for a defined and long-lasting lip look.",
    'shades': [
      {'name': 'Deep Rose', 'hex': '#7B1C1C'},
      {'name': 'Nude Liner', 'hex': '#B08070'},
      {'name': 'Berry Line', 'hex': '#7A2050'},
      {'name': 'Red Liner', 'hex': '#9A1020'},
    ],
  },

  // ── Mascara ──────────────────────────────────────────────────────────────────
  {
    'id': 'mas_big_deal',
    'name': "Big Deal Mascara",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2400,
    'rating': 4.4,
    'reviews': 189,
    'colorHex': '#1C1C1C',
    'imagePath': 'assets/products/eye products/mascara/big deal .png',
    'imageUrl': '',
    'description': "Volumising and lengthening mascara for dramatic lashes.",
    'shades': [
      {'name': 'Blackout', 'hex': '#1C1C1C'},
      {'name': 'Espresso', 'hex': '#3D2314'},
    ],
  },
  {
    'id': 'mas_extensionist',
    'name': "Extensionist Mascara",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2600,
    'rating': 4.5,
    'reviews': 234,
    'colorHex': '#1C1C1C',
    'imagePath': 'assets/products/eye products/mascara/extensionist masacra.png',
    'imageUrl': '',
    'description': "Extends, thickens and separates every lash.",
    'shades': [
      {'name': 'Blackout', 'hex': '#1C1C1C'},
      {'name': 'Brown Black', 'hex': '#2D1A0E'},
    ],
  },
  {
    'id': 'mas_extensionist_washable',
    'name': "Extensionist Washable",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2600,
    'rating': 4.3,
    'reviews': 112,
    'colorHex': '#1C1C1C',
    'imagePath': 'assets/products/eye products/mascara/extensionist mascara washable.png',
    'imageUrl': '',
    'description': "Gentle washable formula for sensitive eyes.",
    'shades': [
      {'name': 'Black', 'hex': '#1C1C1C'},
      {'name': 'Dark Brown', 'hex': '#3A2010'},
    ],
  },
  {
    'id': 'mas_original_washable',
    'name': "Original Washable Bold Eye",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2300,
    'rating': 4.2,
    'reviews': 98,
    'colorHex': '#1C1C1C',
    'imagePath': 'assets/products/eye products/mascara/original washable bold eye.png',
    'imageUrl': '',
    'description': "Classic bold-eye mascara in an easy washable formula.",
    'shades': [
      {'name': 'Black', 'hex': '#1C1C1C'},
      {'name': 'Dark Brown', 'hex': '#3A2010'},
    ],
  },
  {
    'id': 'mas_panorama_wp',
    'name': "Panorama Waterproof",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2800,
    'rating': 4.6,
    'reviews': 301,
    'colorHex': '#1C1C1C',
    'imagePath': 'assets/products/eye products/mascara/panroma water proof masacara.png',
    'imageUrl': '',
    'description': "360° waterproof fan effect for panoramic volume.",
    'shades': [
      {'name': 'Black', 'hex': '#1C1C1C'},
      {'name': 'Brown', 'hex': '#4A2D18'},
    ],
  },
  {
    'id': 'mas_superstar_wp',
    'name': "Super Star Waterproof",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 3000,
    'rating': 4.7,
    'reviews': 267,
    'colorHex': '#1C1C1C',
    'imagePath': 'assets/products/eye products/mascara/super star water prrof.png',
    'imageUrl': '',
    'description': "Extreme volume waterproof mascara for all-day hold.",
    'shades': [
      {'name': 'Black', 'hex': '#1C1C1C'},
      {'name': 'Brown Black', 'hex': '#2D1A0E'},
    ],
  },
  {
    'id': 'mas_superstar',
    'name': "Superstar Mascara",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2900,
    'rating': 4.5,
    'reviews': 178,
    'colorHex': '#1C1C1C',
    'imagePath': 'assets/products/eye products/mascara/superstart.png',
    'imageUrl': '',
    'description': "Superstar lash mascara for the ultimate lash transformation.",
    'shades': [
      {'name': 'Black', 'hex': '#1C1C1C'},
      {'name': 'Brown', 'hex': '#4A2D18'},
    ],
  },
  {
    'id': 'mas_big_deal_buildable',
    'name': "Big Deal Buildable Waterproof",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2500,
    'rating': 4.4,
    'reviews': 143,
    'colorHex': '#1C1C1C',
    'imagePath': 'assets/products/eye products/mascara/big deal buildable waterproof mascara.png',
    'imageUrl': '',
    'description': "Buildable waterproof mascara from natural to bold in multiple coats.",
    'shades': [
      {'name': 'Black', 'hex': '#1C1C1C'},
      {'name': 'Espresso', 'hex': '#3D2314'},
    ],
  },

  // ── Eyeliner ─────────────────────────────────────────────────────────────────
  {
    'id': 'el_grip_gel',
    'name': "Grip Mechanical Gel Eyeliner",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2200,
    'rating': 4.4,
    'reviews': 134,
    'colorHex': '#000000',
    'imagePath': 'assets/products/eye products/eye liner/grip mechanical gel eyeliner.png',
    'imageUrl': '',
    'description': "Mechanical gel eyeliner with a precise tip for a clean cat-eye.",
    'shades': [
      {'name': 'Black', 'hex': '#000000'},
      {'name': 'Brown', 'hex': '#4A2D18'},
      {'name': 'Navy', 'hex': '#1A1A4A'},
    ],
  },
  {
    'id': 'el_grip_felt',
    'name': "Grip Precision Felt Waterproof",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2400,
    'rating': 4.6,
    'reviews': 221,
    'colorHex': '#000000',
    'imagePath': 'assets/products/eye products/eye liner/grip precision felt water proof eye liner.png',
    'imageUrl': '',
    'description': "Ultra-fine felt tip for precise lines that last all day.",
    'shades': [
      {'name': 'Black', 'hex': '#000000'},
      {'name': 'Brown', 'hex': '#4A2D18'},
    ],
  },
  {
    'id': 'el_matematic',
    'name': "Matee-Matic Eyeliner",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 1900,
    'rating': 4.2,
    'reviews': 89,
    'colorHex': '#2C2C2C',
    'imagePath': 'assets/products/eye products/eye liner/matee-matic.png',
    'imageUrl': '',
    'description': "Matte finish eyeliner pencil with a built-in smudger.",
    'shades': [
      {'name': 'Matte Black', 'hex': '#2C2C2C'},
      {'name': 'Dark Brown', 'hex': '#3A2010'},
      {'name': 'Charcoal', 'hex': '#3C3C3C'},
    ],
  },
  {
    'id': 'el_new_fail',
    'name': "New Fail Eyeliner",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 1800,
    'rating': 4.1,
    'reviews': 67,
    'colorHex': '#1A1A1A',
    'imagePath': 'assets/products/eye products/eye liner/new fail eye liner.png',
    'imageUrl': '',
    'description': "Fail-proof formula for beginners and pros alike.",
    'shades': [
      {'name': 'Black', 'hex': '#1A1A1A'},
      {'name': 'Brown', 'hex': '#4A2D18'},
    ],
  },
  {
    'id': 'el_prolast_wp',
    'name': "Pro-Last Waterproof Eyeliner",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2100,
    'rating': 4.5,
    'reviews': 156,
    'colorHex': '#000000',
    'imagePath': 'assets/products/eye products/eye liner/pro-last waterproof eye liner.png',
    'imageUrl': '',
    'description': "Professional waterproof eyeliner for precise, bold lines.",
    'shades': [
      {'name': 'Black', 'hex': '#000000'},
      {'name': 'Dark Brown', 'hex': '#3A2010'},
      {'name': 'Plum', 'hex': '#4A1A3A'},
    ],
  },
  {
    'id': 'el_smoldering',
    'name': "Smoldering Liner",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 3500,
    'rating': 4.7,
    'reviews': 98,
    'colorHex': '#111111',
    'imagePath': 'assets/products/eye products/eye liner/smoldering liner.png',
    'imageUrl': '',
    'description': "Rich, creamy smoldering liner for an intense and sultry look.",
    'shades': [
      {'name': 'Smoldering Black', 'hex': '#111111'},
      {'name': 'Smoky Brown', 'hex': '#3A2215'},
      {'name': 'Deep Plum', 'hex': '#3A1040'},
    ],
  },
  {
    'id': 'el_super_slim',
    'name': "Super Slim Liquid Eyeliner",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2000,
    'rating': 4.3,
    'reviews': 112,
    'colorHex': '#000000',
    'imagePath': 'assets/products/eye products/eye liner/super slim liquid eye liner.png',
    'imageUrl': '',
    'description': "0.5mm super slim tip for ultra-precise liquid lines.",
    'shades': [
      {'name': 'Black', 'hex': '#000000'},
      {'name': 'Brown', 'hex': '#4A2D18'},
    ],
  },
  {
    'id': 'el_superstar',
    'name': "Super Star Liner",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2300,
    'rating': 4.4,
    'reviews': 145,
    'colorHex': '#000000',
    'imagePath': 'assets/products/eye products/eye liner/super star liner.png',
    'imageUrl': '',
    'description': "Superstar liner for defined, lasting eye looks.",
    'shades': [
      {'name': 'Black', 'hex': '#000000'},
      {'name': 'Dark Brown', 'hex': '#3A2010'},
      {'name': 'Navy Blue', 'hex': '#1A1A5A'},
    ],
  },

  // ── Eyeshadow ─────────────────────────────────────────────────────────────────
  {
    'id': 'es_24hr',
    'name': "24 HR Eyeshadow",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 3200,
    'rating': 4.5,
    'reviews': 167,
    'colorHex': '#8B6F47',
    'imagePath': 'assets/products/eye products/eyeshadows/24 hr eyeshadow.png',
    'imageUrl': '',
    'description': "Long-lasting 24-hour eyeshadow with intense colour payoff.",
    'shades': [
      {'name': 'Warm Taupe', 'hex': '#8B6F47'},
      {'name': 'Rose Gold', 'hex': '#B8836A'},
      {'name': 'Bronze', 'hex': '#9A6B3A'},
      {'name': 'Copper', 'hex': '#B87040'},
    ],
  },
  {
    'id': 'es_le_shadow',
    'name': "Le Shadow Stick",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 4500,
    'rating': 4.8,
    'reviews': 54,
    'colorHex': '#C9A96E',
    'imagePath': 'assets/products/eye products/eyeshadows/le shadow stick.png',
    'imageUrl': '',
    'description': "Luxury shadow stick that glides on for blendable, vivid colour.",
    'shades': [
      {'name': 'Champagne', 'hex': '#C9A96E'},
      {'name': 'Gold', 'hex': '#D4A820'},
      {'name': 'Smoky Quartz', 'hex': '#707070'},
      {'name': 'Amethyst', 'hex': '#8B6B9A'},
    ],
  },
  {
    'id': 'es_metallic',
    'name': "Metallic Eyeshadow",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2800,
    'rating': 4.4,
    'reviews': 134,
    'colorHex': '#C0A060',
    'imagePath': 'assets/products/eye products/eyeshadows/metalic.png',
    'imageUrl': '',
    'description': "Foil-finish metallic eyeshadow for a glam, high-impact look.",
    'shades': [
      {'name': 'Bronze Foil', 'hex': '#C0A060'},
      {'name': 'Silver', 'hex': '#B0B0B0'},
      {'name': 'Gold Foil', 'hex': '#D4A820'},
      {'name': 'Rose Gold Foil', 'hex': '#C8826A'},
    ],
  },
  {
    'id': 'es_monos',
    'name': "Monos Eyeshadow",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2600,
    'rating': 4.3,
    'reviews': 88,
    'colorHex': '#A0856A',
    'imagePath': 'assets/products/eye products/eyeshadows/monos.png',
    'imageUrl': '',
    'description': "Single colour eyeshadow pans in a curated palette of shades.",
    'shades': [
      {'name': 'Taupe', 'hex': '#A0856A'},
      {'name': 'Burgundy', 'hex': '#7A2035'},
      {'name': 'Forest Green', 'hex': '#2D5A3D'},
      {'name': 'Navy', 'hex': '#1A2A5A'},
      {'name': 'Dusty Mauve', 'hex': '#907080'},
    ],
  },
  {
    'id': 'es_shimmer_liquid',
    'name': "Shimmer Liquid Eye Shadow",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 3000,
    'rating': 4.5,
    'reviews': 112,
    'colorHex': '#D4AF37',
    'imagePath': 'assets/products/eye products/eyeshadows/shimeer liquid eye shadow.png',
    'imageUrl': '',
    'description': "Liquid shimmer shadow for a dazzling, high-shine eye.",
    'shades': [
      {'name': 'Gold Shimmer', 'hex': '#D4AF37'},
      {'name': 'Rose Shimmer', 'hex': '#D48090'},
      {'name': 'Silver Shimmer', 'hex': '#C0C0C0'},
      {'name': 'Bronze Shimmer', 'hex': '#C08040'},
    ],
  },

  // ── Eyebrow ──────────────────────────────────────────────────────────────────
  {
    'id': 'eb_24hr_lamination',
    'name': "24HR Brow Lamination",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 3800,
    'rating': 4.6,
    'reviews': 203,
    'colorHex': '#6B4226',
    'imagePath': 'assets/products/eye products/eye brow/24hr brow lamination.png',
    'imageUrl': '',
    'description': "Lamination brow gel for fluffy, defined brows that last 24 hours.",
    'shades': [
      {'name': 'Brunette', 'hex': '#6B4226'},
      {'name': 'Dark Brown', 'hex': '#3A2010'},
      {'name': 'Taupe', 'hex': '#8B7055'},
      {'name': 'Blonde', 'hex': '#C8A868'},
    ],
  },
  {
    'id': 'eb_brow_gloss',
    'name': "Brow Gloss",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2900,
    'rating': 4.4,
    'reviews': 88,
    'colorHex': '#7A5C3C',
    'imagePath': 'assets/products/eye products/eye brow/brow gless.png',
    'imageUrl': '',
    'description': "Clear gloss gel for polished, glossy brows.",
    'shades': [
      {'name': 'Clear', 'hex': '#7A5C3C'},
      {'name': 'Tinted Brown', 'hex': '#5A3820'},
    ],
  },
  {
    'id': 'eb_definer',
    'name': "Definer Waterproof Brow Pencil",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2400,
    'rating': 4.5,
    'reviews': 176,
    'colorHex': '#5C3D1E',
    'imagePath': 'assets/products/eye products/eye brow/definer mechanical water proof eye brow pencil.png',
    'imageUrl': '',
    'description': "Mechanical waterproof pencil for hair-like strokes and precise definition.",
    'shades': [
      {'name': 'Brunette', 'hex': '#5C3D1E'},
      {'name': 'Blonde', 'hex': '#B8905A'},
      {'name': 'Soft Black', 'hex': '#2A1A0E'},
      {'name': 'Auburn', 'hex': '#7A3020'},
    ],
  },
  {
    'id': 'eb_shape_fill',
    'name': "Shape and Fill Pencil",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 2600,
    'rating': 4.3,
    'reviews': 134,
    'colorHex': '#6B4C2A',
    'imagePath': 'assets/products/eye products/eye brow/shape and fill pencil.png',
    'imageUrl': '',
    'description': "Dual-ended pencil for shaping outline and filling brows in one step.",
    'shades': [
      {'name': 'Medium Brown', 'hex': '#6B4C2A'},
      {'name': 'Dark Brown', 'hex': '#3A2010'},
      {'name': 'Taupe', 'hex': '#9A7A55'},
      {'name': 'Soft Brown', 'hex': '#8B6340'},
    ],
  },
  {
    'id': 'eb_volumizing',
    'name': "Volumizing 24H Wear Brow",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'price': 3100,
    'rating': 4.4,
    'reviews': 99,
    'colorHex': '#7A5530',
    'imagePath': 'assets/products/eye products/eye brow/volumizing 24h wear brow.png',
    'imageUrl': '',
    'description': "Thickening brow mascara for bold, full brows that last all day.",
    'shades': [
      {'name': 'Medium Brown', 'hex': '#7A5530'},
      {'name': 'Dark Brown', 'hex': '#3A2010'},
      {'name': 'Black Brown', 'hex': '#1A0E08'},
      {'name': 'Blonde', 'hex': '#C8A060'},
    ],
  },

  // ── Face Products ────────────────────────────────────────────────────────────

  // Foundation
  {
    'id': 'fp_foundation_flawless',
    'name': "Flawless Foundation",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'subCategory': 'Foundation',
    'price': 4800,
    'rating': 4.7,
    'reviews': 342,
    'colorHex': '#D9B28D',
    'imagePath': 'assets/products/face products/foundation/foundation.png',
    'imageUrl': '',
    'description': "Buildable, long-wear foundation with a natural second-skin finish. Available in 39 shades.",
    'shades': [
      // Light-Light
      {'name': 'Shade 102 Ivory',        'hex': '#F7EDE0'},
      {'name': 'Shade 105 Porcelain',    'hex': '#F5E6D5'},
      {'name': 'Shade 110 Linen',        'hex': '#F2DDC8'},
      {'name': 'Shade 112 Alabaster',    'hex': '#F0D8C0'},
      {'name': 'Shade 115 Vanilla',      'hex': '#EDD0B4'},
      {'name': 'Shade 118 Pearl',        'hex': '#E9C8A8'},
      {'name': 'Shade 120 Shell',        'hex': '#E6C3A0'},
      {'name': 'Shade 122 Cream',        'hex': '#E3BC98'},
      // Light-Medium
      {'name': 'Shade 124 Buff',         'hex': '#E0B590'},
      {'name': 'Shade 125 Sand',         'hex': '#DDB088'},
      {'name': 'Shade 128 Warm Nude',    'hex': '#D9A87E'},
      {'name': 'Shade 130 Natural',      'hex': '#D6A278'},
      {'name': 'Shade 220 Bisque',       'hex': '#D29C70'},
      {'name': 'Shade 222 Wheat',        'hex': '#CE9568'},
      {'name': 'Shade 228 Warm Beige',   'hex': '#CA8E60'},
      {'name': 'Shade 230 Natural Beige','hex': '#C68858'},
      {'name': 'Shade 235 Latte',        'hex': '#C28050'},
      // Medium
      {'name': 'Shade 238 Toffee',       'hex': '#BD7848'},
      {'name': 'Shade 242 Warm Toffee',  'hex': '#B87040'},
      {'name': 'Shade 245 Caramel',      'hex': '#B26838'},
      {'name': 'Shade 310 Golden',       'hex': '#AC6230'},
      {'name': 'Shade 312 Honey',        'hex': '#A85C28'},
      {'name': 'Shade 320 Warm Honey',   'hex': '#A05820'},
      // Medium-Deep
      {'name': 'Shade 330 Almond',       'hex': '#985218'},
      {'name': 'Shade 332 Terra Cotta',  'hex': '#904C14'},
      {'name': 'Shade 334 Chestnut',     'hex': '#884510'},
      {'name': 'Shade 335 Maple',        'hex': '#80400C'},
      {'name': 'Shade 338 Hazelnut',     'hex': '#783B08'},
      {'name': 'Shade 340 Warm Tan',     'hex': '#703606'},
      {'name': 'Shade 355 Espresso',     'hex': '#683004'},
      {'name': 'Shade 356 Truffle',      'hex': '#5E2C02'},
      {'name': 'Shade 358 Umber',        'hex': '#562800'},
      // Deep
      {'name': 'Shade 360 Mahogany',     'hex': '#4E2400'},
      {'name': 'Shade 362 Cinnamon',     'hex': '#462000'},
      {'name': 'Shade 365 Sienna',       'hex': '#3E1C00'},
      {'name': 'Shade 368 Cocoa',        'hex': '#361800'},
      {'name': 'Shade 370 Nutmeg',       'hex': '#2E1400'},
      {'name': 'Shade 375 Mocha',        'hex': '#261000'},
      {'name': 'Shade 380 Ebony',        'hex': '#1E0E00'},
    ],
  },

  // Powder
  {
    'id': 'fp_powder_translucent',
    'name': "Velvet Setting Powder",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'subCategory': 'Powder',
    'price': 3600,
    'rating': 4.5,
    'reviews': 201,
    'colorHex': '#E2C9A8',
    'imagePath': 'assets/products/face products/powder/powder_translucent_setting.png',
    'imageUrl': '',
    'description': "Finely milled setting powder for a velvety, long-lasting matte finish.",
    'shades': [
      {'name': 'Translucent',       'hex': '#F5EDE0'},
      {'name': 'Ivory Finish',      'hex': '#F0DEC8'},
      {'name': 'Fair Beige',        'hex': '#EAD4B8'},
      {'name': 'Natural Beige',     'hex': '#E2C9A8'},
      {'name': 'Warm Honey',        'hex': '#D4A87A'},
      {'name': 'Sun Tan',           'hex': '#C49060'},
      {'name': 'Sun-Kissed Bronze', 'hex': '#B87840'},
      {'name': 'Warm Bronze',       'hex': '#A86830'},
      {'name': 'Deep Tan',          'hex': '#986020'},
      {'name': 'Mineral Matte',     'hex': '#C8A878'},
      {'name': 'Soft Luminous',     'hex': '#DEC090'},
      {'name': 'Golden Glow',       'hex': '#CC9850'},
    ],
  },

  // Blush
  {
    'id': 'fp_blush_silk',
    'name': "Silk Blush",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'subCategory': 'Blush',
    'price': 3200,
    'rating': 4.6,
    'reviews': 278,
    'colorHex': '#E8A0A5',
    'imagePath': 'assets/products/face products/blush/blush_bonbon_coral.png',
    'imageUrl': '',
    'description': "Silky-smooth blush with a buildable, natural flush. Available in 10 flattering shades.",
    'shades': [
      {'name': 'Funfetti',   'hex': '#F9C0C8'},
      {'name': 'Bonbon',     'hex': '#E8A0A5'},
      {'name': 'Souffle',    'hex': '#D88090'},
      {'name': 'Macaron',    'hex': '#D07080'},
      {'name': 'Jam',        'hex': '#B84060'},
      {'name': 'Croffle',    'hex': '#C07060'},
      {'name': 'Shortcake',  'hex': '#E89090'},
      {'name': 'Taffy',      'hex': '#E07888'},
      {'name': 'Truffle',    'hex': '#9A5848'},
      {'name': 'Churro',     'hex': '#D4A050'},
      {'name': 'Praline',    'hex': '#C08860'},
      {'name': 'Berry Kiss', 'hex': '#A03060'},
    ],
  },

  // Concealer
  {
    'id': 'fp_concealer_radiant',
    'name': "Radiant Concealer",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'subCategory': 'Concealer',
    'price': 3000,
    'rating': 4.5,
    'reviews': 187,
    'colorHex': '#E0C8A8',
    'imagePath': 'assets/products/face products/concealer/concealer_medium_beige.png',
    'imageUrl': '',
    'description': "Full-coverage concealer that brightens dark circles and hides blemishes seamlessly.",
    'shades': [
      {'name': 'Fair Ivory',        'hex': '#F5E8D5'},
      {'name': 'Light Nude',        'hex': '#EFD8C0'},
      {'name': 'Light Beige',       'hex': '#E8CEAC'},
      {'name': 'Warm Vanilla',      'hex': '#E2C89C'},
      {'name': 'Medium Beige',      'hex': '#D8B888'},
      {'name': 'Natural',           'hex': '#D0A878'},
      {'name': 'Warm Honey',        'hex': '#C89860'},
      {'name': 'Golden',            'hex': '#BE8850'},
      {'name': 'Caramel',           'hex': '#B07840'},
      {'name': 'Tan Sand',          'hex': '#A06830'},
      {'name': 'Warm Tan',          'hex': '#905820'},
      {'name': 'Deep Espresso',     'hex': '#603010'},
    ],
  },

  // Highlighter
  {
    'id': 'fp_highlighter_glow',
    'name': "Glow Highlighter",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'subCategory': 'Highlighter',
    'price': 3800,
    'rating': 4.7,
    'reviews': 224,
    'colorHex': '#F0D080',
    'imagePath': 'assets/products/face products/highlighter/highlighter_champagne_glow.png',
    'imageUrl': '',
    'description': "Blinding luminosity in a single swipe. Buildable shimmer for a lit-from-within glow.",
    'shades': [
      {'name': 'Champagne Glow',   'hex': '#F5D888'},
      {'name': 'Rose Ice',         'hex': '#F0C0C8'},
      {'name': 'Golden Hour',      'hex': '#F0C840'},
      {'name': 'Arctic Pearl',     'hex': '#E0E8F8'},
      {'name': 'Peach Shimmer',    'hex': '#F0B880'},
      {'name': 'Bronze Beam',      'hex': '#C89040'},
      {'name': 'Star Dust',        'hex': '#E8E0C0'},
      {'name': 'Moonrise',         'hex': '#D8D0E8'},
      {'name': 'Coral Glow',       'hex': '#F0A888'},
      {'name': 'Sun Halo',         'hex': '#E8C060'},
      {'name': 'Rose Gold Flash',  'hex': '#E0A898'},
      {'name': 'Bronze Galaxy',    'hex': '#C07830'},
    ],
  },

  // Contour & Bronzer
  {
    'id': 'fp_contour_sculpt',
    'name': "Sculpt & Bronze",
    'brand': "La Vogue Vista",
    'category': 'Makeup',
    'subCategory': 'Contour & Bronzer',
    'price': 3500,
    'rating': 4.4,
    'reviews': 196,
    'colorHex': '#B07840',
    'imagePath': 'assets/products/face products/contour_bronzer/bronzer_warm_bronze.png',
    'imageUrl': '',
    'description': "Dual-use contour and bronzer compact for sculpted, sun-kissed definition.",
    'shades': [
      {'name': 'Soft Sculpt',   'hex': '#C8A070'},
      {'name': 'Cool Contour',  'hex': '#B89068'},
      {'name': 'Medium Contour','hex': '#A87848'},
      {'name': 'Deep Define',   'hex': '#906030'},
      {'name': 'Warm Sculpt',   'hex': '#C08858'},
      {'name': 'Sun-Kissed',    'hex': '#C89050'},
      {'name': 'Light Bronze',  'hex': '#D0A060'},
      {'name': 'Warm Bronze',   'hex': '#B07840'},
      {'name': 'Sunkissed Tan', 'hex': '#A06830'},
      {'name': 'Rich Cocoa',    'hex': '#805020'},
      {'name': 'Deep Mahogany', 'hex': '#603010'},
      {'name': 'Ebony Bronze',  'hex': '#402008'},
    ],
  },

  // ── Hair Color Products ────────────────────────────────────────────────────

  {
    'id': 'hc_permanent_cream',
    'name': "Colour Couture Permanent Cream",
    'brand': "La Vogue Vista",
    'category': 'Hair Colors',
    'subCategory': 'Colour Match',
    'price': 3200,
    'rating': 4.6,
    'reviews': 312,
    'colorHex': '#3B1F0A',
    'imagePath': 'assets/products/hair colors/permanent_cream.png',
    'imageUrl': '',
    'description': "Professional-grade permanent cream hair colour with 100% grey coverage. Enriched with keratin and argan oil for silky, vibrant results that last 8–10 weeks.",
    'shades': [
      // Black
      {'name': 'Jet Black',            'hex': '#0F0F0F'},
      {'name': 'Natural Black',        'hex': '#1A0A00'},
      {'name': 'Blue Black',           'hex': '#0A0820'},
      {'name': 'Soft Black',           'hex': '#2C2C2C'},
      {'name': 'Plum Black',           'hex': '#1A0820'},
      // Dark Browns
      {'name': 'Espresso',             'hex': '#2A1008'},
      {'name': 'Dark Chocolate',       'hex': '#3B1A08'},
      {'name': 'Dark Brown',           'hex': '#4A2010'},
      {'name': 'Brown Black',          'hex': '#221408'},
      // Medium Browns
      {'name': 'Chestnut',             'hex': '#6B3020'},
      {'name': 'Medium Brown',         'hex': '#7A4520'},
      {'name': 'Rich Brown',           'hex': '#5E2C10'},
      {'name': 'Cinnamon Brown',       'hex': '#7D3D18'},
      {'name': 'Warm Brown',           'hex': '#8A4828'},
      {'name': 'Milk Chocolate',       'hex': '#7A3E1E'},
      // Caramel & Honey
      {'name': 'Golden Brown',         'hex': '#A86030'},
      {'name': 'Caramel',              'hex': '#B07040'},
      {'name': 'Light Brown',          'hex': '#B87040'},
      {'name': 'Honey Brown',          'hex': '#C07838'},
      {'name': 'Toffee',               'hex': '#C08040'},
      {'name': 'Warm Caramel',         'hex': '#C88840'},
      // Auburn & Spice
      {'name': 'Bright Auburn',        'hex': '#B55030'},
      {'name': 'Auburn Spice',         'hex': '#9B3015'},
      {'name': 'Warm Auburn',          'hex': '#8A3C22'},
      {'name': 'Rich Auburn',          'hex': '#7A3028'},
      {'name': 'Dark Auburn',          'hex': '#6B2810'},
      {'name': 'Cinnamon',             'hex': '#A06030'},
      {'name': 'Auburn Brown',         'hex': '#724040'},
      // Copper Tones
      {'name': 'Light Copper',         'hex': '#CC7830'},
      {'name': 'Mango Copper',         'hex': '#D26838'},
      {'name': 'Spiced Copper',        'hex': '#B86030'},
      {'name': 'Burnt Copper',         'hex': '#9E5020'},
      {'name': 'Bronze',               'hex': '#CC8030'},
      {'name': 'Caramel Copper',       'hex': '#D08840'},
      // Mahogany
      {'name': 'Red Mahogany',         'hex': '#7A2820'},
      {'name': 'Mahogany',             'hex': '#5E2820'},
      {'name': 'Dark Mahogany',        'hex': '#481815'},
      {'name': 'Choc. Mahogany',       'hex': '#5A2C28'},
      // Blonde
      {'name': 'Strawberry Blonde',    'hex': '#CC8850'},
      {'name': 'Dark Blonde',          'hex': '#B89050'},
      {'name': 'Golden Blonde',        'hex': '#D4A840'},
      {'name': 'Honey Blonde',         'hex': '#C89050'},
      {'name': 'Sandy Blonde',         'hex': '#C8A060'},
      {'name': 'Warm Blonde',          'hex': '#E0B870'},
      {'name': 'Ash Blonde',           'hex': '#B1A28A'},
      // Platinum & Icy
      {'name': 'Light Blonde',         'hex': '#DECB80'},
      {'name': 'Very Light Blonde',    'hex': '#E8D090'},
      {'name': 'Platinum Blonde',      'hex': '#EDE0B5'},
      {'name': 'Cool Platinum',        'hex': '#E5DCBA'},
      {'name': 'Icy Blonde',           'hex': '#F0EBE1'},
      {'name': 'Pearl Blonde',         'hex': '#F4F0E8'},
    ],
  },

  {
    'id': 'hc_fashion_vivid',
    'name': "Vivid Fantasy Fashion Colour",
    'brand': "La Vogue Vista",
    'category': 'Hair Colors',
    'subCategory': 'Colour Match',
    'price': 2800,
    'rating': 4.7,
    'reviews': 418,
    'colorHex': '#CC1515',
    'imagePath': 'assets/products/hair colors/vivid_fantasy.png',
    'imageUrl': '',
    'description': "Bold, ultra-vivid fashion hair colour for daring, statement looks. Semi-permanent formula fades beautifully. Best on pre-lightened hair.",
    'shades': [
      // Vibrant Reds
      {'name': 'Fire Red',             'hex': '#CC1515'},
      {'name': 'Pillar Box Red',       'hex': '#E02020'},
      {'name': 'True Red',             'hex': '#D72020'},
      {'name': 'Scarlet',              'hex': '#C41E3A'},
      {'name': 'Cherry Red',           'hex': '#9B1C25'},
      {'name': 'Passion Red',          'hex': '#B22222'},
      {'name': 'Vivid Crimson',        'hex': '#A01030'},
      // Burgundy & Wine
      {'name': 'Cherry Burgundy',      'hex': '#7A1830'},
      {'name': 'Burgundy',             'hex': '#6B2030'},
      {'name': 'Deep Burgundy',        'hex': '#4A0F1E'},
      {'name': 'Wine Red',             'hex': '#6B1428'},
      {'name': 'Bordeaux',             'hex': '#571022'},
      {'name': 'Cherry Cola',          'hex': '#5E2A30'},
      // Fashion Colors
      {'name': 'Rose Gold',            'hex': '#D48078'},
      {'name': 'Fuchsia',              'hex': '#CC1888'},
      {'name': 'Red Violet',           'hex': '#9A1060'},
      {'name': 'Purple',               'hex': '#6A1090'},
      {'name': 'Violet',               'hex': '#501878'},
      {'name': 'Lavender',             'hex': '#9080C0'},
      {'name': 'Indigo',               'hex': '#201878'},
      {'name': 'Cobalt Blue',          'hex': '#0047AB'},
      {'name': 'Teal',                 'hex': '#208080'},
      {'name': 'Silver',               'hex': '#909090'},
    ],
  },

  {
    'id': 'hc_gloss_refresh',
    'name': "Gloss & Refresh Toner",
    'brand': "La Vogue Vista",
    'category': 'Hair Colors',
    'subCategory': 'Colour Match',
    'price': 2200,
    'rating': 4.5,
    'reviews': 267,
    'colorHex': '#C89050',
    'imagePath': 'assets/products/hair colors/gloss_toner.png',
    'imageUrl': '',
    'description': "Shine-boosting toner that neutralises brassiness and refreshes colour between full applications. No developer needed — use after shampooing.",
    'shades': [
      // Platinum & Icy
      {'name': 'Icy Blonde',           'hex': '#F0EBE1'},
      {'name': 'Pearl Blonde',         'hex': '#F4F0E8'},
      {'name': 'Cool Platinum',        'hex': '#E5DCBA'},
      {'name': 'Platinum Blonde',      'hex': '#EDE0B5'},
      {'name': 'Very Light Blonde',    'hex': '#E8D090'},
      // Blonde
      {'name': 'Ash Blonde',           'hex': '#B1A28A'},
      {'name': 'Sandy Blonde',         'hex': '#C8A060'},
      {'name': 'Honey Blonde',         'hex': '#C89050'},
      {'name': 'Golden Blonde',        'hex': '#D4A840'},
      {'name': 'Warm Blonde',          'hex': '#E0B870'},
      {'name': 'Strawberry Blonde',    'hex': '#CC8850'},
      // Caramel & Honey (gloss refresh)
      {'name': 'Warm Caramel',         'hex': '#C88840'},
      {'name': 'Toffee',               'hex': '#C08040'},
      {'name': 'Honey Brown',          'hex': '#C07838'},
      {'name': 'Caramel',              'hex': '#B07040'},
      // Cool toners
      {'name': 'Rose Quartz',          'hex': '#D48078'},
      {'name': 'Violet Neutraliser',   'hex': '#9080C0'},
      {'name': 'Blue Ash',             'hex': '#7088B0'},
    ],
  },

  {
    'id': 'hc_colour_mask',
    'name': "Colour Treat & Tone Mask",
    'brand': "La Vogue Vista",
    'category': 'Hair Colors',
    'subCategory': 'Colour Match',
    'price': 2600,
    'rating': 4.6,
    'reviews': 289,
    'colorHex': '#9B3015',
    'imagePath': 'assets/products/hair colors/colour_mask.png',
    'imageUrl': '',
    'description': "2-in-1 semi-permanent colour depositing hair mask. Nourishes deeply while refreshing or adding a new tone. No developer needed — use as your regular conditioner.",
    'shades': [
      // Auburn & Spice
      {'name': 'Bright Auburn',        'hex': '#B55030'},
      {'name': 'Auburn Spice',         'hex': '#9B3015'},
      {'name': 'Warm Auburn',          'hex': '#8A3C22'},
      {'name': 'Rich Auburn',          'hex': '#7A3028'},
      {'name': 'Dark Auburn',          'hex': '#6B2810'},
      {'name': 'Cinnamon',             'hex': '#A06030'},
      // Copper Tones
      {'name': 'Light Copper',         'hex': '#CC7830'},
      {'name': 'Mango Copper',         'hex': '#D26838'},
      {'name': 'Spiced Copper',        'hex': '#B86030'},
      {'name': 'Burnt Copper',         'hex': '#9E5020'},
      {'name': 'Bronze',               'hex': '#CC8030'},
      {'name': 'Caramel Copper',       'hex': '#D08840'},
      // Mahogany
      {'name': 'Red Mahogany',         'hex': '#7A2820'},
      {'name': 'Mahogany',             'hex': '#5E2820'},
      {'name': 'Dark Mahogany',        'hex': '#481815'},
      // Burgundy & Wine
      {'name': 'Cherry Burgundy',      'hex': '#7A1830'},
      {'name': 'Burgundy',             'hex': '#6B2030'},
      {'name': 'Wine Red',             'hex': '#6B1428'},
      {'name': 'Cherry Cola',          'hex': '#5E2A30'},
      // Browns (conditioning refresh)
      {'name': 'Rich Brown',           'hex': '#5E2C10'},
      {'name': 'Chestnut',             'hex': '#6B3020'},
      {'name': 'Warm Brown',           'hex': '#8A4828'},
      {'name': 'Caramel',              'hex': '#B07040'},
      // Fashion tones
      {'name': 'Rose Gold',            'hex': '#D48078'},
      {'name': 'Violet',               'hex': '#501878'},
      {'name': 'Teal',                 'hex': '#208080'},
      {'name': 'Silver',               'hex': '#909090'},
    ],
  },

  {
    'id': 'hc_highlight_kit',
    'name': "Colour Lift Highlight Kit",
    'brand': "La Vogue Vista",
    'category': 'Hair Colors',
    'subCategory': 'Colour Match',
    'price': 4200,
    'rating': 4.8,
    'reviews': 534,
    'colorHex': '#D4A840',
    'imagePath': 'assets/products/hair colors/highlight_kit.png',
    'imageUrl': '',
    'description': "Complete at-home highlighting kit with pre-measured bleach, developer, and toner. Choose your highlight shade — from subtle sun-kissed to bold platinum streaks.",
    'shades': [
      // Platinum & Icy highlights
      {'name': 'Icy Blonde',           'hex': '#F0EBE1'},
      {'name': 'Pearl Blonde',         'hex': '#F4F0E8'},
      {'name': 'Platinum Streak',      'hex': '#EDE0B5'},
      {'name': 'Cool Platinum',        'hex': '#E5DCBA'},
      {'name': 'Very Light Blonde',    'hex': '#E8D090'},
      // Blonde highlights
      {'name': 'Warm Blonde',          'hex': '#E0B870'},
      {'name': 'Golden Blonde',        'hex': '#D4A840'},
      {'name': 'Sandy Blonde',         'hex': '#C8A060'},
      {'name': 'Honey Blonde',         'hex': '#C89050'},
      {'name': 'Strawberry Blonde',    'hex': '#CC8850'},
      {'name': 'Ash Blonde',           'hex': '#B1A28A'},
      // Caramel & balayage
      {'name': 'Warm Caramel',         'hex': '#C88840'},
      {'name': 'Toffee',               'hex': '#C08040'},
      {'name': 'Honey Brown',          'hex': '#C07838'},
      {'name': 'Caramel',              'hex': '#B07040'},
      {'name': 'Light Brown',          'hex': '#B87040'},
      {'name': 'Golden Brown',         'hex': '#A86030'},
      // Copper highlights
      {'name': 'Light Copper',         'hex': '#CC7830'},
      {'name': 'Mango Copper',         'hex': '#D26838'},
      {'name': 'Spiced Copper',        'hex': '#B86030'},
      {'name': 'Caramel Copper',       'hex': '#D08840'},
      // Auburn streaks
      {'name': 'Bright Auburn',        'hex': '#B55030'},
      {'name': 'Auburn Spice',         'hex': '#9B3015'},
      {'name': 'Rich Auburn',          'hex': '#7A3028'},
      // Rose Gold
      {'name': 'Rose Gold',            'hex': '#D48078'},
    ],
  },
];


// ─────────────────────────────────────────────────────────────────────────────
// Public entry point called from main()
// ─────────────────────────────────────────────────────────────────────────────

/// IDs of old face-product docs that were replaced by the subcategorised versions.
const _legacyFaceIds = ['fp_foundation', 'fp_powder', 'fp_blush'];

List<Map<String, dynamic>> _buildFaceAssetProducts() {
  const entries = <Map<String, String>>[
    // Blush
    {'sub': 'Blush', 'path': 'assets/products/face products/blush/blush.png', 'hex': '#E8A0A5'},
    {'sub': 'Blush', 'path': 'assets/products/face products/blush/blush_bonbon_coral.png', 'hex': '#E8A0A5'},
    {'sub': 'Blush', 'path': 'assets/products/face products/blush/blush_churro_gold.png', 'hex': '#D4A050'},
    {'sub': 'Blush', 'path': 'assets/products/face products/blush/blush_funfetti_soft_pink.png', 'hex': '#F9C0C8'},
    {'sub': 'Blush', 'path': 'assets/products/face products/blush/blush_jam_berry.png', 'hex': '#B84060'},
    {'sub': 'Blush', 'path': 'assets/products/face products/blush/blush_shortcake_pink.png', 'hex': '#E89090'},
    {'sub': 'Blush', 'path': 'assets/products/face products/blush/blush_souffle_mauve.png', 'hex': '#D88090'},
    {'sub': 'Blush', 'path': 'assets/products/face products/blush/blush_truffle_brown.png', 'hex': '#9A5848'},
    // Concealer
    {'sub': 'Concealer', 'path': 'assets/products/face products/concealer/concealer_deep_espresso.png', 'hex': '#603010'},
    {'sub': 'Concealer', 'path': 'assets/products/face products/concealer/concealer_fair_ivory.png', 'hex': '#F5E8D5'},
    {'sub': 'Concealer', 'path': 'assets/products/face products/concealer/concealer_light_nude.png', 'hex': '#EFD8C0'},
    {'sub': 'Concealer', 'path': 'assets/products/face products/concealer/concealer_medium_beige.png', 'hex': '#D8B888'},
    {'sub': 'Concealer', 'path': 'assets/products/face products/concealer/concealer_tan_sand.png', 'hex': '#A06830'},
    {'sub': 'Concealer', 'path': 'assets/products/face products/concealer/concealer_warm_honey.png', 'hex': '#C89860'},
    // Contour & Bronzer
    {'sub': 'Contour & Bronzer', 'path': 'assets/products/face products/contour_bronzer/bronzer_rich_cocoa.png', 'hex': '#805020'},
    {'sub': 'Contour & Bronzer', 'path': 'assets/products/face products/contour_bronzer/bronzer_sun_kissed.png', 'hex': '#C89050'},
    {'sub': 'Contour & Bronzer', 'path': 'assets/products/face products/contour_bronzer/bronzer_warm_bronze.png', 'hex': '#B07840'},
    {'sub': 'Contour & Bronzer', 'path': 'assets/products/face products/contour_bronzer/contour_deep_define.png', 'hex': '#906030'},
    {'sub': 'Contour & Bronzer', 'path': 'assets/products/face products/contour_bronzer/contour_medium.png', 'hex': '#A87848'},
    {'sub': 'Contour & Bronzer', 'path': 'assets/products/face products/contour_bronzer/contour_soft_sculpt.png', 'hex': '#C8A070'},
    // Foundation
    {'sub': 'Foundation', 'path': 'assets/products/face products/foundation/foundation.png', 'hex': '#D9B28D'},
    {'sub': 'Foundation', 'path': 'assets/products/face products/foundation/foundation_shade102_ivory.png', 'hex': '#F7EDE0'},
    {'sub': 'Foundation', 'path': 'assets/products/face products/foundation/foundation_shade115_vanilla.png', 'hex': '#EDD0B4'},
    {'sub': 'Foundation', 'path': 'assets/products/face products/foundation/foundation_shade230_natural_beige.png', 'hex': '#C68858'},
    {'sub': 'Foundation', 'path': 'assets/products/face products/foundation/foundation_shade310_golden.png', 'hex': '#AC6230'},
    {'sub': 'Foundation', 'path': 'assets/products/face products/foundation/foundation_shade340_warm_tan.png', 'hex': '#703606'},
    {'sub': 'Foundation', 'path': 'assets/products/face products/foundation/foundation_shade375_mocha.png', 'hex': '#261000'},
    // Highlighter
    {'sub': 'Highlighter', 'path': 'assets/products/face products/highlighter/highlighter_arctic_pearl.png', 'hex': '#E0E8F8'},
    {'sub': 'Highlighter', 'path': 'assets/products/face products/highlighter/highlighter_bronze_beam.png', 'hex': '#C89040'},
    {'sub': 'Highlighter', 'path': 'assets/products/face products/highlighter/highlighter_champagne_glow.png', 'hex': '#F5D888'},
    {'sub': 'Highlighter', 'path': 'assets/products/face products/highlighter/highlighter_golden_hour.png', 'hex': '#F0C840'},
    {'sub': 'Highlighter', 'path': 'assets/products/face products/highlighter/highlighter_peach_shimmer.png', 'hex': '#F0B880'},
    {'sub': 'Highlighter', 'path': 'assets/products/face products/highlighter/highlighter_rose_ice.png', 'hex': '#F0C0C8'},
    // Powder
    {'sub': 'Powder', 'path': 'assets/products/face products/powder/powder.png', 'hex': '#E2C9A8'},
    {'sub': 'Powder', 'path': 'assets/products/face products/powder/powder_ivory_finish.png', 'hex': '#F0DEC8'},
    {'sub': 'Powder', 'path': 'assets/products/face products/powder/powder_mineral_matte.png', 'hex': '#C8A878'},
    {'sub': 'Powder', 'path': 'assets/products/face products/powder/powder_natural_beige.png', 'hex': '#E2C9A8'},
    {'sub': 'Powder', 'path': 'assets/products/face products/powder/powder_sun_kissed_bronze.png', 'hex': '#B87840'},
    {'sub': 'Powder', 'path': 'assets/products/face products/powder/powder_translucent_setting.png', 'hex': '#F5EDE0'},
    {'sub': 'Powder', 'path': 'assets/products/face products/powder/powder_warm_honey.png', 'hex': '#D4A87A'},
  ];

  String titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  int priceFor(String sub) {
    switch (sub) {
      case 'Foundation':
        return 4800;
      case 'Powder':
        return 3600;
      case 'Blush':
        return 3200;
      case 'Concealer':
        return 3000;
      case 'Highlighter':
        return 3800;
      default:
        return 3500;
    }
  }

  return entries.map((e) {
    final path = e['path']!;
    final sub = e['sub']!;
    final file = path.split('/').last.replaceAll('.png', '');
    final clean = titleCase(file);
    final id = 'fp_asset_${file.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_').toLowerCase()}';
    final productName = clean == sub.toLowerCase() ? '$sub Variant' : clean;

    return <String, dynamic>{
      'id': id,
      'name': productName,
      'brand': "La Vogue Vista",
      'category': 'Makeup',
      'subCategory': sub,
      'price': priceFor(sub),
      'rating': 4.4,
      'reviews': 70,
      'colorHex': e['hex']!,
      'imagePath': path,
      'imageUrl': '',
      'description': '$sub product variant from the La Vogue Vista collection.',
      'shades': [
        {'name': clean, 'hex': e['hex']!},
      ],
    };
  }).toList();
}

/// Seeds missing products to Firestore AND updates existing ones.
/// Also removes any legacy IDs that have been superseded. Safe to call every app launch.
Future<void> seedAllProductsOnce() async {
  final db = FirebaseFirestore.instance;
  final col = db.collection('products');
  final allProducts = <Map<String, dynamic>>[
    ..._products,
    ..._buildFaceAssetProducts(),
  ];

  // 1. Remove legacy/stale face-product documents.
  for (final oldId in _legacyFaceIds) {
    try {
      final snap = await col.doc(oldId).get();
      if (snap.exists) {
        await col.doc(oldId).delete();
        debugPrint('🗑️  Removed legacy doc: $oldId');
      }
    } catch (e) {
      debugPrint('seed: could not delete $oldId — $e');
    }
  }

  // 2. Upsert all current products (full set to capture new fields like subCategory).
  var added = 0;
  var updated = 0;
  for (final p in allProducts) {
    final id = p['id'] as String;
    try {
      final snap = await col.doc(id).get();
      final data = Map<String, dynamic>.from(p)..remove('id');
      if (!snap.exists) {
        await col.doc(id).set(data);
        added++;
      } else {
        // Full set (merge) so all new fields (subCategory, imagePath, shades) are written.
        await col.doc(id).set(data, SetOptions(merge: true));
        updated++;
      }
    } catch (e) {
      debugPrint('seed: skipped $id — $e');
    }
  }

  debugPrint('✅ Seeded $added new + updated $updated (${allProducts.length} total). '
      'Removed ${_legacyFaceIds.length} legacy docs.');
}
