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

export type State = Record<string, unknown>;

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
} as const;

type TokenType = typeof TOKEN[keyof typeof TOKEN];
interface Token { type: TokenType; value?: number | string; }

function tokenize(expr: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  while (i < expr.length) {
    if (/\s/.test(expr[i])) { i++; continue; }

    if (/[0-9.]/.test(expr[i])) {
      let num = '';
      while (i < expr.length && /[0-9.]/.test(expr[i])) num += expr[i++];
      tokens.push({ type: TOKEN.NUMBER, value: parseFloat(num) });
      continue;
    }

    if (expr[i] === '"') {
      i++;
      let str = '';
      while (i < expr.length && expr[i] !== '"') str += expr[i++];
      i++;
      tokens.push({ type: TOKEN.STRING, value: str });
      continue;
    }

    const two = expr.slice(i, i + 2);
    if (['>=', '<=', '==', '!='].includes(two)) {
      tokens.push({ type: TOKEN.OP, value: two });
      i += 2;
      continue;
    }

    if ('+-*/><!'.includes(expr[i])) {
      tokens.push({ type: TOKEN.OP, value: expr[i] });
      i++;
      continue;
    }

    if (expr[i] === '(') { tokens.push({ type: TOKEN.LPAREN }); i++; continue; }
    if (expr[i] === ')') { tokens.push({ type: TOKEN.RPAREN }); i++; continue; }
    if (expr[i] === ',') { tokens.push({ type: TOKEN.COMMA });  i++; continue; }

    if (expr[i] === '{') {
      i++;
      let id = '';
      while (i < expr.length && expr[i] !== '}') id += expr[i++];
      i++;
      tokens.push({ type: TOKEN.IDENT, value: id });
      continue;
    }

    if (/[a-zA-Z_]/.test(expr[i])) {
      let id = '';
      while (i < expr.length && /[a-zA-Z0-9_]/.test(expr[i])) id += expr[i++];
      tokens.push({ type: TOKEN.IDENT, value: id });
      continue;
    }

    i++;
  }
  tokens.push({ type: TOKEN.EOF });
  return tokens;
}

// ─── Parser ─────────────────────────────────────────────────────────────────

type EvalResult = number | string | boolean;

class Parser {
  private tokens: Token[];
  private pos: number;
  private state: State;

  constructor(tokens: Token[], state: State) {
    this.tokens = tokens;
    this.pos = 0;
    this.state = state;
  }

  peek(): Token { return this.tokens[this.pos]; }
  advance(): Token { return this.tokens[this.pos++]; }

  expect(type: TokenType): Token {
    const t = this.advance();
    if (t.type !== type) {
      throw new UnknownFormulaTokenError(
        `Expected ${type}, got ${t.type}`,
        { expected: type, actual: t.type },
      );
    }
    return t;
  }

  parse(): EvalResult {
    return this.parseOr();
  }

  parseOr(): EvalResult {
    let left = this.parseAnd();
    while (this.peek().type === TOKEN.IDENT && String(this.peek().value).toUpperCase() === 'OR') {
      this.advance();
      const right = this.parseAnd();
      left = (left || right) as EvalResult;
    }
    return left;
  }

  parseAnd(): EvalResult {
    let left = this.parseNot();
    while (this.peek().type === TOKEN.IDENT && String(this.peek().value).toUpperCase() === 'AND') {
      this.advance();
      const right = this.parseNot();
      left = (left && right) as EvalResult;
    }
    return left;
  }

  parseNot(): EvalResult {
    if (this.peek().type === TOKEN.IDENT && String(this.peek().value).toUpperCase() === 'NOT') {
      this.advance();
      return !this.parseNot();
    }
    return this.parseComparison();
  }

  parseComparison(): EvalResult {
    const left = this.parseAddSub();
    const t = this.peek();
    if (t.type === TOKEN.OP && ['==', '!=', '>', '<', '>=', '<='].includes(String(t.value))) {
      const op = String(this.advance().value);
      const right = this.parseAddSub();
      // eslint-disable-next-line eqeqeq
      switch (op) {
        case '==': return left == right;
        case '!=': return left != right;
        case '>':  return (left as number) > (right as number);
        case '<':  return (left as number) < (right as number);
        case '>=': return (left as number) >= (right as number);
        case '<=': return (left as number) <= (right as number);
      }
    }
    return left;
  }

  parseAddSub(): EvalResult {
    let left = this.parseMulDiv();
    while (this.peek().type === TOKEN.OP && (this.peek().value === '+' || this.peek().value === '-')) {
      const op = this.advance().value as string;
      const right = this.parseMulDiv();
      left = op === '+' ? (left as number) + (right as number) : (left as number) - (right as number);
    }
    return left;
  }

  parseMulDiv(): EvalResult {
    let left = this.parseUnary();
    while (this.peek().type === TOKEN.OP && (this.peek().value === '*' || this.peek().value === '/')) {
      const op = this.advance().value as string;
      const right = this.parseUnary();
      left = op === '*' ? (left as number) * (right as number) : (left as number) / (right as number);
    }
    return left;
  }

  parseUnary(): EvalResult {
    if (this.peek().type === TOKEN.OP && this.peek().value === '-') {
      this.advance();
      return -(this.parseUnary() as number);
    }
    return this.parseAtom();
  }

  parseAtom(): EvalResult {
    const t = this.peek();

    if (t.type === TOKEN.NUMBER) {
      this.advance();
      return t.value as number;
    }

    if (t.type === TOKEN.STRING) {
      this.advance();
      return t.value as string;
    }

    if (t.type === TOKEN.LPAREN) {
      this.advance();
      const val = this.parseOr();
      this.expect(TOKEN.RPAREN);
      return val;
    }

    if (t.type === TOKEN.IDENT) {
      const name = String(t.value);
      const upper = name.toUpperCase();

      if (upper === 'TRUE') { this.advance(); return true; }
      if (upper === 'FALSE') { this.advance(); return false; }

      this.advance();
      if (this.peek().type === TOKEN.LPAREN) {
        return this.parseFunction(name);
      }

      const val = this.state[name];
      if (val !== undefined) {
        const num = parseFloat(String(val));
        return isNaN(num) ? (val as string) : num;
      }
      return 0;
    }

    throw new UnknownFormulaTokenError(
      `Unexpected token: ${JSON.stringify(t)}`,
      { token: t as unknown as Record<string, unknown> },
    );
  }

  parseFunction(name: string): EvalResult {
    this.expect(TOKEN.LPAREN);
    const args: EvalResult[] = [];
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
      case 'ceil':  return Math.ceil(args[0] as number);
      case 'floor': return Math.floor(args[0] as number);
      case 'round': return Math.round(args[0] as number);
      case 'max':   return Math.max(...(args as number[]));
      case 'min':   return Math.min(...(args as number[]));
      case 'abs':   return Math.abs(args[0] as number);
      case 'if':    return args[0] ? args[1] : args[2];
      default:
        console.warn(`[formulaEngine] Unknown function: ${name}`);
        return 0;
    }
  }
}

// ─── Public API ─────────────────────────────────────────────────────────────

/**
 * Strict variant — parses the formula and propagates any
 * UnknownFormulaTokenError to the caller. Used by tests + by callers that
 * want to fail loud on a malformed expression instead of silently falling
 * back to a default quantity.
 */
export function parseFormulaStrict(formula: string, state: State): EvalResult {
  const tokens = tokenize(formula);
  const parser = new Parser(tokens, state);
  return parser.parse();
}

/**
 * Evaluate a quantity formula against project state.
 * Returns a number, or null if the formula fails.
 */
export function evaluateFormula(formula: string | null | undefined, state: State): number | null {
  if (!formula || typeof formula !== 'string') return null;
  try {
    const tokens = tokenize(formula);
    const parser = new Parser(tokens, state);
    const result = parser.parse();
    if (typeof result !== 'number' || isNaN(result) || !isFinite(result)) return null;
    return result;
  } catch (e) {
    console.warn(`[formulaEngine] Formula error: "${formula}" →`, (e as Error).message);
    return null;
  }
}

/**
 * Evaluate a condition trigger against project state.
 * Returns true (item included) or false (item excluded).
 * Special case: "always" → true.
 */
export function evaluateCondition(condition: string | null | undefined, state: State): boolean {
  if (!condition || condition === 'always') return true;
  try {
    const tokens = tokenize(condition);
    const parser = new Parser(tokens, state);
    const result = parser.parse();
    return !!result;
  } catch (e) {
    console.warn(`[formulaEngine] Condition error: "${condition}" →`, (e as Error).message);
    return false;
  }
}
