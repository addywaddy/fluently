import { toArray } from './util';
import { shouldEmbed, embedResources } from './embed-resources';
// Fluently: read stylesheets without inserting rules into the host document.
// Remote CSS uses the same credential/referrer/timeout policy as font assets.
async function getCSSRules(styleSheets, options) {
    const fonts = [];
    const visited = new Set();
    async function readRemote(url, depth) {
        if (visited.has(url) || visited.size >= 64 || depth > 8) return;
        visited.add(url);
        try {
            const response = await fetch(url, options.fetchRequestInit);
            if (!response.ok) return;
            const css = await response.text();
            const doc = document.implementation.createHTMLDocument('');
            const base = doc.createElement('base');
            base.href = response.url || url;
            const style = doc.createElement('style');
            style.textContent = css;
            doc.head.append(base, style);
            if (style.sheet) await readRules(style.sheet.cssRules, base.href, depth);
        } catch {
            // Unavailable/CORS-blocked fonts fall back to the browser's font stack.
        }
    }
    async function readSheet(sheet, baseUrl, depth) {
        if (depth > 8) return;
        try {
            await readRules(sheet.cssRules, sheet.href || baseUrl, depth);
        } catch {
            if (sheet.href) await readRemote(sheet.href, depth);
        }
    }
    async function readRules(rules, baseUrl, depth) {
        if (depth > 8) return;
        for (const rule of toArray(rules || [])) {
            if (rule.type === CSSRule.FONT_FACE_RULE) {
                fonts.push({type: rule.type, style: rule.style, cssText: rule.cssText,
                    parentStyleSheet: {href: baseUrl}});
            } else if (rule.type === CSSRule.IMPORT_RULE) {
                const url = new URL(rule.href, baseUrl).href;
                let importedRules;
                try { importedRules = rule.styleSheet?.cssRules; } catch { /* CORS stylesheet */ }
                if (importedRules?.length) await readRules(importedRules, url, depth + 1);
                else await readRemote(url, depth + 1);
            } else if (rule.cssRules) {
                await readRules(rule.cssRules, baseUrl, depth);
            }
        }
    }
    for (const sheet of styleSheets) {
        await readSheet(sheet, document.baseURI, 0);
    }
    return fonts;
}
function getWebFontRules(cssRules) {
    return cssRules
        .filter((rule) => rule.type === CSSRule.FONT_FACE_RULE)
        .filter((rule) => shouldEmbed(rule.style.getPropertyValue('src')));
}
async function parseWebFontRules(node, options) {
    if (node.ownerDocument == null) {
        throw new Error('Provided element is not within a Document');
    }
    const styleSheets = toArray(node.ownerDocument.styleSheets);
    const cssRules = await getCSSRules(styleSheets, options);
    return getWebFontRules(cssRules);
}
function normalizeFontFamily(font) {
    return font.trim().replace(/["']/g, '');
}
function getUsedFonts(node) {
    const fonts = new Set();
    function traverse(node) {
        const fontFamily = node.style.fontFamily || getComputedStyle(node).fontFamily;
        fontFamily.split(',').forEach((font) => {
            fonts.add(normalizeFontFamily(font));
        });
        Array.from(node.children).forEach((child) => {
            if (child instanceof HTMLElement) {
                traverse(child);
            }
        });
    }
    traverse(node);
    return fonts;
}
export async function getWebFontCSS(node, options) {
    const rules = await parseWebFontRules(node, options);
    const usedFonts = getUsedFonts(node);
    const cssTexts = await Promise.all(rules
        .filter((rule) => usedFonts.has(normalizeFontFamily(rule.style.fontFamily)))
        .map((rule) => {
        const baseUrl = rule.parentStyleSheet
            ? rule.parentStyleSheet.href
            : null;
        return embedResources(rule.cssText, baseUrl, options);
    }));
    return cssTexts.join('\n');
}
export async function embedWebFonts(clonedNode, options) {
    const cssText = options.fontEmbedCSS != null
        ? options.fontEmbedCSS
        : options.skipFonts
            ? null
            : await getWebFontCSS(clonedNode, options);
    if (cssText) {
        const styleNode = document.createElement('style');
        const sytleContent = document.createTextNode(cssText);
        styleNode.appendChild(sytleContent);
        if (clonedNode.firstChild) {
            clonedNode.insertBefore(styleNode, clonedNode.firstChild);
        }
        else {
            clonedNode.appendChild(styleNode);
        }
    }
}
