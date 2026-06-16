/**
 * Safe expression evaluator for catalog formulas and conditions.
 *
 * No eval(). Recursive descent parser supporting:
 *   Arithmetic: + - * /
 *   Comparison: > < >= <= == !=
 *   Logic: AND OR NOT (case-insensitive)
 *   Functions: ceil() floor() round() max() min() if()
 *   State keys: bare words resolve to state values
 *   Literals: numbers, quoted strings ("yes", "full_gut")
 */
import { UnknownFormulaTokenError } from '../errors/index.js';

// ─── Tokenizer ──────────────────────────────────────────────────────────────

const TOKEN = {
  NUMBER: 'NUMBER',
  STRING: 'STRING',
  IDENT:  'IDENT',
  OP:     'OP',
  LPAREN: 'LPAREN',
  RPAREN: 'RPAREN',
  COMMA:  'COMMA',
  EOF:    'EOF',
};

function tokenize(expr) {
  const tokens = [];
  let i = 0;
  while (i < expr.length) {
    // Skip whitespace
    if (/\s/.test(expr[i])) { i++; continue; }

    // Number (including decimals)
    if (/[0-9.]/.test(expr[i])) {
      let num = '';
      while (i < expr.length && /[0-9.]/.test(expr[i])) num += expr[i++];
      tokens.push({ type: TOKEN.NUMBER, value: parseFloat(num) });
      continue;
    }

    // String literal "..."
    if (expr[i] === '"') {
      i++; // skip opening quote
      let str = '';
      while (i < expr.length && expr[i] !== '"') str += expr[i++];
      i++; // skip closing quote
      tokens.push({ type: TOKEN.STRING, value: str });
      continue;
    }

    // Two-char operators
    const two = expr.slice(i, i + 2);
    if (['>=', '<=', '==', '!='].includes(two)) {
      tokens.push({ type: TOKEN.OP, value: two });
      i += 2;
      continue;
    }

    // Single-char operators
    if ('+-*/><!'.includes(expr[i])) {
      tokens.push({ type: TOKEN.OP, value: expr[i] });
      i++;
      continue;
    }

    // Parens, comma
    if (expr[i] === '(') { tokens.push({ type: TOKEN.LPAREN }); i++; continue; }
    if (expr[i] === ')') { tokens.push({ type: TOKEN.RPAREN }); i++; continue; }
    if (expr[i] === ',') { tokens.push({ type: TOKEN.COMMA });  i++; continue; }

    // {param} bracketed parameter reference — strip braces, emit as IDENT
    if (expr[i] === '{') {
      i++; // skip {
      let id = '';
      while (i < expr.length && expr[i] !== '}') id += expr[i++];
      i++; // skip }
      tokens.push({ type: TOKEN.IDENT, value: id });
      continue;
    }

    // Identifier or keyword (alphanumeric + underscore)
    if (/[a-zA-Z_]/.test(expr[i])) {
      let id = '';
      while (i < expr.length && /[a-zA-Z0-9_]/.test(expr[i])) id += expr[i++];
      tokens.push({ type: TOKEN.IDENT, value: id });
      continue;
    }

    // Unknown char — skip
    i++;
  }
  tokens.push({ type: TOKEN.EOF });
  return tokens;
}

// ─── Parser ─────────────────────────────────────────────────────────────────
// Precedence (low to high): OR, AND, NOT, comparison, add/sub, mul/div, unary, atom

class Parser {
  constructor(tokens, state) {
    this.tokens = tokens;
    this.pos = 0;
    this.state = state;
  }

  peek() { return this.tokens[this.pos]; }
  advance() { return this.tokens[this.pos++]; }

  expect(type) {
    const t = this.advance();
    if (t.type !== type) {
      throw new UnknownFormulaTokenError(
        `Expected ${type}, got ${t.type}`,
        { expected: type, actual: t.type },
      );
    }
    return t;
  }

  // ── Entry point ─────────────────────────────────────────────────────────
  parse() {
    const result = this.parseOr();
    return result;
  }

  // ── OR ──────────────────────────────────────────────────────────────────
  parseOr() {
    let left = this.parseAnd();
    while (this.peek().type === TOKEN.IDENT && this.peek().value.toUpperCase() === 'OR') {
      this.advance();
      const right = this.parseAnd(); // must always parse to consume tokens
      left = left || right;
    }
    return left;
  }

  // ── AND ─────────────────────────────────────────────────────────────────
  parseAnd() {
    let left = this.parseNot();
    while (this.peek().type === TOKEN.IDENT && this.peek().value.toUpperCase() === 'AND') {
      this.advance();
      const right = this.parseNot(); // must always parse to consume tokens
      left = left && right;
    }
    return left;
  }

  // ── NOT ─────────────────────────────────────────────────────────────────
  parseNot() {
    if (this.peek().type === TOKEN.IDENT && this.peek().value.toUpperCase() === 'NOT') {
      this.advance();
      return !this.parseNot();
    }
    return this.parseComparison();
  }

  // ── Comparison: == != > < >= <= ──────────────────────────────────────────
  parseComparison() {
    let left = this.parseAddSub();
    const t = this.peek();
    if (t.type === TOKEN.OP && ['==', '!=', '>', '<', '>=', '<='].includes(t.value)) {
      const op = this.advance().value;
      const right = this.parseAddSub();
      switch (op) {
        case '==': return left == right;  // intentional loose equality for "yes"/true
        case '!=': return left != right;
        case '>':  return left > right;
        case '<':  return left < right;
        case '>=': return left >= right;
        case '<=': return left <= right;
      }
    }
    return left;
  }

  // ── Addition / Subtraction ──────────────────────────────────────────────
  parseAddSub() {
    let left = this.parseMulDiv();
    while (this.peek().type === TOKEN.OP && (this.peek().value === '+' || this.peek().value === '-')) {
      const op = this.advance().value;
      const right = this.parseMulDiv();
      left = op === '+' ? left + right : left - right;
    }
    return left;
  }

  // ── Multiplication / Division ───────────────────────────────────────────
  parseMulDiv() {
    let left = this.parseUnary();
    while (this.peek().type === TOKEN.OP && (this.peek().value === '*' || this.peek().value === '/')) {
      const op = this.advance().value;
      const right = this.parseUnary();
      left = op === '*' ? left * right : left / right;
    }
    return left;
  }

  // ── Unary minus ─────────────────────────────────────────────────────────
  parseUnary() {
    if (this.peek().type === TOKEN.OP && this.peek().value === '-') {
      this.advance();
      return -this.parseUnary();
    }
    return this.parseAtom();
  }

  // ── Atom: number, string, function call, state key, parenthesized expr ─
  parseAtom() {
    const t = this.peek();

    // Number literal
    if (t.type === TOKEN.NUMBER) {
      this.advance();
      return t.value;
    }

    // String literal
    if (t.type === TOKEN.STRING) {
      this.advance();
      return t.value;
    }

    // Parenthesized expression
    if (t.type === TOKEN.LPAREN) {
      this.advance();
      const val = this.parseOr();
      this.expect(TOKEN.RPAREN);
      return val;
    }

    // Identifier: function call, keyword, or state key
    if (t.type === TOKEN.IDENT) {
      const name = t.value;
      const upper = name.toUpperCase();

      // Boolean literals
      if (upper === 'TRUE') { this.advance(); return true; }
      if (upper === 'FALSE') { this.advance(); return false; }

      // Function call?
      this.advance();
      if (this.peek().type === TOKEN.LPAREN) {
        return this.parseFunction(name);
      }

      // State key lookup
      const val = this.state[name];
      if (val !== undefined) {
        const num = parseFloat(val);
        return isNaN(num) ? val : num;
      }
      return 0; // Unknown key → 0 (safe default for arithmetic)
    }

    throw new UnknownFormulaTokenError(
      `Unexpected token: ${JSON.stringify(t)}`,
      { token: t },
    );
  }

  // ── Function calls ────────────────────────────────────────────────────────
  parseFunction(name) {
    this.expect(TOKEN.LPAREN);
    const args = [];
    if (this.peek().type !== TOKEN.RPAREN) {
      args.push(this.parseOr());
      while (this.peek().type === TOKEN.COMMA) {
        this.advance();
        args.push(this.parseOr());
      }
    }
    this.expect(TOKEN.RPAREN);

    const fn = name.toLowerCase();
    switch (fn) {
      case 'ceil':  return Math.ceil(args[0]);
      case 'floor': return Math.floor(args[0]);
      case 'round': return Math.round(args[0]);
      case 'max':   return Math.max(...args);
      case 'min':   return Math.min(...args);
      case 'abs':   return Math.abs(args[0]);
      case 'if':    return args[0] ? args[1] : args[2];
      default:
        console.warn(`[formulaEngine] Unknown function: ${name}`);
        return 0;
    }
  }
}

// ─── Public API ─────────────────────────────────────────────────────────────

/**
 * Evaluate a quantity formula against project state.
 * Returns a number, or null if the formula fails.
 */
/**
 * Strict variant — parses the formula and propagates any
 * UnknownFormulaTokenError to the caller. Used by tests + by callers that
 * want to fail loud on a malformed expression instead of silently falling
 * back to a default quantity.
 */
export function parseFormulaStrict(formula, state) {
  const tokens = tokenize(formula);
  const parser = new Parser(tokens, state);
  return parser.parse();
}

export function evaluateFormula(formula, state) {
  if (!formula || typeof formula !== 'string') return null;
  try {
    const tokens = tokenize(formula);
    const parser = new Parser(tokens, state);
    const result = parser.parse();
    if (typeof result !== 'number' || isNaN(result) || !isFinite(result)) return null;
    return result;
  } catch (e) {
    console.warn(`[formulaEngine] Formula error: "${formula}" →`, e.message);
    return null;
  }
}

/**
 * Evaluate a condition trigger against project state.
 * Returns true (item included) or false (item excluded).
 * Special case: "always" → true.
 */
export function evaluateCondition(condition, state) {
  if (!condition || condition === 'always') return true;
  try {
    const tokens = tokenize(condition);
    const parser = new Parser(tokens, state);
    const result = parser.parse();
    return !!result;
  } catch (e) {
    console.warn(`[formulaEngine] Condition error: "${condition}" →`, e.message);
    return false;
  }
}
