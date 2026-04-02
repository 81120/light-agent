const crypto = require("crypto");

function main() {
  if (process.argv.length !== 3) {
    console.error("请提供一个姓名作为参数");
    process.exit(1);
  }
  console.log(`${crypto.randomUUID()}，你好，${process.argv[2]}！见到你真高兴`);
}

main();
