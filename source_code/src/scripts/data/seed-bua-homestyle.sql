-- =============================================================================
-- Northstar Living Group — BU-A: HomeStyle Living
-- Replaces nopCommerce sample products/categories with HomeStyle catalogue.
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
-- 2. Update TaxCategory names to HomeStyle context
-- ---------------------------------------------------------------------------
UPDATE "TaxCategory" SET "Name" = 'Homewares & Furniture'  WHERE "Id" = 2;
UPDATE "TaxCategory" SET "Name" = 'Home Textiles & Bedding' WHERE "Id" = 5;

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
  (1,'Furniture',              1,0,0,12,true,true, false,false,true,false,1,NOW(),NOW(),false,0,0,false,false,
   'Premium furniture for every room in your home.', 'furniture, sofas, beds, tables', 'Furniture',            '6, 3, 9'),
  (2,'Kitchen & Dining',       1,0,0,12,true,false,false,false,true,false,2,NOW(),NOW(),false,0,0,false,false,
   'Quality cookware, tableware and kitchen essentials.','kitchen, cookware, dining','Kitchen & Dining',       '6, 3, 9'),
  (3,'Bedding & Bath',         1,0,0,12,true,false,false,false,true,false,3,NOW(),NOW(),false,0,0,false,false,
   'Luxurious bedding, towels and bathroom accessories.','bedding, duvet, towels, bath','Bedding & Bath',      '6, 3, 9'),
  (4,'Lighting & Decor',       1,0,0,12,true,false,false,false,true,false,4,NOW(),NOW(),false,0,0,false,false,
   'Beautiful lighting, wall art and home accessories.','lighting, lamps, wall art, decor','Lighting & Decor', '6, 3, 9'),
  (5,'Garden & Outdoor',       1,0,0,12,true,false,false,false,true,false,5,NOW(),NOW(),false,0,0,false,false,
   'Outdoor furniture, garden decor and planting essentials.','garden, outdoor, patio, plants','Garden & Outdoor','6, 3, 9'),
  (6,'Smart Home',             1,0,0,12,true,false,false,false,true,false,6,NOW(),NOW(),false,0,0,false,false,
   'Connected devices that make everyday living smarter.','smart home, thermostat, doorbell, IoT','Smart Home', '6, 3, 9'),
  (7,'Storage & Organisation', 1,0,0,12,true,false,false,false,true,false,7,NOW(),NOW(),false,0,0,false,false,
   'Clever storage solutions to declutter every space.','storage, organisation, shelves','Storage & Organisation','6, 3, 9');

-- ---------------------------------------------------------------------------
-- 4. Products  (ProductTypeId=5=Simple, ProductTemplateId=1, TaxCategoryId=2)
-- ---------------------------------------------------------------------------
-- Helper macro columns used in every row:
--   ProductTypeId=5, ParentGroupedProductId=0, VisibleIndividually=true,
--   ProductTemplateId=1, VendorId=0, AllowCustomerReviews=true,
--   ApprovedRatingSum=0, NotApprovedRatingSum=0,
--   ApprovedTotalReviews=0, NotApprovedTotalReviews=0,
--   SubjectToAcl=false, LimitedToStores=false,
--   IsGiftCard=false, GiftCardTypeId=0, OverriddenGiftCardAmount=0,
--   RequireOtherProducts=false, AutomaticallyAddRequiredProducts=false,
--   IsDownload=false, DownloadId=0, UnlimitedDownloads=true,
--   MaxNumberOfDownloads=10, DownloadActivationTypeId=0,
--   HasSampleDownload=false, SampleDownloadId=0, HasUserAgreement=false,
--   IsRecurring=false, RecurringCycleLength=100, RecurringCyclePeriodId=0,
--   RecurringTotalCycles=10, IsRental=false, RentalPriceLength=1, RentalPricePeriodId=0,
--   IsShipEnabled=true, IsFreeShipping=false, ShipSeparately=false,
--   AdditionalShippingCharge=0, DeliveryDateId=0, IsTaxExempt=false, TaxCategoryId=2,
--   ManageInventoryMethodId=1, ProductAvailabilityRangeId=0, UseMultipleWarehouses=false,
--   WarehouseId=0, DisplayStockAvailability=false, DisplayStockQuantity=false,
--   MinStockQuantity=0, LowStockActivityId=0, NotifyAdminForQuantityBelow=1,
--   BackorderModeId=0, AllowBackInStockSubscriptions=false,
--   OrderMinimumQuantity=1, OrderMaximumQuantity=10000,
--   AllowAddingOnlyExistingAttributeCombinations=false,
--   DisplayAttributeCombinationImagesOnly=false, NotReturnable=false,
--   DisableBuyButton=false, DisableWishlistButton=false,
--   AvailableForPreOrder=false, CallForPrice=false,
--   OldPrice=0, ProductCost=0, CustomerEntersPrice=false,
--   MinimumCustomerEnteredPrice=0, MaximumCustomerEnteredPrice=1000,
--   BasepriceEnabled=false, BasepriceAmount=0, BasepriceUnitId=0,
--   BasepriceBaseAmount=0, BasepriceBaseUnitId=0,
--   MarkAsNew=false, Length=1, Width=1, Height=1,
--   DisplayOrder=0, Published=true, Deleted=false,
--   AgeVerification=false, MinimumAgeToPurchase=0
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

-- ── Furniture (category 1) ──────────────────────────────────────────────────
('Nordic Oak Dining Table 6-Seater',        'NSL-FUR-001',
 'Solid oak dining table with hairpin legs seating up to 6.',
 '<p>A statement piece for any home, our Nordic Oak Dining Table is crafted from sustainably sourced solid oak with a natural oiled finish. The sleek hairpin steel legs provide contrast and stability. Seats 6 comfortably. Dimensions: 180cm L × 90cm W × 76cm H.</p>',
 449.99, 35.00, 5,0,true, 1,0,true,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,50,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,180,90,76,1,true,false,
 false,0,'dining table, oak, furniture, Nordic','Nordic Oak Dining Table','Solid oak 6-seater dining table with hairpin legs.',
 NULL,NULL,NULL,NOW(),NOW()),

('Velvet 3-Seater Sofa Charcoal',           'NSL-FUR-002',
 'Deep-button velvet sofa with solid wooden legs in charcoal grey.',
 '<p>Sink into luxury with our Velvet 3-Seater Sofa. Upholstered in sumptuous charcoal grey velvet with deep button detailing and solid beechwood legs. High-density foam cushions ensure lasting comfort. Available in multiple colours. Dimensions: 210cm W × 90cm D × 85cm H.</p>',
 899.00, 60.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,25,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,210,90,85,2,true,false,
 false,0,'sofa, velvet, 3-seater, living room','Velvet 3-Seater Sofa','Deep-button charcoal velvet 3-seater sofa.',
 NULL,NULL,NULL,NOW(),NOW()),

('King Upholstered Bed Frame',              'NSL-FUR-003',
 'Fabric-headboard king-size bed frame in warm sand linen.',
 '<p>Create the bedroom of your dreams with our King Upholstered Bed Frame. Features a tall, button-tufted linen headboard and solid oak slat base. Fits standard 150cm × 200cm king mattress. Dimensions: 163cm W × 215cm D × 130cm H (headboard).</p>',
 649.00, 45.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,30,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,163,215,130,3,true,false,
 false,0,'bed frame, king size, upholstered, bedroom','King Upholstered Bed Frame','King-size linen upholstered bed frame with button headboard.',
 NULL,NULL,NULL,NOW(),NOW()),

('Scandinavian Solid Oak Bookcase',         'NSL-FUR-004',
 'Five-shelf solid oak bookcase with a timeless Scandi aesthetic.',
 '<p>Organise your books and display your treasures in style. Our Scandinavian Solid Oak Bookcase features five generously spaced shelves crafted from solid FSC-certified oak. Clean lines and a natural oil finish make it a versatile fit for any interior. Dimensions: 80cm W × 30cm D × 190cm H.</p>',
 229.00, 28.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,40,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,80,30,190,4,true,false,
 false,0,'bookcase, oak, shelving, Scandinavian','Scandinavian Solid Oak Bookcase','Five-shelf solid oak bookcase with natural finish.',
 NULL,NULL,NULL,NOW(),NOW()),

('Rattan Wingback Armchair',                'NSL-FUR-005',
 'Natural rattan armchair with deep-seat cushion in sage velvet.',
 '<p>Bring organic texture indoors with our Rattan Wingback Armchair. Handwoven natural rattan frame with a deep-seated cushion upholstered in sage green velvet. A statement accent piece perfect for reading nooks or living rooms. Weight limit: 120 kg. Dimensions: 75cm W × 80cm D × 100cm H.</p>',
 349.99, 12.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,35,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,75,80,100,5,true,false,
 false,0,'armchair, rattan, accent chair, living room','Rattan Wingback Armchair','Natural rattan wingback armchair with sage velvet cushion.',
 NULL,NULL,NULL,NOW(),NOW()),

('Sintered Stone Coffee Table',             'NSL-FUR-006',
 'Rectangular coffee table with sintered stone top and brushed brass frame.',
 '<p>A luxurious focal point for any living room. Our Sintered Stone Coffee Table features a scratch and heat-resistant sintered stone top in Calacatta white marble effect, set on a brushed brass metal frame. Dimensions: 120cm L × 60cm W × 42cm H.</p>',
 549.00, 22.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,20,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,120,60,42,6,true,false,
 false,0,'coffee table, marble, brass, living room','Sintered Stone Coffee Table','Calacatta marble-effect sintered stone coffee table with brass frame.',
 NULL,NULL,NULL,NOW(),NOW()),

('Floating Shelves Set of 3',               'NSL-FUR-007',
 'Set of 3 solid oak floating wall shelves with hidden brackets.',
 '<p>Maximise your wall space with our Floating Shelves Set of 3. Crafted from solid oak with a clear lacquer finish. Invisible heavy-duty steel brackets make them appear to float. Suitable for books, plants and ornaments. Sizes: 60cm, 80cm, 100cm long. Max load per shelf: 15 kg.</p>',
 89.99, 4.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,80,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,100,25,4,7,true,false,
 false,0,'floating shelves, wall shelves, oak, storage','Floating Shelves Set of 3','Set of 3 solid oak floating wall shelves with hidden brackets.',
 NULL,NULL,NULL,NOW(),NOW()),

-- ── Kitchen & Dining (category 2) ───────────────────────────────────────────
('Artisan Cast Iron Dutch Oven 4.7L',       'NSL-KIT-001',
 'Enamelled cast iron casserole dish for stove-top and oven use.',
 '<p>Slow-cook your way to flavourful meals with our Artisan Cast Iron Dutch Oven. The 4.7-litre capacity is ideal for family casseroles, braises and soups. The porcelain enamel interior is non-reactive and dishwasher safe. Compatible with all hob types including induction. Available in burnt orange, midnight navy and sage green.</p>',
 129.99, 7.00, 5,0,true, 1,0,true,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,60,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,32,26,20,1,true,false,
 false,0,'dutch oven, cast iron, casserole, cookware','Artisan Cast Iron Dutch Oven 4.7L','4.7L enamelled cast iron Dutch oven for hob and oven.',
 NULL,NULL,NULL,NOW(),NOW()),

('Bamboo Chopping Board Set of 3',          'NSL-KIT-002',
 'Three graduated bamboo chopping boards with juice grooves.',
 '<p>Keep cross-contamination at bay with our colour-coded Bamboo Chopping Board Set. Includes small (25cm), medium (35cm) and large (45cm) boards, each with a deep juice groove and non-slip rubber feet. Bamboo is naturally antibacterial, harder than maple and kinder to knife edges. Hand-wash recommended.</p>',
 44.99, 2.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,120,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,45,30,2,2,true,false,
 false,0,'chopping board, bamboo, kitchen, eco','Bamboo Chopping Board Set of 3','Set of 3 graduated bamboo chopping boards.',
 NULL,NULL,NULL,NOW(),NOW()),

('5-Piece Copper Clad Cookware Set',        'NSL-KIT-003',
 'Professional-grade stainless steel cookware with copper-clad bases.',
 '<p>Elevate your cooking with our 5-Piece Copper Clad Cookware Set. Includes 16cm, 18cm and 20cm saucepans, a 24cm sauté pan and a 28cm frying pan. Tri-ply construction with a copper base for rapid, even heat distribution. Stainless steel interior for durability. Oven safe to 220°C. Suitable for all hob types.</p>',
 299.99, 8.50, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,40,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,50,35,25,3,true,false,
 false,0,'cookware, copper, saucepan, pots pans','5-Piece Copper Clad Cookware Set','Professional 5-piece stainless steel cookware with copper-clad bases.',
 NULL,NULL,NULL,NOW(),NOW()),

('Porcelain Dinner Set 16-Piece',           'NSL-KIT-004',
 'Service for 4: dinner plates, side plates, bowls and mugs in white porcelain.',
 '<p>Bring effortless elegance to the table with our 16-Piece Porcelain Dinner Set. The set includes 4 dinner plates (27cm), 4 side plates (19cm), 4 pasta bowls (20cm) and 4 mugs (320ml). Premium porcelain with a reactive glaze for a unique handcrafted look. Dishwasher, microwave and oven safe to 180°C.</p>',
 89.99, 6.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,50,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,30,30,25,4,true,false,
 false,0,'dinner set, porcelain, plates, tableware','Porcelain Dinner Set 16-Piece','16-piece white porcelain dinner set, service for 4.',
 NULL,NULL,NULL,NOW(),NOW()),

('Bean-to-Cup Espresso Machine',            'NSL-KIT-005',
 'Fully automatic bean-to-cup coffee machine with milk frother.',
 '<p>Wake up to barista-quality coffee every morning. Our Bean-to-Cup Espresso Machine grinds fresh beans on demand, with adjustable grind size and strength settings. The built-in steam wand froths milk for cappuccinos and flat whites. 1.8L water tank, 15-bar pump pressure, removable drip tray for cleaning ease.</p>',
 349.00, 9.00, 5,0,true, 1,0,true,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,30,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,30,22,35,5,true,false,
 false,0,'espresso machine, coffee, bean-to-cup, cappuccino','Bean-to-Cup Espresso Machine','Fully automatic bean-to-cup espresso machine with steam wand.',
 NULL,NULL,NULL,NOW(),NOW()),

-- ── Bedding & Bath (category 3) ─────────────────────────────────────────────
('1000TC Egyptian Cotton Duvet Set King',   'NSL-BED-001',
 'Luxurious 1000 thread-count Egyptian cotton duvet cover set, king size.',
 '<p>Experience five-star comfort at home. Our 1000TC Egyptian Cotton Duvet Set features an ultra-soft duvet cover (230cm × 220cm) and two pillowcases (50cm × 75cm). The extra-long staple cotton ensures silky smoothness and exceptional durability. Sateen weave with a subtle sheen. Machine washable at 40°C. Includes corner ties.</p>',
 149.99, 1.50, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,60,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,40,30,8,1,true,false,
 false,0,'duvet cover, Egyptian cotton, bedding, king size','1000TC Egyptian Cotton Duvet Set King','King-size 1000 thread-count Egyptian cotton duvet cover set.',
 NULL,NULL,NULL,NOW(),NOW()),

('Luxury Memory Foam Pillow Pair',          'NSL-BED-002',
 'Pair of premium temperature-responsive memory foam pillows.',
 '<p>Sleep better with our Luxury Memory Foam Pillow Pair. Each pillow (48cm × 74cm) features a 100% memory foam core that responds to body heat to provide personalised support for neck and shoulders. Breathable bamboo-derived viscose cover with a zippered microfibre outer case. Hypoallergenic and dust-mite resistant.</p>',
 74.99, 3.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,80,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,74,48,15,2,true,false,
 false,0,'memory foam pillow, luxury, sleep, bedding','Luxury Memory Foam Pillow Pair','Pair of temperature-responsive memory foam pillows with bamboo cover.',
 NULL,NULL,NULL,NOW(),NOW()),

('Waffle-Weave Towel Bale 6-Piece',         'NSL-BED-003',
 'Six-piece waffle-weave towel set: 2 bath sheets, 2 hand towels, 2 face cloths.',
 '<p>Wrap yourself in luxury with our Waffle-Weave Towel Bale. The honeycomb waffle texture is highly absorbent and quick-drying. Made from 600gsm cotton. Set includes 2 bath sheets (90cm × 150cm), 2 hand towels (50cm × 90cm) and 2 face cloths (30cm × 30cm). Available in stone, blush, sage and navy. Machine washable.</p>',
 59.99, 2.50, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,100,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,40,30,10,3,true,false,
 false,0,'towels, waffle weave, bath, cotton','Waffle-Weave Towel Bale 6-Piece','6-piece waffle-weave cotton towel set with bath sheets, hand towels and face cloths.',
 NULL,NULL,NULL,NOW(),NOW()),

('Dual-Zone Electric Blanket King',         'NSL-BED-004',
 'King-size dual-control electric underblanket with 9 heat settings.',
 '<p>Stay warm all winter with our Dual-Zone Electric Blanket. The king-size (150cm × 160cm) underblanket has two independent heat zones, allowing each partner to choose their preferred warmth level from 9 settings. Auto overheat protection and timer function. Machine washable. Low running cost — full warmth in under 10 minutes.</p>',
 89.99, 1.20, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,50,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,60,50,5,4,true,false,
 false,0,'electric blanket, heated blanket, king, bedroom','Dual-Zone Electric Blanket King','King-size dual-control electric underblanket with 9 heat settings.',
 NULL,NULL,NULL,NOW(),NOW()),

('Bamboo Mattress Topper 5cm King',         'NSL-BED-005',
 'Deep 5cm bamboo-filled mattress topper with stretch-fit skirt, king size.',
 '<p>Rejuvenate your mattress with our 5cm Bamboo Mattress Topper. The deep-fill bamboo microfibre filling provides pressure-relieving cushioning while the bamboo-derived cover regulates temperature and wicks moisture. Fitted stretch skirt fits mattresses up to 35cm deep. King size: 150cm × 200cm. Machine washable at 40°C.</p>',
 149.00, 4.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,40,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,200,150,8,5,true,false,
 false,0,'mattress topper, bamboo, king size, bedding','Bamboo Mattress Topper 5cm King','King-size 5cm bamboo-filled mattress topper with stretch-fit skirt.',
 NULL,NULL,NULL,NOW(),NOW()),

-- ── Lighting & Decor (category 4) ────────────────────────────────────────────
('Arched Floor Lamp Brushed Brass',         'NSL-LIT-001',
 'Tall arc floor lamp with brushed brass finish and linen drum shade.',
 '<p>Cast a warm ambient glow with our Arched Floor Lamp. The graceful 180cm arc is finished in brushed brass, topped with a 40cm ivory linen drum shade. A dimmer switch and inline rocker offer versatile light control. Compatible with E27 LED bulbs up to 25W. Includes 2m fabric-covered cable and earth pin plug.</p>',
 179.99, 6.50, 5,0,true, 1,0,true,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,35,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,50,50,180,1,true,false,
 false,0,'floor lamp, arc lamp, brass, lighting','Arched Floor Lamp Brushed Brass','Tall brass arc floor lamp with ivory linen drum shade and dimmer.',
 NULL,NULL,NULL,NOW(),NOW()),

('Smoked Glass Pendant Light Cluster',      'NSL-LIT-002',
 'Three-drop smoked glass globe pendant cluster for dining tables.',
 '<p>Make a dramatic statement with our Smoked Glass Pendant Light Cluster. Three hand-blown smoked glass globes (15cm, 18cm and 22cm) hang at varied heights on a brushed gunmetal ceiling rose. Suitable for standard ceilings up to 3m. Compatible with E27 filament bulbs up to 60W per globe. Easy installation with all fittings included.</p>',
 139.99, 4.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,25,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,60,60,60,2,true,false,
 false,0,'pendant light, smoked glass, cluster, ceiling light','Smoked Glass Pendant Light Cluster','Three-drop smoked glass globe pendant cluster for dining rooms.',
 NULL,NULL,NULL,NOW(),NOW()),

('Luxury Scented Candle Set of 3',          'NSL-LIT-003',
 'Set of 3 hand-poured soy wax candles in velvet gift boxes.',
 '<p>Fill your home with exquisite fragrance. Our Luxury Scented Candle Set contains three 220g hand-poured soy wax candles with cotton wicks: Bergamot & Jasmine, Oakmoss & Amber and Sea Salt & Driftwood. Each candle burns for 55+ hours. Presented in individual velvet-lined gift boxes, perfect as a gift or treat for yourself.</p>',
 39.99, 0.80, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,150,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,30,25,12,3,true,false,
 false,0,'scented candle, soy wax, home fragrance, gift','Luxury Scented Candle Set of 3','Set of 3 hand-poured soy wax scented candles in gift boxes.',
 NULL,NULL,NULL,NOW(),NOW()),

('Abstract Canvas Triptych 120x40',         'NSL-LIT-004',
 'Three-panel abstract art canvas print set, 120cm × 40cm total.',
 '<p>Transform a blank wall with our Abstract Canvas Triptych. Three 40cm × 40cm gallery-wrapped canvases form a cohesive composition in warm earth tones — terracotta, sandstone and charcoal. Printed on premium 380gsm canvas with UV-resistant inks for lasting vibrancy. Pre-strung and ready to hang, wall fixings included.</p>',
 119.00, 2.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,40,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,120,40,4,4,true,false,
 false,0,'canvas art, triptych, wall art, abstract','Abstract Canvas Triptych 120x40','Three-panel gallery-wrapped abstract canvas print in earth tones.',
 NULL,NULL,NULL,NOW(),NOW()),

('Smart RGB LED Strip Light 5m',            'NSL-LIT-005',
 '5-metre app-controlled RGB LED strip with music sync and scene modes.',
 '<p>Set the mood with our Smart RGB LED Strip Light. The 5-metre self-adhesive strip connects to Wi-Fi and is controlled via the HomeStyle app or voice assistants (Alexa, Google Home). Choose from 16 million colours, 20 scene modes and a music-sync function that pulses with your beats. Includes power adapter and corner connectors. Cuttable at 10cm intervals.</p>',
 49.99, 0.50, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,200,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,50,5,1,5,true,false,
 false,0,'LED strip, smart home, RGB, Alexa','Smart RGB LED Strip Light 5m','5m Wi-Fi RGB LED strip with app, Alexa and music-sync control.',
 NULL,NULL,NULL,NOW(),NOW()),

-- ── Garden & Outdoor (category 5) ────────────────────────────────────────────
('6-Piece Rattan Garden Furniture Set',     'NSL-GDN-001',
 'All-weather PE rattan garden set: 2-seater sofa, 2 chairs, coffee table, footstool.',
 '<p>Enjoy outdoor living year-round with our 6-Piece Rattan Garden Furniture Set. Constructed from UV-resistant PE rattan over a powder-coated aluminium frame. Includes 2-seater sofa, 2 lounge chairs, coffee table and footstool. Deep-fill cushions upholstered in water-resistant fabric. Easy to clean with a damp cloth. Garden cover included.</p>',
 799.00, 45.00, 5,0,true, 1,0,true,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,15,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,220,150,80,1,true,false,
 false,0,'garden furniture, rattan, outdoor, patio set','6-Piece Rattan Garden Furniture Set','6-piece all-weather PE rattan garden furniture set with cushions.',
 NULL,NULL,NULL,NOW(),NOW()),

('Solar Path Lights Set of 10',             'NSL-GDN-002',
 'Set of 10 stainless steel solar-powered path lights with warm white LEDs.',
 '<p>Line your garden paths beautifully with no wiring needed. Our Solar Path Lights feature a brushed stainless steel spike design with warm white (3000K) LEDs. Each light charges in 6–8 hours of sunlight and provides up to 10 hours of illumination. IP65 waterproof rating. Auto on/off at dusk and dawn. Easy push-in installation.</p>',
 39.99, 3.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,75,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,30,30,10,2,true,false,
 false,0,'solar lights, garden, path lights, outdoor','Solar Path Lights Set of 10','Set of 10 stainless steel solar path lights, IP65 waterproof.',
 NULL,NULL,NULL,NOW(),NOW()),

('Terracotta Plant Pots Set of 3',          'NSL-GDN-003',
 'Handmade terracotta pots with drainage holes in sizes 15, 20 and 25cm.',
 '<p>Bring natural warmth to your garden or windowsill with our Handmade Terracotta Plant Pots. The set of three graduated pots (15cm, 20cm, 25cm diameter) are thrown from traditional terracotta clay with a slightly rough-hewn texture. Pre-drilled drainage holes prevent waterlogging. Frost-resistant down to -5°C. Saucers sold separately.</p>',
 59.99, 8.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,60,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,25,25,25,3,true,false,
 false,0,'terracotta pots, plant pots, garden, clay','Terracotta Plant Pots Set of 3','Set of 3 handmade terracotta plant pots with drainage holes.',
 NULL,NULL,NULL,NOW(),NOW()),

('Heavy-Duty Outdoor Storage Box',          'NSL-GDN-004',
 '455-litre waterproof garden storage box for cushions, tools and toys.',
 '<p>Keep your garden clutter-free with our Heavy-Duty Outdoor Storage Box. The 455-litre capacity is large enough for cushions, garden tools, toys and more. Constructed from UV-stabilised polypropylene with a reinforced lid that doubles as extra seating (max 200 kg). Gas-piston lid stays open safely. Dimensions: 130cm L × 60cm W × 58cm H.</p>',
 129.99, 12.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,30,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,130,60,58,4,true,false,
 false,0,'storage box, garden, outdoor, waterproof','Heavy-Duty Outdoor Storage Box','455L waterproof garden storage box with double-lid seating.',
 NULL,NULL,NULL,NOW(),NOW()),

-- ── Smart Home (category 6) ──────────────────────────────────────────────────
('Smart Learning Thermostat',               'NSL-SMH-001',
 'Wi-Fi connected learning thermostat with colour touch display.',
 '<p>Cut heating bills and stay comfortable with our Smart Learning Thermostat. After just one week it learns your schedule and adjusts automatically. Control from anywhere via the HomeStyle app, or use voice commands with Alexa and Google Home. Colour 3.5-inch touchscreen, clear installation guide. Compatible with most combi boiler systems.</p>',
 219.99, 0.40, 5,0,true, 1,0,true,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,50,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,10,10,5,1,true,false,
 false,0,'smart thermostat, smart home, heating, Alexa','Smart Learning Thermostat','Wi-Fi learning thermostat with colour touchscreen, Alexa & Google Home.',
 NULL,NULL,NULL,NOW(),NOW()),

('2K Video Doorbell with Chime',            'NSL-SMH-002',
 'Wired 2K video doorbell with two-way audio, motion zones and indoor chime.',
 '<p>See and speak to visitors from anywhere with our 2K Video Doorbell. The 2K HDR camera gives crystal-clear video day and night (colour night vision). Adjustable motion detection zones reduce false alerts. Two-way audio lets you chat via the HomeStyle app. Works with Alexa Show and Google Nest displays. Wired install, indoor chime included.</p>',
 149.99, 0.45, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,60,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,15,5,18,2,true,false,
 false,0,'video doorbell, smart home, security, 2K','2K Video Doorbell with Chime','Wired 2K HDR video doorbell with motion zones, two-way audio and indoor chime.',
 NULL,NULL,NULL,NOW(),NOW()),

('Smart Plug Energy Monitor 4-Pack',        'NSL-SMH-003',
 'Pack of 4 Wi-Fi smart plugs with real-time energy monitoring.',
 '<p>Manage your home energy use intelligently with our Smart Plug Energy Monitor 4-Pack. Each 13A plug monitors real-time power consumption and reports weekly usage stats in the HomeStyle app. Schedule on/off times, set energy budgets and control with Alexa or Google Home. Compact design means it never blocks the adjacent socket.</p>',
 39.99, 0.60, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,200,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,15,7,7,3,true,false,
 false,0,'smart plug, energy monitor, Wi-Fi, Alexa','Smart Plug Energy Monitor 4-Pack','4-pack Wi-Fi smart plugs with energy monitoring, schedules and voice control.',
 NULL,NULL,NULL,NOW(),NOW()),

('Robot Vacuum & Mop Combo',                'NSL-SMH-004',
 'LiDAR mapping robot vacuum and mop with auto-empty base station.',
 '<p>Take the chore out of floor cleaning with our Robot Vacuum & Mop Combo. Powered by LiDAR 360° laser mapping, it navigates around furniture and creates precise room maps in the HomeStyle app. 4000Pa suction tackles pet hair and fine dust. The sonic mopping attachment removes stuck-on grime. Auto-empty base station holds 60 days of debris. Compatible with Alexa and Google Home.</p>',
 399.99, 5.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,20,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,35,35,10,4,true,false,
 false,0,'robot vacuum, smart home, mopping, LiDAR','Robot Vacuum & Mop Combo','LiDAR robot vacuum and mop with auto-empty base station.',
 NULL,NULL,NULL,NOW(),NOW()),

-- ── Storage & Organisation (category 7) ──────────────────────────────────────
('Modular Wardrobe System with Drawers',    'NSL-STG-001',
 'White modular wardrobe unit with 6 hanging rails and 4 drawers.',
 '<p>Create bespoke storage with our Modular Wardrobe System. The white finish unit offers flexible configuration with 6 hanging rail sections and 4 soft-close drawers. Solid MDF with durable melamine finish. Includes all necessary fixings and a step-by-step guide. Dimensions: 250cm W × 55cm D × 220cm H. Can be split into two 125cm units.</p>',
 499.00, 80.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,20,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,250,55,220,1,true,false,
 false,0,'wardrobe, storage, modular, bedroom','Modular Wardrobe System with Drawers','White modular wardrobe with 6 hanging rails and 4 soft-close drawers.',
 NULL,NULL,NULL,NOW(),NOW()),

('Over-Door Shoe Organiser 24-Pocket',      'NSL-STG-002',
 'Fabric 24-pocket over-door shoe storage with clear pockets.',
 '<p>Reclaim your hallway and bedroom floor with our Over-Door Shoe Organiser. The 24 clear-front pockets accommodate shoes, accessories and small items. Non-woven fabric construction with reinforced over-door hooks that fit doors up to 4cm thick without drilling. Full dimensions: 140cm H × 60cm W. Max weight: 15 kg.</p>',
 24.99, 0.50, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,150,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,60,5,140,2,true,false,
 false,0,'shoe organiser, storage, over door, hallway','Over-Door Shoe Organiser 24-Pocket','24-pocket over-door shoe organiser with clear pockets.',
 NULL,NULL,NULL,NOW(),NOW()),

('Stackable Linen Storage Boxes Set of 4', 'NSL-STG-003',
 'Set of 4 collapsible linen storage boxes with lids and labels.',
 '<p>Tidy up every room with our Stackable Linen Storage Box Set. Each rigid-frame box collapses flat when not in use. Strong cotton linen exterior, cardboard frame and cotton rope handles. Set of 4 includes large (40×30×30cm), medium (30×22×22cm) and two small (22×16×16cm) boxes, each with a matching lid and a label holder. Available in natural linen and charcoal grey.</p>',
 44.99, 1.00, 5,0,true, 1,0,false,true, 0,0,0,0, false,false,false,0,0, false,false,
 false,0,true,10,0, false,0,false, false,100,0,10, false,1,0,
 true,false,false,0,0, false,2,1,0, false,0,100,
 false,false,0,0, 1,0,false, 1,10000,
 false,false, false,false,false, false,false,
 0,0,false,0,1000,
 false,0,0,0,0, false,40,30,30,3,true,false,
 false,0,'storage boxes, linen, stackable, organisation','Stackable Linen Storage Boxes Set of 4','Set of 4 collapsible linen storage boxes with lids.',
 NULL,NULL,NULL,NOW(),NOW());

-- ---------------------------------------------------------------------------
-- 5. Category–Product mappings
-- ---------------------------------------------------------------------------
INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 1, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('NSL-FUR-001','NSL-FUR-002','NSL-FUR-003','NSL-FUR-004','NSL-FUR-005','NSL-FUR-006','NSL-FUR-007');

INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 2, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('NSL-KIT-001','NSL-KIT-002','NSL-KIT-003','NSL-KIT-004','NSL-KIT-005');

INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 3, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('NSL-BED-001','NSL-BED-002','NSL-BED-003','NSL-BED-004','NSL-BED-005');

INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 4, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('NSL-LIT-001','NSL-LIT-002','NSL-LIT-003','NSL-LIT-004','NSL-LIT-005');

INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 5, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('NSL-GDN-001','NSL-GDN-002','NSL-GDN-003','NSL-GDN-004');

INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 6, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('NSL-SMH-001','NSL-SMH-002','NSL-SMH-003','NSL-SMH-004');

INSERT INTO "Product_Category_Mapping" ("CategoryId","ProductId","IsFeaturedProduct","DisplayOrder")
SELECT 7, "Id", false, 0 FROM "Product" WHERE "Sku" IN
  ('NSL-STG-001','NSL-STG-002','NSL-STG-003');

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
  ('Category',1,'furniture',            true,0),
  ('Category',2,'kitchen-dining',       true,0),
  ('Category',3,'bedding-bath',         true,0),
  ('Category',4,'lighting-decor',       true,0),
  ('Category',5,'garden-outdoor',       true,0),
  ('Category',6,'smart-home',           true,0),
  ('Category',7,'storage-organisation', true,0);

-- ---------------------------------------------------------------------------
-- 7. Store branding — HomeStyle Living
-- ---------------------------------------------------------------------------
UPDATE "Store"
SET "Name"        = 'HomeStyle Living',
    "CompanyName" = 'Northstar Living Group — HomeStyle',
    "Url"         = 'http://localhost:5001/'
WHERE "Id" = 1;

-- Remove any extra sample-data stores
DELETE FROM "Store" WHERE "Id" != 1;

-- ---------------------------------------------------------------------------
-- 8. Tidy up navigation / SEO settings
-- ---------------------------------------------------------------------------
UPDATE "Setting"
SET "Value" = replace(replace("Value",
  'http://nopcommerce-bua/','http://localhost:5001/'),
  'http://nopcommerce-bub/','http://localhost:5001/')
WHERE "Value" LIKE '%nopcommerce-bu%';

COMMIT;

-- Quick sanity check
SELECT 'Products' AS entity, COUNT(*) AS cnt FROM "Product" WHERE "Published" = true
UNION ALL
SELECT 'Categories',           COUNT(*) FROM "Category"  WHERE "Published" = true
UNION ALL
SELECT 'URL Records',           COUNT(*) FROM "UrlRecord" WHERE "EntityName" IN ('Product','Category');

