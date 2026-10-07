const fs = require("fs");
const pkg = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const deps = pkg.dependencies || {};
const names = Object.keys(deps);

if (names.length === 0) {
  console.error("runtime-package.json に依存がありません。");
  process.exit(1);
}

for (const name of names) {
  if (deps[name] !== "latest") {
    console.error(`${name} は latest を参照してください。`);
    process.exit(1);
  }
  console.log(name);
}
