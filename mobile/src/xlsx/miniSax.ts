/**
 * A tiny event-style XML reader — just enough for the parts of an `.xlsx` this app reads and writes. Reports
 * element starts (with attributes), text, and element ends, in document order. Namespace prefixes are dropped
 * from element names (`x:sheet` → `sheet`) but kept on attributes (`r:id`).
 */
export interface SaxHandler {
  start?(name: string, attributes: Record<string, string>): void;
  text?(text: string): void;
  end?(name: string): void;
}

const ENTITIES: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };

export function decodeXmlEntities(text: string): string {
  if (!text.includes('&')) return text;
  return text.replace(/&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);/g, (whole, body: string) => {
    if (body[0] !== '#') return ENTITIES[body] ?? whole;
    const code = body[1] === 'x' || body[1] === 'X' ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
    return Number.isFinite(code) ? String.fromCodePoint(code) : whole;
  });
}

const localName = (qualified: string) => qualified.slice(qualified.lastIndexOf(':') + 1);

export function parseXml(xml: string, handler: SaxHandler): void {
  const token = /<!\[CDATA\[([\s\S]*?)\]\]>|<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!DOCTYPE[^>]*>|<\/([^\s>]+)\s*>|<([^\s/>]+)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>|([^<]+)/g;
  const attribute = /([^\s=]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
  let match: RegExpExecArray | null;
  while ((match = token.exec(xml))) {
    const [, cdata, closing, opening, attributeText, selfClosing, text] = match;
    if (cdata !== undefined) {
      handler.text?.(cdata);
    } else if (closing !== undefined) {
      handler.end?.(localName(closing));
    } else if (opening !== undefined) {
      const attributes: Record<string, string> = {};
      let attr: RegExpExecArray | null;
      attribute.lastIndex = 0;
      while ((attr = attribute.exec(attributeText))) attributes[attr[1]] = decodeXmlEntities(attr[2] ?? attr[3] ?? '');
      const name = localName(opening);
      handler.start?.(name, attributes);
      if (selfClosing) handler.end?.(name);
    } else if (text !== undefined) {
      handler.text?.(decodeXmlEntities(text));
    }
  }
}
