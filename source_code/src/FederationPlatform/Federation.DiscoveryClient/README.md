# Federation Discovery Client

Reusable web component for embedding cross-BU federated product search on individual BU storefronts.

## Features

- 🎯 **Lightweight** — Vanilla JS, no dependencies
- 🎨 **Themeable** — Built-in themes for BU-A (blue) and BU-B (green)
- 📱 **Responsive** — Mobile-friendly grid layout
- ⚡ **Performant** — Debounced search, pagination, caching-friendly API
- ♿ **Accessible** — Semantic HTML, keyboard navigation
- 🔗 **Deep-linking** — Products link directly to their BU store page

## Installation

### 1. Copy files to BU website

Copy the component files to your nopCommerce web project's static assets:

```bash
cp federated-search.js  Presentation/Nop.Web/wwwroot/lib/federated-search/
cp federated-search.css Presentation/Nop.Web/wwwroot/lib/federated-search/
```

### 2. Include in your page (e.g., homepage)

**Option A: Declarative (data attributes)**

```html
<link rel="stylesheet" href="/lib/federated-search/federated-search.css" />

<div id="federated-search" 
     data-federated-search
     data-api-base="http://localhost:5010"
     data-theme="bu-a"
     data-store-filter="bu-a"
     data-show-filter="true">
</div>

<script type="module">
  import { FederatedSearch } from '/lib/federated-search/federated-search.js';
  // Auto-initializes via data attributes
</script>
```

**Option B: Programmatic**

```html
<link rel="stylesheet" href="/lib/federated-search/federated-search.css" />

<div id="federated-search"></div>

<script type="module">
  import { FederatedSearch } from '/lib/federated-search/federated-search.js';
  
  new FederatedSearch({
    containerId: 'federated-search',
    apiBase: 'http://localhost:5010',
    theme: 'bu-a',
    defaultStoreFilter: 'bu-a',
    showStoreFilter: true
  });
</script>
```

## Configuration

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `containerId` | string | `'federated-search'` | DOM element ID where component renders |
| `apiBase` | string | `'http://localhost:5010'` | Discovery API base URL (local-dev fallback when omitted) |
| `theme` | string | `'default'` | Theme name: `'default'`, `'bu-a'`, or `'bu-b'` |
| `defaultStoreFilter` | string | `''` | Pre-select a store filter (e.g., `'bu-a'` shows only BU-A products) |
| `showStoreFilter` | boolean | `true` | Show/hide store filter buttons |
| `pageSize` | number | `20` | Results per page |
| `debounceMs` | number | `320` | Debounce delay for search input (milliseconds) |

### Examples

Set `data-api-base` or `apiBase` explicitly when Discovery runs behind a non-local URL.

**BU-A Homepage (HomeStyle Living)**
```javascript
new FederatedSearch({
  containerId: 'federated-search',
  apiBase: 'http://localhost:5010',
  theme: 'bu-a',
  defaultStoreFilter: 'bu-a',  // Only show HomeStyle Living
  showStoreFilter: true         // Allow browsing other stores
});
```

**BU-B Homepage (WorkForge Industrial)**
```javascript
new FederatedSearch({
  containerId: 'federated-search',
  apiBase: 'http://localhost:5010',
  theme: 'bu-b',
  defaultStoreFilter: 'bu-b',  // Only show WorkForge Industrial
  showStoreFilter: true
});
```

**Standalone Portal style (All stores, neutral theme)**
```javascript
new FederatedSearch({
  containerId: 'federated-search',
  apiBase: 'http://localhost:5010',
  theme: 'default',
  defaultStoreFilter: '',       // Show all stores
  showStoreFilter: true
});
```

## CSS Customization

The component uses CSS custom properties (variables) for theming. Override at the parent level:

```css
/* Custom theme for a BU */
#federated-search {
  --fed-accent: #your-brand-color;
  --fed-accent-hover: #darker-shade;
  --fed-text: #your-text-color;
}
```

## API Integration

The component expects these endpoints from the Discovery API:

### `/api/search`

Query parameters:
- `q` (string) — search query
- `stores` (string, optional) — comma-separated store codes (e.g., `'bu-a,bu-b'`)
- `page` (number, default: 0) — zero-indexed page number
- `pageSize` (number, default: 20) — results per page
- `sort` (string, optional) — sort option (`'price:asc'`, `'price:desc'`, `'publishedAt:desc'`)

Response:
```json
{
  "hits": [
    {
      "productId": 123,
      "productName": "Samsung Galaxy S23",
      "storeCode": "bu-a",
      "storeName": "HomeStyle Living",
      "price": 799.99,
      "thumbnailUrl": "https://...",
      "productUrl": "http://localhost:5001/samsung-galaxy-s23",
      "slug": "samsung-galaxy-s23",
      "shortDescription": "Latest flagship phone",
      "categories": ["Cell phones", "Electronics"]
    }
  ],
  "totalHits": 2,
  "page": 0,
  "pageSize": 20
}
```

### `/api/facets`

Query parameters:
- `q` (string, optional) — filter facets by search query

Response:
```json
{
  "stores": {
    "bu-a": { "name": "HomeStyle Living", "count": 1 },
    "bu-b": { "name": "WorkForge Industrial", "count": 1 }
  }
}
```

## Browser Support

- Chrome/Edge 88+
- Firefox 87+
- Safari 14+
- iOS Safari 14+

## Performance Notes

1. **Debounced search** (320ms) reduces API calls during rapid typing
2. **Cached facets** — store names are cached after first load
3. **Lazy image loading** — `loading="lazy"` on product thumbnails
4. **Output caching (server-side)** — Discovery API caches responses 5–30s

For 100+ results per store, pagination is automatically enabled.

## Troubleshooting

**Component not showing?**
- Check browser console for JavaScript errors
- Verify `containerId` matches your HTML `id` attribute
- Ensure CSS file is loaded (check Network tab)

**API requests failing?**
- Confirm `apiBase` URL is correct (no trailing slash)
- Check CORS headers from Discovery API (`Access-Control-Allow-Origin`)
- Verify Discovery API is running: `curl http://localhost:5010/api/facets`

**Styling looks broken?**
- Check CSS file is loaded (Network tab)
- Verify theme class is applied: inspect `.fed-search--bu-a` or `.fed-search--bu-b`
- Clear browser cache and hard-refresh

## Examples

See `demo.html` for a standalone example.

## License

Part of nopCommerce Federated Commerce Platform.

