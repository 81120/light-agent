const crypto = require("crypto");

function main() {
  if (process.argv.length < 3) {
    console.log("Usage: node greet.js <name>");
    return;
  }

  const name = process.argv[2];
  console.log(`[${crypto.randomUUID()}] Hello, ${name}!`);
}

main();
