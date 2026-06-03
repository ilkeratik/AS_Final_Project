-- =============================================================================
-- Northstar Living Group — BU-B: WorkForge Industrial
-- Replaces nopCommerce sample products/categories with WorkForge catalogue.
-- Idempotent: safe to re-run on a fresh-installed database.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Clear all product-related data (safe on fresh install — no real orders)
-- ---------------------------------------------------------------------------
DELETE FROM "ProductReview_ReviewType_Mapping";
DELETE FROM "ProductReviewHelpfulness";
DELETE FROM "ProductReview";
DELETE FROM "ProductAttributeCombinationPicture";
DELETE FROM "ProductAttributeCombination";
DELETE FROM "ProductAttributeValue";
DELETE FROM "Product_ProductAttribute_Mapping";
DELETE FROM "Product_SpecificationAttribute_Mapping";
DELETE FROM "Product_ProductTag_Mapping";
DELETE FROM "Product_Picture_Mapping";
DELETE FROM "CrossSellProduct";
DELETE FROM "RelatedProduct";
DELETE FROM "Discount_AppliedToProducts";
DELETE FROM "FilterLevelValueProductMapping";
DELETE FROM "ProductWarehouseInventory";
DELETE FROM "ProductVideo";
DELETE FROM "Product_Category_Mapping";
DELETE FROM "Product_Manufacturer_Mapping";
DELETE FROM "Product";
DELETE FROM "UrlRecord" WHERE "EntityName" = 'Product';
DELETE FROM "UrlRecord" WHERE "EntityName" = 'Category';
DELETE FROM "Category";

-- Reset sequences
SELECT setval(pg_get_serial_sequence('"Product"','Id'), 1, false);
SELECT setval(pg_get_serial_sequence('"Category"','Id'), 1, false);
SELECT setval(pg_get_serial_sequence('"Product_Category_Mapping"','Id'), 1, false);
SELECT setval(pg_get_serial_sequence('"UrlRecord"','Id'), (SELECT MAX("Id") FROM "UrlRecord") + 1, false);

-- ---------------------------------------------------------------------------
-- 2. Update TaxCategory names to WorkForge context
-- ---------------------------------------------------------------------------
UPDATE "TaxCategory" SET "Name" = 'Industrial Equipment & Tools'  WHERE "Id" = 2;
UPDATE "TaxCategory" SET "Name" = 'Safety & PPE'                  WHERE "Id" = 5;

-- ---------------------------------------------------------------------------
-- 3. Categories
-- ---------------------------------------------------------------------------
INSERT INTO "Category"
  ("Id","Name","CategoryTemplateId","ParentCategoryId","PictureId","PageSize",
   "AllowCustomersToSelectPageSize","ShowOnHomepage","SubjectToAcl","LimitedToStores",
   "Published","Deleted","DisplayOrder","CreatedOnUtc","UpdatedOnUtc",
   "PriceRangeFiltering","PriceFrom","PriceTo","ManuallyPriceRange","RestrictFromVendors",
   "Description","MetaKeywords","MetaTitle","PageSizeOptions")
VALUES
  (1,'Power Tools',          1,0,0,12,true,true, false,false,true,false,1,NOW(),NOW(),false,0,0,false,false,
   'Professional-grade power tools for every trade and workshop.','power tools, drills, grinders, saws','Power Tools','6, 3, 9'),
  (2,'Safety Equipment',     1,0,0,12,true,false,false,false,true,false,2,NOW(),NOW(),false,0,0,false,false,
   'PPE and safety equipment to keep your workforce protected.','safety, PPE, hard hat, gloves, hi-vis','Safety Equipment','6, 3, 9'),
  (3,'Lifting & Handling',   1,0,0,12,true,false,false,false,true,false,3,NOW(),NOW(),false,0,0,false,false,
   'Jacks, hoists, pallet trucks and access equipment.','lifting, hoist, pallet truck, floor jack','Lifting & Handling','6, 3, 9'),
  (4,'Welding Supplies',     1,0,0,12,true,false,false,false,true,false,4,NOW(),NOW(),false,0,0,false,false,
   'MIG welders, plasma cutters, helmets and consumables.','welding, MIG, plasma cutter, welder','Welding Supplies','6, 3, 9'),
  (5,'Electrical & Wiring',  1,0,0,12,true,false,false,false,true,false,5,NOW(),NOW(),false,0,0,false,false,
   'Extension leads, cable management, meters and site lighting.','electrical, extension lead, cable, RCD','Electrical & Wiring','6, 3, 9'),
  (6,'Fasteners & Hardware', 1,0,0,12,true,false,false,false,true,false,6,NOW(),NOW(),false,0,0,false,false,
   'Industrial-grade bolts, screws, anchors and fixings.','fasteners, bolts, screws, anchors, fixings','Fasteners & Hardware','6, 3, 9'),
  (7,'Workwear & PPE',       1,0,0,12,true,false,false,false,true,false,7,NOW(),NOW(),false,0,0,false,false,
   'Durable workwear, safety footwear and specialist PPE.','workwear, safety boots, overalls, PPE','Workwear & PPE','6, 3, 9');

-- ---------------------------------------------------------------------------
-- 4. Products  (ProductTypeId=5=Simple, ProductTemplateId=1, TaxCategoryId=2)
-- ---------------------------------------------------------------------------
INSERT INTO "Product"
  ("Name","Sku","ShortDescription","FullDescription","Price","Weight",
   "ProductTypeId","ParentGroupedProductId","VisibleIndividually",
   "ProductTemplateId","VendorId","ShowOnHomepage","AllowCustomerReviews",
   "ApprovedRatingSum","NotApprovedRatingSum","ApprovedTotalReviews","NotApprovedTotalReviews",
   "SubjectToAcl","LimitedToStores","IsGiftCard","GiftCardTypeId","OverriddenGiftCardAmount",
   "RequireOtherProducts","AutomaticallyAddRequiredProducts",
   "IsDownload","DownloadId","UnlimitedDownloads","MaxNumberOfDownloads","DownloadActivationTypeId",
   "HasSampleDownload","SampleDownloadId","HasUserAgreement",
   "IsRecurring","RecurringCycleLength","RecurringCyclePeriodId","RecurringTotalCycles",
   "IsRental","RentalPriceLength","RentalPricePeriodId",
   "IsShipEnabled","IsFreeShipping","ShipSeparately","AdditionalShippingCharge","DeliveryDateId",
   "IsTaxExempt","TaxCategoryId","ManageInventoryMethodId","ProductAvailabilityRangeId",
   "UseMultipleWarehouses","WarehouseId","StockQuantity",
   "DisplayStockAvailability","DisplayStockQuantity","MinStockQuantity","LowStockActivityId",
   "NotifyAdminForQuantityBelow","BackorderModeId","AllowBackInStockSubscriptions",
   "OrderMinimumQuantity","OrderMaximumQuantity",
   "AllowAddingOnlyExistingAttributeCombinations","DisplayAttributeCombinationImagesOnly",
   "NotReturnable","DisableBuyButton","DisableWishlistButton",
   "AvailableForPreOrder","CallForPrice",
   "OldPrice","ProductCost","CustomerEntersPrice","MinimumCustomerEnteredPrice","MaximumCustomerEnteredPrice",
   "BasepriceEnabled","BasepriceAmount","BasepriceUnitId","BasepriceBaseAmount","BasepriceBaseUnitId",
   "MarkAsNew","Length","Width","Height","DisplayOrder","Published","Deleted",
   "AgeVerification","MinimumAgeToPurchase","MetaKeywords","MetaTitle","MetaDescription",
   "RequiredProductIds","AllowedQuantities","AdminComment","CreatedOnUtc","UpdatedOnUtc")
VALUES

-- ── Power Tools (category 1) ─────────────────────────────────────────────────
('18V Brushless Combi Drill — Twin-Battery Kit', 'WF-PWR-001',
 '18V Li-Ion brushless combi drill with 2×2Ah batteries, charger and case.',
 '<p>The WorkForge 18V Brushless Combi Drill delivers class-leading torque in a compact form. The brushless motor extends battery life and runtime by up to 50%. Includes 2×2Ah Li-Ion batteries with charge-level indicator, 30-minute rapid charger and heavy-duty carry case. 21+1 torque settings, 2-speed gearbox (0–550 / 0–2000 rpm), 13mm keyless chuck. Max torque: 65Nm. Ideal for drilling into masonry, wood and metal.</p>',
 189.99, 4.80, 5,0,true, 1,0,true,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,50,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,22,9,22,1,true,false,
 false,0,'combi drill, 18V, brushless, cordless tools','18V Brushless Combi Drill','18V Li-Ion brushless combi drill twin-battery kit with case.',
 NULL,NULL,NULL,NOW(),NOW()),

('1400W Angle Grinder 125mm',                    'WF-PWR-002',
 'Heavy-duty 1400W corded angle grinder with toolless guard adjustment.',
 '<p>Cut, grind and sand with confidence using our 1400W Angle Grinder. The 125mm disc size and 11,000 rpm no-load speed handle heavy metalwork with ease. Toolless guard adjustment allows rapid 90° repositioning. Anti-vibration grip, restart protection and a spindle lock for safe disc changes. Accepts standard 5/8-11 UNF spindle accessories. Supplied with side handle and grinding disc.</p>',
 79.99, 2.30, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,60,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,30,8,20,2,true,false,
 false,0,'angle grinder, 125mm, 1400W, power tool','1400W Angle Grinder 125mm','1400W corded 125mm angle grinder with toolless guard adjustment.',
 NULL,NULL,NULL,NOW(),NOW()),

('18V Cordless Reciprocating Saw',              'WF-PWR-003',
 'Variable-speed cordless recip saw with tool-free blade clamp.',
 '<p>Tackle demolition and rough-cutting work with our 18V Cordless Reciprocating Saw. Variable-speed trigger (0–3,000 spm) and 28mm stroke length give precise control through timber, steel and PVC pipe. Tool-free blade clamp accepts standard T-shank and U-shank blades. Orbital action setting for faster cutting through wood. 18V compatible with WorkForge Li-Ion battery platform. Battery sold separately.</p>',
 149.99, 2.60, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,40,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,46,8,22,3,true,false,
 false,0,'reciprocating saw, cordless, 18V, demolition','18V Cordless Reciprocating Saw','18V cordless recip saw with variable speed and tool-free blade clamp.',
 NULL,NULL,NULL,NOW(),NOW()),

('20V Impact Driver with Belt Clip',            'WF-PWR-004',
 '20V cordless impact driver with 3-speed mode, LED and belt clip.',
 '<p>Drive screws and bolts faster with our 20V Impact Driver. Delivers 200Nm of maximum torque with three selectable speed/impact modes for precise control. Quick-release 1/4" hex chuck accepts all standard bits. Built-in LED work light illuminates the workspace. Compact 122mm head length reaches into tight spaces. Belt clip included. 20V Li-Ion compatible. Battery and charger sold separately.</p>',
 159.99, 1.80, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,55,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,20,8,18,4,true,false,
 false,0,'impact driver, 20V, cordless, screwdriving','20V Impact Driver with Belt Clip','20V cordless 3-speed impact driver, 200Nm, LED, belt clip.',
 NULL,NULL,NULL,NOW(),NOW()),

('Bench Pillar Drill 350W 13-Speed',            'WF-PWR-005',
 'Heavy-duty bench pillar drill with 350W motor and 16mm chuck capacity.',
 '<p>Achieve precision hole-making with our Bench Pillar Drill. The 350W induction motor and 13-speed belt-drive system (180–2,580 rpm) handles wood, aluminium and mild steel up to 16mm diameter. Rack-and-pinion table raises from 200mm to 530mm. 360° swivel table with 45° tilt. Depth stop with scale, crank-feed handle and integrated work light. Requires 230V single-phase supply.</p>',
 229.00, 28.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,20,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,45,35,80,5,true,false,
 false,0,'pillar drill, bench drill, 350W, workshop','Bench Pillar Drill 350W 13-Speed','350W bench pillar drill with 13-speed belt drive and 16mm chuck.',
 NULL,NULL,NULL,NOW(),NOW()),

('Random Orbital Sander 400W 125mm',            'WF-PWR-006',
 '400W orbital sander with 6-speed dial, dust bag and 10 sanding sheets.',
 '<p>Achieve a professional finish every time with our Random Orbital Sander. The 400W motor and 6-speed dial (4,500–12,000 rpm) make light work of paint stripping, rust removal and fine finishing. 125mm hook-and-loop sanding pad accepts standard 8-hole discs. Integrated dust-collection bag with 70% efficiency. Includes 10 mixed-grit sanding sheets. Vibration-damped grip reduces fatigue on long jobs.</p>',
 59.99, 1.60, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,70,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,25,15,18,6,true,false,
 false,0,'orbital sander, 400W, 125mm, finishing','Random Orbital Sander 400W 125mm','400W random orbital sander with 6-speed dial and dust extraction.',
 NULL,NULL,NULL,NOW(),NOW()),

-- ── Safety Equipment (category 2) ────────────────────────────────────────────
('Class A Hard Hat Vented White',               'WF-SFT-001',
 'EN397 class A safety helmet with 6-point ratchet suspension and slots for accessories.',
 '<p>Protect against falling objects with our EN397-certified Class A Hard Hat. The high-density polyethylene shell withstands lateral and top impact. The 6-point ratchet suspension adjusts from 51cm to 63cm head circumference. Pre-formed slots accept ear defenders, face shields and visors (sold separately). Padded sweatband and ventilation slots. Available in white, yellow, red and blue. CE marked.</p>',
 19.99, 0.35, 5,0,true, 1,0,true,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,5,1,0, false,0,200,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,28,22,14,1,true,false,
 false,0,'hard hat, safety helmet, EN397, PPE','Class A Hard Hat Vented White','EN397 class A vented hard hat with 6-point ratchet, 51–63cm.',
 NULL,NULL,NULL,NOW(),NOW()),

('Anti-Fog Safety Spectacles UV400',            'WF-SFT-002',
 'Clear-lens polycarbonate safety glasses with anti-fog and UV400 coating.',
 '<p>Keep your eyes protected in all conditions with our Anti-Fog Safety Spectacles. Polycarbonate lenses rated EN166 and EN170 provide impact resistance and UV400 protection. The durable anti-fog coating prevents condensation during temperature changes. Wraparound design with soft adjustable temple tips for all-day comfort. Supplied in a microfibre pouch. CE marked.</p>',
 8.99, 0.05, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,5,1,0, false,0,300,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,16,6,4,2,true,false,
 false,0,'safety glasses, anti-fog, UV400, PPE','Anti-Fog Safety Spectacles UV400','EN166 polycarbonate safety spectacles with anti-fog UV400 coating.',
 NULL,NULL,NULL,NOW(),NOW()),

('Cut-Resistant Gloves EN388 Level D',          'WF-SFT-003',
 'High-dexterity cut-resistant gloves rated EN388:2016 Level D.',
 '<p>Handle sharp materials with confidence using our Level D Cut-Resistant Gloves. The Dyneema fibre liner is 15× stronger than steel by weight, while the nitrile foam coating on the palm and fingers gives a sure grip in dry, wet and oily conditions. EN388:2016 rated for cut (Level D), abrasion (4), tear (3) and puncture (2). Seamless construction for all-day comfort. Available in sizes 7–11.</p>',
 24.99, 0.10, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,5,1,0, false,0,250,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,25,12,3,3,true,false,
 false,0,'cut resistant gloves, EN388, Dyneema, PPE','Cut-Resistant Gloves EN388 Level D','EN388 Level D Dyneema cut-resistant gloves with nitrile foam coating.',
 NULL,NULL,NULL,NOW(),NOW()),

('Hi-Vis Waistcoat Class 2 Yellow',             'WF-SFT-004',
 'EN ISO 20471 Class 2 hi-vis waistcoat with two front pockets.',
 '<p>Stay visible in all lighting conditions with our Class 2 Hi-Vis Waistcoat. Meets EN ISO 20471:2013 Class 2 with 360° retroreflective bands and fluorescent yellow fabric. Two front zip pockets, left-chest ID holder pocket and a full-length zip. Breathable mesh back panel for comfort in warm weather. Available sizes S–3XL. Machine washable at 40°C.</p>',
 9.99, 0.20, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,5,1,0, false,0,500,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,65,10,55,4,true,false,
 false,0,'hi-vis vest, high visibility, Class 2, EN ISO 20471','Hi-Vis Waistcoat Class 2 Yellow','EN ISO 20471 Class 2 hi-vis waistcoat with zip and pockets.',
 NULL,NULL,NULL,NOW(),NOW()),

('S3 Composite-Toe Safety Boot',                'WF-SFT-005',
 'Lightweight S3 safety boot with composite toecap, midsole and waterproof membrane.',
 '<p>All-day protection without the weight. Our S3 Composite-Toe Safety Boot features a 200J-rated composite toecap and a penetration-resistant composite midsole — no metal means no cold spots and airport-friendly wear. The waterproof membrane keeps feet dry in wet environments. SRC slip-resistant rubber outsole rated for oil and fuel. ESD-compliant. EN ISO 20345:2022 certified. Available sizes 6–13 (UK).</p>',
 89.99, 1.20, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,5,1,0, false,0,80,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,30,12,20,5,true,false,
 false,0,'safety boots, S3, composite toe, waterproof','S3 Composite-Toe Safety Boot','S3 composite-toecap waterproof safety boot, EN ISO 20345, SRC rated.',
 NULL,NULL,NULL,NOW(),NOW()),

-- ── Lifting & Handling (category 3) ──────────────────────────────────────────
('2-Tonne Low-Profile Floor Jack',              'WF-LFT-001',
 'Hydraulic trolley jack, 2-tonne capacity, 100mm min height.',
 '<p>Service vehicles with ease using our 2-Tonne Low-Profile Floor Jack. The 100mm minimum saddle height allows it to fit under lowered sports cars and performance vehicles. Single-stage hydraulic ram lifts to 380mm. Safety overload bypass valve prevents over-pressurising. Swivel rear casters and fixed front wheels for easy manoeuvring. Conforms to PALD requirements. Supplied with two extension bars.</p>',
 169.99, 14.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,30,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,60,22,20,1,true,false,
 false,0,'floor jack, trolley jack, 2 tonne, hydraulic','2-Tonne Low-Profile Floor Jack','2T hydraulic trolley jack, 100mm min height, 380mm max lift.',
 NULL,NULL,NULL,NOW(),NOW()),

('2500kg Hand Pallet Truck',                    'WF-LFT-002',
 'Heavy-duty 2500kg hand pump pallet truck with 1150mm fork length.',
 '<p>Move heavy loads efficiently with our 2500kg Hand Pallet Truck. The 1150mm fork length accepts standard EUR pallets. Precision German-engineered hydraulic pump lifts from 85mm to 200mm with five handle positions for comfortable pumping. Lowering is controlled via a trigger release valve for safe, gradual descent. Tandem polyurethane rollers minimise floor damage. Powder-coated steel chassis. EN ISO 3691-5 compliant.</p>',
 349.00, 68.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,15,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,165,55,120,2,true,false,
 false,0,'pallet truck, hand pump, 2500kg, material handling','2500kg Hand Pallet Truck','2500kg capacity hand pallet truck with 1150mm forks, EN ISO 3691-5.',
 NULL,NULL,NULL,NOW(),NOW()),

('3-Tonne Chain Block Hoist',                   'WF-LFT-003',
 '3-tonne manual chain block with 3m lift height and Grade 80 chain.',
 '<p>Lift heavy loads vertically with our 3-Tonne Chain Block Hoist. Grade 80 alloy steel load chain and hooks. Hardened brake pads ensure smooth, positive braking. Supported by a top hook with safety latch (shackle included). Lift height: 3 metres standard. Operating temperature range: -10°C to +50°C. CE marked and tested to 1.5× working load limit. Supplied in a carry bag for site transport.</p>',
 134.99, 9.50, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,20,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,30,20,25,3,true,false,
 false,0,'chain block, hoist, 3 tonne, lifting','3-Tonne Chain Block Hoist','3T manual chain block hoist, 3m lift, Grade 80 chain, CE marked.',
 NULL,NULL,NULL,NOW(),NOW()),

('Aluminium Platform Step Ladder 3-Tread',      'WF-LFT-004',
 'Lightweight aluminium 3-tread platform step ladder, 150kg rated, EN 131.',
 '<p>Reach comfortably and safely with our Aluminium Platform Step Ladder. The large anti-slip platform (40cm × 20cm) provides a stable standing area. Large ribbed anti-slip steps and rubber feet protect floors. One-touch folding mechanism and integrated carry handle for quick deployment. Fully opened dimensions: 56cm W × 65cm D × 94cm H to platform. Max user weight: 150 kg. EN 131 Professional standard.</p>',
 229.00, 7.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,25,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,56,65,94,4,true,false,
 false,0,'step ladder, platform ladder, aluminium, EN 131','Aluminium Platform Step Ladder 3-Tread','EN 131 aluminium 3-tread platform step ladder, 150kg rated.',
 NULL,NULL,NULL,NOW(),NOW()),

('Heavy-Duty Ratchet Straps 5m x4 Set',         'WF-LFT-005',
 'Set of 4 EN 12195-2 ratchet straps, 5m × 25mm, 500kg lashing capacity.',
 '<p>Secure cargo confidently with our Heavy-Duty Ratchet Straps. Each 5m strap has a 500kg lashing capacity (LC) and 2,500kg breaking strength. The trigger-release ratchet buckle winds and tensions the strap quickly. 25mm polyester webbing is UV, abrasion and acid resistant. J-hook ends fit most vehicle anchor points. EN 12195-2 certified. Set of 4 in a mesh storage bag.</p>',
 24.99, 1.20, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,150,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,30,18,8,5,true,false,
 false,0,'ratchet straps, cargo tie-down, EN 12195, lashing','Heavy-Duty Ratchet Straps 5m x4 Set','Set of 4 EN 12195-2 ratchet straps, 5m, 500kg LC, J-hooks.',
 NULL,NULL,NULL,NOW(),NOW()),

-- ── Welding Supplies (category 4) ────────────────────────────────────────────
('MIG Welder 180A Inverter Unit',               'WF-WLD-001',
 'Compact 180A MIG/MAG inverter welder with synergic control panel.',
 '<p>Weld like a professional with our 180A MIG Welder. IGBT inverter technology makes it lighter (6.8 kg) and more energy-efficient than traditional transformer welders. Synergic control automatically sets wire feed speed when you select material thickness (0.5–8mm steel). Input: 230V single phase. Duty cycle: 60% at 130A. Accepts 0.8mm and 1.0mm wire on D200 spools. Euro torch connector for easy torch replacement. Includes regulator and earth clamp.</p>',
 399.00, 6.80, 5,0,true, 1,0,true,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,20,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,38,20,28,1,true,false,
 false,0,'MIG welder, 180A, inverter, welding','MIG Welder 180A Inverter','Compact synergic 180A MIG/MAG inverter welder, 230V, 60% duty cycle.',
 NULL,NULL,NULL,NOW(),NOW()),

('Auto-Darkening Welding Helmet',               'WF-WLD-002',
 'Solar-powered auto-darkening welding helmet, shade 9–13, ANSI Z87.1.',
 '<p>Protect your face and eyes with our Auto-Darkening Welding Helmet. The 100mm × 50mm auto-darkening filter switches from shade 4 to shade 9–13 in 1/25,000 of a second, preventing arc flash injury. Solar and Li-Ion battery powered for continuous use. Wide viewing area with grinding mode (shade 4 fixed). Adjustable headgear fits helmet sizes 52–64cm. ANSI Z87.1 and EN 379 certified.</p>',
 79.99, 0.80, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,40,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,30,22,26,2,true,false,
 false,0,'welding helmet, auto-darkening, shade 13, EN 379','Auto-Darkening Welding Helmet','Solar/battery auto-darkening welding helmet, shade 9–13, EN 379.',
 NULL,NULL,NULL,NOW(),NOW()),

('MIG Wire 316L Stainless Steel 5kg',           'WF-WLD-003',
 '0.8mm 316L austenitic stainless steel MIG welding wire on D200 spool.',
 '<p>Weld stainless steel with confidence using our 316L Stainless MIG Wire. The 0.8mm diameter solid wire provides excellent corrosion resistance in marine, chemical and food-processing environments. Low carbon content prevents sensitisation at elevated temperatures. Suitable for use with Ar/CO₂ shielding gas. 5 kg spool on a D200 plastic drum — fits most standard MIG torches. AWS A5.9:ER316L certified.</p>',
 64.99, 5.20, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,60,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,22,22,22,3,true,false,
 false,0,'MIG wire, stainless steel, 316L, welding consumable','MIG Wire 316L Stainless Steel 5kg','5kg 316L stainless steel 0.8mm MIG welding wire, D200 spool.',
 NULL,NULL,NULL,NOW(),NOW()),

('50A Inverter Plasma Cutter',                  'WF-WLD-004',
 'Compact 50A IGBT plasma cutter, cuts up to 12mm steel, pilot arc.',
 '<p>Cut metal cleanly and accurately with our 50A Inverter Plasma Cutter. The HF pilot arc starts without touching the work, ideal for painted and rusty surfaces. Cuts mild steel up to 12mm (clean cut: 8mm). Lightweight IGBT inverter design at just 5.5 kg. Durable AG60 plasma torch with 4m cable, regulator and earth clamp included. Input: 230V/1ph, 50Hz. Air supply: minimum 5 bar, 160 l/min.</p>',
 549.00, 5.50, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,15,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,35,16,22,4,true,false,
 false,0,'plasma cutter, 50A, inverter, metal cutting','50A Inverter Plasma Cutter','50A IGBT plasma cutter with pilot arc, cuts 12mm steel, 5.5 kg.',
 NULL,NULL,NULL,NOW(),NOW()),

-- ── Electrical & Wiring (category 5) ─────────────────────────────────────────
('16A Industrial Extension Lead 10m',           'WF-ELC-001',
 'Heavy-duty 16A extension lead with 4 sockets, 2.5mm² cable, IP44.',
 '<p>Power multiple tools safely on site with our 16A Industrial Extension Lead. The 10-metre 2.5mm² H07RN-F rubber cable handles 16A continuous load (3,680W). Four IP44-rated sockets with individual covers prevent water ingress. Overload thermal cut-out with manual reset. Cable management handle and integrated storage hook. Fitted with 16A industrial blue plug (CEE7). BS EN 60669-1 certified.</p>',
 49.99, 3.80, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,50,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,28,28,8,1,true,false,
 false,0,'extension lead, 16A, industrial, IP44','16A Industrial Extension Lead 10m','16A 10m H07RN-F extension lead, 4 IP44 sockets, thermal cut-out.',
 NULL,NULL,NULL,NOW(),NOW()),

('PVC Cable Trunking Management Kit',            'WF-ELC-002',
 'PVC trunking kit with 10m of 25×16mm channel, clips, corners and end caps.',
 '<p>Route and protect cables neatly with our PVC Cable Trunking Kit. Includes 10 × 1m lengths of 25mm × 16mm white PVC mini trunking, 20 adhesive base clips, 10 internal corners, 10 external corners, 10 flat bends and 20 end caps. Flame-retardant to IEC 60695-11-10. Self-adhesive backing on base for tool-free installation on smooth surfaces. Snap-fit lid for easy cable access. Suitable for data, power and AV cables.</p>',
 34.99, 2.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,80,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,100,5,5,2,true,false,
 false,0,'cable trunking, cable management, PVC, wiring','PVC Cable Trunking Management Kit','10m PVC mini trunking kit with clips, corners and end caps.',
 NULL,NULL,NULL,NOW(),NOW()),

('Digital Clamp Meter 600A AC/DC',              'WF-ELC-003',
 'True-RMS digital clamp meter measuring AC/DC current to 600A.',
 '<p>Measure electrical loads accurately and safely with our True-RMS Digital Clamp Meter. AC/DC current measurement to 600A via a 35mm jaw. True-RMS calculation ensures accuracy on non-sinusoidal waveforms. Functions include: AC/DC voltage (600V), resistance (60MΩ), continuity, diode test, capacitance, frequency and temperature. Auto-ranging, data hold, peak hold and backlit LCD. CAT III 600V rated. Supplied with test leads and thermocouple.</p>',
 69.99, 0.45, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,40,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,20,7,5,3,true,false,
 false,0,'clamp meter, multimeter, 600A, True-RMS','Digital Clamp Meter 600A AC/DC','True-RMS 600A AC/DC clamp meter, CAT III 600V, with temperature.',
 NULL,NULL,NULL,NOW(),NOW()),

('100W IP65 LED Site Flood Light',              'WF-ELC-004',
 '100W LED site work light on adjustable tripod, 10,000 lm, IP65.',
 '<p>Illuminate your work area with our 100W IP65 LED Site Flood Light. 10,000 lumens of cool white (6000K) output cuts through darkness on late jobs. The IP65 weatherproof housing withstands dust, rain and mud. The 1.5m telescopic tripod adjusts from 0.8m to 1.5m and folds flat for transport. 5m cable with 13A moulded plug. Suitable for construction sites, sports fields and emergency use.</p>',
 89.99, 5.50, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,30,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,50,40,150,4,true,false,
 false,0,'site light, LED flood, 100W, IP65, worklight','100W IP65 LED Site Flood Light','100W 10,000lm IP65 LED site flood on telescopic tripod, 5m cable.',
 NULL,NULL,NULL,NOW(),NOW()),

('RCD Protected 4-Gang Extension Block',        'WF-ELC-005',
 '13A 4-gang trailing socket with built-in 30mA RCD protection.',
 '<p>Never compromise on electrical safety with our RCD Protected Extension Block. The 30mA residual current device trips within 30ms of a fault, protecting users from electric shock. Four individually switched 13A BS 1363 sockets. 2m flat cable with 13A moulded plug. Surge protection indicator LED. Cable tie-off bracket for secure positioning. Conforms to BS EN 60669-1 and IET wiring regulations.</p>',
 39.99, 0.80, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,100,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,35,8,5,5,true,false,
 false,0,'RCD extension lead, 4 gang, electrical safety, 30mA','RCD Protected 4-Gang Extension Block','13A 4-gang extension block with 30mA RCD, surge protection, 2m cable.',
 NULL,NULL,NULL,NOW(),NOW()),

-- ── Fasteners & Hardware (category 6) ─────────────────────────────────────────
('Hex Bolt Assortment Kit M8–M16',              'WF-FST-001',
 'A2 stainless steel hex bolts, nuts and washers assortment, 220 pieces.',
 '<p>Always have the right fastener to hand with our Hex Bolt Assortment Kit. 220 pieces of A2 (304) stainless steel fully-threaded hex bolts with matching nuts and flat washers. Sizes: M8×20, M8×40, M10×20, M10×40, M10×60, M12×30, M12×50, M16×50 (10 of each bolt + matching nut + 2 washers). Stored in a labelled polypropylene sortment box. ISO 4017 metric coarse thread.</p>',
 34.99, 1.80, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,100,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,28,20,8,1,true,false,
 false,0,'hex bolts, stainless, M8-M16, fasteners assortment','Hex Bolt Assortment Kit M8–M16','220pc A2 stainless hex bolt, nut and washer assortment, M8–M16.',
 NULL,NULL,NULL,NOW(),NOW()),

('A2 Stainless Self-Tapping Screws 500pk',      'WF-FST-002',
 'A2 stainless pan-head self-tapping screws, mixed sizes, 500 pieces.',
 '<p>Fasten sheet materials and thin sections quickly with our A2 Stainless Self-Tapping Screws. Pack of 500 includes five sizes: 3.5×16mm, 3.5×25mm, 4.2×19mm, 4.8×25mm and 4.8×38mm (100 of each). Pan head with Pozi No.2 drive. A2 stainless steel resists corrosion in external applications. Stored in a 5-compartment box with size labels. DIN 7981 standard.</p>',
 19.99, 1.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,150,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,18,14,5,2,true,false,
 false,0,'self-tapping screws, stainless, A2, 500pk','A2 Stainless Self-Tapping Screws 500pk','500pc A2 stainless pan-head self-tapping screw mixed size kit.',
 NULL,NULL,NULL,NOW(),NOW()),

('Chemical Anchor Rods M10×130mm Box 25',       'WF-FST-003',
 'Threaded A4 stainless anchor rods for use with resin chemical anchor, M10×130mm, box of 25.',
 '<p>Achieve high-load fixings in concrete and masonry with our M10 Chemical Anchor Rods. A4 (316) stainless steel threaded rods with a roughened bond zone for maximum resin adhesion. 130mm overall length with 90mm embedment depth. Suitable for use with our polyester and vinylester anchor resins (sold separately). Load ratings: characteristic tensile 14.7kN (C20/25 concrete). Supplied in a box of 25 with installation datasheet.</p>',
 44.99, 0.90, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,80,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,14,5,14,3,true,false,
 false,0,'chemical anchor, M10, resin anchor, concrete fixings','Chemical Anchor Rods M10×130mm Box 25','Box of 25 A4 stainless M10×130mm chemical anchor rods for resin fixing.',
 NULL,NULL,NULL,NOW(),NOW()),

('Nyloc Nuts & Flat Washers Kit 300pc',          'WF-FST-004',
 'Assorted M6–M12 A2 stainless nyloc nuts and flat washers, 300 pieces.',
 '<p>Prevent fastener loosening with our Nyloc Nuts and Flat Washers Kit. Includes 300 pieces of A2 stainless steel nyloc (ISO 7042) and DIN 125 flat washers in M6, M8, M10 and M12 sizes (25 nylocs + 25 washers per size, 4 sizes). Nylon insert locks prevent vibration-induced loosening. 8-compartment stackable tray with size labels. Suitable for marine, outdoor and structural applications.</p>',
 29.99, 0.90, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,120,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,18,14,5,4,true,false,
 false,0,'nyloc nuts, washers, M6-M12, stainless fasteners','Nyloc Nuts & Flat Washers Kit 300pc','300pc A2 stainless M6–M12 nyloc nut and flat washer assortment.',
 NULL,NULL,NULL,NOW(),NOW()),

-- ── Workwear & PPE (category 7) ───────────────────────────────────────────────
('Flame-Retardant Coveralls EN 11612',           'WF-WRK-001',
 'FR cotton coveralls, EN 11612 A1 B1 C1, with 9 pockets and reflective bands.',
 '<p>Stay protected from heat and flame with our Flame-Retardant Coveralls. Manufactured from 350gsm FR cotton fabric that will not melt or drip and self-extinguishes when the flame source is removed. EN 11612:2015 A1 B1 C1 rated. Nine pockets including two front chest, two hip, two thigh map, rear and bib. 50mm silver reflective bands on arms, legs and torso. Metal-free design for use in areas with electrostatic risk. Available sizes 34–52 regular. Machine washable 60°C, maintains protection for 50+ washes.</p>',
 89.99, 0.90, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,5,1,0, false,0,60,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,50,30,5,1,true,false,
 false,0,'FR coveralls, flame retardant, EN 11612, workwear','Flame-Retardant Coveralls EN 11612','EN 11612 A1 B1 C1 FR cotton coveralls, 9 pockets, reflective bands.',
 NULL,NULL,NULL,NOW(),NOW()),

('Waterproof Knee-Pad Work Trousers',            'WF-WRK-002',
 'Cordura-reinforced work trousers with built-in knee-pad pockets and waterproof membrane.',
 '<p>Get through the harshest jobs dry and protected with our Waterproof Knee-Pad Work Trousers. The 300g canvas outer shell has Cordura reinforcement at the knees, seat and cuffs. The integrated waterproof membrane keeps you dry in rain and on wet surfaces. Twin knee-pad pockets accept standard CE EN 14404 Type 2 knee pads (included). 10 pockets including holster side pockets for knee pads and tools. Triple-stitched seams. Available in khaki, black and navy in sizes 30–42 (waist) × 30–34 (leg). Machine washable 40°C.</p>',
 74.99, 0.70, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,5,1,0, false,0,80,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,45,30,5,2,true,false,
 false,0,'work trousers, knee pad, waterproof, Cordura','Waterproof Knee-Pad Work Trousers','Waterproof Cordura work trousers with integrated knee-pad pockets.',
 NULL,NULL,NULL,NOW(),NOW()),

('3M Half-Face Respirator P3 Kit',              'WF-WRK-003',
 '3M 6200 half-face respirator with P3 filters, fit for dust, mist and fumes.',
 '<p>Breathe safely in hazardous environments with our 3M Half-Face Respirator Kit. The 3M 6200 silicone half-face piece fits medium faces (suitable for >95% of wearers). Supplied with two 3M 2138 P3 combination filters providing protection against fine dust, mist and oil-based fumes (Class P3, EN 143). The low-profile bayonet fitting allows quick filter changes. Comfortable silicone seal and adjustable head harness with neck strap. Supplied in a resealable bag to maintain filter service life.</p>',
 44.99, 0.30, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,5,1,0, false,0,100,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,18,12,12,3,true,false,
 false,0,'respirator, P3, half face, 3M, dust mask','3M Half-Face Respirator P3 Kit','3M 6200 half-face respirator with P3 combination filters, EN 143.',
 NULL,NULL,NULL,NOW(),NOW());

-- ---------------------------------------------------------------------------
-- 5. Category–Product mappings
-- ---------------------------------------------------------------------------
INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 1, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('WF-PWR-001','WF-PWR-002','WF-PWR-003','WF-PWR-004','WF-PWR-005','WF-PWR-006');

INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 2, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('WF-SFT-001','WF-SFT-002','WF-SFT-003','WF-SFT-004','WF-SFT-005');

INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 3, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('WF-LFT-001','WF-LFT-002','WF-LFT-003','WF-LFT-004','WF-LFT-005');

INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 4, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('WF-WLD-001','WF-WLD-002','WF-WLD-003','WF-WLD-004');

INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 5, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('WF-ELC-001','WF-ELC-002','WF-ELC-003','WF-ELC-004','WF-ELC-005');

INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 6, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('WF-FST-001','WF-FST-002','WF-FST-003','WF-FST-004');

INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 7, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('WF-WRK-001','WF-WRK-002','WF-WRK-003');

-- ---------------------------------------------------------------------------
-- 6. URL records for products
-- ---------------------------------------------------------------------------
INSERT INTO "UrlRecord" ("EntityName","EntityId","Slug","IsActive","LanguageId")
SELECT 'Product', "Id",
  lower(regexp_replace(regexp_replace("Name",'[^a-zA-Z0-9\s-]','','g'),'\s+','-','g')),
  true, 0
FROM "Product";

-- URL records for categories
INSERT INTO "UrlRecord" ("EntityName","EntityId","Slug","IsActive","LanguageId")
VALUES
  ('Category',1,'power-tools',        true,0),
  ('Category',2,'safety-equipment',   true,0),
  ('Category',3,'lifting-handling',   true,0),
  ('Category',4,'welding-supplies',   true,0),
  ('Category',5,'electrical-wiring',  true,0),
  ('Category',6,'fasteners-hardware', true,0),
  ('Category',7,'workwear-ppe',       true,0);

-- ---------------------------------------------------------------------------
-- 7. Store branding — WorkForge Industrial
-- ---------------------------------------------------------------------------
UPDATE "Store"
SET "Name"        = 'WorkForge Industrial',
    "CompanyName" = 'Northstar Living Group — WorkForge',
    "Url"         = 'http://localhost:5002/'
WHERE "Id" = 1;

-- Remove any extra sample-data stores
DELETE FROM "Store" WHERE "Id" != 1;

-- ---------------------------------------------------------------------------
-- 8. Tidy up navigation / SEO settings
-- ---------------------------------------------------------------------------
UPDATE "Setting"
SET "Value" = replace(replace("Value",
  'http://nopcommerce-bub/','http://localhost:5002/'),
  'http://nopcommerce-bua/','http://localhost:5002/')
WHERE "Value" LIKE '%nopcommerce-bu%';

COMMIT;

-- Quick sanity check
SELECT 'Products' AS entity, COUNT(*) AS cnt FROM "Product" WHERE "Published" = true
UNION ALL
SELECT 'Categories',           COUNT(*) FROM "Category"  WHERE "Published" = true
UNION ALL
SELECT 'URL Records',           COUNT(*) FROM "UrlRecord" WHERE "EntityName" IN ('Product','Category');

