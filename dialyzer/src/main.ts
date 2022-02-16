/*
  - run Elixir via @core/exec to get the Elixir and OTP versions
  - hash mix.lock
  - restore the cache using OTP/Elixir/hash versions
  - run mix dialyzer --plt if the cache wasn't found
  - save the cache after building the PLT
  - run mix dialyzer $(INPUTS_CMD_LINE)
 */
import * as exec from "@actions/exec";
import * as core from "@actions/core";
import * as cache from "@actions/cache";
import * as glob from "@actions/glob";
import * as crypto from "crypto";
import * as fs from "fs";
import * as stream from "stream";
import * as util from "util";
import * as path from "path";

async function hashFiles(globPaths: string[]): Promise<string> {
  // borrowed from hashFiles implementation in GitHub Actions
  const globber = await glob.create(globPaths.join("\n"));
  const githubWorkspace = process.cwd();
  const result = crypto.createHash("sha256");
  for await (const file of globber.globGenerator()) {
    if (!file.startsWith(`${githubWorkspace}${path.sep}`)) {
      continue;
    }
    if (fs.statSync(file).isDirectory()) {
      continue;
    }
    const hash = crypto.createHash("sha256");
    const pipeline = util.promisify(stream.pipeline);
    await pipeline(fs.createReadStream(file), hash);
    result.write(hash.digest());
  }
  result.end();
  return result.digest("hex");
}

const elixirScript = `
map = %{
  architecture: IO.iodata_to_binary(:erlang.system_info(:system_architecture)),
  elixir_version: System.version(),
  otp_release: System.otp_release(),
  erts_version: IO.iodata_to_binary(:erlang.system_info(:version))
}
rough_json = map
|> Enum.map(fn {key, value} -> [?", Atom.to_string(key), '":', inspect(value)] end)
|> Enum.intersperse(?,)
IO.puts([?{, rough_json, ?}])
`;
async function elixirVersions(): Promise<{
  architecture: string;
  elixir_version: string;
  otp_release: string;
  erts_version: string;
}> {
  const tempDirectory: string = process.env["RUNNER_TEMP"] || "/tmp";
  const elixirScriptPath = `${tempDirectory}${path.sep}elixir_dialyzer_config.exs`;
  fs.writeFileSync(elixirScriptPath, elixirScript);
  let output = "";
  const options = {
    silent: true,
    listeners: {
      stdout: (data: Buffer) => {
        output += data.toString();
      },
    },
  };
  try {
    await exec.exec("elixir", ["-r", elixirScriptPath], options);
  } finally {
    fs.unlinkSync(elixirScriptPath);
  }
  const config = JSON.parse(output);
  return config;
}

async function mixDialyzer(args: string[]): Promise<number> {
  return exec.exec("mix", ["dialyzer", ...args]);
}

async function run(): Promise<void> {
  const workingDirectory = core.getInput("working-directory");
  process.chdir(workingDirectory);

  const {
    architecture,
    elixir_version,
    otp_release,
    erts_version,
  } = await elixirVersions();
  const mixLockHash = await hashFiles(["mix.lock", "apps/*/mix.lock"]);
  const dialyzerPaths = [" _build/*/*.plt*"];
  const cacheKey = `${architecture}-dialyzer-${otp_release}-${erts_version}-${elixir_version}-${mixLockHash}`;
  const restoreKeys = [
    `${architecture}-dialyzer-${otp_release}-${erts_version}-${elixir_version}-`,
    `${architecture}-dialyzer-${otp_release}-${erts_version}-`,
    // previous version of the Dialyzer cache
    `${architecture}-dialyzer-${otp_release}-${elixir_version}-`,
    `${architecture}-dialyzer-${otp_release}-`,
    `${architecture}-dialyzer-`,
  ];
  const cacheId = await cache.restoreCache(
    dialyzerPaths,
    cacheKey,
    restoreKeys
  );
  if (cacheId) {
    console.log("Restored cache:", cacheId);
  } else {
    console.log("Unable to restore cache:", cacheKey);
  }
  if (cacheId === cacheKey) {
    console.log("Cache hit, not building PLT.");
  } else {
    try {
      await mixDialyzer(["--plt"]);
      await cache.saveCache(dialyzerPaths, cacheKey);
      console.log("Saved cache:", cacheKey);
    } catch (e) {
      console.error("Unable to save cache:", e);
    }
  }
  await mixDialyzer(core.getInput("cmd-line").split(" "));
}

run().catch((e) => {
  console.error("Dialyzer failed", e);
  process.exit(1);
});
