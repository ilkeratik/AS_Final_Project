#!/usr/bin/env python3
"""Validate BU CSV inputs for a minimal nopCommerce catalog import."""
from __future__ import annotations

import argparse
import csv
from pathlib import Path

REQUIRED_FILES = [
    "stores.csv",
    "languages.csv",
    "categories.csv",
    "manufacturers.csv",
    "products.csv",
    "product_categories.csv",
    "product_manufacturers.csv",
]

REQUIRED_COLUMNS = {
    "stores.csv": [
        "StoreName",
        "Url",
        "Hosts",
        "SslEnabled",
        "DefaultLanguageCulture",
        "DisplayOrder",
    ],
    "languages.csv": [
        "Name",
        "LanguageCulture",
        "UniqueSeoCode",
        "Rtl",
        "Published",
        "DisplayOrder",
    ],
    "categories.csv": [
        "Name",
        "ParentCategory",
        "Description",
        "Published",
        "DisplayOrder",
    ],
    "manufacturers.csv": [
        "Name",
        "Description",
        "Published",
        "DisplayOrder",
    ],
    "products.csv": [
        "Sku",
        "Name",
        "ShortDescription",
        "FullDescription",
        "Price",
        "OldPrice",
        "Cost",
        "StockQuantity",
        "Published",
        "VisibleIndividually",
    ],
    "product_categories.csv": [
        "ProductSku",
        "CategoryName",
        "IsFeaturedProduct",
        "DisplayOrder",
    ],
    "product_manufacturers.csv": [
        "ProductSku",
        "ManufacturerName",
        "IsFeaturedProduct",
        "DisplayOrder",
    ],
}


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        rows = [row for row in reader]
    return rows


def _assert_columns(path: Path, required: list[str]) -> list[str]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        headers = reader.fieldnames or []
    missing = [col for col in required if col not in headers]
    return missing


def validate(input_dir: Path) -> list[str]:
    errors: list[str] = []

    for filename in REQUIRED_FILES:
        file_path = input_dir / filename
        if not file_path.exists():
            errors.append(f"Missing required file: {filename}")
            continue
        missing = _assert_columns(file_path, REQUIRED_COLUMNS[filename])
        if missing:
            errors.append(f"{filename} missing columns: {', '.join(missing)}")

    if errors:
        return errors

    products = _read_csv(input_dir / "products.csv")
    categories = _read_csv(input_dir / "categories.csv")
    manufacturers = _read_csv(input_dir / "manufacturers.csv")

    product_skus = {row["Sku"].strip() for row in products if row.get("Sku")}
    category_names = {row["Name"].strip() for row in categories if row.get("Name")}
    manufacturer_names = {row["Name"].strip() for row in manufacturers if row.get("Name")}

    for row in _read_csv(input_dir / "product_categories.csv"):
        sku = row.get("ProductSku", "").strip()
        cat = row.get("CategoryName", "").strip()
        if sku and sku not in product_skus:
            errors.append(f"product_categories.csv: unknown ProductSku '{sku}'")
        if cat and cat not in category_names:
            errors.append(f"product_categories.csv: unknown CategoryName '{cat}'")

    for row in _read_csv(input_dir / "product_manufacturers.csv"):
        sku = row.get("ProductSku", "").strip()
        manufacturer = row.get("ManufacturerName", "").strip()
        if sku and sku not in product_skus:
            errors.append(f"product_manufacturers.csv: unknown ProductSku '{sku}'")
        if manufacturer and manufacturer not in manufacturer_names:
            errors.append(f"product_manufacturers.csv: unknown ManufacturerName '{manufacturer}'")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate BU CSV inputs")
    parser.add_argument("--input", required=True, help="Path to BU CSV directory")
    parser.add_argument("--bu", default="", help="BU label for display")
    args = parser.parse_args()

    input_dir = Path(args.input)
    label = f" ({args.bu})" if args.bu else ""

    if not input_dir.exists():
        print(f"ERROR: input directory does not exist: {input_dir}{label}")
        return 2

    errors = validate(input_dir)
    if errors:
        print(f"CSV validation failed{label}:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(f"CSV validation OK{label}: {input_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
