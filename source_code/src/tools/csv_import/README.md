# CSV Import Pack (Two BU Scenario)

This folder provides:
- BU-specific CSV files for the **Northstar Living Group** scenario
- A small validator that checks required columns and basic referential integrity

## Scenario Summary
Northstar Living Group operates multiple specialist brands. Each BU maintains its own catalog logic, pricing, and inventory assumptions.

- **BU-A** brands: Northstar Living, Pine and Hearth
- **BU-B** brands: Harbor and Home, Summit Sleep

## Folder Layout
```
/Users/ilker/RiderProjects/nopCommerce/src/data/csv/
  bu-a/
    stores.csv
    languages.csv
    categories.csv
    manufacturers.csv
    products.csv
    product_categories.csv
    product_manufacturers.csv
  bu-b/
    stores.csv
    languages.csv
    categories.csv
    manufacturers.csv
    products.csv
    product_categories.csv
    product_manufacturers.csv
```

## Validate CSVs (recommended)
```
cd /Users/ilker/RiderProjects/nopCommerce/src
python3 tools/csv_import/validate_csv.py --input data/csv/bu-a --bu BU-A
python3 tools/csv_import/validate_csv.py --input data/csv/bu-b --bu BU-B
```

## Import Order (nopCommerce Admin)
1. **Stores** (if using multi-store)
2. **Languages**
3. **Categories**
4. **Manufacturers**
5. **Products**
6. **Product-Category mappings**
7. **Product-Manufacturer mappings**

Notes:
- The CSVs are intentionally minimal and can be extended with extra columns.
- Keep `ProductSku` and category/manufacturer names consistent across files.
- These files are safe defaults for staging and demo. Adjust pricing and stock as needed.
