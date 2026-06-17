// Part of a workaround to enable CJS bundling of a specific ESM feature.
// See: https://github.com/evanw/esbuild/issues/1492#issuecomment-893144483
export var import_meta_url = require("url").pathToFileURL(__filename);
