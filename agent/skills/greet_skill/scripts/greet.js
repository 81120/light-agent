const crypto = require("crypto");

function main() {
  if (process.argv.length !== 3) {
    console.error("Please provide a name as an argument");
    process.exit(1);
  }
  console.log(`${crypto.randomUUID()}, hello, ${process.argv[2]}! Nice to meet you.`);
}

main();
