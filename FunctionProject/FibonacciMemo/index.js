var bigInt = require("big-integer");

// Cache en memoria del proceso: vive mientras la instancia siga activa
const memo = new Map();
memo.set(0, bigInt.zero);
memo.set(1, bigInt.one);

function fib(n) {
    if (memo.has(n)) return memo.get(n);
    const result = fib(n - 1).add(fib(n - 2));
    memo.set(n, result);
    return result;
}

module.exports = async function (context, req) {
    const nth = req.body && req.body.nth;

    if (!Number.isInteger(nth) || nth < 0) {
        context.res = { status: 400, body: "nth debe ser un entero >= 0" };
        return;
    }

    const cacheHit = memo.has(nth);
    const inicio = Date.now();

    try {
        const answer = fib(nth).toString();
        context.res = {
            body: JSON.stringify({
                nth: nth,
                digitos: answer.length,
                inicioResultado: answer.substring(0, 20),
                cacheHit: cacheHit,
                tamanoCache: memo.size,
                ms: Date.now() - inicio,
                instancia: process.env.WEBSITE_INSTANCE_ID
            })
        };
    } catch (e) {
        context.res = { status: 500, body: "Error: " + e.message };
    }
};