import type { Page } from '@playwright/test';

export type EpmHeaderMetadata = {
  exists: boolean;
  titleText: string | null;
  display: string | null;
  position: string | null;
  top: string | null;
  zIndex: string | null;
  pointerEvents: string | null;
  headerClassList: string[];
  cssVars: Record<string, string | null>;
};

export type EpmShellSnapshot = {
  currentPageTitleText: string | null;
  activeTab: string | null;
  header: EpmHeaderMetadata;
};

export async function getEpmShellSnapshot(page: Page): Promise<EpmShellSnapshot> {
  return page.evaluate(() => {
    const clean = (v: string | null | undefined): string | null => {
      if (!v) return null;
      const t = v.replace(/\s+/g, ' ').trim();
      return t.length ? t : null;
    };

    const headerEl = document.querySelector('oj-sp-header-general-overview');
    const pageTitleEl =
      headerEl?.querySelector('.oj-sp-header-general-overview-page-title') ??
      document.querySelector('.oj-sp-header-general-overview-page-title') ??
      document.querySelector('h1');

    const currentPageTitleText = clean(pageTitleEl?.textContent ?? null);

    const activeTabEl =
      document.querySelector('[role="tab"][aria-selected="true"]') ??
      document.querySelector('.oj-tabbar-item[aria-selected="true"]') ??
      document.querySelector('.oj-selected[role="tab"]');
    const activeTab = clean(activeTabEl?.textContent ?? null);

    const computed = headerEl ? window.getComputedStyle(headerEl) : null;
    const root = document.documentElement;
    const rootComputed = window.getComputedStyle(root);

    const cssVarKeys = [
      '--oj-sp-theme-page-header-strip',
      '--oj-sp-headers-title-sm-up-font-size',
      '--oj-sp-headers-title-font-weight',
      '--oj-sp-headers-title-sm-up-line-height',
      '--oj-typography-heading-2xl-font-size',
      '--oj-typography-heading-2xl-font-weight',
      '--oj-typography-heading-2xl-line-height',
    ];
    const cssVars: Record<string, string | null> = {};
    for (const key of cssVarKeys) {
      cssVars[key] = clean(rootComputed.getPropertyValue(key));
    }

    return {
      currentPageTitleText,
      activeTab,
      header: {
        exists: Boolean(headerEl),
        titleText: clean(pageTitleEl?.textContent ?? null),
        display: computed ? clean(computed.display) : null,
        position: computed ? clean(computed.position) : null,
        top: computed ? clean(computed.top) : null,
        zIndex: computed ? clean(computed.zIndex) : null,
        pointerEvents: computed ? clean(computed.pointerEvents) : null,
        headerClassList: headerEl ? Array.from(headerEl.classList) : [],
        cssVars,
      },
    };
  });
}
