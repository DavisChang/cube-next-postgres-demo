require("dotenv").config();
const CubejsServer = require("@cubejs-backend/server");

async function main() {
  const server = new CubejsServer();
  const { version, port } = await server.listen();
  console.log(`🚀 Cube ${version} is listening on http://localhost:${port}`);
  console.log(`    Ready check: http://localhost:${port}/cubejs-api/v1/ready`);
}
main().catch((e) => {
  console.error("Cube failed to start:", e);
  process.exit(1);
});
