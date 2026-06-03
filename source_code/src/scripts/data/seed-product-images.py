#!/usr/bin/env python3
"""
scripts/data/seed-product-images.py
Download one product image per SKU and insert it into the nopCommerce
Picture / PictureBinary / Product_Picture_Mapping tables.

Image source: Unsplash CDN (no API key, direct photo IDs)
Usage:
    python3 scripts/data/seed-product-images.py          # both BUs
    python3 scripts/data/seed-product-images.py bua      # BU-A only
    python3 scripts/data/seed-product-images.py bub      # BU-B only
"""

import sys
import time
import urllib.request
import psycopg2
import psycopg2.extras

# ── Database connections (via exposed host ports) ─────────────────────────────
DBS = {
    "bua": dict(host="localhost", port=5433, dbname="nopcommerce",
                user="nopcommerce_bua", password="nopcommerce123"),
    "bub": dict(host="localhost", port=5434, dbname="nopcommerce",
                user="nopcommerce_bub", password="nopcommerce123"),
}

# ── Image map: SKU → (unsplash_photo_id, seo_filename, alt_text) ─────────────
# All images from Unsplash (public CDN, no auth needed)
# Format: https://images.unsplash.com/photo-{id}?w=800&q=80&auto=format&fit=crop
IMAGES = {
    # ── BU-A  HomeStyle Living ────────────────────────────────────────────────
    # Furniture
    "NSL-FUR-001": ("1555041469-a586c61ea9bc", "nordic-oak-dining-table",     "Nordic Oak Dining Table 6-Seater"),
    "NSL-FUR-002": ("1555041469-a586c61ea9bc", "velvet-3-seater-sofa",         "Velvet 3-Seater Sofa Charcoal"),
    "NSL-FUR-003": ("1631049307-72547b0c8f5e", "king-upholstered-bed-frame",   "King Upholstered Bed Frame"),
    "NSL-FUR-004": ("1507003211169-0a1dd7228f2d","scandinavian-solid-oak-bookcase","Scandinavian Solid Oak Bookcase"),
    "NSL-FUR-005": ("1598300042247-d088f8ab3a91", "rattan-wingback-armchair",  "Rattan Wingback Armchair"),
    "NSL-FUR-006": ("1555041469-a586c61ea9bc", "sintered-stone-coffee-table",  "Sintered Stone Coffee Table"),
    "NSL-FUR-007": ("1598300042247-d088f8ab3a91", "floating-shelves-set",      "Floating Shelves Set of 3"),
    # Kitchen & Dining
    "NSL-KIT-001": ("1556909114-f6e7ad7d3136", "artisan-cast-iron-dutch-oven", "Artisan Cast Iron Dutch Oven 4.7L"),
    "NSL-KIT-002": ("1556909114-f6e7ad7d3136", "bamboo-chopping-board-set",    "Bamboo Chopping Board Set of 3"),
    "NSL-KIT-003": ("1556909114-f6e7ad7d3136", "copper-clad-cookware-set",     "5-Piece Copper Clad Cookware Set"),
    "NSL-KIT-004": ("1526170375885-4d8ecf77b99f","porcelain-dinner-set",       "Porcelain Dinner Set 16-Piece"),
    "NSL-KIT-005": ("1495474472359-6904d4d4d4ce", "bean-to-cup-espresso-machine","Bean-to-Cup Espresso Machine"),
    # Bedding & Bath
    "NSL-BED-001": ("1631049307-72547b0c8f5e", "egyptian-cotton-duvet-set",    "1000TC Egyptian Cotton Duvet Set King"),
    "NSL-BED-002": ("1631049307-72547b0c8f5e", "luxury-memory-foam-pillow",    "Luxury Memory Foam Pillow Pair"),
    "NSL-BED-003": ("1528360983277-13d401cdc186","waffle-weave-towel-bale",     "Waffle-Weave Towel Bale 6-Piece"),
    "NSL-BED-004": ("1631049307-72547b0c8f5e", "dual-zone-electric-blanket",   "Dual-Zone Electric Blanket King"),
    "NSL-BED-005": ("1631049307-72547b0c8f5e", "bamboo-mattress-topper",       "Bamboo Mattress Topper 5cm King"),
    # Lighting & Decor
    "NSL-LIT-001": ("1507003211169-0a1dd7228f2d","arched-floor-lamp-brass",    "Arched Floor Lamp Brushed Brass"),
    "NSL-LIT-002": ("1507003211169-0a1dd7228f2d","smoked-glass-pendant-light", "Smoked Glass Pendant Light Cluster"),
    "NSL-LIT-003": ("1602173574-eefe74bc810a",   "luxury-scented-candle-set",  "Luxury Scented Candle Set of 3"),
    "NSL-LIT-004": ("1541123437800-f9f5db9e7e5e","abstract-canvas-triptych",   "Abstract Canvas Triptych 120x40"),
    "NSL-LIT-005": ("1558618666-fcd25c85cd64",   "smart-rgb-led-strip",        "Smart RGB LED Strip Light 5m"),
    # Garden & Outdoor
    "NSL-GDN-001": ("1555041469-a586c61ea9bc", "rattan-garden-furniture-set",  "6-Piece Rattan Garden Furniture Set"),
    "NSL-GDN-002": ("1416879595882-3373a0480b5b","solar-path-lights",          "Solar Path Lights Set of 10"),
    "NSL-GDN-003": ("1416879595882-3373a0480b5b","terracotta-plant-pots",      "Terracotta Plant Pots Set of 3"),
    "NSL-GDN-004": ("1416879595882-3373a0480b5b","heavy-duty-outdoor-storage", "Heavy-Duty Outdoor Storage Box"),
    # Smart Home
    "NSL-SMH-001": ("1558618666-fcd25c85cd64", "smart-learning-thermostat",    "Smart Learning Thermostat"),
    "NSL-SMH-002": ("1558618666-fcd25c85cd64", "2k-video-doorbell",            "2K Video Doorbell with Chime"),
    "NSL-SMH-003": ("1558618666-fcd25c85cd64", "smart-plug-energy-monitor",    "Smart Plug Energy Monitor 4-Pack"),
    "NSL-SMH-004": ("1558618666-fcd25c85cd64", "robot-vacuum-mop-combo",       "Robot Vacuum & Mop Combo"),
    # Storage
    "NSL-STG-001": ("1507003211169-0a1dd7228f2d","modular-wardrobe-system",    "Modular Wardrobe System with Drawers"),
    "NSL-STG-002": ("1507003211169-0a1dd7228f2d","over-door-shoe-organiser",   "Over-Door Shoe Organiser 24-Pocket"),
    "NSL-STG-003": ("1507003211169-0a1dd7228f2d","stackable-linen-storage",    "Stackable Linen Storage Boxes Set of 4"),

    # ── BU-B  WorkForge Industrial ────────────────────────────────────────────
    # Power Tools
    "WF-PWR-001": ("1581092795360-0e5e4a5f3d2e", "18v-brushless-combi-drill",  "18V Brushless Combi Drill"),
    "WF-PWR-002": ("1581092795360-0e5e4a5f3d2e", "angle-grinder-125mm",        "1400W Angle Grinder 125mm"),
    "WF-PWR-003": ("1581092795360-0e5e4a5f3d2e", "cordless-reciprocating-saw", "18V Cordless Reciprocating Saw"),
    "WF-PWR-004": ("1581092795360-0e5e4a5f3d2e", "20v-impact-driver",          "20V Impact Driver with Belt Clip"),
    "WF-PWR-005": ("1581092795360-0e5e4a5f3d2e", "bench-pillar-drill",         "Bench Pillar Drill 350W 13-Speed"),
    "WF-PWR-006": ("1581092795360-0e5e4a5f3d2e", "orbital-sander-400w",        "Random Orbital Sander 400W 125mm"),
    # Safety Equipment
    "WF-SFT-001": ("1504328345596-6defdc68d0e6","hard-hat-class-a-white",      "Class A Hard Hat Vented White"),
    "WF-SFT-002": ("1504328345596-6defdc68d0e6","safety-spectacles-anti-fog",  "Anti-Fog Safety Spectacles UV400"),
    "WF-SFT-003": ("1504328345596-6defdc68d0e6","cut-resistant-gloves-level-d","Cut-Resistant Gloves EN388 Level D"),
    "WF-SFT-004": ("1504328345596-6defdc68d0e6","hi-vis-waistcoat-class2",     "Hi-Vis Waistcoat Class 2 Yellow"),
    "WF-SFT-005": ("1504328345596-6defdc68d0e6","s3-composite-toe-safety-boot","S3 Composite-Toe Safety Boot"),
    # Lifting & Handling
    "WF-LFT-001": ("1581092795360-0e5e4a5f3d2e","2-tonne-low-profile-floor-jack","2-Tonne Low-Profile Floor Jack"),
    "WF-LFT-002": ("1581092795360-0e5e4a5f3d2e","2500kg-hand-pallet-truck",    "2500kg Hand Pallet Truck"),
    "WF-LFT-003": ("1581092795360-0e5e4a5f3d2e","3-tonne-chain-block-hoist",   "3-Tonne Chain Block Hoist"),
    "WF-LFT-004": ("1581092795360-0e5e4a5f3d2e","aluminium-platform-step-ladder","Aluminium Platform Step Ladder"),
    "WF-LFT-005": ("1581092795360-0e5e4a5f3d2e","heavy-duty-ratchet-straps",   "Heavy-Duty Ratchet Straps 5m x4 Set"),
    # Welding
    "WF-WLD-001": ("1581092795360-0e5e4a5f3d2e","mig-welder-180a-inverter",    "MIG Welder 180A Inverter Unit"),
    "WF-WLD-002": ("1581092795360-0e5e4a5f3d2e","auto-darkening-welding-helmet","Auto-Darkening Welding Helmet"),
    "WF-WLD-003": ("1581092795360-0e5e4a5f3d2e","mig-wire-316l-stainless",     "MIG Wire 316L Stainless Steel 5kg"),
    "WF-WLD-004": ("1581092795360-0e5e4a5f3d2e","50a-inverter-plasma-cutter",  "50A Inverter Plasma Cutter"),
    # Electrical
    "WF-ELC-001": ("1558618666-fcd25c85cd64","16a-industrial-extension-lead",  "16A Industrial Extension Lead 10m"),
    "WF-ELC-002": ("1558618666-fcd25c85cd64","pvc-cable-trunking-kit",         "PVC Cable Trunking Management Kit"),
    "WF-ELC-003": ("1558618666-fcd25c85cd64","digital-clamp-meter-600a",       "Digital Clamp Meter 600A AC/DC"),
    "WF-ELC-004": ("1558618666-fcd25c85cd64","100w-led-site-flood-light",      "100W IP65 LED Site Flood Light"),
    "WF-ELC-005": ("1558618666-fcd25c85cd64","rcd-protected-4-gang-extension", "RCD Protected 4-Gang Extension Block"),
    # Fasteners
    "WF-FST-001": ("1581092795360-0e5e4a5f3d2e","hex-bolt-assortment-m8-m16", "Hex Bolt Assortment Kit M8-M16"),
    "WF-FST-002": ("1581092795360-0e5e4a5f3d2e","stainless-self-tapping-screws","A2 Stainless Self-Tapping Screws"),
    "WF-FST-003": ("1581092795360-0e5e4a5f3d2e","chemical-anchor-rods-m10",   "Chemical Anchor Rods M10x130mm"),
    "WF-FST-004": ("1581092795360-0e5e4a5f3d2e","nyloc-nuts-flat-washers",     "Nyloc Nuts & Flat Washers Kit 300pc"),
    # Workwear
    "WF-WRK-001": ("1504328345596-6defdc68d0e6","fr-coveralls-en11612",        "Flame-Retardant Coveralls EN 11612"),
    "WF-WRK-002": ("1504328345596-6defdc68d0e6","waterproof-knee-pad-trousers","Waterproof Knee-Pad Work Trousers"),
    "WF-WRK-003": ("1504328345596-6defdc68d0e6","3m-half-face-respirator-p3",  "3M Half-Face Respirator P3 Kit"),
}

# Better Unsplash photo IDs per product — category-specific
# We override the generic IDs above with more specific photos:
PHOTO_IDS = {
    # Furniture / home interior
    "NSL-FUR-001": "1555041469-a586c61ea9bc",  # dining table wood
    "NSL-FUR-002": "1555041469-a586c61ea9bc",  # sofa living room
    "NSL-FUR-003": "1631049307-72547b0c8f5e",  # bedroom bed
    "NSL-FUR-004": "1507003211169-0a1dd7228f2d",# bookcase shelves
    "NSL-FUR-005": "1598300042247-d088f8ab3a91",# armchair
    "NSL-FUR-006": "1555041469-a586c61ea9bc",   # coffee table
    "NSL-FUR-007": "1507003211169-0a1dd7228f2d",# wall shelves
    # Kitchen
    "NSL-KIT-001": "1556909114-f6e7ad7d3136",   # cast iron pot
    "NSL-KIT-002": "1556909114-f6e7ad7d3136",   # kitchen boards
    "NSL-KIT-003": "1556909114-f6e7ad7d3136",   # cookware set
    "NSL-KIT-004": "1526170375885-4d8ecf77b99f",# dinner plates
    "NSL-KIT-005": "1495474472359-6904d4d4d4ce",# espresso machine
    # Bedding
    "NSL-BED-001": "1631049307-72547b0c8f5e",   # linen bedding
    "NSL-BED-002": "1631049307-72547b0c8f5e",   # pillows
    "NSL-BED-003": "1528360983277-13d401cdc186",# towels
    "NSL-BED-004": "1631049307-72547b0c8f5e",   # blanket
    "NSL-BED-005": "1631049307-72547b0c8f5e",   # mattress
    # Lighting / decor
    "NSL-LIT-001": "1507003211169-0a1dd7228f2d",# floor lamp
    "NSL-LIT-002": "1507003211169-0a1dd7228f2d",# pendant light
    "NSL-LIT-003": "1602173574-eefe74bc810a",   # candles
    "NSL-LIT-004": "1541123437800-f9f5db9e7e5e",# canvas art
    "NSL-LIT-005": "1558618666-fcd25c85cd64",   # LED strip
    # Garden
    "NSL-GDN-001": "1416879595882-3373a0480b5b",# garden furniture
    "NSL-GDN-002": "1416879595882-3373a0480b5b",# solar lights garden
    "NSL-GDN-003": "1416879595882-3373a0480b5b",# plant pots
    "NSL-GDN-004": "1416879595882-3373a0480b5b",# outdoor storage
    # Smart Home
    "NSL-SMH-001": "1558618666-fcd25c85cd64",   # smart home device
    "NSL-SMH-002": "1558618666-fcd25c85cd64",   # video doorbell
    "NSL-SMH-003": "1558618666-fcd25c85cd64",   # smart plug
    "NSL-SMH-004": "1558618666-fcd25c85cd64",   # robot vacuum
    # Storage
    "NSL-STG-001": "1507003211169-0a1dd7228f2d",# wardrobe bedroom
    "NSL-STG-002": "1507003211169-0a1dd7228f2d",# shoe storage
    "NSL-STG-003": "1507003211169-0a1dd7228f2d",# storage boxes
    # Power Tools
    "WF-PWR-001": "1504328345596-6defdc68d0e6", # drill
    "WF-PWR-002": "1504328345596-6defdc68d0e6", # angle grinder
    "WF-PWR-003": "1504328345596-6defdc68d0e6", # saw
    "WF-PWR-004": "1504328345596-6defdc68d0e6", # impact driver
    "WF-PWR-005": "1504328345596-6defdc68d0e6", # pillar drill
    "WF-PWR-006": "1504328345596-6defdc68d0e6", # orbital sander
    # Safety
    "WF-SFT-001": "1504328345596-6defdc68d0e6", # hard hat
    "WF-SFT-002": "1504328345596-6defdc68d0e6", # safety glasses
    "WF-SFT-003": "1504328345596-6defdc68d0e6", # gloves
    "WF-SFT-004": "1504328345596-6defdc68d0e6", # hi-vis
    "WF-SFT-005": "1504328345596-6defdc68d0e6", # safety boots
    # Lifting
    "WF-LFT-001": "1581092795360-0e5e4a5f3d2e", # floor jack
    "WF-LFT-002": "1581092795360-0e5e4a5f3d2e", # pallet truck
    "WF-LFT-003": "1581092795360-0e5e4a5f3d2e", # chain block
    "WF-LFT-004": "1581092795360-0e5e4a5f3d2e", # step ladder
    "WF-LFT-005": "1581092795360-0e5e4a5f3d2e", # ratchet straps
    # Welding
    "WF-WLD-001": "1581092795360-0e5e4a5f3d2e", # welder
    "WF-WLD-002": "1581092795360-0e5e4a5f3d2e", # welding helmet
    "WF-WLD-003": "1581092795360-0e5e4a5f3d2e", # welding wire
    "WF-WLD-004": "1581092795360-0e5e4a5f3d2e", # plasma cutter
    # Electrical
    "WF-ELC-001": "1558618666-fcd25c85cd64",    # extension lead
    "WF-ELC-002": "1558618666-fcd25c85cd64",    # cable trunking
    "WF-ELC-003": "1558618666-fcd25c85cd64",    # clamp meter
    "WF-ELC-004": "1558618666-fcd25c85cd64",    # site light
    "WF-ELC-005": "1558618666-fcd25c85cd64",    # RCD extension
    # Fasteners
    "WF-FST-001": "1581092795360-0e5e4a5f3d2e", # bolts assortment
    "WF-FST-002": "1581092795360-0e5e4a5f3d2e", # screws
    "WF-FST-003": "1581092795360-0e5e4a5f3d2e", # anchor rods
    "WF-FST-004": "1581092795360-0e5e4a5f3d2e", # nuts washers
    # Workwear
    "WF-WRK-001": "1504328345596-6defdc68d0e6", # coveralls
    "WF-WRK-002": "1504328345596-6defdc68d0e6", # work trousers
    "WF-WRK-003": "1504328345596-6defdc68d0e6", # respirator
}

# ── Loremflickr category-specific image URLs (reliable, no API key) ───────────
# Using loremflickr with keywords — these return actual matching photos
LOREMFLICKR_URLS = {
    # BU-A HomeStyle
    "NSL-FUR-001": "https://loremflickr.com/800/600/dining,table,wooden,interior?lock=1001",
    "NSL-FUR-002": "https://loremflickr.com/800/600/sofa,velvet,livingroom?lock=1002",
    "NSL-FUR-003": "https://loremflickr.com/800/600/bed,bedroom,upholstered?lock=1003",
    "NSL-FUR-004": "https://loremflickr.com/800/600/bookcase,bookshelf,wooden?lock=1004",
    "NSL-FUR-005": "https://loremflickr.com/800/600/armchair,rattan,interior?lock=1005",
    "NSL-FUR-006": "https://loremflickr.com/800/600/coffeetable,marble,living?lock=1006",
    "NSL-FUR-007": "https://loremflickr.com/800/600/shelves,wall,wooden,floating?lock=1007",
    "NSL-KIT-001": "https://loremflickr.com/800/600/castiron,dutch,oven,cookware?lock=1008",
    "NSL-KIT-002": "https://loremflickr.com/800/600/chopping,board,kitchen,bamboo?lock=1009",
    "NSL-KIT-003": "https://loremflickr.com/800/600/cookware,copper,pots,kitchen?lock=1010",
    "NSL-KIT-004": "https://loremflickr.com/800/600/dinner,plates,ceramic,table?lock=1011",
    "NSL-KIT-005": "https://loremflickr.com/800/600/espresso,coffee,machine,cafe?lock=1012",
    "NSL-BED-001": "https://loremflickr.com/800/600/bedding,duvet,linen,bedroom?lock=1013",
    "NSL-BED-002": "https://loremflickr.com/800/600/pillow,memory,foam,sleep?lock=1014",
    "NSL-BED-003": "https://loremflickr.com/800/600/towels,bath,waffle,cotton?lock=1015",
    "NSL-BED-004": "https://loremflickr.com/800/600/blanket,electric,heated,bedroom?lock=1016",
    "NSL-BED-005": "https://loremflickr.com/800/600/mattress,topper,bamboo,sleep?lock=1017",
    "NSL-LIT-001": "https://loremflickr.com/800/600/floor,lamp,brass,interior?lock=1018",
    "NSL-LIT-002": "https://loremflickr.com/800/600/pendant,light,glass,ceiling?lock=1019",
    "NSL-LIT-003": "https://loremflickr.com/800/600/candle,soy,wax,luxury?lock=1020",
    "NSL-LIT-004": "https://loremflickr.com/800/600/canvas,abstract,art,wall?lock=1021",
    "NSL-LIT-005": "https://loremflickr.com/800/600/led,strip,rgb,light?lock=1022",
    "NSL-GDN-001": "https://loremflickr.com/800/600/garden,rattan,patio,furniture?lock=1023",
    "NSL-GDN-002": "https://loremflickr.com/800/600/solar,garden,lights,path?lock=1024",
    "NSL-GDN-003": "https://loremflickr.com/800/600/terracotta,plant,pots,garden?lock=1025",
    "NSL-GDN-004": "https://loremflickr.com/800/600/outdoor,storage,box,garden?lock=1026",
    "NSL-SMH-001": "https://loremflickr.com/800/600/smart,thermostat,home,display?lock=1027",
    "NSL-SMH-002": "https://loremflickr.com/800/600/video,doorbell,smart,home?lock=1028",
    "NSL-SMH-003": "https://loremflickr.com/800/600/smart,plug,socket,wifi?lock=1029",
    "NSL-SMH-004": "https://loremflickr.com/800/600/robot,vacuum,cleaner,floor?lock=1030",
    "NSL-STG-001": "https://loremflickr.com/800/600/wardrobe,bedroom,white,storage?lock=1031",
    "NSL-STG-002": "https://loremflickr.com/800/600/shoe,organiser,storage,rack?lock=1032",
    "NSL-STG-003": "https://loremflickr.com/800/600/storage,boxes,linen,basket?lock=1033",
    # BU-B WorkForge Industrial
    "WF-PWR-001": "https://loremflickr.com/800/600/cordless,drill,power,tool?lock=2001",
    "WF-PWR-002": "https://loremflickr.com/800/600/angle,grinder,metalwork?lock=2002",
    "WF-PWR-003": "https://loremflickr.com/800/600/reciprocating,saw,cordless?lock=2003",
    "WF-PWR-004": "https://loremflickr.com/800/600/impact,driver,drill,cordless?lock=2004",
    "WF-PWR-005": "https://loremflickr.com/800/600/pillar,drill,workshop,bench?lock=2005",
    "WF-PWR-006": "https://loremflickr.com/800/600/orbital,sander,woodwork?lock=2006",
    "WF-SFT-001": "https://loremflickr.com/800/600/hard,hat,construction,safety?lock=2007",
    "WF-SFT-002": "https://loremflickr.com/800/600/safety,glasses,goggles,ppe?lock=2008",
    "WF-SFT-003": "https://loremflickr.com/800/600/work,gloves,safety,industrial?lock=2009",
    "WF-SFT-004": "https://loremflickr.com/800/600/high,visibility,vest,worker?lock=2010",
    "WF-SFT-005": "https://loremflickr.com/800/600/safety,boots,steel,toe?lock=2011",
    "WF-LFT-001": "https://loremflickr.com/800/600/floor,jack,hydraulic,car?lock=2012",
    "WF-LFT-002": "https://loremflickr.com/800/600/pallet,truck,warehouse,forklift?lock=2013",
    "WF-LFT-003": "https://loremflickr.com/800/600/chain,hoist,block,lifting?lock=2014",
    "WF-LFT-004": "https://loremflickr.com/800/600/step,ladder,aluminium,platform?lock=2015",
    "WF-LFT-005": "https://loremflickr.com/800/600/ratchet,straps,cargo,strap?lock=2016",
    "WF-WLD-001": "https://loremflickr.com/800/600/mig,welder,welding,industrial?lock=2017",
    "WF-WLD-002": "https://loremflickr.com/800/600/welding,helmet,auto,darkening?lock=2018",
    "WF-WLD-003": "https://loremflickr.com/800/600/welding,wire,mig,stainless?lock=2019",
    "WF-WLD-004": "https://loremflickr.com/800/600/plasma,cutter,metal,cutting?lock=2020",
    "WF-ELC-001": "https://loremflickr.com/800/600/extension,lead,industrial,cable?lock=2021",
    "WF-ELC-002": "https://loremflickr.com/800/600/cable,trunking,management,wiring?lock=2022",
    "WF-ELC-003": "https://loremflickr.com/800/600/clamp,meter,multimeter,electrical?lock=2023",
    "WF-ELC-004": "https://loremflickr.com/800/600/led,flood,light,site,work?lock=2024",
    "WF-ELC-005": "https://loremflickr.com/800/600/rcd,extension,socket,electrical?lock=2025",
    "WF-FST-001": "https://loremflickr.com/800/600/hex,bolts,nuts,stainless,assortment?lock=2026",
    "WF-FST-002": "https://loremflickr.com/800/600/screws,self-tapping,stainless?lock=2027",
    "WF-FST-003": "https://loremflickr.com/800/600/anchor,chemical,bolt,concrete?lock=2028",
    "WF-FST-004": "https://loremflickr.com/800/600/nuts,washers,stainless,assortment?lock=2029",
    "WF-WRK-001": "https://loremflickr.com/800/600/coveralls,workwear,flame,retardant?lock=2030",
    "WF-WRK-002": "https://loremflickr.com/800/600/work,trousers,knee,pad,waterproof?lock=2031",
    "WF-WRK-003": "https://loremflickr.com/800/600/respirator,mask,dust,ppe,3m?lock=2032",
}


def download_image(url: str, retries: int = 3) -> bytes:
    """Download image bytes from URL with retries."""
    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                      "AppleWebKit/537.36 (KHTML, like Gecko) "
                      "Chrome/120.0.0.0 Safari/537.36",
        "Accept": "image/webp,image/apng,image/*,*/*;q=0.8",
    }
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
                content_type = resp.headers.get("Content-Type", "image/jpeg")
                return data, content_type.split(";")[0].strip()
        except Exception as e:
            if attempt < retries - 1:
                print(f"  ↻ retry {attempt + 1}: {e}")
                time.sleep(2)
            else:
                raise


def seed_images_for_bu(bu_name: str, db_config: dict, skus: list):
    """Download and insert images for a BU."""
    print(f"\n{'═' * 60}")
    print(f"  Seeding images: {bu_name.upper()}")
    print(f"{'═' * 60}")

    conn = psycopg2.connect(**db_config)
    conn.autocommit = False
    cur = conn.cursor()

    # Ensure storesindb is True (store images in database)
    cur.execute("""
        INSERT INTO "Setting" ("Name","Value","StoreId")
        VALUES ('mediasettings.storesindb','True',0)
        ON CONFLICT DO NOTHING;
        UPDATE "Setting" SET "Value"='True'
        WHERE "Name"='mediasettings.storesindb';
    """)

    ok = 0
    failed = []

    for sku in skus:
        info = IMAGES.get(sku)
        if not info:
            print(f"  ⚠  No image config for {sku}, skipping")
            continue

        _, seo_name, alt_text = info
        url = LOREMFLICKR_URLS.get(sku, f"https://loremflickr.com/800/600/product?lock={abs(hash(sku)) % 9999}")

        print(f"  ↓ {sku:20s}  {seo_name[:40]}", end="", flush=True)

        try:
            img_data, mime_type = download_image(url)

            # Check if product already has a picture
            cur.execute("""
                SELECT COUNT(*) FROM "Product_Picture_Mapping" ppm
                JOIN "Product" p ON ppm."ProductId" = p."Id"
                WHERE p."Sku" = %s
            """, (sku,))
            if cur.fetchone()[0] > 0:
                print("  [already has image, skipping]")
                continue

            # Insert Picture record
            cur.execute("""
                INSERT INTO "Picture" ("MimeType","SeoFilename","AltAttribute","TitleAttribute","IsNew","VirtualPath")
                VALUES (%s, %s, %s, %s, false, NULL)
                RETURNING "Id"
            """, (mime_type, seo_name, alt_text, alt_text))
            picture_id = cur.fetchone()[0]

            # Insert binary data
            cur.execute("""
                INSERT INTO "PictureBinary" ("PictureId","BinaryData")
                VALUES (%s, %s)
            """, (picture_id, psycopg2.Binary(img_data)))

            # Link to product
            cur.execute("""
                INSERT INTO "Product_Picture_Mapping" ("ProductId","PictureId","DisplayOrder")
                SELECT p."Id", %s, 1
                FROM "Product" p
                WHERE p."Sku" = %s
            """, (picture_id, sku))

            # Mark product for cache invalidation
            cur.execute("""
                UPDATE "Product" SET "UpdatedOnUtc" = NOW()
                WHERE "Sku" = %s
            """, (sku,))

            conn.commit()
            size_kb = len(img_data) // 1024
            print(f"  ✓  ({size_kb} KB, PictureId={picture_id})")
            ok += 1

        except Exception as e:
            conn.rollback()
            print(f"  ✗  FAILED: {e}")
            failed.append(sku)

        time.sleep(0.3)  # be polite to the image CDN

    cur.close()
    conn.close()

    print(f"\n  Summary: {ok}/{len(skus)} images loaded" + (f", {len(failed)} failed: {failed}" if failed else ""))
    return ok, failed


def main():
    target = sys.argv[1].lower() if len(sys.argv) > 1 else "both"

    bua_skus = [s for s in IMAGES if s.startswith("NSL-")]
    bub_skus = [s for s in IMAGES if s.startswith("WF-")]

    total_ok = 0
    total_fail = []

    if target in ("bua", "a", "both"):
        ok, fail = seed_images_for_bu("BU-A HomeStyle Living", DBS["bua"], bua_skus)
        total_ok += ok
        total_fail.extend(fail)

    if target in ("bub", "b", "both"):
        ok, fail = seed_images_for_bu("BU-B WorkForge Industrial", DBS["bub"], bub_skus)
        total_ok += ok
        total_fail.extend(fail)

    print(f"\n{'═' * 60}")
    print(f"  DONE — {total_ok} images inserted total")
    if total_fail:
        print(f"  Failed SKUs: {total_fail}")
    print(f"{'═' * 60}")


if __name__ == "__main__":
    main()

