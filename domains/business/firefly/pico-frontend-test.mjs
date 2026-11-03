import assert from 'node:assert/strict'
import { evalMath, sanitizeAmount } from './utils/MathUtils.js'
for (const [expression, value] of [['1+2*3',7],['(2+3)*4',20],['-2+3',1],['1 2',3],['1.25+2.5',3.75]]) {
  assert.equal(evalMath(expression).value, value)
}
assert.equal(evalMath('').value, null)
assert.equal(sanitizeAmount('12,5x'), '12.5')
for (const expression of ['constructor', '__proto__', 'constructor.constructor("return process")()', 'x=1', 'foo(1)']) {
  assert.equal(evalMath(expression).wasSuccessful, false, expression)
}
console.log('calculator arithmetic and hostile-expression tests passed')
