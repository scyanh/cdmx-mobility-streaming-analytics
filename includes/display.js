// Colonia names come title-cased from the source, which turns roman numerals into "Ii", "Iv".
function colonia(column) {
  let expr = column;
  for (const [from, to] of [["Iii", "III"], ["Ii", "II"], ["Iv", "IV"], ["Vi", "VI"]]) {
    expr = `REGEXP_REPLACE(${expr}, r' ${from}\\b', ' ${to}')`;
  }
  return expr;
}

module.exports = { colonia };
