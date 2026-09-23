.pragma library

// Live FX via open.er-api.com (no API key).
// Note: Frankfurter/ECB omits KES and UGX, which this widget defaults to.
var FX_CURRENCIES = ["USD", "EUR", "GBP", "KES", "UGX", "ZAR", "INR", "JPY", "CAD", "AUD", "CHF", "CNY"]

function fxUrl(base) {
  return "https://open.er-api.com/v6/latest/" + encodeURIComponent(base || "USD")
}

function parseFxResponse(raw, requestedBase) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || (data.result && data.result !== "success") || !data.rates)
      return { error: "Bad FX response" }
    return {
      base: data.base_code || data.base || requestedBase || "USD",
      rates: data.rates,
      updatedAt: data.time_last_update_utc || data.date || new Date().toISOString(),
      fetchedAt: Date.now()
    }
  } catch (e) {
    return { error: "Parse error" }
  }
}

function convertCurrency(amount, from, to, rates, base) {
  var a = Number(amount)
  if (!isFinite(a)) return { error: "Invalid amount" }
  from = String(from || "").toUpperCase()
  to = String(to || "").toUpperCase()
  base = String(base || "USD").toUpperCase()
  rates = rates || {}

  function rateToBase(code) {
    if (code === base) return 1
    if (rates[code] === undefined) return null
    return Number(rates[code])
  }

  var rf = rateToBase(from)
  var rt = rateToBase(to)
  if (rf === null || rt === null) return { error: "Missing rate" }
  // amount in base = amount / rf (if rates are "1 base = rf foreign"? open.er-api: rates are 1 base = N currency)
  // So amount_from * (1/rf) * rt? Wait: rates[code] = how many of code per 1 base.
  // amount in base units = amount / rates[from] when from != base, else amount
  // result = amountInBase * rates[to]
  var inBase = from === base ? a : a / rf
  var result = to === base ? inBase : inBase * rt
  return { value: result }
}

function formatRate(n) {
  if (!isFinite(n)) return "—"
  var abs = Math.abs(n)
  if (abs >= 1000) return n.toFixed(2)
  if (abs >= 1) return n.toFixed(4)
  if (abs >= 0.01) return n.toFixed(6)
  return n.toPrecision(4)
}

function timeAgo(ms) {
  if (!ms) return "never"
  var sec = Math.floor((Date.now() - ms) / 1000)
  if (sec < 60) return "just now"
  if (sec < 3600) return Math.floor(sec / 60) + "m ago"
  if (sec < 86400) return Math.floor(sec / 3600) + "h ago"
  return Math.floor(sec / 86400) + "d ago"
}

// ---------- Units (all convert via SI base) ----------

var UNIT_CATEGORIES = {
  length: {
    label: "Length",
    base: "m",
    units: {
      m: 1, km: 1000, cm: 0.01, mm: 0.001, mi: 1609.344, yd: 0.9144, ft: 0.3048, in: 0.0254, nmi: 1852
    }
  },
  mass: {
    label: "Mass",
    base: "kg",
    units: {
      kg: 1, g: 0.001, mg: 0.000001, lb: 0.45359237, oz: 0.028349523125, t: 1000, st: 6.35029318
    }
  },
  temperature: {
    label: "Temperature",
    special: true,
    units: { C: "C", F: "F", K: "K" }
  },
  data: {
    label: "Data",
    base: "B",
    units: {
      B: 1, KB: 1000, MB: 1e6, GB: 1e9, TB: 1e12,
      KiB: 1024, MiB: 1048576, GiB: 1073741824, TiB: 1099511627776
    }
  },
  time: {
    label: "Time",
    base: "s",
    units: {
      s: 1, ms: 0.001, min: 60, h: 3600, d: 86400, wk: 604800
    }
  },
  area: {
    label: "Area",
    base: "m2",
    units: {
      m2: 1, km2: 1e6, ha: 10000, acre: 4046.8564224, ft2: 0.09290304, in2: 0.00064516
    }
  },
  volume: {
    label: "Volume",
    base: "L",
    units: {
      L: 1, mL: 0.001, m3: 1000, gal: 3.785411784, qt: 0.946352946, pt: 0.473176473, cup: 0.2365882365, floz: 0.0295735295625
    }
  },
  speed: {
    label: "Speed",
    base: "mps",
    units: {
      mps: 1, kph: 1 / 3.6, mph: 0.44704, kn: 0.514444, fps: 0.3048
    }
  }
}

function categoryList() {
  var keys = Object.keys(UNIT_CATEGORIES)
  var out = []
  for (var i = 0; i < keys.length; i++)
    out.push({ id: keys[i], label: UNIT_CATEGORIES[keys[i]].label })
  return out
}

function unitIds(category) {
  var cat = UNIT_CATEGORIES[category]
  if (!cat) return []
  return Object.keys(cat.units)
}

function tempToC(value, from) {
  var v = Number(value)
  if (from === "C") return v
  if (from === "F") return (v - 32) * 5 / 9
  if (from === "K") return v - 273.15
  return NaN
}

function tempFromC(value, to) {
  var v = Number(value)
  if (to === "C") return v
  if (to === "F") return v * 9 / 5 + 32
  if (to === "K") return v + 273.15
  return NaN
}

function convertUnit(amount, category, from, to) {
  var a = Number(amount)
  if (!isFinite(a)) return { error: "Invalid amount" }
  var cat = UNIT_CATEGORIES[category]
  if (!cat) return { error: "Unknown category" }
  if (cat.special) {
    var c = tempToC(a, from)
    if (!isFinite(c)) return { error: "Invalid unit" }
    var r = tempFromC(c, to)
    if (!isFinite(r)) return { error: "Invalid unit" }
    return { value: r }
  }
  var fu = cat.units[from]
  var tu = cat.units[to]
  if (fu === undefined || tu === undefined) return { error: "Unknown unit" }
  var base = a * fu
  return { value: base / tu }
}

// ---------- Tip / VAT ----------

function tipSplit(bill, tipPercent, people, vatPercent, vatMode) {
  var b = Number(bill)
  var tip = Number(tipPercent)
  var n = Math.max(1, Math.floor(Number(people) || 1))
  var vat = Number(vatPercent)
  if (!isFinite(b) || b < 0) return { error: "Invalid bill" }
  if (!isFinite(tip) || tip < 0) tip = 0
  if (!isFinite(vat) || vat < 0) vat = 0

  var net = b
  var vatAmount = 0
  if (vatMode === "add") {
    vatAmount = b * (vat / 100)
    net = b + vatAmount
  } else if (vatMode === "extract") {
    // b includes VAT
    vatAmount = b - (b / (1 + vat / 100))
    net = b // still tip on displayed bill
  }

  var tipBase = vatMode === "add" ? b : b
  var tipAmount = tipBase * (tip / 100)
  var total = (vatMode === "add" ? net : b) + tipAmount
  if (vatMode === "extract") {
    // tip on bill including VAT is common; total = bill + tip
    total = b + tipAmount
  }

  return {
    bill: b,
    vatAmount: vatAmount,
    tipAmount: tipAmount,
    total: total,
    perPerson: total / n,
    people: n,
    netBeforeTip: vatMode === "add" ? b : (vatMode === "extract" ? b - vatAmount : b)
  }
}

function defaultFxPairs() {
  return { from: "USD", to: "KES" }
}
