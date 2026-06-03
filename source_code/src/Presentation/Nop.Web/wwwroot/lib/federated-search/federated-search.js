/**
 * Federated Search Component
 * Reusable web component for embedding cross-BU product search on individual BU websites.
 * 
 * Usage:
 *   import { FederatedSearch } from './federated-search.js';
 *   new FederatedSearch({
 *     apiBase: 'http://localhost:5010',
 *     containerId: 'federated-search',
 *     theme: 'bu-a',
 *     defaultStoreFilter: 'bu-a',
 *     showStoreFilter: true
 *   });
 */

const DEFAULT_API_BASE = 'http://localhost:5010';

function normalizeApiBase(apiBase) {
  return String(apiBase || DEFAULT_API_BASE).replace(/\/+$/, '');
}

export class FederatedSearch {
  constructor(options = {}) {
    this.apiBase = normalizeApiBase(options.apiBase);
    this.containerId = options.containerId || 'federated-search';
    this.theme = options.theme || 'default';
    this.defaultStoreFilter = options.defaultStoreFilter || '';
    this.showStoreFilter = options.showStoreFilter !== false;
    this.pageSize = options.pageSize || 20;
    this.debounceMs = options.debounceMs || 320;
    
    this.state = {
      q: '',
      store: this.defaultStoreFilter,
      page: 0,
      sort: '',
      total: 0,
      stores: {},
    };
    
    this.debounceTimer = null;
    this.container = null;
    this.dom = {};
    
    this.init();
  }

  init() {
    this.container = document.getElementById(this.containerId);
    if (!this.container) {
      console.error(`FederatedSearch: container #${this.containerId} not found`);
      return;
    }
    
    this.render();
    this.attachEventListeners();
    this.loadFacets('');
    this.renderPrompt();
  }

  render() {
    this.container.innerHTML = `
      <div class="fed-search fed-search--${this.theme}">
        <div class="fed-search__header">
          <h2 class="fed-search__title">🛍 Search All Stores</h2>
          <div class="fed-search__search-wrap">
            <input 
              type="search" 
              class="fed-search__input" 
              id="${this.containerId}-input"
              placeholder="Search products, categories…" 
              autocomplete="off" />
            <span class="fed-search__icon">🔍</span>
          </div>
        </div>

        ${this.showStoreFilter ? `
          <div class="fed-search__filters" id="${this.containerId}-filters">
            <button class="fed-search__filter-btn fed-search__filter-btn--active" data-store="">All Stores</button>
          </div>
        ` : ''}

        <div class="fed-search__content">
          <div class="fed-search__meta-bar" id="${this.containerId}-meta" style="display:none">
            <span class="fed-search__count" id="${this.containerId}-count"></span>
            <select class="fed-search__sort" id="${this.containerId}-sort">
              <option value="">Relevance</option>
              <option value="price:asc">Price ↑</option>
              <option value="price:desc">Price ↓</option>
              <option value="publishedAt:desc">Newest</option>
            </select>
          </div>

          <div class="fed-search__results" id="${this.containerId}-results"></div>

          <nav class="fed-search__pagination" id="${this.containerId}-pagination" style="display:none">
            <button class="fed-search__page-btn" id="${this.containerId}-prev" disabled>← Prev</button>
            <span class="fed-search__page-info" id="${this.containerId}-page-info"></span>
            <button class="fed-search__page-btn" id="${this.containerId}-next">Next →</button>
          </nav>
        </div>
      </div>
    `;
    
    // Cache DOM references
    this.dom = {
      input: document.getElementById(`${this.containerId}-input`),
      filterBar: document.getElementById(`${this.containerId}-filters`),
      meta: document.getElementById(`${this.containerId}-meta`),
      count: document.getElementById(`${this.containerId}-count`),
      sort: document.getElementById(`${this.containerId}-sort`),
      results: document.getElementById(`${this.containerId}-results`),
      pagination: document.getElementById(`${this.containerId}-pagination`),
      prevBtn: document.getElementById(`${this.containerId}-prev`),
      nextBtn: document.getElementById(`${this.containerId}-next`),
      pageInfo: document.getElementById(`${this.containerId}-page-info`),
    };
  }

  attachEventListeners() {
    if (this.dom.input) {
      this.dom.input.addEventListener('input', e => {
        this.state.q = e.target.value;
        this.state.page = 0;
        this.debounce(() => this.search(), this.debounceMs);
      });
      
      this.dom.input.addEventListener('keydown', e => {
        if (e.key === 'Enter') {
          clearTimeout(this.debounceTimer);
          this.search();
        }
      });
    }
    
    if (this.dom.sort) {
      this.dom.sort.addEventListener('change', e => {
        this.state.sort = e.target.value;
        this.state.page = 0;
        this.search();
      });
    }
    
    if (this.dom.prevBtn) {
      this.dom.prevBtn.addEventListener('click', () => {
        this.state.page--;
        this.search();
        this.container.scrollIntoView({ behavior: 'smooth' });
      });
    }
    
    if (this.dom.nextBtn) {
      this.dom.nextBtn.addEventListener('click', () => {
        this.state.page++;
        this.search();
        this.container.scrollIntoView({ behavior: 'smooth' });
      });
    }
    
    if (this.dom.filterBar) {
      this.dom.filterBar.addEventListener('click', e => {
        const btn = e.target.closest('.fed-search__filter-btn');
        if (btn) {
          this.selectStore(btn.dataset.store);
        }
      });
    }
  }

  debounce(fn, ms) {
    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(fn, ms);
  }

  selectStore(code) {
    this.state.store = code;
    this.state.page = 0;
    
    if (this.dom.filterBar) {
      this.dom.filterBar.querySelectorAll('.fed-search__filter-btn').forEach(b => {
        b.classList.toggle('fed-search__filter-btn--active', b.dataset.store === code);
      });
    }
    
    if (this.state.q) this.search();
  }

  async loadFacets(q) {
    try {
      const url = q 
        ? `${this.apiBase}/api/facets?q=${encodeURIComponent(q)}` 
        : `${this.apiBase}/api/facets`;
      const res = await fetch(url);
      if (!res.ok) return;
      const data = await res.json();
      const storeMap = data.stores || {};
      this.buildFilterButtons(storeMap);
    } catch (e) {
      console.error('FederatedSearch: loadFacets error', e);
    }
  }

  buildFilterButtons(storeMap) {
    if (!this.dom.filterBar) return;
    
    // Remove all store buttons except "All"
    this.dom.filterBar.querySelectorAll('[data-store]:not([data-store=""])').forEach(b => b.remove());
    
    for (const [code, info] of Object.entries(storeMap).sort()) {
      let name = code;
      let count = 0;
      
      // Handle both object and number formats from API
      if (typeof info === 'object') {
        name = info.name && info.name !== code ? info.name : code;
        count = info.count || 0;
      } else {
        name = code;
        count = info;
      }
      
      this.state.stores[code] = name;
      
      const btn = document.createElement('button');
      btn.className = `fed-search__filter-btn ${this.state.store === code ? 'fed-search__filter-btn--active' : ''}`;
      btn.dataset.store = code;
      btn.textContent = `${name} (${count})`;
      this.dom.filterBar.appendChild(btn);
    }
  }

  renderSkeleton() {
    this.dom.results.innerHTML = `
      <div class="fed-search__spinner-wrap">
        <div class="fed-search__spinner"></div>
      </div>
    `;
    this.dom.meta.style.display = 'none';
    this.dom.pagination.style.display = 'none';
  }

  renderEmpty(q) {
    this.dom.results.innerHTML = `
      <div class="fed-search__state-box">
        <div class="fed-search__state-emoji">🔍</div>
        <h3 class="fed-search__state-title">No results for "${this.esc(q)}"</h3>
        <p class="fed-search__state-text">Try a different search term or clear the store filter.</p>
      </div>
    `;
    this.dom.meta.style.display = 'none';
    this.dom.pagination.style.display = 'none';
  }

  renderPrompt() {
    this.dom.results.innerHTML = `
      <div class="fed-search__state-box">
        <div class="fed-search__state-emoji">🛍</div>
        <h3 class="fed-search__state-title">Find products across all stores</h3>
        <p class="fed-search__state-text">Type a product name, category, or keyword above to get started.</p>
      </div>
    `;
    this.dom.meta.style.display = 'none';
    this.dom.pagination.style.display = 'none';
  }

  renderError() {
    this.dom.results.innerHTML = `
      <div class="fed-search__state-box">
        <div class="fed-search__state-emoji">⚠️</div>
        <h3 class="fed-search__state-title">Something went wrong</h3>
        <p class="fed-search__state-text">Could not reach the discovery service. Please try again.</p>
      </div>
    `;
    this.dom.meta.style.display = 'none';
    this.dom.pagination.style.display = 'none';
  }

  renderResults(data) {
    const { hits, totalHits, page, pageSize } = data;
    
    // Update meta bar
    this.dom.meta.style.display = 'flex';
    this.dom.count.textContent = totalHits === 1 ? '1 result' : `${totalHits.toLocaleString()} results`;
    
    // Build grid
    const grid = document.createElement('div');
    grid.className = 'fed-search__grid';
    
    hits.forEach(h => grid.appendChild(this.buildCard(h)));
    
    this.dom.results.innerHTML = '';
    this.dom.results.appendChild(grid);
    
    // Pagination
    const totalPages = Math.ceil(totalHits / pageSize);
    if (totalPages > 1) {
      this.dom.pagination.style.display = 'flex';
      this.dom.prevBtn.disabled = page === 0;
      this.dom.nextBtn.disabled = page >= totalPages - 1;
      this.dom.pageInfo.textContent = `Page ${page + 1} of ${totalPages}`;
    } else {
      this.dom.pagination.style.display = 'none';
    }
  }

  buildCard(h) {
    const card = document.createElement('div');
    card.className = 'fed-search__card';
    
    const imgHtml = h.thumbnailUrl
      ? `<img class="fed-search__card-image" src="${this.esc(h.thumbnailUrl)}" alt="${this.esc(h.productName)}" loading="lazy">`
      : `<div class="fed-search__placeholder">📦</div>`;
    
    const catHtml = (h.categories || []).slice(0, 3)
      .map(c => `<span class="fed-search__cat-tag">${this.esc(c)}</span>`)
      .join('');
    
    let link = h.productUrl || '';
    
    if (link) {
      const trimmed = link.trim();
      if (!/^https?:\/\//i.test(trimmed)) {
        link = trimmed;
      }
    }
    
    const viewHtml = link
      ? `<a class="fed-search__btn-view" href="${this.esc(link)}" target="_blank" rel="noopener">View ↗</a>`
      : `<span class="fed-search__btn-view fed-search__btn-view--disabled">No link</span>`;
    
    const displayName = h.storeName || h.storeCode;
    
    card.innerHTML = `
      <div class="fed-search__card-img">${imgHtml}</div>
      <div class="fed-search__card-body">
        <span class="fed-search__store-badge fed-search__store-badge--${h.storeCode}">${this.esc(displayName)}</span>
        <h3 class="fed-search__card-title">${this.esc(h.productName)}</h3>
        ${h.shortDescription ? `<p class="fed-search__card-desc">${this.esc(h.shortDescription)}</p>` : ''}
        ${catHtml ? `<div class="fed-search__card-cats">${catHtml}</div>` : ''}
        <div class="fed-search__card-footer">
          <span class="fed-search__price">$${Number(h.price || 0).toFixed(2)}</span>
          ${viewHtml}
        </div>
      </div>
    `;

    const img = card.querySelector('.fed-search__card-image');
    if (img) {
      img.addEventListener('error', () => {
        const placeholder = document.createElement('div');
        placeholder.className = 'fed-search__placeholder';
        placeholder.textContent = '📦';
        img.parentElement?.replaceChildren(placeholder);
      }, { once: true });
    }
    
    return card;
  }

  esc(s) {
    if (s == null) return '';
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  async search() {
    const q = this.state.q.trim();
    if (!q) {
      this.renderPrompt();
      return;
    }
    
    this.renderSkeleton();
    
    try {
      const params = new URLSearchParams({
        q,
        page: this.state.page,
        pageSize: this.pageSize,
        sort: this.state.sort
      });
      
      if (this.state.store) {
        params.set('stores', this.state.store);
      }
      
      const [searchRes] = await Promise.all([
        fetch(`${this.apiBase}/api/search?${params}`),
        this.loadFacets(q)
      ]);
      
      if (!searchRes.ok) {
        this.renderError();
        return;
      }
      
      const data = await searchRes.json();
      
      if (!data.hits || data.hits.length === 0) {
        this.renderEmpty(q);
        return;
      }
      
      this.state.total = data.totalHits;
      this.renderResults(data);
    } catch (e) {
      console.error('FederatedSearch: search error', e);
      this.renderError();
    }
  }
}

// Auto-initialize if data attributes present on container
document.addEventListener('DOMContentLoaded', () => {
  const el = document.querySelector('[data-federated-search]');
  if (el) {
    const options = {
      containerId: el.id || 'federated-search',
      apiBase: normalizeApiBase(el.dataset.apiBase),
      theme: el.dataset.theme || 'default',
      defaultStoreFilter: el.dataset.storeFilter || '',
      showStoreFilter: el.dataset.showFilter !== 'false',
    };
    new FederatedSearch(options);
  }
});

