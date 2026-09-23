.pragma library

function factorial(n) {
  if (n < 0 || !isFinite(n) || Math.floor(n) !== n) return NaN
  if (n > 170) return Infinity
  var r = 1
  for (var i = 2; i <= n; i++) r *= i
  return r
}

function toRadians(deg) { return deg * Math.PI / 180 }
function toDegrees(rad) { return rad * 180 / Math.PI }

function tokenize(expr) {
  var s = String(expr || "").replace(/\s+/g, "")
  var tokens = []
  var i = 0
  while (i < s.length) {
    var c = s[i]
    if ((c >= "0" && c <= "9") || c === ".") {
      var j = i + 1
      while (j < s.length && ((s[j] >= "0" && s[j] <= "9") || s[j] === ".")) j++
      if (j < s.length && (s[j] === "e" || s[j] === "E")) {
        var k = j + 1
        if (k < s.length && (s[k] === "+" || s[k] === "-")) k++
        while (k < s.length && s[k] >= "0" && s[k] <= "9") k++
        j = k
      }
      tokens.push({ type: "num", value: parseFloat(s.slice(i, j)) })
      i = j
      continue
    }
    if (c === "π" || (c === "p" && s.slice(i, i + 2) === "pi")) {
      tokens.push({ type: "num", value: Math.PI })
      i += (c === "π" ? 1 : 2)
      continue
    }
    if (c === "e" && (i + 1 >= s.length || !/[0-9a-zA-Z.]/.test(s[i + 1]))) {
      tokens.push({ type: "num", value: Math.E })
      i++
      continue
    }
    var funcs = ["asin", "acos", "atan", "sin", "cos", "tan", "log10", "log", "ln", "exp", "sqrt", "cbrt", "abs", "fact"]
    var matched = false
    for (var f = 0; f < funcs.length; f++) {
      var name = funcs[f]
      if (s.slice(i, i + name.length) === name) {
        tokens.push({ type: "func", value: name })
        i += name.length
        matched = true
        break
      }
    }
    if (matched) continue
    if ("+-*/^%()!".indexOf(c) !== -1) {
      // Unary minus / plus
      if ((c === "-" || c === "+") && (tokens.length === 0
          || tokens[tokens.length - 1].type === "op"
          || tokens[tokens.length - 1].type === "func"
          || (tokens[tokens.length - 1].type === "paren" && tokens[tokens.length - 1].value === "("))) {
        tokens.push({ type: "unary", value: c })
      } else if (c === "!") {
        tokens.push({ type: "postfix", value: "!" })
      } else if (c === "(" || c === ")") {
        tokens.push({ type: "paren", value: c })
      } else {
        tokens.push({ type: "op", value: c })
      }
      i++
      continue
    }
    return { error: "Unexpected character: " + c }
  }
  return { tokens: tokens }
}

function precedence(op) {
  if (op === "+" || op === "-") return 1
  if (op === "*" || op === "/" || op === "%") return 2
  if (op === "^") return 3
  if (op === "u+" || op === "u-") return 4
  return 0
}

function rightAssoc(op) {
  return op === "^" || op === "u+" || op === "u-"
}

function toRpn(tokens) {
  var output = []
  var stack = []
  for (var i = 0; i < tokens.length; i++) {
    var t = tokens[i]
    if (t.type === "num") {
      output.push(t)
    } else if (t.type === "func") {
      stack.push(t)
    } else if (t.type === "unary") {
      stack.push({ type: "op", value: "u" + t.value })
    } else if (t.type === "postfix") {
      output.push(t)
    } else if (t.type === "op") {
      while (stack.length > 0) {
        var top = stack[stack.length - 1]
        if (top.type !== "op") break
        var p1 = precedence(t.value)
        var p2 = precedence(top.value)
        if (p2 > p1 || (p2 === p1 && !rightAssoc(t.value))) stack.pop(), output.push(top)
        else break
      }
      stack.push(t)
    } else if (t.type === "paren" && t.value === "(") {
      stack.push(t)
    } else if (t.type === "paren" && t.value === ")") {
      var found = false
      while (stack.length > 0) {
        var s = stack.pop()
        if (s.type === "paren" && s.value === "(") { found = true; break }
        output.push(s)
      }
      if (!found) return { error: "Mismatched parentheses" }
      if (stack.length > 0 && stack[stack.length - 1].type === "func")
        output.push(stack.pop())
    }
  }
  while (stack.length > 0) {
    var rem = stack.pop()
    if (rem.type === "paren") return { error: "Mismatched parentheses" }
    output.push(rem)
  }
  return { rpn: output }
}

function applyFunc(name, x, angleMode) {
  var v = x
  if (["sin", "cos", "tan"].indexOf(name) !== -1 && angleMode === "deg")
    v = toRadians(x)
  switch (name) {
    case "sin": return Math.sin(v)
    case "cos": return Math.cos(v)
    case "tan": return Math.tan(v)
    case "asin": {
      var a = Math.asin(x)
      return angleMode === "deg" ? toDegrees(a) : a
    }
    case "acos": {
      var b = Math.acos(x)
      return angleMode === "deg" ? toDegrees(b) : b
    }
    case "atan": {
      var c = Math.atan(x)
      return angleMode === "deg" ? toDegrees(c) : c
    }
    case "ln": case "log": return Math.log(x)
    case "log10": return Math.log(x) / Math.LN10
    case "exp": return Math.exp(x)
    case "sqrt": return Math.sqrt(x)
    case "cbrt": return Math.cbrt ? Math.cbrt(x) : Math.pow(x, 1 / 3)
    case "abs": return Math.abs(x)
    case "fact": return factorial(x)
    default: return NaN
  }
}

function evalRpn(rpn, angleMode) {
  var stack = []
  for (var i = 0; i < rpn.length; i++) {
    var t = rpn[i]
    if (t.type === "num") {
      stack.push(t.value)
    } else if (t.type === "func") {
      if (stack.length < 1) return { error: "Missing argument" }
      stack.push(applyFunc(t.value, stack.pop(), angleMode || "deg"))
    } else if (t.type === "postfix" && t.value === "!") {
      if (stack.length < 1) return { error: "Missing argument" }
      stack.push(factorial(stack.pop()))
    } else if (t.type === "op") {
      if (t.value === "u-" || t.value === "u+") {
        if (stack.length < 1) return { error: "Missing operand" }
        var u = stack.pop()
        stack.push(t.value === "u-" ? -u : u)
        continue
      }
      if (stack.length < 2) return { error: "Missing operand" }
      var b = stack.pop()
      var a = stack.pop()
      var r = NaN
      switch (t.value) {
        case "+": r = a + b; break
        case "-": r = a - b; break
        case "*": r = a * b; break
        case "/": r = b === 0 ? NaN : a / b; break
        case "%": r = a * (b / 100); break
        case "^": r = Math.pow(a, b); break
      }
      stack.push(r)
    }
  }
  if (stack.length !== 1) return { error: "Invalid expression" }
  var result = stack[0]
  if (!isFinite(result)) return { error: "Overflow or undefined" }
  return { value: result }
}

function evaluate(expr, angleMode) {
  var cleaned = String(expr || "")
    .replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-")
    .replace(/√/g, "sqrt").replace(/∛/g, "cbrt")
  var tok = tokenize(cleaned)
  if (tok.error) return tok
  if (!tok.tokens || tok.tokens.length === 0) return { error: "Empty" }
  var rpn = toRpn(tok.tokens)
  if (rpn.error) return rpn
  return evalRpn(rpn.rpn, angleMode || "deg")
}

function formatNumber(n, maxDecimals) {
  if (n === null || n === undefined || !isFinite(n)) return "Error"
  var d = maxDecimals === undefined ? 12 : maxDecimals
  var s = Number(n).toPrecision(d)
  // Trim scientific if not needed; strip trailing zeros
  if (s.indexOf("e") !== -1 || s.indexOf("E") !== -1) {
    var abs = Math.abs(n)
    if (abs !== 0 && (abs >= 1e12 || abs < 1e-6)) return s.replace(/\.?0+e/, "e").replace(/e\+/, "e")
  }
  var num = Number(s)
  var out = String(num)
  if (out.indexOf("e") !== -1 || out.indexOf("E") !== -1) return out
  // Prefer fixed without trailing zeros for normal range
  if (Math.abs(num) < 1e12) {
    out = num.toFixed(Math.min(d, 10))
    out = out.replace(/\.?0+$/, "")
  }
  return out || "0"
}

function formatGrouped(n, useGrouping) {
  var s = formatNumber(n)
  if (!useGrouping || s === "Error" || s.indexOf("e") !== -1) return s
  var parts = s.split(".")
  var neg = parts[0][0] === "-"
  var intPart = neg ? parts[0].slice(1) : parts[0]
  intPart = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return (neg ? "-" : "") + intPart + (parts.length > 1 ? "." + parts[1] : "")
}

// ---------- Programmer helpers ----------

function maskBits(value, bits) {
  if (bits >= 64) {
    // JS safe integer path — clamp to signed 53-bit friendly unsigned wrap via BigInt-like
    var m = Math.pow(2, 32)
    var hi = Math.floor(value / m)
    var lo = value >>> 0
    // For 64 we approximate with Number; keep low 53 bits meaningfully
    return value
  }
  var mod = Math.pow(2, bits)
  var v = ((value % mod) + mod) % mod
  // Sign-extend for display of negative in DEC when high bit set? Keep unsigned for bases.
  return v
}

function toSigned(value, bits) {
  var mod = Math.pow(2, bits)
  var v = ((value % mod) + mod) % mod
  if (bits < 53 && v >= mod / 2) return v - mod
  return v
}

function formatBase(value, base, bits) {
  var v = maskBits(Math.trunc(value), bits || 32)
  if (base === 10) return String(toSigned(v, bits || 32))
  var unsigned = maskBits(Math.trunc(value), bits || 32)
  if (base === 16) return unsigned.toString(16).toUpperCase()
  if (base === 8) return unsigned.toString(8)
  if (base === 2) {
    var bin = unsigned.toString(2)
    var pad = bits || 32
    if (pad <= 32) while (bin.length < pad) bin = "0" + bin
    return bin
  }
  return String(unsigned)
}

function parseBase(text, base) {
  var s = String(text || "").trim().replace(/\s+/g, "")
  if (!s) return { error: "Empty" }
  var n = parseInt(s, base)
  if (isNaN(n)) return { error: "Invalid number" }
  return { value: n }
}

function bitwiseOp(op, a, b, bits) {
  var av = Math.trunc(a) >>> 0
  var bv = b === undefined ? 0 : (Math.trunc(b) >>> 0)
  var r = 0
  switch (op) {
    case "AND": r = av & bv; break
    case "OR": r = av | bv; break
    case "XOR": r = av ^ bv; break
    case "NOT": r = ~av; break
    case "LSH": r = av << (bv & 31); break
    case "RSH": r = av >>> (bv & 31); break
    default: return { error: "Unknown op" }
  }
  // Mask to word size
  if (bits && bits < 32) {
    var mod = Math.pow(2, bits)
    r = ((r % mod) + mod) % mod
  } else {
    r = r >>> 0
  }
  return { value: r }
}

function percentOf(a, b) {
  if (b === 0) return { error: "Division by zero" }
  return { value: (a / b) * 100 }
}

function percentChange(from, to) {
  if (from === 0) return { error: "Division by zero" }
  return { value: ((to - from) / Math.abs(from)) * 100 }
}

function pushHistory(history, entry, limit) {
  var list = (history || []).slice()
  list.unshift(entry)
  var max = limit || 50
  if (list.length > max) list = list.slice(0, max)
  return list
}
